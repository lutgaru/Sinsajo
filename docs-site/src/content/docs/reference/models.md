---
title: Supported Models
description: Complete list of local models, languages, download sources and feature gates.
---

Sinsajo runs every model locally through [`transcribe-rs`](https://github.com/cjpais/transcribe-rs). The OpenAI remote engine is intentionally **not** wired in: Sinsajo is 100% offline by design.

The default server binary includes the **ONNX** backends. Whisper and Whisperfile are available behind cargo features (see [Feature-gated builds](#feature-gated-builds)). A few Moonshine variants are registered but require manual weight placement.

## Quick pick

| You need… | Use |
|-----------|-----|
| Fast English | `MoonshineTiny` or `WhisperTinyEn` |
| Most accurate English | `ParakeetTDT` |
| Multilingual + translation (en/de/es/fr) | `Canary180M` or `Canary1BFlash` |
| 25 languages (incl. Portuguese) | `Canary1BV2` |
| 14 languages, small download | `CohereInt4` |
| Chinese / Japanese / Korean / Cantonese | `SenseVoice` |
| Russian | `GigaAM` |
| 100 languages | `WhisperSmall` or `WhisperfileSmall` |

## Full registry

| `--model` flag | Engine | Languages | Download | Notes |
|----------------|--------|-----------|----------|-------|
| `ParakeetTDT` | Parakeet TDT 0.6B v3 (int8) | `en` | HuggingFace | Most accurate English; default in the Docker image |
| `Canary180M` | Canary 180M Flash (int8) | `en`, `de`, `es`, `fr` | HuggingFace | Fast multilingual + translation |
| `Canary1BFlash` | Canary 1B Flash (int8) | `en`, `de`, `es`, `fr` | HuggingFace | Larger Flash variant |
| `Canary1BV2` | Canary 1B v2 (int8) | 25 languages* | HuggingFace | Widest Canary coverage |
| `CohereInt4` | Cohere Transcribe (int4) | 14 languages† | HuggingFace | Smaller download |
| `CohereInt8` | Cohere Transcribe (int8) | 14 languages† | HuggingFace | Higher-precision weights |
| `SenseVoice` | SenseVoice Small (int8) | `zh`, `en`, `ja`, `ko`, `yue` | Mirror tarball | Auto-download |
| `GigaAM` | GigaAM v3 (int8) | `ru` | HuggingFace | Russian-only |
| `MoonshineTiny` | Moonshine Tiny | `en` | Manual | Tiny and fast |
| `MoonshineBase` | Moonshine Base | `en` | Mirror tarball | Auto-download |
| `MoonshineBaseEs` | Moonshine Base | `es` | Manual | Spanish |
| `MoonshineTinyAr` | Moonshine Tiny | `ar` | Manual | Arabic |
| `MoonshineTinyZh` | Moonshine Tiny | `zh` | Manual | Chinese |
| `MoonshineTinyJa` | Moonshine Tiny | `ja` | Manual | Japanese |
| `MoonshineTinyKo` | Moonshine Tiny | `ko` | Manual | Korean |
| `MoonshineTinyUk` | Moonshine Tiny | `uk` | Manual | Ukrainian |
| `MoonshineTinyVi` | Moonshine Tiny | `vi` | Manual | Vietnamese |
| `MoonshineStreamingTinyEn` | Moonshine Streaming | `en` | Mirror tarball | Auto-download |
| `WhisperTinyEn` | Whisper (whisper.cpp) | `en` | HuggingFace | 75 MB; `--features whisper-cpp` |
| `WhisperSmall` | Whisper (whisper.cpp) | 100 languages‡ | HuggingFace | 244 MB; `--features whisper-cpp` |
| `WhisperfileSmall` | Whisperfile server | 100 languages‡ | GitHub + HuggingFace | `--features whisperfile` |

\* Canary 1B v2: `bg`, `hr`, `cs`, `da`, `nl`, `en`, `et`, `fi`, `fr`, `de`, `el`, `hu`, `it`, `lv`, `lt`, `mt`, `pl`, `pt`, `ro`, `sk`, `sl`, `es`, `sv`, `ru`, `uk`.

† Cohere: `en`, `de`, `fr`, `it`, `es`, `pt`, `el`, `nl`, `pl`, `ar`, `vi`, `zh`, `ja`, `ko`.

‡ Whisper multilingual and Whisperfile use the same 100-language set (including `yue`, `haw`, `nn`, `mt`). The client exposes the full union and enables only what the active model advertises.

## How language selection works

On connect, the server sends `model_info` with the active model and its supported languages. The client uses that list to enable or disable entries in the target-language picker.

The client sends the chosen BCP-47 code as `target_language` in the session `start` message. Behavior depends on the engine:

| Engine | `target_language` behavior |
|--------|---------------------------|
| Canary | Translates into the target language (source hint is pinned to the same code) |
| Whisper / Whisperfile | Used as the transcription language hint |
| Cohere / SenseVoice | Used as a language hint |
| Parakeet | Ignored — English-only |
| GigaAM | Ignored — Russian-only |
| Moonshine | Ignored — each variant is single-language |

Unknown or unsupported codes are rejected or dropped before reaching the model. See [Protocol](/Sinsajo/guides/protocol/).

## Feature-gated builds

The default build is ONNX-only. Whisper and Whisperfile require cargo features at **build** time:

```bash
cd server

# Whisper Tiny English / Whisper Small
cargo run --release --features whisper-cpp -- --model WhisperSmall --autodownload-model

# Whisperfile Small (spawns a local whisperfile HTTP server on port 8080)
cargo run --release --features whisperfile -- --model WhisperfileSmall --autodownload-model

# Both backends
cargo run --release --features "whisper-cpp whisperfile" -- --model WhisperSmall --autodownload-model
```

Docker builds accept the same features through a build arg:

```bash
docker build --build-arg FEATURES=whisper-cpp -t sinsajo-server:whisper .
```

The published Docker Hub image and precompiled binaries are ONNX-only. An unknown `--model` name prints the flags compiled into your binary, plus rebuild hints for gated models.

`WhisperfileSmall` also needs a free local port. Override the default (`8080`) with `WHISPERFILE_PORT`.

## Model manager (runtime switching)

You do not need to restart the server to change models. In the client, open **Settings → Server → Model manager** to:

- See every model compiled into the server, whether it is installed, and which one is active
- **Download** a missing model and follow aggregate progress (a segmented bar with one section per file, plus bytes)
- **Load** or **Reload** an installed model (the server swaps it in memory and persists the choice)
- **Delete** an installed model (the active model cannot be deleted)

Only one model operation runs at a time. Downloads execute on the server and can take minutes; the client can stay connected and continue showing progress.

The manager also works over the raw protocol with `list_models`, `download_model`, `load_model`, `reload_model` and `delete_model`. See [Protocol](/Sinsajo/guides/protocol/#model-manager).

The last model loaded is written to `sinsajo-config.json`, so the next server start uses it when `--model` is omitted.

## Storage and downloads

- Models live under `--model-dir` (default `./models`), one subdirectory per model.
- The server downloads single files from HuggingFace, or mirror tarballs for Moonshine, SenseVoice and Whisperfile distributions.
- `.sinsajo_manifest.json` records which files the server installed, so partial downloads are detected and repaired.
- `--autodownload-model` fetches missing files on startup; without it, the server verifies the model and exits with the missing file list.
- CI checks every download and archive URL on each push, and the full feature-gated set weekly.

### Manual models

Moonshine models marked **Manual** are not auto-downloaded. Place these files in `models/<dir>`:

```
encoder_model.onnx
decoder_model_merged.onnx
tokenizer.json
```

Use the `dir` value reported by the model manager or the server logs (for example `moonshine-tiny`, `moonshine-base-es`, `moonshine-tiny-ar`).

## Adding a model

Add a module under `server/src/model/` that:

1. Defines a `ModelDefinition` (name, dir, display name, files and/or archives)
2. Implements the `Model` trait (`name`, `supported_languages`, `transcribe`)
3. Is registered in `MODELS` in `server/src/model/mod.rs`

If the engine needs an optional backend, add a cargo feature and a `#[cfg(feature = "...")]` entry so the default binary stays lightweight. Unknown names should keep printing the valid flags.
