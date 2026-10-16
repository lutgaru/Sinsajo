<p align="center">
  <img src="sinsajo_client/web/sinsajo.svg" alt="Sinsajo Logo" width="200">
</p>

# Sinsajo - Real-Time Local Voice Transcription

A self-hosted real-time voice transcription system that converts speech to text using local AI models. Built with **Flutter** (client) and **Rust** (server), featuring Voice Activity Detection (VAD) and support for all local engines from [`transcribe-rs`](https://github.com/cjpais/transcribe-rs): **Parakeet TDT 0.6B**, **Canary** (180M Flash / 1B Flash / 1B v2), **Cohere**, **SenseVoice**, **GigaAM**, **Moonshine** (+ streaming), **Whisper** and **Whisperfile** for fast, accurate transcription.

![Architecture](https://img.shields.io/badge/Architecture-Client%2FServer-blue)
![Language](https://img.shields.io/badge/Language-Spanish%20%2F%20English-green)
![Privacy](https://img.shields.io/badge/Privacy-100%25%20Local-brightgreen)

> **Docs & Landing:** https://lutgaru.github.io/Sinsajo/ &nbsp;|&nbsp; **Web App:** https://lutgaru.github.io/Sinsajo/app/ &nbsp;|&nbsp; **Downloads:** [Releases](https://github.com/lutgaru/Sinsajo/releases)

## 🎯 Features

- ✅ **Real-time transcription** - See text as you speak
- ✅ **100% offline** - No cloud services, complete privacy
- ✅ **Voice Activity Detection** - Only sends speech segments (saves bandwidth)
- ✅ **Low latency** - ~150-300ms end-to-end
- ✅ **Multi-platform** - Android, iOS, Desktop (Flutter)
- ✅ **Spanish support** - Native Spanish transcription with punctuation
- ✅ **Target language selection** - Choose the output language from the client settings; translation is applied by models that support it, and the client only enables the languages the active server model advertises (up to 100 languages on Whisper/Whisperfile, 25 on Canary 1B v2)
- ✅ **Self-hosted** - Run on your own hardware
- ✅ **Audio recording** - Saves session audio (WAV/OGG) to the server, configurable from the client settings; optionally also saves VAD speech as a WAV file on the client device for listen-back, or records the session in the browser (WebM download) on Web

## 🏗️ Architecture

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
│  AudioService   │                             │  Parakeet /      │
│  + vad package  │                             │  Canary / Cohere │
│  (ML-based)     │                             │  SenseVoice /    │
└─────────────────┘                             │  GigaAM /        │
                                                │  Moonshine /     │
                                                │  Whisper*        │
                                                └──────────────────┘
```

### Data Flow

1. **Audio Capture** - Flutter records PCM 16-bit @ 16kHz
2. **Voice Activity Detection** - Silero VAD v5 (ML-based) detects speech via ONNX Runtime
3. **WebSocket Transmission** - Sends only speech chunks (not silence)
4. **Transcription** - Rust server processes with the selected local model (Parakeet, Canary, Cohere, SenseVoice, GigaAM, Moonshine, Whisper/Whisperfile*)
5. **Audio Recording** - Rust server saves session as WAV to configurable `records/` directory on clean
6. **Display** - Client shows transcribed text in real-time

### Protocol

**Client → Server:**
- `{"type": "start", "sample_rate": 16000, "save_audio": true, "format": "wav", "target_language": "es"}` - Start session with session-scoped audio save settings (`save_audio`: enable/disable, `format`: `wav` or `ogg`) and output `target_language` (BCP-47 code; the server validates it against the loaded model's supported languages, translation is applied by models that support it, otherwise used as a hint or ignored)
- Binary PCM chunks - Audio data
- `{"type": "stop"}` - End session
- `{"type": "clean"}` - End session and save recorded audio as `wav`/`ogg` file

**Server → Client:**
- `{"type": "transcription", "text": "..."}` - Transcribed text
- `{"type": "status", "message": "ready"}` - Status updates
- `{"type": "error", "message": "..."}` - Error messages
- `{"type": "model_info", "model": "Canary1BV2", "languages": ["bg", "hr", "cs", ...]}` - Sent on connect; the loaded model and the target languages it supports (the client shows the model in Settings and enables only the supported language options)

## 📦 Tech Stack

### Client (Flutter)
- **Framework**: Flutter 3.x + Material 3
- **State Management**: Riverpod 2.x
- **Audio**: `record` package
- **WebSocket**: `web_socket_channel`
- **VAD**: Silero VAD v5 via [`vad`](https://pub.dev/packages/vad) package (ML-based, ONNX Runtime)

### Server (Rust)
- **Runtime**: Tokio (async)
- **WebSocket**: `tokio-tungstenite`
- **ML**: `transcribe-rs` (ONNX Runtime; optional `whisper-cpp` / `whisperfile` features)
- **Models**: Parakeet TDT 0.6B, Canary 180M Flash / 1B Flash / 1B v2, Cohere (int4/int8), SenseVoice, GigaAM v3, Moonshine (tiny/base/base-es + tiny lang variants + streaming), Whisper (tiny-en/small)*, Whisperfile (small)*
- **Auto-download**: Models downloaded automatically from HuggingFace (or mirror tarballs for Moonshine/SenseVoice/Whisperfile) on startup

\* Whisper/Whisperfile backends require building with cargo features: `cargo run --release --features whisper-cpp -- --model WhisperSmall ...` or `--features whisperfile`. The default build is ONNX-only and stays lightweight.

## 🚀 Quick Start

### Prerequisites

- **Flutter** 3.0+ (for client)
- **Rust** 1.70+ (for server)

### 1. Clone the Repository

```bash
git clone https://github.com/yourusername/sinsajo.git
cd sinsajo
```

### 2. Setup Server (Rust)

```bash
# Navigate to server directory
cd server

# Build and run (auto-downloads ParakeetTDT model on first run)
cargo run --release -- --model ParakeetTDT --autodownload-model
```

The server will start on `ws://0.0.0.0:8765`

#### Run the server with Docker

The server is also published to Docker Hub as [lutgaru/sinsajo-server](https://hub.docker.com/r/lutgaru/sinsajo-server):

```bash
docker pull lutgaru/sinsajo-server:latest

# Run with default settings
docker run -p 8765:8765 \
  -v sinsajo_models:/app/models \
  -v sinsajo_records:/app/records \
  lutgaru/sinsajo-server:latest

# Run with a specific tag (e.g. a release)
docker push lutgaru/sinsajo-server:tagname
```

##### Docker Compose (recommended)

Create a `docker-compose.yml`:

```yaml
services:
  sinsajo-server:
    image: lutgaru/sinsajo-server:latest
    container_name: sinsajo-server
    ports:
      - "8765:8765"
    volumes:
      - sinsajo_models:/app/models
      - sinsajo_records:/app/records
    restart: unless-stopped

volumes:
  sinsajo_models:
  sinsajo_records:
```

Then start it with:

```bash
docker compose up -d
```

**CLI arguments:**

| Arg | Default | Description |
|-----|---------|-------------|
| `--model` | *(prompt)* | Model name (see Supported models below; e.g. `ParakeetTDT`, `Canary180M`, `Canary1BV2`, `CohereInt4`, `SenseVoice`, `GigaAM`, `MoonshineBase`, `WhisperSmall`, `WhisperfileSmall`) |
| `--autodownload-model` | `false` | Auto-download model if not found locally |
| `--port` | `8765` | WebSocket server port |
| `--model-dir` | `./models` | Directory to store model files |
| `--records-dir` | `./records` | Directory to save audio recordings (WAV/OGG) |

### 3. Setup Client (Flutter)

```bash
# Navigate to client directory
cd sinsajo_client

# Install dependencies
flutter pub get

# Update server IP in lib/providers/transcription_provider.dart
# Change: const String kWsUrl = 'ws://YOUR_SERVER_IP:8765';

# Run on device/emulator
flutter run
```

## ⚙️ Configuration

### Server Configuration

All server settings are configured via CLI arguments:

```bash
# Use Parakeet model on custom port with explicit paths
cargo run --release -- --model ParakeetTDT --autodownload-model --port 8080 --model-dir /data/models --records-dir /data/records

# Use Canary model (smaller, faster)
cargo run --release -- --model Canary180M --autodownload-model
```

If `--model` is omitted, the server checks for a saved config file (`sinsajo-config.json`), then falls back to an interactive prompt.

### Client Configuration

Edit `sinsajo_client/lib/providers/transcription_provider.dart`:

```dart
// Update server IP address
const String kWsUrl = 'ws://192.168.1.100:8765';  // ← Your server IP
```

Other client options (microphone gain, audio source, server-side audio saving, client-side audio saving, VAD tuning, target language, server IP) are configured from the in-app Settings screen and persist across restarts (localStorage on Web).

### VAD Configuration

VAD is handled by the [`vad`](https://pub.dev/packages/vad) package (Silero VAD v5 via ONNX Runtime). Parameters are passed to `VadHandler.startListening()` in `sinsajo_client/lib/services/audio_service.dart`:

```dart
await _vadHandler.startListening(
  model: 'v5',                          // Silero VAD v5
  frameSamples: 512,                     // 32ms frames
  positiveSpeechThreshold: 0.5,          // Probability threshold to start speech
  negativeSpeechThreshold: 0.35,         // Probability threshold to end speech
  redemptionFrames: 8,                   // Silence frames needed to end utterance
  preSpeechPadFrames: 1,                 // Frames of pre-roll before speech
  minSpeechFrames: 3,                    // Minimum speech frames to emit
);
```

**Tuning tips:**
- Lower `positiveSpeechThreshold` (0.3) for quieter voices
- Lower `negativeSpeechThreshold` (0.2) to keep segments longer
- Increase `redemptionFrames` (12) to avoid cutting pauses within speech

## 📊 Performance

| Metric | Value |
|--------|-------|
| **Latency** | ~150-300ms (chunk → text) |
| **CPU Usage** | ~20-40% (1 core) |
| **RAM Usage** | ~500MB (Int8 model) |
| **Accuracy** | ~95% (clean Spanish) |
| **Bandwidth** | ~256KB/s (PCM audio) |

## 🎮 Usage

1. **Start the server** on your machine:
   ```bash
   cd server && cargo run --release -- --autodownload-model
   ```

2. **Launch the Flutter app** on your device

3. **Tap the microphone button** to start recording

4. **Speak naturally** - the app will:
   - Detect when you're speaking (VAD)
   - Send only speech chunks to the server
   - Display transcribed text in real-time

5. **Tap stop** to end the session

6. **Copy or clear** the transcription using the bottom buttons

## 🔧 Troubleshooting

### No transcriptions showing

**Problem**: Server logs show transcription but client doesn't display it

**Solution**: Check that the client listens for `"transcription"` message type:

```dart
// In transcription_provider.dart
case 'transcription':  // ← Must match server message type
case 'partial':
case 'final':
  // Handle text
```

### App crashes when restarting recording

**Problem**: App crashes when pressing stop then start again

**Solution**: Ensure `AudioService._cleanup()` properly disposes the `VadHandler`:

```dart
Future<void> _cleanup() async {
  await _stopVad();
  await _chunkController?.close();
}
```

### VAD not detecting voice

**Problem**: No chunks are sent even when speaking

**Solution**: Adjust VAD probability thresholds passed to `VadHandler.startListening()`:

```dart
positiveSpeechThreshold: 0.3,   // Lower for quieter speakers
negativeSpeechThreshold: 0.2,   // Lower to keep segments longer
minSpeechFrames: 2,             // Lower for faster response
```

### Server connection failed

**Problem**: Client shows "Connection failed"

**Solution**:
1. Verify server is running: `curl ws://localhost:8765`
2. Check firewall allows port 8765
3. Ensure client and server are on same network
4. Update `kWsUrl` with correct server IP

### Slow transcription

**Problem**: High latency (>500ms)

**Solution**:
1. Use Int8 quantized model (faster, slightly less accurate)
2. Enable GPU acceleration (CUDA/DirectML)
3. Reduce chunk size in VAD config
4. Use smaller model: `--model Canary180M` (180M vs 600M parameters)

## 📁 Project Structure

```
sinsajo/
├── sinsajo_client/              # Flutter client (Android, iOS, Web)
│   ├── lib/
│   │   ├── main.dart           # App entry point
│   │   ├── providers/
│   │   │   └── transcription_provider.dart  # State management
│   │   ├── screens/
│   │   │   └── transcription_screen.dart    # UI
│   │   └── services/
│   │       ├── audio_service.dart  # VAD + recording
│   │       └── ws_service.dart     # WebSocket client
│   ├── pubspec.yaml
│   └── README.md
│
├── server/                      # Rust server
│   ├── src/
│   │   ├── main.rs             # WebSocket + transcription
│   │   ├── config.rs           # Model definitions & config persistence
│   │   └── model_downloader.rs # HuggingFace auto-download
│   ├── models/                  # Downloaded ONNX models
│   ├── Cargo.toml
│   └── Dockerfile
│
├── docs-site/                   # Astro Starlight landing + docs -> GitHub Pages
│   ├── src/content/docs/        # Landing (index.mdx) + guides + reference
│   ├── astro.config.mjs         # site: https://lutgaru.github.io/Sinsajo/
│   └── public/sinsajo.svg
│
└── README.md                    # This file
```

### 🌐 Landing & Docs (docs-site)

Modern static site (Astro + Starlight) deployed to GitHub Pages together with the Flutter Web app:

- `/` → landing + docs
- `/app/` → Flutter Web build
- `/releases` → APKs (GitHub Releases)

Local preview: `cd docs-site && npm ci && npm run dev` → http://localhost:4321/Sinsajo/

Deploy: push to `master` triggers `.github/workflows/docs.yml` — builds Astro + `flutter build web --base-href /Sinsajo/app/` and publishes to Pages.

## 🛠️ Development

### Adding New Models

Switch between supported models via `--model` (an unknown name prints the full list):

```bash
# Parakeet TDT 0.6B (larger, more accurate, English-only, default)
cargo run --release -- --model ParakeetTDT --autodownload-model

# Canary 180M Flash (smaller, faster, en/de/es/fr)
cargo run --release -- --model Canary180M --autodownload-model

# Canary 1B v2 (25 languages, incl. Portuguese)
cargo run --release -- --model Canary1BV2 --autodownload-model

# Whisper Small (multilingual, needs whisper-cpp feature)
cargo run --release --features whisper-cpp -- --model WhisperSmall --autodownload-model
```

#### Supported models

The default binary only includes the ONNX models. An unknown `--model` name prints the flags compiled into your binary, plus rebuild hints for feature-gated ones (`Whisper*` needs `--features whisper-cpp`, `Whisperfile*` needs `--features whisperfile`).

| Model flag | Engine | Languages | Notes |
|------------|--------|-----------|-------|
| `ParakeetTDT` | Parakeet TDT 0.6B v3 (int8) | en | English-only, most accurate |
| `Canary180M` | Canary 180M Flash (int8) | en, de, es, fr | Fast multilingual + translation |
| `Canary1BFlash` | Canary 1B Flash (int8) | en, de, es, fr | Larger Flash variant |
| `Canary1BV2` | Canary 1B v2 (int8) | 25 langs (incl. pt) | Widest Canary coverage |
| `CohereInt4` / `CohereInt8` | Cohere Transcribe | 14 langs | int4 default, smaller download |
| `SenseVoice` | SenseVoice Small (int8) | zh, en, ja, ko, yue | Tarball mirror auto-download |
| `GigaAM` | GigaAM v3 (int8) | ru | Russian-only |
| `MoonshineTiny` / `MoonshineBase` / `MoonshineBaseEs` | Moonshine | en / en / es | Base auto-downloads; others: place `encoder_model.onnx`, `decoder_model_merged.onnx`, `tokenizer.json` in `models/<dir>` |
| `MoonshineTinyAr/Zh/Ja/Ko/Uk/Vi` | Moonshine Tiny | ar/zh/ja/ko/uk/vi | Manual weight placement (same 3 files) |
| `MoonshineStreamingTinyEn` | Moonshine Streaming | en | Tarball mirror auto-download |
| `WhisperTinyEn` / `WhisperSmall` | Whisper (whisper.cpp) | en / 100 langs | Needs `--features whisper-cpp` |
| `WhisperfileSmall` | Whisperfile server | 100 langs | Needs `--features whisperfile`; spawns local server on port 8080 (`WHISPERFILE_PORT` overrides) |

The OpenAI remote engine from `transcribe-rs` is intentionally not wired in: Sinsajo is 100% offline by design and the remote API needs an API key plus async file uploads, which doesn't fit the real-time WebSocket path.

To add a new model, add a module under `server/src/model/` implementing the `Model` trait plus a `ModelDefinition` entry (HuggingFace repo + folder, direct URL, or tarball mirror).

### Enabling GPU Acceleration

```rust
use transcribe_rs::{set_ort_accelerator, OrtAccelerator};

// Enable CUDA (NVIDIA)
set_ort_accelerator(OrtAccelerator::Cuda);

// Or auto-detect best GPU
set_ort_accelerator(OrtAccelerator::Auto);
```

### Adding Translation

Canary supports selecting an output language via the client "Target language" setting (sent with the `start` message). On the server, the selection is forwarded as `target_language`:

```rust
let result = model.transcribe_with(
    &samples,
    &CanaryParams {
        language: Some("es".to_string()),      // Source language
        target_language: Some("en".to_string()), // Translate to English
        ..Default::default()
    },
)?;
```

When a target language is set, Canary pins both `language` and `target_language` to it, so same-language speech is transcribed natively and foreign speech is translated into the selected language. Canary Flash covers en/de/es/fr; Canary 1B v2 covers 25 languages (adds Portuguese among others). Parakeet is English-only and ignores the target language; Whisper/Whisperfile use it as the language hint.

## 📋 Roadmap

### Completed ✅
- [x] Real-time transcription
- [x] Voice Activity Detection
- [x] Multi-platform support
- [x] Spanish language support
- [x] Session restart without crashes

### In Progress 🔄
- [ ] Model switching UI (client)
- [x] Audio recording (WAV export)
- [ ] Export transcriptions (TXT, SRT)

## 🐛 Known Limitations

- Requires WiFi/LAN connection (no mobile data without port forwarding)
- Int8 model has ~2% lower accuracy than Float32
- Single language per session (no mixed languages)
- No authentication (local network only)
- First run downloads the model (~2-3 GB) from HuggingFace
- Model and ONNX Runtime loading takes ~2-3 seconds on startup

## 📄 License

This project is licensed under the GPLv3 license.License - see the [LICENSE](LICENSE) file for details.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📧 Contact

**Adrian Sanchez** - Senior Embedded Systems Engineer

- GitHub: [@lutgaru](https://github.com/lutgaru)
- Project Link: [https://github.com/lutgaru/Sinsajo](https://github.com/lutgaru/Sinsajo)

## 🙏 Acknowledgments

- [transcribe-rs](https://github.com/cjpais/transcribe-rs) - Rust ONNX transcription library
- [Canary](https://huggingface.co/ysdede/canary-180m-flash-onnx) - Fast speech recognition model
- [Flutter](https://flutter.dev/) - UI framework
- [Rust](https://www.rust-lang.org/) - Systems programming language

---

**Status**: ✅ Functional - MVP Complete  
**Version**: 1.0.0  
