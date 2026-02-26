import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_mcp/mobile_mcp.dart';
import 'package:mobile_mcp/src/tool/tool_registry.dart';
import 'package:mobile_mcp/src/tool/tool_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Token Update Repro', () {
    late McpToolRegistry registry;
    late McpToolServer server;

    setUp(() {
      registry = McpToolRegistry();
      server = McpToolServer(registry: registry);
    });

    tearDown(() async {
      await server.dispose();
    });

    test('Server should update session token on subsequent start() calls', () async {
      final port = await server.start(sessionToken: 'token1');
      expect(server.sessionToken, 'token1');

      // Simulate a second wakeup with a new token
      final port2 = await server.start(sessionToken: 'token2');
      expect(port2, port);

      // Verify connection with token2 works
      final client = await WebSocket.connect('ws://localhost:$port');

      // Before fix, server.sessionToken will still be 'token1', so this should fail
      expect(server.sessionToken, 'token2', reason: 'Session token should be updated even if server is already running');

      client.add(jsonEncode({'type': 'auth', 'token': 'token2'}));

      client.add(jsonEncode({
        'jsonrpc': '2.0',
        'id': '1',
        'method': 'mcp/listTools',
        'params': {}
      }));

      final responseCompleter = Completer<String>();
      client.listen((data) {
        if (!responseCompleter.isCompleted) {
          responseCompleter.complete(data as String);
        }
      }, onDone: () {
        if (!responseCompleter.isCompleted) {
          responseCompleter.completeError('Connection closed');
        }
      });

      try {
        final response = await responseCompleter.future.timeout(const Duration(seconds: 2));
        expect(response, contains('"id":"1"'));
      } catch (e) {
        fail('Connection with token2 failed: $e');
      }

      await client.close();
    });
  });
}
