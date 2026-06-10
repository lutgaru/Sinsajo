// lib/services/ws_service.dart
//
// Maneja la conexión WebSocket con el wrapper Python.
// Protocolo:
//   → JSON  { "type": "start" | "stop" | "ping" }
//   → BINARY  raw PCM int16
//   ← JSON  { "type": "partial"|"final"|"error"|"status", "text"|"message": "..." }

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';

enum WsStatus { disconnected, connecting, connected, error }

class WsMessage {
  final String type;     // partial, final, error, status, pong
  final String content;
  WsMessage(this.type, this.content);
}

class WsService {
  final String url;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;

  final _statusController  = StreamController<WsStatus>.broadcast();
  final _messageController = StreamController<WsMessage>.broadcast();

  Stream<WsStatus>   get statusStream  => _statusController.stream;
  Stream<WsMessage>  get messageStream => _messageController.stream;

  WsStatus _status = WsStatus.disconnected;
  WsStatus get status => _status;

  WsService({required this.url});

  // ────────────────────────────────────────────────
  // Connect / Disconnect
  // ────────────────────────────────────────────────

  Future<void> connect() async {
    if (_status == WsStatus.connected) return;

    _setStatus(WsStatus.connecting);

    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      await _channel!.ready;

      _setStatus(WsStatus.connected);

      _sub = _channel!.stream.listen(
        _onMessage,
        onError: (e) {
          _setStatus(WsStatus.error);
          _messageController.add(WsMessage('error', e.toString()));
        },
        onDone: () {
          _setStatus(WsStatus.disconnected);
        },
      );
    } catch (e) {
      _setStatus(WsStatus.error);
      _messageController.add(WsMessage('error', 'Connection failed: $e'));
    }
  }

  Future<void> disconnect() async {
    await _sub?.cancel();
    await _channel?.sink.close();
    _channel = null;
    _setStatus(WsStatus.disconnected);
  }

  // ────────────────────────────────────────────────
  // Send
  // ────────────────────────────────────────────────

  void sendStart({int sampleRate = 16000}) {
    _sendJson({'type': 'start', 'sample_rate': sampleRate});
  }

  void sendStop() {
    _sendJson({'type': 'stop'});
  }

  void sendAudioChunk(Uint8List pcmBytes) {
    if (_status != WsStatus.connected) return;
    _channel?.sink.add(pcmBytes);
  }

  // ────────────────────────────────────────────────
  // Internal
  // ────────────────────────────────────────────────

  void _sendJson(Map<String, dynamic> msg) {
    if (_status != WsStatus.connected) return;
    _channel?.sink.add(jsonEncode(msg));
  }

  void _onMessage(dynamic raw) {
    if (raw is! String) return;

    try {
      final map  = jsonDecode(raw) as Map<String, dynamic>;
      final type = map['type'] as String? ?? 'unknown';
      final text = (map['text'] ?? map['message'] ?? '') as String;
      _messageController.add(WsMessage(type, text));
    } catch (_) {
      // ignore malformed
    }
  }

  void _setStatus(WsStatus s) {
    _status = s;
    _statusController.add(s);
  }

  void dispose() {
    disconnect();
    _statusController.close();
    _messageController.close();
  }
}
