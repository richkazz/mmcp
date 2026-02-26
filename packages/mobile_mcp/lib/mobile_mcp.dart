/// Mobile Model Context Protocol (MCP) for Flutter.
///
/// A unified package enabling cross-app tool discovery, secure registration,
/// and real-time JSON-RPC execution via a hybrid deep-link + local WebSocket
/// transport layer.
///
/// ## Core APIs
///
/// ### For Tool (Plugin) Apps — [McpTool]
/// ```dart
/// final mcpTool = McpTool(appScheme: 'my-notes-app');
/// mcpTool.registerTool(
///   definition: McpToolDefinition(name: 'fetch_notes', ...),
///   handler: (args) async => await db.getNotes(limit: args['limit']),
/// );
/// await mcpTool.initialize();
/// ```
///
/// ### For Host (AI) Apps — [McpHost]
/// ```dart
/// final mcpHost = McpHost(hostScheme: 'my-ai-app');
/// await mcpHost.initialize();
/// final session = await mcpHost.connectToTool('my-notes-app');
/// final result = await session.callTool('fetch_notes', {'limit': 5});
/// ```
library mobile_mcp;

// Shared Models
export 'src/shared/models.dart';
export 'src/shared/errors.dart';

// Infrastructure
export 'src/storage.dart';
export 'src/logger.dart';
export 'src/security.dart';
export 'src/schema_validator.dart';
export 'src/transport.dart';
export 'src/lifecycle.dart';
export 'src/retry.dart';

// Tool API
export 'src/tool/mcp_tool.dart';
export 'src/tool/tool_registry.dart';
export 'src/tool/tool_server.dart';
export 'src/tool/tool_session.dart';

// Host API
export 'src/host/mcp_host.dart';
export 'src/host/mcp_session.dart';
export 'src/host/host_connection.dart';
