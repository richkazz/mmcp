/// Manages an active WebSocket connection with a Host on the Tool side.
///
/// [McpToolSession] handles message framing, JSON-RPC parsing, and
/// dispatching to the [McpToolRegistry].
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../logger.dart';
import '../shared/models.dart';
import 'tool_registry.dart';

/// Represents an active connection session with a Host.
class McpToolSession {
  final WebSocket _ws;
  final McpToolRegistry _registry;
  final McpLogger _logger;
  final String _expectedToken;
  final void Function() _onDone;

  StreamSubscription<dynamic>? _subscription;
  bool _authenticated = false;
  Timer? _authTimer;

  McpToolSession({
    required WebSocket ws,
    required McpToolRegistry registry,
    required McpLogger logger,
    required String expectedToken,
    required void Function() onDone,
    bool alreadyAuthenticated = false,
  }) : _ws = ws,
       _registry = registry,
       _logger = logger,
       _expectedToken = expectedToken,
       _onDone = onDone,
       _authenticated = alreadyAuthenticated {
    _init();
    _startAuthTimer();
  }

  void _startAuthTimer() {
    if (!_authenticated) {
      _authTimer = Timer(const Duration(seconds: 5), () {
        if (!_authenticated) {
          _logger.warning('Authentication timeout');
          close();
        }
      });
    }
  }

  void _init() {
    _subscription = _ws.listen(
      (data) => _handleData(data as String),
      onError: (error, stackTrace) {
        _logger.error('WebSocket error in session', error, stackTrace);
      },
      onDone: () {
        _logger.info('Session WebSocket closed');
        _onDone();
      },
    );
  }

  /// Handles incoming raw data, checking for authentication if needed.
  Future<void> _handleData(String data) async {
    _logger.debug('Received data: $data');

    try {
      final json = jsonDecode(data) as Map<String, dynamic>;
      if (json['type'] == 'auth') {
        _handleAuthMessage(json);
        return;
      }
    } catch (_) {
      // Not a valid JSON or not an auth message, proceed to JSON-RPC if authenticated
    }

    if (!_authenticated) {
      _logger.warning('Received message before authentication');
      _ws.close(WebSocketStatus.policyViolation, 'Not authenticated');
      return;
    }

    await _handleMessage(data);
  }

  void _handleAuthMessage(Map<String, dynamic> message) {
    if (message['token'] == _expectedToken) {
      _authenticated = true;
      _authTimer?.cancel();
      _authTimer = null;
      _logger.info('Session authenticated via message');
    } else {
      _logger.warning('Session auth failed: token mismatch');
      _ws.close(WebSocketStatus.policyViolation, 'Invalid token');
    }
  }

  /// Handles an incoming JSON-RPC message.
  Future<void> _handleMessage(String rawMessage) async {
    McpRequest request;
    try {
      final json = jsonDecode(rawMessage) as Map<String, dynamic>;
      request = McpRequest.fromJson(json);
    } catch (e) {
      _logger.error('Failed to parse JSON-RPC request: $e');
      final errorResponse = McpResponse.error(
        id: '0',
        error: McpError.parseError('Failed to parse JSON-RPC request'),
      );
      _ws.add(jsonEncode(errorResponse.toJson()));
      return;
    }

    // Dispatch to registry
    final response = await _registry.dispatch(request);
    _ws.add(jsonEncode(response.toJson()));
  }

  /// Closes the session.
  Future<void> close() async {
    _authTimer?.cancel();
    _authTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    await _ws.close();
  }
}
