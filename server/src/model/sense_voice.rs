use crate::model::{Model, ModelDefinition, ModelFile};
use std::path::Path;
use transcribe_rs::onnx::sense_voice::{SenseVoiceModel, SenseVoiceParams};
use transcribe_rs::onnx::Quantization;

pub const DEFINITION: ModelDefinition = ModelDefinition {
    name: "SenseVoice",
    dir: "sense-voice-int8",
    display: "SenseVoice Small (zh/en/ja/ko/yue)",
    files: &[
        // Distributed as a tarball (see `archives`); place these two files
        // manually if you prefer not to use the archive mirror.
        ModelFile::manual("model.int8.onnx"),
        ModelFile::manual("tokens.txt"),
    ],
    archives: &[crate::model::ModelArchive {
        url: "https://blob.handy.computer/sense-voice-int8.tar.gz",
    }],
    executable: None,
};

// Upstream SenseVoice CAPABILITIES.
const SUPPORTED_LANGUAGES: &[&str] = &["zh", "en", "ja", "ko", "yue"];

pub struct SenseVoice {
    inner: SenseVoiceModel,
}

impl SenseVoice {
    pub fn new(inner: SenseVoiceModel) -> Self {
        Self { inner }
    }
}

impl Model for SenseVoice {
    fn name(&self) -> &'static str {
        "SenseVoice"
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
                &SenseVoiceParams {
                    language: Some(target_language.unwrap_or("auto").to_string()),
                    ..Default::default()
                },
            )
            .map_err(|e| Box::new(e) as Box<dyn std::error::Error + Send + Sync>)?;
        Ok(result.text.trim().to_string())
    }
}

pub fn load(path: &Path) -> Result<Box<dyn Model>, Box<dyn std::error::Error + Send + Sync>> {
    let inner = SenseVoiceModel::load(path, &Quantization::Int8)
        .map_err(|e| Box::new(e) as Box<dyn std::error::Error + Send + Sync>)?;
    Ok(Box::new(SenseVoice::new(inner)))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sensevoice_languages_match_upstream() {
        assert_eq!(SUPPORTED_LANGUAGES, &["zh", "en", "ja", "ko", "yue"]);
    }
}
