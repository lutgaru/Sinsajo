// Streaming WAV writer seam.
//
// The real implementation lives in `local_wav_writer_io.dart` (dart:io) and
// a no-op fallback in `local_wav_writer_stub.dart` for Web, where dart:io
// is unavailable. This keeps `flutter build web` working while native
// platforms get real file output.
import 'dart:typed_data';

import 'local_wav_writer_stub.dart'
    if (dart.library.io) 'local_wav_writer_io.dart' as impl;

/// Writes 16-bit PCM speech bytes to a single `.wav` file, streaming
/// chunk-by-chunk so RAM stays flat no matter how long the session is.
abstract class LocalWavWriter {
  /// Absolute path of the session file.
  String get path;

  /// Whether the file is currently open for appending.
  bool get isOpen;

  /// Number of PCM data bytes appended so far.
  int get dataBytes;

  /// Creates parent directories and writes a placeholder WAV header.
  Future<void> open();

  /// Appends raw PCM16 bytes. No-op when closed. Never throws.
  Future<void> append(Uint8List pcm);

  /// Flushes OS buffers without closing.
  Future<void> flush();

  /// Patches the WAV header sizes and closes the file, keeping it on disk.
  Future<void> finalize();

  /// Closes (if open) and deletes the file. Used when discarding a session.
  Future<void> discard();
}

/// Creates the platform-appropriate writer. On Web this returns a no-op
/// writer; callers should additionally guard with `kIsWeb`.
Future<LocalWavWriter> createLocalWavWriter({
  required String directoryPath,
  required String fileName,
  int sampleRate = 16000,
  int channels = 1,
  int bitsPerSample = 16,
}) =>
    impl.createWriter(
      directoryPath: directoryPath,
      fileName: fileName,
      sampleRate: sampleRate,
      channels: channels,
      bitsPerSample: bitsPerSample,
    );
