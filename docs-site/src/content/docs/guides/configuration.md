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
| `--model` | prompt | `ParakeetTDT` / `Canary180M` |
| `--autodownload-model` | false | Download if missing |
| `--port` | 8765 | WebSocket port |
| `--model-dir` | ./models | Model storage |
| `--records-dir` | ./records | Recordings output |

Env / file: `sinsajo-config.json` persists last chosen model.

## Client Settings (in-app)

- **Server IP** — `kWsUrl` default; overridden in Settings UI
- **Target language** — `en/es/fr/de/pt` (enabled per `model_info.languages`)
- **Save audio** — toggle + format `wav/ogg`
- **Microphone gain / source**

Code default:

```dart
const String kWsUrl = 'ws://192.168.1.100:8765';
```

## VAD Tuning

In `audio_service.dart` via `VadHandler.startListening`:

```dart
positiveSpeechThreshold: 0.5, // start
negativeSpeechThreshold: 0.35, // stop
redemptionFrames: 8,          // silence to end utterance
preSpeechPadFrames: 1,
minSpeechFrames: 3,
frameSamples: 512, // 32ms
```

Try: `0.3 / 0.2 / 12` for quiet speakers or long pauses.

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
