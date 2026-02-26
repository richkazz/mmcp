import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_mcp/mobile_mcp.dart';

void main() {
  group('McpSecurity', () {
    test('generateSessionToken returns valid UUID v4', () {
      final token = McpSecurity.generateSessionToken();
      expect(token, isNotEmpty);
      expect(McpSecurity.isValidToken(token), isTrue);
    });

    test('generateRequestId returns unique tokens', () {
      final id1 = McpSecurity.generateRequestId();
      final id2 = McpSecurity.generateRequestId();
      expect(id1, isNot(equals(id2)));
    });

    test('bearerHeader constructs header correctly', () {
      final header = McpSecurity.bearerHeader('test-token');
      expect(header, 'Bearer test-token');
    });

    test('extractBearerToken extracts token', () {
      final token = McpSecurity.extractBearerToken('Bearer my-secret-token');
      expect(token, 'my-secret-token');
    });

    test('extractBearerToken returns null on invalid header', () {
      expect(McpSecurity.extractBearerToken('Invalid header'), isNull);
      expect(McpSecurity.extractBearerToken(null), isNull);
      expect(McpSecurity.extractBearerToken('Bearer '), isNull);
    });
  });
}
