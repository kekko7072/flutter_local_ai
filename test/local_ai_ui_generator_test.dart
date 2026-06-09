import 'package:flutter_local_ai/flutter_local_ai.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression coverage for [LocalAiUiGenerator.parseModelOutput] — the parser
/// that turns raw on-device model text into a [GenUiModuleSpec]. Small models
/// (e.g. Gemini Nano, capped at 256 output tokens) wrap output in code fences,
/// add prose, emit trailing commas, and get truncated mid-JSON, so the parser
/// must tolerate and where possible repair all of those.
void main() {
  group('LocalAiUiGenerator.parseModelOutput', () {
    test('parses a clean JSON object', () {
      const raw =
          '{"title":"Weekend trip fund","icon":"piggy-bank","tone":"sky",'
          '"blurb":"Save up.","blocks":[{"type":"amount","label":"Goal",'
          '"value":500,"prefix":"\$"}]}';

      final spec = LocalAiUiGenerator.parseModelOutput(raw);

      expect(spec, isNotNull);
      expect(spec!.title, 'Weekend trip fund');
      expect(spec.icon, 'piggy-bank');
      expect(spec.tone, 'sky');
      expect(spec.blocks, hasLength(1));
      expect(spec.blocks.first['type'], 'amount');
    });

    test('strips ```json code fences and surrounding prose', () {
      const raw = 'Sure! Here is the module:\n```json\n'
          '{"title":"Budget","tone":"fern","blocks":'
          '[{"type":"stat","label":"Remaining","value":"\$100"}]}'
          '\n```\nHope that helps.';

      final spec = LocalAiUiGenerator.parseModelOutput(raw);

      expect(spec, isNotNull);
      expect(spec!.title, 'Budget');
      expect(spec.blocks.single['type'], 'stat');
    });

    test('tolerates trailing commas', () {
      const raw = '{"title":"Habit","tone":"lilac","blocks":['
          '{"type":"week","label":"This week","days":[false,false,false],},'
          '],}';

      final spec = LocalAiUiGenerator.parseModelOutput(raw);

      expect(spec, isNotNull);
      expect(spec!.title, 'Habit');
      expect(spec.blocks.single['type'], 'week');
    });

    test('repairs JSON truncated by the output cap', () {
      // Output cut off mid-way through the second block: the object never
      // closes, but the first block is complete and should be salvaged.
      const raw = '{"title":"Reading habit","icon":"book","tone":"fern",'
          '"blurb":"Read daily.","blocks":['
          '{"type":"lessons","label":"This week","items":['
          '{"title":"Chapter 1","mins":20,"read":false}]},'
          '{"type":"checklist","label":"Today","items":[{"label":"Read for 10';

      final spec = LocalAiUiGenerator.parseModelOutput(raw);

      expect(spec, isNotNull, reason: 'truncated output should be repaired');
      expect(spec!.title, 'Reading habit');
      // Only the complete first block survives the repair.
      expect(spec.blocks, hasLength(1));
      expect(spec.blocks.single['type'], 'lessons');
    });

    test('returns null when there is no JSON object at all', () {
      expect(
        LocalAiUiGenerator.parseModelOutput('I cannot help with that.'),
        isNull,
      );
    });

    test('returns null when no valid block is present', () {
      // Valid JSON, but the only block has an unknown type → not a real module.
      const raw = '{"title":"Nope","blocks":[{"type":"bogus","x":1}]}';
      expect(LocalAiUiGenerator.parseModelOutput(raw), isNull);
    });
  });
}
