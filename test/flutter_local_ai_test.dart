import 'package:flutter_local_ai/flutter_local_ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

void main() {
  late FlutterLocalAiPlatform originalPlatform;
  late FakeFlutterLocalAiPlatform fakePlatform;
  late FlutterLocalAi subject;

  group('FlutterLocalAi', () {
    setUp(() {
      originalPlatform = FlutterLocalAiPlatform.instance;
      fakePlatform = FakeFlutterLocalAiPlatform();
      FlutterLocalAiPlatform.instance = fakePlatform;
      subject = FlutterLocalAi();
    });

    tearDown(() {
      FlutterLocalAiPlatform.instance = originalPlatform;
    });

    test('#isAvailable', () async {
      fakePlatform.isAvailableResult = true;

      final result = await subject.isAvailable();

      expect(result, isTrue);
      expect(fakePlatform.isAvailableCallCount, 1);
    });

    test('#initialize', () async {
      fakePlatform.initializeResult = true;

      final result =
          await subject.initialize(instructions: 'system instructions');

      expect(result, isTrue);
      expect(fakePlatform.lastInstructions, contains('system instructions'));
    });

    test('#registerTools', () async {
      final tools = [
        LocalAiTool(
          name: 'weather',
          description: 'Lookup weather',
          parameters: const [],
          onCall: (_) async => 'clear',
        ),
      ];

      await subject.registerTools(tools);

      expect(fakePlatform.registeredTools, hasLength(1));
      expect(fakePlatform.registeredTools.single.name, contains('weather'));
    });

    test('#generateText', () async {
      fakePlatform.generateTextResult = const AiResponse(
        text: 'hello',
        tokenCount: 11,
        generationTimeMs: 18,
      );

      final config = GenerationConfig(maxTokens: 32);
      final result = await subject.generateText(prompt: 'Hi', config: config);

      expect(result.text, contains('hello'));
      expect(result.tokenCount, isNotNull);
      expect(fakePlatform.lastPrompt, contains('Hi'));
      expect(fakePlatform.lastConfig, same(config));
    });

    test('#generateTextStream', () async {
      fakePlatform.generateTextStreamChunks = const ['hel', 'lo'];

      final config = GenerationConfig(maxTokens: 32);
      final chunks = await subject
          .generateTextStream(prompt: 'Hi', config: config)
          .toList();

      expect(chunks, ['hel', 'lo']);
      expect(fakePlatform.lastPrompt, contains('Hi'));
      expect(fakePlatform.lastConfig, same(config));
    });

    test('one-shot instructions pass through to the platform', () async {
      await subject.generateText(prompt: 'Hi', instructions: 'be terse');
      expect(fakePlatform.lastOneShotInstructions, 'be terse');

      fakePlatform.lastOneShotInstructions = null;
      await subject
          .generateTextStream(prompt: 'Hi', instructions: 'be terse')
          .toList();
      expect(fakePlatform.lastOneShotInstructions, 'be terse');

      // Omitted → null: the platform keeps using its shared session.
      fakePlatform.lastOneShotInstructions = 'stale';
      await subject.generateText(prompt: 'Hi');
      expect(fakePlatform.lastOneShotInstructions, isNull);
    });

    test('#generateTextSimple', () async {
      fakePlatform.generateTextResult =
          const AiResponse(text: 'simple response');

      final result = await subject.generateTextSimple(
        prompt: 'hello',
        maxTokens: 21,
      );

      expect(result, contains('simple response'));
      expect(fakePlatform.lastPrompt, contains('hello'));
      expect(fakePlatform.lastConfig?.maxTokens, 21);
    });

    test('#openAICorePlayStore', () async {
      fakePlatform.openAICorePlayStoreResult = true;

      final result = await subject.openAICorePlayStore();

      expect(result, isTrue);
      expect(fakePlatform.openAICorePlayStoreCallCount, 1);
    });

    test('structured-output config carries the schema to the platform',
        () async {
      fakePlatform.generateTextResult =
          const AiResponse(text: '{"title":"Hello","priority":"high"}');

      final config = GenerationConfig(
        maxTokens: 128,
        responseFormat: ResponseFormat.json,
        schema: const {
          'type': 'object',
          'properties': {
            'title': {'type': 'string'},
            'priority': {
              'enum': ['low', 'med', 'high'],
            },
          },
          'required': ['title'],
        },
      );

      final result = await subject.generateText(prompt: 'Hi', config: config);

      expect(fakePlatform.lastConfig?.schema, isNotNull);
      expect(fakePlatform.lastConfig?.responseFormat, ResponseFormat.json);
      // The JSON arrives in `text`; `.json` is the decoded convenience view.
      expect(result.json, {'title': 'Hello', 'priority': 'high'});
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

      expect(config.toMap(), {
        'maxTokens': 100,
        'responseFormat': 'text',
      });
    });

    test('JSON response format requires a schema', () {
      expect(
        () => GenerationConfig(responseFormat: ResponseFormat.json),
        throwsA(isA<AssertionError>()),
      );
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

  group('LocalAiPlatformInfo', () {
    test('fromMap round-trips supportsStructuredOutput', () {
      final info = LocalAiPlatformInfo.fromMap(const {
        'backend': 'apple_foundation_models',
        'supportsStructuredOutput': true,
      });
      expect(info.supportsStructuredOutput, isTrue);
    });

    test('supportsStructuredOutput defaults to false when absent', () {
      final info = LocalAiPlatformInfo.fromMap(const {
        'backend': 'android_mlkit_genai',
      });
      expect(info.supportsStructuredOutput, isFalse);
    });
  });
}

class FakeFlutterLocalAiPlatform extends FlutterLocalAiPlatform
    with MockPlatformInterfaceMixin {
  bool isAvailableResult = false;
  int isAvailableCallCount = 0;

  bool initializeResult = false;
  String? lastInstructions;

  List<LocalAiTool> registeredTools = const [];

  String? lastPrompt;
  GenerationConfig? lastConfig;
  String? lastOneShotInstructions;
  AiResponse generateTextResult = const AiResponse(text: 'default');
  List<String> generateTextStreamChunks = const [];

  bool openAICorePlayStoreResult = false;
  int openAICorePlayStoreCallCount = 0;

  @override
  Future<bool> isAvailable() async {
    isAvailableCallCount += 1;
    return isAvailableResult;
  }

  @override
  Future<bool> initialize({String? instructions}) async {
    lastInstructions = instructions;
    return initializeResult;
  }

  @override
  Future<void> registerTools(List<LocalAiTool> tools) async {
    registeredTools = tools;
  }

  @override
  Future<AiResponse> generateText({
    required String prompt,
    GenerationConfig? config,
    String? instructions,
  }) async {
    lastPrompt = prompt;
    lastConfig = config;
    lastOneShotInstructions = instructions;
    return generateTextResult;
  }

  @override
  Stream<String> generateTextStream({
    required String prompt,
    GenerationConfig? config,
    String? instructions,
  }) {
    lastPrompt = prompt;
    lastConfig = config;
    lastOneShotInstructions = instructions;
    return Stream.fromIterable(generateTextStreamChunks);
  }

  @override
  Future<bool> openAICorePlayStore() async {
    openAICorePlayStoreCallCount += 1;
    return openAICorePlayStoreResult;
  }
}
