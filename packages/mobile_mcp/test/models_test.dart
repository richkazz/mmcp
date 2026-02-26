import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_mcp/mobile_mcp.dart';

void main() {
  group('McpToolDefinition', () {
    test('toJson and fromJson', () {
      const tool = McpToolDefinition(
        name: 'test_tool',
        description: 'A test tool',
        inputSchema: {'type': 'object', 'properties': {}},
      );

      final json = tool.toJson();
      final fromJson = McpToolDefinition.fromJson(json);

      expect(fromJson.name, tool.name);
      expect(fromJson.description, tool.description);
      expect(fromJson.inputSchema, tool.inputSchema);
    });
  });

  group('McpRequest', () {
    test('toJson and fromJson', () {
      const request = McpRequest(
        id: '1',
        method: 'test_method',
        params: {'foo': 'bar'},
      );

      final json = request.toJson();
      expect(json['jsonrpc'], '2.0');
      expect(json['id'], '1');
      expect(json['method'], 'test_method');
      expect(json['params'], {'foo': 'bar'});

      final fromJson = McpRequest.fromJson(json);
      expect(fromJson.id, request.id);
      expect(fromJson.method, request.method);
      expect(fromJson.params, request.params);
    });
  });

  group('McpResponse', () {
    test('success response', () {
      final response = McpResponse.success(id: '1', result: {'ok': true});
      final json = response.toJson();

      expect(json['id'], '1');
      expect(json['result'], {'ok': true});
      expect(json.containsKey('error'), isFalse);

      final fromJson = McpResponse.fromJson(json);
      expect(fromJson.id, '1');
      expect(fromJson.result, {'ok': true});
      expect(fromJson.isSuccess, isTrue);
    });

    test('error response', () {
      final response = McpResponse.error(
        id: '1',
        error: const McpError(code: -32601, message: 'Method not found'),
      );
      final json = response.toJson();

      expect(json['id'], '1');
      expect(json['error']['code'], -32601);
      expect(json.containsKey('result'), isFalse);

      final fromJson = McpResponse.fromJson(json);
      expect(fromJson.id, '1');
      expect(fromJson.isError, isTrue);
      expect(fromJson.error!.code, -32601);
    });
  });
}
