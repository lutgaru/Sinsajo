// lib/services/audio_service.dart

import 'dart:async';
import 'dart:isolate';
import 'dart:math' show sqrt;
import 'dart:typed_data';
import 'package:record/record.dart';

const int kSampleRate = 16000;
const int kChannels   = 1;
const int kBitDepth   = 16;

const int    kWarmupMs       = 0;
const double kSnrMargin      = 3.5;
const double kAbsMinRms      = 0.008;
const double kAbsMaxRms      = 0.15;
const int    kSilenceMs      = 400;
const int    kMinSpeechMs    = 400;
const int    kCalibrationMs  = 1200;
const int    kHangoverFrames = 3;
const int    kIsolateBatchMs = 40;

class AudioChunk {
  final Uint8List pcmBytes;
  final bool isFinal;
  AudioChunk(this.pcmBytes, {this.isFinal = false});
}

sealed class _IsoMsg {}

class _AudioData extends _IsoMsg {
  final Uint8List bytes;
  _AudioData(this.bytes);
}

class _StopMsg extends _IsoMsg {}
class _CleanMsg extends _IsoMsg {}

sealed class _IsoReply {}

class _ChunkReady extends _IsoReply {
  final Uint8List bytes;
  final bool isFinal;
  _ChunkReady(this.bytes, {required this.isFinal});
}

class _VadLog extends _IsoReply {
  final String msg;
  _VadLog(this.msg);
}

class _VadProcessor {
  final SendPort _out;
  _VadProcessor(this._out);

  final List<int>    _speechBuf     = [];
  final List<double> _noiseHistory  = [];
  int    _silenceBytes  = 0;
  int    _hangover      = 0;
  bool   _inSpeech      = false;
  bool   _calibrated    = false;
  double _noiseFloor    = kAbsMinRms;
  int    _totalBytes    = 0;
  int    _calibBytes    = 0;

  static int get _targetCalibBytes => kSampleRate * 2 * kCalibrationMs ~/ 1000;
  static int get _warmupBytes      => kSampleRate * 2 * kWarmupMs ~/ 1000;
  static int get _minSpeechBytes   => kSampleRate * 2 * kMinSpeechMs ~/ 1000;

  double get _threshold =>
      (_noiseFloor * kSnrMargin).clamp(kAbsMinRms, kAbsMaxRms);

  void process(Uint8List raw) {
    _totalBytes += raw.length;

    if (_totalBytes <= _warmupBytes) {
      _speechBuf.addAll(raw);
      return;
    }

    if (!_calibrated) {
      _calibBytes += raw.length;
      _noiseHistory.add(_rms(raw));
      if (_calibBytes >= _targetCalibBytes) {
        final sorted = List<double>.from(_noiseHistory)..sort();
        final idx = (sorted.length * 0.75).toInt().clamp(0, sorted.length - 1);
        _noiseFloor = sorted[idx].clamp(kAbsMinRms, kAbsMaxRms);
        _calibrated = true;
        _noiseHistory.clear();
        _out.send(_VadLog(
          '[VAD] calibrado noise=${_noiseFloor.toStringAsFixed(4)}'
          ' umbral=${_threshold.toStringAsFixed(4)}'
        ));
      }
    }

    final rms      = _rms(raw);
    final isSpeech = rms > _threshold;

    if (_totalBytes % (kSampleRate * 2) < raw.length) {
      _out.send(_VadLog(
        '[VAD] rms=${rms.toStringAsFixed(4)}'
        ' thr=${_threshold.toStringAsFixed(4)}'
        ' speech=$isSpeech'
        ' buf=${_speechBuf.length ~/ (kSampleRate * 2 ~/ 1000)}ms'
      ));
    }

    if (isSpeech) {
      _silenceBytes = 0;
      _hangover     = kHangoverFrames;
      _inSpeech     = true;
      _speechBuf.addAll(raw);
    } else {
      if (_inSpeech || _hangover > 0) {
        _speechBuf.addAll(raw);
        _silenceBytes += raw.length;
        if (_hangover > 0) {
          _hangover--;
        } else {
          final silMs = (_silenceBytes / (kSampleRate * 2)) * 1000;
          if (silMs >= kSilenceMs) _flush(final_: false);
        }
      }
      _noiseFloor = (_noiseFloor * 0.97 + rms * 0.03).clamp(kAbsMinRms, kAbsMaxRms);
    }
  }

  void reset() {
    _speechBuf.clear();
    _noiseHistory.clear();
    _silenceBytes = 0;
    _hangover     = 0;
    _inSpeech     = false;
    _calibrated   = false;
    _noiseFloor   = kAbsMinRms;
    _totalBytes   = 0;
    _calibBytes   = 0;
  }

  void finish() => _flush(final_: true);

  void _flush({required bool final_}) {
    if (_speechBuf.length >= _minSpeechBytes) {
      _out.send(_ChunkReady(Uint8List.fromList(_speechBuf), isFinal: final_));
      _out.send(_VadLog('[VAD] flush ${_speechBuf.length ~/ (kSampleRate * 2 ~/ 1000)}ms isFinal=$final_'));
    } else if (_speechBuf.isNotEmpty) {
      _out.send(_VadLog('[VAD] flush descartado: muy corto (${_speechBuf.length} bytes)'));
    }
    _speechBuf.clear();
    _silenceBytes = 0;
    _hangover     = 0;
    _inSpeech     = false;
  }

  double _rms(Uint8List raw) {
    if (raw.length < 2) return 0.0;
    final copy = Uint8List.fromList(raw);
    final s = copy.buffer.asInt16List();
    if (s.isEmpty) return 0.0;
    double sum = 0.0;
    for (final v in s) { final n = v / 32768.0; sum += n * n; }
    return sqrt(sum / s.length);
  }
}

void _vadIsolate(SendPort outPort) {
  final recv    = ReceivePort();
  final vad     = _VadProcessor(outPort);
  final batchBuf = <int>[];
  final batchTarget = kSampleRate * 2 * kIsolateBatchMs ~/ 1000;

  outPort.send(recv.sendPort);

  recv.listen((msg) {
    if (msg is _AudioData) {
      batchBuf.addAll(msg.bytes);
      if (batchBuf.length >= batchTarget) {
        vad.process(Uint8List.fromList(batchBuf));
        batchBuf.clear();
      }
    } else if (msg is _StopMsg) {
      if (batchBuf.isNotEmpty) {
        vad.process(Uint8List.fromList(batchBuf));
        batchBuf.clear();
      }
      vad.finish();
      recv.close();
    } else if (msg is _CleanMsg) {
      batchBuf.clear();
      vad.reset();
    }
  });
}

class AudioService {
  final AudioRecorder _recorder = AudioRecorder();
  StreamController<AudioChunk>? _chunkController;
  StreamSubscription<Uint8List>? _rawSub;

  Isolate?   _isolate;
  SendPort?  _isoIn;
  ReceivePort? _isoOut;
  StreamSubscription? _isoOutSub;

  Stream<AudioChunk> get chunks => _chunkController!.stream;
  Future<bool> get hasPermission async => await _recorder.hasPermission();

  Future<void> start() async {
    // Limpiar estado anterior si existe
    await _cleanup();

    _chunkController = StreamController<AudioChunk>.broadcast();

    _isoOut = ReceivePort();
    _isolate = await Isolate.spawn(_vadIsolate, _isoOut!.sendPort);

    final completer = Completer<SendPort>();
    _isoOutSub = _isoOut!.listen((msg) {
      if (!completer.isCompleted && msg is SendPort) {
        completer.complete(msg);
        return;
      }
      if (msg is _ChunkReady) {
        _chunkController?.add(AudioChunk(msg.bytes, isFinal: msg.isFinal));
      } else if (msg is _VadLog) {
        print(msg.msg);
      }
    });
    _isoIn = await completer.future;

    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: kSampleRate,
        numChannels: kChannels,
        bitRate: kSampleRate * kBitDepth * kChannels,
      ),
    );

    _rawSub = stream.listen(
      (raw) => _isoIn?.send(_AudioData(raw)),
      onError: (e) => _chunkController?.addError(e),
      onDone:  () => _isoIn?.send(_StopMsg()),
    );
    print('[Audio] Grabacion iniciada');
  }

  Future<void> clean() async {
    _isoIn?.send(_CleanMsg());
    _isoIn?.send(_StopMsg());

    await Future.delayed(const Duration(milliseconds: 50));

    await _cleanup();
    print('[Audio] Estado limpiado');
  }

  Future<void> stop() async {
    await _rawSub?.cancel();
    _rawSub = null;

    await _recorder.stop();

    await clean();
    print('[Audio] Grabacion detenida');
  }

  Future<void> _cleanup() async {
    await _isoOutSub?.cancel();
    _isoOutSub = null;
    
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    
    _isoOut?.close();
    _isoOut = null;
    
    _isoIn = null;
    
    await _chunkController?.close();
    _chunkController = null;
  }

  void dispose() {
    stop();
    _recorder.dispose();
  }
}