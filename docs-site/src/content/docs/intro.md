---
title: Introduction
description: What Sinsajo is, features and when to use it.
---

# Introduction

**Sinsajo** is a self-hosted real-time voice transcription system. Flutter client + Rust server, local AI models, Voice Activity Detection (VAD), and support for all local engines from `transcribe-rs`: **Parakeet**, **Canary** (180M Flash / 1B Flash / 1B v2), **Cohere**, **SenseVoice**, **GigaAM**, **Moonshine** (+ streaming), **Whisper** and **Whisperfile**.

> No cloud. No API keys. Your audio never leaves your network.

## Features

- ✅ Real-time transcription — see text as you speak
- ✅ 100% offline — complete privacy
- ✅ Voice Activity Detection — Silero VAD v5 (ONNX Runtime), only speech is sent
- ✅ Low latency — ~150–300ms end-to-end
- ✅ Multi-platform — Android, iOS, Desktop, **Web** (Flutter)
- ✅ Spanish native + target language selection (100-language picker, enabled per model's advertised support)
- ✅ Self-hosted — Docker or Cargo
- ✅ Runtime model manager — download, switch and delete models from the client
- ✅ Audio recording — WAV/OGG saved server-side, optional on-device WAV, or WebM download on Web
- ✅ Persistent settings — client and server settings survive restarts
- ✅ 20+ local models — see [Supported Models](/Sinsajo/reference/models/)

## Tech Stack

| Layer | Stack |
|-------|-------|
| Client | Flutter 3.x, Material 3, Riverpod 2.x, `record`, `web_socket_channel`, `vad` (Silero VAD v5), `shared_preferences` |
| Server | Rust + Tokio, `tokio-tungstenite`, `transcribe-rs` (ONNX Runtime; optional whisper-cpp/whisperfile), 20+ local model flags |
| Hosting | GitHub Pages (static) for landing + docs + Flutter Web; Rust server on your infra |
| Distribution | APK via GitHub Releases, Docker Hub `lutgaru/sinsajo-server` |

## Use cases

- Local meeting transcription where privacy matters
- Accessibility and note-taking
- Kiosk / embedded transcription without internet
- Base for building voice-driven apps

## Limitations

- Requires WiFi/LAN (or port forwarding / Tailscale for remote)
- Int8 model ~2% less accurate than Float32
- Single language per session
- No auth (local network only)
- First run downloads the selected model (from ~75 MB for Whisper Tiny to ~2–3 GB for larger models); cold start ~2–3s afterwards

Next: [Quick Start](/Sinsajo/guides/quickstart/) · [Supported Models](/Sinsajo/reference/models/)
