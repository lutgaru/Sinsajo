import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';
import '../providers/settings_provider.dart';
import '../providers/transcription_provider.dart';
import 'help_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final modelState = ref.watch(transcriptionProvider);
    final supportedLanguages = modelState.supportedLanguages;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HelpScreen()),
              );
            },
            tooltip: 'Help',
          ),
        ],
      ),
      body: SingleChildScrollView(
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
                const SizedBox(width: 32, child: Text('0.0', textAlign: TextAlign.center)),
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
                const SizedBox(width: 32, child: Text('3.0', textAlign: TextAlign.center)),
              ],
            ),
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 16),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
              'Server audio saving',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Save audio on server'),
              subtitle: const Text('Store the session recording as a file on the server'),
              value: settings.saveAudio,
              onChanged: (value) {
                ref.read(settingsProvider.notifier).setSaveAudio(value);
              },
            ),
            DropdownButtonFormField<AudioSaveFormat>(
              initialValue: settings.audioFormat,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: AudioSaveFormat.values
                  .map((f) => DropdownMenuItem(
                        value: f,
                        child: Text(f.label),
                      ))
                  .toList(),
              onChanged: settings.saveAudio
                  ? (value) {
                      if (value != null) {
                        ref.read(settingsProvider.notifier).setAudioFormat(value);
                      }
                    }
                  : null,
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color:
                                      Theme.of(context).colorScheme.outline,
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
            Text(
              'Server model',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.memory,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          modelState.serverModel ?? 'Not connected',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        if (supportedLanguages != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Supported languages: '
                            '${supportedLanguages.join(', ')}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color:
                                      Theme.of(context).colorScheme.outline,
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Target language',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<TargetLanguage>(
              initialValue: settings.targetLanguage,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: TargetLanguage.values
                  .map((l) => DropdownMenuItem(
                        value: l,
                        enabled: supportedLanguages == null ||
                            supportedLanguages.contains(l.code),
                        child: Text(l.label),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  ref.read(settingsProvider.notifier).setTargetLanguage(value);
                }
              },
            ),
            const SizedBox(height: 24),
            Text(
              'Server IP',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: settings.ipAddress,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                hintText: '192.168.31.21',
              ),
              keyboardType: TextInputType.url,
              onChanged: (value) {
                ref.read(settingsProvider.notifier).setIpAddress(value);
              },
            ),
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
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: kFrameSamplesOptions
                  .map((v) => DropdownMenuItem(
                        value: v,
                        child: Text('$v (${(v / 16).toStringAsFixed(0)} ms)'),
                      ))
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
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .setRedemptionFrames(v),
            ),
            _VadIntSlider(
              label: 'Pre-speech pad frames',
              subtitle: 'Frames of pre-roll kept before speech',
              value: settings.preSpeechPadFrames,
              min: 0,
              max: 20,
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .setPreSpeechPadFrames(v),
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
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .setEndSpeechPadFrames(v),
            ),
          ],
          ),
        ),
      ),
    );
  }
}

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
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
