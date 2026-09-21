import 'dart:async';

import 'schema_validation.dart';

/// Supported parameter types for a flat [ToolParameter].
enum ToolArgumentType { string, integer, number, boolean }

/// One scalar parameter of a tool.
///
/// Shorthand for the common case. A declaration that needs a nested object,
/// a list, or a string enum builds its own JSON Schema and passes it as
/// [LocalAiTool.parameterSchema] instead — the constraint survives the trip
/// to the model either way, because both spellings become the same schema.
class ToolParameter {
  final String name;
  final ToolArgumentType type;
  final String? description;
  final bool optional;

  const ToolParameter({
    required this.name,
    this.type = ToolArgumentType.string,
    this.description,
    this.optional = false,
  });

  /// This parameter as a JSON Schema node. [optional] is not part of the node
  /// — JSON Schema states it on the enclosing object's `required` list, which
  /// [LocalAiTool.resolvedParameterSchema] assembles.
  Map<String, dynamic> toSchema() => {
    'type': type.name,
    if (description != null) 'description': description,
  };

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'type': type.name,
      if (description != null) 'description': description,
      'optional': optional,
    };
  }
}

/// Thrown from a tool body to tell the *model* that the call did not succeed.
///
/// A tool that refuses, times out, or is declined by the user is a normal
/// outcome of an agent loop, not a failure of the turn. Throwing this (or any
/// other exception — see [LocalAiTool.onCall]) hands the model a readable
/// error result it can answer, retry or work around, instead of aborting
/// generation.
class LocalAiToolException implements Exception {
  const LocalAiToolException(this.message, {this.details});

  /// What the model is told went wrong. Write it for the model to read.
  final String message;

  /// Optional extra JSON-serializable context, passed through alongside
  /// [message].
  final Object? details;

  @override
  String toString() => 'LocalAiToolException: $message';
}

/// A Dart-defined tool that can be invoked by the native model on Apple
/// platforms.
///
/// Declare parameters either as flat [parameters] or as a full JSON Schema in
/// [parameterSchema]; supply one or the other, never both.
///
/// ## The [onCall] contract
///
/// - **It may take as long as it needs.** The native host suspends the turn
///   for the whole of [onCall] and imposes no timeout of its own, so waiting
///   on a human to approve an action is a supported use.
/// - **`stopGeneration()` unwinds it.** Stopping while a tool call is
///   suspended cancels the turn without waiting for [onCall] to return. The
///   `Future` is simply abandoned — nothing cancels the Dart work itself, so a
///   tool that holds a resource should release it on its own.
/// - **Throwing is an answer, not a crash.** Any exception out of [onCall] —
///   [LocalAiToolException] or otherwise — is encoded as a tool *error result*
///   the model reads and can respond to. The turn continues. A tool body's
///   exception therefore never fails the generation, which also means a
///   genuine bug in a tool body is reported to the model rather than thrown to
///   the app: throw [LocalAiToolException] deliberately, and let anything else
///   be the exception it is.
class LocalAiTool {
  final String name;
  final String description;

  /// Flat scalar parameters. Empty when [parameterSchema] carries the
  /// declaration instead.
  final List<ToolParameter> parameters;

  /// The tool's parameters as a JSON Schema object, for declarations the flat
  /// [parameters] list cannot express: nested objects, arrays, and string
  /// enums.
  ///
  /// The same subset `GenerationConfig.schema` accepts, validated by
  /// [validateGenerationSchema] and translated by the same native builder, so
  /// on Apple the model is *constrained* to the declaration rather than asked
  /// to respect it.
  final Map<String, dynamic>? parameterSchema;

  final FutureOr<dynamic> Function(Map<String, dynamic> arguments) onCall;

  const LocalAiTool({
    required this.name,
    required this.description,
    this.parameters = const [],
    this.parameterSchema,
    required this.onCall,
  });

  /// The declaration actually sent to the host: [parameterSchema] when set,
  /// otherwise the object schema the flat [parameters] describe.
  ///
  /// A tool with neither yields the empty object schema, which is how a
  /// zero-argument tool is spelled.
  Map<String, dynamic> get resolvedParameterSchema {
    final schema = parameterSchema;
    if (schema != null) return schema;
    return {
      'type': 'object',
      'properties': {
        for (final parameter in parameters)
          parameter.name: parameter.toSchema(),
      },
      'required': [
        for (final parameter in parameters)
          if (!parameter.optional) parameter.name,
      ],
    };
  }

  /// Validates the declaration against the subset the native backends can
  /// translate, throwing an [ArgumentError] otherwise. A flat declaration
  /// always passes; a hand-written [parameterSchema] fails here, with a
  /// path-qualified message, rather than opaquely inside the native session.
  ///
  /// Checked here rather than in an `assert` on the constructor because a
  /// const constructor cannot assert about a list's contents, and because a
  /// schema is worth validating in release builds too.
  void validateParameterSchema() {
    final schema = parameterSchema;
    if (schema == null) return;
    if (parameters.isNotEmpty) {
      throw ArgumentError.value(
        name,
        'parameterSchema',
        'Tool "$name" declares both a flat `parameters` list and a '
            '`parameterSchema`. Use one or the other.',
      );
    }
    final type = schema['type'];
    if (type != null && (type is! String || type.toLowerCase() != 'object')) {
      throw ArgumentError.value(
        type,
        'parameterSchema',
        'A tool\'s `parameterSchema` must be an object schema; tool '
            '"$name" declares `$type`.',
      );
    }
    validateGenerationSchema(schema);
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'parameters': resolvedParameterSchema,
    };
  }
}
