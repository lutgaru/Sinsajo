// lib/screens/transcription_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../providers/transcription_provider.dart';
import '../services/ws_service.dart';

class TranscriptionScreen extends ConsumerWidget {
  const TranscriptionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state    = ref.watch(transcriptionProvider);
    final notifier = ref.read(transcriptionProvider.notifier);

    ref.listen(transcriptionProvider.select((s) => s.isRecording), (prev, next) {
      if (next) {
        WakelockPlus.enable();
      } else {
        WakelockPlus.disable();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Whisper Local'),
        actions: [
          // Indicador de conexión WS
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: _WsStatusDot(status: state.wsStatus),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Texto transcrito ─────────────────────────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: state.fullText.isEmpty
                  ? Center(
                      child: Text(
                        state.isRecording
                            ? 'Escuchando…'
                            : 'Presiona el micrófono para comenzar',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: Colors.white38,
                            ),
                      ),
                    )
                  : SingleChildScrollView(
                      reverse: true,
                      child: SelectableText(
                        state.fullText,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
            ),
          ),

          // ── Error ────────────────────────────────────
          if (state.error != null)
            Container(
              color: Colors.red.shade900,
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              child: Text(
                state.error!,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),

          // ── Barra de controles ────────────────────────
          _ControlBar(state: state, notifier: notifier),
        ],
      ),
    );
  }
}

// ── Barra inferior ────────────────────────────────

class _ControlBar extends StatelessWidget {
  const _ControlBar({required this.state, required this.notifier});

  final TranscriptionState      state;
  final TranscriptionNotifier   notifier;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Copiar texto
            IconButton.outlined(
              onPressed: state.fullText.isEmpty
                  ? null
                  : () {
                      Clipboard.setData(ClipboardData(text: state.fullText));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Copiado al portapapeles')),
                      );
                    },
              icon: const Icon(Icons.copy),
              tooltip: 'Copiar',
            ),

            // Botón principal de micrófono
            GestureDetector(
              onTap: () async {
                if (state.isRecording) {
                  await notifier.stopRecording();
                } else {
                  await notifier.startRecording();
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: state.isRecording
                      ? Colors.red
                      : Theme.of(context).colorScheme.primary,
                  boxShadow: state.isRecording
                      ? [
                          BoxShadow(
                            color: Colors.red.withOpacity(0.5),
                            blurRadius: 20,
                            spreadRadius: 4,
                          )
                        ]
                      : [],
                ),
                child: Icon(
                  state.isRecording ? Icons.stop : Icons.mic,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),

            // Limpiar transcripción
            IconButton.outlined(
              onPressed: state.fullText.isEmpty ? null : notifier.clearTranscription,
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Limpiar',
            ),
          ],
        ),
      ),
    );
  }
}

// ── Indicador de estado WS ────────────────────────

class _WsStatusDot extends StatelessWidget {
  const _WsStatusDot({required this.status});

  final WsStatus status;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      WsStatus.connected    => (Colors.greenAccent, 'Conectado'),
      WsStatus.connecting   => (Colors.orange, 'Conectando'),
      WsStatus.error        => (Colors.red, 'Error'),
      WsStatus.disconnected => (Colors.grey, 'Desconectado'),
    };

    return Tooltip(
      message: label,
      child: CircleAvatar(
        radius: 6,
        backgroundColor: color,
      ),
    );
  }
}
