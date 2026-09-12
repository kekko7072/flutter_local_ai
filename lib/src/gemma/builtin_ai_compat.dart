/// Source-compatible aliases for apps migrating from
/// `flutter_gemma_builtin_ai`.
///
/// Same names, same semantics, so a migration is a changed import and
/// nothing else. New code should use the `LocalAi*` names directly — these
/// exist to make the switch a non-event, not as a second API to maintain.
library;

import 'package:flutter_gemma/core/model_management/model_specs.dart'
    show InferenceModelSpec;
import 'package:flutter_local_ai/flutter_local_ai.dart';

import 'local_ai_engine.dart';
import 'local_ai_models.dart';
import 'local_ai_hugging_face_resolver.dart';

/// Migration alias for the built-in model resolver.
typedef BuiltInAiHuggingFaceResolver = LocalAiHuggingFaceResolver;

/// Alias of [LocalAiAvailability].
typedef BuiltInAiAvailability = LocalAiAvailability;

/// Alias of [LocalAiUnavailableException].
typedef BuiltInAiUnavailableException = LocalAiUnavailableException;

/// Alias of [LocalAiEngine].
typedef BuiltInAiEngine = LocalAiEngine;

/// Alias of [LocalAiModels], carrying only the two specs
/// `flutter_gemma_builtin_ai` shipped. Windows and web specs are on
/// [LocalAiModels].
abstract final class BuiltInAiModels {
  static InferenceModelSpec get geminiNano => LocalAiModels.geminiNano;

  static InferenceModelSpec get appleFoundationModels =>
      LocalAiModels.appleFoundationModels;
}

/// Alias of the [LocalAi] availability facade.
abstract final class BuiltInAi {
  /// See [LocalAi.debugProbeTimeout].
  static set debugProbeTimeout(Duration value) =>
      LocalAi.debugProbeTimeout = value;

  static Duration get debugProbeTimeout => LocalAi.debugProbeTimeout;

  /// See [LocalAi.availability].
  static Future<BuiltInAiAvailability> availability() => LocalAi.availability();

  /// See [LocalAi.ensureReady].
  static Future<void> ensureReady({
    void Function(int percent)? onProgress,
    Duration timeout = const Duration(minutes: 10),
  }) => LocalAi.ensureReady(onProgress: onProgress, timeout: timeout);
}
