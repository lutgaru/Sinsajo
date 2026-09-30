// Real dart:io implementation of [LocalWavWriter].
//
// Strategy (portable, constant RAM):
// - During the session, raw PCM16 bytes stream into `<name>.wav.part`
//   through an [IOSink] (order-preserving, OS-buffered — RAM stays flat
//   no matter how long the session is).
// - On [finalize], the part file is stream-copied in 64 KiB blocks behind
//   a freshly written WAV header with the now-known sizes, then deleted.
//
// NOTE: in-place header patching was deliberately avoided: opening an
// existing file with [FileMode.writeOnly] truncates it (verified), and
// [FileMode.append] forces end-of-file writes on POSIX, so neither can
// patch the RIFF sizes in place portably.
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'local_wav_writer.dart';

/// Must match the signature used by `local_wav_writer.dart` and the stub.
Future<LocalWavWriter> createWriter({
  required String directoryPath,
  required String fileName,
  int sampleRate = 16000,
  int channels = 1,
  int bitsPerSample = 16,
}) async =>
    _IoLocalWavWriter(
      file: File('$directoryPath/$fileName'),
      sampleRate: sampleRate,
      channels: channels,
      bitsPerSample: bitsPerSample,
    );

class _IoLocalWavWriter implements LocalWavWriter {
  _IoLocalWavWriter({
    required this.file,
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
  }) : partFile = File('${file.path}.part');

  final File file;
  final File partFile;
  final int sampleRate;
  final int channels;
  final int bitsPerSample;

  IOSink? _sink;
  int _dataBytes = 0;

  @override
  String get path => file.path;

  @override
  bool get isOpen => _sink != null;

  @override
  int get dataBytes => _dataBytes;

  @override
  Future<void> open() async {
    if (isOpen) return;
    await file.parent.create(recursive: true);
    _sink = partFile.openWrite();
    _dataBytes = 0;
  }

  @override
  Future<void> append(Uint8List pcm) async {
    final sink = _sink;
    if (sink == null || pcm.isEmpty) return;
    try {
      sink.add(pcm);
      _dataBytes += pcm.length;
    } catch (e) {
      debugPrint('[LocalAudio] ⚠️ append failed: $e');
    }
  }

  @override
  Future<void> flush() async {
    try {
      await _sink?.flush();
    } catch (e) {
      debugPrint('[LocalAudio] ⚠️ flush failed: $e');
    }
  }

  @override
  Future<void> finalize() async {
    final sink = _sink;
    _sink = null;
    if (sink == null) return;
    try {
      await sink.flush();
      await sink.close();
      await _assembleWav();
      debugPrint(
        '[LocalAudio] 💾 Saved ${file.path} (${_dataBytes}B PCM)',
      );
    } catch (e) {
      debugPrint('[LocalAudio] ⚠️ finalize failed: $e');
    }
  }

  @override
  Future<void> discard() async {
    final sink = _sink;
    _sink = null;
    try {
      await sink?.close();
    } catch (_) {
      // Best effort: file may be partially written.
    }
    for (final f in [partFile, file]) {
      try {
        if (await f.exists()) await f.delete();
      } catch (e) {
        debugPrint('[LocalAudio] ⚠️ discard failed: $e');
      }
    }
    _dataBytes = 0;
  }

  /// Writes the final WAV: real header (sizes now known) + streamed copy
  /// of the part file in fixed blocks, then removes the part file.
  Future<void> _assembleWav() async {
    final out = file.openWrite();
    try {
      out.add(_wavHeader(dataBytes: _dataBytes));
      if (await partFile.exists()) {
        await for (final block in partFile.openRead()) {
          out.add(block);
        }
      }
      await out.flush();
      await out.close();
    } catch (_) {
      try {
        await out.close();
      } catch (_) {}
      rethrow;
    }
    try {
      if (await partFile.exists()) await partFile.delete();
    } catch (e) {
      debugPrint('[LocalAudio] ⚠️ part cleanup failed: $e');
    }
  }

  Uint8List _wavHeader({required int dataBytes}) {
    final bytes = ByteData(44);
    // ChunkID "RIFF"
    bytes.setUint8(0, 0x52);
    bytes.setUint8(1, 0x49);
    bytes.setUint8(2, 0x46);
    bytes.setUint8(3, 0x46);
    // ChunkSize = 36 + dataBytes
    bytes.setUint32(4, 36 + dataBytes, Endian.little);
    // Format "WAVE"
    bytes.setUint8(8, 0x57);
    bytes.setUint8(9, 0x41);
    bytes.setUint8(10, 0x56);
    bytes.setUint8(11, 0x45);
    // Subchunk1ID "fmt "
    bytes.setUint8(12, 0x66);
    bytes.setUint8(13, 0x6D);
    bytes.setUint8(14, 0x74);
    bytes.setUint8(15, 0x20);
    bytes.setUint32(16, 16, Endian.little); // PCM subchunk size
    bytes.setUint16(20, 1, Endian.little); // AudioFormat = PCM
    bytes.setUint16(22, channels, Endian.little);
    bytes.setUint32(24, sampleRate, Endian.little);
    final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    bytes.setUint32(28, byteRate, Endian.little);
    bytes.setUint16(32, channels * bitsPerSample ~/ 8, Endian.little);
    bytes.setUint16(34, bitsPerSample, Endian.little);
    // Subchunk2ID "data"
    bytes.setUint8(36, 0x64);
    bytes.setUint8(37, 0x61);
    bytes.setUint8(38, 0x74);
    bytes.setUint8(39, 0x61);
    bytes.setUint32(40, dataBytes, Endian.little);
    return bytes.buffer.asUint8List();
  }
}
