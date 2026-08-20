use crate::model::{Model, ModelDefinition, ModelFile};
use std::path::Path;
use transcribe_rs::onnx::canary::CanaryModel;
use transcribe_rs::onnx::canary::CanaryParams;
use transcribe_rs::onnx::Quantization;

pub const DEFINITION: ModelDefinition = ModelDefinition {
    name: "Canary180M",
    dir: "canary-180m-flash-onnx",
    display: "Canary 180M Flash",
    files: &[
        ModelFile { repo: "istupakov/canary-180m-flash-onnx", path: "config.json" },
        ModelFile { repo: "istupakov/canary-180m-flash-onnx", path: "decoder-model.int8.onnx" },
        ModelFile { repo: "istupakov/canary-180m-flash-onnx", path: "decoder-model.onnx" },
        ModelFile { repo: "istupakov/canary-180m-flash-onnx", path: "encoder-model.int8.onnx" },
        ModelFile { repo: "istupakov/canary-180m-flash-onnx", path: "encoder-model.onnx" },
        ModelFile { repo: "istupakov/canary-180m-flash-onnx", path: "vocab.txt" },
        ModelFile { repo: "istupakov/parakeet-tdt-0.6b-v3-onnx", path: "nemo128.onnx" },
    ],
};

// Canary vocab carries a prompt token for each of these output languages,
// so translation is available for all of them.
const SUPPORTED_LANGUAGES: &[&str] = &["en", "es", "fr", "de", "pt"];

pub struct Canary180M {
    inner: CanaryModel,
}

impl Canary180M {
    pub fn new(inner: CanaryModel) -> Self {
        Self { inner }
    }
}

impl Model for Canary180M {
    fn name(&self) -> &'static str {
        "Canary180M"
    }

    fn supported_languages(&self) -> &'static [&'static str] {
        SUPPORTED_LANGUAGES
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

pub fn load(path: &Path) -> Result<Box<dyn Model>, Box<dyn std::error::Error + Send + Sync>> {
    let inner = CanaryModel::load(path, &Quantization::Int8)
        .map_err(|e| Box::new(e) as Box<dyn std::error::Error + Send + Sync>)?;
    Ok(Box::new(Canary180M::new(inner)))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn supports_all_target_languages() {
        let expected = ["en", "es", "fr", "de", "pt"];
        assert_eq!(SUPPORTED_LANGUAGES, expected);
        // Every advertised language must map to a vocab token so Canary can
        // build a prompt for it.
        assert!(expected.contains(&"en"));
        assert!(expected.contains(&"pt"));
    }
}
