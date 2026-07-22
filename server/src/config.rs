use serde::{Deserialize, Serialize};
use std::fs;
use std::path::Path;

const CONFIG_FILE: &str = "sinsajo-config.json";

#[derive(Debug, Serialize, Deserialize)]
struct Config {
    model: String,
}

pub struct ModelDefinition {
    pub name: &'static str,
    pub repo: &'static str,
    pub dir: &'static str,
    pub display: &'static str,
    pub extra_files: &'static [(&'static str, &'static str)],
}

pub const MODELS: &[ModelDefinition] = &[
    ModelDefinition {
        name: "ParakeetTDT",
        repo: "istupakov/parakeet-tdt-0.6b-v3-onnx",
        dir: "models/parakeet-tdt-0.6b-v3-onnx",
        display: "Parakeet TDT 0.6b v3",
        extra_files: &[],
    },
    ModelDefinition {
        name: "Canary180M",
        repo: "istupakov/canary-180m-flash-onnx",
        dir: "models/canary-180m-flash-onnx",
        display: "Canary 180M Flash",
        extra_files: &[("istupakov/parakeet-tdt-0.6b-v3-onnx", "nemo128.onnx")],
    },
];

pub fn load_model() -> Option<String> {
    let path = Path::new(CONFIG_FILE);
    if !path.exists() {
        return None;
    }
    let content = fs::read_to_string(path).ok()?;
    let config: Config = serde_json::from_str(&content).ok()?;
    Some(config.model)
}

pub fn save_model(model: &str) {
    let config = Config {
        model: model.to_string(),
    };
    if let Ok(json) = serde_json::to_string_pretty(&config) {
        let _ = fs::write(CONFIG_FILE, json);
    }
}

pub fn get_model_info(name: &str) -> &'static ModelDefinition {
    MODELS.iter().find(|m| m.name == name).unwrap_or_else(|| {
        eprintln!(
            "Unknown model '{}'. Valid models: {}",
            name,
            MODELS
                .iter()
                .map(|m| m.name)
                .collect::<Vec<_>>()
                .join(", ")
        );
        std::process::exit(1);
    })
}
