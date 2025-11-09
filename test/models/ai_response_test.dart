import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_ai/flutter_local_ai.dart';

void main() {
  group('AiResponse', () {
    test('equality', () {
      const response1 = AiResponse(
        text: 'Test',
        tokenCount: 10,
        generationTimeMs: 100,
      );
      const response2 = AiResponse(
        text: 'Test',
        tokenCount: 10,
        generationTimeMs: 100,
      );
      const response3 = AiResponse(
        text: 'Different',
        tokenCount: 10,
        generationTimeMs: 100,
      );

      expect(response1.text == response2.text, true);
      expect(response1.text == response3.text, false);
    });

    test('fromMap handles missing optional fields', () {
      final map = <String, dynamic>{
        'text': 'Test response',
      };

      final response = AiResponse.fromMap(map);

      expect(response.text, 'Test response');
      expect(response.tokenCount, isNull);
      expect(response.generationTimeMs, isNull);
    });

    test('toMap excludes null fields', () {
      const response = AiResponse(text: 'Test response');

      final map = response.toMap();

      expect(map.length, 1);
      expect(map['text'], 'Test response');
      expect(map.containsKey('tokenCount'), false);
      expect(map.containsKey('generationTimeMs'), false);
    });
  });
}
