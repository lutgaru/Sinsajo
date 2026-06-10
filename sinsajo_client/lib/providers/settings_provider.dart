import 'package:flutter_riverpod/flutter_riverpod.dart';

class SettingsState {
  final double micGain;
  const SettingsState({this.micGain = 1.0});

  SettingsState copyWith({double? micGain}) =>
      SettingsState(micGain: micGain ?? this.micGain);
}

class SettingsNotifier extends Notifier<SettingsState> {
  @override
  SettingsState build() => const SettingsState();

  void setMicGain(double gain) {
    state = state.copyWith(micGain: gain);
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, SettingsState>(
  SettingsNotifier.new,
);
