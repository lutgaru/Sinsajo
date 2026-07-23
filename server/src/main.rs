use clap::Parser;
use futures_util::{SinkExt, StreamExt};
use hound;
use serde::{Deserialize, Serialize};
use std::fs;
use std::io::Write;
use std::net::SocketAddr;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::SystemTime;
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::{Mutex, Notify, Semaphore};
use tokio_tungstenite::accept_async;
use tokio_tungstenite::tungstenite::Message;
use transcribe_rs::onnx::canary::CanaryModel;
use transcribe_rs::onnx::parakeet::ParakeetModel;
use transcribe_rs::onnx::Quantization;
use transcribe_rs::SpeechModel;
use transcribe_rs::TranscribeOptions;

mod config;
mod model_downloader;

#[derive(Parser)]
#[command(name = "sinsajo-server", version, about = "Speech-to-text WebSocket server")]
struct Args {
    #[arg(long, num_args(0..=1), default_missing_value("ParakeetTDT"))]
    autodownload_models: Option<String>,

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

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ModelKind {
    Canary180M,
    ParakeetTDT,
}

// Shared sink alias for the main loop and transcription tasks
type WsSink = Arc<
    Mutex<futures_util::stream::SplitSink<tokio_tungstenite::WebSocketStream<TcpStream>, Message>>,
>;

async fn send_msg(write: &WsSink, msg: ServerMessage) {
    if let Ok(json) = serde_json::to_string(&msg) {
        let mut w = write.lock().await;
        let _ = w.send(Message::Text(json)).await;
    }
}

async fn save_audio(audio_buffer: &[f32], records_dir: &Path) {
    if audio_buffer.is_empty() {
        return;
    }
    let ts = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .unwrap()
        .as_millis();
    let filename = records_dir.join(format!("{}.wav", ts));
    let filename = filename.to_string_lossy().to_string();
    let spec = hound::WavSpec {
        channels: 1,
        sample_rate: 16000,
        bits_per_sample: 16,
        sample_format: hound::SampleFormat::Int,
    };
    if let Ok(mut writer) = hound::WavWriter::create(&filename, spec) {
        for &s in audio_buffer {
            let _ = writer.write_sample((s * 32768.0) as i16);
        }
        let _ = writer.finalize();
        println!("💾 Audio saved: {}", filename);
    }
}

async fn transcribe_and_send(
    samples: Vec<f32>,
    model: Arc<Mutex<Box<dyn SpeechModel + Send>>>,
    sem: Arc<Semaphore>,
    write: WsSink,
) {
    let _permit = match sem.acquire_owned().await {
        Ok(p) => p,
        Err(_) => return,
    };

    let mut lock = model.lock().await;
    match lock.transcribe(&samples, &TranscribeOptions {
        language: Some("en".to_string()),
        ..Default::default()
    }) {
        Ok(result) => {
            let text = result.text.trim().to_string();
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
    model: Arc<Mutex<Box<dyn SpeechModel + Send>>>,
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

    let _ = fs::create_dir_all(&records_dir);
    let mut audio_buffer: Vec<f32> = Vec::new();

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
                                save_audio(&audio_buffer, &records_dir).await;
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
                        tokio::spawn(transcribe_and_send(
                            samples,
                            model_clone,
                            sem_clone,
                            write_clone,
                        ));
                    }

                    // ── Clean close ───────────────────────────────────────
                    Some(Ok(Message::Close(_))) | None => {
                        println!("👋 Client disconnected: {}", addr);
                        save_audio(&audio_buffer, &records_dir).await;
                        break;
                    }
                    Some(Err(e)) => {
                        eprintln!("WebSocket error ({}): {}", addr, e);
                        save_audio(&audio_buffer, &records_dir).await;
                        break;
                    }
                    _ => {}
                }
            }

            // ── Shutdown global (Ctrl+C) ──────────────────────────────────
            _ = shutdown.notified() => {
                println!("🛑 Shutdown: closing {}", addr);
                save_audio(&audio_buffer, &records_dir).await;
                let mut w = write.lock().await;
                let _ = w.close().await;
                break;
            }
        }
    }

    println!("👋 Connection with {} closed", addr);
}

fn resolve_model_name(args: &Args) -> String {
    if let Some(name) = &args.autodownload_models {
        config::get_model_info(name);
        config::save_model(name);
        return name.clone();
    }

    if let Some(name) = config::load_model() {
        return name;
    }

    println!("Select a model:");
    for (i, m) in config::MODELS.iter().enumerate() {
        println!("  {}. {} ({})", i + 1, m.name, m.display);
    }
    print!("Choice [1]: ");
    std::io::stdout().flush().unwrap();
    let mut input = String::new();
    std::io::stdin().read_line(&mut input).unwrap();
    let idx = input.trim().parse::<usize>().unwrap_or(1).saturating_sub(1);
    let idx = idx.min(config::MODELS.len() - 1);
    let name = config::MODELS[idx].name.to_string();
    config::save_model(&name);
    name
}

#[tokio::main]
async fn main() {
    let args = Args::parse();

    let model_name = resolve_model_name(&args);
    let model_info = config::get_model_info(&model_name);
    let auto_download = args.autodownload_models.is_some();
    model_downloader::ensure_model(model_info, &args.model_dir, auto_download).await;

    let model_kind = match model_name.as_str() {
        "Canary180M" => ModelKind::Canary180M,
        _ => ModelKind::ParakeetTDT,
    };

    let model_path = args.model_dir.join(model_info.dir);

    let model: Arc<Mutex<Box<dyn SpeechModel + Send>>> = match model_kind {
        ModelKind::Canary180M => {
            println!("🚀 Loading Canary 180M Flash model...");
            match CanaryModel::load(&model_path, &Quantization::Int8) {
                Ok(m) => Arc::new(Mutex::new(Box::new(m) as Box<dyn SpeechModel + Send>)),
                Err(e) => {
                    eprintln!("❌ Error loading Canary: {}", e);
                    return;
                }
            }
        }
        ModelKind::ParakeetTDT => {
            println!("🚀 Loading Parakeet TDT 0.6b v3 model...");
            match ParakeetModel::load(&model_path, &Quantization::Int8) {
                Ok(m) => Arc::new(Mutex::new(Box::new(m) as Box<dyn SpeechModel + Send>)),
                Err(e) => {
                    eprintln!("❌ Error loading Parakeet: {}", e);
                    return;
                }
            }
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
