import 'dart:async';

import 'package:flutter_local_ai/flutter_local_ai.dart';
import 'package:flutter_local_ai/testing.dart';
import 'package:flutter_test/flutter_test.dart';

/// The fake plays the model's half of a tool call, so an adapter's tool loop
/// is testable without a device — which is the whole point of the fake.
void main() {
  late FakeLocalAiHost host;

  setUp(() {
    host = FakeLocalAiHost();
    debugLocalAiHost = host;
  });

  tearDown(() async {
    debugLocalAiHost = null;
    await host.dispose();
  });

  Future<LocalAiSession> openWith(List<LocalAiTool> tools) async {
    final model = await LocalAiModel.create();
    addTearDown(model.close);
    return model.openSession(tools: tools);
  }

  test('invokeTool runs the registered handler and records the call', () async {
    final session = await openWith([
      LocalAiTool(
        name: 'weather',
        description: 'Current weather',
        parameters: const [ToolParameter(name: 'city')],
        onCall: (arguments) => {'temp': 21, 'city': arguments['city']},
      ),
    ]);

    final result = await host.invokeTool(session.sessionId, 'weather', {
      'city': 'Rome',
    });

    expect(result, '{"temp":21,"city":"Rome"}');
    expect(host.toolCalls.single.toolName, 'weather');
    expect(host.toolCalls.single.arguments, {'city': 'Rome'});
  });

  test('suspends until the app answers, as a real tool call does', () async {
    final approval = Completer<String>();
    final session = await openWith([
      LocalAiTool(
        name: 'transfer',
        description: 'Move money',
        onCall: (_) => approval.future,
      ),
    ]);

    var answered = false;
    final pending = host
        .invokeTool(session.sessionId, 'transfer')
        .whenComplete(() => answered = true);

    // The confirm-before-acting flow: nothing resolves while a human decides.
    await pumpEventQueue();
    expect(answered, isFalse);

    approval.complete('approved');
    expect(await pending, '"approved"');
  });

  test('a refused tool answers the model rather than throwing', () async {
    final session = await openWith([
      LocalAiTool(
        name: 'transfer',
        description: 'Move money',
        onCall: (_) =>
            throw const LocalAiToolException('The user declined the transfer.'),
      ),
    ]);

    expect(
      await host.invokeTool(session.sessionId, 'transfer'),
      '{"error":"The user declined the transfer."}',
    );
  });

  test('a tool is reachable only from the session it was bound to', () async {
    final session = await openWith([
      LocalAiTool(
        name: 'weather',
        description: 'Current weather',
        onCall: (_) => 'sunny',
      ),
    ]);

    expect(
      () => host.invokeTool(session.sessionId + 1, 'weather'),
      throwsA(isA<UnknownToolException>()),
    );
  });

  test('closing the session makes a late call fail', () async {
    final session = await openWith([
      LocalAiTool(
        name: 'weather',
        description: 'Current weather',
        onCall: (_) => 'sunny',
      ),
    ]);

    await session.close();

    expect(
      () => host.invokeTool(session.sessionId, 'weather'),
      throwsA(isA<UnknownToolException>()),
    );
  });

  test(
    'a host without tool calling rejects a session that binds tools',
    () async {
      debugLocalAiHost = null;
      await host.dispose();
      host = FakeLocalAiHost(
        capabilities: const LocalAiBackendCapabilities(
          backend: LocalAiBackendKind.androidMlKitGenAi,
          platform: 'fake',
          apiName: 'Fake',
          isConfigured: true,
        ),
      );
      debugLocalAiHost = host;

      await expectLater(
        openWith([
          LocalAiTool(
            name: 'weather',
            description: 'Current weather',
            onCall: (_) => 'sunny',
          ),
        ]),
        throwsA(isA<LocalAiUnsupportedException>()),
      );
    },
  );
}
