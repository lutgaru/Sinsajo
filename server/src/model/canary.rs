use crate::model::{Model, ModelDefinition, ModelFile};
use std::path::Path;
use transcribe_rs::onnx::canary::CanaryModel;
use transcribe_rs::onnx::Quantization;
use transcribe_rs::SpeechModel;
use transcribe_rs::TranscribeOptions;

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

    fn transcribe(&mut self, samples: &[f32]) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
        let result = self.inner.transcribe(samples, &TranscribeOptions {
            language: Some("en".to_string()),
            ..Default::default()
        }).map_err(|e| Box::new(e) as Box<dyn std::error::Error + Send + Sync>)?;
        Ok(result.text.trim().to_string())
    }
}

pub fn load(path: &Path) -> Result<Box<dyn Model>, Box<dyn std::error::Error + Send + Sync>> {
    let inner = CanaryModel::load(path, &Quantization::Int8)
        .map_err(|e| Box::new(e) as Box<dyn std::error::Error + Send + Sync>)?;
    Ok(Box::new(Canary180M::new(inner)))
}
