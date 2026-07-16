// lib/services/ws_service.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum WsStatus { disconnected, connecting, connected, error }

class WsMessage {
  final String type;
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

  bool _isDisposed          = false;
  bool _intentionalDisconnect = false;

  Timer?  _reconnectTimer;
  int     _reconnectAttempts = 0;
  static const int     _maxReconnectAttempts = 10;
  static const Duration _reconnectDelay      = Duration(seconds: 2);

  WsService({required this.url});

  Future<void> connect() async {
    if (_status == WsStatus.connected || _isDisposed) return;

    _sub?.cancel();
    _sub = null;
    await _channel?.sink.close();
    _channel = null;

    _intentionalDisconnect = false;
    _setStatus(WsStatus.connecting);

    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      await _channel!.ready;

      _setStatus(WsStatus.connected);
      _reconnectAttempts = 0;
      debugPrint('[WS] ✅ Connected to $url');

      _sub = _channel!.stream.listen(
        _onMessage,
        onError: (e) {
          debugPrint('[WS] ❌ Error: $e');
          _setStatus(WsStatus.error);
          _messageController.add(WsMessage('error', e.toString()));
          _scheduleReconnect();
        },
        onDone: () {
          debugPrint('[WS] 🔌 Disconnected');
          _setStatus(WsStatus.disconnected);
          if (!_intentionalDisconnect && !_isDisposed) {
            _scheduleReconnect();
          }
        },
      );
    } catch (e) {
      debugPrint('[WS] ❌ Connection failed: $e');
      _setStatus(WsStatus.error);
      _messageController.add(WsMessage('error', 'Connection failed: $e'));
      if (!_intentionalDisconnect && !_isDisposed) {
        _scheduleReconnect();
      }
    }
  }

  void _scheduleReconnect() {
    if (_isDisposed || _intentionalDisconnect) return;
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint('[WS] ⚠ Max reconnection attempts reached');
      return;
    }
    _reconnectTimer?.cancel();
    _reconnectAttempts++;
    debugPrint('[WS] 🔄 Retrying in ${_reconnectDelay.inSeconds}s '
        '(attempt $_reconnectAttempts/$_maxReconnectAttempts)');
    _reconnectTimer = Timer(_reconnectDelay, () {
      if (!_isDisposed && !_intentionalDisconnect) {
        connect();
      }
    });
  }

  Future<void> disconnect() async {
    if (_isDisposed) return;
    _intentionalDisconnect = true;
    _reconnectTimer?.cancel();

    await _sub?.cancel();
    _sub = null;

    await _channel?.sink.close();
    _channel = null;

    _setStatus(WsStatus.disconnected);
  }

  void sendStart({int sampleRate = 16000}) {
    _sendJson({'type': 'start', 'sample_rate': sampleRate});
  }

  void sendStop() {
    _sendJson({'type': 'stop'});
  }

  void sendClean() {
    _sendJson({'type': 'clean'});
  }

  void sendDiscard() {
    _sendJson({'type': 'discard'});
  }

  void sendAudioChunk(Uint8List pcmBytes) {
    if (_status != WsStatus.connected) {
      debugPrint('[WS] ⚠ Audio not sent: not connected');
      return;
    }
    _channel?.sink.add(pcmBytes);
  }

  void _sendJson(Map<String, dynamic> msg) {
    if (_status != WsStatus.connected || _isDisposed) {
      debugPrint('[WS] ⚠ JSON not sent: not connected');
      return;
    }
    debugPrint('[WS] → Sending: $msg');
    _channel?.sink.add(jsonEncode(msg));
  }

  void _onMessage(dynamic raw) {
    if (raw is! String || _isDisposed) {
      debugPrint('[WS] ← Non-string message received');
      return;
    }

    try {
      final map  = jsonDecode(raw) as Map<String, dynamic>;
      final type = map['type'] as String? ?? 'unknown';
      final text = (map['text'] ?? map['message'] ?? '') as String;
      _messageController.add(WsMessage(type, text));
    } catch (e) {
      debugPrint('[WS] ⚠ Error parsing message: $e');
    }
  }

  void _setStatus(WsStatus s) {
    if (_isDisposed) return;
    _status = s;
    _statusController.add(s);
  }

  void dispose() {
    _isDisposed = true;
    disconnect();
    _statusController.close();
    _messageController.close();
  }
}