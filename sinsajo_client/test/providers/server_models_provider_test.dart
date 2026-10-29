import 'package:flutter_test/flutter_test.dart';
import 'package:sinsajo_client/providers/server_models_provider.dart';

void main() {
  group('ServerModelEntry', () {
    test('parses a model list entry', () {
      final entry = ServerModelEntry.fromJson(const {
        'name': 'Canary180M',
        'display': 'Canary 180M',
        'dir': 'canary-180m',
        'installed': true,
        'active': false,
        'files': 3,
      });

      expect(entry.name, 'Canary180M');
      expect(entry.display, 'Canary 180M');
      expect(entry.dir, 'canary-180m');
      expect(entry.installed, isTrue);
      expect(entry.active, isFalse);
      expect(entry.files, 3);
    });

    test('falls back to the name when display is missing', () {
      final entry = ServerModelEntry.fromJson(const {'name': 'MoonshineTiny'});

      expect(entry.display, 'MoonshineTiny');
      expect(entry.installed, isFalse);
      expect(entry.files, 0);
    });
  });

  group('ServerModelsState', () {
    test('is busy while an action is started', () {
      const state = ServerModelsState(
        action: 'download',
        actionModel: 'Canary180M',
        actionState: 'started',
      );

      expect(state.isBusy, isTrue);
      expect(state.isDownloading, isTrue);
    });

    test('is not busy after the action completes', () {
      const state = ServerModelsState(
        action: 'download',
        actionModel: 'Canary180M',
        actionState: 'completed',
      );

      expect(state.isBusy, isFalse);
      expect(state.isDownloading, isFalse);
    });

    test('copyWith clears action state and download progress', () {
      const state = ServerModelsState(
        action: 'download',
        actionModel: 'Canary180M',
        actionState: 'started',
        downloadFile: 'model.onnx',
        downloadPercent: 40,
        downloadedBytes: 400,
        totalBytes: 1000,
      );

      final cleared = state.copyWith(clearAction: true);

      expect(cleared.action, isNull);
      expect(cleared.actionModel, isNull);
      expect(cleared.actionState, isNull);
      expect(cleared.downloadFile, isNull);
      expect(cleared.downloadPercent, 0);
      expect(cleared.downloadedBytes, 0);
      expect(cleared.totalBytes, 0);
    });
  });
}
