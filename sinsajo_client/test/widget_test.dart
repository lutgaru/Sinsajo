import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinsajo_client/main.dart';
import 'package:sinsajo_client/screens/transcription_screen.dart';
import 'package:sinsajo_client/providers/transcription_provider.dart';
import 'package:sinsajo_client/services/ws_service.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('WhisperApp', () {
    testWidgets('renders without crashing', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: WhisperApp()),
      );
      await tester.pump();

      expect(find.byType(MaterialApp), findsOneWidget);
      expect(find.byType(TranscriptionScreen), findsOneWidget);
    });

    testWidgets('shows app title in AppBar', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: WhisperApp()),
      );
      await tester.pump();

      expect(find.text('Whisper Local'), findsOneWidget);
    });
  });

  group('TranscriptionScreen', () {
    testWidgets('shows initial prompt when not recording', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: WhisperApp()),
      );
      await tester.pump();

      expect(
        find.text('Presiona el micrófono para comenzar'),
        findsOneWidget,
      );
    });

    testWidgets('shows microphone button', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: WhisperApp()),
      );
      await tester.pump();

      expect(find.byIcon(Icons.mic), findsOneWidget);
    });

    testWidgets('shows copy and clear buttons', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: WhisperApp()),
      );
      await tester.pump();

      expect(find.byIcon(Icons.copy), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });

    testWidgets('copy and clear buttons are disabled when no text', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: WhisperApp()),
      );
      await tester.pump();

      // Buscar los botones de copiar y limpiar por ícono
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