// lib/providers/transcription_provider.dart
//
// Orquesta AudioService + WsService con Riverpod 2.x
// Usa Notifier + NotifierProvider (StateNotifier fue removido en Riverpod 2)

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/audio_service.dart';
import '../services/ws_service.dart';

// ── Config ────────────────────────────────────────
const String kWsUrl = 'ws://192.168.1.100:8765';  // ← cambia a la IP del servidor

// ── Estado de la sesión ───────────────────────────

class TranscriptionState {
  final bool isRecording;
  final WsStatus wsStatus;
  final List<String> segments;   // partials acumulados
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

// ── Notifier ──────────────────────────────────────
// Riverpod 2.x: extender Notifier<T> en lugar de StateNotifier<T>
// - build() reemplaza al constructor para la inicialización
// - state es accesible directamente dentro del Notifier

class TranscriptionNotifier extends Notifier<TranscriptionState> {
  late final WsService    _ws;
  late final AudioService _audio;
  StreamSubscription?     _audioSub;

  @override
  TranscriptionState build() {
    // build() es el nuevo "constructor" en Riverpod 2.x
    // Se llama automáticamente al crear el provider
    _ws    = WsService(url: kWsUrl);
    _audio = AudioService();

    // Cleanup automático cuando el provider se destruye
    ref.onDispose(() {
      _audioSub?.cancel();
      _audio.dispose();
      _ws.dispose();
    });

    _listenWsStatus();
    _listenWsMessages();

    return const TranscriptionState();
  }

  // ── WebSocket listeners ──────────────────────────

  void _listenWsStatus() {
    _ws.statusStream.listen((s) {
      state = state.copyWith(wsStatus: s);
    });
  }

  void _listenWsMessages() {
    _ws.messageStream.listen((msg) {
      switch (msg.type) {
        case 'partial':
        case 'final':
          if (msg.content.isNotEmpty) {
            state = state.copyWith(
              segments: [...state.segments, msg.content],
            );
          }
        case 'error':
          state = state.copyWith(error: msg.content);
        default:
          break;
      }
    });
  }

  // ── Public API ───────────────────────────────────

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
    }

    _ws.sendStart(sampleRate: kSampleRate);
    await _audio.start();

    _audioSub = _audio.chunks.listen((chunk) {
      _ws.sendAudioChunk(chunk.pcmBytes);
    });

    state = state.copyWith(isRecording: true, error: null);
  }

  Future<void> stopRecording() async {
    if (!state.isRecording) return;

    await _audioSub?.cancel();
    await _audio.stop();
    _ws.sendStop();

    state = state.copyWith(isRecording: false);
  }

  void clearTranscription() {
    state = state.copyWith(segments: []);
  }
}

// ── Provider ──────────────────────────────────────
// NotifierProvider reemplaza a StateNotifierProvider en Riverpod 2.x

final transcriptionProvider =
    NotifierProvider<TranscriptionNotifier, TranscriptionState>(
  TranscriptionNotifier.new,
);