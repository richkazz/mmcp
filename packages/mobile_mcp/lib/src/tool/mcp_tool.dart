/// The McpTool public API for Tool/Plugin applications.
///
/// [McpTool] is the primary interface for apps that want to expose
/// capabilities to AI Host applications via the MCP protocol.
///
/// ## Usage
/// ```dart
/// final mcpTool = McpTool(appScheme: 'my-notes-app');
///
/// mcpTool.registerTool(
///   definition: McpToolDefinition(
///     name: 'fetch_notes',
///     description: 'Get latest notes',
///     inputSchema: { "type": "object", "properties": { ... } },
///   ),
///   handler: (args) async => await db.getNotes(limit: args['limit']),
/// );
///
/// mcpTool.setConsentHandler((hostInfo) async {
///   return await showConsentDialog(hostInfo.name);
/// });
///
/// await mcpTool.initialize();
/// ```
library;

import 'dart:async';

import 'package:app_links/app_links.dart';

import '../shared/errors.dart';
import '../logger.dart';
import '../lifecycle.dart';
import '../security.dart';
import '../storage.dart';
import '../transport.dart';
import '../shared/models.dart';
import 'tool_registry.dart';
import 'tool_server.dart';

/// Callback type for connection consent.
///
/// Receives information about the Host requesting connection and
/// returns `true` to allow or `false` to deny.
typedef McpConsentHandler = Future<bool> Function(McpHostInfo hostInfo);

/// Callback type for per-tool execution consent.
///
/// Receives the tool name and host info, returns `true` to allow.
typedef McpToolExecutionConsentHandler =
    Future<bool> Function(String toolName, McpHostInfo hostInfo);

/// The main interface for Tool (plugin) applications.
///
/// Provides methods to:
/// - Register tool capabilities with schemas and handlers
/// - Set consent callbacks for connection approval
/// - Listen for deep links from Host applications
/// - Run a local WebSocket server for JSON-RPC communication
class McpTool {
  /// The custom URL scheme for this Tool app (e.g., `'my-notes-app'`).
  final String appScheme;

  /// Whether to only allow secure transport (App/Universal Links) for handshakes.
  final bool strictTransport;

  /// Optional list of trusted Host package names or bundle IDs.
  final List<String>? trustedHostPackages;

  /// Optional custom storage provider. Uses [SecureMcpStorage] if not provided.
  final McpStorageProvider storage;

  final McpLogger _logger;
  final McpToolRegistry _registry;
  late final McpToolServer _server;
  final McpTransport _transport;

  McpConsentHandler? _consentHandler;
  // ignore: unused_field
  McpToolExecutionConsentHandler? _executionConsentHandler;

  StreamSubscription<Uri>? _linkSubscription;
  bool _initialized = false;

  /// Creates an [McpTool] instance.
  ///
  /// - [appScheme]: The custom URL scheme registered for this app.
  /// - [storage]: Optional custom storage provider.
  /// - [strictTransport]: If true, only allow HTTPS (App/Universal Links)
  ///   for handshake deep links.
  /// - [trustedHostPackages]: Whitelist of Host package names to allow.
  /// - [logLevel]: Logging verbosity (defaults to [McpLogLevel.info]).
  ///
  /// **SECURITY WARNING:** Using custom URL schemes (e.g., `'my-tool-app'`) is
  /// susceptible to hijacking by other apps. For production applications,
  /// it is **highly recommended** to set [strictTransport] to `true`,
  /// use App Links (Android) or Universal Links (iOS), and ensure [storage]
  /// is an instance of `SecureMcpStorage`.
  McpTool({
    required this.appScheme,
    this.strictTransport = false,
    this.trustedHostPackages,
    McpStorageProvider? storage,
    McpLogLevel logLevel = McpLogLevel.info,
  }) : storage = storage ?? SecureMcpStorage(),
       _logger = McpLogger(level: logLevel, tag: 'McpTool'),
       _registry = McpToolRegistry(
         logger: McpLogger(level: logLevel, tag: 'McpToolRegistry'),
       ),
       _transport = McpTransport(
         logger: McpLogger(level: logLevel, tag: 'McpTransport'),
       ) {
    // Create server with the same registry instance
    _server = McpToolServer(
      registry: _registry,
      lifecycle: McpLifecycle(
        logger: McpLogger(level: logLevel, tag: 'McpLifecycle'),
      ),
      logger: McpLogger(level: logLevel, tag: 'McpToolServer'),
    );
  }

  /// Whether this tool has been initialized.
  bool get isInitialized => _initialized;

  /// Whether a Host is currently connected.
  bool get isConnected => _server.hasActiveConnection;

  /// Stream of server state changes.
  Stream<McpToolServerState> get stateChanges => _server.stateChanges;

  /// All registered tool definitions.
  List<McpToolDefinition> get registeredTools => _registry.tools;

  // ---------------------------------------------------------------------------
  // Tool Registration
  // ---------------------------------------------------------------------------

  /// Registers a tool capability with its definition and handler.
  ///
  /// The [definition] describes the tool's name, description, and input schema.
  /// The [handler] is called when a Host executes this tool via JSON-RPC.
  ///
  /// Arguments are automatically validated against the [definition.inputSchema]
  /// before the handler is invoked. Invalid arguments produce an automatic
  /// `InvalidParams` error response.
  ///
  /// Example:
  /// ```dart
  /// mcpTool.registerTool(
  ///   definition: McpToolDefinition(
  ///     name: 'get_battery',
  ///     description: 'Returns current battery level',
  ///     inputSchema: { "type": "object", "properties": {} },
  ///   ),
  ///   handler: (args) async => {'level': 85, 'charging': true},
  /// );
  /// ```
  void registerTool({
    required McpToolDefinition definition,
    required McpToolHandler handler,
  }) {
    _registry.registerTool(definition: definition, handler: handler);
  }

  // ---------------------------------------------------------------------------
  // Consent Handlers
  // ---------------------------------------------------------------------------

  /// Sets the connection consent handler.
  ///
  /// This callback is triggered when a Host app attempts to connect.
  /// The developer should show a UI dialog and return `true` to allow
  /// or `false` to deny the connection.
  ///
  /// **Security Note:** It is highly recommended to display a clear warning
  /// to the user about the risks of sharing sensitive data with AI applications,
  /// and to verify the identity of the requesting app (see documentation).
  ///
  /// If no handler is set, all connections are automatically accepted.
  void setConsentHandler(McpConsentHandler handler) {
    _consentHandler = handler;
  }

  /// Sets the per-tool execution consent handler.
  ///
  /// This optional callback is triggered before executing each tool.
  /// Useful for sensitive operations that require explicit user approval.
  void setExecutionConsentHandler(McpToolExecutionConsentHandler handler) {
    _executionConsentHandler = handler;
  }

  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------

  /// Initializes the Tool, starting to listen for incoming deep links.
  ///
  /// Must be called after registering tools and setting consent handlers.
  /// Listens for wakeup deep links from Host applications and manages
  /// the WebSocket server lifecycle.
  Future<void> initialize() async {
    if (_initialized) {
      _logger.warning('McpTool already initialized');
      return;
    }

    _logger.info('Initializing McpTool with scheme: $appScheme');

    // Listen for incoming deep links
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

    // Handle subsequent links (warm start)
    _linkSubscription = appLinks.uriLinkStream.listen(
      _handleIncomingLink,
      onError: (error) {
        _logger.error('Deep link stream error: $error');
      },
    );

    _initialized = true;
    _logger.info('McpTool initialized successfully');
  }

  /// Handles an incoming deep link from a Host app.
  Future<void> _handleIncomingLink(Uri uri) async {
    _logger.debug('Received deep link: $uri');

    // Support both custom schemes (tool-scheme://mcp/...)
    // and Universal/App Links (https://domain.com/mcp/...)
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

    // For App Links, we expect /mcp/... path
    if (isHttp && !uri.path.startsWith('/mcp/')) {
      _logger.debug('Ignoring non-MCP App Link: $uri');
      return;
    }

    final path = isHttp
        ? uri.path.replaceFirst('/mcp/', '')
        : uri.path.replaceFirst('/', '');

    switch (path) {
      case 'wakeup':
        await _handleWakeup(uri);
      case 'register':
        await _handleRegistration(uri);
      default:
        _logger.warning('Unknown MCP path: $path');
    }
  }

  /// Handles a "wakeup" deep link from a Host.
  Future<void> _handleWakeup(Uri uri) async {
    // Platform identity verification
    final callingPackage = await _server.lifecycle.getCallingPackage();
    final isObscured = await _server.lifecycle.isWindowObscured();

    if (isObscured) {
      _logger.warning('Blocking wakeup: window is obscured (potential clickjacking)');
      return;
    }

    final sessionToken = uri.queryParameters['session_token'];
    final replyTo = uri.queryParameters['reply_to'];
    final hostName =
        uri.queryParameters['host_name'] ?? replyTo ?? 'Unknown Host';

    if (sessionToken == null || replyTo == null) {
      _logger.error('Wakeup link missing required params: $uri');
      return;
    }

    _logger.info('Wakeup from Host: $hostName (reply_to: $replyTo)');

    // Check if Host is already registered and approved
    final existingEntry = await storage.getEntry(replyTo);
    final isAlreadyApproved =
        existingEntry != null && existingEntry.token == sessionToken;

    if (!isAlreadyApproved) {
      _logger.debug(
        'New or re-pairing request from $replyTo, requesting consent',
      );

      // SECURITY: If we already have an entry for this scheme but a different name,
      // it might be an impersonation attempt.
      bool isNameMismatch =
          existingEntry != null && existingEntry.displayName != hostName;
      if (isNameMismatch) {
        _logger.warning(
          'Host name mismatch for existing scheme $replyTo: '
          'Expected "${existingEntry.displayName}", got "$hostName". '
          'Potential impersonation attempt.',
        );
      }

      // Check consent
      final isUniversalLink = callingPackage == 'Verified (Universal Link)';
      final isPackageTrusted = trustedHostPackages != null &&
          callingPackage != null &&
          trustedHostPackages!.contains(callingPackage);

      final hostInfo = McpHostInfo(
        hostScheme: replyTo,
        name: hostName,
        sessionToken: sessionToken,
        callingPackage: callingPackage,
        isUniversalLink: isUniversalLink,
        isVerified: (callingPackage != null && !isNameMismatch) ||
            isUniversalLink ||
            isPackageTrusted,
      );

      if (_consentHandler != null) {
        final allowed = await _consentHandler!(hostInfo);
        if (!allowed) {
          _logger.info('Connection denied by consent handler');
          return;
        }
      }
    } else {
      _logger.info('Auto-approving wakeup for already paired Host: $replyTo');
    }

    // Start the WebSocket server
    final port = await _server.start(sessionToken: sessionToken);

    // Save the host entry
    await storage.saveEntry(
      McpRegistryEntry(
        id: replyTo,
        appScheme: replyTo,
        displayName: hostName,
        token: sessionToken,
        capabilities: [],
        createdAt: DateTime.now(),
      ),
    );

    // Reply to the Host with the port
    await _transport.sendDeepLink(
      scheme: replyTo,
      path: '/ready',
      strictTransport: strictTransport,
      queryParams: {'port': port.toString(), 'tool_scheme': appScheme},
    );

    _logger.info('Replied to Host with port: $port');
  }

  /// Handles a registration request from a Host.
  Future<void> _handleRegistration(Uri uri) async {
    final replyTo = uri.queryParameters['reply_to'];
    final hostName = uri.queryParameters['host_name'] ?? 'Unknown Host';

    if (replyTo == null) {
      _logger.error('Registration link missing reply_to: $uri');
      return;
    }

    // Generate a pairing token
    final pairingToken = McpSecurity.generateSessionToken();

    // Save Host entry
    await storage.saveEntry(
      McpRegistryEntry(
        id: replyTo,
        appScheme: replyTo,
        displayName: hostName,
        token: pairingToken,
        capabilities: [],
        createdAt: DateTime.now(),
      ),
    );

    // Reply with tool capabilities
    await _transport.sendDeepLink(
      scheme: replyTo,
      path: '/registered',
      strictTransport: strictTransport,
      queryParams: {
        'tool_scheme': appScheme,
        'tool_name': appScheme,
        'token': pairingToken,
        'tools': _registry.tools.map((t) => t.name).join(','),
      },
    );

    _logger.info('Registered with Host: $hostName');
  }

  /// Initiates registration with a Host app.
  ///
  /// Sends a deep link to the Host's scheme to begin the pairing process.
  Future<void> registerWithHost(String hostScheme) async {
    _logger.info('Initiating registration with Host: $hostScheme');

    await _transport.sendDeepLink(
      scheme: hostScheme,
      path: '/tool-register',
      strictTransport: strictTransport,
      queryParams: {
        'tool_scheme': appScheme,
        'tool_name': appScheme,
        'tools': _registry.tools.map((t) => t.name).join(','),
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Cleanup
  // ---------------------------------------------------------------------------

  /// Disposes of all resources.
  ///
  /// Stops the WebSocket server, cancels deep link subscriptions,
  /// and releases background task locks.
  Future<void> dispose() async {
    _linkSubscription?.cancel();
    _linkSubscription = null;
    await _server.dispose();
    _initialized = false;
    _logger.info('McpTool disposed');
  }
}
