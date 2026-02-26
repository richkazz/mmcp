/// Tool registration and JSON-RPC request routing.
///
/// [McpToolRegistry] maps tool names to their definitions and handlers,
/// validates incoming arguments against schemas, and dispatches
/// JSON-RPC requests to the correct handler.
library;

import 'dart:async';

import '../shared/models.dart';
import '../logger.dart';
import '../schema_validator.dart';

/// Typedef for tool handler functions.
///
/// Receives the validated arguments map and returns the result
/// (any JSON-serializable value).
typedef McpToolHandler =
    Future<dynamic> Function(Map<String, dynamic> arguments);

/// Internal registry managing tool definitions and their handlers.
///
/// Provides schema validation before invoking handlers and
/// generates standard JSON-RPC errors for unknown tools or
/// invalid parameters.
class McpToolRegistry {
  final McpLogger _logger;
  final McpSchemaValidator _validator;

  final Map<String, McpToolDefinition> _definitions = {};
  final Map<String, McpToolHandler> _handlers = {};

  McpToolRegistry({McpLogger? logger})
    : _logger = logger ?? McpLogger(tag: 'McpToolRegistry'),
      _validator = const McpSchemaValidator();

  /// All registered tool definitions.
  List<McpToolDefinition> get tools => List.unmodifiable(_definitions.values);

  /// Whether a tool with the given [name] is registered.
  bool hasTool(String name) => _definitions.containsKey(name);

  /// Registers a tool with its [definition] and execution [handler].
  ///
  /// Throws [ArgumentError] if a tool with the same name is already registered.
  void registerTool({
    required McpToolDefinition definition,
    required McpToolHandler handler,
  }) {
    if (_definitions.containsKey(definition.name)) {
      throw ArgumentError(
        'Tool "${definition.name}" is already registered. '
        'Unregister it first before re-registering.',
      );
    }

    _definitions[definition.name] = definition;
    _handlers[definition.name] = handler;
    _logger.info('Registered tool: ${definition.name}');
  }

  /// Unregisters a tool by [name].
  void unregisterTool(String name) {
    _definitions.remove(name);
    _handlers.remove(name);
    _logger.info('Unregistered tool: $name');
  }

  /// Dispatches a JSON-RPC [request] to the appropriate handler.
  ///
  /// Handles the `mcp/listTools` meta-method internally.
  /// Validates arguments against the tool's schema before invocation.
  /// Returns an [McpResponse] with either the result or an error.
  Future<McpResponse> dispatch(McpRequest request) async {
    _logger.debug('Dispatching request: ${request.method} (id: ${request.id})');

    // Handle built-in MCP methods
    if (request.method == 'mcp/listTools') {
      return McpResponse.success(
        id: request.id,
        result: tools.map((t) => t.toJson()).toList(),
      );
    }

    // Look up the tool
    final definition = _definitions[request.method];
    final handler = _handlers[request.method];

    if (definition == null || handler == null) {
      _logger.warning('Method not found: ${request.method}');
      return McpResponse.error(
        id: request.id,
        error: McpError.methodNotFound(
          'Tool "${request.method}" is not registered',
        ),
      );
    }

    // Validate arguments against schema
    final validationError = _validator.validate(
      request.params,
      definition.inputSchema,
    );
    if (validationError != null) {
      _logger.warning(
        'Invalid params for ${request.method}: ${validationError.message}',
      );
      return McpResponse.error(id: request.id, error: validationError);
    }

    // Execute the handler
    try {
      final result = await handler(request.params);
      _logger.debug('Tool ${request.method} executed successfully');
      return McpResponse.success(id: request.id, result: result);
    } catch (e, stack) {
      _logger.error('Tool ${request.method} threw an exception', e, stack);
      return McpResponse.error(
        id: request.id,
        error: McpError.internalError('Tool execution failed: ${e.toString()}'),
      );
    }
  }
}
