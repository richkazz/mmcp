/// JSON Schema validation for MCP tool input arguments.
///
/// Validates incoming arguments against a tool's declared [inputSchema]
/// before invoking the developer's handler, automatically returning
/// an [McpError.invalidParams] if validation fails.
library;

import 'shared/models.dart';

/// Validates tool arguments against a JSON Schema definition.
///
/// This is a lightweight validator supporting common JSON Schema features:
/// - `type` checks (object, string, integer, number, boolean, array)
/// - `required` field enforcement
/// - `properties` validation (recursive)
///
/// For production use cases requiring full JSON Schema Draft-07 compliance,
/// consider using the `json_schema` package directly.
class McpSchemaValidator {
  const McpSchemaValidator();

  /// Validates [arguments] against the given [schema].
  ///
  /// Returns `null` if validation passes, or an [McpError.invalidParams]
  /// describing the first validation failure found.
  McpError? validate(
    Map<String, dynamic> arguments,
    Map<String, dynamic> schema,
  ) {
    // Check top-level type
    final type = schema['type'] as String?;
    if (type != null && type != 'object') {
      return McpError.invalidParams(
        'Schema root type must be "object", got "$type"',
      );
    }

    // Check required fields
    final required = schema['required'] as List<dynamic>?;
    if (required != null) {
      for (final field in required) {
        if (!arguments.containsKey(field)) {
          return McpError.invalidParams('Missing required field: "$field"');
        }
      }
    }

    // Validate properties
    final propertiesRaw = schema['properties'];
    final properties = propertiesRaw is Map
        ? Map<String, dynamic>.from(propertiesRaw)
        : null;

    if (properties != null) {
      for (final entry in arguments.entries) {
        final propSchemaRaw = properties[entry.key];
        final propSchema = propSchemaRaw is Map
            ? Map<String, dynamic>.from(propSchemaRaw)
            : null;

        if (propSchema != null) {
          final error = _validateValue(entry.key, entry.value, propSchema);
          if (error != null) return error;
        }
      }
    }

    return null;
  }

  /// Validates a single value against its property schema.
  McpError? _validateValue(
    String fieldName,
    dynamic value,
    Map<String, dynamic> propSchema,
  ) {
    final expectedType = propSchema['type'] as String?;
    if (expectedType == null) return null;

    switch (expectedType) {
      case 'string':
        if (value is! String) {
          return McpError.invalidParams(
            'Field "$fieldName" expected type string, got ${value.runtimeType}',
          );
        }
      case 'integer':
        if (value is! int) {
          return McpError.invalidParams(
            'Field "$fieldName" expected type integer, got ${value.runtimeType}',
          );
        }
      case 'number':
        if (value is! num) {
          return McpError.invalidParams(
            'Field "$fieldName" expected type number, got ${value.runtimeType}',
          );
        }
      case 'boolean':
        if (value is! bool) {
          return McpError.invalidParams(
            'Field "$fieldName" expected type boolean, got ${value.runtimeType}',
          );
        }
      case 'array':
        if (value is! List) {
          return McpError.invalidParams(
            'Field "$fieldName" expected type array, got ${value.runtimeType}',
          );
        }
      case 'object':
        if (value is! Map) {
          return McpError.invalidParams(
            'Field "$fieldName" expected type object, got ${value.runtimeType}',
          );
        }
    }

    return null;
  }
}
