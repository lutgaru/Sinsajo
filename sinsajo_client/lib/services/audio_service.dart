import 'dart:async';
import 'dart:typed_data';
import 'package:record/record.dart';
import 'package:vad/vad.dart';

const int kSampleRate = 16000;
const int kChannels = 1;
const int kBitDepth = 16;

class AudioChunk {
  final Uint8List pcmBytes;
  final bool isFinal;
  AudioChunk(this.pcmBytes, {this.isFinal = false});
}

class AudioService {
  final AudioRecorder _recorder = AudioRecorder();
  StreamController<AudioChunk>? _chunkController;

  VadHandler? _vadHandler;
  StreamSubscription? _speechEndSub;
  StreamSubscription? _errorSub;
  bool _isStopping = false;

  double gain = 1.0;
  double threshold = 0.15; // a partir de qué nivel comprime
  double ratio = 4.0; // cuánto comprime los picos (4:1)
  double makeupGain = 2; // ganancia aplicada después de comprimir
  double knee = 0.05; // transición suave en el threshold

  Stream<AudioChunk> get chunks => _chunkController!.stream;
  Future<bool> get hasPermission async => await _recorder.hasPermission();

  Future<void> start() async {
    await _cleanup();
    _isStopping = false;

    _chunkController = StreamController<AudioChunk>.broadcast();

    _vadHandler = VadHandler.create(isDebug: true);

    _speechEndSub = _vadHandler!.onSpeechEnd.listen((samples) {
      final pcmBytes = _doubleListToPcm16(samples);
      _chunkController?.add(AudioChunk(pcmBytes, isFinal: _isStopping));
    });

    _errorSub = _vadHandler!.onError.listen((err) {
      print('[VAD] Error: $err');
      _chunkController?.addError(err);
    });

    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: kSampleRate,
        numChannels: kChannels,
        autoGain: true,
      ),
    );

    await _vadHandler!.startListening(
      audioStream: stream,
      model: 'v5',
      frameSamples: 512,
      positiveSpeechThreshold: 0.45,
      negativeSpeechThreshold: 0.35,
      redemptionFrames: 7,
      preSpeechPadFrames: 8,
      minSpeechFrames: 8,
      endSpeechPadFrames: 3,
    );

    print('[Audio] Grabacion iniciada (Silero VAD v5)');
  }

  Future<void> clean() async {
    _isStopping = true;
    await _stopVad();
    _isStopping = false;
    print('[Audio] Estado limpiado');
  }

  Future<void> stop() async {
    _isStopping = true;
    await _recorder.stop();
    await _stopVad();
    await _chunkController?.close();
    print('[Audio] Grabacion detenida');
  }

  Future<void> _stopVad() async {
    await _speechEndSub?.cancel();
    _speechEndSub = null;
    await _errorSub?.cancel();
    _errorSub = null;
    if (_vadHandler != null) {
      await _vadHandler!.stopListening();
      await _vadHandler!.dispose();
      _vadHandler = null;
    }
  }

  Future<void> _cleanup() async {
    await _stopVad();
    await _chunkController?.close();
    _chunkController = null;
  }

  void dispose() {
    _isStopping = true;
    stop();
    _recorder.dispose();
  }

  Uint8List _doubleListToPcm16(List<double> samples) {
    final pcm16 = Int16List(samples.length);
    for (var i = 0; i < samples.length; i++) {
      final compressed = _compress(samples[i]);
      pcm16[i] = compressed.clamp(-1.0, 1.0).mul32767();
    }
    return Uint8List.view(pcm16.buffer);
  }

  double _compress(double x) {
    final abs = x.abs();
    double gainReduction = 1.0;
    final halfKnee = knee / 2;

    if (knee > 0 && abs > threshold - halfKnee && abs < threshold + halfKnee) {
      // zona de soft knee: transición suave
      final t = (abs - (threshold - halfKnee)) / knee;
      final effectiveRatio = 1.0 + (ratio - 1.0) * t * t;
      gainReduction = (threshold + (abs - threshold) / effectiveRatio) / abs;
    } else if (abs >= threshold + (knee > 0 ? halfKnee : 0)) {
      // encima del threshold: comprimir
      gainReduction = (threshold + (abs - threshold) / ratio) / abs;
    }

    return x * gainReduction * makeupGain;
  }
}

extension on double {
  int mul32767() => (this * 32767).round().clamp(-32768, 32767);
}
