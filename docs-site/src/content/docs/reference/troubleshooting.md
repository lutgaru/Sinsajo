---
title: Troubleshooting
description: Common issues and fixes.
---

## No transcriptions showing

Server logs show text but client doesn't: check `transcription_provider.dart` listens for `transcription` / `partial` / `final`:

```dart
case 'transcription':
case 'partial':
case 'final':
  // handle text
```

## App crashes on restart

Ensure `AudioService._cleanup()` disposes `VadHandler`:

```dart
Future<void> _cleanup() async {
  await _stopVad();
  await _chunkController?.close();
}
```

## VAD not detecting voice

Adjust thresholds in `audio_service.dart`:

```dart
positiveSpeechThreshold: 0.3,
negativeSpeechThreshold: 0.2,
minSpeechFrames: 2,
```

Lower thresholds for quiet speakers.

## Connection failed

1. Server running? `curl -i ws://localhost:8765` or check logs
2. Firewall allows `8765`
3. Same network / correct `kWsUrl` IP
4. For Web: must be HTTPS page + `wss://` if server behind TLS; browsers block insecure `ws://` from HTTPS

## Slow transcription (>500ms)

- Use Int8 model (default is Int8)
- Enable CUDA/DirectML via `transcribe-rs`
- Reduce chunk size in VAD config
- Try `--model Canary180M` (180M vs 600M)

## Models not downloading

Check `models/` permissions and HuggingFace connectivity. Run with `--model-dir` to an empty writable dir and `--autodownload-model`.

## APK not installing

Enable "Install unknown apps" on Android. Release APKs are signed with debug keystore by default — for production, configure signing in `android/app/build.gradle`.
