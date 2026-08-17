import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinsajo_client/providers/settings_provider.dart';

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
  });
}