use crate::model::Model;
use std::path::Path;
use transcribe_rs::onnx::parakeet::ParakeetModel;
use transcribe_rs::onnx::Quantization;
use transcribe_rs::SpeechModel;
use transcribe_rs::TranscribeOptions;

pub struct ParakeetTDT {
    inner: ParakeetModel,
}

impl ParakeetTDT {
    pub fn new(inner: ParakeetModel) -> Self {
        Self { inner }
    }
}

impl Model for ParakeetTDT {
    fn name(&self) -> &'static str {
        "ParakeetTDT"
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
    let inner = ParakeetModel::load(path, &Quantization::Int8)
        .map_err(|e| Box::new(e) as Box<dyn std::error::Error + Send + Sync>)?;
    Ok(Box::new(ParakeetTDT::new(inner)))
}
