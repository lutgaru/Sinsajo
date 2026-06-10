// lib/services/audio_service.dart
//
// Graba audio del micrófono, aplica VAD energético simple,
// y emite chunks PCM int16 listos para enviar por WebSocket.

import 'dart:async';
import 'dart:typed_data';
import 'package:record/record.dart';

/// Configuración de grabación
const int kSampleRate  = 16000;   // Hz — lo que espera Whisper
const int kChannels    = 1;       // Mono
const int kBitDepth    = 16;      // int16

/// VAD — umbral de energía (0.0 – 1.0 normalizado aprox.)
const double kVadThreshold    = 0.02;
/// Silencio mínimo para considerar fin de utterance (ms)
const int    kSilenceMs       = 800;
/// Chunk mínimo con voz para enviar (ms)
const int    kMinSpeechMs     = 300;

class AudioChunk {
  final Uint8List pcmBytes;  // raw PCM int16 LE
  final bool isFinal;        // true = fin de utterance (silencio detectado)
  AudioChunk(this.pcmBytes, {this.isFinal = false});
}

class AudioService {
  final AudioRecorder _recorder = AudioRecorder();

  StreamController<AudioChunk>? _chunkController;
  StreamSubscription<Uint8List>? _rawSub;

  // VAD state
  final List<int> _speechBuffer = [];
  int _silenceCount = 0;
  bool _inSpeech    = false;

  // Bytes por "tick" de silencio (50 ms a 16kHz int16)
  static const int _tickBytes = kSampleRate * 2 * 50 ~/ 1000;

  Stream<AudioChunk> get chunks =>
      _chunkController!.stream;

  Future<bool> get hasPermission async =>
      await _recorder.hasPermission();

  // ────────────────────────────────────────────────
  // Start / Stop
  // ────────────────────────────────────────────────

  Future<void> start() async {
    _chunkController = StreamController<AudioChunk>.broadcast();
    _speechBuffer.clear();
    _silenceCount = 0;
    _inSpeech     = false;

    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: kSampleRate,
        numChannels: kChannels,
        bitRate: kSampleRate * kBitDepth * kChannels,
      ),
    );

    _rawSub = stream.listen(
      _onRawAudio,
      onError: (e) => _chunkController?.addError(e),
      onDone:  () => _flush(isFinal: true),
    );
  }

  Future<void> stop() async {
    await _rawSub?.cancel();
    await _recorder.stop();
    _flush(isFinal: true);
    await _chunkController?.close();
  }

  // ────────────────────────────────────────────────
  // VAD energético simple
  // ────────────────────────────────────────────────

  void _onRawAudio(Uint8List raw) {
    final samples = raw.buffer.asInt16List();

    // Energía RMS normalizada
    double sumSq = 0;
    for (final s in samples) {
      sumSq += (s / 32768.0) * (s / 32768.0);
    }
    final rms = sumSq > 0 ? (sumSq / samples.length) : 0.0;

    final isSpeech = rms > kVadThreshold;

    if (isSpeech) {
      _silenceCount = 0;
      if (!_inSpeech) _inSpeech = true;
      _speechBuffer.addAll(raw);
    } else {
      if (_inSpeech) {
        _silenceCount += raw.length;
        _speechBuffer.addAll(raw);   // incluye el silencio en el chunk

        final silenceMs = (_silenceCount / (kSampleRate * 2)) * 1000;
        if (silenceMs >= kSilenceMs) {
          _flush(isFinal: false);   // fin de utterance
        }
      }
    }
  }

  void _flush({required bool isFinal}) {
    final minBytes = kSampleRate * 2 * kMinSpeechMs ~/ 1000;

    if (_speechBuffer.length >= minBytes) {
      final chunk = Uint8List.fromList(_speechBuffer);
      _chunkController?.add(AudioChunk(chunk, isFinal: isFinal));
    }

    _speechBuffer.clear();
    _silenceCount = 0;
    _inSpeech     = false;
  }

  void dispose() {
    _rawSub?.cancel();
    _recorder.dispose();
    _chunkController?.close();
  }
}
