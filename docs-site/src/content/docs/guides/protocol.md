---
title: Protocol
description: WebSocket message formats for sessions and the model manager.
---

All control messages are JSON over WebSocket. Audio is binary PCM.

## Client → Server

### Start session

```json
{
  "type": "start",
  "sample_rate": 16000,
  "save_audio": true,
  "format": "wav",
  "target_language": "es"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `sample_rate` | number | Informational; audio is always `16000` Hz |
| `save_audio` | bool | Save the recording when the session is cleaned |
| `format` | `wav` \| `ogg` | Recording format |
| `target_language` | BCP-47 string | Output language hint/translation target |

`target_language` is validated twice: against the global language union and against the loaded model's supported languages. Unsupported values are dropped before they reach the model. Canary translates into the target, Whisper/Whisperfile/Cohere/SenseVoice use it as a hint, and Parakeet/GigaAM/Moonshine ignore it.

### Audio chunks

Binary `PCM 16-bit mono @ 16 kHz` — only speech frames passed through VAD.

### Stop / Clean / Discard

```json
{"type": "stop"}
{"type": "clean"}
{"type": "discard"}
```

- `stop` ends the session and replies with `{"type":"status","message":"stopped"}`
- `clean` saves the buffer to `records/` (if `save_audio` is enabled), clears it, and replies `cleaned`
- `discard` clears the buffer without saving and replies `discarded`

## Model manager

The client can list, download, load and delete models at runtime. All commands share the same WebSocket and require a `model` field (except `list_models`). See [Supported Models](/Sinsajo/reference/models/) for the flags and languages behind each name.

```json
{"type": "list_models"}
{"type": "download_model", "model": "Canary1BV2"}
{"type": "load_model", "model": "Canary1BV2"}
{"type": "reload_model", "model": "Canary1BV2"}
{"type": "delete_model", "model": "MoonshineTiny"}
```

Rules enforced by the server:

- Model names are matched exactly, then case-insensitively
- Only **one** model operation runs at a time; a download cannot overlap a load or delete
- `load_model` fails if the model is not installed
- `delete_model` fails for the active model
- `reload_model` is an alias for `load_model`
- Loading a model sends `model_info` and persists the choice to `sinsajo-config.json`

## Server → Client

### Transcription

```json
{"type": "transcription", "text": "..."}
```

Also accepted by the client: `partial`, `final`.

### Status / Error

```json
{"type": "status", "message": "ready"}
{"type": "error", "message": "..."}
```

### Model info

Sent on connect and after a successful model load:

```json
{"type": "model_info", "model": "Canary1BV2", "languages": ["bg", "hr", "cs", "..."]}
```

The client shows the active model and enables only the advertised languages in Settings.

### Model list

Response to `list_models`, and sent again after every model action:

```json
{
  "type": "model_list",
  "active": "ParakeetTDT",
  "models": [
    {
      "name": "ParakeetTDT",
      "display": "Parakeet TDT 0.6b v3",
      "dir": "parakeet-tdt-0.6b-v3-onnx",
      "installed": true,
      "active": true,
      "files": 8
    }
  ]
}
```

| Field | Description |
|-------|-------------|
| `active` | Name of the loaded model |
| `models[].name` | Value to pass back in manager commands |
| `models[].display` | Human-readable label |
| `models[].dir` | Subdirectory under the model directory |
| `models[].installed` | All required files are present |
| `models[].active` | This is the currently loaded model |
| `models[].files` | Number of files the definition requires |

### Model action

Reports the lifecycle of a manager command:

```json
{"type": "model_action", "action": "load", "model": "Canary1BV2", "state": "started", "message": null}
```

- `action`: `download` \| `load` \| `delete`
- `state`: `started` \| `completed` \| `failed`
- `message`: optional detail (for example `"Model is already installed"`)

A failed action also sets the client's error banner. `completed`/`failed` is followed by a fresh `model_list`.

### Model download progress

Streamed while a `download_model` action runs:

```json
{
  "type": "model_download_progress",
  "model": "Canary1BV2",
  "file": "encoder-model.int8.onnx",
  "file_downloaded": 1048576,
  "file_total": 314572800,
  "file_complete": false,
  "downloaded": 2097152,
  "total": 943718400,
  "percent": 33,
  "files_done": 1,
  "files_total": 7
}
```

| Field | Description |
|-------|-------------|
| `file` | File currently being downloaded |
| `file_downloaded` / `file_total` | Bytes for the current file (`0` total when unknown) |
| `file_complete` | Last snapshot for this file before the next starts |
| `downloaded` / `total` | Aggregate bytes for the whole model |
| `percent` | Overall completion; each file is weighted equally |
| `files_done` / `files_total` | Files finished / files to fetch |

`percent` weights every file equally, so it can differ from `downloaded / total` when files have different sizes. `file_complete` prevents a finished file from being counted twice and keeps the client bar from jumping backwards. Older servers may only send a per-file `percent`; the client falls back to it when `files_total` is `0`.

## Example flows

### Transcription session

```
Client                                    Server
  | -- {"type":"start", ...} -------------> |
  | <-- {"type":"status","message":"ready"} |
  | -- [binary PCM chunk] ----------------> |
  | <-- {"type":"transcription","text":"hola"} |
  | -- [binary PCM chunk] ----------------> |
  | <-- {"type":"transcription","text":"hola mundo"} |
  | -- {"type":"clean"} ------------------> |
  | <-- {"type":"status","message":"cleaned"} |
```

### Model download

```
Client                                    Server
  | -- {"type":"download_model","model":"Canary1BV2"} --> |
  | <-- {"type":"model_action","state":"started", ...}     |
  | <-- {"type":"model_download_progress", ...}            |
  | <-- {"type":"model_download_progress", ...}            |
  | <-- {"type":"model_action","state":"completed", ...}   |
  | <-- {"type":"model_list", ...}                         |
  | -- {"type":"load_model","model":"Canary1BV2"} -------> |
  | <-- {"type":"model_info","model":"Canary1BV2", ...}    |
  | <-- {"type":"model_action","state":"completed", ...}   |
```
