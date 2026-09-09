---
title: Client (Flutter)
description: Flutter client — setup, VAD tuning, Web.
---

## Setup

```bash
cd sinsajo_client
flutter pub get
flutter run
```

Update the server URL:

```dart
// lib/providers/transcription_provider.dart
const String kWsUrl = 'ws://192.168.1.100:8765';
```

Other options (gain, audio source, `save_audio`, `target_language`, server IP) are in the in-app Settings screen.

## Voice Activity Detection

In `lib/services/audio_service.dart`:

```dart
await _vadHandler.startListening(
  model: 'v5',
  frameSamples: 512,
  positiveSpeechThreshold: 0.5,
  negativeSpeechThreshold: 0.35,
  redemptionFrames: 8,
  preSpeechPadFrames: 1,
  minSpeechFrames: 3,
);
```

**Tuning:**

- Lower `positiveSpeechThreshold` to 0.3 for quiet voices
- Lower `negativeSpeechThreshold` to 0.2 to keep segments longer
- Increase `redemptionFrames` to 12 to avoid cutting pauses
- Package: [`vad` (pub.dev)](https://pub.dev/packages/vad)

## Web build

```bash
flutter build web --release --base-href /Sinsajo/app/
```

This site merges the output into `docs-site/dist/app/` during GitHub Pages deploy. Locally, test with:

```bash
cd docs-site && npm run build
# copy flutter build to dist/app for preview
```

:::caution[Microphone on Web]
Browsers require HTTPS for `getUserMedia`. GitHub Pages provides this. If self-hosting elsewhere, ensure TLS.
VAD `onnxruntime-web` WASM must be served with correct MIME and COOP/COEP headers if you customize hosting.
:::

## Android APK

Built via GitHub Actions on tag `client/v*`:

```bash
flutter build apk --release
# output: build/app/outputs/flutter-apk/app-release.apk
```

Download from Releases — do not commit APKs to git. Share the release link or generate a QR in the docs.

## State

Riverpod 2.x manages WebSocket lifecycle and transcription state. Check `transcription_provider.dart` for `transcription`, `partial`, and `model_info` handlers.
