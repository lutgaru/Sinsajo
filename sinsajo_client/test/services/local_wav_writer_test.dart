import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinsajo_client/services/local_wav_writer.dart';

void main() {
  group('LocalWavWriter', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('sinsajo_wav_test');
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    Future<LocalWavWriter> openWriter({String fileName = 's.wav'}) async {
      final writer = await createLocalWavWriter(
        directoryPath: tempDir.path,
        fileName: fileName,
      );
      await writer.open();
      return writer;
    }

    Uint8List pcm(int length, [int fill = 1]) =>
        Uint8List.fromList(List.filled(length, fill));

    test('writes a valid WAV header with patched sizes on finalize', () async {
      final writer = await openWriter();
      await writer.append(pcm(3200));
      await writer.finalize();

      final file = File(writer.path);
      expect(await file.exists(), isTrue);
      final bytes = await file.readAsBytes();
      expect(bytes.length, 44 + 3200);

      // RIFF....WAVE / fmt / data markers
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
      expect(String.fromCharCodes(bytes.sublist(12, 16)), 'fmt ');
      expect(String.fromCharCodes(bytes.sublist(36, 40)), 'data');

      final header = ByteData.sublistView(bytes, 0, 44);
      expect(header.getUint32(4, Endian.little), 36 + 3200);
      expect(header.getUint16(20, Endian.little), 1); // PCM
      expect(header.getUint16(22, Endian.little), 1); // mono
      expect(header.getUint32(24, Endian.little), 16000);
      expect(header.getUint16(34, Endian.little), 16);
      expect(header.getUint32(40, Endian.little), 3200);
    });

    test('concatenates multiple chunks in order as one file', () async {
      final writer = await openWriter();
      await writer.append(pcm(100, 0x11));
      await writer.append(pcm(200, 0x22));
      await writer.append(pcm(300, 0x33));
      expect(writer.dataBytes, 600);
      await writer.finalize();

      final bytes = await File(writer.path).readAsBytes();
      expect(bytes.length, 44 + 600);
      expect(bytes.sublist(44, 144), everyElement(0x11));
      expect(bytes.sublist(144, 344), everyElement(0x22));
      expect(bytes.sublist(344, 644), everyElement(0x33));
    });

    test('empty session finalizes to a valid 44-byte file', () async {
      final writer = await openWriter();
      await writer.finalize();

      final bytes = await File(writer.path).readAsBytes();
      expect(bytes.length, 44);
      final header = ByteData.sublistView(bytes);
      expect(header.getUint32(4, Endian.little), 36);
      expect(header.getUint32(40, Endian.little), 0);
    });

    test('append after finalize is ignored and never throws', () async {
      final writer = await openWriter();
      await writer.append(pcm(100));
      await writer.finalize();
      await writer.append(pcm(100));
      await writer.finalize();

      final bytes = await File(writer.path).readAsBytes();
      expect(bytes.length, 44 + 100);
    });

    test('discard deletes the session file', () async {
      final writer = await openWriter();
      await writer.append(pcm(100));
      final path = writer.path;
      await writer.discard();

      expect(await File(path).exists(), isFalse);
    });

    test('pause/resume pattern keeps a single file', () async {
      final writer = await openWriter();
      await writer.append(pcm(100));
      await writer.flush(); // pause
      await writer.append(pcm(100)); // resume
      await writer.finalize();

      final bytes = await File(writer.path).readAsBytes();
      expect(bytes.length, 44 + 200);
    });
  });
}
