/// An active session between a Host and a connected Tool.
///
/// [McpSession] provides methods to list available tools and
/// execute tool calls over the active WebSocket connection.
/// It manages request-ID-to-Completer mapping for clean async futures.
library;

import 'dart:async';
import 'dart:convert';

import '../logger.dart';
import '../retry.dart';
import '../security.dart';
import '../shared/models.dart';
import '../shared/errors.dart';
import 'host_connection.dart';

/// An active MCP session with a connected Tool app.
///
/// Created by [McpHost.connectToTool], provides methods to
/// interact with the Tool via WebSocket JSON-RPC.
///
/// Example:
/// ```dart
/// final session = await mcpHost.connectToTool('my-notes-app');
/// final tools = await session.listTools();
/// final result = await session.callTool('fetch_notes', {'limit': 5});
/// ```
class McpSession {
  /// The tool's custom URL scheme.
  final String toolScheme;

  /// The display name of the connected tool.
  final String toolName;

  /// The WebSocket port on the tool's local server.
  final int port;

  final String _sessionToken;
  final McpLogger _logger;
  final McpRetryPolicy _retryPolicy;

  McpHostConnection? _connection;
  StreamSubscription<String>? _subscription;

  /// Maps JSON-RPC request IDs to their pending Completers.
  final Map<String, Completer<McpResponse>> _pendingRequests = {};

  /// Cached tool definitions from the last `listTools` call.
  List<McpToolDefinition>? _cachedTools;

  /// Callback to reconnect when the WebSocket drops.
  final Future<int> Function(String toolScheme)? _reconnectCallback;

  McpSession({
    required this.toolScheme,
    required this.toolName,
    required this.port,
    required String sessionToken,
    Future<int> Function(String toolScheme)? reconnectCallback,
    McpLogger? logger,
    McpRetryPolicy? retryPolicy,
  }) : _sessionToken = sessionToken,
       _reconnectCallback = reconnectCallback,
       _logger = logger ?? McpLogger(tag: 'McpSession'),
       _retryPolicy = retryPolicy ?? McpRetryPolicy();

  /// Whether this session has an active WebSocket connection.
  bool get isConnected => _connection?.isConnected ?? false;

  /// Cached tool definitions, available after calling [listTools].
  List<McpToolDefinition>? get cachedTools => _cachedTools;

  /// Establishes the WebSocket connection to the Tool.
  Future<void> connect() async {
    if (_connection != null && _connection!.isConnected) {
      _logger.debug('Already connected to $toolScheme');
      return;
    }

    _logger.info('Connecting to $toolScheme on port $port');

    _connection = McpHostConnection(
      url: 'ws://localhost:$port',
      sessionToken: _sessionToken,
      logger: _logger,
    );

    await _connection!.connect();

    // Listen for responses
    _subscription = _connection!.messages.listen(
      _handleMessage,
      onError: (error) {
        _logger.error('WebSocket error: $error');
        _failAllPending('WebSocket error: $error');
      },
      onDone: () {
        _logger.info('WebSocket closed for $toolScheme');
        _connection = null;
        _subscription = null;
      },
    );

    _logger.info('Connected to $toolScheme');
  }

  /// Handles an incoming WebSocket message.
  void _handleMessage(String data) {
    _logger.debug('Received: $data');

    try {
      final json = jsonDecode(data) as Map<String, dynamic>;
      final response = McpResponse.fromJson(json);

      final completer = _pendingRequests.remove(response.id);
      if (completer != null) {
        completer.complete(response);
      } else {
        _logger.warning(
          'Received response for unknown request ID: ${response.id}',
        );
      }
    } catch (e, stack) {
      _logger.error('Failed to parse response', e, stack);
    }
  }

  /// Fails all pending requests with the given error message.
  void _failAllPending(String reason) {
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.complete(
          McpResponse.error(
            id: 'unknown',
            error: McpError.internalError(reason),
          ),
        );
      }
    }
    _pendingRequests.clear();
  }

  /// Lists all tools available on the connected Tool app.
  ///
  /// Sends the standard MCP `mcp/listTools` request and returns
  /// the list of [McpToolDefinition]s.
  Future<List<McpToolDefinition>> listTools() async {
    final response = await _sendRequest('mcp/listTools', {});

    if (response.isError) {
      throw McpException(response.error!);
    }

    final toolsList = (response.result as List<dynamic>)
        .map(
          (t) =>
              McpToolDefinition.fromJson(Map<String, dynamic>.from(t as Map)),
        )
        .toList();

    _cachedTools = toolsList;
    return toolsList;
  }

  /// Executes a tool by [name] with the given [arguments].
  ///
  /// Sends a JSON-RPC request over the WebSocket and returns the result.
  /// If the WebSocket connection has dropped, automatically retries by
  /// re-triggering the wakeup handshake.
  ///
  /// Throws [McpException] if the Tool returns an error response.
  ///
  /// Example:
  /// ```dart
  /// final result = await session.callTool('fetch_notes', {'limit': 5});
  /// print('Notes: $result');
  /// ```
  Future<dynamic> callTool(
    String name, [
    Map<String, dynamic> arguments = const {},
  ]) async {
    final response = await _retryPolicy.execute<McpResponse>(
      action: () => _sendRequest(name, arguments),
      onRetry: (attempt) async {
        _logger.info('Attempting reconnect for retry $attempt');
        await _reconnect();
      },
      shouldRetry: (error) {
        // Retry on connection-related errors
        return error is McpException &&
            error.code == McpError.internalErrorCode;
      },
    );

    if (response.isError) {
      throw McpException(response.error!);
    }

    return response.result;
  }

  /// Sends a JSON-RPC request and waits for the response.
  Future<McpResponse> _sendRequest(
    String method,
    Map<String, dynamic> params,
  ) async {
    if (_connection == null || !_connection!.isConnected) {
      throw McpException.internalError('WebSocket not connected');
    }

    final requestId = McpSecurity.generateRequestId();
    final request = McpRequest(id: requestId, method: method, params: params);

    final completer = Completer<McpResponse>();
    _pendingRequests[requestId] = completer;

    final payload = jsonEncode(request.toJson());
    _logger.debug('Sending: $payload');
    _connection!.send(payload);

    // Timeout after 30 seconds
    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _pendingRequests.remove(requestId);
        return McpResponse.error(
          id: requestId,
          error: McpError.internalError('Request timed out after 30 seconds'),
        );
      },
    );
  }

  /// Attempts to reconnect to the Tool via deep link wakeup.
  Future<void> _reconnect() async {
    await disconnect();

    if (_reconnectCallback != null) {
      final newPort = await _reconnectCallback!(toolScheme);
      _logger.info('Reconnected on port $newPort');
      // Re-establish WebSocket
      _connection = McpHostConnection(
        url: 'ws://localhost:$newPort',
        sessionToken: _sessionToken,
        logger: _logger,
      );

      await _connection!.connect();

      _subscription = _connection!.messages.listen(
        _handleMessage,
        onError: (error) {
          _logger.error('WebSocket error after reconnect: $error');
          _failAllPending('WebSocket reconnect error: $error');
        },
        onDone: () {
          _connection = null;
          _subscription = null;
        },
      );
    }
  }

  /// Closes the WebSocket connection.
  Future<void> disconnect() async {
    _failAllPending('Session disconnected');
    await _subscription?.cancel();
    _subscription = null;
    await _connection?.close();
    _connection = null;
    _logger.info('Disconnected from $toolScheme');
  }
}
