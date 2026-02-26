/// Cryptographic security utilities for MCP.
///
/// Provides session token generation using UUID v4 for secure
/// WebSocket authentication between Host and Tool apps.
library;

import 'package:uuid/uuid.dart';

/// Security utilities for the MCP protocol.
///
/// Generates cryptographically random session tokens used to
/// authenticate WebSocket connections after the deep link handshake.
class McpSecurity {
  static const _uuid = Uuid();

  /// Generates a new cryptographically random session token.
  ///
  /// Returns a UUID v4 string (e.g., `'f47ac10b-58cc-4372-a567-0e02b2c3d479'`).
  static String generateSessionToken() {
    return _uuid.v4();
  }

  /// Generates a unique request ID for JSON-RPC calls.
  static String generateRequestId() {
    return _uuid.v4();
  }

  /// Validates that a token matches the expected format (UUID v4).
  static bool isValidToken(String token) {
    return Uuid.isValidUUID(fromString: token);
  }

  /// Constructs the `Authorization` header value for WebSocket connections.
  static String bearerHeader(String token) => 'Bearer $token';

  /// Extracts the token from an `Authorization: Bearer <token>` header.
  ///
  /// Returns `null` if the header is missing or malformed.
  static String? extractBearerToken(String? authHeader) {
    if (authHeader == null) return null;
    if (!authHeader.startsWith('Bearer ')) return null;
    final token = authHeader.substring(7).trim();
    return token.isNotEmpty ? token : null;
  }
}
