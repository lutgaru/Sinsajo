import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinsajo_client/main.dart';
import 'package:sinsajo_client/screens/transcription_screen.dart';
import 'package:sinsajo_client/providers/transcription_provider.dart';
import 'package:sinsajo_client/providers/server_models_provider.dart';
import 'package:sinsajo_client/services/ws_service.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('SinsajoApp', () {
    testWidgets('renders without crashing', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: SinsajoApp()),
      );
      await tester.pump();

      expect(find.byType(MaterialApp), findsOneWidget);
      expect(find.byType(TranscriptionScreen), findsOneWidget);
    });

    testWidgets('shows app title in AppBar', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: SinsajoApp()),
      );
      await tester.pump();

      expect(find.text('Sinsajo client'), findsOneWidget);
    });
  });

  group('TranscriptionScreen', () {
    testWidgets('shows initial prompt when not recording', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: SinsajoApp()),
      );
      await tester.pump();

      expect(
        find.text('Press the microphone to start'),
        findsOneWidget,
      );
    });

    testWidgets('shows microphone button', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: SinsajoApp()),
      );
      await tester.pump();

      expect(find.byIcon(Icons.mic), findsOneWidget);
    });

    testWidgets('shows copy and clear buttons', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: SinsajoApp()),
      );
      await tester.pump();

      expect(find.byIcon(Icons.copy), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });

    testWidgets('copy and clear buttons are disabled when no text', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: SinsajoApp()),
      );
      await tester.pump();

      // Find the copy and clear buttons by icon
      final copyIcon  = find.byIcon(Icons.copy);
      final clearIcon = find.byIcon(Icons.delete_outline);
      
      expect(copyIcon,  findsOneWidget);
      expect(clearIcon, findsOneWidget);
      
      final copyButton  = tester.widget<IconButton>(
        find.ancestor(of: copyIcon, matching: find.byType(IconButton)),
      );
      final clearButton = tester.widget<IconButton>(
        find.ancestor(of: clearIcon, matching: find.byType(IconButton)),
      );
      
      expect(copyButton.onPressed,  isNull);
      expect(clearButton.onPressed, isNull);
    });
  });

  group('TranscriptionState', () {
    test('initial state has correct defaults', () {
      const state = TranscriptionState();

      expect(state.isRecording, false);
      expect(state.wsStatus, WsStatus.disconnected);
      expect(state.segments, isEmpty);
      expect(state.error, isNull);
      expect(state.fullText, '');
    });

    test('fullText joins segments with spaces', () {
      const state = TranscriptionState(
        segments: ['Hola', 'mundo', 'test'],
      );

      expect(state.fullText, 'Hola mundo test');
    });

    test('copyWith updates isRecording', () {
      const state = TranscriptionState();
      final newState = state.copyWith(isRecording: true);

      expect(newState.isRecording, true);
      expect(newState.wsStatus, state.wsStatus);
      expect(newState.segments, state.segments);
    });

    test('copyWith updates wsStatus', () {
      const state = TranscriptionState();
      final newState = state.copyWith(wsStatus: WsStatus.connected);

      expect(newState.wsStatus, WsStatus.connected);
      expect(newState.isRecording, state.isRecording);
    });

    test('copyWith appends segments', () {
      const state = TranscriptionState(segments: ['Hola']);
      final newState = state.copyWith(
        segments: [...state.segments, 'mundo'],
      );

      expect(newState.segments, ['Hola', 'mundo']);
      expect(newState.fullText, 'Hola mundo');
    });

    test('copyWith updates error', () {
      const state = TranscriptionState();
      final newState = state.copyWith(error: 'Test error');

      expect(newState.error, 'Test error');
    });

    test('copyWith preserves unchanged fields', () {
      const state = TranscriptionState(
        isRecording: true,
        wsStatus: WsStatus.connected,
        segments: ['test'],
        error: 'err',
      );

      final newState = state.copyWith(isRecording: false);

      expect(newState.isRecording, false);
      expect(newState.wsStatus, WsStatus.connected);
      expect(newState.segments, ['test']);
      expect(newState.error, 'err');
    });

    test('copyWith clearError removes error', () {
      const state = TranscriptionState(error: 'test error');
      final newState = state.copyWith(clearError: true);

      expect(newState.error, isNull);
    });

    test('copyWith updates server model info', () {
      const state = TranscriptionState();
      final newState = state.copyWith(
        serverModel: 'Canary180M',
        supportedLanguages: const ['en', 'es', 'fr', 'de', 'pt'],
      );

      expect(newState.serverModel, 'Canary180M');
      expect(newState.supportedLanguages, ['en', 'es', 'fr', 'de', 'pt']);
      expect(newState.wsStatus, state.wsStatus);
    });
  });

  group('ServerModelsState', () {
    test('copyWith updates aggregate download progress', () {
      const state = ServerModelsState();
      final updated = state.copyWith(
        downloadFile: 'encoder.onnx',
        downloadPercent: 42,
        downloadedBytes: 120,
        totalBytes: 300,
        downloadFraction: 0.42,
        downloadFilesDone: 1,
        downloadFilesTotal: 3,
      );

      expect(updated.downloadFile, 'encoder.onnx');
      expect(updated.downloadPercent, 42);
      expect(updated.downloadedBytes, 120);
      expect(updated.totalBytes, 300);
      expect(updated.downloadFraction, 0.42);
      expect(updated.downloadFilesDone, 1);
      expect(updated.downloadFilesTotal, 3);
    });

    test('clearDownload resets aggregate progress', () {
      const state = ServerModelsState(
        downloadFile: 'encoder.onnx',
        downloadPercent: 42,
        downloadedBytes: 120,
        totalBytes: 300,
        downloadFraction: 0.42,
        downloadFilesDone: 1,
        downloadFilesTotal: 3,
      );
      final cleared = state.copyWith(clearDownload: true);

      expect(cleared.downloadFile, isNull);
      expect(cleared.downloadPercent, 0);
      expect(cleared.downloadedBytes, 0);
      expect(cleared.totalBytes, 0);
      expect(cleared.downloadFraction, 0);
      expect(cleared.downloadFilesDone, 0);
      expect(cleared.downloadFilesTotal, 0);
    });
  });

  group('downloadFractionFromProgress', () {
    test('weights every file equally', () {
      expect(
        downloadFractionFromProgress(const {
          'files_done': 0,
          'files_total': 2,
          'file_downloaded': 50,
          'file_total': 100,
        }),
        closeTo(0.25, 1e-9),
      );
      expect(
        downloadFractionFromProgress(const {
          'files_done': 1,
          'files_total': 2,
          'file_downloaded': 50,
          'file_total': 100,
        }),
        closeTo(0.75, 1e-9),
      );
    });

    test('does not drop at a file boundary', () {
      final completed = downloadFractionFromProgress(const {
        'files_done': 0,
        'files_total': 2,
        'file_downloaded': 100,
        'file_total': 100,
        'file_complete': true,
      });
      final nextFile = downloadFractionFromProgress(const {
        'files_done': 1,
        'files_total': 2,
        'file_downloaded': 0,
        'file_total': 100,
      });

      expect(completed, closeTo(0.5, 1e-9));
      expect(nextFile, closeTo(completed, 1e-9));
    });

    test('advances unknown-size files only once they complete', () {
      const inProgress = {
        'files_done': 1,
        'files_total': 4,
        'file_downloaded': 999,
        'file_total': 0,
      };
      final completed = {...inProgress, 'file_complete': true};

      expect(downloadFractionFromProgress(inProgress), closeTo(0.25, 1e-9));
      expect(downloadFractionFromProgress(completed), closeTo(0.5, 1e-9));
    });

    test('falls back to the reported percent for older servers', () {
      expect(
        downloadFractionFromProgress(const {
          'downloaded': 42,
          'total': 100,
          'percent': 42,
        }),
        closeTo(0.42, 1e-9),
      );
      expect(
        downloadFractionFromProgress(const {'downloaded': 1, 'total': 4}),
        closeTo(0.25, 1e-9),
      );
    });
  });

  group('WsMessage', () {
    test('stores type and content', () {
      final msg = WsMessage('transcription', 'Hello world');

      expect(msg.type, 'transcription');
      expect(msg.content, 'Hello world');
    });

    test('handles empty content', () {
      final msg = WsMessage('status', '');

      expect(msg.type, 'status');
      expect(msg.content, '');
    });

    test('stores model info fields', () {
      final msg = WsMessage(
        'model_info',
        '',
        model: 'Canary180M',
        languages: const ['en', 'es', 'fr', 'de', 'pt'],
      );

      expect(msg.type, 'model_info');
      expect(msg.model, 'Canary180M');
      expect(msg.languages, ['en', 'es', 'fr', 'de', 'pt']);
    });

    test('model info fields are null by default', () {
      final msg = WsMessage('status', 'ready');

      expect(msg.model, isNull);
      expect(msg.languages, isNull);
      expect(msg.data, isEmpty);
    });

    test('stores the full decoded payload', () {
      final msg = WsMessage(
        'model_download_progress',
        '',
        data: const {
          'model': 'Canary180M',
          'file': 'model.onnx',
          'file_downloaded': 50,
          'file_total': 100,
          'file_complete': false,
          'downloaded': 42,
          'total': 100,
          'percent': 42,
          'files_done': 1,
          'files_total': 3,
        },
      );

      expect(msg.data['file'], 'model.onnx');
      expect(msg.data['percent'], 42);
      expect(msg.data['files_total'], 3);
    });
  });

  group('WsStatus', () {
    test('has all expected values', () {
      expect(WsStatus.values, hasLength(4));
      expect(WsStatus.values, contains(WsStatus.disconnected));
      expect(WsStatus.values, contains(WsStatus.connecting));
      expect(WsStatus.values, contains(WsStatus.connected));
      expect(WsStatus.values, contains(WsStatus.error));
    });
  });
}