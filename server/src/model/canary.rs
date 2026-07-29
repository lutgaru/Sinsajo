use crate::model::Model;
use std::path::Path;
use transcribe_rs::onnx::canary::CanaryModel;
use transcribe_rs::onnx::Quantization;
use transcribe_rs::SpeechModel;
use transcribe_rs::TranscribeOptions;

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
