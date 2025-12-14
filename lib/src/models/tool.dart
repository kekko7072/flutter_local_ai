import 'dart:async';

/// Supported parameter types for a tool definition.
enum ToolArgumentType {
  string,
  integer,
  number,
  boolean,
}

/// Parameter definition sent to the native tool runner.
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

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'type': type.name,
      if (description != null) 'description': description,
      'optional': optional,
    };
  }
}

/// A Dart-defined tool that can be invoked by the native model on Apple platforms.
class LocalAiTool {
  final String name;
  final String description;
  final List<ToolParameter> parameters;
  final FutureOr<dynamic> Function(Map<String, dynamic> arguments) onCall;

  const LocalAiTool({
    required this.name,
    required this.description,
    required this.parameters,
    required this.onCall,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'parameters': parameters.map((p) => p.toMap()).toList(),
    };
  }
}
