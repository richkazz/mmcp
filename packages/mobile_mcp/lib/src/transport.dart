/// Hybrid transport layer for the MCP protocol.
///
/// Abstracts the two-phase communication:
/// 1. **Deep Link phase**: Wakeup handshakes via custom URL schemes.
/// 2. **WebSocket phase**: Real-time bidirectional JSON-RPC once connected.
library;

import 'dart:async';
import 'dart:convert';

import 'package:url_launcher/url_launcher.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'logger.dart';
import 'shared/errors.dart';
import 'shared/models.dart';

/// Encapsulates the deep link + WebSocket transport switching.
///
/// Used internally by [McpHost] and [McpTool] to manage the handshake
/// and communication lifecycle.
class McpTransport {
  final McpLogger _logger;

  McpTransport({McpLogger? logger})
    : _logger = logger ?? McpLogger(tag: 'McpTransport');

  // ---------------------------------------------------------------------------
  // Deep Link Operations
  // ---------------------------------------------------------------------------

  /// Sends a deep link to the given [scheme] with [path] and [queryParams].
  ///
  /// Used by the Host to trigger a "wakeup" and by the Tool to return
  /// the "ready" handshake.
  Future<bool> sendDeepLink({
    required String scheme,
    required String path,
    Map<String, String> queryParams = const {},
    String? host,
    bool strictTransport = false,
  }) async {
    final isHttp = scheme == 'http' || scheme == 'https';

    if (strictTransport && !isHttp) {
      throw McpSecurityException(
        'Insecure transport $scheme blocked by strictTransport policy.',
      );
    }

    // For App Links (HTTP/S), the path should be prefixed with /mcp
    final normalizedPath = isHttp && !path.startsWith('/mcp')
        ? '/mcp${path.startsWith('/') ? '' : '/'}$path'
        : path;

    final uri = Uri(
      scheme: scheme,
      host: host ?? (isHttp ? null : 'mcp'),
      path: normalizedPath,
      queryParameters: queryParams.isNotEmpty ? queryParams : null,
    );

    _logger.debug('Sending deep link: $uri');

    try {
      final canSend = await canLaunchUrl(uri);
      if (!canSend) {
        _logger.error('Cannot launch URL: $uri');
        return false;
      }
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e, stack) {
      _logger.error('Failed to send deep link', e, stack);
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // WebSocket Client (used by McpHost)
  // ---------------------------------------------------------------------------

  /// Connects to a Tool's WebSocket server at the given [port].
  ///
  /// The [sessionToken] is sent as an `Authorization: Bearer` header
  /// for authentication.
  WebSocketChannel connectToWebSocket({
    required int port,
    required String sessionToken,
    String host = 'localhost',
  }) {
    final uri = Uri.parse('ws://$host:$port');
    _logger.info('Connecting to WebSocket at $uri');

    return WebSocketChannel.connect(uri, protocols: ['mcp']);
  }

  /// Sends the session token as the first message for authentication
  /// (fallback for platforms that don't support custom headers on WS connect).
  void authenticateWebSocket(WebSocketChannel channel, String sessionToken) {
    final authMessage = jsonEncode({'type': 'auth', 'token': sessionToken});
    channel.sink.add(authMessage);
    _logger.debug('Sent WebSocket authentication message');
  }

  /// Sends a JSON-RPC request over an active WebSocket.
  void sendJsonRpc(WebSocketChannel channel, McpRequest request) {
    final payload = jsonEncode(request.toJson());
    _logger.debug('Sending JSON-RPC: $payload');
    channel.sink.add(payload);
  }

  /// Sends a JSON-RPC response over an active WebSocket.
  void sendJsonRpcResponse(WebSocketChannel channel, McpResponse response) {
    final payload = jsonEncode(response.toJson());
    _logger.debug('Sending JSON-RPC response: $payload');
    channel.sink.add(payload);
  }
}
