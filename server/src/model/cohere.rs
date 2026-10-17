use crate::model::{Model, ModelDefinition, ModelFile};
use std::path::Path;
use transcribe_rs::onnx::cohere::{CohereModel, CohereParams};
use transcribe_rs::onnx::Quantization;

pub const DEFINITION_INT4: ModelDefinition = ModelDefinition {
    name: "CohereInt4",
    dir: "cohere-transcribe-int4-onnx",
    display: "Cohere Transcribe (int4)",
    files: &[
        ModelFile { repo: Some("cstr/cohere-transcribe-onnx-int4"), url: None, remote: None, path: "cohere-encoder.int4.onnx" },
        ModelFile { repo: Some("cstr/cohere-transcribe-onnx-int4"), url: None, remote: None, path: "cohere-encoder.int4.onnx.data" },
        ModelFile { repo: Some("cstr/cohere-transcribe-onnx-int4"), url: None, remote: None, path: "cohere-decoder.int4.onnx" },
        ModelFile { repo: Some("cstr/cohere-transcribe-onnx-int4"), url: None, remote: None, path: "cohere-decoder.int4.onnx.data" },
        ModelFile { repo: Some("cstr/cohere-transcribe-onnx-int4"), url: None, remote: None, path: "tokens.txt" },
    ],
    archives: &[],
    executable: None,
};

pub const DEFINITION_INT8: ModelDefinition = ModelDefinition {
    name: "CohereInt8",
    dir: "cohere-transcribe-int8-onnx",
    display: "Cohere Transcribe (int8)",
    // Note: unlike the int4 repo, the int8 repo ships the decoder as a single
    // self-contained file (no `cohere-decoder.int8.onnx.data`); only the
    // encoder has a sidecar `.data`. Listing a nonexistent file here causes a
    // 404 on download.
    files: &[
        ModelFile { repo: Some("tristanripke/cohere-transcribe-onnx-int8"), url: None, remote: None, path: "cohere-encoder.int8.onnx" },
        ModelFile { repo: Some("tristanripke/cohere-transcribe-onnx-int8"), url: None, remote: None, path: "cohere-encoder.int8.onnx.data" },
        ModelFile { repo: Some("tristanripke/cohere-transcribe-onnx-int8"), url: None, remote: None, path: "cohere-decoder.int8.onnx" },
        ModelFile { repo: Some("tristanripke/cohere-transcribe-onnx-int8"), url: None, remote: None, path: "tokens.txt" },
    ],
    archives: &[],
    executable: None,
};

// Upstream Cohere CAPABILITIES: 14 languages, no translation/timestamps.
const SUPPORTED_LANGUAGES: &[&str] = &[
    "en", "de", "fr", "it", "es", "pt", "el", "nl", "pl", "ar", "vi", "zh", "ja", "ko",
];

pub struct Cohere {
    inner: CohereModel,
    name: &'static str,
    quantization: Quantization,
}

impl Cohere {
    pub fn new(inner: CohereModel, name: &'static str, quantization: Quantization) -> Self {
        Self { inner, name, quantization }
    }
}

impl Model for Cohere {
    fn name(&self) -> &'static str {
        self.name
    }

    fn supported_languages(&self) -> &'static [&'static str] {
        SUPPORTED_LANGUAGES
    }

    fn transcribe(
        &mut self,
        samples: &[f32],
        target_language: Option<&str>,
    ) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
        // The local ONNX export ignores translation; the language is only a
        // prompt hint. Default to English like the upstream example.
        let _ = &self.quantization;
        let result = self
            .inner
            .transcribe_with(
                samples,
                &CohereParams {
                    language: Some(target_language.unwrap_or("en").to_string()),
                    ..Default::default()
                },
            )
            .map_err(|e| Box::new(e) as Box<dyn std::error::Error + Send + Sync>)?;
        Ok(result.text.trim().to_string())
    }
}

pub fn load(path: &Path, name: &str) -> Result<Box<dyn Model>, Box<dyn std::error::Error + Send + Sync>> {
    let (static_name, quant) = match name {
        "CohereInt8" => ("CohereInt8", Quantization::Int8),
        _ => ("CohereInt4", Quantization::Int4),
    };
    let inner = CohereModel::load(path, &quant)
        .map_err(|e| Box::new(e) as Box<dyn std::error::Error + Send + Sync>)?;
    Ok(Box::new(Cohere::new(inner, static_name, quant)))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cohere_languages_match_upstream() {
        assert_eq!(SUPPORTED_LANGUAGES.len(), 14);
        assert!(SUPPORTED_LANGUAGES.contains(&"en"));
        assert!(SUPPORTED_LANGUAGES.contains(&"ko"));
    }
}
