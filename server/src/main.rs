use futures_util::{SinkExt, StreamExt};
use hound;
use serde::{Deserialize, Serialize};
use std::fs;
use std::net::SocketAddr;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::SystemTime;
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::Mutex;
use tokio::sync::Notify;
use tokio_tungstenite::accept_async;
use tokio_tungstenite::tungstenite::Message;
use transcribe_rs::onnx::canary::{CanaryModel, CanaryParams};
use transcribe_rs::onnx::Quantization;

#[derive(Debug, Deserialize)]
struct ClientMessage {
    #[serde(rename = "type")]
    msg_type: String,
    sample_rate: Option<u32>,
}

#[derive(Debug, Serialize)]
struct ServerMessage {
    #[serde(rename = "type")]
    msg_type: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    text: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    message: Option<String>,
}

async fn save_audio(audio_buffer: &[f32]) {
    if audio_buffer.is_empty() {
        return;
    }
    let timestamp = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .unwrap()
        .as_millis();
    let filename = format!("records/{}.wav", timestamp);
    let spec = hound::WavSpec {
        channels: 1,
        sample_rate: 16000,
        bits_per_sample: 16,
        sample_format: hound::SampleFormat::Int,
    };
    if let Ok(mut writer) = hound::WavWriter::create(&filename, spec) {
        for &sample in audio_buffer {
            let sample_i16 = (sample * 32768.0) as i16;
            let _ = writer.write_sample(sample_i16);
        }
        let _ = writer.finalize();
        println!("💾 Audio guardado: {}", filename);
    }
}

async fn handle_connection(
    stream: TcpStream,
    addr: SocketAddr,
    model: Arc<Mutex<CanaryModel>>,
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

    let (mut write, mut read) = ws_stream.split();
    let write = Arc::new(Mutex::new(write));

    let _ = fs::create_dir_all("records");
    let mut audio_buffer: Vec<f32> = Vec::new();

    loop {
        tokio::select! {
            msg = read.next() => {
                match msg {
                    Some(Ok(Message::Text(text))) => {
                        let client_msg: ClientMessage = match serde_json::from_str(&text) {
                            Ok(m) => m,
                            Err(e) => {
                                let err_msg = ServerMessage {
                                    msg_type: "error".to_string(),
                                    text: None,
                                    message: Some(format!("JSON inválido: {}", e)),
                                };
                                let mut w = write.lock().await;
                                let _ = w
                                    .send(Message::Text(serde_json::to_string(&err_msg).unwrap()))
                                    .await;
                                continue;
                            }
                        };

                        match client_msg.msg_type.as_str() {
                            "start" => {
                                audio_buffer.clear();
                                let response = ServerMessage {
                                    msg_type: "status".to_string(),
                                    text: None,
                                    message: Some("ready".to_string()),
                                };
                                let mut w = write.lock().await;
                                let _ = w
                                    .send(Message::Text(serde_json::to_string(&response).unwrap()))
                                    .await;
                            }
                            "stop" => {
                                let response = ServerMessage {
                                    msg_type: "status".to_string(),
                                    text: None,
                                    message: Some("stopped".to_string()),
                                };
                                let mut w = write.lock().await;
                                let _ = w
                                    .send(Message::Text(serde_json::to_string(&response).unwrap()))
                                    .await;
                            }
                            "clean" => {
                                save_audio(&audio_buffer).await;
                                audio_buffer.clear();
                                let response = ServerMessage {
                                    msg_type: "status".to_string(),
                                    text: None,
                                    message: Some("cleaned".to_string()),
                                };
                                let mut w = write.lock().await;
                                let _ = w
                                    .send(Message::Text(serde_json::to_string(&response).unwrap()))
                                    .await;
                            }
                            _ => {}
                        }
                    }
                    Some(Ok(Message::Binary(data))) => {
                        // Convertir PCM 16-bit a i16
                        let mut samples_i16 = Vec::with_capacity(data.len() / 2);
                        for chunk in data.chunks_exact(2) {
                            let sample = i16::from_le_bytes([chunk[0], chunk[1]]);
                            samples_i16.push(sample);
                        }

                        // Convertir i16 a f32 normalizado
                        let samples: Vec<f32> = samples_i16
                            .iter()
                            .map(|&s| s as f32 / 32768.0)
                            .collect();

                        audio_buffer.extend_from_slice(&samples);

                        let duration_ms = samples.len() as f32 / 16000.0 * 1000.0;
                        println!("📥 Chunk recibido: {:.0}ms ({} samples)", duration_ms, samples.len());

                        // Validar duración mínima
                        if duration_ms < 300.0 {
                            println!("⚠ Chunk muy corto ({:.0}ms), descartado", duration_ms);
                            continue;
                        }

                        // Transcribir inmediatamente
                        let mut model_lock = model.lock().await;
                        match model_lock.transcribe_with(
                            &samples,
                            &CanaryParams {
                                language: Some("en".to_string()),
                                use_pnc: true,
                                use_itn: true,
                                ..Default::default()
                            },
                        ) {
                            Ok(result) => {
                                let text = result.text.trim();
                                if !text.is_empty() {
                                    println!("✅ Transcripción: '{}'", text);
                                    let response = ServerMessage {
                                        msg_type: "transcription".to_string(),
                                        text: Some(text.to_string()),
                                        message: None,
                                    };
                                    let mut w = write.lock().await;
                                    let _ = w
                                        .send(Message::Text(serde_json::to_string(&response).unwrap()))
                                        .await;
                                } else {
                                    println!("⚠ Transcripción vacía");
                                }
                            }
                            Err(e) => {
                                eprintln!("❌ Error transcribiendo: {}", e);
                                let response = ServerMessage {
                                    msg_type: "error".to_string(),
                                    text: None,
                                    message: Some(format!("Error: {}", e)),
                                };
                                let mut w = write.lock().await;
                                let _ = w
                                    .send(Message::Text(serde_json::to_string(&response).unwrap()))
                                    .await;
                            }
                        }
                    }
                    Some(Ok(Message::Close(_))) => {
                        println!("👋 Cliente desconectado: {}", addr);
                        save_audio(&audio_buffer).await;
                        break;
                    }
                    Some(Err(e)) => {
                        eprintln!("Error WebSocket ({}): {}", addr, e);
                        save_audio(&audio_buffer).await;
                        break;
                    }
                    None => {
                        println!("🔌 Stream cerrado: {}", addr);
                        save_audio(&audio_buffer).await;
                        break;
                    }
                    _ => {}
                }
            }
            _ = shutdown.notified() => {
                println!("🛑 Shutdown: guardando audio y cerrando conexión con {}", addr);
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
    println!("🚀 Cargando modelo Canary 180M Flash...");

    let model = match CanaryModel::load(
        &PathBuf::from("models/canary-180m-flash-onnx"),
        &Quantization::Int8,
    ) {
        Ok(m) => Arc::new(Mutex::new(m)),
        Err(e) => {
            eprintln!("❌ Error cargando modelo: {}", e);
            return;
        }
    };

    println!("✅ Modelo cargado");

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
                        let model_clone = Arc::clone(&model);
                        let shutdown_clone = Arc::clone(&shutdown);
                        tokio::spawn(async move {
                            handle_connection(stream, addr, model_clone, shutdown_clone).await;
                        });
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
                // Pequeña pausa para que los handlers terminen de guardar
                tokio::time::sleep(std::time::Duration::from_millis(500)).await;
                println!("✅ Servidor detenido.");
                break;
            }
        }
    }
}