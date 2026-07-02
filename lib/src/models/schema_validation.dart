/// The scalar JSON Schema types the native backends can translate.
const _scalarTypes = {'string', 'integer', 'number', 'boolean'};

/// Validates that [schema] uses only the JSON Schema subset the native backends
/// can translate (Apple FoundationModels `GenerationSchema`), throwing an
/// [ArgumentError] with a path-qualified message otherwise. Catching invalid
/// schemas in Dart yields a clear, immediate error instead of an opaque native
/// failure after the method-channel round trip.
///
/// Supported constructs (mirrors the Apple `SchemaBuilder`):
/// - objects: `type: 'object'` (or omitted) with `properties` (each itself a
///   schema), an optional `required` list of property names, and `description`;
/// - arrays: `type: 'array'` with an `items` schema and optional integer
///   `minItems` / `maxItems`;
/// - string enums: `enum` as a non-empty list of strings (with or without a
///   `type`);
/// - scalars: a `type` of `string`, `integer`, `number`, or `boolean`.
void validateGenerationSchema(Map<String, dynamic> schema) {
  _validateNode(schema, r'$');
}

void _validateNode(Object? node, String path) {
  if (node is! Map) {
    throw ArgumentError.value(
        node, 'schema', 'Schema node at $path must be a map.');
  }

  // An `enum` is a string-choice constraint regardless of any `type`, matching
  // the native builder which short-circuits on it.
  if (node.containsKey('enum')) {
    final choices = node['enum'];
    if (choices is! List || choices.isEmpty) {
      throw ArgumentError.value(choices, 'enum',
          'Schema `enum` at $path must be a non-empty list of strings.');
    }
    for (var i = 0; i < choices.length; i++) {
      if (choices[i] is! String) {
        throw ArgumentError.value(choices[i], 'enum',
            'Schema `enum` at $path[$i] must be a string; only string enums '
            'are supported.');
      }
    }
    return;
  }

  final rawType = node['type'];
  if (rawType != null && rawType is! String) {
    // e.g. `type: ['string', 'null']` for nullability — not supported yet.
    throw ArgumentError.value(rawType, 'type',
        'Schema `type` at $path must be a string; union/nullable types are '
        'not supported.');
  }
  final type = (rawType as String?)?.toLowerCase() ?? 'object';

  switch (type) {
    case 'object':
      final properties = node['properties'];
      if (properties != null) {
        if (properties is! Map) {
          throw ArgumentError.value(properties, 'properties',
              'Schema `properties` at $path must be a map.');
        }
        properties.forEach((key, value) {
          _validateNode(value, '$path.properties.$key');
        });
      }
      final required = node['required'];
      if (required != null &&
          (required is! List || required.any((e) => e is! String))) {
        throw ArgumentError.value(required, 'required',
            'Schema `required` at $path must be a list of property-name '
            'strings.');
      }
      return;

    case 'array':
      final items = node['items'];
      if (items == null) {
        throw ArgumentError.value(null, 'items',
            'Array schema at $path requires an `items` schema.');
      }
      _validateNode(items, '$path.items');
      _validateIntBound(node['minItems'], 'minItems', path);
      _validateIntBound(node['maxItems'], 'maxItems', path);
      return;

    default:
      if (_scalarTypes.contains(type)) return;
      throw ArgumentError.value(type, 'type',
          'Unsupported schema type `$type` at $path. Supported: object, '
          'array, string, integer, number, boolean, or a string `enum`.');
  }
}

void _validateIntBound(Object? value, String key, String path) {
  if (value != null && value is! int) {
    throw ArgumentError.value(
        value, key, 'Schema `$key` at $path must be an integer.');
  }
}
