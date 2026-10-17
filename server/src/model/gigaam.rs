use crate::model::{Model, ModelDefinition, ModelFile};
use std::path::Path;
use transcribe_rs::onnx::gigaam::{GigaAMModel, GigaAMParams};
use transcribe_rs::onnx::Quantization;

pub const DEFINITION: ModelDefinition = ModelDefinition {
    name: "GigaAM",
    dir: "gigaam-v3-onnx",
    display: "GigaAM v3 (Russian)",
    // The upstream repo publishes onnx-asr naming (`v3_e2e_ctc.int8.onnx`,
    // `v3_e2e_ctc_vocab.txt`), but transcribe-rs loads `model.int8.onnx`
    // (or `model.onnx`) plus `vocab.txt`, so the files are renamed on
    // download via `hf_renamed`. E2E CTC is the punctuation/normalization
    // variant that matches transcribe-rs' CTC decoding.
    files: &[
        ModelFile::hf_renamed(
            "istupakov/gigaam-v3-onnx",
            "v3_e2e_ctc.int8.onnx",
            "model.int8.onnx",
        ),
        ModelFile::hf_renamed(
            "istupakov/gigaam-v3-onnx",
            "v3_e2e_ctc_vocab.txt",
            "vocab.txt",
        ),
    ],
    archives: &[],
    executable: None,
};

// Upstream GigaAM CAPABILITIES: Russian-only.
const SUPPORTED_LANGUAGES: &[&str] = &["ru"];

pub struct GigaAM {
    inner: GigaAMModel,
}

impl GigaAM {
    pub fn new(inner: GigaAMModel) -> Self {
        Self { inner }
    }
}

impl Model for GigaAM {
    fn name(&self) -> &'static str {
        "GigaAM"
    }

    fn supported_languages(&self) -> &'static [&'static str] {
        SUPPORTED_LANGUAGES
    }

    fn transcribe(
        &mut self,
        samples: &[f32],
        _target_language: Option<&str>,
    ) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
        let result = self
            .inner
            .transcribe_with(samples, &GigaAMParams::default())
            .map_err(|e| Box::new(e) as Box<dyn std::error::Error + Send + Sync>)?;
        Ok(result.text.trim().to_string())
    }
}

pub fn load(path: &Path) -> Result<Box<dyn Model>, Box<dyn std::error::Error + Send + Sync>> {
    let inner = GigaAMModel::load(path, &Quantization::Int8)
        .map_err(|e| Box::new(e) as Box<dyn std::error::Error + Send + Sync>)?;
    Ok(Box::new(GigaAM::new(inner)))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn gigaam_is_russian_only() {
        assert_eq!(SUPPORTED_LANGUAGES, &["ru"]);
    }
}
