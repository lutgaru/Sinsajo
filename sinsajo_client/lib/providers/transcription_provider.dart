// lib/providers/transcription_provider.dart

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/audio_service.dart';
import '../services/ws_service.dart';
import 'settings_provider.dart';

const String kWsUrl = 'ws://192.168.31.21:8765';

class TranscriptionState {
  final bool isRecording;
  final WsStatus wsStatus;
  final List<String> segments;
  final String? error;

  const TranscriptionState({
    this.isRecording = false,
    this.wsStatus    = WsStatus.disconnected,
    this.segments    = const [],
    this.error,
  });

  String get fullText => segments.join(' ');

  TranscriptionState copyWith({
    bool?         isRecording,
    WsStatus?     wsStatus,
    List<String>? segments,
    String?       error,
    bool          clearError = false,
  }) =>
      TranscriptionState(
        isRecording: isRecording ?? this.isRecording,
        wsStatus:    wsStatus    ?? this.wsStatus,
        segments:    segments    ?? this.segments,
        error:       clearError ? null : (error ?? this.error),
      );
}

class TranscriptionNotifier extends Notifier<TranscriptionState> {
  late final WsService    _ws;
  late final AudioService _audio;
  StreamSubscription?     _audioSub;
  StreamSubscription?     _wsStatusSub;
  StreamSubscription?     _wsMessageSub;

  @override
  TranscriptionState build() {
    _ws    = WsService(url: kWsUrl);
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
      state = state.copyWith(wsStatus: s);
    });

    _wsMessageSub = _ws.messageStream.listen((msg) {
      print('[WS] ← Recibido: type=${msg.type}, content=${msg.content}');
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
      print('[WS] 🔄 Reconectando por cambio de lifecycle');
      await _ws.connect();
    }
  }

  Future<void> startRecording() async {
    if (state.isRecording) return;

    final hasPerm = await _audio.hasPermission;
    if (!hasPerm) {
      state = state.copyWith(error: 'Permiso de micrófono denegado');
      return;
    }

    _ws.sendStart(sampleRate: kSampleRate);
    final settings = ref.read(settingsProvider);
    _audio.gain = settings.micGain;
    await _audio.start(audioSource: settings.audioSource);

    _audioSub = _audio.chunks.listen((chunk) {
      print('[Audio] → Enviando chunk: ${chunk.pcmBytes.length} bytes, isFinal=${chunk.isFinal}');
      _ws.sendAudioChunk(chunk.pcmBytes);
    });

    state = state.copyWith(isRecording: true, clearError: true);
  }

  Future<void> stopRecording() async {
    if (!state.isRecording) return;

    await _audioSub?.cancel();
    _audioSub = null;

    await _audio.stop();
    _ws.sendStop();
    _ws.sendClean();

    state = state.copyWith(isRecording: false);
  }

  void clearTranscription() {
    state = state.copyWith(segments: []);
  }
}

final transcriptionProvider =
    NotifierProvider<TranscriptionNotifier, TranscriptionState>(
  TranscriptionNotifier.new,
);