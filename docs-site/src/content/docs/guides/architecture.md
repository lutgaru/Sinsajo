---
title: Architecture
description: Data flow, components and protocol.
---

## Overview

```
┌─────────────────┐         WebSocket          ┌──────────────────┐
│  Flutter Client │ ◄─────────────────────────►│   Rust Server    │
│  (Dart/Silero)  │    PCM 16-bit / JSON       │ (transcribe-rs)  │
└─────────────────┘                            └──────────────────┘
       │                                                 │
       │ Silero VAD v5                                   │ ONNX Model
       │ (ONNX Runtime)                                  │
       ▼                                                 ▼
 ┌─────────────────┐                             ┌──────────────────┐
 │  AudioService   │                             │  Canary 180M     │
 │  + vad package  │                             │  Flash /         │
 │  (ML-based)     │                             │  Parakeet TDT    │
 └─────────────────┘                             └──────────────────┘
```

### Data flow

1. **Audio Capture** — Flutter `record` → PCM 16-bit @ 16kHz
2. **VAD** — Silero VAD v5 via `vad` package (ONNX Runtime), emits only speech chunks
3. **WebSocket** — Binary PCM chunks + JSON control messages
4. **Transcription** — Rust server (`transcribe-rs` + ONNX Runtime) with Canary/Parakeet
5. **Recording** — Optional WAV/OGG saved to `records/` on `clean`
6. **Display** — Client renders text in real-time

### Project structure

```
sinsajo/
├── sinsajo_client/   # Flutter
│   ├── lib/providers/transcription_provider.dart
│   ├── lib/screens/transcription_screen.dart
│   └── lib/services/{audio_service.dart, ws_service.dart}
├── server/           # Rust
│   ├── src/{main.rs, config.rs, model_downloader.rs}
│   └── models/       # downloaded ONNX models
├── docs-site/        # Astro Starlight (this site) -> GitHub Pages
└── .github/workflows/
    ├── client.yml
    ├── server.yml
    └── docs.yml      # builds Astro + Flutter Web -> Pages
```

### Hosting on GitHub Pages (static only)

GitHub Pages can only serve static files. So:

- **Landing + Docs** — `docs-site/dist` (Astro) at `/Sinsajo/`
- **Web App** — `sinsajo_client/build/web` merged into `dist/app/` at `/Sinsajo/app/`
- **APK** — **not** on Pages; attached to GitHub Release and linked from the landing

The Rust server must run elsewhere (your machine, VPS, Docker). The Web App connects to it via `ws://` / `wss://`. For microphone access, the Page **must be HTTPS** (GitHub Pages is) and the WebSocket should be `wss://` if you use a custom domain with TLS.

### Why Astro + Flutter

Flutter Web is excellent for the app but poor for SEO/docs (Canvas rendering, large JS payload). Astro Starlight is zero-JS by default and great for docs/landing. Combining both gives the best of each world while keeping a single GitHub Pages deployment.

See [Protocol](/Sinsajo/guides/protocol/) for message formats.
