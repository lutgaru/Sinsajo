import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinsajo_client/providers/settings_provider.dart';

Future<void> _waitFor(FutureOr<bool> Function() condition) async {
  for (var i = 0; i < 200; i++) {
    if (await condition()) return;
    await Future.delayed(const Duration(milliseconds: 10));
  }
  throw StateError('Timed out waiting for condition');
}

/// In-memory [SettingsStore] fake: writes land synchronously.
class InMemorySettingsStore implements SettingsStore {
  InMemorySettingsStore([Map<String, Object>? initial])
      : data = {...?initial};

  final Map<String, Object> data;

  @override
  Future<bool?> getBool(String key) async => data[key] is bool
      ? data[key] as bool
      : null;

  @override
  Future<int?> getInt(String key) async => data[key] is int
      ? data[key] as int
      : null;

  @override
  Future<double?> getDouble(String key) async => data[key] is double
      ? data[key] as double
      : null;

  @override
  Future<String?> getString(String key) async => data[key] is String
      ? data[key] as String
      : null;

  @override
  Future<void> setBool(String key, bool value) async {
    data[key] = value;
  }

  @override
  Future<void> setInt(String key, int value) async {
    data[key] = value;
  }

  @override
  Future<void> setDouble(String key, double value) async {
    data[key] = value;
  }

  @override
  Future<void> setString(String key, String value) async {
    data[key] = value;
  }
}

void main() {
  group('TargetLanguage', () {
    test('has the five supported languages with codes', () {
      expect(TargetLanguage.values, hasLength(5));

      expect(TargetLanguage.english.label, 'English');
      expect(TargetLanguage.english.code, 'en');
      expect(TargetLanguage.spanish.label, 'Spanish');
      expect(TargetLanguage.spanish.code, 'es');
      expect(TargetLanguage.french.label, 'French');
      expect(TargetLanguage.french.code, 'fr');
      expect(TargetLanguage.german.label, 'German');
      expect(TargetLanguage.german.code, 'de');
      expect(TargetLanguage.portuguese.label, 'Portuguese');
      expect(TargetLanguage.portuguese.code, 'pt');
    });
  });

  group('SettingsState', () {
    test('defaults to English target language', () {
      const state = SettingsState();

      expect(state.targetLanguage, TargetLanguage.english);
    });

    test('defaults to local audio saving disabled', () {
      const state = SettingsState();

      expect(state.saveAudioLocal, isFalse);
    });

    test('copyWith updates targetLanguage', () {
      const state = SettingsState();
      final updated = state.copyWith(targetLanguage: TargetLanguage.spanish);

      expect(updated.targetLanguage, TargetLanguage.spanish);
      expect(updated.micGain, state.micGain);
      expect(updated.audioFormat, state.audioFormat);
    });
  });

  group('SettingsNotifier', () {
    test('setTargetLanguage updates state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(settingsProvider.notifier).setTargetLanguage(TargetLanguage.portuguese);

      expect(container.read(settingsProvider).targetLanguage, TargetLanguage.portuguese);
    });

    test('setSaveAudioLocal updates state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(settingsProvider).saveAudioLocal, isFalse);

      container.read(settingsProvider.notifier).setSaveAudioLocal(true);

      expect(container.read(settingsProvider).saveAudioLocal, isTrue);
    });

    test('local and web audio saving default to disabled', () {
      const state = SettingsState();

      expect(state.saveAudioLocal, isFalse);
      expect(state.saveAudioWeb, isFalse);
    });

    test('setSaveAudioWeb updates state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(settingsProvider.notifier).setSaveAudioWeb(true);

      expect(container.read(settingsProvider).saveAudioWeb, isTrue);
      expect(container.read(settingsProvider).saveAudioLocal, isFalse);
    });
  });

  group('Settings persistence', () {
    ProviderContainer containerWithStore(SettingsStore store) {
      final container = ProviderContainer(
        overrides: [
          settingsStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('hydrates persisted values on start', () async {
      final container = containerWithStore(InMemorySettingsStore({
        'sinsajo.settings.micGain': 2.5,
        'sinsajo.settings.ipAddress': '10.0.0.5',
        'sinsajo.settings.targetLanguage': 'spanish',
        'sinsajo.settings.frameSamples': 1024,
        'sinsajo.settings.saveAudioLocal': true,
      }));

      await _waitFor(
        () => container.read(settingsProvider).micGain == 2.5,
      );

      final state = container.read(settingsProvider);
      expect(state.micGain, 2.5);
      expect(state.ipAddress, '10.0.0.5');
      expect(state.targetLanguage, TargetLanguage.spanish);
      expect(state.frameSamples, 1024);
      expect(state.saveAudioLocal, isTrue);
      // Keys with no stored value keep their defaults.
      expect(state.saveAudioWeb, isFalse);
      expect(state.positiveSpeechThreshold, 0.45);
    });

    test('setters persist through to storage', () async {
      final store = InMemorySettingsStore();
      final container = containerWithStore(store);

      container.read(settingsProvider.notifier).setMicGain(1.5);
      container
          .read(settingsProvider.notifier)
          .setTargetLanguage(TargetLanguage.german);
      container.read(settingsProvider.notifier).setSaveAudioWeb(true);

      expect(store.data['sinsajo.settings.micGain'], 1.5);
      expect(store.data['sinsajo.settings.targetLanguage'], 'german');
      expect(store.data['sinsajo.settings.saveAudioWeb'], true);
    });

    test('unknown enum names fall back to defaults', () async {
      final container = containerWithStore(InMemorySettingsStore({
        'sinsajo.settings.micGain': 2.0,
        'sinsajo.settings.targetLanguage': 'klingon',
        'sinsajo.settings.audioSource': 'nope',
      }));

      // micGain proves hydration ran; enums must fall back, not crash.
      await _waitFor(
        () => container.read(settingsProvider).micGain == 2.0,
      );

      final state = container.read(settingsProvider);
      expect(state.targetLanguage, TargetLanguage.english);
    });

    test('a user edit before hydration finishes is not clobbered', () async {
      final store = InMemorySettingsStore({
        'sinsajo.settings.micGain': 2.5,
      });
      final container = containerWithStore(store);

      container.read(settingsProvider.notifier).setMicGain(1.5);

      // Give hydration time to finish, then confirm the user value won.
      await Future.delayed(const Duration(milliseconds: 100));

      expect(container.read(settingsProvider).micGain, 1.5);
      expect(store.data['sinsajo.settings.micGain'], 1.5);
    });
  });
}