import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_ai/flutter_local_ai.dart';

void main() {
  group('GenerationConfig', () {
    test('default values', () {
      const config = GenerationConfig();

      expect(config.maxTokens, 100);
      expect(config.temperature, isNull);
      expect(config.topP, isNull);
      expect(config.topK, isNull);
    });

    test('custom values', () {
      const config = GenerationConfig(
        maxTokens: 500,
        temperature: 0.8,
        topP: 0.95,
        topK: 50,
      );

      expect(config.maxTokens, 500);
      expect(config.temperature, 0.8);
      expect(config.topP, 0.95);
      expect(config.topK, 50);
    });

    test('toMap includes all non-null values', () {
      const config = GenerationConfig(
        maxTokens: 300,
        temperature: 0.6,
      );

      final map = config.toMap();

      expect(map['maxTokens'], 300);
      expect(map['temperature'], 0.6);
      expect(map.containsKey('topP'), false);
      expect(map.containsKey('topK'), false);
    });
  });
}
