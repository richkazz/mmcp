/// Data models for the Mobile Model Context Protocol.
///
/// Provides strongly-typed Dart classes for tool definitions,
/// JSON-RPC 2.0 requests/responses, host info, and registry entries.
library;

import 'package:meta/meta.dart';

/// Describes a tool capability that a Tool app can expose to a Host.
///
/// Each tool has a unique [name], a human-readable [description],
/// and an [inputSchema] conforming to JSON Schema to validate arguments.
///
/// Example:
/// ```dart
/// McpToolDefinition(
///   name: 'fetch_notes',
///   description: 'Fetches the latest user notes',
///   inputSchema: {
///     "type": "object",
///     "properties": {
///       "limit": {"type": "integer", "description": "Max notes"}
///     },
///     "required": ["limit"]
///   },
/// )
/// ```
@immutable
class McpToolDefinition {
  /// Unique identifier for this tool.
  final String name;

  /// Human-readable description of what this tool does.
  final String description;

  /// JSON Schema describing the expected input arguments.
  final Map<String, dynamic> inputSchema;

  const McpToolDefinition({
    required this.name,
    required this.description,
    required this.inputSchema,
  });

  /// Creates an [McpToolDefinition] from a JSON map.
  factory McpToolDefinition.fromJson(Map<String, dynamic> json) {
    return McpToolDefinition(
      name: json['name'] as String,
      description: json['description'] as String,
      inputSchema: Map<String, dynamic>.from(json['inputSchema'] as Map),
    );
  }

  /// Serializes this definition to a JSON map.
  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'inputSchema': inputSchema,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is McpToolDefinition &&
          runtimeType == other.runtimeType &&
          name == other.name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'McpToolDefinition(name: $name)';
}

/// A JSON-RPC 2.0 request sent from Host to Tool.
///
/// The [method] field maps to a tool name (e.g., `'fetch_notes'`),
/// and [params] carries the arguments validated against the tool's schema.
@immutable
class McpRequest {
  /// Unique request identifier for correlating responses.
  final String id;

  /// The JSON-RPC method name (tool name or MCP method like `'mcp/listTools'`).
  final String method;

  /// The parameters/arguments for this request.
  final Map<String, dynamic> params;

  const McpRequest({
    required this.id,
    required this.method,
    this.params = const {},
  });

  /// Creates an [McpRequest] from a JSON-RPC payload.
  factory McpRequest.fromJson(Map<String, dynamic> json) {
    return McpRequest(
      id: json['id'].toString(),
      method: json['method'] as String,
      params: json['params'] != null
          ? Map<String, dynamic>.from(json['params'] as Map)
          : const {},
    );
  }

  /// Serializes to a JSON-RPC 2.0 request map.
  Map<String, dynamic> toJson() => {
    'jsonrpc': '2.0',
    'id': id,
    'method': method,
    'params': params,
  };

  @override
  String toString() => 'McpRequest(id: $id, method: $method)';
}

/// A JSON-RPC 2.0 response returned from Tool to Host.
///
/// Contains either a [result] on success or an [error] on failure.
@immutable
class McpResponse {
  /// The request ID this response corresponds to.
  final String id;

  /// The result data on success. `null` if an error occurred.
  final dynamic result;

  /// The error data on failure. `null` if successful.
  final McpError? error;

  const McpResponse({required this.id, this.result, this.error});

  /// Whether this response represents a successful result.
  bool get isSuccess => error == null;

  /// Whether this response represents an error.
  bool get isError => error != null;

  /// Creates a success response.
  factory McpResponse.success({required String id, required dynamic result}) {
    return McpResponse(id: id, result: result);
  }

  /// Creates an error response.
  factory McpResponse.error({required String id, required McpError error}) {
    return McpResponse(id: id, error: error);
  }

  /// Creates an [McpResponse] from a JSON-RPC payload.
  factory McpResponse.fromJson(Map<String, dynamic> json) {
    return McpResponse(
      id: json['id'].toString(),
      result: json['result'],
      error: json['error'] != null
          ? McpError.fromJson(Map<String, dynamic>.from(json['error'] as Map))
          : null,
    );
  }

  /// Serializes to a JSON-RPC 2.0 response map.
  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'jsonrpc': '2.0', 'id': id};
    if (error != null) {
      map['error'] = error!.toJson();
    } else {
      map['result'] = result;
    }
    return map;
  }

  @override
  String toString() => isSuccess
      ? 'McpResponse.success(id: $id)'
      : 'McpResponse.error(id: $id, error: $error)';
}

/// A JSON-RPC 2.0 error object.
///
/// Standard error codes from the JSON-RPC 2.0 specification are provided
/// as constants on this class.
@immutable
class McpError {
  /// Standard JSON-RPC 2.0: Parse error.
  static const int parseErrorCode = -32700;

  /// Standard JSON-RPC 2.0: Invalid request.
  static const int invalidRequestCode = -32600;

  /// Standard JSON-RPC 2.0: Method not found.
  static const int methodNotFoundCode = -32601;

  /// Standard JSON-RPC 2.0: Invalid params.
  static const int invalidParamsCode = -32602;

  /// Standard JSON-RPC 2.0: Internal error.
  static const int internalErrorCode = -32603;

  /// The error code.
  final int code;

  /// A short description of the error.
  final String message;

  /// Optional additional error data.
  final dynamic data;

  const McpError({required this.code, required this.message, this.data});

  /// Creates a Parse Error (-32700).
  factory McpError.parseError([String? message]) =>
      McpError(code: parseErrorCode, message: message ?? 'Parse error');

  /// Creates an Invalid Request error (-32600).
  factory McpError.invalidRequest([String? message]) =>
      McpError(code: invalidRequestCode, message: message ?? 'Invalid request');

  /// Creates a Method Not Found error (-32601).
  factory McpError.methodNotFound([String? message]) => McpError(
    code: methodNotFoundCode,
    message: message ?? 'Method not found',
  );

  /// Creates an Invalid Params error (-32602).
  factory McpError.invalidParams([String? message]) =>
      McpError(code: invalidParamsCode, message: message ?? 'Invalid params');

  /// Creates an Internal Error (-32603).
  factory McpError.internalError([String? message]) =>
      McpError(code: internalErrorCode, message: message ?? 'Internal error');

  /// Creates an [McpError] from a JSON map.
  factory McpError.fromJson(Map<String, dynamic> json) {
    return McpError(
      code: json['code'] as int,
      message: json['message'] as String,
      data: json['data'],
    );
  }

  /// Serializes to JSON.
  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'code': code, 'message': message};
    if (data != null) {
      map['data'] = data;
    }
    return map;
  }

  @override
  String toString() => 'McpError(code: $code, message: $message)';
}

/// Information about a Host application requesting a connection.
///
/// Passed to consent handlers so the Tool app can display
/// meaningful information to the user.
@immutable
class McpHostInfo {
  /// The custom URL scheme of the Host app (e.g., `'my-ai-app'`).
  final String hostScheme;

  /// A human-readable name for the Host application.
  final String name;

  /// An optional session token for this connection attempt.
  final String? sessionToken;

  /// The verified platform package name or bundle ID of the caller.
  final String? callingPackage;

  /// Whether the caller's identity was successfully verified by the OS.
  final bool isVerified;

  /// Whether the connection was initiated via a verified Universal/App Link.
  final bool isUniversalLink;

  const McpHostInfo({
    required this.hostScheme,
    required this.name,
    this.sessionToken,
    this.callingPackage,
    this.isVerified = false,
    this.isUniversalLink = false,
  });

  /// Creates an [McpHostInfo] from a JSON map.
  factory McpHostInfo.fromJson(Map<String, dynamic> json) {
    return McpHostInfo(
      hostScheme: json['hostScheme'] as String,
      name: json['name'] as String,
      sessionToken: json['sessionToken'] as String?,
      callingPackage: json['callingPackage'] as String?,
      isVerified: json['isVerified'] as bool? ?? false,
      isUniversalLink: json['isUniversalLink'] as bool? ?? false,
    );
  }

  /// Serializes to JSON.
  Map<String, dynamic> toJson() => {
    'hostScheme': hostScheme,
    'name': name,
    'isVerified': isVerified,
    'isUniversalLink': isUniversalLink,
    if (sessionToken != null) 'sessionToken': sessionToken,
    if (callingPackage != null) 'callingPackage': callingPackage,
  };

  @override
  String toString() => 'McpHostInfo(name: $name, hostScheme: $hostScheme)';
}

/// A registry entry representing a paired Tool or Host app.
///
/// Stored locally on each side to remember established connections
/// and their authentication tokens.
@immutable
class McpRegistryEntry {
  /// The unique identifier for this connection.
  final String id;

  /// The custom URL scheme of the connected app.
  final String appScheme;

  /// A human-readable display name.
  final String displayName;

  /// The authentication token for this pairing.
  final String token;

  /// The list of tool names this app provides (empty for Host entries).
  final List<String> capabilities;

  /// When this entry was created.
  final DateTime createdAt;

  const McpRegistryEntry({
    required this.id,
    required this.appScheme,
    required this.displayName,
    required this.token,
    this.capabilities = const [],
    required this.createdAt,
  });

  /// Creates an [McpRegistryEntry] from a JSON map.
  factory McpRegistryEntry.fromJson(Map<String, dynamic> json) {
    return McpRegistryEntry(
      id: json['id'] as String,
      appScheme: json['appScheme'] as String,
      displayName: json['displayName'] as String,
      token: json['token'] as String,
      capabilities:
          (json['capabilities'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  /// Serializes to JSON.
  Map<String, dynamic> toJson() => {
    'id': id,
    'appScheme': appScheme,
    'displayName': displayName,
    'token': token,
    'capabilities': capabilities,
    'createdAt': createdAt.toIso8601String(),
  };

  /// Creates a copy with optional overrides.
  McpRegistryEntry copyWith({
    String? id,
    String? appScheme,
    String? displayName,
    String? token,
    List<String>? capabilities,
    DateTime? createdAt,
  }) {
    return McpRegistryEntry(
      id: id ?? this.id,
      appScheme: appScheme ?? this.appScheme,
      displayName: displayName ?? this.displayName,
      token: token ?? this.token,
      capabilities: capabilities ?? this.capabilities,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() => 'McpRegistryEntry(id: $id, appScheme: $appScheme)';
}
