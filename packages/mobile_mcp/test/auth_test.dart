import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_mcp/mobile_mcp.dart';

void main() {
  group('Authentication Handshake', () {
    late HttpServer server;
    late McpToolRegistry registry;
    const testToken = 'test-token-123';

    setUp(() async {
      registry = McpToolRegistry();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test('Successful authentication via first message', () async {
      final completer = Completer<void>();

      server.listen((request) async {
        final ws = await WebSocketTransformer.upgrade(request);
        McpToolSession(
          ws: ws,
          registry: registry,
          logger: McpLogger(level: McpLogLevel.none),
          expectedToken: testToken,
          onDone: () {},
        );
        completer.complete();
      });

      final client = await WebSocket.connect('ws://localhost:${server.port}');
      client.add(jsonEncode({'type': 'auth', 'token': testToken}));

      await completer.future;

      const requestId = 'req-1';
      client.add(jsonEncode({
        'jsonrpc': '2.0',
        'id': requestId,
        'method': 'mcp/listTools',
        'params': {}
      }));

      final responseStr = await client.first.timeout(const Duration(seconds: 2));
      final response = jsonDecode(responseStr as String);
      expect(response['id'], requestId);

      await client.close();
    });

    test('Failed authentication closes connection', () async {
      server.listen((request) async {
        final ws = await WebSocketTransformer.upgrade(request);
        McpToolSession(
          ws: ws,
          registry: registry,
          logger: McpLogger(level: McpLogLevel.none),
          expectedToken: testToken,
          onDone: () {},
        );
      });

      final client = await WebSocket.connect('ws://localhost:${server.port}');
      client.listen((_) {}, onDone: () {}, onError: (_) {});
      client.add(jsonEncode({'type': 'auth', 'token': 'wrong-token'}));

      await client.done.timeout(const Duration(seconds: 2));
    });

    test('Rejects JSON-RPC before authentication', () async {
      server.listen((request) async {
        final ws = await WebSocketTransformer.upgrade(request);
        McpToolSession(
          ws: ws,
          registry: registry,
          logger: McpLogger(level: McpLogLevel.none),
          expectedToken: testToken,
          onDone: () {},
        );
      });

      final client = await WebSocket.connect('ws://localhost:${server.port}');
      client.listen((_) {}, onDone: () {}, onError: (_) {});
      client.add(jsonEncode({
        'jsonrpc': '2.0',
        'id': '1',
        'method': 'mcp/listTools',
        'params': {}
      }));

      await client.done.timeout(const Duration(seconds: 2));
    });

    test('Works if already authenticated via headers', () async {
      final completer = Completer<void>();

      server.listen((request) async {
        final ws = await WebSocketTransformer.upgrade(request);
        McpToolSession(
          ws: ws,
          registry: registry,
          logger: McpLogger(level: McpLogLevel.none),
          expectedToken: testToken,
          onDone: () {},
          alreadyAuthenticated: true,
        );
        completer.complete();
      });

      final client = await WebSocket.connect('ws://localhost:${server.port}');
      client.add(jsonEncode({'type': 'auth', 'token': testToken}));

      await completer.future;

      const requestId = 'req-2';
      client.add(jsonEncode({
        'jsonrpc': '2.0',
        'id': requestId,
        'method': 'mcp/listTools',
        'params': {}
      }));

      final responseStr = await client.first.timeout(const Duration(seconds: 2));
      final response = jsonDecode(responseStr as String);
      expect(response['id'], requestId);

      await client.close();
    });
  });
}
