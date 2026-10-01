// Real Web implementation of [WebSessionRecorder] using MediaRecorder.
//
// Pipeline: own `getUserMedia` mic stream → MediaRecorder (opus/webm,
// mp4 fallback for Safari) with a 1 s timeslice so encoded data flows
// incrementally and RAM stays flat. Pause/resume map 1:1 to keep a single
// file per session. On stop the parts are assembled into a Blob and
// delivered via an anchor download — pages cannot silently keep files.
import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'web_session_recorder.dart';

/// Must match the signature used by `web_session_recorder.dart`.
WebSessionRecorder createRecorder() => _WebMediaRecorder();

/// Preferred encodings, first supported wins.
const List<String> _kMimeCandidates = [
  'audio/webm;codecs=opus',
  'audio/webm',
  'audio/mp4',
];

class _WebMediaRecorder implements WebSessionRecorder {
  web.MediaRecorder? _recorder;
  web.MediaStream? _stream;
  final List<JSAny> _parts = [];
  Completer<web.Blob>? _stopCompleter;
  String _fileName = '';

  @override
  bool get isActive => _recorder != null;

  @override
  Future<void> start() async {
    if (isActive) return;
    web.MediaDevices mediaDevices;
    try {
      // Throws when the browser exposes no capture API (e.g. insecure
      // context), since the getter is typed non-nullable.
      mediaDevices = web.window.navigator.mediaDevices;
    } catch (_) {
      throw StateError(
        'Microphone capture is not available in this browser.',
      );
    }
    final mime = _pickMimeType();
    if (mime == null) {
      throw StateError(
        'This browser cannot record audio (MediaRecorder unsupported).',
      );
    }
    web.MediaStream stream;
    try {
      stream = await mediaDevices
          .getUserMedia(web.MediaStreamConstraints(audio: true.toJS))
          .toDart;
    } catch (e) {
      throw StateError('Microphone permission denied or unavailable ($e).');
    }
    _fileName = _sessionFileName(
      DateTime.now(),
      mime == 'audio/mp4' ? '.mp4' : '.webm',
    );
    _parts.clear();
    _stopCompleter = Completer<web.Blob>();
    final recorder = web.MediaRecorder(
      stream,
      web.MediaRecorderOptions(
        mimeType: mime,
        audioBitsPerSecond: 32000,
      ),
    );
    recorder.ondataavailable = ((web.BlobEvent event) {
      if (event.data.size > 0) _parts.add(event.data);
    }).toJS;
    recorder.onstop = ((web.Event _) {
      final completer = _stopCompleter;
      if (completer != null && !completer.isCompleted) {
        completer.complete(web.Blob(_parts.toJS));
      }
    }).toJS;
    recorder.start(1000);
    _recorder = recorder;
    _stream = stream;
  }

  @override
  Future<void> pause() async {
    try {
      if (_recorder?.state == 'recording') _recorder!.pause();
    } catch (_) {}
  }

  @override
  Future<void> resume() async {
    try {
      if (_recorder?.state == 'paused') _recorder!.resume();
    } catch (_) {}
  }

  @override
  Future<String?> stopAndDownload() async {
    final recorder = _recorder;
    _recorder = null;
    if (recorder == null) return null;
    try {
      if (recorder.state == 'recording' || recorder.state == 'paused') {
        recorder.stop();
        final blob = await _stopCompleter?.future;
        if (blob != null) _download(blob, _fileName);
        return _fileName;
      }
      return null;
    } finally {
      _stopCompleter = null;
      _stopTracks();
    }
  }

  @override
  Future<void> discard() async {
    final recorder = _recorder;
    _recorder = null;
    _stopCompleter = null;
    try {
      if (recorder != null &&
          (recorder.state == 'recording' || recorder.state == 'paused')) {
        recorder.stop();
      }
    } catch (_) {}
    _stopTracks();
    _parts.clear();
  }

  String? _pickMimeType() {
    try {
      for (final candidate in _kMimeCandidates) {
        if (web.MediaRecorder.isTypeSupported(candidate)) {
          return candidate;
        }
      }
    } catch (_) {
      // MediaRecorder itself missing on very old browsers.
    }
    return null;
  }

  void _stopTracks() {
    final stream = _stream;
    _stream = null;
    if (stream == null) return;
    try {
      for (final track in stream.getTracks().toDart) {
        try {
          track.stop();
        } catch (_) {}
      }
    } catch (_) {}
  }

  void _download(web.Blob blob, String fileName) {
    final url = web.URL.createObjectURL(blob);
    final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
    anchor.href = url;
    anchor.download = fileName;
    web.document.body!.append(anchor);
    anchor.click();
    anchor.remove();
    // Revoking immediately can abort in-flight downloads; release later.
    Future.delayed(const Duration(seconds: 60), () {
      try {
        web.URL.revokeObjectURL(url);
      } catch (_) {}
    });
  }

  String _sessionFileName(DateTime t, String extension) {
    String two(int n) => n.toString().padLeft(2, '0');
    final date = '${t.year}${two(t.month)}${two(t.day)}';
    final time =
        '${two(t.hour)}${two(t.minute)}${two(t.second)}_${t.millisecond.toString().padLeft(3, '0')}';
    return 'sinsajo_${date}_$time$extension';
  }
}
