import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';
import '../providers/server_models_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/transcription_provider.dart';
import '../services/ws_service.dart';
import 'help_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Settings'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.phone_android), text: 'Client'),
              Tab(icon: Icon(Icons.dns_outlined), text: 'Server'),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.help_outline),
              onPressed: () {
                Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const HelpScreen()));
              },
              tooltip: 'Help',
            ),
          ],
        ),
        body: const TabBarView(
          children: [_ClientSettingsTab(), _ServerSettingsTab()],
        ),
      ),
    );
  }
}

// ── Client settings ─────────────────────────────────────────────────────────

class _ClientSettingsTab extends ConsumerWidget {
  const _ClientSettingsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final modelState = ref.watch(transcriptionProvider);

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Microphone gain',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const SizedBox(
                  width: 32,
                  child: Text('0.0', textAlign: TextAlign.center),
                ),
                Expanded(
                  child: Slider(
                    value: settings.micGain,
                    min: 0.0,
                    max: 3.0,
                    divisions: 60,
                    label: '${settings.micGain.toStringAsFixed(1)}x',
                    onChanged: (value) {
                      ref.read(settingsProvider.notifier).setMicGain(value);
                    },
                  ),
                ),
                const SizedBox(
                  width: 32,
                  child: Text('3.0', textAlign: TextAlign.center),
                ),
              ],
            ),
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 16),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${settings.micGain.toStringAsFixed(1)}x',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Audio source (Android)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<AndroidAudioSource>(
              initialValue: settings.audioSource,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              items: const [
                DropdownMenuItem(
                  value: AndroidAudioSource.defaultSource,
                  child: Text('Default'),
                ),
                DropdownMenuItem(
                  value: AndroidAudioSource.voiceRecognition,
                  child: Text('Voice recognition'),
                ),
                DropdownMenuItem(
                  value: AndroidAudioSource.camcorder,
                  child: Text('Camcorder'),
                ),
                DropdownMenuItem(
                  value: AndroidAudioSource.mic,
                  child: Text('Microphone'),
                ),
                DropdownMenuItem(
                  value: AndroidAudioSource.voiceCommunication,
                  child: Text('Voice communication'),
                ),
                DropdownMenuItem(
                  value: AndroidAudioSource.unprocessed,
                  child: Text('Unprocessed'),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  ref.read(settingsProvider.notifier).setAudioSource(value);
                }
              },
            ),
            const SizedBox(height: 24),
            Text(
              'Client audio saving',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Save audio on this device'),
              subtitle: Text(
                kIsWeb
                    ? 'Not supported on Web — use the browser recording below'
                    : 'Store VAD speech as one WAV file (16 kHz mono) per session, so you can listen back to what was transcribed',
              ),
              value: settings.saveAudioLocal,
              onChanged: kIsWeb
                  ? null
                  : (value) {
                      ref
                          .read(settingsProvider.notifier)
                          .setSaveAudioLocal(value);
                    },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Record session audio (Web)'),
              subtitle: Text(
                !kIsWeb
                    ? 'Only available on Web — use the device saving above'
                    : 'Records full microphone audio as WebM/Opus in the browser and downloads it when you stop',
              ),
              value: settings.saveAudioWeb,
              onChanged: !kIsWeb
                  ? null
                  : (value) {
                      ref
                          .read(settingsProvider.notifier)
                          .setSaveAudioWeb(value);
                    },
            ),
            if (modelState.localAudioPath != null) ...[
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.audio_file_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Last saved session',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 2),
                          SelectableText(
                            modelState.localAudioPath!,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Voice Activity Detection (VAD)',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    ref.read(settingsProvider.notifier).resetVadDefaults();
                  },
                  child: const Text('Reset defaults'),
                ),
              ],
            ),
            Text(
              'Tuning how speech is detected. Lower thresholds react to quieter voices; higher frame counts make detection more stable. Changes apply to the next recording.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Frame samples',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            DropdownButtonFormField<int>(
              initialValue: settings.frameSamples,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              items: kFrameSamplesOptions
                  .map(
                    (v) => DropdownMenuItem(
                      value: v,
                      child: Text('$v (${(v / 16).toStringAsFixed(0)} ms)'),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  ref.read(settingsProvider.notifier).setFrameSamples(value);
                }
              },
            ),
            _VadDoubleSlider(
              label: 'Positive speech threshold',
              subtitle: 'Probability to start speech',
              value: settings.positiveSpeechThreshold,
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .setPositiveSpeechThreshold(v),
            ),
            _VadDoubleSlider(
              label: 'Negative speech threshold',
              subtitle: 'Probability to end speech',
              value: settings.negativeSpeechThreshold,
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .setNegativeSpeechThreshold(v),
            ),
            _VadIntSlider(
              label: 'Redemption frames',
              subtitle: 'Silence frames needed to end an utterance',
              value: settings.redemptionFrames,
              min: 0,
              max: 20,
              onChanged: (v) =>
                  ref.read(settingsProvider.notifier).setRedemptionFrames(v),
            ),
            _VadIntSlider(
              label: 'Pre-speech pad frames',
              subtitle: 'Frames of pre-roll kept before speech',
              value: settings.preSpeechPadFrames,
              min: 0,
              max: 20,
              onChanged: (v) =>
                  ref.read(settingsProvider.notifier).setPreSpeechPadFrames(v),
            ),
            _VadIntSlider(
              label: 'Min speech frames',
              subtitle: 'Minimum speech frames to emit a segment',
              value: settings.minSpeechFrames,
              min: 1,
              max: 20,
              onChanged: (v) =>
                  ref.read(settingsProvider.notifier).setMinSpeechFrames(v),
            ),
            _VadIntSlider(
              label: 'End speech pad frames',
              subtitle: 'Trailing frames kept after speech ends',
              value: settings.endSpeechPadFrames,
              min: 0,
              max: 10,
              onChanged: (v) =>
                  ref.read(settingsProvider.notifier).setEndSpeechPadFrames(v),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Server settings + model manager ──────────────────────────────────────────

class _ServerSettingsTab extends ConsumerWidget {
  const _ServerSettingsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final transcription = ref.watch(transcriptionProvider);
    final models = ref.watch(serverModelsProvider);
    final supportedLanguages = transcription.supportedLanguages;
    final isConnected = transcription.wsStatus == WsStatus.connected;
    final activeModel = transcription.serverModel ?? models.activeModel;

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle(
              title: 'Connection',
              subtitle: 'Address of the Sinsajo server that transcribes audio',
            ),
            const SizedBox(height: 8),
            _ConnectionStatus(status: transcription.wsStatus),
            const SizedBox(height: 16),
            Text('Server IP', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            const _ServerIpField(),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: transcription.isRecording
                    ? null
                    : () async {
                        await ref
                            .read(transcriptionProvider.notifier)
                            .applyServerAddress();
                      },
                icon: const Icon(Icons.sync),
                label: const Text('Apply & reconnect'),
              ),
            ),
            if (transcription.isRecording)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Stop recording before changing the server address.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ),
            const SizedBox(height: 24),
            _SectionTitle(
              title: 'Active server model',
              subtitle: activeModel == null
                  ? 'Not connected'
                  : '$activeModel'
                      '${supportedLanguages != null ? ' • ${supportedLanguages.length} languages' : ''}',
            ),
            const SizedBox(height: 8),
            _InfoCard(
              icon: Icons.memory,
              title: activeModel ?? 'Not connected',
              subtitle: supportedLanguages == null
                  ? null
                  : 'Supported languages: ${supportedLanguages.join(', ')}',
            ),
            const SizedBox(height: 24),
            _SectionTitle(
              title: 'Server audio saving',
              subtitle:
                  'Controls the recordings the server keeps. Applies to the next session.',
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Save audio on server'),
              subtitle: const Text(
                'Store the session recording as a file on the server',
              ),
              value: settings.saveAudio,
              onChanged: (value) {
                ref.read(settingsProvider.notifier).setSaveAudio(value);
              },
            ),
            DropdownButtonFormField<AudioSaveFormat>(
              initialValue: settings.audioFormat,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                labelText: 'Recording format',
              ),
              items: AudioSaveFormat.values
                  .map((f) => DropdownMenuItem(value: f, child: Text(f.label)))
                  .toList(),
              onChanged: settings.saveAudio
                  ? (value) {
                      if (value != null) {
                        ref
                            .read(settingsProvider.notifier)
                            .setAudioFormat(value);
                      }
                    }
                  : null,
            ),
            const SizedBox(height: 24),
            _SectionTitle(
              title: 'Target language',
              subtitle:
                  'Language the server model writes. Applies to the next session.',
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<TargetLanguage>(
              initialValue: settings.targetLanguage,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              items: TargetLanguage.values
                  .map(
                    (l) => DropdownMenuItem(
                      value: l,
                      enabled:
                          supportedLanguages == null ||
                          supportedLanguages.contains(l.code),
                      child: Text(l.label),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  ref.read(settingsProvider.notifier).setTargetLanguage(value);
                }
              },
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(
                  child: _SectionTitle(
                    title: 'Model manager',
                    subtitle:
                        'Install, activate or remove models on the server. '
                        'Downloads run on the server and can take a while.',
                  ),
                ),
                IconButton(
                  onPressed: models.isBusy
                      ? null
                      : ref.read(serverModelsProvider.notifier).refresh,
                  icon: models.loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  tooltip: 'Refresh model list',
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (models.actionMessage != null ||
                models.actionState == 'completed') ...[
              _ActionBanner(
                failed: models.actionState == 'failed',
                message:
                    models.actionMessage ??
                    '${_actionLabel(models.action)} completed',
                onDismiss: models.isBusy
                    ? null
                    : ref.read(serverModelsProvider.notifier).clearStatus,
              ),
              const SizedBox(height: 12),
            ],
            if (!isConnected)
              const _InfoCard(
                icon: Icons.cloud_off,
                title: 'Server offline',
                subtitle:
                    'Connect to the server to see and manage its models. '
                    'The model list refreshes automatically after reconnecting.',
              )
            else if (models.loading && models.models.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (models.error != null && models.models.isEmpty)
              _InfoCard(
                icon: Icons.error_outline,
                title: 'Could not load models',
                subtitle: models.error,
              )
            else if (models.models.isEmpty)
              const _InfoCard(
                icon: Icons.inbox_outlined,
                title: 'No models reported',
                subtitle:
                    'This server build did not report any models. Check the server logs.',
              )
            else
              ...models.models.map(
                (model) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ModelCard(
                    model: model,
                    state: models,
                    connected: isConnected,
                    onDownload: () => ref
                        .read(serverModelsProvider.notifier)
                        .downloadModel(model.name),
                    onLoad: () => ref
                        .read(serverModelsProvider.notifier)
                        .loadModel(model.name),
                    onDelete: () => _confirmDelete(context, ref, model),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _actionLabel(String? action) => switch (action) {
    'download' => 'Download',
    'load' => 'Model load',
    'delete' => 'Delete',
    _ => 'Action',
  };

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    ServerModelEntry model,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete model'),
        content: Text(
          'Remove "${model.display}" from the server?\n\n'
          'The files will be deleted and the model must be downloaded again '
          'before it can be used. The active model cannot be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      ref.read(serverModelsProvider.notifier).deleteModel(model.name);
    }
  }
}

class _ServerIpField extends ConsumerStatefulWidget {
  const _ServerIpField();

  @override
  ConsumerState<_ServerIpField> createState() => _ServerIpFieldState();
}

class _ServerIpFieldState extends ConsumerState<_ServerIpField> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: ref.read(settingsProvider).ipAddress,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(settingsProvider.select((s) => s.ipAddress), (_, next) {
      if (!_focusNode.hasFocus && _controller.text != next) {
        _controller.text = next;
      }
    });

    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        hintText: '192.168.31.21',
      ),
      keyboardType: TextInputType.url,
      onChanged: (value) {
        ref.read(settingsProvider.notifier).setIpAddress(value.trim());
      },
    );
  }
}

class _ConnectionStatus extends StatelessWidget {
  const _ConnectionStatus({required this.status});

  final WsStatus status;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      WsStatus.connected => (Colors.greenAccent, 'Connected'),
      WsStatus.connecting => (Colors.orange, 'Connecting…'),
      WsStatus.error => (Colors.red, 'Connection error'),
      WsStatus.disconnected => (Colors.grey, 'Disconnected'),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.circle, size: 12, color: color),
          const SizedBox(width: 10),
          Text(label, style: Theme.of(context).textTheme.titleSmall),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.title, this.subtitle});

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionBanner extends StatelessWidget {
  const _ActionBanner({
    required this.failed,
    required this.message,
    this.onDismiss,
  });

  final bool failed;
  final String message;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final color = failed
        ? Theme.of(context).colorScheme.errorContainer
        : Theme.of(context).colorScheme.secondaryContainer;
    final onColor = failed
        ? Theme.of(context).colorScheme.onErrorContainer
        : Theme.of(context).colorScheme.onSecondaryContainer;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            failed ? Icons.error_outline : Icons.check_circle_outline,
            color: onColor,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: onColor),
            ),
          ),
          if (onDismiss != null)
            IconButton(
              onPressed: onDismiss,
              icon: Icon(Icons.close, size: 18, color: onColor),
              tooltip: 'Dismiss',
            ),
        ],
      ),
    );
  }
}

/// Progress bar split into one segment per file still to download.
class _SegmentedProgressBar extends StatelessWidget {
  const _SegmentedProgressBar({required this.segments, required this.value});

  /// Number of file sections. Values <= 1 fall back to a normal bar.
  final int segments;

  /// Overall completion in the range 0..1, or null for an indeterminate bar.
  final double? value;

  @override
  Widget build(BuildContext context) {
    final trackColor = Theme.of(context).colorScheme.outlineVariant;
    final shownValue = value;

    if (shownValue == null || segments <= 1) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: shownValue,
          minHeight: 8,
          backgroundColor: trackColor,
        ),
      );
    }

    // Every file owns the same slice of the bar. `filled` counts how many
    // sections are complete (including the partially filled current one).
    final filled = shownValue.clamp(0.0, 1.0).toDouble() * segments;
    return Row(
      children: [
        for (var index = 0; index < segments; index++) ...[
          if (index > 0) const SizedBox(width: 3),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: (filled - index).clamp(0.0, 1.0).toDouble(),
                minHeight: 8,
                backgroundColor: trackColor,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({
    required this.model,
    required this.state,
    required this.connected,
    required this.onDownload,
    required this.onLoad,
    required this.onDelete,
  });

  final ServerModelEntry model;
  final ServerModelsState state;
  final bool connected;
  final VoidCallback onDownload;
  final VoidCallback onLoad;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final busy = state.isBusy;
    final thisAction = state.actionModel == model.name;
    final isThisDownloading =
        thisAction &&
        state.action == 'download' &&
        state.actionState == 'started';
    final isThisLoading =
        thisAction && state.action == 'load' && state.actionState == 'started';
    final isThisDeleting =
        thisAction &&
        state.action == 'delete' &&
        state.actionState == 'started';

    final statusColor = model.active
        ? Theme.of(context).colorScheme.primary
        : model.installed
        ? Theme.of(context).colorScheme.tertiary
        : Theme.of(context).colorScheme.outline;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: model.active
            ? Border.all(color: Theme.of(context).colorScheme.primary, width: 1)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                model.active
                    ? Icons.play_circle_fill
                    : model.installed
                    ? Icons.download_done
                    : Icons.cloud_download_outlined,
                color: statusColor,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      model.display,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${model.name} • ${model.files} file(s)',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              if (model.active)
                Chip(
                  label: const Text('Active'),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.primaryContainer,
                  labelStyle: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    fontSize: 11,
                  ),
                )
              else
                Text(
                  model.installed ? 'Installed' : 'Not installed',
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: statusColor),
                ),
            ],
          ),
          if (isThisDownloading) ...[
            const SizedBox(height: 12),
            _SegmentedProgressBar(
              segments: state.downloadFilesTotal,
              value: (state.totalBytes > 0 || state.downloadFilesTotal > 0)
                  ? state.downloadFraction
                  : null,
            ),
            const SizedBox(height: 6),
            Text(
              state.downloadFile == null
                  ? 'Downloading model…'
                  : 'Downloading ${state.downloadFile}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 2),
            Text(
              _downloadLabel(state),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
          if (isThisLoading || isThisDeleting) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(
                  isThisDeleting
                      ? 'Removing model files…'
                      : 'Loading model on the server…',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            children: [
              if (!model.installed)
                FilledButton.tonalIcon(
                  onPressed: connected && !busy ? onDownload : null,
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('Download'),
                )
              else ...[
                TextButton.icon(
                  onPressed: connected && !busy ? onLoad : null,
                  icon: Icon(
                    model.active ? Icons.refresh : Icons.bolt,
                    size: 18,
                  ),
                  label: Text(model.active ? 'Reload' : 'Load'),
                ),
                TextButton.icon(
                  onPressed: connected && !busy && !model.active
                      ? onDelete
                      : null,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Delete'),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  static String _downloadLabel(ServerModelsState state) {
    final downloaded = _formatBytes(state.downloadedBytes);
    final fileCount = state.downloadFilesTotal > 1
        ? ' • file ${(state.downloadFilesDone + 1).clamp(1, state.downloadFilesTotal)}'
              ' of ${state.downloadFilesTotal}'
        : '';
    if (state.totalBytes <= 0) {
      return '$downloaded downloaded$fileCount';
    }
    final percent = state.downloadPercent.clamp(0, 100);
    return '$percent% • $downloaded / ${_formatBytes(state.totalBytes)}$fileCount';
  }

  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var size = bytes.toDouble();
    var index = 0;
    while (size >= 1024 && index < units.length - 1) {
      size /= 1024;
      index++;
    }
    final decimals = index == 0 || size >= 100 ? 0 : 1;
    return '${size.toStringAsFixed(decimals)} ${units[index]}';
  }
}

// ── VAD sliders ─────────────────────────────────────────────────────────────

class _VadDoubleSlider extends StatelessWidget {
  const _VadDoubleSlider({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String subtitle;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: Theme.of(context).textTheme.titleSmall),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  value.toStringAsFixed(2),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ],
          ),
          Slider(
            value: value.clamp(0.0, 1.0),
            min: 0.0,
            max: 1.0,
            divisions: 100,
            label: value.toStringAsFixed(2),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _VadIntSlider extends StatelessWidget {
  const _VadIntSlider({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final String subtitle;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: Theme.of(context).textTheme.titleSmall),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$value',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ],
          ),
          Slider(
            value: value.clamp(min, max).toDouble(),
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: (max - min) == 0 ? 1 : (max - min),
            label: '$value',
            onChanged: (v) => onChanged(v.round()),
          ),
        ],
      ),
    );
  }
}
