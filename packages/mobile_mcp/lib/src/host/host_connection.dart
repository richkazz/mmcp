/// Low-level WebSocket connection management for the Host side.
///
/// [McpHostConnection] handles establishing the connection,
/// sending the initial authentication message, and providing
/// a stream of incoming JSON-RPC responses.
library;

import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../logger.dart';

/// Represents a low-level WebSocket connection to a Tool.
class McpHostConnection {
  final String _url;
  final String _sessionToken;
  final McpLogger _logger;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;

  final _messageController = StreamController<String>.broadcast();

  McpHostConnection({
    required String url,
    required String sessionToken,
    required McpLogger logger,
  }) : _url = url,
       _sessionToken = sessionToken,
       _logger = logger;

  /// Whether the connection is active.
  bool get isConnected => _channel != null;

  /// Stream of incoming raw JSON-RPC messages.
  Stream<String> get messages => _messageController.stream;

  /// Establishes the connection and sends the auth token.
  Future<void> connect() async {
    if (_channel != null) return;

    _logger.info('Connecting to WebSocket at $_url');
    _channel = WebSocketChannel.connect(Uri.parse(_url));

    // Send auth as first message
    final authMessage = jsonEncode({'type': 'auth', 'token': _sessionToken});
    _channel!.sink.add(authMessage);

    _subscription = _channel!.stream.listen(
      (data) {
        _messageController.add(data as String);
      },
      onError: (error) {
        _logger.error('WebSocket error: $error');
        _messageController.addError(error as Object);
      },
      onDone: () {
        _logger.info('WebSocket connection closed');
        _channel = null;
        _subscription = null;
      },
    );
  }

  /// Sends a raw string message.
  void send(String message) {
    if (_channel == null) {
      throw Exception('Not connected');
    }
    _channel!.sink.add(message);
  }

  /// Closes the connection.
  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
    await _messageController.close();
  }
}
