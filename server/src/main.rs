use futures_util::{SinkExt, StreamExt};
use hound;
use serde::{Deserialize, Serialize};
use std::fs;
use std::net::SocketAddr;
use std::path::PathBuf;
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

#[derive(Debug, Deserialize)]
struct ClientMessage {
    #[serde(rename = "type")]
    msg_type: String,
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

const MODEL_KIND: ModelKind = ModelKind::ParakeetTDT;

// Alias para el sink compartido entre el loop principal y las tareas de transcripción
type WsSink = Arc<
    Mutex<futures_util::stream::SplitSink<tokio_tungstenite::WebSocketStream<TcpStream>, Message>>,
>;

async fn send_msg(write: &WsSink, msg: ServerMessage) {
    if let Ok(json) = serde_json::to_string(&msg) {
        let mut w = write.lock().await;
        let _ = w.send(Message::Text(json)).await;
    }
}

async fn save_audio(audio_buffer: &[f32]) {
    if audio_buffer.is_empty() {
        return;
    }
    let ts = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .unwrap()
        .as_millis();
    let filename = format!("records/{}.wav", ts);
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
        println!("💾 Audio guardado: {}", filename);
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
                println!("✅ Transcripción: '{}'", text);
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
                println!("⚠ Transcripción vacía");
            }
        }
        Err(e) => {
            eprintln!("❌ Error transcribiendo: {}", e);
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
) {
    println!("🔗 Cliente conectado: {}", addr);

    let ws_stream = match accept_async(stream).await {
        Ok(ws) => ws,
        Err(e) => {
            eprintln!("Error aceptando WebSocket: {}", e);
            return;
        }
    };

    let (write_half, mut read) = ws_stream.split();
    // Arc<Mutex<sink>> compartido entre el loop y las tareas de transcripción
    let write: WsSink = Arc::new(Mutex::new(write_half));

    let _ = fs::create_dir_all("records");
    let mut audio_buffer: Vec<f32> = Vec::new();

    loop {
        tokio::select! {
            msg = read.next() => {
                match msg {
                    // ── Mensajes de control (JSON) ────────────────────────
                    Some(Ok(Message::Text(text))) => {
                        let client_msg: ClientMessage = match serde_json::from_str(&text) {
                            Ok(m) => m,
                            Err(e) => {
                                send_msg(&write, ServerMessage {
                                    msg_type: "error".to_string(),
                                    text: None,
                                    message: Some(format!("JSON inválido: {}", e)),
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
                                save_audio(&audio_buffer).await;
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

                    // ── Audio binario (PCM int16 LE) ──────────────────────
                    Some(Ok(Message::Binary(data))) => {
                        // Decodificar PCM i16 → f32
                        let samples: Vec<f32> = data
                            .chunks_exact(2)
                            .map(|b| i16::from_le_bytes([b[0], b[1]]) as f32 / 32768.0)
                            .collect();

                        let duration_ms = samples.len() as f32 / 16.0; // /16000*1000
                        println!("📥 Chunk recibido: {:.0}ms ({} samples)", duration_ms, samples.len());

                        if duration_ms < 300.0 {
                            println!("⚠ Chunk muy corto ({:.0}ms), descartado", duration_ms);
                            continue;
                        }

                        // Acumular para el WAV de debug
                        audio_buffer.extend_from_slice(&samples);

                        // ── Transcripción en tarea separada ───────────────
                        // El loop de lectura NO se bloquea. Mientras el modelo
                        // procesa el chunk, seguimos recibiendo audio.
                        // El Semaphore(1) garantiza que solo una inferencia
                        // corre a la vez (evita OOM y resultados desordenados).
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

                    // ── Cierre limpio ─────────────────────────────────────
                    Some(Ok(Message::Close(_))) | None => {
                        println!("👋 Cliente desconectado: {}", addr);
                        save_audio(&audio_buffer).await;
                        break;
                    }
                    Some(Err(e)) => {
                        eprintln!("Error WebSocket ({}): {}", addr, e);
                        save_audio(&audio_buffer).await;
                        break;
                    }
                    _ => {}
                }
            }

            // ── Shutdown global (Ctrl+C) ──────────────────────────────────
            _ = shutdown.notified() => {
                println!("🛑 Shutdown: cerrando {}", addr);
                save_audio(&audio_buffer).await;
                let mut w = write.lock().await;
                let _ = w.close().await;
                break;
            }
        }
    }

    println!("👋 Conexión con {} finalizada", addr);
}

#[tokio::main]
async fn main() {
    let model: Arc<Mutex<Box<dyn SpeechModel + Send>>> = match MODEL_KIND {
        ModelKind::Canary180M => {
            println!("🚀 Cargando modelo Canary 180M Flash...");
            match CanaryModel::load(
                &PathBuf::from("models/canary-180m-flash-onnx"),
                &Quantization::Int8,
            ) {
                Ok(m) => Arc::new(Mutex::new(Box::new(m) as Box<dyn SpeechModel + Send>)),
                Err(e) => {
                    eprintln!("❌ Error cargando Canary: {}", e);
                    return;
                }
            }
        }
        ModelKind::ParakeetTDT => {
            println!("🚀 Cargando modelo Parakeet TDT 0.6b v3...");
            match ParakeetModel::load(
                &PathBuf::from("models/parakeet-tdt-0.6b-v3-onnx"),
                &Quantization::Int8,
            ) {
                Ok(m) => Arc::new(Mutex::new(Box::new(m) as Box<dyn SpeechModel + Send>)),
                Err(e) => {
                    eprintln!("❌ Error cargando Parakeet: {}", e);
                    return;
                }
            }
        }
    };

    println!("✅ Modelo cargado");

    // Un solo permiso = máximo 1 inferencia simultánea
    // Sube a 2 si el modelo lo soporta y tienes RAM suficiente
    let semaphore = Arc::new(Semaphore::new(1));

    let addr = "0.0.0.0:8765";
    let listener = match TcpListener::bind(addr).await {
        Ok(l) => l,
        Err(e) => {
            eprintln!("❌ Error binding: {}", e);
            return;
        }
    };

    println!("✅ Servidor listo en ws://{}", addr);

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
                        ));
                    }
                    Err(e) => {
                        eprintln!("❌ Error aceptando conexión: {}", e);
                        break;
                    }
                }
            }
            _ = tokio::signal::ctrl_c() => {
                println!("\n🛑 Ctrl+C recibido. Cerrando servidor...");
                shutdown.notify_waiters();
                tokio::time::sleep(std::time::Duration::from_millis(500)).await;
                println!("✅ Servidor detenido.");
                break;
            }
        }
    }
}
