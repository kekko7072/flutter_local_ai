import 'dart:convert';

/// Response from AI generation
class AiResponse {
  /// The generated text
  final String text;

  /// Token count used
  final int? tokenCount;

  /// Generation time in milliseconds
  final int? generationTimeMs;

  const AiResponse({
    required this.text,
    this.tokenCount,
    this.generationTimeMs,
  });

  /// The generated text decoded as a JSON object, or `null` if [text] is not a
  /// JSON object (e.g. free-form text, a root array/scalar, or malformed JSON).
  /// Use this when generation was constrained by an object schema via
  /// `GenerationConfig(responseFormat: ResponseFormat.json, schema: ...)`. For
  /// schemas whose root is an array or scalar, use [decodedJson].
  Map<String, dynamic>? get json {
    final decoded = decodedJson;
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  /// The generated [text] decoded as any JSON value — object, array, string,
  /// number, boolean, or `null` — or `null` if [text] isn't valid JSON. Use
  /// this when a schema's root is an array or scalar; for object roots, [json]
  /// is the typed `Map` convenience view.
  ///
  /// Note: a `null` result is ambiguous between "not valid JSON" and the JSON
  /// literal `null`. Schema-constrained output is rarely a bare null, but check
  /// [text] directly if you must distinguish the two.
  Object? get decodedJson {
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }

  factory AiResponse.fromMap(Map<String, dynamic> map) {
    return AiResponse(
      text: map['text'] as String,
      tokenCount: map['tokenCount'] as int?,
      generationTimeMs: map['generationTimeMs'] as int?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'text': text,
      if (tokenCount != null) 'tokenCount': tokenCount,
      if (generationTimeMs != null) 'generationTimeMs': generationTimeMs,
    };
  }
}
