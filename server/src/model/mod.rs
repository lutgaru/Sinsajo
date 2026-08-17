use futures_util::StreamExt;
use indicatif::{ProgressBar, ProgressStyle};
use reqwest::Client;
use std::collections::HashSet;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};

mod canary;
mod parakeet;

// ── Model metadata types ───────────────────────────────────────────────────────

#[derive(Debug, Clone)]
pub struct ModelFile {
    pub repo: &'static str,
    pub path: &'static str,
}

pub struct ModelDefinition {
    pub name: &'static str,
    pub dir: &'static str,
    pub display: &'static str,
    pub files: &'static [ModelFile],
}

pub const MODELS: &[&ModelDefinition] = &[&canary::DEFINITION, &parakeet::DEFINITION];

pub fn get_model_info(name: &str) -> &'static ModelDefinition {
    MODELS.iter().find(|m| m.name == name).copied().unwrap_or_else(|| {
        eprintln!(
            "Unknown model '{}'. Valid models: {}",
            name,
            MODELS
                .iter()
                .map(|m| m.name)
                .collect::<Vec<_>>()
                .join(", ")
        );
        std::process::exit(1);
    })
}

// ── Model trait ────────────────────────────────────────────────────────────────

pub trait Model: Send {
    fn name(&self) -> &'static str;
    /// Transcribe `samples`, optionally targeting `target_language` as the output
    /// language. Models that support translation (Canary) will produce text in
    /// that language; single-language models (Parakeet, English-only) ignore it.
    fn transcribe(
        &mut self,
        samples: &[f32],
        target_language: Option<&str>,
    ) -> Result<String, Box<dyn std::error::Error + Send + Sync>>;
}

// ── Manifest helpers ───────────────────────────────────────────────────────────

const MANIFEST_FILE: &str = ".sinsajo_manifest.json";

fn load_manifest(dir: &Path) -> HashSet<String> {
    let path = dir.join(MANIFEST_FILE);
    if !path.exists() {
        return HashSet::new();
    }
    fs::read_to_string(path)
        .ok()
        .and_then(|s| serde_json::from_str::<Vec<String>>(&s).ok())
        .map(|v| v.into_iter().collect())
        .unwrap_or_default()
}

fn save_manifest(dir: &Path, files: &HashSet<String>) {
    let path = dir.join(MANIFEST_FILE);
    let list: Vec<&String> = files.iter().collect();
    if let Ok(json) = serde_json::to_string(&list) {
        let _ = fs::write(path, json);
    }
}

fn add_to_manifest(dir: &Path, manifest: &mut HashSet<String>, file: &str) {
    manifest.insert(file.to_string());
    save_manifest(dir, manifest);
}

// ── Public API ─────────────────────────────────────────────────────────────────

pub fn exists(definition: &ModelDefinition, model_dir: &Path) -> bool {
    let target_dir = model_dir.join(definition.dir);
    if !target_dir.exists() {
        return false;
    }
    let manifest = load_manifest(&target_dir);
    if manifest.is_empty() {
        return false;
    }
    definition.files.iter().all(|f| manifest.contains(f.path) && target_dir.join(f.path).exists())
}

pub fn verify(definition: &ModelDefinition, model_dir: &Path) -> Result<(), Vec<String>> {
    let target_dir = model_dir.join(definition.dir);
    let missing: Vec<String> = definition
        .files
        .iter()
        .filter(|f| !target_dir.join(f.path).exists())
        .map(|f| format!("  missing: {} ({})", f.path, f.repo))
        .collect();

    if missing.is_empty() {
        Ok(())
    } else {
        Err(missing)
    }
}

pub async fn download(definition: &ModelDefinition, model_dir: &Path, auto_download: bool) {
    let target_dir = PathBuf::from(model_dir).join(definition.dir);

    if exists(definition, model_dir) {
        println!("✓ Model '{}' found in '{}'", definition.display, definition.dir);
        return;
    }

    if auto_download {
        println!("📥 Model '{}' not found. Downloading...", definition.display);
    } else {
        println!("⚠ Model '{}' not found in '{}'", definition.display, definition.dir);
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

    fs::create_dir_all(&target_dir).expect("Failed to create model directory");

    let mut manifest = load_manifest(&target_dir);

    // legacy migration: no manifest yet but files exist on disk
    if manifest.is_empty() && target_dir.join("config.json").exists() {
        for file in definition.files {
            if target_dir.join(file.path).exists() {
                manifest.insert(file.path.to_string());
            }
        }
        if !manifest.is_empty() {
            save_manifest(&target_dir, &manifest);
        }
    }

    let client = Client::builder()
        .user_agent("sinsajo-server/0.1.0")
        .build()
        .expect("Failed to build HTTP client");

    for file in definition.files {
        // skip if already in manifest and exists on disk
        if manifest.contains(file.path) && target_dir.join(file.path).exists() {
            println!("  ✓ {}", file.path);
            continue;
        }

        let file_path = target_dir.join(file.path);
        if let Some(parent) = file_path.parent() {
            fs::create_dir_all(parent).expect("Failed to create parent directory");
        }

        let file_url = format!("https://huggingface.co/{}/resolve/main/{}", file.repo, file.path);
        println!("  📥 {}", file.path);

        if let Err(e) = download_file(&client, &file_url, &file_path).await {
            eprintln!("  ❌ Error downloading {}: {}", file.path, e);
            eprintln!("  Run again to resume download");
            std::process::exit(1);
        }

        add_to_manifest(&target_dir, &mut manifest, file.path);
    }

    println!("✅ Model '{}' downloaded successfully to '{}'", definition.display, definition.dir);
}

async fn download_file(client: &Client, url: &str, dest: &Path) -> Result<(), Box<dyn std::error::Error>> {
    let response = client.get(url).send().await?;
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
    fs::write(dest, &file_content)?;
    Ok(())
}

pub fn load_from_disk(name: &str, path: &Path) -> Result<Box<dyn Model>, Box<dyn std::error::Error + Send + Sync>> {
    match name {
        "Canary180M" => canary::load(path),
        "ParakeetTDT" => parakeet::load(path),
        _ => Err(format!("Unknown model '{}'", name).into()),
    }
}
