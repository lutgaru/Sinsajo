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

// ── VAD defaults (Silero VAD v5, 16 kHz) ────────────────
const int kDefaultFrameSamples = 512;
const double kDefaultPositiveSpeechThreshold = 0.45;
const double kDefaultNegativeSpeechThreshold = 0.35;
const int kDefaultRedemptionFrames = 7;
const int kDefaultPreSpeechPadFrames = 8;
const int kDefaultMinSpeechFrames = 8;
const int kDefaultEndSpeechPadFrames = 3;

/// Valid frame sizes offered in the Settings UI.
const List<int> kFrameSamplesOptions = [256, 512, 768, 1024, 1536];

class SettingsState {
  final double micGain;
  final AndroidAudioSource audioSource;
  final String ipAddress;
  final bool saveAudio;
  final AudioSaveFormat audioFormat;
  final TargetLanguage targetLanguage;
  // ── VAD (Silero v5) ─────────────────────────────
  final int frameSamples;
  final double positiveSpeechThreshold;
  final double negativeSpeechThreshold;
  final int redemptionFrames;
  final int preSpeechPadFrames;
  final int minSpeechFrames;
  final int endSpeechPadFrames;
  const SettingsState({
    this.micGain = 1.0,
    this.audioSource = AndroidAudioSource.camcorder,
    this.ipAddress = '192.168.31.21',
    this.saveAudio = true,
    this.audioFormat = AudioSaveFormat.wav,
    this.targetLanguage = TargetLanguage.english,
    this.frameSamples = kDefaultFrameSamples,
    this.positiveSpeechThreshold = kDefaultPositiveSpeechThreshold,
    this.negativeSpeechThreshold = kDefaultNegativeSpeechThreshold,
    this.redemptionFrames = kDefaultRedemptionFrames,
    this.preSpeechPadFrames = kDefaultPreSpeechPadFrames,
    this.minSpeechFrames = kDefaultMinSpeechFrames,
    this.endSpeechPadFrames = kDefaultEndSpeechPadFrames,
  });

  SettingsState copyWith({
    double? micGain,
    AndroidAudioSource? audioSource,
    String? ipAddress,
    bool? saveAudio,
    AudioSaveFormat? audioFormat,
    TargetLanguage? targetLanguage,
    int? frameSamples,
    double? positiveSpeechThreshold,
    double? negativeSpeechThreshold,
    int? redemptionFrames,
    int? preSpeechPadFrames,
    int? minSpeechFrames,
    int? endSpeechPadFrames,
  }) =>
      SettingsState(
        micGain: micGain ?? this.micGain,
        audioSource: audioSource ?? this.audioSource,
        ipAddress: ipAddress ?? this.ipAddress,
        saveAudio: saveAudio ?? this.saveAudio,
        audioFormat: audioFormat ?? this.audioFormat,
        targetLanguage: targetLanguage ?? this.targetLanguage,
        frameSamples: frameSamples ?? this.frameSamples,
        positiveSpeechThreshold:
            positiveSpeechThreshold ?? this.positiveSpeechThreshold,
        negativeSpeechThreshold:
            negativeSpeechThreshold ?? this.negativeSpeechThreshold,
        redemptionFrames: redemptionFrames ?? this.redemptionFrames,
        preSpeechPadFrames: preSpeechPadFrames ?? this.preSpeechPadFrames,
        minSpeechFrames: minSpeechFrames ?? this.minSpeechFrames,
        endSpeechPadFrames: endSpeechPadFrames ?? this.endSpeechPadFrames,
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

  void setFrameSamples(int value) {
    state = state.copyWith(frameSamples: value);
  }

  void setPositiveSpeechThreshold(double value) {
    state = state.copyWith(positiveSpeechThreshold: value);
  }

  void setNegativeSpeechThreshold(double value) {
    state = state.copyWith(negativeSpeechThreshold: value);
  }

  void setRedemptionFrames(int value) {
    state = state.copyWith(redemptionFrames: value);
  }

  void setPreSpeechPadFrames(int value) {
    state = state.copyWith(preSpeechPadFrames: value);
  }

  void setMinSpeechFrames(int value) {
    state = state.copyWith(minSpeechFrames: value);
  }

  void setEndSpeechPadFrames(int value) {
    state = state.copyWith(endSpeechPadFrames: value);
  }

  void resetVadDefaults() {
    state = state.copyWith(
      frameSamples: kDefaultFrameSamples,
      positiveSpeechThreshold: kDefaultPositiveSpeechThreshold,
      negativeSpeechThreshold: kDefaultNegativeSpeechThreshold,
      redemptionFrames: kDefaultRedemptionFrames,
      preSpeechPadFrames: kDefaultPreSpeechPadFrames,
      minSpeechFrames: kDefaultMinSpeechFrames,
      endSpeechPadFrames: kDefaultEndSpeechPadFrames,
    );
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, SettingsState>(
  SettingsNotifier.new,
);
