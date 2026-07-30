use crate::model::{Model, ModelDefinition, ModelFile};
use std::path::Path;
use transcribe_rs::onnx::parakeet::ParakeetModel;
use transcribe_rs::onnx::Quantization;
use transcribe_rs::SpeechModel;
use transcribe_rs::TranscribeOptions;

pub const DEFINITION: ModelDefinition = ModelDefinition {
    name: "ParakeetTDT",
    dir: "parakeet-tdt-0.6b-v3-onnx",
    display: "Parakeet TDT 0.6b v3",
    files: &[
        ModelFile { repo: "istupakov/parakeet-tdt-0.6b-v3-onnx", path: "config.json" },
        ModelFile { repo: "istupakov/parakeet-tdt-0.6b-v3-onnx", path: "decoder_joint-model.int8.onnx" },
        ModelFile { repo: "istupakov/parakeet-tdt-0.6b-v3-onnx", path: "decoder_joint-model.onnx" },
        ModelFile { repo: "istupakov/parakeet-tdt-0.6b-v3-onnx", path: "encoder-model.int8.onnx" },
        ModelFile { repo: "istupakov/parakeet-tdt-0.6b-v3-onnx", path: "encoder-model.onnx" },
        ModelFile { repo: "istupakov/parakeet-tdt-0.6b-v3-onnx", path: "encoder-model.onnx.data" },
        ModelFile { repo: "istupakov/parakeet-tdt-0.6b-v3-onnx", path: "nemo128.onnx" },
        ModelFile { repo: "istupakov/parakeet-tdt-0.6b-v3-onnx", path: "vocab.txt" },
    ],
};

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
