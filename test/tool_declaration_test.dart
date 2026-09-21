import 'package:flutter_local_ai/flutter_local_ai.dart';
import 'package:flutter_local_ai/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolvedParameterSchema', () {
    test('a flat declaration becomes an equivalent object schema', () {
      final tool = LocalAiTool(
        name: 'weather',
        description: 'Current weather',
        parameters: const [
          ToolParameter(name: 'city', description: 'Where to look'),
          ToolParameter(
            name: 'days',
            type: ToolArgumentType.integer,
            optional: true,
          ),
        ],
        onCall: (_) => null,
      );

      expect(tool.resolvedParameterSchema, {
        'type': 'object',
        'properties': {
          'city': {'type': 'string', 'description': 'Where to look'},
          'days': {'type': 'integer'},
        },
        // JSON Schema states optionality on the enclosing object, so an
        // optional parameter is simply absent from `required`.
        'required': ['city'],
      });
    });

    test('a zero-argument tool is an empty object schema', () {
      final tool = LocalAiTool(
        name: 'status',
        description: 'Read status',
        onCall: (_) => null,
      );

      expect(tool.resolvedParameterSchema, {
        'type': 'object',
        'properties': <String, dynamic>{},
        'required': <String>[],
      });
    });

    test('a schema declaration is passed through whole', () {
      const schema = {
        'type': 'object',
        'properties': {
          'colour': {
            'enum': ['red', 'green', 'blue'],
          },
          'shades': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'name': {'type': 'string'},
                'weight': {'type': 'number'},
              },
              'required': ['name'],
            },
          },
        },
        'required': ['colour'],
      };
      final tool = LocalAiTool(
        name: 'paint',
        description: 'Paint something',
        parameterSchema: schema,
        onCall: (_) => null,
      );

      // The constraint a flat parameter list cannot express — a string enum,
      // a list, a nested object — survives the declaration intact.
      expect(tool.resolvedParameterSchema, schema);
    });
  });

  group('validateParameterSchema', () {
    test('accepts nested objects, arrays and string enums', () {
      LocalAiTool(
        name: 'paint',
        description: 'Paint something',
        parameterSchema: const {
          'type': 'object',
          'properties': {
            'colour': {
              'enum': ['red', 'green'],
            },
            'layers': {
              'type': 'array',
              'items': {
                'type': 'object',
                'properties': {
                  'thickness': {'type': 'number'},
                },
              },
              'minItems': 1,
            },
          },
        },
        onCall: (_) => null,
      ).validateParameterSchema();
    });

    test('rejects a schema that is not an object', () {
      final tool = LocalAiTool(
        name: 'paint',
        description: 'Paint something',
        parameterSchema: const {'type': 'string'},
        onCall: (_) => null,
      );

      expect(
        tool.validateParameterSchema,
        throwsA(
          isA<ArgumentError>().having(
            (e) => '${e.message}',
            'message',
            contains('must be an object schema'),
          ),
        ),
      );
    });

    test('rejects an unsupported construct, naming the path', () {
      final tool = LocalAiTool(
        name: 'paint',
        description: 'Paint something',
        parameterSchema: const {
          'type': 'object',
          'properties': {
            'colour': {'type': 'colour'},
          },
        },
        onCall: (_) => null,
      );

      expect(
        tool.validateParameterSchema,
        throwsA(
          isA<ArgumentError>().having(
            (e) => '${e.message}',
            'message',
            contains(r'$.properties.colour'),
          ),
        ),
      );
    });

    test('rejects a declaration that is both flat and schema-shaped', () {
      final tool = LocalAiTool(
        name: 'paint',
        description: 'Paint something',
        parameters: const [ToolParameter(name: 'colour')],
        parameterSchema: const {'type': 'object'},
        onCall: (_) => null,
      );

      expect(
        tool.validateParameterSchema,
        throwsA(
          isA<ArgumentError>().having(
            (e) => '${e.message}',
            'message',
            contains('Use one or the other'),
          ),
        ),
      );
    });
  });

  group('openSession', () {
    late FakeLocalAiHost host;

    setUp(() {
      host = FakeLocalAiHost();
      debugLocalAiHost = host;
    });

    tearDown(() async {
      debugLocalAiHost = null;
      await host.dispose();
    });

    test('carries a tool schema down to the host', () async {
      final model = await LocalAiModel.create();
      addTearDown(model.close);

      await model.openSession(
        tools: [
          LocalAiTool(
            name: 'paint',
            description: 'Paint something',
            parameterSchema: const {
              'type': 'object',
              'properties': {
                'colour': {
                  'enum': ['red', 'green', 'blue'],
                },
              },
              'required': ['colour'],
            },
            onCall: (_) => null,
          ),
        ],
      );

      expect(host.sessions.single.toolSchemas['paint'], {
        'type': 'object',
        'properties': {
          'colour': {
            'enum': ['red', 'green', 'blue'],
          },
        },
        'required': ['colour'],
      });
    });

    test('rejects an invalid tool schema before opening anything', () async {
      final model = await LocalAiModel.create();
      addTearDown(model.close);

      await expectLater(
        model.openSession(
          tools: [
            LocalAiTool(
              name: 'paint',
              description: 'Paint something',
              parameterSchema: const {
                'type': 'object',
                'properties': {
                  'colour': {'type': 'colour'},
                },
              },
              onCall: (_) => null,
            ),
          ],
        ),
        throwsA(isA<ArgumentError>()),
      );

      // Failing in Dart means no native session was ever built for it.
      expect(host.sessions, isEmpty);
    });
  });
}
