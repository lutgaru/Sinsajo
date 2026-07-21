use futures_util::StreamExt;
use indicatif::{ProgressBar, ProgressStyle};
use reqwest::Client;
use serde::Deserialize;
use std::fs;
use std::io::Write;
use std::path::Path;

const MODEL_REPO: &str = "istupakov/parakeet-tdt-0.6b-v3-onnx";
const HF_API: &str = "https://huggingface.co/api/models";
const HF_RESOLVE: &str = "https://huggingface.co/istupakov/parakeet-tdt-0.6b-v3-onnx/resolve/main";
const MODEL_DIR: &str = "models/parakeet-tdt-0.6b-v3-onnx";

#[derive(Debug, Deserialize)]
struct ModelInfo {
    siblings: Vec<Sibling>,
}

#[derive(Debug, Deserialize)]
struct Sibling {
    rfilename: String,
}

pub fn model_exists() -> bool {
    Path::new(MODEL_DIR).join("config.json").exists()
}

pub async fn ensure_model(auto_download: bool) {
    if model_exists() {
        println!("✓ Model found in '{}'", MODEL_DIR);
        return;
    }

    if auto_download {
        println!("📥 Model not found. Downloading (--autodownload-models enabled)...");
    } else {
        println!("⚠ Model not found in '{}'", MODEL_DIR);
        print!("Download model automatically? (y/N): ");
        std::io::stdout().flush().unwrap();
        let mut input = String::new();
        std::io::stdin().read_line(&mut input).unwrap();
        if input.trim().to_lowercase() != "y" {
            eprintln!("❌ Download cancelled. Exiting.");
            std::process::exit(1);
        }
        println!("📥 Downloading model...");
    }

    if let Err(e) = download_model().await {
        eprintln!("❌ Error downloading model: {}", e);
        std::process::exit(1);
    }
    println!("✅ Model downloaded successfully to '{}'", MODEL_DIR);
}

async fn download_model() -> Result<(), Box<dyn std::error::Error>> {
    let client = Client::builder()
        .user_agent("sinsajo-server/0.1.0")
        .build()?;

    // Fetch file list from HuggingFace API
    let url = format!("{}/{}", HF_API, MODEL_REPO);
    let resp = client.get(&url).send().await?;
    let info: ModelInfo = resp.json().await?;

    let target_dir = Path::new(MODEL_DIR);
    fs::create_dir_all(target_dir)?;

    // Filter out .git files/dirs
    let rfilenames: Vec<&String> = info.siblings.iter()
        .filter(|s| !s.rfilename.starts_with(".git"))
        .map(|s| &s.rfilename)
        .collect();

    let total_count = rfilenames.len();

    for (i, name) in rfilenames.iter().enumerate() {
        let file_url = format!("{}/{}", HF_RESOLVE, name);
        let file_path = target_dir.join(name);

        if let Some(parent) = file_path.parent() {
            fs::create_dir_all(parent)?;
        }

        println!("[{}/{}] Downloading {}...", i + 1, total_count, name);

        let response = client.get(&file_url).send().await?;
        let file_size = response.content_length().unwrap_or(0);

        let pb = if file_size > 0 {
            let pb = ProgressBar::new(file_size);
            pb.set_style(
                ProgressStyle::default_bar()
                    .template("[{elapsed_precise}] [{bar:30.cyan/blue}] {bytes}/{total_bytes} ({eta})")
                    .unwrap()
                    .progress_chars("=>-"),
            );
            pb
        } else {
            let pb = ProgressBar::new_spinner();
            pb.set_style(
                ProgressStyle::default_spinner()
                    .template("{spinner} {bytes} downloaded")
                    .unwrap(),
            );
            pb
        };

        let mut file_content = Vec::new();
        let mut stream = response.bytes_stream();

        while let Some(chunk) = stream.next().await {
            let chunk = chunk?;
            file_content.extend_from_slice(&chunk);
            pb.inc(chunk.len() as u64);
        }

        pb.finish_and_clear();

        fs::write(&file_path, &file_content)?;
    }

    println!("✅ Download complete");
    Ok(())
}
