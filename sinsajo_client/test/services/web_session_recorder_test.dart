import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinsajo_client/services/web_session_recorder.dart';

void main() {
  group('WebSessionRecorder seam', () {
    test('factory returns a recorder on every platform', () {
      expect(createWebSessionRecorder(), isNotNull);
    });

    test('off-web recorder is a safe no-op', () async {
      // On Web itself this returns the real MediaRecorder engine, which
      // needs a microphone and a user gesture — only exercise the stub.
      if (kIsWeb) return;

      final recorder = createWebSessionRecorder();
      expect(recorder.isActive, isFalse);

      await recorder.start();
      await recorder.pause();
      await recorder.resume();
      expect(await recorder.stopAndDownload(), isNull);
      await recorder.discard();
    });
  });
}
