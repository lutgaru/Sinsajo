import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';

class SettingsState {
  final double micGain;
  final AndroidAudioSource audioSource;
  const SettingsState({
    this.micGain = 1.0,
    this.audioSource = AndroidAudioSource.camcorder,
  });

  SettingsState copyWith({double? micGain, AndroidAudioSource? audioSource}) =>
      SettingsState(
        micGain: micGain ?? this.micGain,
        audioSource: audioSource ?? this.audioSource,
      );
}

class SettingsNotifier extends Notifier<SettingsState> {
  @override
  SettingsState build() => const SettingsState();

  void setMicGain(double gain) {
    state = state.copyWith(micGain: gain);
  }

  void setAudioSource(AndroidAudioSource source) {
    state = state.copyWith(audioSource: source);
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, SettingsState>(
  SettingsNotifier.new,
);
