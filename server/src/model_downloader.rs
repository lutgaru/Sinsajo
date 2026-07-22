use crate::config::ModelDefinition;
use futures_util::StreamExt;
use indicatif::{ProgressBar, ProgressStyle};
use reqwest::Client;
use serde::Deserialize;
use std::fs;
use std::io::Write;
use std::path::Path;

const HF_API: &str = "https://huggingface.co/api/models";

#[derive(Debug, Deserialize)]
struct ModelInfo {
    siblings: Vec<Sibling>,
}

#[derive(Debug, Deserialize)]
struct Sibling {
    rfilename: String,
}

pub fn model_exists(model: &ModelDefinition) -> bool {
    Path::new(model.dir).join("config.json").exists()
}

pub async fn ensure_model(model: &ModelDefinition, auto_download: bool) {
    if model_exists(model) {
        println!("✓ Model '{}' found in '{}'", model.display, model.dir);
        return;
    }

    if auto_download {
        println!("📥 Model '{}' not found. Downloading...", model.display);
    } else {
        println!("⚠ Model '{}' not found in '{}'", model.display, model.dir);
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

    if let Err(e) = download_model(model).await {
        eprintln!("❌ Error downloading model: {}", e);
        std::process::exit(1);
    }
    println!("✅ Model '{}' downloaded successfully to '{}'", model.display, model.dir);
}

async fn download_model(model: &ModelDefinition) -> Result<(), Box<dyn std::error::Error>> {
    let client = Client::builder()
        .user_agent("sinsajo-server/0.1.0")
        .build()?;

    let url = format!("{}/{}", HF_API, model.repo);
    let resp = client.get(&url).send().await?;
    let info: ModelInfo = resp.json().await?;

    let target_dir = Path::new(model.dir);
    fs::create_dir_all(target_dir)?;

    let rfilenames: Vec<&String> = info
        .siblings
        .iter()
        .filter(|s| !s.rfilename.starts_with(".git"))
        .map(|s| &s.rfilename)
        .collect();

    let total_count = rfilenames.len();
    let resolve_base = format!("https://huggingface.co/{}/resolve/main", model.repo);

    for (i, name) in rfilenames.iter().enumerate() {
        let file_url = format!("{}/{}", resolve_base, name);
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

    for (extra_repo, extra_file) in model.extra_files {
        let file_path = target_dir.join(extra_file);
        if file_path.exists() {
            continue;
        }

        let file_url = format!("https://huggingface.co/{}/resolve/main/{}", extra_repo, extra_file);
        println!("Downloading shared dependency {}...", extra_file);

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

    Ok(())
}
