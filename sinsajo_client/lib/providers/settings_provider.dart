import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';

class SettingsState {
  final double micGain;
  final AndroidAudioSource audioSource;
  final String ipAddress;
  const SettingsState({
    this.micGain = 1.0,
    this.audioSource = AndroidAudioSource.camcorder,
    this.ipAddress = '192.168.31.21',
  });

  SettingsState copyWith({double? micGain, AndroidAudioSource? audioSource, String? ipAddress}) =>
      SettingsState(
        micGain: micGain ?? this.micGain,
        audioSource: audioSource ?? this.audioSource,
        ipAddress: ipAddress ?? this.ipAddress,
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

  void setIpAddress(String ip) {
    state = state.copyWith(ipAddress: ip);
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, SettingsState>(
  SettingsNotifier.new,
);
