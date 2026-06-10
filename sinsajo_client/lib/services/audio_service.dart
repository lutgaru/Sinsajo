import 'dart:async';
import 'dart:typed_data';
import 'package:record/record.dart';
import 'package:vad/vad.dart';

const int kSampleRate = 16000;
const int kChannels   = 1;
const int kBitDepth   = 16;

class AudioChunk {
  final Uint8List pcmBytes;
  final bool isFinal;
  AudioChunk(this.pcmBytes, {this.isFinal = false});
}

class AudioService {
  final AudioRecorder _recorder = AudioRecorder();
  StreamController<AudioChunk>? _chunkController;

  VadHandler?  _vadHandler;
  StreamSubscription? _speechEndSub;
  StreamSubscription? _errorSub;
  bool _isStopping = false;

  double gain = 1.0;

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
      ),
    );

    await _vadHandler!.startListening(
      audioStream: stream,
      model: 'v5',
      frameSamples: 512,
      positiveSpeechThreshold: 0.5,
      negativeSpeechThreshold: 0.38,
      redemptionFrames: 4,
      preSpeechPadFrames: 2,
      minSpeechFrames: 3,
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
    _chunkController?.add(AudioChunk(Uint8List(0), isFinal: true));
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
      pcm16[i] = (samples[i] * gain * 32767).clamp(-32768, 32767).toInt();
    }
    return Uint8List.view(pcm16.buffer);
  }
}
