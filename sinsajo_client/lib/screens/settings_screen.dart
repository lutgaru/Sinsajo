import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';
import '../providers/settings_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajustes'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ganancia del micrófono',
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
              'Fuente de audio (Android)',
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
                  child: Text('Por defecto'),
                ),
                DropdownMenuItem(
                  value: AndroidAudioSource.voiceRecognition,
                  child: Text('Reconocimiento de voz'),
                ),
                DropdownMenuItem(
                  value: AndroidAudioSource.camcorder,
                  child: Text('Camcorder'),
                ),
                DropdownMenuItem(
                  value: AndroidAudioSource.mic,
                  child: Text('Micrófono'),
                ),
                DropdownMenuItem(
                  value: AndroidAudioSource.voiceCommunication,
                  child: Text('Comunicación de voz'),
                ),
                DropdownMenuItem(
                  value: AndroidAudioSource.unprocessed,
                  child: Text('Sin procesar'),
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
              'IP del servidor',
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
          ],
        ),
      ),
    );
  }
}
