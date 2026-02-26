import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_mcp/mobile_mcp.dart';

void main() {
  group('McpError', () {
    test('standard codes', () {
      expect(McpError.parseErrorCode, -32700);
      expect(McpError.invalidRequestCode, -32600);
      expect(McpError.methodNotFoundCode, -32601);
      expect(McpError.invalidParamsCode, -32602);
      expect(McpError.internalErrorCode, -32603);
    });

    test('factory constructors', () {
      final parseError = McpError.parseError();
      expect(parseError.code, -32700);
      expect(parseError.message, 'Parse error');

      final methodNotFound = McpError.methodNotFound('Custom message');
      expect(methodNotFound.code, -32601);
      expect(methodNotFound.message, 'Custom message');
    });
  });

  group('McpException', () {
    test('wrapping McpError', () {
      const error = McpError(code: 100, message: 'Test');
      const exception = McpException(error);

      expect(exception.code, 100);
      expect(exception.message, 'Test');
    });

    test('factory constructors', () {
      final exception = McpException.methodNotFound();
      expect(exception.code, -32601);
      expect(exception.toString(), contains('Method not found'));
    });
  });
}
