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
  /// JSON object (e.g. free-form text, or malformed/truncated JSON). Use this
  /// when generation was constrained by a schema via
  /// `GenerationConfig(responseFormat: ResponseFormat.json, schema: ...)`.
  Map<String, dynamic>? get json {
    try {
      final decoded = jsonDecode(text);
      return decoded is Map<String, dynamic> ? decoded : null;
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
