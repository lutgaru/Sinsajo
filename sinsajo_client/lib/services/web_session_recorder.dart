// Browser session-recording seam.
//
// The real implementation lives in `web_session_recorder_web.dart`
// (MediaRecorder via package:web) and a no-op fallback in
// `web_session_recorder_stub.dart` for non-Web platforms, where browser
// APIs don't exist. Selected with `dart.library.html` so `flutter build
// web` compiles the real engine and native/VM builds get the stub.
import 'web_session_recorder_stub.dart'
    if (dart.library.html) 'web_session_recorder_web.dart' as impl;

/// Records a transcription session in the browser.
///
/// Unlike the native WAV writer (which stores VAD-filtered speech), the
/// browser engine records the live microphone via MediaRecorder — the Web
/// platform gives us no way to tap the `record` plugin's mic stream, and
/// feeding VAD chunks into MediaRecorder would lag real time by design.
/// Files are delivered as a browser download on stop, since pages cannot
/// silently keep files on disk.
abstract class WebSessionRecorder {
  /// Whether a recording is currently open.
  bool get isActive;

  /// Opens the microphone and starts recording. Throws [StateError] when
  /// the browser can't record (no mic, denied permission, no MediaRecorder).
  Future<void> start();

  /// Pauses capture; [resume] continues into the same single file.
  Future<void> pause();

  /// Continues a paused capture.
  Future<void> resume();

  /// Stops capture, triggers the browser download, and returns the file
  /// name. Returns null when nothing was recording.
  Future<String?> stopAndDownload();

  /// Stops capture and throws the recording away (no download).
  Future<void> discard();
}

/// Creates the platform-appropriate recorder (no-op off Web).
WebSessionRecorder createWebSessionRecorder() => impl.createRecorder();
