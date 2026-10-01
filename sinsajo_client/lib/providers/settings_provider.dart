import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// Key-value persistence for settings.
///
/// The default implementation is `shared_preferences` (localStorage on Web,
/// native prefs elsewhere). Abstracted so tests can inject an in-memory
/// fake and so a broken storage backend can never poison providers —
/// reads/writes only fail at awaited call sites, which are all guarded.
abstract class SettingsStore {
  Future<bool?> getBool(String key);
  Future<int?> getInt(String key);
  Future<double?> getDouble(String key);
  Future<String?> getString(String key);
  Future<void> setBool(String key, bool value);
  Future<void> setInt(String key, int value);
  Future<void> setDouble(String key, double value);
  Future<void> setString(String key, String value);
}

class SharedPreferencesSettingsStore implements SettingsStore {
  SharedPreferencesAsync? _backend;

  SharedPreferencesAsync get _prefs => _backend ??= SharedPreferencesAsync();

  @override
  Future<bool?> getBool(String key) async => await _prefs.getBool(key);

  @override
  Future<int?> getInt(String key) async => await _prefs.getInt(key);

  @override
  Future<double?> getDouble(String key) async =>
      await _prefs.getDouble(key);

  @override
  Future<String?> getString(String key) async =>
      await _prefs.getString(key);

  @override
  Future<void> setBool(String key, bool value) async =>
      await _prefs.setBool(key, value);

  @override
  Future<void> setInt(String key, int value) async =>
      await _prefs.setInt(key, value);

  @override
  Future<void> setDouble(String key, double value) async =>
      await _prefs.setDouble(key, value);

  @override
  Future<void> setString(String key, String value) async =>
      await _prefs.setString(key, value);
}

final settingsStoreProvider = Provider<SettingsStore>(
  (_) => SharedPreferencesSettingsStore(),
);

// Storage keys (one per persisted setting).
const _kMicGain = 'sinsajo.settings.micGain';
const _kAudioSource = 'sinsajo.settings.audioSource';
const _kIpAddress = 'sinsajo.settings.ipAddress';
const _kSaveAudio = 'sinsajo.settings.saveAudio';
const _kAudioFormat = 'sinsajo.settings.audioFormat';
const _kTargetLanguage = 'sinsajo.settings.targetLanguage';
const _kSaveAudioLocal = 'sinsajo.settings.saveAudioLocal';
const _kSaveAudioWeb = 'sinsajo.settings.saveAudioWeb';
const _kFrameSamples = 'sinsajo.settings.frameSamples';
const _kPositiveSpeechThreshold =
    'sinsajo.settings.positiveSpeechThreshold';
const _kNegativeSpeechThreshold =
    'sinsajo.settings.negativeSpeechThreshold';
const _kRedemptionFrames = 'sinsajo.settings.redemptionFrames';
const _kPreSpeechPadFrames = 'sinsajo.settings.preSpeechPadFrames';
const _kMinSpeechFrames = 'sinsajo.settings.minSpeechFrames';
const _kEndSpeechPadFrames = 'sinsajo.settings.endSpeechPadFrames';

class SettingsState {
  final double micGain;
  final AndroidAudioSource audioSource;
  final String ipAddress;
  final bool saveAudio;
  final AudioSaveFormat audioFormat;
  final TargetLanguage targetLanguage;
  final bool saveAudioLocal;
  final bool saveAudioWeb;
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
    this.saveAudioLocal = false,
    this.saveAudioWeb = false,
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
    bool? saveAudioLocal,
    bool? saveAudioWeb,
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
        saveAudioLocal: saveAudioLocal ?? this.saveAudioLocal,
        saveAudioWeb: saveAudioWeb ?? this.saveAudioWeb,
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
  /// Keys changed by the user since [build]. Hydration skips these so a
  /// slow storage read can never clobber a fresh user edit.
  final Set<String> _touched = {};

  @override
  SettingsState build() {
    // Deferred past build: ref.read is not allowed synchronously inside
    // build() itself. A microtask (not Future()) so widget tests under
    // fake_async see no pending timers. User edits in the meantime still
    // win via _touched.
    scheduleMicrotask(_hydrate);
    return const SettingsState();
  }

  /// Loads persisted settings in the background. Missing keys and storage
  /// failures fall back to defaults; unknown enum names fall back too.
  Future<void> _hydrate() async {
    // The container may be gone before this deferred work runs (e.g. in
    // tests). Never touch a dead ref.
    if (!ref.mounted) return;
    try {
      final store = ref.read(settingsStoreProvider);
      final current = state;
      final loaded = SettingsState(
        micGain: _touched.contains(_kMicGain)
            ? current.micGain
            : await store.getDouble(_kMicGain) ?? current.micGain,
        audioSource: _touched.contains(_kAudioSource)
            ? current.audioSource
            : _enumByName(
                AndroidAudioSource.values,
                await store.getString(_kAudioSource),
                current.audioSource,
              ),
        ipAddress: _touched.contains(_kIpAddress)
            ? current.ipAddress
            : await store.getString(_kIpAddress) ?? current.ipAddress,
        saveAudio: _touched.contains(_kSaveAudio)
            ? current.saveAudio
            : await store.getBool(_kSaveAudio) ?? current.saveAudio,
        audioFormat: _touched.contains(_kAudioFormat)
            ? current.audioFormat
            : _enumByName(
                AudioSaveFormat.values,
                await store.getString(_kAudioFormat),
                current.audioFormat,
              ),
        targetLanguage: _touched.contains(_kTargetLanguage)
            ? current.targetLanguage
            : _enumByName(
                TargetLanguage.values,
                await store.getString(_kTargetLanguage),
                current.targetLanguage,
              ),
        saveAudioLocal: _touched.contains(_kSaveAudioLocal)
            ? current.saveAudioLocal
            : await store.getBool(_kSaveAudioLocal) ?? current.saveAudioLocal,
        saveAudioWeb: _touched.contains(_kSaveAudioWeb)
            ? current.saveAudioWeb
            : await store.getBool(_kSaveAudioWeb) ?? current.saveAudioWeb,
        frameSamples: _touched.contains(_kFrameSamples)
            ? current.frameSamples
            : await store.getInt(_kFrameSamples) ?? current.frameSamples,
        positiveSpeechThreshold: _touched.contains(_kPositiveSpeechThreshold)
            ? current.positiveSpeechThreshold
            : await store.getDouble(_kPositiveSpeechThreshold) ??
                current.positiveSpeechThreshold,
        negativeSpeechThreshold: _touched.contains(_kNegativeSpeechThreshold)
            ? current.negativeSpeechThreshold
            : await store.getDouble(_kNegativeSpeechThreshold) ??
                current.negativeSpeechThreshold,
        redemptionFrames: _touched.contains(_kRedemptionFrames)
            ? current.redemptionFrames
            : await store.getInt(_kRedemptionFrames) ??
                current.redemptionFrames,
        preSpeechPadFrames: _touched.contains(_kPreSpeechPadFrames)
            ? current.preSpeechPadFrames
            : await store.getInt(_kPreSpeechPadFrames) ??
                current.preSpeechPadFrames,
        minSpeechFrames: _touched.contains(_kMinSpeechFrames)
            ? current.minSpeechFrames
            : await store.getInt(_kMinSpeechFrames) ??
                current.minSpeechFrames,
        endSpeechPadFrames: _touched.contains(_kEndSpeechPadFrames)
            ? current.endSpeechPadFrames
            : await store.getInt(_kEndSpeechPadFrames) ??
                current.endSpeechPadFrames,
      );
      if (!ref.mounted) return;
      state = loaded;
    } catch (e) {
      debugPrint('[Settings] ⚠️ Could not load persisted settings: $e');
    }
  }

  /// Fire-and-forget write; sync and async failures only log so the
  /// UI never blocks and setters never throw.
  void _persist(Future<void> Function() write) {
    Future<void> future;
    try {
      future = write();
    } catch (e) {
      debugPrint('[Settings] ⚠️ Could not persist setting: $e');
      return;
    }
    unawaited(future.then(
      (_) {},
      onError: (Object e) {
        debugPrint('[Settings] ⚠️ Could not persist setting: $e');
      },
    ));
  }

  SettingsStore get _store => ref.read(settingsStoreProvider);

  void setMicGain(double gain) {
    _touched.add(_kMicGain);
    state = state.copyWith(micGain: gain);
    _persist(() => _store.setDouble(_kMicGain, gain));
  }

  void setAudioSource(AndroidAudioSource source) {
    _touched.add(_kAudioSource);
    state = state.copyWith(audioSource: source);
    _persist(() => _store.setString(_kAudioSource, source.name));
  }

  void setIpAddress(String ip) {
    _touched.add(_kIpAddress);
    state = state.copyWith(ipAddress: ip);
    _persist(() => _store.setString(_kIpAddress, ip));
  }

  void setSaveAudio(bool enabled) {
    _touched.add(_kSaveAudio);
    state = state.copyWith(saveAudio: enabled);
    _persist(() => _store.setBool(_kSaveAudio, enabled));
  }

  void setSaveAudioLocal(bool enabled) {
    _touched.add(_kSaveAudioLocal);
    state = state.copyWith(saveAudioLocal: enabled);
    _persist(() => _store.setBool(_kSaveAudioLocal, enabled));
  }

  void setSaveAudioWeb(bool enabled) {
    _touched.add(_kSaveAudioWeb);
    state = state.copyWith(saveAudioWeb: enabled);
    _persist(() => _store.setBool(_kSaveAudioWeb, enabled));
  }

  void setAudioFormat(AudioSaveFormat format) {
    _touched.add(_kAudioFormat);
    state = state.copyWith(audioFormat: format);
    _persist(() => _store.setString(_kAudioFormat, format.name));
  }

  void setTargetLanguage(TargetLanguage language) {
    _touched.add(_kTargetLanguage);
    state = state.copyWith(targetLanguage: language);
    _persist(() => _store.setString(_kTargetLanguage, language.name));
  }

  void setFrameSamples(int value) {
    _touched.add(_kFrameSamples);
    state = state.copyWith(frameSamples: value);
    _persist(() => _store.setInt(_kFrameSamples, value));
  }

  void setPositiveSpeechThreshold(double value) {
    _touched.add(_kPositiveSpeechThreshold);
    state = state.copyWith(positiveSpeechThreshold: value);
    _persist(() => _store.setDouble(_kPositiveSpeechThreshold, value));
  }

  void setNegativeSpeechThreshold(double value) {
    _touched.add(_kNegativeSpeechThreshold);
    state = state.copyWith(negativeSpeechThreshold: value);
    _persist(() => _store.setDouble(_kNegativeSpeechThreshold, value));
  }

  void setRedemptionFrames(int value) {
    _touched.add(_kRedemptionFrames);
    state = state.copyWith(redemptionFrames: value);
    _persist(() => _store.setInt(_kRedemptionFrames, value));
  }

  void setPreSpeechPadFrames(int value) {
    _touched.add(_kPreSpeechPadFrames);
    state = state.copyWith(preSpeechPadFrames: value);
    _persist(() => _store.setInt(_kPreSpeechPadFrames, value));
  }

  void setMinSpeechFrames(int value) {
    _touched.add(_kMinSpeechFrames);
    state = state.copyWith(minSpeechFrames: value);
    _persist(() => _store.setInt(_kMinSpeechFrames, value));
  }

  void setEndSpeechPadFrames(int value) {
    _touched.add(_kEndSpeechPadFrames);
    state = state.copyWith(endSpeechPadFrames: value);
    _persist(() => _store.setInt(_kEndSpeechPadFrames, value));
  }

  void resetVadDefaults() {
    setFrameSamples(kDefaultFrameSamples);
    setPositiveSpeechThreshold(kDefaultPositiveSpeechThreshold);
    setNegativeSpeechThreshold(kDefaultNegativeSpeechThreshold);
    setRedemptionFrames(kDefaultRedemptionFrames);
    setPreSpeechPadFrames(kDefaultPreSpeechPadFrames);
    setMinSpeechFrames(kDefaultMinSpeechFrames);
    setEndSpeechPadFrames(kDefaultEndSpeechPadFrames);
  }
}

T _enumByName<T extends Enum>(List<T> values, String? name, T fallback) {
  if (name == null) return fallback;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, SettingsState>(
  SettingsNotifier.new,
);
