---
title: Configuration
description: Server CLI, client settings, VAD tuning.
---

## Server CLI

```bash
cargo run --release -- --help
# or
docker run lutgaru/sinsajo-server:latest --help
```

| Arg | Default | Description |
|-----|---------|-------------|
| `--model` | prompt | Model flag (see [Supported Models](/Sinsajo/reference/models/); e.g. `ParakeetTDT`, `Canary1BV2`, `WhisperSmall`) |
| `--autodownload-model` | false | Download if missing |
| `--port` | 8765 | WebSocket port |
| `--model-dir` | ./models | Model storage |
| `--records-dir` | ./records | Recordings output |

File: `sinsajo-config.json` persists the last chosen or manager-loaded model.

## Client Settings (in-app)

Settings are split into **Client** and **Server** tabs and persist across restarts.

- **Server IP** — `kWsUrl` default; overridden in Settings UI, with **Apply & reconnect**
- **Target language** — 100-language picker (enabled per `model_info.languages` of the active model)
- **Save audio on server** — toggle + format `wav/ogg`
- **Save audio on this device** — WAV per session on desktop/mobile
- **Record session audio (Web)** — WebM/Opus download via `MediaRecorder`
- **Microphone gain / source** (Android source options)
- **VAD tuning** — frame size, thresholds, padding and redemption frames
- **Model manager** — list/download/load/delete server models

See [Client](/Sinsajo/guides/client/#settings) and [Supported Models](/Sinsajo/reference/models/).

Code default:

```dart
const String kWsUrl = 'ws://192.168.1.100:8765';
```

## VAD Tuning

Defaults live in `settings_provider.dart` and are passed to `VadHandler.startListening`:

```dart
await _vadHandler.startListening(
  model: 'v5',
  positiveSpeechThreshold: 0.45, // start
  negativeSpeechThreshold: 0.35, // stop
  redemptionFrames: 7,           // silence to end utterance
  preSpeechPadFrames: 8,
  minSpeechFrames: 8,
  endSpeechPadFrames: 3,
  frameSamples: 512, // 32ms
);
```

Try `0.3 / 0.2 / 12` for quiet speakers or long pauses. All values are editable in **Settings → Client → Voice Activity Detection**.

## Audio recording

Client sends with `start`:

```json
{"type":"start","sample_rate":16000,"save_audio":true,"format":"wav","target_language":"es"}
```

Server saves on `clean` to `records/YYYY-MM-DD_HH-mm-ss.wav`.

## GitHub Pages deployment (docs-site)

Config in `astro.config.mjs`:

```js
site: 'https://lutgaru.github.io',
base: '/Sinsajo/',
```

If you add a custom domain, set `base: '/'` and add `public/CNAME`.

Flutter Web must use:

```bash
flutter build web --base-href /Sinsajo/app/
```
