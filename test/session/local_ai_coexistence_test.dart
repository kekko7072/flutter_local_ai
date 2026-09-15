import 'dart:async';

import 'package:flutter_local_ai/flutter_local_ai.dart';
import 'package:flutter_local_ai/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeLocalAiHost host;
  setUp(() {
    host = FakeLocalAiHost();
    debugLocalAiHost = host;
  });
  tearDown(() async {
    await FlutterLocalAi.debugReset();
    debugLocalAiHost = null;
    await host.dispose();
  });

  test(
    'independent model owners cannot collide or tear down each other',
    () async {
      final models = await Future.wait([
        LocalAiModel.create(),
        LocalAiModel.create(),
      ]);
      final a = await models[0].openSession();
      final b = await models[1].openSession();
      expect(a.sessionId, isNot(b.sessionId));
      expect(host.calls.where((c) => c == 'createModel'), hasLength(1));
      final output = b.getResponseAsync().toList();
      await pumpEventQueue();
      host.emitToken(a.sessionId, 'wrong owner');
      await models[0].close();
      expect(host.modelClosed, isFalse);
      host.emitDone(b.sessionId, text: 'right owner');
      expect(await output, ['right owner']);
      await models[1].close();
      expect(host.modelClosed, isTrue);
      final replacement = await LocalAiModel.create();
      final c = await replacement.openSession();
      expect(c.sessionId, greaterThan(b.sessionId));
      await replacement.close();
    },
  );

  test(
    'genUI borrows the host without disturbing the facade or another owner',
    () async {
      final model = await LocalAiModel.create();
      final chat = await model.openSession(systemInstruction: 'Direct chat');
      final ai = FlutterLocalAi();
      await ai.initialize(instructions: 'Application chat');
      final shared = host.sessions.last;
      host.response =
          '{"title":"Plan","blocks":[{"type":"note","text":"Start"}]}';
      final spec = await LocalAiUiGenerator(ai).generateModule('Plan today');
      expect(spec, isNotNull);
      expect(shared.closed, isFalse);
      expect(shared.systemInstruction, 'Application chat');
      expect(
        host.sessions.last.systemInstruction,
        LocalAiUiGenerator.genUiInstructions,
      );
      expect(host.sessions.last.closed, isTrue);
      await model.close();
      expect(host.modelClosed, isFalse);
      expect((await ai.generateText(prompt: 'Continue')).text, host.response);
      expect(chat.isClosed, isTrue);
    },
  );

  test('closing during session creation waits for native cleanup', () async {
    final delayed = _DelayedHost();
    final model = await LocalAiModel.create(host: delayed);
    final opening = model.openSession();
    final failure = expectLater(opening, throwsStateError);
    final closing = model.close();
    delayed.created.complete();
    await pumpEventQueue();
    expect(delayed.modelClosed, isFalse);
    delayed.cleaned.complete();
    await Future.wait([failure, closing]);
    expect(model.sessions, isEmpty);
    expect(delayed.modelClosed, isTrue);
    await delayed.dispose();
  });
}

class _DelayedHost extends FakeLocalAiHost {
  final created = Completer<void>();
  final cleaned = Completer<void>();
  @override
  Future<void> createSession({
    required int sessionId,
    required double temperature,
    required int topK,
    double? topP,
    int? maxOutputTokens,
    String? systemInstruction,
    List<LocalAiTool>? tools,
  }) => created.future;
  @override
  Future<void> closeSession(int sessionId) => cleaned.future;
}
