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
  AiResponse generateTextResult = const AiResponse(text: 'default');

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
  }) async {
    lastPrompt = prompt;
    lastConfig = config;
    return generateTextResult;
  }

  @override
  Future<bool> openAICorePlayStore() async {
    openAICorePlayStoreCallCount += 1;
    return openAICorePlayStoreResult;
  }
}
