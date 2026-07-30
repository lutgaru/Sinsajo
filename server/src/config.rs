use serde::{Deserialize, Serialize};
use std::fs;
use std::path::Path;

const CONFIG_FILE: &str = "sinsajo-config.json";

#[derive(Debug, Serialize, Deserialize)]
struct Config {
    model: String,
}

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
