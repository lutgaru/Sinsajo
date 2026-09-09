---
title: Server (Rust)
description: Rust server — run with Cargo or Docker.
---

## Quick run

```bash
cd server
cargo run --release -- --model ParakeetTDT --autodownload-model
# or
cargo run --release -- --model Canary180M --autodownload-model
```

If `--model` is omitted, the server checks `sinsajo-config.json`, then prompts.

## Docker

Pull from Docker Hub [`lutgaru/sinsajo-server`](https://hub.docker.com/r/lutgaru/sinsajo-server):

```bash
docker pull lutgaru/sinsajo-server:latest
docker run -p 8765:8765 \
  -v sinsajo_models:/app/models \
  -v sinsajo_records:/app/records \
  lutgaru/sinsajo-server:latest --model ParakeetTDT --autodownload-model
```

Compose (recommended) — see [Quick Start](/Sinsajo/guides/quickstart/).

## Models

Add new models in `server/src/config.rs` (`MODELS` array) with HuggingFace repo + folder.

Current: `ParakeetTDT` (0.6B, more accurate, English) and `Canary180M` (180M, faster, multilingual).

Auto-download handles ~2–3GB on first run. Override dirs with `--model-dir` / `--records-dir`.

## GPU acceleration

```rust
use transcribe_rs::{set_ort_accelerator, OrtAccelerator};
set_ort_accelerator(OrtAccelerator::Cuda); // or Auto
```

## Translation

Canary supports `target_language` from client `start` message. Server forwards to `transcribe_with`:

```rust
model.transcribe_with(&samples, &CanaryParams {
  language: Some("es".to_string()),
  target_language: Some("en".to_string()),
  ..Default::default()
})?;
```

Parakeet is English-only and ignores the target language. See [Protocol](/Sinsajo/guides/protocol/).

## Persistence

- Models: `models/` (or `--model-dir`)
- Recordings: `records/` (WAV/OGG, triggered by client `clean`)
- Config: `sinsajo-config.json`

## Deployment

The server is **not** deployed to GitHub Pages (static). Run it on your LAN, VPS, or fly.io / Railway with Docker. Expose `8765` and point clients to `ws://YOUR_IP:8765` or `wss://` behind a reverse proxy.
