// lib/screens/transcription_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../providers/transcription_provider.dart';
import '../services/ws_service.dart';
import 'settings_screen.dart';

class TranscriptionScreen extends ConsumerStatefulWidget {
  const TranscriptionScreen({super.key});

  @override
  ConsumerState<TranscriptionScreen> createState() =>
      _TranscriptionScreenState();
}

class _TranscriptionScreenState extends ConsumerState<TranscriptionScreen>
    with WidgetsBindingObserver {

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(transcriptionProvider.notifier).reconnectIfNeeded();
    }
  }

  @override
  Widget build(BuildContext context) {
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
        title: const Text('Sinsajo client'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
            tooltip: 'Settings',
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: _WsStatusDot(status: state.wsStatus),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Transcribed text ─────────────────────────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: state.fullText.isEmpty
                  ? Center(
                      child: Text(
                        state.isPaused
                            ? 'Paused'
                            : state.isRecording
                                ? 'Listening…'
                                : 'Press the microphone to start',
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

          // ── Control bar ────────────────────────
          _ControlBar(state: state, notifier: notifier),
        ],
      ),
    );
  }
}

// ── Bottom bar ────────────────────────────────

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
            // Copy text
            IconButton.outlined(
              onPressed: state.fullText.isEmpty
                  ? null
                  : () {
                      Clipboard.setData(ClipboardData(text: state.fullText));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Copied to clipboard')),
                      );
                    },
              icon: const Icon(Icons.copy),
              tooltip: 'Copy',
            ),

            // Main microphone button
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
                            color: Colors.red.withValues(alpha: 0.5),
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

            // Pause / Resume (only visible during recording)
            if (state.isRecording)
              IconButton.outlined(
                onPressed: state.isPaused
                    ? () => notifier.resumeRecording()
                    : () => notifier.pauseRecording(),
                icon: Icon(state.isPaused ? Icons.play_arrow : Icons.pause),
                tooltip: state.isPaused ? 'Resume' : 'Pause',
              ),

            // Clear transcription
            IconButton.outlined(
              onPressed: state.fullText.isEmpty
                  ? null
                  : () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Clear transcription'),
                          content: Text(
                            state.isRecording
                                ? 'The current audio will be discarded and the transcription cleared.'
                                : 'Are you sure you want to clear the transcription?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(true),
                              child: const Text('Yes, clear'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        if (state.isRecording) {
                          await notifier.discardRecording();
                        } else {
                          notifier.clearTranscription();
                        }
                      }
                    },
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Clear',
            ),
          ],
        ),
      ),
    );
  }
}

// ── WS status indicator ────────────────────────

class _WsStatusDot extends StatelessWidget {
  const _WsStatusDot({required this.status});

  final WsStatus status;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      WsStatus.connected    => (Colors.greenAccent, 'Connected'),
      WsStatus.connecting   => (Colors.orange, 'Connecting'),
      WsStatus.error        => (Colors.red, 'Error'),
      WsStatus.disconnected => (Colors.grey, 'Disconnected'),
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
