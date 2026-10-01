// No-op [WebSessionRecorder] for non-Web platforms.
import 'web_session_recorder.dart';

/// Must match the signature used by `web_session_recorder.dart`.
WebSessionRecorder createRecorder() => _NoopWebSessionRecorder();

class _NoopWebSessionRecorder implements WebSessionRecorder {
  @override
  bool get isActive => false;

  @override
  Future<void> start() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<String?> stopAndDownload() async => null;

  @override
  Future<void> discard() async {}
}
