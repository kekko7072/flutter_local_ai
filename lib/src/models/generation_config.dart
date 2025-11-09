/// Configuration for text generation
class GenerationConfig {
  /// Maximum number of tokens to generate
  final int maxTokens;

  /// Temperature for generation (0.0 to 1.0)
  final double? temperature;

  /// Top-p sampling parameter
  final double? topP;

  /// Top-k sampling parameter
  final int? topK;

  const GenerationConfig({
    this.maxTokens = 100,
    this.temperature,
    this.topP,
    this.topK,
  });

  Map<String, dynamic> toMap() {
    return {
      'maxTokens': maxTokens,
      if (temperature != null) 'temperature': temperature,
      if (topP != null) 'topP': topP,
      if (topK != null) 'topK': topK,
    };
  }
}
