/// Desired shape of the generated output.
enum ResponseFormat {
  /// Free-form text (the default).
  text,

  /// Schema-constrained JSON. Requires [GenerationConfig.schema] and is only
  /// honored on backends that report `supportsStructuredOutput` (Apple
  /// FoundationModels). Other backends throw when JSON output is requested.
  json,
}

/// Configuration for text generation
class GenerationConfig {
  /// Maximum number of tokens to generate
  final int maxTokens;

  /// Temperature for generation (0.0 to 1.0)
  final double? temperature;

  /// Nucleus sampling probability threshold (top-p). On Apple this selects the
  /// `.random(probabilityThreshold:)` sampling mode.
  final double? topP;

  /// Top-K sampling parameter. On Apple this selects the `.random(top:)`
  /// sampling mode and takes precedence over [topP].
  final int? topK;

  /// Desired output format. Defaults to [ResponseFormat.text]. Selecting
  /// [ResponseFormat.json] requires a non-null [schema].
  final ResponseFormat responseFormat;

  /// JSON Schema describing the structured output. When provided (with
  /// [responseFormat] == [ResponseFormat.json]), the model is constrained to
  /// emit JSON matching this schema. Only supported on Apple FoundationModels;
  /// see `LocalAiPlatformInfo.supportsStructuredOutput`.
  final Map<String, dynamic>? schema;

  const GenerationConfig({
    this.maxTokens = 100,
    this.temperature,
    this.topP,
    this.topK,
    this.responseFormat = ResponseFormat.text,
    this.schema,
  }) : assert(
          responseFormat == ResponseFormat.text || schema != null,
          'ResponseFormat.json requires a non-null schema.',
        );

  Map<String, dynamic> toMap() {
    return {
      'maxTokens': maxTokens,
      if (temperature != null) 'temperature': temperature,
      if (topP != null) 'topP': topP,
      if (topK != null) 'topK': topK,
      'responseFormat': responseFormat.name,
      if (schema != null) 'schema': schema,
    };
  }
}
