import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';

enum AudioSaveFormat {
  wav('WAV'),
  ogg('OGG');

  const AudioSaveFormat(this.label);
  final String label;

  String get serverValue => name;
}

enum TargetLanguage {
  english('English', 'en'),
  spanish('Spanish', 'es'),
  french('French', 'fr'),
  german('German', 'de'),
  portuguese('Portuguese', 'pt');

  const TargetLanguage(this.label, this.code);
  final String label;
  final String code;
}

class SettingsState {
  final double micGain;
  final AndroidAudioSource audioSource;
  final String ipAddress;
  final bool saveAudio;
  final AudioSaveFormat audioFormat;
  final TargetLanguage targetLanguage;
  const SettingsState({
    this.micGain = 1.0,
    this.audioSource = AndroidAudioSource.camcorder,
    this.ipAddress = '192.168.31.21',
    this.saveAudio = true,
    this.audioFormat = AudioSaveFormat.wav,
    this.targetLanguage = TargetLanguage.english,
  });

  SettingsState copyWith({
    double? micGain,
    AndroidAudioSource? audioSource,
    String? ipAddress,
    bool? saveAudio,
    AudioSaveFormat? audioFormat,
    TargetLanguage? targetLanguage,
  }) =>
      SettingsState(
        micGain: micGain ?? this.micGain,
        audioSource: audioSource ?? this.audioSource,
        ipAddress: ipAddress ?? this.ipAddress,
        saveAudio: saveAudio ?? this.saveAudio,
        audioFormat: audioFormat ?? this.audioFormat,
        targetLanguage: targetLanguage ?? this.targetLanguage,
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

  void setSaveAudio(bool enabled) {
    state = state.copyWith(saveAudio: enabled);
  }

  void setAudioFormat(AudioSaveFormat format) {
    state = state.copyWith(audioFormat: format);
  }

  void setTargetLanguage(TargetLanguage language) {
    state = state.copyWith(targetLanguage: language);
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, SettingsState>(
  SettingsNotifier.new,
);
