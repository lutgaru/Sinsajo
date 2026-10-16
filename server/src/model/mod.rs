use futures_util::StreamExt;
use indicatif::{ProgressBar, ProgressStyle};
use reqwest::Client;
use std::collections::HashSet;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};

mod canary;
mod cohere;
mod gigaam;
mod moonshine;
mod parakeet;
mod sense_voice;
#[cfg(feature = "whisper-cpp")]
mod whisper;
#[cfg(feature = "whisperfile")]
mod whisperfile;

// ── Model metadata types ───────────────────────────────────────────────────────

#[derive(Debug, Clone)]
pub struct ModelFile {
    /// HuggingFace repo, e.g. "istupakov/canary-180m-flash-onnx".
    /// If `None`, `url` must be `Some` (direct download).
    pub repo: Option<&'static str>,
    /// Full direct URL for single-file downloads
    /// (GitHub releases, blob.handy.computer, …). Takes precedence when
    /// `repo` is `None`.
    pub url: Option<&'static str>,
    /// Destination path relative to the model dir.
    pub path: &'static str,
}

impl ModelFile {
    #[allow(dead_code)]
    pub const fn hf(repo: &'static str, path: &'static str) -> Self {
        Self {
            repo: Some(repo),
            url: None,
            path,
        }
    }

    #[allow(dead_code)]
    pub const fn direct(url: &'static str, path: &'static str) -> Self {
        Self {
            repo: None,
            url: Some(url),
            path,
        }
    }

    fn download_url(&self) -> Option<String> {
        if let Some(repo) = self.repo {
            Some(format!("https://huggingface.co/{}/resolve/main/{}", repo, self.path))
        } else if let Some(url) = self.url {
            Some(url.to_string())
        } else {
            // No remote source: file must be placed manually.
            None
        }
    }

    fn source_label(&self) -> String {
        if let Some(repo) = self.repo {
            format!("hf:{repo}")
        } else if let Some(url) = self.url {
            url.to_string()
        } else {
            "manual placement".to_string()
        }
    }
}

/// A `.tar.gz` archive that expands into the model dir.
/// Used for distributions that only publish tarballs
/// (e.g. blob.handy.computer Moonshine / SenseVoice builds).
pub struct ModelArchive {
    pub url: &'static str,
}

pub struct ModelDefinition {
    pub name: &'static str,
    pub dir: &'static str,
    pub display: &'static str,
    pub files: &'static [ModelFile],
    /// Optional tarball mirrors. The downloader tries single `files` first;
    /// archives are only fetched when files are still missing afterwards
    /// (or when `files` is empty).
    pub archives: &'static [ModelArchive],
    /// Set for binaries that need a Unix exec bit (whisperfile).
    /// Only read on Unix; kept on all platforms for a uniform registry.
    #[allow(dead_code)]
    pub executable: Option<&'static str>,
}

pub const MODELS: &[&ModelDefinition] = &[
    &canary::DEFINITION_180M,
    &canary::DEFINITION_1B_FLASH,
    &canary::DEFINITION_1B_V2,
    &parakeet::DEFINITION,
    &cohere::DEFINITION_INT4,
    &cohere::DEFINITION_INT8,
    &sense_voice::DEFINITION,
    &gigaam::DEFINITION,
    &moonshine::DEFINITION_TINY,
    &moonshine::DEFINITION_BASE,
    &moonshine::DEFINITION_BASE_ES,
    &moonshine::DEFINITION_TINY_AR,
    &moonshine::DEFINITION_TINY_ZH,
    &moonshine::DEFINITION_TINY_JA,
    &moonshine::DEFINITION_TINY_KO,
    &moonshine::DEFINITION_TINY_UK,
    &moonshine::DEFINITION_TINY_VI,
    &moonshine::DEFINITION_STREAMING_TINY_EN,
    #[cfg(feature = "whisper-cpp")]
    &whisper::DEFINITION_TINY_EN,
    #[cfg(feature = "whisper-cpp")]
    &whisper::DEFINITION_SMALL,
    #[cfg(feature = "whisperfile")]
    &whisperfile::DEFINITION_SMALL,
];

/// Models that exist but are compiled out of this binary because their
/// cargo feature was not enabled at build time: (model flag, feature).
/// Each list is empty when its feature IS enabled (the models are then in
/// `MODELS`), so the unknown-model error can point at the right rebuild.
#[cfg(not(feature = "whisper-cpp"))]
const GATED_WHISPER: &[(&str, &str)] = &[
    ("WhisperTinyEn", "whisper-cpp"),
    ("WhisperSmall", "whisper-cpp"),
];
#[cfg(feature = "whisper-cpp")]
const GATED_WHISPER: &[(&str, &str)] = &[];

#[cfg(not(feature = "whisperfile"))]
const GATED_WHISPERFILE: &[(&str, &str)] = &[("WhisperfileSmall", "whisperfile")];
#[cfg(feature = "whisperfile")]
const GATED_WHISPERFILE: &[(&str, &str)] = &[];

fn gated_feature_for(name: &str) -> Option<&'static str> {
    GATED_WHISPER
        .iter()
        .chain(GATED_WHISPERFILE.iter())
        .find(|(gated, _)| gated.eq_ignore_ascii_case(name))
        .map(|(_, feature)| *feature)
}

pub fn get_model_info(name: &str) -> &'static ModelDefinition {
    if let Some(def) = MODELS.iter().find(|m| m.name == name).copied() {
        return def;
    }
    if let Some(feature) = gated_feature_for(name) {
        eprintln!("Model '{name}' needs the '{feature}' cargo feature, which this binary was built without.");
        eprintln!("Rebuild with: cargo build --release --features {feature}");
        eprintln!("(Docker: docker build --build-arg FEATURES={feature} .)");
        std::process::exit(1);
    }
    // Case-insensitive suggestion for typos.
    if let Some(def) = MODELS
        .iter()
        .find(|m| m.name.eq_ignore_ascii_case(name))
        .copied()
    {
        eprintln!("Unknown model '{name}'. Did you mean '{}'?", def.name);
        std::process::exit(1);
    }
    eprintln!(
        "Unknown model '{}'. Valid models: {}",
        name,
        MODELS
            .iter()
            .map(|m| m.name)
            .collect::<Vec<_>>()
            .join(", ")
    );
    let gated: Vec<String> = GATED_WHISPER
        .iter()
        .chain(GATED_WHISPERFILE.iter())
        .map(|(gated, feature)| format!("{gated} (--features {feature})"))
        .collect();
    if !gated.is_empty() {
        eprintln!("Feature-gated (rebuild to enable): {}", gated.join(", "));
    }
    std::process::exit(1);
}

// ── Model trait ────────────────────────────────────────────────────────────────

pub trait Model: Send {
    fn name(&self) -> &'static str;

    /// Target languages this model can output, as BCP-47 codes
    /// (e.g. "en", "es"). The client uses this to enable/disable the
    /// language options it presents to the user.
    fn supported_languages(&self) -> &'static [&'static str];

    /// Transcribe `samples`, optionally targeting `target_language` as the output
    /// language. Models that support translation (Canary) will produce text in
    /// that language; single-language models ignore it or use it as a hint.
    /// The caller should only pass languages reported by `supported_languages`.
    fn transcribe(
        &mut self,
        samples: &[f32],
        target_language: Option<&str>,
    ) -> Result<String, Box<dyn std::error::Error + Send + Sync>>;
}

/// Languages accepted by `transcribe()` across backends, used to validate the
/// client-supplied `target_language` before it reaches a model.
/// Per-model filtering happens via `supported_languages()`.
pub fn is_supported_language_code(code: &str) -> bool {
    let code = code.to_ascii_lowercase();
    // Union of Whisper/Whisperfile 100 + Canary V2 25 + Cohere 14 +
    // SenseVoice 5 + GigaAM + Moonshine family. Kept as a match so an
    // unknown code is rejected rather than forwarded to a model.
    matches!(
        code.as_str(),
        "en" | "zh" | "de" | "es" | "ru" | "ko" | "fr" | "ja" | "pt" | "tr" | "pl" | "ca"
            | "nl" | "ar" | "sv" | "it" | "id" | "hi" | "fi" | "vi" | "he" | "uk" | "el"
            | "ms" | "cs" | "ro" | "da" | "hu" | "ta" | "no" | "th" | "ur" | "hr" | "bg"
            | "lt" | "la" | "mi" | "ml" | "cy" | "sk" | "te" | "fa" | "lv" | "bn" | "sr"
            | "az" | "sl" | "kn" | "et" | "mk" | "br" | "eu" | "is" | "hy" | "ne" | "mn"
            | "bs" | "kk" | "sq" | "sw" | "gl" | "mr" | "pa" | "si" | "km" | "sn" | "yo"
            | "so" | "af" | "oc" | "ka" | "be" | "tg" | "sd" | "gu" | "am" | "yi" | "lo"
            | "uz" | "fo" | "ht" | "ps" | "tk" | "nn" | "mt" | "sa" | "lb" | "my" | "bo"
            | "tl" | "mg" | "as" | "tt" | "haw" | "ln" | "ha" | "ba" | "jw" | "su" | "yue"
    )
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
    // Whisper single-file models: manifest may predate the executable flag;
    // fall back to plain file existence.
    if definition.files.is_empty() {
        return false;
    }
    let manifest = load_manifest(&target_dir);
    if manifest.is_empty() {
        // No manifest (manual download): accept if all files exist on disk.
        return definition
            .files
            .iter()
            .all(|f| target_dir.join(f.path).exists());
    }
    definition
        .files
        .iter()
        .all(|f| manifest.contains(f.path) && target_dir.join(f.path).exists())
}

pub fn verify(definition: &ModelDefinition, model_dir: &Path) -> Result<(), Vec<String>> {
    let target_dir = model_dir.join(definition.dir);
    let missing: Vec<String> = definition
        .files
        .iter()
        .filter(|f| !target_dir.join(f.path).exists())
        .map(|f| format!("  missing: {} ({})", f.path, f.source_label()))
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
    if manifest.is_empty() && target_dir.exists() {
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
        // skip silently re-usable manual downloads
        if target_dir.join(file.path).exists() {
            println!("  ✓ {} (present)", file.path);
            add_to_manifest(&target_dir, &mut manifest, file.path);
            continue;
        }

        let file_path = target_dir.join(file.path);
        if let Some(parent) = file_path.parent() {
            fs::create_dir_all(parent).expect("Failed to create parent directory");
        }

        let file_url = match file.download_url() {
            Some(u) => u,
            None => {
                println!("  ⚠ {} has no remote source — place it manually", file.path);
                continue;
            }
        };
        println!("  📥 {}", file.path);

        if let Err(e) = download_file(&client, &file_url, &file_path).await {
            eprintln!("  ❌ Error downloading {}: {}", file.path, e);
            eprintln!("  Run again to resume download");
            std::process::exit(1);
        }

        add_to_manifest(&target_dir, &mut manifest, file.path);
    }

    // Tarball fallback: some distributions (Moonshine / SenseVoice mirrors)
    // only publish `.tar.gz`. If files are still missing and the definition
    // lists an archive, fetch + extract it, then re-check.
    let has_missing = definition
        .files
        .iter()
        .any(|f| !target_dir.join(f.path).exists());
    if has_missing {
        if let Some(archive) = definition.archives.first() {
            println!("  📦 Fetching archive {}", archive.url);
            if let Err(e) = download_and_extract(&client, archive.url, &target_dir).await {
                eprintln!("  ❌ Error extracting archive: {}", e);
                std::process::exit(1);
            }
            for file in definition.files {
                if target_dir.join(file.path).exists() {
                    add_to_manifest(&target_dir, &mut manifest, file.path);
                }
            }
        } else {
            let missing_count = definition
                .files
                .iter()
                .filter(|f| !target_dir.join(f.path).exists())
                .count();
            eprintln!(
                "  ❌ {} file(s) have no remote source. Place them manually in '{}' and re-run.",
                missing_count,
                target_dir.display()
            );
            std::process::exit(1);
        }
    }

    #[cfg(unix)]
    if let Some(exe) = definition.executable {
        use std::os::unix::fs::PermissionsExt;
        let p = target_dir.join(exe);
        if p.exists() {
            let _ = fs::set_permissions(&p, fs::Permissions::from_mode(0o755));
        }
    }

    println!("✅ Model '{}' downloaded successfully to '{}'", definition.display, definition.dir);
}

async fn download_file(client: &Client, url: &str, dest: &Path) -> Result<(), Box<dyn std::error::Error>> {
    let response = client.get(url).send().await?;
    if !response.status().is_success() {
        return Err(format!("HTTP {} for {}", response.status(), url).into());
    }
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

async fn download_and_extract(
    client: &Client,
    url: &str,
    dest: &Path,
) -> Result<(), Box<dyn std::error::Error>> {
    let response = client.get(url).send().await?;
    if !response.status().is_success() {
        return Err(format!("HTTP {} for {}", response.status(), url).into());
    }
    let bytes = response.bytes().await?;
    let tar = flate2::read::GzDecoder::new(&bytes[..]);
    let mut archive = tar::Archive::new(tar);
    archive.unpack(dest)?;
    // Tarballs often wrap files in a single top-level dir
    // (e.g. `moonshine-base/encoder_model.onnx`). Hoist one level so the
    // expected layout (`dest/encoder_model.onnx`) holds.
    if let Ok(entries) = fs::read_dir(dest) {
        let subdirs: Vec<PathBuf> = entries
            .filter_map(|e| e.ok().map(|e| e.path()))
            .filter(|p| p.is_dir() && p.file_name().is_some())
            .collect();
        if subdirs.len() == 1 {
            let inner = &subdirs[0];
            let mut moved_any = false;
            if let Ok(inner_entries) = fs::read_dir(inner) {
                for entry in inner_entries.filter_map(|e| e.ok()) {
                    let to = dest.join(entry.file_name());
                    if !to.exists() {
                        let _ = fs::rename(entry.path(), &to);
                        moved_any = true;
                    }
                }
            }
            if moved_any {
                let _ = fs::remove_dir(inner);
            }
        }
    }
    Ok(())
}

pub fn load_from_disk(name: &str, path: &Path) -> Result<Box<dyn Model>, Box<dyn std::error::Error + Send + Sync>> {    match name {
        "Canary180M" | "Canary1BFlash" | "Canary1BV2" => canary::load(path, name),
        "ParakeetTDT" => parakeet::load(path),
        "CohereInt4" | "CohereInt8" => cohere::load(path, name),
        "SenseVoice" => sense_voice::load(path),
        "GigaAM" => gigaam::load(path),
        "MoonshineTiny" | "MoonshineBase" | "MoonshineBaseEs" | "MoonshineTinyAr"
        | "MoonshineTinyZh" | "MoonshineTinyJa" | "MoonshineTinyKo" | "MoonshineTinyUk"
        | "MoonshineTinyVi" => moonshine::load(path, name),
        "MoonshineStreamingTinyEn" => moonshine::load_streaming(path),
        #[cfg(feature = "whisper-cpp")]
        "WhisperTinyEn" | "WhisperSmall" => whisper::load(path, name),
        #[cfg(feature = "whisperfile")]
        "WhisperfileSmall" => whisperfile::load(path),
        _ => Err(format!("Unknown model '{}'", name).into()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn registry_lists_all_local_backends() {
        let names: Vec<&str> = MODELS.iter().map(|m| m.name).collect();
        for expected in [
            "Canary180M",
            "Canary1BFlash",
            "Canary1BV2",
            "ParakeetTDT",
            "CohereInt4",
            "CohereInt8",
            "SenseVoice",
            "GigaAM",
            "MoonshineTiny",
            "MoonshineBase",
            "MoonshineBaseEs",
            "MoonshineStreamingTinyEn",
        ] {
            assert!(names.contains(&expected), "missing model {expected}");
        }
    }

    #[test]
    fn gated_lookup_points_at_missing_features() {
        // Unknown names never match, regardless of features.
        assert_eq!(gated_feature_for("NoSuchModel"), None);
        // Lookup is case-insensitive, matching the error path.
        #[cfg(not(feature = "whisper-cpp"))]
        assert_eq!(gated_feature_for("whispersmall"), Some("whisper-cpp"));
        #[cfg(feature = "whisper-cpp")]
        assert_eq!(gated_feature_for("WhisperSmall"), None);
        #[cfg(not(feature = "whisperfile"))]
        assert_eq!(gated_feature_for("WhisperfileSmall"), Some("whisperfile"));
        #[cfg(feature = "whisperfile")]
        assert_eq!(gated_feature_for("WhisperfileSmall"), None);
    }

    #[test]
    fn language_union_covers_engine_spot_checks() {        for code in ["en", "es", "ru", "yue", "haw", "nn", "mt", "uk", "zh"] {
            assert!(is_supported_language_code(code), "{code} should be known");
        }
        assert!(is_supported_language_code("ES"));
        for code in ["xx", "", "english"] {
            assert!(!is_supported_language_code(code), "{code} should be rejected");
        }
    }
}
