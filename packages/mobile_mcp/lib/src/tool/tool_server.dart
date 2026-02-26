/// Local WebSocket server for the Tool side of the MCP protocol.
///
/// Starts a `dart:io` [HttpServer], upgrades connections to WebSockets,
/// validates session tokens, and dispatches incoming JSON-RPC requests
/// to the [McpToolRegistry].
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../logger.dart';
import '../lifecycle.dart';
import '../security.dart';
import '../shared/models.dart';
import 'tool_registry.dart';
import 'tool_session.dart';

/// Manages the local WebSocket server that Hosts connect to.
///
/// The server:
/// 1. Binds to an OS-assigned ephemeral port (port 0).
/// 2. Rejects connections without the correct session token.
/// 3. Dispatches JSON-RPC requests to the [McpToolRegistry].
/// 4. Acquires a background task lock via [McpLifecycle] to keep
///    the Dart VM alive while connections are active.
class McpToolServer {
  final McpToolRegistry _registry;
  final McpLifecycle _lifecycle;
  final McpLogger _logger;

  HttpServer? _server;
  McpToolSession? _activeConnection;
  String? _sessionToken;

  /// Stream controller for server state changes.
  final _stateController = StreamController<McpToolServerState>.broadcast();

  McpToolServer({
    required McpToolRegistry registry,
    McpLifecycle? lifecycle,
    McpLogger? logger,
  }) : _registry = registry,
       _lifecycle = lifecycle ?? McpLifecycle(),
       _logger = logger ?? McpLogger(tag: 'McpToolServer');

  /// The port the server is listening on, or `null` if not started.
  int? get port => _server?.port;

  /// Whether the server is currently running.
  bool get isRunning => _server != null;

  /// Whether a Host is currently connected.
  bool get hasActiveConnection => _activeConnection != null;

  /// The lifecycle manager for this server.
  McpLifecycle get lifecycle => _lifecycle;

  /// Stream of server state changes.
  Stream<McpToolServerState> get stateChanges => _stateController.stream;

  /// Current session token for this server instance.
  String? get sessionToken => _sessionToken;

  /// Starts the WebSocket server on a dynamic port.
  ///
  /// The [sessionToken] is required — only connections presenting
  /// this token will be accepted.
  ///
  /// Returns the assigned port number.
  Future<int> start({required String sessionToken}) async {
    _sessionToken = sessionToken;

    if (_server != null) {
      _logger.warning('Server already running on port ${_server!.port}');
      return _server!.port;
    }

    // Request port 0 — OS assigns an available ephemeral port
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final assignedPort = _server!.port;
    _logger.info('WebSocket server started on port $assignedPort');

    // Acquire background lock to keep the server alive
    await _lifecycle.acquireBackgroundLock();

    _stateController.add(McpToolServerState.listening);

    // Handle incoming HTTP requests
    _server!.listen(
      _handleRequest,
      onError: (error, stackTrace) {
        _logger.error('Server error', error, stackTrace);
      },
      onDone: () {
        _logger.info('Server closed');
        _stateController.add(McpToolServerState.stopped);
      },
    );

    return assignedPort;
  }

  /// Handles an incoming HTTP request, upgrading to WebSocket if valid.
  Future<void> _handleRequest(HttpRequest request) async {
    _logger.debug('Incoming request: ${request.method} ${request.uri}');

    // Only accept WebSocket upgrade requests
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('WebSocket upgrade required')
        ..close();
      return;
    }

    // Validate session token from Authorization header
    final authHeader = request.headers.value('authorization');
    final token = McpSecurity.extractBearerToken(authHeader);

    // We'll also accept token authentication via the first message
    // if headers aren't available (see _handleFirstMessage)
    final isHeaderAuth = token != null && token == _sessionToken;

    try {
      final ws = await WebSocketTransformer.upgrade(request);
      _acceptConnection(ws, alreadyAuthenticated: isHeaderAuth);
    } catch (e, stack) {
      _logger.error('WebSocket upgrade failed', e, stack);
    }
  }

  /// Accepts an authenticated connection and starts dispatching.
  void _acceptConnection(WebSocket ws, {bool alreadyAuthenticated = false}) {
    // Only one active connection at a time
    _activeConnection?.close();

    _logger.info('Host connected');
    _stateController.add(McpToolServerState.connected);

    _activeConnection = McpToolSession(
      ws: ws,
      registry: _registry,
      logger: _logger,
      expectedToken: _sessionToken!,
      alreadyAuthenticated: alreadyAuthenticated,
      onDone: () {
        _logger.info('Host disconnected');
        _activeConnection = null;
        _stateController.add(McpToolServerState.listening);
      },
    );
  }

  /// Stops the server and releases all resources.
  Future<void> stop() async {
    _activeConnection?.close();
    _activeConnection = null;
    await _server?.close(force: true);
    _server = null;
    _sessionToken = null;
    await _lifecycle.releaseBackgroundLock();
    _stateController.add(McpToolServerState.stopped);
    _logger.info('Server stopped');
  }

  /// Disposes of all resources including the state stream.
  Future<void> dispose() async {
    await stop();
    await _stateController.close();
  }
}

/// States of the [McpToolServer].
enum McpToolServerState {
  /// Server is not running.
  stopped,

  /// Server is listening for connections.
  listening,

  /// A Host is actively connected via WebSocket.
  connected,
}
