---
title: Roadmap
description: Completed, in progress and planned.
---

## Completed ✅

- [x] Real-time transcription
- [x] Voice Activity Detection (Silero VAD v5)
- [x] Multi-platform (Android, iOS, Desktop, Web)
- [x] Spanish support + punctuation
- [x] Full `transcribe-rs` local model registry (Parakeet, Canary, Cohere, SenseVoice, GigaAM, Moonshine, Whisper, Whisperfile)
- [x] 100-language target picker gated by the active model
- [x] Runtime model manager in the client — list, download, load/reload and delete models
- [x] Per-file and aggregate download progress in the client
- [x] Configurable VAD settings in the UI (thresholds, frame size, padding)
- [x] Settings persistence across restarts (`shared_preferences`, localStorage on Web)
- [x] Audio recording (WAV/OGG) on the server, triggered by the client
- [x] Optional on-device session audio saving (WAV)
- [x] Browser session recording on Web (`MediaRecorder` → WebM download)
- [x] Session restart without crashes
- [x] Docker image on Hub
- [x] CI check that model download links still resolve
- [x] Landing + docs (this site) on GitHub Pages

## In Progress 🔄

- [ ] Export transcriptions (TXT, SRT)
- [ ] Model manager polish (size estimates and richer per-model metadata)

## Planned

- [ ] Authentication for remote deployments
- [ ] HTTPS/WSS reverse proxy guide (Caddy/Nginx + Tailscale)
- [ ] PWA packaging for Web App
- [ ] i18n for docs (en/es)

Contributions welcome — see [GitHub](https://github.com/lutgaru/Sinsajo).
