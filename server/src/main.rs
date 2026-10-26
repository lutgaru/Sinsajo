use clap::Parser;
use futures_util::{SinkExt, StreamExt};
use hound;
use serde::{Deserialize, Serialize};
use std::fs;
use std::io::Write;
use std::net::SocketAddr;
use std::num::{NonZeroU32, NonZeroU8};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::SystemTime;
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::{Mutex, Notify, RwLock, Semaphore};
use tokio_tungstenite::accept_async;
use tokio_tungstenite::tungstenite::Message;
use vorbis_rs::VorbisEncoderBuilder;

mod config;
mod model;

#[derive(Parser)]
#[command(name = "sinsajo-server", version, about = "Speech-to-text WebSocket server")]
struct Args {
    /// Model name (e.g. ParakeetTDT, Canary180M, Canary1BV2, CohereInt4,
    /// SenseVoice, GigaAM, MoonshineBase, WhisperSmall, WhisperfileSmall).
    /// An unknown name prints the flags compiled into this binary; Whisper*
    /// needs --features whisper-cpp and Whisperfile* --features whisperfile.
    #[arg(long)]
    model: Option<String>,

    #[arg(long)]
    autodownload_model: bool,

    #[arg(long, default_value = "8765")]
    port: u16,

    #[arg(long, default_value = "models")]
    model_dir: PathBuf,

    #[arg(long, default_value = "records")]
    records_dir: PathBuf,
}

#[derive(Debug, Deserialize)]
struct ClientMessage {
    #[serde(rename = "type")]
    msg_type: String,
    #[allow(dead_code)]
    sample_rate: Option<u32>,
    save_audio: Option<bool>,
    format: Option<String>,
    target_language: Option<String>,
    /// Model selected by model-manager commands.
    model: Option<String>,
}

// BCP-47 language codes accepted as output language.
// The global union (see `model::is_supported_language_code`) rejects typos;
// the loaded model's `supported_languages()` decides per-session.
fn valid_target_language(s: &str, supported: &[&str]) -> Option<String> {
    let lower = s.to_ascii_lowercase();
    if !model::is_supported_language_code(&lower) {
        return None;
    }
    if supported.iter().any(|l| l.eq_ignore_ascii_case(&lower)) {
        Some(lower)
    } else {
        None
    }
}

#[derive(Debug, Serialize, Clone)]
struct ServerMessage {
    #[serde(rename = "type")]
    msg_type: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    text: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    message: Option<String>,
}

// Shared sink alias for the main loop and transcription tasks
type WsSink = Arc<
    Mutex<futures_util::stream::SplitSink<tokio_tungstenite::WebSocketStream<TcpStream>, Message>>,
>;

// ── Audio save settings (session-scoped; supplied on connection start) ──────

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum AudioFormat {
    Wav,
    Ogg,
}

impl AudioFormat {
    fn from_str(s: &str) -> Option<AudioFormat> {
        match s.to_ascii_lowercase().as_str() {
            "wav" | "wave" => Some(AudioFormat::Wav),
            "ogg" | "vorbis" => Some(AudioFormat::Ogg),
            _ => None,
        }
    }

    fn ext(self) -> &'static str {
        match self {
            AudioFormat::Wav => "wav",
            AudioFormat::Ogg => "ogg",
        }
    }
}

#[derive(Debug, Clone, Copy)]
struct SaveSettings {
    enabled: bool,
    format: AudioFormat,
}

impl Default for SaveSettings {
    fn default() -> Self {
        SaveSettings {
            enabled: true,
            format: AudioFormat::Wav,
        }
    }
}

// ── Runtime model management ─────────────────────────────────────────────────

/// The model currently installed in memory. Model-manager commands can swap
/// this at runtime without restarting the server.
struct ActiveModel {
    name: String,
    languages: Vec<String>,
    handle: Arc<Mutex<Box<dyn model::Model>>>,
}

/// State shared by every connection so any client can inspect and manage the
/// server's models. Filesystem/load operations are serialized by `action_lock`
/// to avoid two downloads or model swaps racing each other.
#[derive(Clone)]
struct ServerContext {
    active: Arc<RwLock<ActiveModel>>,
    model_dir: PathBuf,
    action_lock: Arc<Mutex<()>>,
}

async fn send_json(write: &WsSink, value: serde_json::Value) {
    if let Ok(json) = serde_json::to_string(&value) {
        let mut w = write.lock().await;
        let _ = w.send(Message::Text(json)).await;
    }
}

async fn send_model_action(
    write: &WsSink,
    action: &str,
    model: &str,
    state: &str,
    message: Option<String>,
) {
    send_json(
        write,
        serde_json::json!({
            "type": "model_action",
            "action": action,
            "model": model,
            "state": state,
            "message": message,
        }),
    )
    .await;
}

async fn send_model_info(write: &WsSink, ctx: &ServerContext) {
    let active = ctx.active.read().await;
    send_json(
        write,
        serde_json::json!({
            "type": "model_info",
            "model": &active.name,
            "languages": &active.languages,
        }),
    )
    .await;
}

async fn send_model_list(write: &WsSink, ctx: &ServerContext) {
    let active_name = ctx.active.read().await.name.clone();
    let models: Vec<serde_json::Value> = model::MODELS
        .iter()
        .map(|def| {
            serde_json::json!({
                "name": def.name,
                "display": def.display,
                "dir": def.dir,
                "installed": model::exists(def, &ctx.model_dir),
                "active": def.name == active_name.as_str(),
                "files": def.files.len(),
            })
        })
        .collect();

    send_json(
        write,
        serde_json::json!({
            "type": "model_list",
            "active": active_name,
            "models": models,
        }),
    )
    .await;
}

async fn reject_unknown_model(write: &WsSink, action: &str, name: &str) {
    send_model_action(
        write,
        action,
        name,
        "failed",
        Some(format!("Unknown model '{}'", name)),
    )
    .await;
}

fn spawn_model_download(write: WsSink, ctx: ServerContext, name: String) {
    tokio::spawn(async move {
        let Some(def) = model::find(&name) else {
            reject_unknown_model(&write, "download", &name).await;
            return;
        };

        // One model operation at a time: a download may take minutes and we
        // must not delete or swap a model while it is being written.
        let _guard = ctx.action_lock.lock().await;

        if model::exists(def, &ctx.model_dir) {
            send_model_action(
                &write,
                "download",
                def.name,
                "completed",
                Some("Model is already installed".to_string()),
            )
            .await;
            send_model_list(&write, &ctx).await;
            return;
        }

        send_model_action(&write, "download", def.name, "started", None).await;

        // Preserve event ordering and avoid spawning one task per chunk:
        // the download callback pushes into this channel and a single task
        // forwards the messages to the client.
        let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel::<serde_json::Value>();
        let progress_write = write.clone();
        let forwarder = tokio::spawn(async move {
            while let Some(value) = rx.recv().await {
                send_json(&progress_write, value).await;
            }
        });

        let model_name = def.name.to_string();
        // (percent, bytes) last reported per file. Known-length files report
        // every 5%; unknown-length files report every ~2 MiB.
        let last_progress = Arc::new(std::sync::Mutex::new(
            std::collections::HashMap::<String, (u64, u64)>::new(),
        ));
        let tx_progress = tx.clone();
        let result =
            model::download_with_progress(def, &ctx.model_dir, &move |file, downloaded, total| {
                let percent = if total > 0 {
                    downloaded.saturating_mul(100) / total
                } else {
                    0
                };
                let should_send = {
                    let mut seen = last_progress
                        .lock()
                        .unwrap_or_else(|poisoned| poisoned.into_inner());
                    let should_send = match seen.get(file).copied() {
                        None => true,
                        Some((previous_percent, previous_bytes)) => {
                            if total > 0 {
                                percent != previous_percent
                                    && (percent % 5 == 0 || downloaded == total)
                            } else {
                                downloaded.saturating_sub(previous_bytes) >= 2 * 1024 * 1024
                                    || downloaded == total
                            }
                        }
                    };
                    if should_send {
                        seen.insert(file.to_string(), (percent, downloaded));
                    }
                    should_send
                };
                if should_send {
                    let _ = tx_progress.send(serde_json::json!({
                        "type": "model_download_progress",
                        "model": &model_name,
                        "file": file,
                        "downloaded": downloaded,
                        "total": total,
                        "percent": percent,
                    }));
                }
            })
            .await;

        drop(tx);
        let _ = forwarder.await;

        match result {
            Ok(()) => {
                send_model_action(&write, "download", def.name, "completed", None).await;
            }
            Err(e) => {
                send_model_action(&write, "download", def.name, "failed", Some(e)).await;
            }
        }
        send_model_list(&write, &ctx).await;
    });
}

fn spawn_model_load(write: WsSink, ctx: ServerContext, name: String) {
    tokio::spawn(async move {
        let Some(def) = model::find(&name) else {
            reject_unknown_model(&write, "load", &name).await;
            return;
        };

        let _guard = ctx.action_lock.lock().await;

        if !model::exists(def, &ctx.model_dir) {
            send_model_action(
                &write,
                "load",
                def.name,
                "failed",
                Some("Model is not installed. Download it first.".to_string()),
            )
            .await;
            send_model_list(&write, &ctx).await;
            return;
        }

        send_model_action(&write, "load", def.name, "started", None).await;

        let model_name = def.name.to_string();
        let model_path = ctx.model_dir.join(def.dir);
        let loaded =
            tokio::task::spawn_blocking(move || model::load_from_disk(&model_name, &model_path))
                .await;

        match loaded {
            Ok(Ok(model)) => {
                let name = model.name().to_string();
                let languages: Vec<String> = model
                    .supported_languages()
                    .iter()
                    .map(|s| s.to_string())
                    .collect();
                let handle = Arc::new(Mutex::new(model));

                {
                    let mut active = ctx.active.write().await;
                    *active = ActiveModel {
                        name: name.clone(),
                        languages,
                        handle,
                    };
                }
                config::save_model(&name);
                println!("🚀 Active model switched to {}", name);

                send_model_info(&write, &ctx).await;
                send_model_action(&write, "load", &name, "completed", None).await;
            }
            Ok(Err(e)) => {
                send_model_action(
                    &write,
                    "load",
                    def.name,
                    "failed",
                    Some(format!("Error loading model: {e}")),
                )
                .await;
            }
            Err(e) => {
                send_model_action(
                    &write,
                    "load",
                    def.name,
                    "failed",
                    Some(format!("Model load task failed: {e}")),
                )
                .await;
            }
        }

        send_model_list(&write, &ctx).await;
    });
}

fn spawn_model_delete(write: WsSink, ctx: ServerContext, name: String) {
    tokio::spawn(async move {
        let Some(def) = model::find(&name) else {
            reject_unknown_model(&write, "delete", &name).await;
            return;
        };

        let _guard = ctx.action_lock.lock().await;

        let active_name = ctx.active.read().await.name.clone();
        if def.name == active_name.as_str() {
            send_model_action(
                &write,
                "delete",
                def.name,
                "failed",
                Some("Cannot delete the active model. Load another model first.".to_string()),
            )
            .await;
            return;
        }

        let dir = ctx.model_dir.join(def.dir);
        if !dir.exists() {
            send_model_action(
                &write,
                "delete",
                def.name,
                "completed",
                Some("Model is not installed".to_string()),
            )
            .await;
            send_model_list(&write, &ctx).await;
            return;
        }

        send_model_action(&write, "delete", def.name, "started", None).await;

        let removed = tokio::task::spawn_blocking(move || fs::remove_dir_all(&dir)).await;
        match removed {
            Ok(Ok(())) => {
                println!("🗑️ Model removed: {}", def.display);
                send_model_action(&write, "delete", def.name, "completed", None).await;
            }
            Ok(Err(e)) => {
                send_model_action(
                    &write,
                    "delete",
                    def.name,
                    "failed",
                    Some(format!("Could not delete model: {e}")),
                )
                .await;
            }
            Err(e) => {
                send_model_action(
                    &write,
                    "delete",
                    def.name,
                    "failed",
                    Some(format!("Delete task failed: {e}")),
                )
                .await;
            }
        }

        send_model_list(&write, &ctx).await;
    });
}

async fn send_msg(write: &WsSink, msg: ServerMessage) {
    if let Ok(json) = serde_json::to_string(&msg) {
        let mut w = write.lock().await;
        let _ = w.send(Message::Text(json)).await;
    }
}

async fn save_audio(audio_buffer: &[f32], records_dir: &Path, settings: &SaveSettings) {
    if !settings.enabled || audio_buffer.is_empty() {
        return;
    }
    let ts = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .unwrap()
        .as_millis();
    let filename = records_dir.join(format!("{}.{}", ts, settings.format.ext()));
    let filename = filename.to_string_lossy().to_string();

    let saved = match settings.format {
        AudioFormat::Wav => write_wav(&filename, audio_buffer),
        AudioFormat::Ogg => write_ogg(&filename, audio_buffer),
    };

    if saved {
        println!("💾 Audio saved: {}", filename);
    }
}

fn write_wav(filename: &str, audio_buffer: &[f32]) -> bool {
    let spec = hound::WavSpec {
        channels: 1,
        sample_rate: 16000,
        bits_per_sample: 16,
        sample_format: hound::SampleFormat::Int,
    };
    if let Ok(mut writer) = hound::WavWriter::create(filename, spec) {
        for &s in audio_buffer {
            let _ = writer.write_sample((s * 32768.0) as i16);
        }
        let _ = writer.finalize();
        return true;
    }
    false
}

fn write_ogg(filename: &str, audio_buffer: &[f32]) -> bool {
    let file = match fs::File::create(filename) {
        Ok(f) => f,
        Err(_) => return false,
    };

    let mut encoder = match VorbisEncoderBuilder::new(
        NonZeroU32::new(16000).unwrap(),
        NonZeroU8::new(1).unwrap(),
        file,
    )
    .and_then(|mut b| b.build())
    {
        Ok(e) => e,
        Err(_) => return false,
    };

    // Encode in Vorbis-friendly block sizes (window max is 8192 samples).
    for chunk in audio_buffer.chunks(8192) {
        if encoder.encode_audio_block([chunk]).is_err() {
            return false;
        }
    }

    encoder.finish().is_ok()
}

async fn transcribe_and_send(
    samples: Vec<f32>,
    model: Arc<Mutex<Box<dyn model::Model>>>,
    target_language: Option<String>,
    sem: Arc<Semaphore>,
    write: WsSink,
) {
    let _permit = match sem.acquire_owned().await {
        Ok(p) => p,
        Err(_) => return,
    };

    let mut lock = model.lock().await;
    match lock.transcribe(&samples, target_language.as_deref()) {
        Ok(text) => {
            if !text.is_empty() {
                println!("✅ Transcription: '{}'", text);
                send_msg(
                    &write,
                    ServerMessage {
                        msg_type: "transcription".to_string(),
                        text: Some(text),
                        message: None,
                    },
                )
                .await;
            } else {
                println!("⚠ Empty transcription");
            }
        }
        Err(e) => {
            eprintln!("❌ Error transcribing: {}", e);
            send_msg(
                &write,
                ServerMessage {
                    msg_type: "error".to_string(),
                    text: None,
                    message: Some(format!("Error: {}", e)),
                },
            )
            .await;
        }
    }
}

async fn handle_connection(
    stream: TcpStream,
    addr: SocketAddr,
    ctx: ServerContext,
    sem: Arc<Semaphore>,
    shutdown: Arc<Notify>,
    records_dir: PathBuf,
) {
    println!("🔗 Client connected: {}", addr);

    let ws_stream = match accept_async(stream).await {
        Ok(ws) => ws,
        Err(e) => {
            eprintln!("Error accepting WebSocket: {}", e);
            return;
        }
    };

    let (write_half, mut read) = ws_stream.split();
    // Arc<Mutex<sink>> shared between the main loop and transcription tasks
    let write: WsSink = Arc::new(Mutex::new(write_half));

    // Announce the loaded model and its supported languages so the client can
    // show it in the UI and enable only the language options that work.
    send_model_info(&write, &ctx).await;

    let _ = fs::create_dir_all(&records_dir);
    let mut audio_buffer: Vec<f32> = Vec::new();
    let mut save_settings = SaveSettings::default();
    let mut session_target_language: Option<String> = None;

    loop {
        tokio::select! {
            msg = read.next() => {
                match msg {
                    // ── Control messages (JSON) ───────────────────────────
                    Some(Ok(Message::Text(text))) => {
                        let client_msg: ClientMessage = match serde_json::from_str(&text) {
                            Ok(m) => m,
                            Err(e) => {
                                send_msg(&write, ServerMessage {
                                    msg_type: "error".to_string(),
                                    text: None,
                                    message: Some(format!("Invalid JSON: {}", e)),
                                }).await;
                                continue;
                            }
                        };

                        match client_msg.msg_type.as_str() {
                            "start" => {
                                // Audio save settings are session-scoped and
                                // supplied with the start message, not mutated
                                // globally through a separate settings call.
                                if let Some(enabled) = client_msg.save_audio {
                                    save_settings.enabled = enabled;
                                }
                                if let Some(f) = &client_msg.format {
                                    if let Some(fmt) = AudioFormat::from_str(f) {
                                        save_settings.format = fmt;
                                    }
                                }
                                if let Some(lang) = &client_msg.target_language {
                                    let supported = ctx.active.read().await.languages.clone();
                                    let supported_ref: Vec<&str> =
                                        supported.iter().map(|s| s.as_str()).collect();
                                    session_target_language =
                                        valid_target_language(lang, &supported_ref);
                                }
                                println!(
                                    "▶ Session started (save_audio={}, format={}, target_language={})",
                                    save_settings.enabled,
                                    save_settings.format.ext(),
                                    session_target_language.as_deref().unwrap_or("en"),
                                );
                                audio_buffer.clear();
                                send_msg(&write, ServerMessage {
                                    msg_type: "status".to_string(),
                                    text: None,
                                    message: Some("ready".to_string()),
                                }).await;
                            }
                            "stop" => {
                                send_msg(&write, ServerMessage {
                                    msg_type: "status".to_string(),
                                    text: None,
                                    message: Some("stopped".to_string()),
                                }).await;
                            }
                            "discard" => {
                                audio_buffer.clear();
                                send_msg(&write, ServerMessage {
                                    msg_type: "status".to_string(),
                                    text: None,
                                    message: Some("discarded".to_string()),
                                }).await;
                            }
                            "clean" => {
                                save_audio(&audio_buffer, &records_dir, &save_settings).await;
                                audio_buffer.clear();
                                send_msg(&write, ServerMessage {
                                    msg_type: "status".to_string(),
                                    text: None,
                                    message: Some("cleaned".to_string()),
                                }).await;
                            }

                            // ── Model manager ─────────────────────────────
                            "list_models" => {
                                send_model_list(&write, &ctx).await;
                            }
                            "download_model" => {
                                match client_msg.model {
                                    Some(name) => {
                                        spawn_model_download(Arc::clone(&write), ctx.clone(), name)
                                    }
                                    None => {
                                        send_model_action(
                                            &write,
                                            "download",
                                            "",
                                            "failed",
                                            Some("Missing model name".to_string()),
                                        )
                                        .await;
                                    }
                                }
                            }
                            "load_model" | "reload_model" => {
                                match client_msg.model {
                                    Some(name) => {
                                        spawn_model_load(Arc::clone(&write), ctx.clone(), name)
                                    }
                                    None => {
                                        send_model_action(
                                            &write,
                                            "load",
                                            "",
                                            "failed",
                                            Some("Missing model name".to_string()),
                                        )
                                        .await;
                                    }
                                }
                            }
                            "delete_model" => {
                                match client_msg.model {
                                    Some(name) => {
                                        spawn_model_delete(Arc::clone(&write), ctx.clone(), name)
                                    }
                                    None => {
                                        send_model_action(
                                            &write,
                                            "delete",
                                            "",
                                            "failed",
                                            Some("Missing model name".to_string()),
                                        )
                                        .await;
                                    }
                                }
                            }
                            _ => {}
                        }
                    }

                    // ── Binary audio (PCM int16 LE) ───────────────────────
                    Some(Ok(Message::Binary(data))) => {
                        // Decode PCM i16 → f32
                        let samples: Vec<f32> = data
                            .chunks_exact(2)
                            .map(|b| i16::from_le_bytes([b[0], b[1]]) as f32 / 32768.0)
                            .collect();

                        let duration_ms = samples.len() as f32 / 16.0; // /16000*1000
                        println!("📥 Chunk received: {:.0}ms ({} samples)", duration_ms, samples.len());

                        if duration_ms < 300.0 {
                            println!("⚠ Chunk too short ({:.0}ms), discarded", duration_ms);
                            continue;
                        }

                        // Accumulate for debug WAV
                        audio_buffer.extend_from_slice(&samples);

                        // ── Transcription in a separate task ──────────────
                        // The read loop does NOT block. While the model
                        // processes the chunk, we keep receiving audio.
                        // Semaphore(1) ensures only one inference runs
                        // at a time (avoids OOM and out-of-order results).
                        // Snapshot the active model handle: if the model is
                        // swapped while this chunk is in flight, it still
                        // completes with the model it started with.
                        let model_clone = ctx.active.read().await.handle.clone();
                        let sem_clone   = Arc::clone(&sem);
                        let write_clone = Arc::clone(&write);
                        let target_clone = session_target_language.clone();
                        tokio::spawn(transcribe_and_send(
                            samples,
                            model_clone,
                            target_clone,
                            sem_clone,
                            write_clone,
                        ));
                    }

                    // ── Clean close ───────────────────────────────────────
                    Some(Ok(Message::Close(_))) | None => {
                        println!("👋 Client disconnected: {}", addr);
                        save_audio(&audio_buffer, &records_dir, &save_settings).await;
                        break;
                    }
                    Some(Err(e)) => {
                        eprintln!("WebSocket error ({}): {}", addr, e);
                        save_audio(&audio_buffer, &records_dir, &save_settings).await;
                        break;
                    }
                    _ => {}
                }
            }

            // ── Shutdown global (Ctrl+C) ──────────────────────────────────
            _ = shutdown.notified() => {
                println!("🛑 Shutdown: closing {}", addr);
                save_audio(&audio_buffer, &records_dir, &save_settings).await;
                let mut w = write.lock().await;
                let _ = w.close().await;
                break;
            }
        }
    }

    println!("👋 Connection with {} closed", addr);
}

fn resolve_model_name(args: &Args) -> String {
    if let Some(name) = &args.model {
        model::get_model_info(name);
        config::save_model(name);
        return name.clone();
    }

    if let Some(name) = config::load_model() {
        return name;
    }

    println!("Select a model:");
    for (i, m) in model::MODELS.iter().enumerate() {
        println!("  {}. {} ({})", i + 1, m.name, m.display);
    }
    print!("Choice [1]: ");
    std::io::stdout().flush().unwrap();
    let mut input = String::new();
    std::io::stdin().read_line(&mut input).unwrap();
    let idx = input.trim().parse::<usize>().unwrap_or(1).saturating_sub(1);
    let idx = idx.min(model::MODELS.len() - 1);
    let name = model::MODELS[idx].name.to_string();
    config::save_model(&name);
    name
}

#[tokio::main]
async fn main() {
    let args = Args::parse();

    let model_name = resolve_model_name(&args);
    let model_info = model::get_model_info(&model_name);
    let auto_download = args.autodownload_model;
    model::download(model_info, &args.model_dir, auto_download).await;

    if let Err(missing) = model::verify(model_info, &args.model_dir) {
        eprintln!("❌ Model '{}' is incomplete:", model_info.display);
        for m in missing {
            eprintln!("{}", m);
        }
        eprintln!("Run again with --autodownload-model to re-download missing files");
        return;
    }

    let model_path = args.model_dir.join(model_info.dir);

    let model = match model::load_from_disk(&model_name, &model_path) {
        Ok(m) => {
            println!("🚀 Loaded {} model", m.name());
            m
        }
        Err(e) => {
            eprintln!("❌ Error loading model: {}", e);
            return;
        }
    };

    let active_name = model.name().to_string();
    let active_languages: Vec<String> = model
        .supported_languages()
        .iter()
        .map(|s| s.to_string())
        .collect();
    let ctx = ServerContext {
        active: Arc::new(RwLock::new(ActiveModel {
            name: active_name,
            languages: active_languages,
            handle: Arc::new(Mutex::new(model)),
        })),
        model_dir: args.model_dir.clone(),
        action_lock: Arc::new(Mutex::new(())),
    };

    println!("✅ Model loaded");

    // Single permit = max 1 concurrent inference
    // Bump to 2 if the model supports it and you have enough RAM
    let semaphore = Arc::new(Semaphore::new(1));

    let bind_addr = format!("0.0.0.0:{}", args.port);
    let listener = match TcpListener::bind(&bind_addr).await {
        Ok(l) => l,
        Err(e) => {
            eprintln!("❌ Error binding: {}", e);
            return;
        }
    };

    println!("✅ Server ready at ws://{}", bind_addr);

    let shutdown = Arc::new(Notify::new());

    loop {
        tokio::select! {
            result = listener.accept() => {
                match result {
                    Ok((stream, addr)) => {
                        tokio::spawn(handle_connection(
                            stream,
                            addr,
                            ctx.clone(),
                            Arc::clone(&semaphore),
                            Arc::clone(&shutdown),
                            args.records_dir.clone(),
                        ));
                    }
                    Err(e) => {
                        eprintln!("❌ Error accepting connection: {}", e);
                        break;
                    }
                }
            }
            _ = tokio::signal::ctrl_c() => {
                println!("\n🛑 Ctrl+C received. Shutting down server...");
                shutdown.notify_waiters();
                tokio::time::sleep(std::time::Duration::from_millis(500)).await;
                println!("✅ Server stopped.");
                break;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_samples() -> Vec<f32> {
        (0..16000)
            .map(|i| ((i as f32) / 16000.0 * std::f32::consts::PI * 2.0 * 440.0).sin() * 0.5)
            .collect()
    }

    #[test]
    fn write_wav_produces_valid_file() {
        let path = std::env::temp_dir().join("sinsajo_test.wav");
        let path = path.to_string_lossy().to_string();
        assert!(write_wav(&path, &test_samples()));
        let bytes = std::fs::read(&path).unwrap();
        assert!(bytes.starts_with(b"RIFF") && bytes.windows(4).any(|w| w == b"WAVE"));
        std::fs::remove_file(&path).ok();
    }

    #[test]
    fn write_ogg_produces_valid_file() {
        let path = std::env::temp_dir().join("sinsajo_test.ogg");
        let path = path.to_string_lossy().to_string();
        assert!(write_ogg(&path, &test_samples()));
        let bytes = std::fs::read(&path).unwrap();
        assert!(bytes.starts_with(b"OggS"));
        assert!(bytes.len() > 200);
        std::fs::remove_file(&path).ok();
    }

    #[test]
    fn valid_target_language_accepts_supported_codes() {
        // Canary Flash: en/de/es/fr (no pt — matches upstream FLASH_LANGUAGES).
        let flash = ["en", "de", "es", "fr"];
        for code in flash {
            assert_eq!(valid_target_language(code, &flash), Some(code.to_string()));
        }
        // Case-insensitive
        assert_eq!(valid_target_language("ES", &flash), Some("es".to_string()));
        // Model-scoped: pt is a known code but not a Flash language.
        assert_eq!(valid_target_language("pt", &flash), None);
        // Canary V2 supports pt.
        let v2 = ["en", "pt", "uk"];
        assert_eq!(valid_target_language("pt", &v2), Some("pt".to_string()));
    }

    #[test]
    fn valid_target_language_rejects_unknown_codes() {
        let flash = ["en", "de", "es", "fr"];
        assert_eq!(valid_target_language("xx", &flash), None);
        assert_eq!(valid_target_language("", &flash), None);
        assert_eq!(valid_target_language("english", &flash), None);
    }

    #[test]
    fn start_message_parses_target_language() {
        let msg: ClientMessage = serde_json::from_str(
            r#"{"type":"start","sample_rate":16000,"save_audio":true,"format":"wav","target_language":"es"}"#,
        )
        .unwrap();
        assert_eq!(msg.msg_type, "start");
        assert_eq!(msg.target_language.as_deref(), Some("es"));

        let msg: ClientMessage = serde_json::from_str(r#"{"type":"start"}"#).unwrap();
        assert_eq!(msg.msg_type, "start");
        assert_eq!(msg.target_language, None);
    }

    #[test]
    fn model_manager_messages_parse_model_name() {
        for action in [
            "download_model",
            "load_model",
            "reload_model",
            "delete_model",
        ] {
            let json = format!(r#"{{"type":"{action}","model":"Canary180M"}}"#);
            let msg: ClientMessage = serde_json::from_str(&json).unwrap();
            assert_eq!(msg.msg_type, action);
            assert_eq!(msg.model.as_deref(), Some("Canary180M"));
        }

        let msg: ClientMessage = serde_json::from_str(r#"{"type":"list_models"}"#).unwrap();
        assert_eq!(msg.msg_type, "list_models");
        assert_eq!(msg.model, None);
    }

    #[test]
    fn save_audio_respects_settings() {
        let dir = std::env::temp_dir().join("sinsajo_records_test");
        let _ = fs::create_dir_all(&dir);
        let before = fs::read_dir(&dir).unwrap().count();

        // disabled → nothing written
        let disabled = SaveSettings {
            enabled: false,
            format: AudioFormat::Wav,
        };
        // use a runtime block to stay synchronous with the async fn
        let rt = tokio::runtime::Runtime::new().unwrap();
        rt.block_on(save_audio(&test_samples(), &dir, &disabled));
        assert_eq!(fs::read_dir(&dir).unwrap().count(), before);

        // enabled + enabled formats produce files
        for fmt in [AudioFormat::Wav, AudioFormat::Ogg] {
            let settings = SaveSettings {
                enabled: true,
                format: fmt,
            };
            rt.block_on(save_audio(&test_samples(), &dir, &settings));
        }
        assert_eq!(fs::read_dir(&dir).unwrap().count(), before + 2);

        for entry in fs::read_dir(&dir).unwrap() {
            let _ = fs::remove_file(entry.unwrap().path());
        }
        fs::remove_dir(&dir).ok();
    }
}
