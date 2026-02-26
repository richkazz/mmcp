/// Exception types for the Mobile Model Context Protocol.
///
/// [McpException] wraps [McpError] objects for use in Dart's
/// exception handling flow, providing convenience constructors
/// for all standard JSON-RPC 2.0 error codes.
library;

import 'models.dart';

/// An exception thrown during MCP operations.
///
/// Wraps an [McpError] and provides convenient factory constructors
/// for all standard JSON-RPC 2.0 error codes.
///
/// Example:
/// ```dart
/// throw McpException.methodNotFound('Tool "foo" is not registered');
/// ```
class McpException implements Exception {
  /// The underlying MCP error.
  final McpError error;

  /// Creates an [McpException] wrapping the given [error].
  const McpException(this.error);

  /// The JSON-RPC error code.
  int get code => error.code;

  /// The error message.
  String get message => error.message;

  /// Optional additional error data.
  dynamic get data => error.data;

  /// Creates a Parse Error exception (-32700).
  factory McpException.parseError([String? message]) =>
      McpException(McpError.parseError(message));

  /// Creates an Invalid Request exception (-32600).
  factory McpException.invalidRequest([String? message]) =>
      McpException(McpError.invalidRequest(message));

  /// Creates a Method Not Found exception (-32601).
  factory McpException.methodNotFound([String? message]) =>
      McpException(McpError.methodNotFound(message));

  /// Creates an Invalid Params exception (-32602).
  factory McpException.invalidParams([String? message]) =>
      McpException(McpError.invalidParams(message));

  /// Creates an Internal Error exception (-32603).
  factory McpException.internalError([String? message]) =>
      McpException(McpError.internalError(message));

  /// Creates an [McpException] from an [McpError].
  factory McpException.fromError(McpError error) => McpException(error);

  @override
  String toString() => 'McpException(code: $code, message: $message)';
}

/// Thrown when a security check fails (e.g., insecure deep link transport).
class McpSecurityException extends McpException {
  McpSecurityException(String message)
      : super(McpError.internalError('Security Error: $message'));
}
