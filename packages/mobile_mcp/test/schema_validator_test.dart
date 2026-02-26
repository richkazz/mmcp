import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_mcp/mobile_mcp.dart';

void main() {
  group('McpSchemaValidator', () {
    const validator = McpSchemaValidator();

    test('validates correct arguments', () {
      final schema = {
        'type': 'object',
        'required': ['id', 'name'],
        'properties': {
          'id': {'type': 'integer'},
          'name': {'type': 'string'},
          'active': {'type': 'boolean'},
        }
      };

      final args = {'id': 123, 'name': 'John Doe', 'active': true};
      final error = validator.validate(args, schema);

      expect(error, isNull);
    });

    test('fails on missing required field', () {
      final schema = {
        'type': 'object',
        'required': ['id'],
        'properties': {'id': {'type': 'integer'}}
      };

      final args = {'name': 'Missing ID'};
      final error = validator.validate(args, schema);

      expect(error, isNotNull);
      expect(error!.code, -32602);
      expect(error.message, contains('Missing required field: "id"'));
    });

    test('fails on incorrect type', () {
      final schema = {
        'type': 'object',
        'properties': {'id': {'type': 'integer'}}
      };

      final args = {'id': 'not an integer'};
      final error = validator.validate(args, schema);

      expect(error, isNotNull);
      expect(error!.code, -32602);
      expect(error.message, contains('expected type integer, got String'));
    });

    test('validates arrays and nested objects', () {
      final schema = {
        'type': 'object',
        'properties': {
          'tags': {'type': 'array'},
          'metadata': {'type': 'object'},
        }
      };

      final args = {
        'tags': ['a', 'b'],
        'metadata': {'foo': 'bar'},
      };
      final error = validator.validate(args, schema);

      expect(error, isNull);
    });
  });
}
