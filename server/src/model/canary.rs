use crate::model::{Model, ModelDefinition, ModelFile};
use std::path::Path;
use transcribe_rs::onnx::canary::CanaryModel;
use transcribe_rs::onnx::canary::CanaryParams;
use transcribe_rs::onnx::Quantization;

pub const DEFINITION_180M: ModelDefinition = ModelDefinition {
    name: "Canary180M",
    dir: "canary-180m-flash-onnx",
    display: "Canary 180M Flash",
    files: &[
        ModelFile { repo: Some("istupakov/canary-180m-flash-onnx"), url: None, remote: None, path: "config.json" },
        ModelFile { repo: Some("istupakov/canary-180m-flash-onnx"), url: None, remote: None, path: "decoder-model.int8.onnx" },
        ModelFile { repo: Some("istupakov/canary-180m-flash-onnx"), url: None, remote: None, path: "decoder-model.onnx" },
        ModelFile { repo: Some("istupakov/canary-180m-flash-onnx"), url: None, remote: None, path: "encoder-model.int8.onnx" },
        ModelFile { repo: Some("istupakov/canary-180m-flash-onnx"), url: None, remote: None, path: "encoder-model.onnx" },
        ModelFile { repo: Some("istupakov/canary-180m-flash-onnx"), url: None, remote: None, path: "vocab.txt" },
        ModelFile { repo: Some("istupakov/parakeet-tdt-0.6b-v3-onnx"), url: None, remote: None, path: "nemo128.onnx" },
    ],
    archives: &[],
    executable: None,
};

pub const DEFINITION_1B_FLASH: ModelDefinition = ModelDefinition {
    name: "Canary1BFlash",
    dir: "canary-1b-flash-onnx",
    display: "Canary 1B Flash",
    files: &[
        ModelFile { repo: Some("istupakov/canary-1b-flash-onnx"), url: None, remote: None, path: "config.json" },
        ModelFile { repo: Some("istupakov/canary-1b-flash-onnx"), url: None, remote: None, path: "decoder-model.int8.onnx" },
        ModelFile { repo: Some("istupakov/canary-1b-flash-onnx"), url: None, remote: None, path: "decoder-model.onnx" },
        ModelFile { repo: Some("istupakov/canary-1b-flash-onnx"), url: None, remote: None, path: "encoder-model.int8.onnx" },
        ModelFile { repo: Some("istupakov/canary-1b-flash-onnx"), url: None, remote: None, path: "encoder-model.onnx" },
        ModelFile { repo: Some("istupakov/canary-1b-flash-onnx"), url: None, remote: None, path: "vocab.txt" },
        ModelFile { repo: Some("istupakov/parakeet-tdt-0.6b-v3-onnx"), url: None, remote: None, path: "nemo128.onnx" },
    ],
    archives: &[],
    executable: None,
};

pub const DEFINITION_1B_V2: ModelDefinition = ModelDefinition {
    name: "Canary1BV2",
    dir: "canary-1b-v2-onnx",
    display: "Canary 1B v2 (25 languages)",
    files: &[
        ModelFile { repo: Some("istupakov/canary-1b-v2-onnx"), url: None, remote: None, path: "config.json" },
        ModelFile { repo: Some("istupakov/canary-1b-v2-onnx"), url: None, remote: None, path: "decoder-model.int8.onnx" },
        ModelFile { repo: Some("istupakov/canary-1b-v2-onnx"), url: None, remote: None, path: "decoder-model.onnx" },
        ModelFile { repo: Some("istupakov/canary-1b-v2-onnx"), url: None, remote: None, path: "encoder-model.int8.onnx" },
        ModelFile { repo: Some("istupakov/canary-1b-v2-onnx"), url: None, remote: None, path: "encoder-model.onnx" },
        ModelFile { repo: Some("istupakov/canary-1b-v2-onnx"), url: None, remote: None, path: "vocab.txt" },
        ModelFile { repo: Some("istupakov/parakeet-tdt-0.6b-v3-onnx"), url: None, remote: None, path: "nemo128.onnx" },
    ],
    archives: &[],
    executable: None,
};

// Backwards compat for mod.rs MODELS list built before this refactor.
#[allow(dead_code)]
pub const DEFINITION: ModelDefinition = DEFINITION_180M;

// Flash vocab carries prompt tokens for en/de/es/fr only.
// V2 carries 25 languages. Variant is auto-detected from vocab size by
// transcribe-rs, but we advertise the right set per model entry so the
// client only enables languages that actually work.
const SUPPORTED_LANGUAGES_FLASH: &[&str] = &["en", "de", "es", "fr"];
const SUPPORTED_LANGUAGES_V2: &[&str] = &[
    "bg", "hr", "cs", "da", "nl", "en", "et", "fi", "fr", "de", "el", "hu", "it", "lv", "lt",
    "mt", "pl", "pt", "ro", "sk", "sl", "es", "sv", "ru", "uk",
];

pub struct Canary {
    inner: CanaryModel,
    name: &'static str,
    languages: &'static [&'static str],
}

impl Canary {
    pub fn new(inner: CanaryModel, name: &'static str, languages: &'static [&'static str]) -> Self {
        Self { inner, name, languages }
    }
}

impl Model for Canary {
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
        // Canary translates into the requested target language. The source
        // hint is set to the target so same-language speech is transcribed
        // natively and foreign speech is translated into it.
        let params = match target_language {
            Some(lang) => CanaryParams {
                language: Some(lang.to_string()),
                target_language: Some(lang.to_string()),
                ..Default::default()
            },
            None => CanaryParams {
                language: Some("en".to_string()),
                ..Default::default()
            },
        };
        let result = self
            .inner
            .transcribe_with(samples, &params)
            .map_err(|e| Box::new(e) as Box<dyn std::error::Error + Send + Sync>)?;
        Ok(result.text.trim().to_string())
    }
}

pub fn load(path: &Path, name: &str) -> Result<Box<dyn Model>, Box<dyn std::error::Error + Send + Sync>> {
    let inner = CanaryModel::load(path, &Quantization::Int8)
        .map_err(|e| Box::new(e) as Box<dyn std::error::Error + Send + Sync>)?;
    let (static_name, langs) = match name {
        "Canary1BFlash" => ("Canary1BFlash", SUPPORTED_LANGUAGES_FLASH),
        "Canary1BV2" => ("Canary1BV2", SUPPORTED_LANGUAGES_V2),
        _ => ("Canary180M", SUPPORTED_LANGUAGES_FLASH),
    };
    Ok(Box::new(Canary::new(inner, static_name, langs)))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn flash_languages_match_upstream() {
        // transcribe-rs FLASH_LANGUAGES = en/de/es/fr (no pt).
        assert_eq!(SUPPORTED_LANGUAGES_FLASH, &["en", "de", "es", "fr"]);
    }

    #[test]
    fn v2_has_25_languages_including_portuguese() {
        assert_eq!(SUPPORTED_LANGUAGES_V2.len(), 25);
        assert!(SUPPORTED_LANGUAGES_V2.contains(&"pt"));
        assert!(SUPPORTED_LANGUAGES_V2.contains(&"uk"));
    }
}
