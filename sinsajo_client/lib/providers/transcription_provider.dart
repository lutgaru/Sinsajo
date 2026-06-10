// lib/providers/transcription_provider.dart

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/audio_service.dart';
import '../services/ws_service.dart';

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
  }) =>
      TranscriptionState(
        isRecording: isRecording ?? this.isRecording,
        wsStatus:    wsStatus    ?? this.wsStatus,
        segments:    segments    ?? this.segments,
        error:       error,
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
        case 'transcription': // ← AGREGADO: acepta "transcription" del servidor Rust
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
          // Ignorar mensajes de status
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

  Future<void> startRecording() async {
    if (state.isRecording) return;

    final hasPerm = await _audio.hasPermission;
    if (!hasPerm) {
      state = state.copyWith(error: 'Permiso de micrófono denegado');
      return;
    }

    if (state.wsStatus != WsStatus.connected) {
      await _ws.connect();
      // Esperar un poco para que la conexión se establezca
      await Future.delayed(const Duration(milliseconds: 500));
    }

    _ws.sendStart(sampleRate: kSampleRate);
    await _audio.start();

    _audioSub = _audio.chunks.listen((chunk) {
      print('[Audio] → Enviando chunk: ${chunk.pcmBytes.length} bytes, isFinal=${chunk.isFinal}');
      _ws.sendAudioChunk(chunk.pcmBytes);
    });

    state = state.copyWith(isRecording: true, error: null);
  }

  Future<void> stopRecording() async {
    if (!state.isRecording) return;

    // Cancelar suscripción de audio PRIMERO
    await _audioSub?.cancel();
    _audioSub = null;

    // Detener grabación
    await _audio.stop();
    
    // Enviar stop al servidor
    _ws.sendStop();

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