import 'dart:convert';

import '../flutter_local_ai.dart';
import '../models/generation_config.dart';
import 'genui_module_spec.dart';

/// Turns a natural-language goal into a [GenUiModuleSpec] using the on-device
/// model (Apple FoundationModels on iOS/macOS via [FlutterLocalAi]).
///
/// This is the genUI brain: the user types what they want, the local model
/// decides which typed blocks best express it, and the result is rendered by
/// `genui` / the host app. If the model is unavailable or its generation is
/// blocked by the platform, [generateModule] returns null so the caller can
/// fall back to a deterministic composer.
class LocalAiUiGenerator {
  LocalAiUiGenerator([FlutterLocalAi? ai]) : _ai = ai ?? FlutterLocalAi();

  final FlutterLocalAi _ai;
  bool _ready = false;
  bool? _available;
  String? _lastError;

  /// The last platform error encountered (for diagnostics / UI labelling).
  String? get lastError => _lastError;

  /// Whether the on-device model reported itself available (cached).
  bool? get available => _available;

  static const _systemInstructions = '''
You are Fledge's genUI engine. You design a small mobile "module" that helps a
young adult accomplish a goal. You output ONLY a single JSON object — no prose,
no markdown, no code fences.

The JSON shape is:
{
  "title": string,            // short, sentence case
  "icon": string,             // a lucide icon name, e.g. "piggy-bank"
  "tone": "fern"|"apricot"|"sky"|"lilac",
  "blurb": string,            // one short line describing the module
  "blocks": [ ...blocks ]     // 2-4 blocks, ordered, the right tools for the goal
}

Each block is an object with a "type" and type-specific fields:
- {"type":"amount","label":string,"value":number,"prefix":"\$"}
- {"type":"progress","label":string,"value":number,"target":number,"prefix":"\$","tone":"brand","quickAdd":[number,number]}
- {"type":"checklist","label":string,"items":[{"label":string,"meta":string,"done":false}]}
- {"type":"week","label":string,"days":[false,false,false,false,false,false,false]}
- {"type":"stat","label":string,"value":string}   // or "dynamic":"remaining" for budgets
- {"type":"list","label":string,"prefix":"\$","rows":[{"name":string,"amount":number}]}
- {"type":"lessons","label":string,"items":[{"title":string,"mins":number,"read":false}]}
- {"type":"reminder","title":string,"date":"YYYY-MM-DD","time":"HH:MM","location":string,"remind":true}
- {"type":"calc","label":string,"inputs":[{"key":string,"label":string,"value":number,"prefix":"\$"}],"formula":"savingsTimeline"|"tip"|"rentAffordable"|"splitBill"|"takeHome","resultLabel":string}
- {"type":"note","text":string}

Pick blocks that genuinely fit: savings -> amount + progress + calc; an
appointment -> reminder + checklist; a budget -> amount + list + stat(remaining);
a habit -> week + checklist; learning -> lessons. Money is in US dollars (\$).
Keep copy warm, plain and encouraging. Never use emoji.
''';

  /// Ensure the model is available and a genUI session is initialized.
  Future<bool> ensureReady() async {
    if (_ready) return true;
    try {
      _available = await _ai.isAvailable();
      if (_available != true) {
        _lastError = await _ai.availabilityReason();
        return false;
      }
      _ready = await _ai.initialize(instructions: _systemInstructions);
      if (!_ready) _lastError = 'initialize returned false';
      return _ready;
    } catch (e) {
      _lastError = e.toString();
      _ready = false;
      return false;
    }
  }

  /// Generate a module for [goal]. Returns null on any failure.
  Future<GenUiModuleSpec?> generateModule(String goal, {String? principles}) async {
    final clean = goal.trim();
    if (clean.isEmpty) return null;
    if (!await ensureReady()) return null;

    final principleLine = (principles != null && principles.isNotEmpty)
        ? '\nThe user\'s guiding principles: $principles. Respect them.'
        : '';
    final prompt =
        'Design the Fledge module for this goal: "$clean".$principleLine\n'
        'Return ONLY the JSON object.';

    try {
      final res = await _ai.generateText(
        prompt: prompt,
        config: const GenerationConfig(maxTokens: 900, temperature: 0.5),
      );
      final json = _extractJsonObject(res.text);
      if (json == null) {
        _lastError = 'model did not return JSON';
        return null;
      }
      final spec = GenUiModuleSpec.tryParse(json);
      if (spec == null) _lastError = 'model JSON failed validation';
      return spec;
    } catch (e) {
      _lastError = e.toString();
      return null;
    }
  }

  /// Extract the first balanced top-level JSON object from arbitrary text
  /// (handles code fences and leading/trailing prose defensively).
  static Map<String, dynamic>? _extractJsonObject(String text) {
    var s = text.trim();
    // Strip ``` / ```json fences if present.
    s = s.replaceAll(RegExp(r'```[a-zA-Z]*'), '').replaceAll('```', '');
    final start = s.indexOf('{');
    if (start < 0) return null;
    var depth = 0;
    var inString = false;
    var escape = false;
    for (var i = start; i < s.length; i++) {
      final c = s[i];
      if (inString) {
        if (escape) {
          escape = false;
        } else if (c == r'\') {
          escape = true;
        } else if (c == '"') {
          inString = false;
        }
        continue;
      }
      if (c == '"') {
        inString = true;
      } else if (c == '{') {
        depth++;
      } else if (c == '}') {
        depth--;
        if (depth == 0) {
          final candidate = s.substring(start, i + 1);
          try {
            final decoded = jsonDecode(candidate);
            return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
          } catch (_) {
            return null;
          }
        }
      }
    }
    return null;
  }
}
