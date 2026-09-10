import 'dart:typed_data';

import 'package:flutter_gemma/core/domain/model_source.dart';
import 'package:flutter_gemma/core/message.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/core/model_management/model_specs.dart'
    show InferenceModelSpec;
import 'package:flutter_gemma/core/registry/runtime_config.dart';
import 'package:flutter_gemma_local_ai/flutter_gemma_local_ai.dart';
import 'package:flutter_local_ai/flutter_local_ai.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_local_ai_host.dart';

InferenceModelSpec _spec({ModelFileType fileType = ModelFileType.builtIn}) =>
    InferenceModelSpec(
      name: 'gemini-nano',
      modelSource: ModelSource.bundled('gemini-nano'),
      modelType: ModelType.general,
      fileType: fileType,
    );

const _config = RuntimeConfig(maxTokens: 4096, modelPath: '');

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

  group('engine selection', () {
    test('claims builtIn specs and nothing else', () {
      const engine = LocalAiEngine();

      expect(engine.canHandle(_spec()), isTrue);
      for (final other in [
        ModelFileType.task,
        ModelFileType.binary,
        ModelFileType.litertlm,
        ModelFileType.onnx,
      ]) {
        expect(engine.canHandle(_spec(fileType: other)), isFalse,
            reason: '$other belongs to another engine');
      }
    });

    test('reserves the builtIn Hugging Face slot with a clear error',
        () async {
      const resolver = LocalAiHuggingFaceResolver();

      expect(resolver.canResolve('any/repo', fileType: ModelFileType.builtIn),
          isTrue);
      expect(resolver.canResolve('any/repo', fileType: ModelFileType.task),
          isFalse);
      await expectLater(
        resolver.resolve('any/repo'),
        throwsUnsupportedError,
      );
    });
  });

  group('createModel', () {
    test('refuses to build a model the OS is not ready to run', () async {
      host.availability = LocalAiAvailability.unavailableDisabled;

      await expectLater(
        const LocalAiEngine().createModel(_spec(), _config),
        throwsA(isA<LocalAiUnavailableException>().having(
          (e) => e.status,
          'status',
          LocalAiAvailability.unavailableDisabled,
        )),
      );
      expect(host.calls, isNot(contains('createModel')));
    });

    test('builds a model carrying the runtime config', () async {
      final model = await const LocalAiEngine().createModel(_spec(), _config);

      expect(model, isA<LocalAiGemmaModel>());
      expect(model.maxTokens, 4096);
      expect(model.fileType, ModelFileType.builtIn);
      // The OS picks its own accelerator and doesn't report it.
      expect(model.activeBackend, isNull);
    });
  });

  group('session lanes', () {
    Future<LocalAiGemmaModel> newModel() async =>
        await const LocalAiEngine().createModel(_spec(), _config)
            as LocalAiGemmaModel;

    test('createSession replaces and closes the previous singleton',
        () async {
      final model = await newModel();

      final first = await model.createSession();
      final second = await model.createSession();

      expect(host.closedSessions, [1]);
      expect(model.session, same(second));
      expect(model.sessions, [second]);
      expect(first, isNot(same(second)));
    });

    test('openSession leaves the singleton lane alone', () async {
      final model = await newModel();

      final singleton = await model.createSession();
      final detached = await model.openSession();

      expect(model.session, same(singleton));
      expect(model.sessions, containsAll([singleton, detached]));
      expect(host.closedSessions, isEmpty);
    });

    test('closing an open session removes it from sessions', () async {
      final model = await newModel();
      final detached = await model.openSession();

      await detached.close();

      expect(model.sessions, isNot(contains(detached)));
    });

    test('audio is rejected rather than silently dropped', () async {
      final model = await newModel();

      expect(
        () => model.createSession(enableAudioModality: true),
        throwsUnsupportedError,
      );
    });

    test('systemInstruction and maxOutputTokens reach the host', () async {
      final model = await newModel();

      await model.createSession(
        systemInstruction: 'Be terse.',
        maxOutputTokens: 128,
        temperature: 0.3,
      );

      expect(host.createdSessions.single['systemInstruction'], 'Be terse.');
      expect(host.createdSessions.single['maxOutputTokens'], 128);
      expect(host.createdSessions.single['temperature'], 0.3);
    });

    test('flutter_gemma tools are not handed to the native tool runner',
        () async {
      final model = await newModel();

      // InferenceChat owns function calling for this engine: it weaves the
      // declarations into the prompt and parses the calls back out. Passing
      // them natively too would run two tool loops for one turn.
      await model.createSession(tools: const []);

      expect(host.createdSessions.single['tools'], isNull);
    });
  });

  group('message adaptation', () {
    test('a text message reaches the host transcript', () async {
      final model = await const LocalAiEngine().createModel(_spec(), _config)
          as LocalAiGemmaModel;
      final session = await model.createSession() as LocalAiGemmaSession;

      await session.addQueryChunk(
        const Message(text: 'Hello!', isUser: true),
      );

      expect(
        host.transcripts[session.localAiSession.sessionId].toString(),
        contains('Hello!'),
      );
    });

    test('images are sent before the text that refers to them', () async {
      final model = await const LocalAiEngine().createModel(
        _spec(),
        const RuntimeConfig(
          maxTokens: 4096,
          modelPath: '',
          supportImage: true,
        ),
      ) as LocalAiGemmaModel;
      final session = await model.createSession() as LocalAiGemmaSession;
      final bytes = Uint8List.fromList([9, 9, 9]);

      await session.addQueryChunk(
        Message.withImage(
          text: 'What is this?',
          imageBytes: bytes,
          isUser: true,
        ),
      );

      final id = session.localAiSession.sessionId;
      expect(host.images[id], [bytes]);
      expect(host.transcripts[id].toString(), contains('What is this?'));
    });

    test('metrics are empty rather than invented', () async {
      final model = await const LocalAiEngine().createModel(_spec(), _config)
          as LocalAiGemmaModel;
      final session = await model.createSession();

      final metrics = session.getSessionMetrics();
      expect(metrics.totalTokens, 0);
      expect(metrics.tokensPerSecond, isNull);
    });
  });

  group('specs', () {
    test('every built-in spec is a builtIn file type', () {
      for (final spec in LocalAiModels.all) {
        expect(spec.fileType, ModelFileType.builtIn);
        expect(const LocalAiEngine().canHandle(spec), isTrue);
      }
    });

    test('migration aliases point at the same specs', () {
      expect(BuiltInAiModels.geminiNano.name, LocalAiModels.geminiNano.name);
      expect(
        BuiltInAiModels.appleFoundationModels.name,
        LocalAiModels.appleFoundationModels.name,
      );
    });
  });
}
