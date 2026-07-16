import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinsajo_client/services/ws_service.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('WsService', () {
    test('initial status is disconnected', () {
      final service = WsService(url: 'ws://localhost:8765');

      expect(service.status, WsStatus.disconnected);
      
      service.dispose();
    });

    test('dispose can be called safely', () {
      final service = WsService(url: 'ws://localhost:8765');

      // Should not throw an exception
      service.dispose();
      service.dispose(); // Calling twice should not fail either
    });

    test('messageStream can be listened to', () async {
      final service = WsService(url: 'ws://localhost:8765');

      expect(service.messageStream, isNotNull);

      service.dispose();
    });
  });

  group('WsMessage parsing', () {
    test('parses transcription message', () {
      final json = '{"type": "transcription", "text": "Hello world"}';
      final map = jsonDecode(json) as Map<String, dynamic>;

      final type = map['type'] as String;
      final text = map['text'] as String;

      expect(type, 'transcription');
      expect(text, 'Hello world');
    });

    test('parses error message', () {
      final json = '{"type": "error", "message": "Connection failed"}';
      final map = jsonDecode(json) as Map<String, dynamic>;

      final type = map['type'] as String;
      final message = map['message'] as String;

      expect(type, 'error');
      expect(message, 'Connection failed');
    });

    test('parses status message', () {
      final json = '{"type": "status", "message": "ready"}';
      final map = jsonDecode(json) as Map<String, dynamic>;

      final type = map['type'] as String;
      final message = map['message'] as String;

      expect(type, 'status');
      expect(message, 'ready');
    });

    test('handles missing text field', () {
      final json = '{"type": "status"}';
      final map = jsonDecode(json) as Map<String, dynamic>;

      final text = (map['text'] ?? map['message'] ?? '') as String;

      expect(text, '');
    });
  });

  group('JSON encoding', () {
    test('encodes start message', () {
      final msg = {'type': 'start', 'sample_rate': 16000};
      final encoded = jsonEncode(msg);
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;

      expect(decoded['type'], 'start');
      expect(decoded['sample_rate'], 16000);
    });

    test('encodes stop message', () {
      final msg = {'type': 'stop'};
      final encoded = jsonEncode(msg);
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;

      expect(decoded['type'], 'stop');
    });
  });
}