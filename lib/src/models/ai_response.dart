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
