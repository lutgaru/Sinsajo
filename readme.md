# Sinsajó - Real-Time Local Voice Transcription

A self-hosted real-time voice transcription system that converts speech to text using local AI models. Built with **Flutter** (client) and **Rust** (server), featuring Voice Activity Detection (VAD) and the **Canary 180M Flash** model for fast, accurate transcription.

![Architecture](https://img.shields.io/badge/Architecture-Client%2FServer-blue)
![Language](https://img.shields.io/badge/Language-Spanish%20%2F%20English-green)
![Privacy](https://img.shields.io/badge/Privacy-100%25%20Local-brightgreen)

## 🎯 Features

- ✅ **Real-time transcription** - See text as you speak
- ✅ **100% offline** - No cloud services, complete privacy
- ✅ **Voice Activity Detection** - Only sends speech segments (saves bandwidth)
- ✅ **Low latency** - ~150-300ms end-to-end
- ✅ **Multi-platform** - Android, iOS, Desktop (Flutter)
- ✅ **Spanish support** - Native Spanish transcription with punctuation
- ✅ **Self-hosted** - Run on your own hardware
- ✅ **Audio recording** - Saves session audio as WAV files on clean

## 🏗️ Architecture

```
┌─────────────────┐         WebSocket          ┌──────────────────┐
│  Flutter Client │ ◄─────────────────────────► │   Rust Server    │
│  (Dart/Silero)  │    PCM 16-bit / JSON       │ (transcribe-rs)  │
└─────────────────┘                             └──────────────────┘
       │                                                  │
       │ Silero VAD v5                                   │ ONNX Model
       │ (ONNX Runtime)                                  │
       ▼                                                  ▼
┌─────────────────┐                             ┌──────────────────┐
│  AudioService   │                             │  Canary 180M     │
│  + vad package  │                             │  Flash (Int8)    │
│  (ML-based)     │                             │                  │
└─────────────────┘                             └──────────────────┘
```

### Data Flow

1. **Audio Capture** - Flutter records PCM 16-bit @ 16kHz
2. **Voice Activity Detection** - Silero VAD v5 (ML-based) detects speech via ONNX Runtime
3. **WebSocket Transmission** - Sends only speech chunks (not silence)
4. **Transcription** - Rust server processes with Canary model
5. **Audio Recording** - Rust server saves session as WAV to `records/` on clean
6. **Display** - Client shows transcribed text in real-time

### Protocol

**Client → Server:**
- `{"type": "start", "sample_rate": 16000}` - Start session
- Binary PCM chunks - Audio data
- `{"type": "stop"}` - End session
- `{"type": "clean"}` - End session and save recorded audio as WAV

**Server → Client:**
- `{"type": "transcription", "text": "..."}` - Transcribed text
- `{"type": "status", "message": "ready"}` - Status updates
- `{"type": "error", "message": "..."}` - Error messages

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
- **ML**: `transcribe-rs` (ONNX Runtime)
- **Model**: Canary 180M Flash (Int8 quantized)

## 🚀 Quick Start

### Prerequisites

- **Flutter** 3.0+ (for client)
- **Rust** 1.70+ (for server)
- **Git LFS** (for model download)

### 1. Clone the Repository

```bash
git clone https://github.com/yourusername/sinsajo.git
cd sinsajo
```

### 2. Setup Server (Rust)

```bash
# Navigate to server directory
cd whisper-server

# Download the Canary model
mkdir -p models
cd models
git lfs install
git clone https://huggingface.co/ysdede/canary-180m-flash-onnx
cd ..

# Build and run
cargo run --release
```

The server will start on `ws://0.0.0.0:8765`

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

Edit `whisper-server/src/main.rs`:

```rust
// Change port
let addr = "0.0.0.0:8765";

// Change model path
let model = CanaryModel::load(
    &PathBuf::from("models/canary-180m-flash-onnx"),
    &Quantization::Int8,
)?;

// Change language (default: Spanish)
CanaryParams {
    language: Some("es".to_string()),  // "en" for English
    use_pnc: true,                      // Punctuation & capitalization
    use_itn: true,                      // Number normalization
    ..Default::default()
}
```

### Client Configuration

Edit `sinsajo_client/lib/providers/transcription_provider.dart`:

```dart
// Update server IP address
const String kWsUrl = 'ws://192.168.1.100:8765';  // ← Your server IP
```

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
   cd whisper-server && cargo run --release
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
4. Use smaller model (Canary 180M vs Parakeet 600M)

## 📁 Project Structure

```
sinsajo/
├── sinsajo_client/              # Flutter client
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
├── whisper-server/              # Rust server
│   ├── src/
│   │   └── main.rs             # WebSocket + transcription
│   ├── models/
│   │   └── canary-180m-flash-onnx/  # AI model
│   ├── Cargo.toml
│   └── README.md
│
└── README.md                    # This file
```

## 🛠️ Development

### Adding New Models

Replace Canary with other models from `transcribe-rs`:

```rust
// Use Parakeet (larger, more accurate)
use transcribe_rs::onnx::parakeet::{ParakeetModel, ParakeetParams};

let model = ParakeetModel::load(
    &PathBuf::from("models/parakeet-tdt-0.6b-v3-int8"),
    &Quantization::Int8,
)?;
```

### Enabling GPU Acceleration

```rust
use transcribe_rs::{set_ort_accelerator, OrtAccelerator};

// Enable CUDA (NVIDIA)
set_ort_accelerator(OrtAccelerator::Cuda);

// Or auto-detect best GPU
set_ort_accelerator(OrtAccelerator::Auto);
```

### Adding Translation

Canary supports translation between languages:

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

## 📋 Roadmap

### Completed ✅
- [x] Real-time transcription
- [x] Voice Activity Detection
- [x] Multi-platform support
- [x] Spanish language support
- [x] Session restart without crashes

### In Progress 🔄
- [ ] Model switching UI
- [x] Audio recording (WAV export)
- [ ] Export transcriptions (TXT, SRT)

### Planned 📅
- [ ] GPU acceleration (CUDA/DirectML)
- [ ] Audio compression (Opus codec)
- [ ] WebSocket authentication
- [ ] Multi-language support
- [ ] Offline mode (bundled server)
- [ ] Performance metrics dashboard

## 🐛 Known Limitations

- Requires WiFi/LAN connection (no mobile data without port forwarding)
- Int8 model has ~2% lower accuracy than Float32
- Single language per session (no mixed languages)
- No authentication (local network only)
- Model and ONNX Runtime loading takes ~2-3 seconds on first run

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