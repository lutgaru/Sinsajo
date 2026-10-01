// lib/providers/transcription_provider.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../services/audio_service.dart';
import '../services/local_wav_writer.dart';
import '../services/web_session_recorder.dart';
import '../services/ws_service.dart';
import 'settings_provider.dart';

class TranscriptionState {
  final bool isRecording;
  final bool isPaused;
  final WsStatus wsStatus;
  final List<String> segments;
  final String? error;
  final String? serverModel;
  final List<String>? supportedLanguages;
  final String? localAudioPath;

  const TranscriptionState({
    this.isRecording = false,
    this.isPaused    = false,
    this.wsStatus    = WsStatus.disconnected,
    this.segments    = const [],
    this.error,
    this.serverModel,
    this.supportedLanguages,
    this.localAudioPath,
  });

  String get fullText => segments.join(' ');

  TranscriptionState copyWith({
    bool?         isRecording,
    bool?         isPaused,
    WsStatus?     wsStatus,
    List<String>? segments,
    String?       error,
    String?       serverModel,
    List<String>? supportedLanguages,
    String?       localAudioPath,
    bool          clearError = false,
    bool          clearLocalAudioPath = false,
  }) =>
      TranscriptionState(
        isRecording: isRecording ?? this.isRecording,
        isPaused:    isPaused    ?? this.isPaused,
        wsStatus:    wsStatus    ?? this.wsStatus,
        segments:    segments    ?? this.segments,
        error:       clearError ? null : (error ?? this.error),
        serverModel: serverModel ?? this.serverModel,
        supportedLanguages: supportedLanguages ?? this.supportedLanguages,
        localAudioPath: clearLocalAudioPath
            ? null
            : (localAudioPath ?? this.localAudioPath),
      );
}

class TranscriptionNotifier extends Notifier<TranscriptionState> {
  late final WsService    _ws;
  late final AudioService _audio;
  StreamSubscription?     _audioSub;
  StreamSubscription?     _wsStatusSub;
  StreamSubscription?     _wsMessageSub;
  LocalWavWriter?         _localWav;
  WebSessionRecorder?     _webRec;

  @override
  TranscriptionState build() {
    final settings = ref.read(settingsProvider);
    _ws    = WsService(url: 'ws://${settings.ipAddress}:8765');
    _audio = AudioService();

    _ws.connect();

    ref.onDispose(() {
      _audioSub?.cancel();
      _wsStatusSub?.cancel();
      _wsMessageSub?.cancel();
      _audio.dispose();
      _ws.dispose();
    });

    _wsStatusSub = _ws.statusStream.listen((s) {
      final wasRecording = state.isRecording;
      final wasPaused    = state.isPaused;
      state = state.copyWith(wsStatus: s, clearError: s == WsStatus.connected);

      // The server drops all session state when it crashes/restarts. If we
      // were recording when the connection dropped, re-register the session
      // once the socket is back so transcription resumes seamlessly.
      if (s == WsStatus.connected && wasRecording && !wasPaused) {
        debugPrint('[WS] 📡 Reopening recording session on reconnect');
        _sendStartWithSettings();
      }
    });

    _wsMessageSub = _ws.messageStream.listen((msg) {
      debugPrint('[WS] ← Received: type=${msg.type}, content=${msg.content}');
      switch (msg.type) {
        case 'transcription':
        case 'partial':
        case 'final':
          if (msg.content.isNotEmpty) {
            state = state.copyWith(
              segments: [...state.segments, msg.content],
            );
          }
          break;
        case 'error':
          state = state.copyWith(error: msg.content);
          break;
        case 'model_info':
          final langs = msg.languages;
          // If the running model no longer supports the selected target
          // language, fall back to English so the UI never shows a selection
          // the server cannot honor.
          if (langs != null && langs.isNotEmpty) {
            final settings = ref.read(settingsProvider);
            if (!langs.contains(settings.targetLanguage.code)) {
              ref
                  .read(settingsProvider.notifier)
                  .setTargetLanguage(TargetLanguage.english);
            }
          }
          state = state.copyWith(
            serverModel: msg.model,
            supportedLanguages: langs,
          );
          break;
        case 'status':
          break;
        default:
          break;
      }
    });

    return const TranscriptionState();
  }

  Future<void> connect() async {
    await _ws.connect();
  }

  Future<void> reconnectIfNeeded() async {
    if (_ws.status != WsStatus.connected) {
      debugPrint('[WS] 🔄 Reconnecting due to lifecycle change');
      await _ws.connect();
    }
  }

  void _sendStartWithSettings() {
    final settings = ref.read(settingsProvider);
    _ws.sendStart(
      sampleRate: kSampleRate,
      saveAudio: settings.saveAudio,
      format: settings.audioFormat.serverValue,
      targetLanguage: settings.targetLanguage.code,
    );
  }

  Future<void> startRecording() async {
    if (state.isRecording && !state.isPaused) return;
    if (state.isPaused) {
      await resumeRecording();
      return;
    }

    final hasPerm = await _audio.hasPermission;
    if (!hasPerm) {
      state = state.copyWith(error: 'Microphone permission denied');
      return;
    }

    _sendStartWithSettings();
    final settings = ref.read(settingsProvider);
    _audio.gain = settings.micGain;
    String? localAudioError;
    void noteLocalError(String msg) {
      localAudioError =
          localAudioError == null ? msg : '$localAudioError\n$msg';
    }

    _localWav = await _maybeStartLocalWriter(settings, onError: noteLocalError);
    _webRec = await _maybeStartWebRecorder(settings, onError: noteLocalError);
    try {
      await _audio.start(
        audioSource: settings.audioSource,
        frameSamples: settings.frameSamples,
        positiveSpeechThreshold: settings.positiveSpeechThreshold,
        negativeSpeechThreshold: settings.negativeSpeechThreshold,
        redemptionFrames: settings.redemptionFrames,
        preSpeechPadFrames: settings.preSpeechPadFrames,
        minSpeechFrames: settings.minSpeechFrames,
        endSpeechPadFrames: settings.endSpeechPadFrames,
      );
    } catch (_) {
      // Avoid leaving orphaned empty recordings behind when starting fails.
      await _finishLocalWriter(keep: false);
      await _finishWebRecorder(keep: false);
      rethrow;
    }

    _audioSub = _audio.chunks.listen((chunk) {
      debugPrint('[Audio] → Enviando chunk: ${chunk.pcmBytes.length} bytes, isFinal=${chunk.isFinal}');
      _ws.sendAudioChunk(chunk.pcmBytes);
      // IOSink.add preserves order synchronously, so no chaining needed
      // and RAM stays flat (bytes go straight to the OS buffer).
      unawaited(_localWav?.append(chunk.pcmBytes));
    });

    state = state.copyWith(
      isRecording: true,
      clearError: localAudioError == null,
      error: localAudioError,
    );
  }

  Future<void> pauseRecording() async {
    if (!state.isRecording || state.isPaused) return;
    await _audioSub?.cancel();
    _audioSub = null;
    await _audio.pause();
    // Keep the WAV open: resume appends to the same single session file.
    await _localWav?.flush();
    // MediaRecorder pauses into the same single file as well.
    await _webRec?.pause();
    state = state.copyWith(isPaused: true);
  }

  Future<void> resumeRecording() async {
    if (!state.isPaused) return;
    final settings = ref.read(settingsProvider);
    _audio.gain = settings.micGain;
    await _webRec?.resume();
    await _audio.resume(
      audioSource: settings.audioSource,
      frameSamples: settings.frameSamples,
      positiveSpeechThreshold: settings.positiveSpeechThreshold,
      negativeSpeechThreshold: settings.negativeSpeechThreshold,
      redemptionFrames: settings.redemptionFrames,
      preSpeechPadFrames: settings.preSpeechPadFrames,
      minSpeechFrames: settings.minSpeechFrames,
      endSpeechPadFrames: settings.endSpeechPadFrames,
    );
    _audioSub = _audio.chunks.listen((chunk) {
      debugPrint('[Audio] → Enviando chunk: ${chunk.pcmBytes.length} bytes, isFinal=${chunk.isFinal}');
      _ws.sendAudioChunk(chunk.pcmBytes);
      unawaited(_localWav?.append(chunk.pcmBytes));
    });
    state = state.copyWith(isPaused: false);
  }

  Future<void> stopRecording() async {
    if (!state.isRecording) return;

    await _audioSub?.cancel();
    _audioSub = null;

    try {
      await _audio.stop();
    } finally {
      await _finishLocalWriter(keep: true);
      await _finishWebRecorder(keep: true);
    }
    _ws.sendStop();
    _ws.sendClean();

    state = state.copyWith(isRecording: false, isPaused: false);
  }

  void clearTranscription() {
    state = state.copyWith(segments: []);
  }

  Future<void> discardRecording() async {
    if (!state.isRecording) {
      state = state.copyWith(segments: []);
      return;
    }

    await _audioSub?.cancel();
    _audioSub = null;

    try {
      await _audio.stop();
    } finally {
      // Discarding means the transcription is thrown away, so the local
      // preview file is deleted too instead of kept.
      await _finishLocalWriter(keep: false);
      await _finishWebRecorder(keep: false);
    }
    _ws.sendDiscard();

    state = state.copyWith(isRecording: false, isPaused: false, segments: []);
  }

  /// Opens a new single-file WAV session recording when the user enabled
  /// client-side saving. Returns null when disabled, on Web, or on failure
  /// (recording continues without local saving in that case).
  Future<LocalWavWriter?> _maybeStartLocalWriter(
    SettingsState settings, {
    required void Function(String message) onError,
  }) async {
    if (!settings.saveAudioLocal || kIsWeb) return null;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final writer = await createLocalWavWriter(
        directoryPath: '${dir.path}/sinsajo_recordings',
        fileName: _localSessionFileName(DateTime.now()),
        sampleRate: kSampleRate,
      );
      await writer.open();
      return writer;
    } catch (e) {
      debugPrint('[LocalAudio] ⚠️ Could not start local recording: $e');
      onError('Could not save local audio: $e');
      return null;
    }
  }

  /// Finalizes the session file (keep) or deletes it (discard).
  Future<void> _finishLocalWriter({required bool keep}) async {
    final writer = _localWav;
    _localWav = null;
    if (writer == null) return;
    try {
      if (keep) {
        await writer.finalize();
        state = state.copyWith(localAudioPath: writer.path);
      } else {
        await writer.discard();
        state = state.copyWith(clearLocalAudioPath: true);
      }
    } catch (e) {
      debugPrint('[LocalAudio] ⚠️ Could not finish local recording: $e');
    }
  }

  String _localSessionFileName(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    final date = '${t.year}${two(t.month)}${two(t.day)}';
    final time =
        '${two(t.hour)}${two(t.minute)}${two(t.second)}_${t.millisecond.toString().padLeft(3, '0')}';
    return 'sinsajo_${date}_$time.wav';
  }

  /// Starts the browser MediaRecorder when the user enabled Web saving.
  /// Returns null when disabled, off Web, or on failure (transcription
  /// continues without the browser recording in that case).
  Future<WebSessionRecorder?> _maybeStartWebRecorder(
    SettingsState settings, {
    required void Function(String message) onError,
  }) async {
    if (!settings.saveAudioWeb || !kIsWeb) return null;
    try {
      final recorder = createWebSessionRecorder();
      await recorder.start();
      return recorder;
    } catch (e) {
      debugPrint('[WebAudio] ⚠️ Could not start browser recording: $e');
      onError('Could not record browser audio: $e');
      return null;
    }
  }

  /// Downloads the session file (keep) or throws it away (discard).
  Future<void> _finishWebRecorder({required bool keep}) async {
    final recorder = _webRec;
    _webRec = null;
    if (recorder == null) return;
    try {
      if (keep) {
        final fileName = await recorder.stopAndDownload();
        if (fileName != null) {
          state = state.copyWith(localAudioPath: fileName);
        }
      } else {
        await recorder.discard();
        state = state.copyWith(clearLocalAudioPath: true);
      }
    } catch (e) {
      debugPrint('[WebAudio] ⚠️ Could not finish browser recording: $e');
    }
  }
}

final transcriptionProvider =
    NotifierProvider<TranscriptionNotifier, TranscriptionState>(
  TranscriptionNotifier.new,
);