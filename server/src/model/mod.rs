use futures_util::StreamExt;
use indicatif::{ProgressBar, ProgressStyle};
use reqwest::Client;
use std::collections::HashSet;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::time::Duration;

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
    /// If `None`, `url` must be `Some` (direct download) or the file must be
    /// placed manually.
    pub repo: Option<&'static str>,
    /// Full direct URL for single-file downloads
    /// (GitHub releases, blob.handy.computer, …). Takes precedence when
    /// `repo` is `None`.
    pub url: Option<&'static str>,
    /// Remote filename inside `repo` when it differs from the local `path`
    /// (e.g. upstream ships `v3_e2e_ctc.int8.onnx` but transcribe-rs loads
    /// `model.int8.onnx`). `None` means the remote name equals `path`.
    pub remote: Option<&'static str>,
    /// Local destination path relative to the model dir.
    pub path: &'static str,
}

impl ModelFile {
    /// HuggingFace file whose remote and local names match.
    #[allow(dead_code)] // used behind feature gates / by some definitions
    pub const fn hf(repo: &'static str, path: &'static str) -> Self {
        Self {
            repo: Some(repo),
            url: None,
            remote: None,
            path,
        }
    }

    /// HuggingFace file downloaded from `remote` and saved as `path`
    /// (used when upstream filenames differ from what transcribe-rs loads).
    pub const fn hf_renamed(repo: &'static str, remote: &'static str, path: &'static str) -> Self {
        Self {
            repo: Some(repo),
            url: None,
            remote: Some(remote),
            path,
        }
    }

    /// Direct URL download saved as `path`.
    #[allow(dead_code)] // used behind feature gates
    pub const fn direct(url: &'static str, path: &'static str) -> Self {
        Self {
            repo: None,
            url: Some(url),
            remote: None,
            path,
        }
    }

    /// File with no remote source: the user must place it manually at `path`.
    #[allow(dead_code)]
    pub const fn manual(path: &'static str) -> Self {
        Self {
            repo: None,
            url: None,
            remote: None,
            path,
        }
    }

    /// Filename used in the remote repo (falls back to the local path).
    fn remote_name(&self) -> &str {
        self.remote.unwrap_or(self.path)
    }

    fn download_url(&self) -> Option<String> {
        if let Some(repo) = self.repo {
            Some(format!(
                "https://huggingface.co/{}/resolve/main/{}",
                repo,
                self.remote_name()
            ))
        } else if let Some(url) = self.url {
            Some(url.to_string())
        } else {
            // No remote source: file must be placed manually.
            None
        }
    }

    fn source_label(&self) -> String {
        if let Some(repo) = self.repo {
            if self.remote.is_some() {
                format!("hf:{repo} ({})", self.remote_name())
            } else {
                format!("hf:{repo}")
            }
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

/// Look up a model without terminating the process on failure.
///
/// Client-supplied names (model manager commands) must use this instead of
/// [`get_model_info`], which exits on unknown models for CLI convenience.
pub fn find(name: &str) -> Option<&'static ModelDefinition> {
    MODELS
        .iter()
        .find(|m| m.name == name)
        .or_else(|| MODELS.iter().find(|m| m.name.eq_ignore_ascii_case(name)))
        .copied()
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

/// Snapshot of an in-progress model install.
///
/// `downloaded`/`total` are aggregate byte counters for the whole model.
/// [`DownloadProgress::percent`] weights every file equally so clients can
/// render one section per file and the bar never moves backwards.
/// The per-file fields describe the file currently being fetched.
pub struct DownloadProgress<'a> {
    /// File currently being fetched.
    pub file: &'a str,
    /// Bytes downloaded for `file`.
    pub file_downloaded: u64,
    /// Expected size of `file` (0 when unknown).
    pub file_total: u64,
    /// Bytes downloaded across the whole model (completed files + current).
    pub downloaded: u64,
    /// Expected bytes for every file still to fetch (0 when unknown).
    pub total: u64,
    /// Files finished before the current file.
    pub files_done: usize,
    /// Files to fetch for this model (excludes already-installed files).
    pub files_total: usize,
    /// True for the final snapshot of the current file. Lets the aggregate
    /// percentage advance even when the file size is unknown.
    pub file_complete: bool,
}

impl DownloadProgress<'_> {
    /// Aggregate completion as an integer percentage (0..=100).
    ///
    /// Every file owns an equal slice of the bar. This keeps the bar monotonic
    /// even when file sizes differ wildly, and lets the client render one
    /// section per file.
    pub fn percent(&self) -> u64 {
        if self.files_total == 0 {
            return 0;
        }
        if self.files_done >= self.files_total {
            return 100;
        }
        let file_percent = if self.file_complete {
            100
        } else {
            self.file_downloaded
                .saturating_mul(100)
                .checked_div(self.file_total)
                .unwrap_or(0)
                .min(100)
        };
        let done = self.files_done.min(self.files_total) as u64;
        ((done * 100 + file_percent) / self.files_total as u64).min(100)
    }
}

/// Progress callback used by remote model-manager downloads.
pub type DownloadProgressFn<'a> = &'a (dyn Fn(DownloadProgress<'_>) + Send + Sync);

/// CLI entry point: downloads (or prompts) and exits with an error message on
/// failure. Remote model-manager downloads use [`download_with_progress`],
/// which never terminates the server process.
pub async fn download(definition: &ModelDefinition, model_dir: &Path, auto_download: bool) {
    if let Err(e) = download_inner(definition, model_dir, auto_download, None).await {
        eprintln!("❌ {}", e);
        std::process::exit(1);
    }
}

/// Installs a model without prompting or exiting the process, reporting
/// per-file progress so the client can display it.
pub async fn download_with_progress(
    definition: &ModelDefinition,
    model_dir: &Path,
    progress: DownloadProgressFn<'_>,
) -> Result<(), String> {
    download_inner(definition, model_dir, true, Some(progress)).await
}

async fn download_inner(
    definition: &ModelDefinition,
    model_dir: &Path,
    auto_download: bool,
    progress: Option<DownloadProgressFn<'_>>,
) -> Result<(), String> {
    let target_dir = model_dir.join(definition.dir);

    if exists(definition, model_dir) {
        println!("✓ Model '{}' found in '{}'", definition.display, definition.dir);
        return Ok(());
    }

    if auto_download {
        println!("📥 Model '{}' not found. Downloading...", definition.display);
    } else {
        println!("⚠ Model '{}' not found in '{}'", definition.display, definition.dir);
        print!("Download model automatically? (y/N): ");
        std::io::stdout().flush().map_err(|e| e.to_string())?;
        let mut input = String::new();
        std::io::stdin()
            .read_line(&mut input)
            .map_err(|e| e.to_string())?;
        if input.trim().to_lowercase() != "y" {
            return Err("Download cancelled.".to_string());
        }
        println!("📥 Downloading model...");
    }

    fs::create_dir_all(&target_dir)
        .map_err(|e| format!("Failed to create model directory: {e}"))?;

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
        .map_err(|e| format!("Failed to build HTTP client: {e}"))?;

    // Resolve every file that still has to be fetched before starting so the
    // client can show one progress bar for the whole model. HEAD requests give
    // the total size without downloading the bodies.
    let mut pending: Vec<(&ModelFile, String)> = Vec::new();
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
        match file.download_url() {
            Some(url) => pending.push((file, url)),
            None => {
                println!("  ⚠ {} has no remote source — place it manually", file.path);
            }
        }
    }

    // The CLI has its own per-file bar and does not need an aggregate total;
    // only the remote model manager asks for progress.
    let sizes = if progress.is_some() {
        futures_util::future::join_all(
            pending
                .iter()
                .map(|(_, url)| remote_size(&client, url.as_str())),
        )
        .await
    } else {
        vec![None; pending.len()]
    };
    let planned_total: u64 = sizes.iter().copied().flatten().sum();
    let files_total = pending.len();
    let mut completed_bytes = 0u64;

    // Announce the plan (file count and total size) before the first chunk so
    // the client can switch from an indeterminate to a determinate bar.
    if let (Some((file, _)), Some(expected_size)) = (pending.first(), sizes.first()) {
        if let Some(cb) = progress {
            cb(DownloadProgress {
                file: file.path,
                file_downloaded: 0,
                file_total: expected_size.unwrap_or(0),
                downloaded: 0,
                total: planned_total,
                files_done: 0,
                files_total,
                file_complete: false,
            });
        }
    }

    for (index, ((file, url), expected_size)) in pending.iter().zip(sizes).enumerate() {
        let file_path = target_dir.join(file.path);
        if let Some(parent) = file_path.parent() {
            fs::create_dir_all(parent)
                .map_err(|e| format!("Failed to create parent directory: {e}"))?;
        }
        println!("  📥 {}", file.path);

        let downloaded = download_file(
            &client,
            url,
            &file_path,
            file.path,
            expected_size.unwrap_or(0),
            completed_bytes,
            planned_total,
            index,
            files_total,
            progress,
        )
        .await
        .map_err(|e| {
            format!(
                "Error downloading {}: {e}. Run the download again to resume.",
                file.path
            )
        })?;

        completed_bytes = completed_bytes.saturating_add(downloaded);
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
            download_and_extract(&client, archive.url, &target_dir)
                .await
                .map_err(|e| format!("Error extracting archive: {e}"))?;
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
            return Err(format!(
                "{} file(s) have no remote source. Place them manually in '{}' and retry.",
                missing_count,
                target_dir.display()
            ));
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
    Ok(())
}

/// Best-effort size lookup used to build the aggregate download total before
/// the first byte is fetched. Never downloads a full body.
async fn remote_size(client: &Client, url: &str) -> Option<u64> {
    // HEAD is cheap and every current model host supports it. Some CDNs
    // answer without Content-Length, so fall back to a one-byte ranged GET
    // which reports the complete size in Content-Range.
    if let Ok(response) = client.head(url).timeout(Duration::from_secs(10)).send().await {
        if response.status().is_success() {
            if let Some(size) = response.content_length() {
                return Some(size);
            }
        }
    }

    let response = client
        .get(url)
        .header(reqwest::header::RANGE, "bytes=0-0")
        .timeout(Duration::from_secs(10))
        .send()
        .await
        .ok()?;
    if response.status() == reqwest::StatusCode::PARTIAL_CONTENT {
        let value = response
            .headers()
            .get(reqwest::header::CONTENT_RANGE)?
            .to_str()
            .ok()?;
        return value.rsplit('/').next()?.trim().parse().ok();
    }
    // Host ignored Range: it still told us the full size in Content-Length.
    response.content_length().filter(|size| *size > 0)
}

#[allow(clippy::too_many_arguments)]
async fn download_file(
    client: &Client,
    url: &str,
    dest: &Path,
    label: &str,
    expected_size: u64,
    completed_bytes: u64,
    planned_total: u64,
    files_done: usize,
    files_total: usize,
    progress: Option<DownloadProgressFn<'_>>,
) -> Result<u64, Box<dyn std::error::Error>> {
    let response = client.get(url).send().await?;
    if !response.status().is_success() {
        return Err(format!("HTTP {} for {}", response.status(), url).into());
    }
    let response_size = response.content_length().unwrap_or(0);
    let file_size = if response_size > 0 {
        response_size
    } else {
        expected_size
    };

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
    let mut downloaded = 0u64;
    let mut stream = response.bytes_stream();

    while let Some(chunk) = stream.next().await {
        let chunk = chunk?;
        file_content.extend_from_slice(&chunk);
        downloaded += chunk.len() as u64;
        pb.inc(chunk.len() as u64);
        if let Some(cb) = progress {
            cb(DownloadProgress {
                file: label,
                file_downloaded: downloaded,
                file_total: file_size,
                downloaded: completed_bytes.saturating_add(downloaded),
                total: planned_total,
                files_done,
                files_total,
                file_complete: false,
            });
        }
    }

    pb.finish_and_clear();
    fs::write(dest, &file_content)?;

    // Emit a final snapshot for this file. `files_done` is not incremented
    // here: it counts files finished *before* the current one, and the next
    // file's first snapshot will advance it. This keeps the aggregate
    // percentage monotonic.
    if let Some(cb) = progress {
        cb(DownloadProgress {
            file: label,
            file_downloaded: downloaded,
            file_total: file_size,
            downloaded: completed_bytes.saturating_add(downloaded),
            total: planned_total,
            files_done,
            files_total,
            file_complete: true,
        });
    }

    Ok(downloaded)
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
    fn find_is_optional_and_case_insensitive() {
        assert!(find("NoSuchModel").is_none());
        assert_eq!(find("Canary180M").map(|m| m.name), Some("Canary180M"));
        assert_eq!(find("canary180m").map(|m| m.name), Some("Canary180M"));
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

    // ── Download URL validation ───────────────────────────────────────────

    /// Every file must resolve to exactly one sane source, and local/remote
    /// names must be flat filenames so the manifest keys stay consistent.
    /// This catches typos such as a file listed on a repo that never had it
    /// (the `cohere-decoder.int8.onnx.data` 404).
    #[test]
    fn download_sources_are_well_formed() {
        let mut checked = 0usize;
        for def in MODELS {
            assert!(!def.files.is_empty(), "{} lists no files", def.name);
            for file in def.files {
                assert!(
                    file.repo.is_none() || file.url.is_none(),
                    "{}:{} declares both repo and url",
                    def.name,
                    file.path
                );
                assert!(
                    !file.path.is_empty() && !file.path.contains(['/', '\\']),
                    "{}: local path '{}' must be a bare filename",
                    def.name,
                    file.path
                );
                if let Some(remote) = file.remote {
                    assert!(
                        !remote.is_empty() && !remote.contains(['/', '\\']),
                        "{}: remote name '{remote}' must be a bare filename",
                        def.name
                    );
                }

                let Some(url) = file.download_url() else {
                    // No source: manual placement, nothing remote to check.
                    assert!(file.repo.is_none() && file.url.is_none());
                    continue;
                };
                checked += 1;

                assert!(url.starts_with("https://"), "{}: insecure url {url}", def.name);
                assert!(
                    !url["https://".len()..].contains("//") && !url.ends_with('/'),
                    "{}: malformed url {url}",
                    def.name
                );

                if let Some(repo) = file.repo {
                    assert!(
                        url.contains(&format!("/{repo}/resolve/main/")),
                        "{}: HF url {url} does not reference repo {repo}",
                        def.name
                    );
                    let remote = file.remote.unwrap_or(file.path);
                    assert!(
                        url.ends_with(&format!("/{remote}")),
                        "{}: HF url {url} should end with /{remote}",
                        def.name
                    );
                } else {
                    assert_eq!(Some(url.as_str()), file.url, "{}: url mismatch", def.name);
                }
            }
        }
        assert!(checked > 0, "no downloadable files found");
    }

    /// The model name is the CLI selector and the dir is the on-disk folder;
    /// both must be unique and folder-safe.
    #[test]
    fn model_names_and_dirs_are_unique() {
        let mut names = HashSet::new();
        let mut dirs = HashSet::new();
        for def in MODELS {
            assert!(!def.name.is_empty());
            assert!(names.insert(def.name), "duplicate model name {}", def.name);
            assert!(
                !def.dir.is_empty() && !def.dir.contains(['/', '\\']),
                "{}: dir '{}' must be a bare folder name",
                def.name,
                def.dir
            );
            assert!(dirs.insert(def.dir), "duplicate model dir {}", def.dir);
        }
    }

    /// Local paths within one model must be distinct (manifest keys on them).
    #[test]
    fn model_file_paths_are_unique() {
        for def in MODELS {
            let mut paths = HashSet::new();
            for file in def.files {
                assert!(
                    paths.insert(file.path),
                    "{}: duplicate file path {}",
                    def.name,
                    file.path
                );
            }
        }
    }

    /// HEAD (or a ranged GET when HEAD is unsupported) every download and
    /// archive URL, failing on any 4xx/5xx. Ignored by default because it
    /// needs network access: run with `cargo test -- --ignored`.
    #[tokio::test]
    #[ignore = "requires network access"]
    async fn all_remote_urls_resolve() {
        let client = Client::builder()
            .user_agent("sinsajo-server-tests/0.1.0")
            .build()
            .expect("build http client");

        let mut urls: Vec<(String, String)> = Vec::new();
        for def in MODELS {
            for file in def.files {
                if let Some(url) = file.download_url() {
                    urls.push((def.name.to_string(), url));
                }
            }
            for archive in def.archives {
                urls.push((def.name.to_string(), archive.url.to_string()));
            }
        }
        assert!(!urls.is_empty(), "no remote urls to check");

        let mut failures = Vec::new();
        for (name, url) in &urls {
            match probe(&client, url).await {
                Ok(status) if status.is_success() => {}
                Ok(status) => failures.push(format!("{name} -> {status} ({url})")),
                Err(e) => failures.push(format!("{name} -> {e} ({url})")),
            }
        }
        assert!(
            failures.is_empty(),
            "unreachable model URLs:\n{}",
            failures.join("\n")
        );
    }

    /// Some hosts reject HEAD; fall back to a one-byte ranged GET.
    async fn probe(client: &Client, url: &str) -> Result<reqwest::StatusCode, reqwest::Error> {
        let head = client.head(url).send().await?;
        if matches!(head.status().as_u16(), 405 | 501) {
            let get = client
                .get(url)
                .header(reqwest::header::RANGE, "bytes=0-0")
                .send()
                .await?;
            return Ok(get.status());
        }
        Ok(head.status())
    }

    #[test]
    fn aggregate_progress_gives_every_file_an_equal_section() {
        // Two files: the first one is half downloaded.
        let first = DownloadProgress {
            file: "encoder.onnx",
            file_downloaded: 50,
            file_total: 100,
            downloaded: 50,
            total: 200,
            files_done: 0,
            files_total: 2,
            file_complete: false,
        };
        assert_eq!(first.percent(), 25);

        // First file complete, second one half downloaded.
        let second = DownloadProgress {
            file: "decoder.onnx",
            file_downloaded: 50,
            file_total: 100,
            downloaded: 150,
            total: 200,
            files_done: 1,
            files_total: 2,
            file_complete: false,
        };
        assert_eq!(second.percent(), 75);
    }

    #[test]
    fn aggregate_progress_does_not_drop_between_files() {
        // Last snapshot of the first file and the first snapshot of the second
        // file must report the same percentage.
        let completed = DownloadProgress {
            file: "first.onnx",
            file_downloaded: 100,
            file_total: 100,
            downloaded: 100,
            total: 200,
            files_done: 0,
            files_total: 2,
            file_complete: true,
        };
        let next = DownloadProgress {
            file: "second.onnx",
            file_downloaded: 0,
            file_total: 100,
            downloaded: 100,
            total: 200,
            files_done: 1,
            files_total: 2,
            file_complete: false,
        };
        assert_eq!(completed.percent(), 50);
        assert_eq!(next.percent(), 50);
    }

    #[test]
    fn aggregate_progress_is_full_when_all_files_finish() {
        let progress = DownloadProgress {
            file: "decoder.onnx",
            file_downloaded: 50,
            file_total: 50,
            downloaded: 100,
            total: 100,
            files_done: 2,
            files_total: 2,
            file_complete: true,
        };
        assert_eq!(progress.percent(), 100);
    }

    #[test]
    fn aggregate_progress_handles_unknown_file_size() {
        // Unknown file size: the current section stays empty until the file
        // completes, but completed files still advance the bar.
        let progress = DownloadProgress {
            file: "encoder.onnx",
            file_downloaded: 50,
            file_total: 0,
            downloaded: 50,
            total: 0,
            files_done: 1,
            files_total: 4,
            file_complete: false,
        };
        assert_eq!(progress.percent(), 25);

        let completed = DownloadProgress {
            file: "encoder.onnx",
            file_downloaded: 50,
            file_total: 0,
            downloaded: 50,
            total: 0,
            files_done: 1,
            files_total: 4,
            file_complete: true,
        };
        assert_eq!(completed.percent(), 50);
    }
}
