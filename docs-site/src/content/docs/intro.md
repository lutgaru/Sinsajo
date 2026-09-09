---
title: Introduction
description: What Sinsajo is, features and when to use it.
---

# Introduction

**Sinsajo** is a self-hosted real-time voice transcription system. Flutter client + Rust server, local AI models, Voice Activity Detection (VAD), and support for **Canary 180M Flash** and **Parakeet TDT 0.6B**.

> No cloud. No API keys. Your audio never leaves your network.

## Features

- ✅ Real-time transcription — see text as you speak
- ✅ 100% offline — complete privacy
- ✅ Voice Activity Detection — Silero VAD v5 (ONNX Runtime), only speech is sent
- ✅ Low latency — ~150–300ms end-to-end
- ✅ Multi-platform — Android, iOS, Desktop, **Web** (Flutter)
- ✅ Spanish native + target language selection (en/es/fr/de/pt)
- ✅ Self-hosted — Docker or Cargo
- ✅ Audio recording — WAV/OGG saved server-side, configurable from client

## Tech Stack

| Layer | Stack |
|-------|-------|
| Client | Flutter 3.x, Material 3, Riverpod 2.x, `record`, `web_socket_channel`, `vad` (Silero VAD v5) |
| Server | Rust + Tokio, `tokio-tungstenite`, `transcribe-rs` (ONNX Runtime), Canary/Parakeet Int8 |
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
- First run downloads ~2–3GB model from HuggingFace, cold start ~2–3s

Next: [Quick Start](/Sinsajo/guides/quickstart/).
