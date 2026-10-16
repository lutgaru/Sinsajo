use crate::model::{Model, ModelArchive, ModelDefinition, ModelFile};
use std::path::Path;
use transcribe_rs::onnx::moonshine::{MoonshineModel, MoonshineParams, MoonshineVariant, StreamingModel};
use transcribe_rs::onnx::Quantization;

// transcribe-rs layout (non-streaming):
//   encoder_model.onnx, decoder_model_merged.onnx, tokenizer.json
// Streaming layout:
//   encoder.onnx, decoder.onnx, streaming_config.json, tokenizer.json

const NON_STREAMING_FILES: &[ModelFile] = &[
    ModelFile { repo: None, url: None, path: "encoder_model.onnx" },
    ModelFile { repo: None, url: None, path: "decoder_model_merged.onnx" },
    ModelFile { repo: None, url: None, path: "tokenizer.json" },
];

pub const DEFINITION_TINY: ModelDefinition = ModelDefinition {
    name: "MoonshineTiny",
    dir: "moonshine-tiny",
    display: "Moonshine Tiny (English)",
    files: NON_STREAMING_FILES,
    archives: &[],
    executable: None,
};

pub const DEFINITION_BASE: ModelDefinition = ModelDefinition {
    name: "MoonshineBase",
    dir: "moonshine-base",
    display: "Moonshine Base (English)",
    files: NON_STREAMING_FILES,
    archives: &[ModelArchive {
        url: "https://blob.handy.computer/moonshine-base.tar.gz",
    }],
    executable: None,
};

pub const DEFINITION_BASE_ES: ModelDefinition = ModelDefinition {
    name: "MoonshineBaseEs",
    dir: "moonshine-base-es",
    display: "Moonshine Base (Spanish)",
    files: NON_STREAMING_FILES,
    archives: &[],
    executable: None,
};

pub const DEFINITION_TINY_AR: ModelDefinition = ModelDefinition {
    name: "MoonshineTinyAr",
    dir: "moonshine-tiny-ar",
    display: "Moonshine Tiny (Arabic)",
    files: NON_STREAMING_FILES,
    archives: &[],
    executable: None,
};

pub const DEFINITION_TINY_ZH: ModelDefinition = ModelDefinition {
    name: "MoonshineTinyZh",
    dir: "moonshine-tiny-zh",
    display: "Moonshine Tiny (Chinese)",
    files: NON_STREAMING_FILES,
    archives: &[],
    executable: None,
};

pub const DEFINITION_TINY_JA: ModelDefinition = ModelDefinition {
    name: "MoonshineTinyJa",
    dir: "moonshine-tiny-ja",
    display: "Moonshine Tiny (Japanese)",
    files: NON_STREAMING_FILES,
    archives: &[],
    executable: None,
};

pub const DEFINITION_TINY_KO: ModelDefinition = ModelDefinition {
    name: "MoonshineTinyKo",
    dir: "moonshine-tiny-ko",
    display: "Moonshine Tiny (Korean)",
    files: NON_STREAMING_FILES,
    archives: &[],
    executable: None,
};

pub const DEFINITION_TINY_UK: ModelDefinition = ModelDefinition {
    name: "MoonshineTinyUk",
    dir: "moonshine-tiny-uk",
    display: "Moonshine Tiny (Ukrainian)",
    files: NON_STREAMING_FILES,
    archives: &[],
    executable: None,
};

pub const DEFINITION_TINY_VI: ModelDefinition = ModelDefinition {
    name: "MoonshineTinyVi",
    dir: "moonshine-tiny-vi",
    display: "Moonshine Tiny (Vietnamese)",
    files: NON_STREAMING_FILES,
    archives: &[],
    executable: None,
};

pub const DEFINITION_STREAMING_TINY_EN: ModelDefinition = ModelDefinition {
    name: "MoonshineStreamingTinyEn",
    dir: "moonshine-tiny-streaming-en",
    display: "Moonshine Tiny Streaming (English)",
    files: &[
        ModelFile { repo: None, url: None, path: "encoder.onnx" },
        ModelFile { repo: None, url: None, path: "decoder.onnx" },
        ModelFile { repo: None, url: None, path: "streaming_config.json" },
        ModelFile { repo: None, url: None, path: "tokenizer.json" },
    ],
    archives: &[ModelArchive {
        url: "https://blob.handy.computer/moonshine-tiny-streaming-en.tar.gz",
    }],
    executable: None,
};

// Upstream Moonshine non-streaming models are single-language.
const LANG_EN: &[&str] = &["en"];
const LANG_ES: &[&str] = &["es"];
const LANG_AR: &[&str] = &["ar"];
const LANG_ZH: &[&str] = &["zh"];
const LANG_JA: &[&str] = &["ja"];
const LANG_KO: &[&str] = &["ko"];
const LANG_UK: &[&str] = &["uk"];
const LANG_VI: &[&str] = &["vi"];

fn variant_for(name: &str) -> (MoonshineVariant, &'static str, &'static [&'static str]) {
    match name {
        "MoonshineBase" => (MoonshineVariant::Base, "MoonshineBase", LANG_EN),
        "MoonshineBaseEs" => (MoonshineVariant::BaseEs, "MoonshineBaseEs", LANG_ES),
        "MoonshineTinyAr" => (MoonshineVariant::TinyAr, "MoonshineTinyAr", LANG_AR),
        "MoonshineTinyZh" => (MoonshineVariant::TinyZh, "MoonshineTinyZh", LANG_ZH),
        "MoonshineTinyJa" => (MoonshineVariant::TinyJa, "MoonshineTinyJa", LANG_JA),
        "MoonshineTinyKo" => (MoonshineVariant::TinyKo, "MoonshineTinyKo", LANG_KO),
        "MoonshineTinyUk" => (MoonshineVariant::TinyUk, "MoonshineTinyUk", LANG_UK),
        "MoonshineTinyVi" => (MoonshineVariant::TinyVi, "MoonshineTinyVi", LANG_VI),
        _ => (MoonshineVariant::Tiny, "MoonshineTiny", LANG_EN),
    }
}

pub struct Moonshine {
    inner: MoonshineModel,
    name: &'static str,
    languages: &'static [&'static str],
}

impl Moonshine {
    pub fn new(inner: MoonshineModel, name: &'static str, languages: &'static [&'static str]) -> Self {
        Self { inner, name, languages }
    }
}

impl Model for Moonshine {
    fn name(&self) -> &'static str {
        self.name
    }

    fn supported_languages(&self) -> &'static [&'static str] {
        self.languages
    }

    fn transcribe(
        &mut self,
        samples: &[f32],
        _target_language: Option<&str>,
    ) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
        let result = self
            .inner
            .transcribe_with(samples, &MoonshineParams::default())
            .map_err(|e| Box::new(e) as Box<dyn std::error::Error + Send + Sync>)?;
        Ok(result.text.trim().to_string())
    }
}

pub struct MoonshineStreaming {
    inner: StreamingModel,
}

impl MoonshineStreaming {
    pub fn new(inner: StreamingModel) -> Self {
        Self { inner }
    }
}

impl Model for MoonshineStreaming {
    fn name(&self) -> &'static str {
        "MoonshineStreamingTinyEn"
    }

    fn supported_languages(&self) -> &'static [&'static str] {
        LANG_EN
    }

    fn transcribe(
        &mut self,
        samples: &[f32],
        _target_language: Option<&str>,
    ) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
        use transcribe_rs::SpeechModel as _SpeechModel;
        let result = self
            .inner
            .transcribe(samples, &transcribe_rs::TranscribeOptions::default())
            .map_err(|e| Box::new(e) as Box<dyn std::error::Error + Send + Sync>)?;
        Ok(result.text.trim().to_string())
    }
}

pub fn load(path: &Path, name: &str) -> Result<Box<dyn Model>, Box<dyn std::error::Error + Send + Sync>> {
    let (variant, static_name, langs) = variant_for(name);
    let inner = MoonshineModel::load(path, variant, &Quantization::default())
        .map_err(|e| Box::new(e) as Box<dyn std::error::Error + Send + Sync>)?;
    Ok(Box::new(Moonshine::new(inner, static_name, langs)))
}

pub fn load_streaming(path: &Path) -> Result<Box<dyn Model>, Box<dyn std::error::Error + Send + Sync>> {
    // 4 threads matches the upstream streaming example.
    let inner = StreamingModel::load(path, 4, &Quantization::default())
        .map_err(|e| Box::new(e) as Box<dyn std::error::Error + Send + Sync>)?;
    Ok(Box::new(MoonshineStreaming::new(inner)))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn all_variants_map_to_expected_languages() {
        assert_eq!(variant_for("MoonshineTiny").2, &["en"]);
        assert_eq!(variant_for("MoonshineBase").2, &["en"]);
        assert_eq!(variant_for("MoonshineBaseEs").2, &["es"]);
        assert_eq!(variant_for("MoonshineTinyAr").2, &["ar"]);
        assert_eq!(variant_for("MoonshineTinyZh").2, &["zh"]);
        assert_eq!(variant_for("MoonshineTinyJa").2, &["ja"]);
        assert_eq!(variant_for("MoonshineTinyKo").2, &["ko"]);
        assert_eq!(variant_for("MoonshineTinyUk").2, &["uk"]);
        assert_eq!(variant_for("MoonshineTinyVi").2, &["vi"]);
    }
}
