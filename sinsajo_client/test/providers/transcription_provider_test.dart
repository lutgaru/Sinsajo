import 'package:flutter_test/flutter_test.dart';
import 'package:sinsajo_client/providers/transcription_provider.dart';
import 'package:sinsajo_client/services/ws_service.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('TranscriptionState', () {
    test('segments accumulate correctly', () {
      var state = const TranscriptionState();

      state = state.copyWith(segments: [...state.segments, 'Hello']);
      expect(state.fullText, 'Hello');

      state = state.copyWith(segments: [...state.segments, 'world']);
      expect(state.fullText, 'Hello world');

      state = state.copyWith(segments: [...state.segments, 'test']);
      expect(state.fullText, 'Hello world test');
    });

    test('clear transcription resets segments', () {
      var state = const TranscriptionState(
        segments: ['Hello', 'world'],
      );

      expect(state.fullText, 'Hello world');

      state = state.copyWith(segments: []);

      expect(state.fullText, '');
      expect(state.segments, isEmpty);
    });

    test('recording state transitions', () {
      var state = const TranscriptionState();

      state = state.copyWith(isRecording: true);
      expect(state.isRecording, true);

      state = state.copyWith(isRecording: false);
      expect(state.isRecording, false);
    });

    test('connection state transitions', () {
      var state = const TranscriptionState();

      state = state.copyWith(wsStatus: WsStatus.connecting);
      expect(state.wsStatus, WsStatus.connecting);

      state = state.copyWith(wsStatus: WsStatus.connected);
      expect(state.wsStatus, WsStatus.connected);

      state = state.copyWith(wsStatus: WsStatus.disconnected);
      expect(state.wsStatus, WsStatus.disconnected);
    });

    test('error state handling', () {
      var state = const TranscriptionState();

      state = state.copyWith(error: 'Connection failed');
      expect(state.error, 'Connection failed');

      state = state.copyWith(clearError: true);
      expect(state.error, isNull);
    });

    test('complex state update', () {
      var state = const TranscriptionState();

      state = state.copyWith(wsStatus: WsStatus.connecting);
      state = state.copyWith(wsStatus: WsStatus.connected);
      state = state.copyWith(isRecording: true);
      state = state.copyWith(segments: ['Hola']);
      state = state.copyWith(segments: [...state.segments, 'mundo']);
      state = state.copyWith(isRecording: false);

      expect(state.wsStatus, WsStatus.connected);
      expect(state.isRecording, false);
      expect(state.fullText, 'Hola mundo');
      expect(state.error, isNull);
    });
  });
}