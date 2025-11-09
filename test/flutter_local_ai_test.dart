import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_ai/flutter_local_ai.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AiResponse', () {
    test('should create AiResponse with all fields', () {
      const response = AiResponse(
        text: 'Test response',
        tokenCount: 10,
        generationTimeMs: 100,
      );

      expect(response.text, 'Test response');
      expect(response.tokenCount, 10);
      expect(response.generationTimeMs, 100);
    });

    test('should create AiResponse with only required field', () {
      const response = AiResponse(text: 'Test response');

      expect(response.text, 'Test response');
      expect(response.tokenCount, isNull);
      expect(response.generationTimeMs, isNull);
    });

    test('should create AiResponse from map', () {
      final map = {
        'text': 'Test response',
        'tokenCount': 10,
        'generationTimeMs': 100,
      };

      final response = AiResponse.fromMap(map);

      expect(response.text, 'Test response');
      expect(response.tokenCount, 10);
      expect(response.generationTimeMs, 100);
    });

    test('should create AiResponse from map with null optional fields', () {
      final map = {
        'text': 'Test response',
      };

      final response = AiResponse.fromMap(map);

      expect(response.text, 'Test response');
      expect(response.tokenCount, isNull);
      expect(response.generationTimeMs, isNull);
    });

    test('should convert AiResponse to map', () {
      const response = AiResponse(
        text: 'Test response',
        tokenCount: 10,
        generationTimeMs: 100,
      );

      final map = response.toMap();

      expect(map['text'], 'Test response');
      expect(map['tokenCount'], 10);
      expect(map['generationTimeMs'], 100);
    });

    test('should convert AiResponse to map without null fields', () {
      const response = AiResponse(text: 'Test response');

      final map = response.toMap();

      expect(map['text'], 'Test response');
      expect(map.containsKey('tokenCount'), false);
      expect(map.containsKey('generationTimeMs'), false);
    });
  });

  group('GenerationConfig', () {
    test('should create GenerationConfig with default values', () {
      const config = GenerationConfig();

      expect(config.maxTokens, 100);
      expect(config.temperature, isNull);
      expect(config.topP, isNull);
      expect(config.topK, isNull);
    });

    test('should create GenerationConfig with all fields', () {
      const config = GenerationConfig(
        maxTokens: 200,
        temperature: 0.7,
        topP: 0.9,
        topK: 40,
      );

      expect(config.maxTokens, 200);
      expect(config.temperature, 0.7);
      expect(config.topP, 0.9);
      expect(config.topK, 40);
    });

    test('should convert GenerationConfig to map', () {
      const config = GenerationConfig(
        maxTokens: 200,
        temperature: 0.7,
        topP: 0.9,
        topK: 40,
      );

      final map = config.toMap();

      expect(map['maxTokens'], 200);
      expect(map['temperature'], 0.7);
      expect(map['topP'], 0.9);
      expect(map['topK'], 40);
    });

    test('should convert GenerationConfig to map without null fields', () {
      const config = GenerationConfig(maxTokens: 200);

      final map = config.toMap();

      expect(map['maxTokens'], 200);
      expect(map.containsKey('temperature'), false);
      expect(map.containsKey('topP'), false);
      expect(map.containsKey('topK'), false);
    });
  });

  group('FlutterLocalAi', () {
    const MethodChannel channel = MethodChannel('flutter_local_ai');
    late FlutterLocalAi aiEngine;

    setUp(() {
      aiEngine = FlutterLocalAi();
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMethodCallHandler(channel, null);
    });

    test('isAvailable should return true when available', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'isAvailable') {
          return true;
        }
        return null;
      });

      final result = await aiEngine.isAvailable();

      expect(result, true);
    });

    test('isAvailable should return false when not available', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'isAvailable') {
          return false;
        }
        return null;
      });

      final result = await aiEngine.isAvailable();

      expect(result, false);
    });

    test('isAvailable should return false on exception', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'isAvailable') {
          throw PlatformException(code: 'ERROR', message: 'Test error');
        }
        return null;
      });

      final result = await aiEngine.isAvailable();

      expect(result, false);
    });

    test('generateText should return AiResponse', () async {
      const expectedResponse = {
        'text': 'Generated text',
        'tokenCount': 10,
        'generationTimeMs': 100,
      };

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'generateText') {
          expect(methodCall.arguments['prompt'], 'Test prompt');
          return expectedResponse;
        }
        return null;
      });

      final response = await aiEngine.generateText(prompt: 'Test prompt');

      expect(response.text, 'Generated text');
      expect(response.tokenCount, 10);
      expect(response.generationTimeMs, 100);
    });

    test('generateText should include config in arguments', () async {
      const expectedResponse = {
        'text': 'Generated text',
        'tokenCount': 10,
        'generationTimeMs': 100,
      };

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'generateText') {
          expect(methodCall.arguments['prompt'], 'Test prompt');
          expect(methodCall.arguments['config'], isNotNull);
          final config = methodCall.arguments['config'] as Map;
          expect(config['maxTokens'], 200);
          expect(config['temperature'], 0.7);
          return expectedResponse;
        }
        return null;
      });

      final response = await aiEngine.generateText(
        prompt: 'Test prompt',
        config: const GenerationConfig(
          maxTokens: 200,
          temperature: 0.7,
        ),
      );

      expect(response.text, 'Generated text');
    });

    test('generateText should throw exception on null response', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'generateText') {
          return null;
        }
        return null;
      });

      expect(
        () => aiEngine.generateText(prompt: 'Test prompt'),
        throwsA(isA<Exception>()),
      );
    });

    test('generateText should throw exception on PlatformException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'generateText') {
          throw PlatformException(
            code: 'GENERATION_ERROR',
            message: 'Test error',
          );
        }
        return null;
      });

      expect(
        () => aiEngine.generateText(prompt: 'Test prompt'),
        throwsA(isA<Exception>()),
      );
    });

    test('generateTextSimple should return string', () async {
      const expectedResponse = {
        'text': 'Generated text',
        'tokenCount': 10,
        'generationTimeMs': 100,
      };

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'generateText') {
          expect(methodCall.arguments['prompt'], 'Test prompt');
          return expectedResponse;
        }
        return null;
      });

      final text = await aiEngine.generateTextSimple(
        prompt: 'Test prompt',
        maxTokens: 200,
      );

      expect(text, 'Generated text');
    });

    test('generateTextSimple should use default maxTokens', () async {
      const expectedResponse = {
        'text': 'Generated text',
        'tokenCount': 10,
        'generationTimeMs': 100,
      };

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'generateText') {
          final config = methodCall.arguments['config'] as Map;
          expect(config['maxTokens'], 100); // Default value
          return expectedResponse;
        }
        return null;
      });

      final text = await aiEngine.generateTextSimple(prompt: 'Test prompt');

      expect(text, 'Generated text');
    });
  });
}
