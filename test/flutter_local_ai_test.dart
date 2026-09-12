import 'package:flutter_local_ai/flutter_local_ai.dart';
import 'package:flutter_local_ai/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeLocalAiHost host;
  late FlutterLocalAi subject;

  setUp(() async {
    host = FakeLocalAiHost();
    debugLocalAiHost = host;
    await FlutterLocalAi.debugReset();
    subject = FlutterLocalAi(host: host);
  });

  tearDown(() async {
    await FlutterLocalAi.debugReset();
    debugLocalAiHost = null;
    await host.dispose();
  });

  group('FlutterLocalAi', () {
    test('isAvailable is true only when the model is ready now', () async {
      expect(await subject.isAvailable(), isTrue);

      host.availability = LocalAiAvailability.downloadable;
      expect(await subject.isAvailable(), isFalse);
    });

    test('isAvailable never throws', () async {
      debugLocalAiHost = _ThrowingHost(host);
      expect(await FlutterLocalAi().isAvailable(), isFalse);
    });

    test('initialize starts a session carrying the instructions', () async {
      await subject.initialize(instructions: 'Be terse.');

      expect(host.sessions.single.systemInstruction, 'Be terse.');
    });

    test('initialize again replaces the conversation', () async {
      await subject.initialize(instructions: 'First.');
      await subject.initialize(instructions: 'Second.');

      expect(host.sessions, hasLength(2));
      expect(host.closedIds, [1]);
      expect(host.sessions.last.systemInstruction, 'Second.');
    });

    test(
      'generateText creates a session on its own without initialize',
      () async {
        host.response = 'hello';

        final response = await subject.generateText(prompt: 'hi');

        expect(response.text, 'hello');
        expect(host.sessions, hasLength(1));
      },
    );

    test('successive calls share one conversation', () async {
      await subject.generateText(prompt: 'first');
      await subject.generateText(prompt: 'second');

      // One session, both turns on it — the same on every platform now.
      expect(host.sessions, hasLength(1));
      expect(host.sessions.single.transcript.toString(), 'firstsecond');
    });

    test('one-shot instructions run in a throwaway session', () async {
      await subject.generateText(
        prompt: 'hi',
        instructions: 'Answer in French.',
      );

      expect(host.sessions.single.systemInstruction, 'Answer in French.');
      // The throwaway must not outlive the call, or the OS keeps a context
      // alive for a conversation nobody will continue.
      expect(host.closedIds, [1]);
    });

    test('a one-shot call leaves the shared conversation untouched', () async {
      await subject.initialize(instructions: 'Shared.');
      await subject.generateText(prompt: 'aside', instructions: 'One-shot.');
      await subject.generateText(prompt: 'later');

      // Session 1 is the shared one and is still open; session 2 was the
      // throwaway.
      expect(host.closedIds, [2]);
      expect(host.session(1)!.transcript.toString(), 'later');
    });

    test('a GenerationConfig reaches the host as per-call sampling', () async {
      await subject.generateText(
        prompt: 'hi',
        config: const GenerationConfig(maxTokens: 64, temperature: 0.2),
      );

      expect(host.lastOverrides?.maxOutputTokens, 64);
      expect(host.lastOverrides?.temperature, 0.2);
      // Sampling is per call, so the shared session keeps its own settings.
      expect(host.sessions.single.maxOutputTokens, isNull);
    });

    test('generateText reports timing and a token count', () async {
      host.response = 'some words';
      host.countTokensResult = 3;

      final response = await subject.generateText(prompt: 'hi');

      expect(response.tokenCount, 3);
      expect(response.generationTimeMs, isNotNull);
    });

    test(
      'a failed token count does not fail a successful generation',
      () async {
        host.response = 'fine';
        host.countTokensError = StateError('tokenizer exploded');

        final response = await subject.generateText(prompt: 'hi');

        expect(response.text, 'fine');
        expect(response.tokenCount, isNull);
      },
    );

    test('a schema is validated before any platform call', () async {
      await expectLater(
        subject.generateText(
          prompt: 'hi',
          config: const GenerationConfig(schema: {'type': 'date'}),
        ),
        throwsArgumentError,
      );
      expect(host.calls, isNot(contains('generateStructuredResponse')));
    });

    test('a valid schema routes to constrained generation', () async {
      await subject.generateText(
        prompt: 'hi',
        config: const GenerationConfig(
          schema: {
            'type': 'object',
            'properties': {
              'city': {'type': 'string'},
            },
          },
        ),
      );

      expect(host.calls, contains('generateStructuredResponse'));
    });

    test('generateTextStream emits deltas', () async {
      final chunks = <String>[];
      final done = subject
          .generateTextStream(prompt: 'hi')
          .listen(chunks.add)
          .asFuture<void>();
      await pumpEventQueue();

      host.emitToken(1, 'a');
      host.emitDone(1, text: 'b');
      await done;

      expect(chunks, ['a', 'b']);
    });

    test('generateTextStream closes its one-shot session', () async {
      final done = subject
          .generateTextStream(prompt: 'hi', instructions: 'One-shot.')
          .listen((_) {})
          .asFuture<void>();
      await pumpEventQueue();

      host.emitDone(1);
      await done;

      expect(host.closedIds, [1]);
    });

    test('generateTextStream rejects structured-output requests', () async {
      await expectLater(
        subject.generateTextStream(
          prompt: 'hi',
          config: const GenerationConfig(schema: {'type': 'object'}),
        ),
        emitsError(isA<ArgumentError>()),
      );
    });

    test('generateTextSimple returns just the text', () async {
      host.response = 'short';
      expect(await subject.generateTextSimple(prompt: 'hi'), 'short');
    });

    test('registerTools restarts the conversation so tools bind', () async {
      await subject.initialize();
      await subject.registerTools([
        LocalAiTool(
          name: 'weather',
          description: 'Current weather',
          parameters: const [ToolParameter(name: 'city')],
          onCall: (_) async => 'sunny',
        ),
      ]);

      // Apple binds tools when a session is constructed and cannot add them
      // to a live one, so the old session has to go.
      expect(host.closedIds, [1]);
      expect(host.sessions.last.toolNames, ['weather']);
    });

    test('registering an empty list stops offering tools', () async {
      await subject.registerTools([]);
      await subject.generateText(prompt: 'hi');

      expect(host.sessions.single.toolNames, isEmpty);
    });

    test('getPlatformInfo narrows the host capabilities', () async {
      host.capabilities = const LocalAiBackendCapabilities(
        backend: LocalAiBackendKind.appleFoundationModels,
        platform: 'ios',
        apiName: 'Apple Foundation Models',
        supportsToolCalling: true,
        supportsStructuredOutput: true,
      );

      final info = await subject.getPlatformInfo();

      expect(info.backend, LocalAiBackend.appleFoundationModels);
      expect(info.supportsToolCalling, isTrue);
      expect(info.supportsStructuredOutput, isTrue);
    });

    test('getPlatformInfo degrades instead of throwing', () async {
      debugLocalAiHost = _ThrowingHost(host);
      final info = await FlutterLocalAi().getPlatformInfo();
      expect(info.backend, LocalAiBackend.unsupported);
    });

    test('getModelStatus maps availability', () async {
      host.availability = LocalAiAvailability.downloading;
      expect(await subject.getModelStatus(), ModelFeatureStatus.downloading);

      host.availability = LocalAiAvailability.unavailableDisabled;
      expect(await subject.getModelStatus(), ModelFeatureStatus.unavailable);
    });

    test('downloadModel always terminates, even on failure', () async {
      host.availability = LocalAiAvailability.unavailableDeviceUnsupported;

      final statuses = await subject.downloadModel().toList();

      expect(statuses.first.type, ModelDownloadStatusType.started);
      expect(statuses.last.type, ModelDownloadStatusType.failed);
    });

    test('downloadModel reports progress then completion', () async {
      host.availability = LocalAiAvailability.downloadable;
      final statuses = <ModelDownloadStatus>[];
      final done = subject
          .downloadModel()
          .listen(statuses.add)
          .asFuture<void>();
      await pumpEventQueue();

      host.emitDownloadProgress(1024);
      await pumpEventQueue();
      host.availability = LocalAiAvailability.available;
      await done;

      expect(statuses.map((s) => s.type), [
        ModelDownloadStatusType.started,
        ModelDownloadStatusType.progress,
        ModelDownloadStatusType.completed,
      ]);
      expect(statuses[1].totalBytesDownloaded, 1024);
    });

    test('openAICorePlayStore is false where there is no Play Store', () async {
      expect(await subject.openAICorePlayStore(), isFalse);
    });
  });

  group('GenerationConfig', () {
    test('toMap includes sampling knobs, response format, and schema', () {
      const config = GenerationConfig(
        maxTokens: 300,
        temperature: 0.7,
        topP: 0.9,
        topK: 40,
        responseFormat: ResponseFormat.json,
        schema: {'type': 'object'},
      );

      expect(config.toMap(), {
        'maxTokens': 300,
        'temperature': 0.7,
        'topP': 0.9,
        'topK': 40,
        'responseFormat': 'json',
        'schema': {'type': 'object'},
      });
    });

    test('toMap omits null knobs and defaults to text format', () {
      const config = GenerationConfig(maxTokens: 100);

      expect(config.toMap(), {'maxTokens': 100, 'responseFormat': 'text'});
    });

    test(
      'a schema implies JSON mode even when responseFormat is left text',
      () {
        const config = GenerationConfig(
          maxTokens: 100,
          schema: {'type': 'object'},
        );

        // The field still reflects what the caller passed...
        expect(config.responseFormat, ResponseFormat.text);
        // ...but the effective/wire format is promoted to json so the backend
        // never sees a schema paired with a 'text' format.
        expect(config.effectiveResponseFormat, ResponseFormat.json);
        expect(config.requestsStructuredOutput, isTrue);
        expect(config.toMap()['responseFormat'], 'json');
      },
    );

    test('requestsStructuredOutput is false for plain text generation', () {
      const config = GenerationConfig(maxTokens: 100);
      expect(config.requestsStructuredOutput, isFalse);
      expect(config.effectiveResponseFormat, ResponseFormat.text);
    });

    test('JSON response format requires a schema', () {
      expect(
        () => GenerationConfig(responseFormat: ResponseFormat.json),
        throwsA(isA<AssertionError>()),
      );
    });

    test('validateSchema is a no-op without a schema', () {
      const config = GenerationConfig(maxTokens: 100);
      expect(config.validateSchema, returnsNormally);
    });

    test('validateSchema rejects an unsupported schema construct', () {
      const config = GenerationConfig(
        schema: {
          'type': 'object',
          'properties': {
            'when': {'type': 'date'}, // unsupported scalar
          },
        },
      );
      expect(config.validateSchema, throwsArgumentError);
    });
  });

  group('AiResponse.json', () {
    test('decodes a JSON object payload', () {
      const response = AiResponse(text: '{"a":1,"b":"two"}');
      expect(response.json, {'a': 1, 'b': 'two'});
    });

    test('returns null for free-form text', () {
      const response = AiResponse(text: 'just words');
      expect(response.json, isNull);
    });

    test('returns null for non-object JSON (e.g. an array)', () {
      const response = AiResponse(text: '[1, 2, 3]');
      expect(response.json, isNull);
    });
  });

  group('AiResponse.decodedJson', () {
    test('decodes a root object', () {
      const response = AiResponse(text: '{"a":1}');
      expect(response.decodedJson, {'a': 1});
    });

    test('decodes a root array (where .json returns null)', () {
      const response = AiResponse(text: '[1, 2, 3]');
      expect(response.json, isNull);
      expect(response.decodedJson, [1, 2, 3]);
    });

    test('decodes a root scalar', () {
      const response = AiResponse(text: '42');
      expect(response.decodedJson, 42);
    });

    test('returns null for free-form text', () {
      const response = AiResponse(text: 'just words');
      expect(response.decodedJson, isNull);
    });
  });

  group('LocalAiPlatformInfo', () {
    test('carries structured-output support across from capabilities', () {
      final info = LocalAiPlatformInfo.fromCapabilities(
        const LocalAiBackendCapabilities(
          backend: LocalAiBackendKind.appleFoundationModels,
          platform: 'ios',
          apiName: 'Apple Foundation Models',
          supportsStructuredOutput: true,
        ),
      );
      expect(info.supportsStructuredOutput, isTrue);
      expect(info.backend, LocalAiBackend.appleFoundationModels);
    });

    test('defaults to unsupported where the capability is absent', () {
      final info = LocalAiPlatformInfo.fromCapabilities(
        const LocalAiBackendCapabilities(
          backend: LocalAiBackendKind.androidMlKitGenAi,
          platform: 'android',
          apiName: 'ML Kit GenAI',
        ),
      );
      expect(info.supportsStructuredOutput, isFalse);
      expect(info.backend, LocalAiBackend.androidMlKitGenAi);
    });

    test('maps the web backend, which predates this enum', () {
      final info = LocalAiPlatformInfo.fromCapabilities(
        const LocalAiBackendCapabilities(
          backend: LocalAiBackendKind.chromePromptApi,
          platform: 'web',
          apiName: 'Chrome Prompt API',
        ),
      );
      expect(info.backend, LocalAiBackend.chromePromptApi);
    });
  });
}

/// A host whose every call throws, for the paths documented as degrading
/// rather than propagating.
class _ThrowingHost implements LocalAiHost {
  _ThrowingHost(this.inner);

  final LocalAiHost inner;

  @override
  Stream<LocalAiHostEvent> get events => inner.events;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Future<Never>.error(StateError('host is broken'));
}
