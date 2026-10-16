//! Whisper backend (whisper.cpp via whisper-rs).
//! Enabled with `--features whisper-cpp`.

use crate::model::{Model, ModelDefinition, ModelFile};
use std::path::Path;
use transcribe_rs::whisper_cpp::{WhisperEngine, WhisperInferenceParams};

pub const DEFINITION_TINY_EN: ModelDefinition = ModelDefinition {
    name: "WhisperTinyEn",
    dir: "whisper-tiny-en",
    display: "Whisper Tiny English (fast, 75MB)",
    files: &[ModelFile {
        repo: Some("ggerganov/whisper.cpp"),
        url: None,
        path: "ggml-tiny.en.bin",
    }],
    archives: &[],
    executable: None,
};

pub const DEFINITION_SMALL: ModelDefinition = ModelDefinition {
    name: "WhisperSmall",
    dir: "whisper-small",
    display: "Whisper Small (multilingual, 244MB)",
    files: &[ModelFile {
        repo: Some("ggerganov/whisper.cpp"),
        url: None,
        path: "ggml-small.bin",
    }],
    archives: &[],
    executable: None,
};

const LANG_EN: &[&str] = &["en"];

// Matches transcribe-rs WhisperEngine MULTILINGUAL_LANGUAGES (100).
const LANG_MULTILINGUAL: &[&str] = &[
    "en", "zh", "de", "es", "ru", "ko", "fr", "ja", "pt", "tr", "pl", "ca", "nl", "ar", "sv",
    "it", "id", "hi", "fi", "vi", "he", "uk", "el", "ms", "cs", "ro", "da", "hu", "ta", "no",
    "th", "ur", "hr", "bg", "lt", "la", "mi", "ml", "cy", "sk", "te", "fa", "lv", "bn", "sr",
    "az", "sl", "kn", "et", "mk", "br", "eu", "is", "hy", "ne", "mn", "bs", "kk", "sq", "sw",
    "gl", "mr", "pa", "si", "km", "sn", "yo", "so", "af", "oc", "ka", "be", "tg", "sd", "gu",
    "am", "yi", "lo", "uz", "fo", "ht", "ps", "tk", "nn", "mt", "sa", "lb", "my", "bo", "tl",
    "mg", "as", "tt", "haw", "ln", "ha", "ba", "jw", "su", "yue",
];

pub struct Whisper {
    inner: WhisperEngine,
    name: &'static str,
    languages: &'static [&'static str],
}

impl Whisper {
    pub fn new(inner: WhisperEngine, name: &'static str, languages: &'static [&'static str]) -> Self {
        Self { inner, name, languages }
    }
}

impl Model for Whisper {
    fn name(&self) -> &'static str {
        self.name
    }

    fn supported_languages(&self) -> &'static [&'static str] {
        self.languages
    }

    fn transcribe(
        &mut self,
        samples: &[f32],
        target_language: Option<&str>,
    ) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
        // `target_language` becomes the language hint. The whisper
        // `translate` flag (translate-to-English) is intentionally not
        // exposed: the client selects the desired output language and the
        // model transcribes in it.
        let result = self
            .inner
            .transcribe_with(
                samples,
                &WhisperInferenceParams {
                    language: target_language.map(|l| l.to_string()),
                    ..Default::default()
                },
            )
            .map_err(|e| Box::new(e) as Box<dyn std::error::Error + Send + Sync>)?;
        Ok(result.text.trim().to_string())
    }
}

fn model_file_for(name: &str, dir: &Path) -> (std::path::PathBuf, &'static str, &'static [&'static str]) {
    match name {
        "WhisperSmall" => (dir.join("ggml-small.bin"), "WhisperSmall", LANG_MULTILINGUAL),
        _ => (dir.join("ggml-tiny.en.bin"), "WhisperTinyEn", LANG_EN),
    }
}

pub fn load(path: &Path, name: &str) -> Result<Box<dyn Model>, Box<dyn std::error::Error + Send + Sync>> {
    let (file, static_name, langs) = model_file_for(name, path);
    let inner = WhisperEngine::load(&file)
        .map_err(|e| Box::new(e) as Box<dyn std::error::Error + Send + Sync>)?;
    Ok(Box::new(Whisper::new(inner, static_name, langs)))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tiny_is_english_only() {
        assert_eq!(LANG_EN, &["en"]);
    }

    #[test]
    fn small_covers_whisper_multilingual_set() {
        assert!(LANG_MULTILINGUAL.contains(&"es"));
        assert!(LANG_MULTILINGUAL.contains(&"yue"));
        assert!(LANG_MULTILINGUAL.len() >= 90);
    }
}
