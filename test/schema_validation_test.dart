import 'package:flutter_local_ai/src/models/schema_validation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('validateGenerationSchema (supported subset)', () {
    test('accepts a nested object with properties, required, and description',
        () {
      expect(
        () => validateGenerationSchema(const {
          'type': 'object',
          'description': 'A support ticket',
          'properties': {
            'title': {'type': 'string', 'description': 'Short headline'},
            'priority': {
              'enum': ['low', 'med', 'high'],
            },
            'tags': {
              'type': 'array',
              'items': {'type': 'string'},
              'minItems': 1,
              'maxItems': 5,
            },
            'meta': {
              'type': 'object',
              'properties': {
                'count': {'type': 'integer'},
                'ratio': {'type': 'number'},
                'urgent': {'type': 'boolean'},
              },
            },
          },
          'required': ['title'],
        }),
        returnsNormally,
      );
    });

    test('treats an object as the default when type is omitted', () {
      expect(() => validateGenerationSchema(const {}), returnsNormally);
      expect(
        () => validateGenerationSchema(const {
          'properties': {
            'a': {'type': 'string'},
          },
        }),
        returnsNormally,
      );
    });

    test('accepts an enum with or without an explicit type', () {
      expect(
        () => validateGenerationSchema(const {
          'enum': ['a', 'b'],
        }),
        returnsNormally,
      );
      expect(
        () => validateGenerationSchema(const {
          'type': 'string',
          'enum': ['a', 'b'],
        }),
        returnsNormally,
      );
    });
  });

  group('validateGenerationSchema (rejections)', () {
    test('rejects an empty enum', () {
      expect(
        () => validateGenerationSchema(const {'enum': []}),
        throwsArgumentError,
      );
    });

    test('rejects a non-string enum value', () {
      expect(
        () => validateGenerationSchema(const {
          'enum': ['a', 1],
        }),
        throwsArgumentError,
      );
    });

    test('rejects an unsupported scalar type', () {
      expect(
        () => validateGenerationSchema(const {'type': 'date'}),
        throwsArgumentError,
      );
    });

    test('rejects a union/nullable type list', () {
      expect(
        () => validateGenerationSchema(const {
          'type': ['string', 'null'],
        }),
        throwsArgumentError,
      );
    });

    test('rejects an array without items', () {
      expect(
        () => validateGenerationSchema(const {'type': 'array'}),
        throwsArgumentError,
      );
    });

    test('rejects non-integer array bounds', () {
      expect(
        () => validateGenerationSchema(const {
          'type': 'array',
          'items': {'type': 'string'},
          'minItems': 1.5,
        }),
        throwsArgumentError,
      );
    });

    test('rejects a property whose schema is not a map', () {
      expect(
        () => validateGenerationSchema(const {
          'type': 'object',
          'properties': {'title': 'string'},
        }),
        throwsArgumentError,
      );
    });

    test('rejects a non-string required entry', () {
      expect(
        () => validateGenerationSchema(const {
          'type': 'object',
          'properties': {
            'title': {'type': 'string'},
          },
          'required': [1],
        }),
        throwsArgumentError,
      );
    });

    test('surfaces the offending path in nested schemas', () {
      expect(
        () => validateGenerationSchema(const {
          'type': 'object',
          'properties': {
            'items': {
              'type': 'array',
              'items': {'type': 'date'},
            },
          },
        }),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains(r'$.properties.items.items'),
          ),
        ),
      );
    });
  });
}
