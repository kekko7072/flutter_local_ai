import 'package:flutter_local_ai/flutter_local_ai.dart';
import 'package:flutter_local_ai/src/session/local_ai_tool_registry.dart';
import 'package:flutter_test/flutter_test.dart';

LocalAiTool _tool(
  String name, {
  Object? Function(Map<String, dynamic> arguments)? onCall,
}) => LocalAiTool(
  name: name,
  description: 'test tool',
  parameters: const [ToolParameter(name: 'city')],
  onCall: onCall ?? (arguments) => 'called $name with $arguments',
);

void main() {
  late LocalAiToolRegistry registry;

  setUp(() => registry = LocalAiToolRegistry());

  group('dispatch', () {
    test('runs the named tool and encodes its result as JSON', () async {
      registry.register(1, [
        _tool('weather', onCall: (args) => {'temp': 21, 'city': args['city']}),
      ]);

      final result = await registry.invoke(1, 'weather', '{"city":"Rome"}');

      expect(result, '{"temp":21,"city":"Rome"}');
    });

    test('awaits an asynchronous tool body', () async {
      registry.register(1, [
        _tool(
          'slow',
          onCall: (_) async {
            await Future<void>.delayed(Duration.zero);
            return 'done';
          },
        ),
      ]);

      expect(await registry.invoke(1, 'slow', '{}'), '"done"');
    });

    test('a tool that yields nothing returns null, not "null"', () async {
      registry.register(1, [_tool('noop', onCall: (_) => null)]);

      // The host turns null into a JSON null itself; encoding it here would
      // be indistinguishable from a tool that genuinely returned the string.
      expect(await registry.invoke(1, 'noop', '{}'), isNull);
    });

    test('propagates a failure from the tool body', () async {
      registry.register(1, [
        _tool('broken', onCall: (_) => throw StateError('tool exploded')),
      ]);

      expect(() => registry.invoke(1, 'broken', '{}'), throwsStateError);
    });
  });

  group('argument decoding', () {
    test('passes the decoded object through', () async {
      Map<String, dynamic>? seen;
      registry.register(1, [
        _tool(
          'spy',
          onCall: (args) {
            seen = args;
            return null;
          },
        ),
      ]);

      await registry.invoke(1, 'spy', '{"a":1,"b":[2,3]}');

      expect(seen, {
        'a': 1,
        'b': [2, 3],
      });
    });

    test('an empty payload is an empty argument map', () async {
      Map<String, dynamic>? seen;
      registry.register(1, [
        _tool(
          'spy',
          onCall: (args) {
            seen = args;
            return null;
          },
        ),
      ]);

      await registry.invoke(1, 'spy', '');

      // A zero-argument tool is legitimate; this must not be an error.
      expect(seen, isEmpty);
    });

    test('malformed JSON degrades to empty arguments', () async {
      Map<String, dynamic>? seen;
      registry.register(1, [
        _tool(
          'spy',
          onCall: (args) {
            seen = args;
            return null;
          },
        ),
      ]);

      await registry.invoke(1, 'spy', 'not json at all');

      // Letting the tool decide beats failing the whole generation over one
      // malformed call.
      expect(seen, isEmpty);
    });

    test('a non-object payload degrades to empty arguments', () async {
      Map<String, dynamic>? seen;
      registry.register(1, [
        _tool(
          'spy',
          onCall: (args) {
            seen = args;
            return null;
          },
        ),
      ]);

      await registry.invoke(1, 'spy', '[1,2,3]');

      expect(seen, isEmpty);
    });
  });

  group('session scoping', () {
    test('a tool registered for one session is invisible to another', () async {
      registry.register(1, [_tool('weather')]);

      expect(
        () => registry.invoke(2, 'weather', '{}'),
        throwsA(isA<UnknownToolException>()),
      );
    });

    test('an unknown tool name names both the tool and the session', () async {
      registry.register(1, [_tool('weather')]);

      await expectLater(
        registry.invoke(1, 'stocks', '{}'),
        throwsA(
          isA<UnknownToolException>()
              .having((e) => e.toolName, 'toolName', 'stocks')
              .having((e) => e.sessionId, 'sessionId', 1),
        ),
      );
    });

    test(
      'forget makes a late call fail instead of running a stale handler',
      () async {
        registry.register(1, [_tool('weather')]);
        registry.forget(1);

        expect(
          () => registry.invoke(1, 'weather', '{}'),
          throwsA(isA<UnknownToolException>()),
        );
      },
    );

    test('clear drops every session, as closing the model does', () async {
      registry.register(1, [_tool('a')]);
      registry.register(2, [_tool('b')]);

      registry.clear();

      expect(registry.isEmpty, isTrue);
      expect(
        () => registry.invoke(2, 'b', '{}'),
        throwsA(isA<UnknownToolException>()),
      );
    });

    test('registering again replaces the previous set', () async {
      registry.register(1, [_tool('old')]);
      registry.register(1, [_tool('new')]);

      expect(await registry.invoke(1, 'new', '{}'), isNotNull);
      expect(
        () => registry.invoke(1, 'old', '{}'),
        throwsA(isA<UnknownToolException>()),
      );
    });

    test('registering an empty list costs no bookkeeping', () {
      registry.register(1, const []);
      registry.register(2, null);

      expect(registry.isEmpty, isTrue);
    });
  });
}
