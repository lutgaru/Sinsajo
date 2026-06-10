use futures_util::{SinkExt, StreamExt};
use serde::{Deserialize, Serialize};
use std::net::SocketAddr;
use std::path::PathBuf;
use std::sync::Arc;
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::Mutex;
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

async fn handle_connection(
    stream: TcpStream,
    addr: SocketAddr,
    model: Arc<Mutex<CanaryModel>>,
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

    while let Some(msg) = read.next().await {
        match msg {
            Ok(Message::Text(text)) => {
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
                    _ => {}
                }
            }
            Ok(Message::Binary(data)) => {
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
            Ok(Message::Close(_)) => {
                println!("👋 Cliente desconectado: {}", addr);
                break;
            }
            Err(e) => {
                eprintln!("Error WebSocket: {}", e);
                break;
            }
            _ => {}
        }
    }
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

    while let Ok((stream, addr)) = listener.accept().await {
        let model_clone = Arc::clone(&model);
        tokio::spawn(async move {
            handle_connection(stream, addr, model_clone).await;
        });
    }
}