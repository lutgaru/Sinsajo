//! Whisperfile backend (Mozilla llamafile server wrapper).
//! Enabled with `--features whisperfile`.
//!
//! The engine spawns the whisperfile binary as a local HTTP server on
//! startup and shuts it down on drop. Requires the whisperfile binary +
//! a GGML model in the model dir.

use crate::model::{Model, ModelDefinition, ModelFile};
use std::path::Path;
use transcribe_rs::whisperfile::{WhisperfileEngine, WhisperfileInferenceParams, WhisperfileLoadParams};

pub const DEFINITION_SMALL: ModelDefinition = ModelDefinition {
    name: "WhisperfileSmall",
    dir: "whisperfile-small",
    display: "Whisperfile Small (multilingual server)",
    files: &[
        ModelFile {
            repo: None,
            url: Some("https://github.com/mozilla-ai/llamafile/releases/download/0.9.3/whisperfile-0.9.3"),
            path: "whisperfile-0.9.3",
        },
        ModelFile {
            repo: Some("ggerganov/whisper.cpp"),
            url: None,
            path: "ggml-small.bin",
        },
    ],
    archives: &[],
    executable: Some("whisperfile-0.9.3"),
};

// Same 100-language set as Whisper multilingual.
const SUPPORTED_LANGUAGES: &[&str] = &[
    "en", "zh", "de", "es", "ru", "ko", "fr", "ja", "pt", "tr", "pl", "ca", "nl", "ar", "sv",
    "it", "id", "hi", "fi", "vi", "he", "uk", "el", "ms", "cs", "ro", "da", "hu", "ta", "no",
    "th", "ur", "hr", "bg", "lt", "la", "mi", "ml", "cy", "sk", "te", "fa", "lv", "bn", "sr",
    "az", "sl", "kn", "et", "mk", "br", "eu", "is", "hy", "ne", "mn", "bs", "kk", "sq", "sw",
    "gl", "mr", "pa", "si", "km", "sn", "yo", "so", "af", "oc", "ka", "be", "tg", "sd", "gu",
    "am", "yi", "lo", "uz", "fo", "ht", "ps", "tk", "nn", "mt", "sa", "lb", "my", "bo", "tl",
    "mg", "as", "tt", "haw", "ln", "ha", "ba", "jw", "su", "yue",
];

pub struct Whisperfile {
    inner: WhisperfileEngine,
}

impl Whisperfile {
    pub fn new(inner: WhisperfileEngine) -> Self {
        Self { inner }
    }
}

impl Model for Whisperfile {
    fn name(&self) -> &'static str {
        "WhisperfileSmall"
    }

    fn supported_languages(&self) -> &'static [&'static str] {
        SUPPORTED_LANGUAGES
    }

    fn transcribe(
        &mut self,
        samples: &[f32],
        target_language: Option<&str>,
    ) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
        let result = self
            .inner
            .transcribe_with(
                samples,
                &WhisperfileInferenceParams {
                    language: target_language.map(|l| l.to_string()),
                    ..Default::default()
                },
            )
            .map_err(|e| Box::new(e) as Box<dyn std::error::Error + Send + Sync>)?;
        Ok(result.text.trim().to_string())
    }
}

fn binary_path(dir: &Path) -> std::path::PathBuf {
    let base = dir.join("whisperfile-0.9.3");
    // llamafile APE binaries need an `.exe` suffix on Windows.
    if cfg!(windows) && !base.with_extension("exe").exists() && !base.exists() {
        base.with_extension("exe")
    } else if cfg!(windows) && base.with_extension("exe").exists() {
        base.with_extension("exe")
    } else {
        base
    }
}

pub fn load(path: &Path) -> Result<Box<dyn Model>, Box<dyn std::error::Error + Send + Sync>> {
    let binary = binary_path(path);
    let model = path.join("ggml-small.bin");
    // Port override for tests / parallel instances: WHISPERFILE_PORT.
    let port: u16 = std::env::var("WHISPERFILE_PORT")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(8080);
    let inner = WhisperfileEngine::load_with_params(
        &binary,
        &model,
        WhisperfileLoadParams {
            port,
            ..Default::default()
        },
    )
    .map_err(|e| Box::new(e) as Box<dyn std::error::Error + Send + Sync>)?;
    Ok(Box::new(Whisperfile::new(inner)))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn whisperfile_covers_multilingual_set() {
        assert!(SUPPORTED_LANGUAGES.contains(&"es"));
        assert!(SUPPORTED_LANGUAGES.contains(&"yue"));
    }
}
