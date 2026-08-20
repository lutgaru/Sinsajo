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
use tokio::sync::{Mutex, Notify, Semaphore};
use tokio_tungstenite::accept_async;
use tokio_tungstenite::tungstenite::Message;
use vorbis_rs::VorbisEncoderBuilder;

mod config;
mod model;

#[derive(Parser)]
#[command(name = "sinsajo-server", version, about = "Speech-to-text WebSocket server")]
struct Args {
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
}

// BCP-47 language codes the transcription models accept as output language.
// Canary's vocabulary carries a prompt token for each of these; Parakeet is
// English-only and ignores the target language.
fn valid_target_language(s: &str) -> Option<String> {
    match s.to_ascii_lowercase().as_str() {
        "en" | "es" | "fr" | "de" | "pt" => Some(s.to_ascii_lowercase()),
        _ => None,
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
    model: Arc<Mutex<Box<dyn model::Model>>>,
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
    {
        let m = model.lock().await;
        let json = serde_json::json!({
            "type": "model_info",
            "model": m.name(),
            "languages": m.supported_languages(),
        });
        if let Ok(s) = serde_json::to_string(&json) {
            let mut w = write.lock().await;
            let _ = w.send(Message::Text(s)).await;
        }
    }

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
                                    session_target_language = valid_target_language(lang);
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
                        let model_clone = Arc::clone(&model);
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

    let model: Arc<Mutex<Box<dyn model::Model>>> = match model::load_from_disk(&model_name, &model_path) {
        Ok(m) => {
            println!("🚀 Loaded {} model", m.name());
            Arc::new(Mutex::new(m))
        }
        Err(e) => {
            eprintln!("❌ Error loading model: {}", e);
            return;
        }
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
                            Arc::clone(&model),
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
        for code in ["en", "es", "fr", "de", "pt"] {
            assert_eq!(valid_target_language(code), Some(code.to_string()));
        }
        // Case-insensitive
        assert_eq!(valid_target_language("ES"), Some("es".to_string()));
        assert_eq!(valid_target_language("Pt"), Some("pt".to_string()));
    }

    #[test]
    fn valid_target_language_rejects_unknown_codes() {
        assert_eq!(valid_target_language("xx"), None);
        assert_eq!(valid_target_language(""), None);
        assert_eq!(valid_target_language("english"), None);
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
