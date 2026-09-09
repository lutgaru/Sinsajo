---
title: Protocol
description: WebSocket message formats.
---

All control messages are JSON over WebSocket. Audio is binary PCM.

## Client → Server

**Start session:**

```json
{
  "type": "start",
  "sample_rate": 16000,
  "save_audio": true,
  "format": "wav",
  "target_language": "es"
}
```

- `save_audio`: bool, save recording on `clean`
- `format`: `wav` | `ogg`
- `target_language`: `en|es|fr|de|pt` — translated if model supports, otherwise ignored

**Audio chunks:** Binary `PCM 16-bit mono @ 16kHz` (only speech frames passed through VAD)

**Stop / Clean:**

```json
{"type": "stop"}
{"type": "clean"}
```

`clean` = `stop` + save file to `records/`.

## Server → Client

**Transcription:**

```json
{"type": "transcription", "text": "..."}
```

Also accepted by client: `partial`, `final`.

**Status / Error / Model info:**

```json
{"type": "status", "message": "ready"}
{"type": "error", "message": "..."}
{"type": "model_info", "model": "Canary180M", "languages": ["en","es","fr","de","pt"]}
```

`model_info` is sent on connect. Client uses it to show active model and enable only supported languages in Settings.

## Example flow

```
Client                                    Server
  | -- {"type":"start", ...} -------------> |
  | -- [binary PCM chunk] ----------------> |
  | <-- {"type":"transcription","text":"hola"} |
  | -- [binary PCM chunk] ----------------> |
  | <-- {"type":"transcription","text":"hola mundo"} |
  | -- {"type":"clean"} ------------------> |
  | <-- {"type":"status","message":"saved records/..wav"} |
```
