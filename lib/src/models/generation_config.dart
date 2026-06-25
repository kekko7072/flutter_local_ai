import 'schema_validation.dart';

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
  /// [ResponseFormat.json] requires a non-null [schema]. Supplying a [schema]
  /// implies JSON mode regardless of this field — see [effectiveResponseFormat].
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

  /// Whether this config asks for schema-constrained JSON output. True when a
  /// [schema] is supplied (which implies JSON mode) or [responseFormat] is
  /// [ResponseFormat.json]. Backends that report `supportsStructuredOutput:
  /// false` reject such requests.
  bool get requestsStructuredOutput =>
      schema != null || responseFormat == ResponseFormat.json;

  /// The format actually sent to the backend: supplying a [schema] implies
  /// [ResponseFormat.json], so the wire format never disagrees with the
  /// presence of a schema (Apple keys structured output off the schema alone).
  ResponseFormat get effectiveResponseFormat =>
      schema != null ? ResponseFormat.json : responseFormat;

  /// Validates [schema] against the JSON Schema subset the native backends can
  /// translate, throwing an [ArgumentError] if it uses unsupported constructs.
  /// A no-op when no schema is set. Call ahead of generation to fail fast in
  /// Dart instead of with an opaque native error.
  void validateSchema() {
    final schema = this.schema;
    if (schema != null) validateGenerationSchema(schema);
  }

  Map<String, dynamic> toMap() {
    return {
      'maxTokens': maxTokens,
      if (temperature != null) 'temperature': temperature,
      if (topP != null) 'topP': topP,
      if (topK != null) 'topK': topK,
      'responseFormat': effectiveResponseFormat.name,
      if (schema != null) 'schema': schema,
    };
  }
}
