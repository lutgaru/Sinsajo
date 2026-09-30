// No-op [LocalWavWriter] for Web (dart:io is unavailable).
import 'dart:typed_data';

import 'local_wav_writer.dart';

/// Must match the signature used by `local_wav_writer.dart` and the io file.
Future<LocalWavWriter> createWriter({
  required String directoryPath,
  required String fileName,
  int sampleRate = 16000,
  int channels = 1,
  int bitsPerSample = 16,
}) async =>
    _NoopLocalWavWriter();

class _NoopLocalWavWriter implements LocalWavWriter {
  @override
  String get path => '';

  @override
  bool get isOpen => false;

  @override
  int get dataBytes => 0;

  @override
  Future<void> open() async {}

  @override
  Future<void> append(Uint8List pcm) async {}

  @override
  Future<void> flush() async {}

  @override
  Future<void> finalize() async {}

  @override
  Future<void> discard() async {}
}
