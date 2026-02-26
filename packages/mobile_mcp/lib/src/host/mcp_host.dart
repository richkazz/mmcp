/// The McpHost public API for AI/Controller applications.
///
/// [McpHost] is the primary interface for apps that want to discover
/// and execute tools provided by other apps via the MCP protocol.
///
/// ## Usage
/// ```dart
/// final mcpHost = McpHost(hostScheme: 'my-ai-app');
/// await mcpHost.initialize();
///
/// final session = await mcpHost.connectToTool('my-notes-app');
/// final tools = await session.listTools();
/// final result = await session.callTool('fetch_notes', {'limit': 5});
/// ```
library;

import 'dart:async';

import 'package:app_links/app_links.dart';

import '../shared/errors.dart';
import '../logger.dart';
import '../retry.dart';
import '../security.dart';
import '../storage.dart';
import '../transport.dart';
import '../shared/models.dart';
import 'mcp_session.dart';

/// The main interface for Host (AI/controller) applications.
///
/// Provides methods to:
/// - Accept Tool registrations
/// - Connect to Tool apps via the wakeup handshake
/// - Execute tools through [McpSession]
/// - Manage active sessions and registry entries
class McpHost {
  /// The custom URL scheme for this Host app (e.g., `'my-ai-app'`).
  final String hostScheme;

  /// A human-readable name for this Host app.
  final String hostName;

  /// Whether to only allow secure transport (App/Universal Links) for handshakes.
  final bool strictTransport;

  /// Optional custom storage provider.
  final McpStorageProvider storage;

  final McpLogger _logger;
  final McpTransport _transport;
  final McpRetryPolicy _retryPolicy;

  /// Active sessions keyed by tool scheme.
  final Map<String, McpSession> _sessions = {};

  /// Pending wakeup handshakes: tool scheme → Completer<port>.
  final Map<String, Completer<int>> _pendingWakeups = {};

  StreamSubscription<Uri>? _linkSubscription;
  bool _initialized = false;

  /// Stream controller for registry change notifications.
  final _registryController = StreamController<McpRegistryEntry>.broadcast();

  /// Creates an [McpHost] instance.
  ///
  /// - [hostScheme]: The custom URL scheme registered for this app.
  /// - [hostName]: Human-readable name shown to Tools during consent.
  /// - [storage]: Optional custom storage provider.
  /// - [strictTransport]: If true, only allow HTTPS (App/Universal Links)
  ///   for handshake deep links.
  /// - [logLevel]: Logging verbosity.
  ///
  /// **SECURITY WARNING:** Using custom URL schemes (e.g., `'my-ai-app'`) is
  /// susceptible to hijacking by other apps. For production applications,
  /// it is **highly recommended** to set [strictTransport] to `true`,
  /// use App Links (Android) or Universal Links (iOS), and ensure [storage]
  /// is an instance of `SecureMcpStorage`.
  McpHost({
    required this.hostScheme,
    this.hostName = 'AI Host',
    this.strictTransport = false,
    McpStorageProvider? storage,
    McpLogLevel logLevel = McpLogLevel.info,
  }) : storage = storage ?? SecureMcpStorage(),
       _logger = McpLogger(level: logLevel, tag: 'McpHost'),
       _transport = McpTransport(
         logger: McpLogger(level: logLevel, tag: 'McpTransport'),
       ),
       _retryPolicy = McpRetryPolicy(
         logger: McpLogger(level: logLevel, tag: 'McpRetry'),
       );

  /// Whether this host has been initialized.
  bool get isInitialized => _initialized;

  /// All active sessions.
  Map<String, McpSession> get sessions => Map.unmodifiable(_sessions);

  /// Stream of newly registered tools.
  Stream<McpRegistryEntry> get onToolRegistered => _registryController.stream;

  /// Returns all registered tool entries from storage.
  Future<List<McpRegistryEntry>> getRegisteredTools() async {
    return storage.getAllEntries();
  }

  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------

  /// Initializes the Host, listening for Tool registrations and
  /// wakeup handshake replies via deep links.
  ///
  /// Must be called before [connectToTool] or [executeTool].
  Future<void> initialize() async {
    if (_initialized) {
      _logger.warning('McpHost already initialized');
      return;
    }

    _logger.info('Initializing McpHost with scheme: $hostScheme');

    final appLinks = AppLinks();

    // Handle initial link (cold start)
    try {
      final initialUri = await appLinks.getInitialLink();
      if (initialUri != null) {
        _handleIncomingLink(initialUri);
      }
    } catch (e) {
      _logger.debug('No initial link: $e');
    }

    // Handle subsequent links
    _linkSubscription = appLinks.uriLinkStream.listen(
      _handleIncomingLink,
      onError: (error) {
        _logger.error('Deep link stream error: $error');
      },
    );

    _initialized = true;
    _logger.info('McpHost initialized successfully');
  }

  /// Handles an incoming deep link.
  Future<void> _handleIncomingLink(Uri uri) async {
    _logger.debug('Received deep link: $uri');

    final isHttp = uri.scheme == 'http' || uri.scheme == 'https';

    if (strictTransport && !isHttp) {
      throw McpSecurityException(
        'Insecure transport ${uri.scheme} blocked by strictTransport policy.',
      );
    }

    if (!isHttp && uri.host != 'mcp') {
      _logger.debug('Ignoring non-MCP deep link: $uri');
      return;
    }

    final path = uri.path.replaceFirst('/', '');

    switch (path) {
      case 'ready':
        _handleReady(uri);
      case 'registered':
        await _handleToolRegistered(uri);
      case 'tool-register':
        await _handleToolRegisterRequest(uri);
      default:
        _logger.warning('Unknown MCP path: $path');
    }
  }

  /// Handles the "ready" response from a Tool (wakeup handshake complete).
  void _handleReady(Uri uri) {
    final portStr = uri.queryParameters['port'];
    final toolScheme = uri.queryParameters['tool_scheme'];

    if (portStr == null || toolScheme == null) {
      _logger.error('Ready link missing required params: $uri');
      return;
    }

    final port = int.tryParse(portStr);
    if (port == null) {
      _logger.error('Invalid port in ready link: $portStr');
      return;
    }

    _logger.info('Tool $toolScheme ready on port $port');

    // Complete the pending wakeup
    final completer = _pendingWakeups.remove(toolScheme);
    if (completer != null && !completer.isCompleted) {
      completer.complete(port);
    } else {
      _logger.warning('No pending wakeup for $toolScheme');
    }
  }

  /// Handles a Tool's registration response.
  Future<void> _handleToolRegistered(Uri uri) async {
    final toolScheme = uri.queryParameters['tool_scheme'];
    final toolName = uri.queryParameters['tool_name'] ?? toolScheme;
    final token = uri.queryParameters['token'];
    final toolsStr = uri.queryParameters['tools'] ?? '';

    if (toolScheme == null || token == null) {
      _logger.error('Registration response missing required params: $uri');
      return;
    }

    final capabilities = toolsStr.isNotEmpty ? toolsStr.split(',') : <String>[];

    final entry = McpRegistryEntry(
      id: toolScheme,
      appScheme: toolScheme,
      displayName: toolName ?? toolScheme,
      token: token,
      capabilities: capabilities,
      createdAt: DateTime.now(),
    );

    await storage.saveEntry(entry);
    _registryController.add(entry);

    _logger.info(
      'Tool registered: $toolName ($toolScheme) with ${capabilities.length} tools',
    );
  }

  /// Handles a direct registration request from a Tool via deep link.
  Future<void> _handleToolRegisterRequest(Uri uri) async {
    final toolScheme = uri.queryParameters['tool_scheme'];
    final toolName = uri.queryParameters['tool_name'] ?? toolScheme;
    final toolsStr = uri.queryParameters['tools'] ?? '';

    if (toolScheme == null) {
      _logger.error('Tool register request missing tool_scheme: $uri');
      return;
    }

    // Generate a pairing token
    final pairingToken = McpSecurity.generateSessionToken();
    final capabilities = toolsStr.isNotEmpty ? toolsStr.split(',') : <String>[];

    final entry = McpRegistryEntry(
      id: toolScheme,
      appScheme: toolScheme,
      displayName: toolName ?? toolScheme,
      token: pairingToken,
      capabilities: capabilities,
      createdAt: DateTime.now(),
    );

    await storage.saveEntry(entry);
    _registryController.add(entry);

    // Acknowledge registration to the Tool
    await _transport.sendDeepLink(
      scheme: toolScheme,
      path: '/register',
      strictTransport: strictTransport,
      queryParams: {
        'reply_to': hostScheme,
        'host_name': hostName,
        'token': pairingToken,
      },
    );

    _logger.info('Accepted registration from $toolName');
  }

  // ---------------------------------------------------------------------------
  // Connection Management
  // ---------------------------------------------------------------------------

  /// Connects to a Tool app, establishing a WebSocket session.
  ///
  /// This triggers the "wakeup" deep link, waits for the Tool
  /// to start its WebSocket server, and establishes the connection.
  ///
  /// Returns an [McpSession] for interacting with the Tool.
  ///
  /// If a session already exists for this tool, it is returned.
  ///
  /// Example:
  /// ```dart
  /// final session = await mcpHost.connectToTool('my-notes-app');
  /// ```
  Future<McpSession> connectToTool(String toolScheme) async {
    // Return existing session if connected
    if (_sessions.containsKey(toolScheme) &&
        _sessions[toolScheme]!.isConnected) {
      _logger.debug('Reusing existing session for $toolScheme');
      return _sessions[toolScheme]!;
    }

    _logger.info('Connecting to tool: $toolScheme');

    // Generate a session token
    final sessionToken = McpSecurity.generateSessionToken();

    // Trigger wakeup deep link
    final port = await _triggerWakeup(toolScheme, sessionToken);

    // Create and connect session
    final session = McpSession(
      toolScheme: toolScheme,
      toolName: toolScheme,
      port: port,
      sessionToken: sessionToken,
      reconnectCallback: (scheme) => _triggerWakeup(scheme, sessionToken),
      logger: McpLogger(level: _logger.level, tag: 'McpSession:$toolScheme'),
      retryPolicy: _retryPolicy,
    );

    await session.connect();
    _sessions[toolScheme] = session;

    // Update registry entry with session info
    final existingEntry = await storage.getEntry(toolScheme);
    if (existingEntry != null) {
      await storage.saveEntry(existingEntry.copyWith(token: sessionToken));
    }

    return session;
  }

  /// Triggers a wakeup deep link and waits for the Tool to respond.
  Future<int> _triggerWakeup(String toolScheme, String sessionToken) async {
    final completer = Completer<int>();
    _pendingWakeups[toolScheme] = completer;

    await _transport.sendDeepLink(
      scheme: toolScheme,
      path: '/wakeup',
      strictTransport: strictTransport,
      queryParams: {
        'session_token': sessionToken,
        'reply_to': hostScheme,
        'host_name': hostName,
      },
    );

    // Wait for the Tool to respond with its port
    return completer.future.timeout(
      _retryPolicy.wakeupTimeout,
      onTimeout: () {
        _pendingWakeups.remove(toolScheme);
        throw McpException.internalError(
          'Tool $toolScheme did not respond to wakeup within '
          '${_retryPolicy.wakeupTimeout.inSeconds}s',
        );
      },
    );
  }

  /// Executes a tool directly by scheme and name.
  ///
  /// Convenience method that connects (if needed) and calls the tool.
  /// Wraps [McpSession.callTool] with automatic connection management.
  ///
  /// Example:
  /// ```dart
  /// final result = await mcpHost.executeTool(
  ///   'my-notes-app',
  ///   'fetch_notes',
  ///   {'limit': 5},
  /// );
  /// ```
  Future<dynamic> executeTool(
    String toolScheme,
    String toolName, [
    Map<String, dynamic> arguments = const {},
  ]) async {
    final session = await connectToTool(toolScheme);
    return session.callTool(toolName, arguments);
  }

  /// Disconnects from a specific Tool.
  Future<void> disconnectSession(String toolScheme) async {
    final session = _sessions.remove(toolScheme);
    if (session != null) {
      await session.disconnect();
      _logger.info('Disconnected from $toolScheme');
    }
  }

  /// Disconnects all active sessions.
  Future<void> disconnectAll() async {
    for (final session in _sessions.values) {
      await session.disconnect();
    }
    _sessions.clear();
    _logger.info('Disconnected all sessions');
  }

  // ---------------------------------------------------------------------------
  // Cleanup
  // ---------------------------------------------------------------------------

  /// Disposes of all resources.
  ///
  /// Disconnects all sessions and cancels deep link subscriptions.
  Future<void> dispose() async {
    await disconnectAll();
    _linkSubscription?.cancel();
    _linkSubscription = null;
    await _registryController.close();
    _initialized = false;
    _logger.info('McpHost disposed');
  }
}
