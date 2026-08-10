// lib/services/ws_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:math';
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
  Timer?  _connectTimer;
  int     _reconnectAttempts = 0;
  DateTime? _connectedAt;

  // Reconnection policy: exponential backoff with jitter, bounded.
  // This keeps the retry rate low so a crashed/restarting server is not
  // hammered by the client (network/device load stays minimal).
  static const Duration _baseDelay       = Duration(seconds: 1);
  static const Duration _maxDelay        = Duration(seconds: 15);
  static const Duration _stableThreshold = Duration(seconds: 10);
  static const Duration _connectTimeout  = Duration(seconds: 8);
  static const double   _jitterFactor    = 0.25; // +/-25% random jitter
  final      Random    _random          = Random();
  Duration   _currentDelay = _baseDelay;

  WsService({required this.url});

  int _connectSeq = 0;

  Future<void> connect() async {
    if (_status == WsStatus.connected || _isDisposed) return;

    final seq = ++_connectSeq;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _connectTimer?.cancel();
    _connectTimer = null;
    _sub?.cancel();
    _sub = null;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;

    _intentionalDisconnect = false;
    _setStatus(WsStatus.connecting);

    try {
      final channel = WebSocketChannel.connect(Uri.parse(url));
      _channel = channel;

      // Subscribe BEFORE awaiting `ready`: on web, an unreachable server can
      // leave the handshake future pending forever. With the listener attached
      // immediately + a cancellable timeout we guarantee the retry loop always
      // advances without leaking a timer.
      _sub = channel.stream.listen(
        _onMessage,
        onError: (e) {
          debugPrint('[WS] ❌ Error: $e');
          _messageController.add(WsMessage('error', e.toString()));
          _handleDisconnect();
        },
        onDone: () {
          debugPrint('[WS] 🔌 Disconnected');
          _handleDisconnect();
        },
      );

      // Manual timeout instead of Future.timeout: a plain `.timeout()`
      // timer cannot be cancelled, which breaks widget tests that dispose
      // the tree while a connect attempt is in flight.
      final completer = Completer<void>();
      _connectTimer = Timer(_connectTimeout, () {
        if (!completer.isCompleted) {
          completer.completeError(TimeoutException('WS connect timed out'));
        }
      });
      channel.ready.then(
        (_) {
          if (!completer.isCompleted) completer.complete();
        },
        onError: (e) {
          if (!completer.isCompleted) completer.completeError(e);
        },
      );

      await completer.future;

      // A newer connect() started while this one was in flight; ignore it.
      if (seq != _connectSeq || _isDisposed || _intentionalDisconnect) return;

      _connectedAt = DateTime.now();
      _setStatus(WsStatus.connected);
      _reconnectAttempts = 0;
      debugPrint('[WS] ✅ Connected to $url');
    } catch (e) {
      if (seq != _connectSeq) return; // superseded by a newer connect().
      debugPrint('[WS] ❌ Connection failed: $e');
      _messageController.add(WsMessage('error', 'Connection failed: $e'));
      _handleDisconnect();
    } finally {
      _connectTimer?.cancel();
      _connectTimer = null;
    }
  }

  void _handleDisconnect() {
    if (_isDisposed) return;

    _setStatus(WsStatus.error);

    // If the connection survived long enough to be considered stable
    // (e.g. a genuine server restart after being up a while), restart the
    // backoff from its base value so we recover quickly. A crash-looping
    // server keeps the delay growing instead of being hammered.
    if (_connectedAt != null) {
      final uptime = DateTime.now().difference(_connectedAt!);
      _connectedAt = null;
      if (uptime >= _stableThreshold) {
        _currentDelay = _baseDelay;
        _reconnectAttempts = 0;
      }
    }

    if (!_intentionalDisconnect && !_isDisposed) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_isDisposed || _intentionalDisconnect) return;
    if (_reconnectTimer?.isActive ?? false) return;

    _reconnectAttempts++;

    // Jitter avoids a thundering herd of clients reconnecting in sync.
    final factor  = 1.0 + (_random.nextDouble() * 2 - 1) * _jitterFactor;
    final delayMs = (_currentDelay.inMilliseconds * factor).round();
    debugPrint('[WS] 🔄 Reconnect attempt $_reconnectAttempts in '
        '${(delayMs / 1000).toStringAsFixed(2)}s (backoff: '
        '${_currentDelay.inMilliseconds}ms)');

    _reconnectTimer = Timer(Duration(milliseconds: delayMs), () {
      if (!_isDisposed && !_intentionalDisconnect) {
        connect();
      }
    });

    // Exponential growth for the next attempt, capped at _maxDelay.
    final next = _currentDelay * 2;
    _currentDelay = next > _maxDelay ? _maxDelay : next;
  }

  Future<void> disconnect() async {
    if (_isDisposed) return;
    _intentionalDisconnect = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _connectTimer?.cancel();
    _connectTimer = null;

    await _sub?.cancel();
    _sub = null;

    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;

    _connectedAt = null;
    _currentDelay = _baseDelay;
    _reconnectAttempts = 0;

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
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _connectTimer?.cancel();
    _connectTimer = null;
    _sub?.cancel();
    _sub = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _connectedAt = null;
    _statusController.close();
    _messageController.close();
  }
}