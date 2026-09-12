import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/core/domain/model_source.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/core/model_management/model_specs.dart'
    show InferenceModelSpec;

/// Ready-made [InferenceModelSpec]s for the OS built-in models.
///
/// The bundled source on each is inert — an identity token, not a file. The
/// OS owns the weights, and `ModelFileType.builtIn` is what makes core's
/// install pipeline skip the download it would otherwise attempt (and what
/// [LocalAiEngine.canHandle] matches on).
///
/// Which spec to install is a platform question, so pick with
/// [forCurrentPlatform] rather than hardcoding one.
abstract final class LocalAiModels {
  /// Gemini Nano via Android ML Kit GenAI (AICore).
  static InferenceModelSpec get geminiNano => InferenceModelSpec(
    name: 'gemini-nano',
    modelSource: ModelSource.bundled('gemini-nano'),
    modelType: ModelType.general,
    fileType: ModelFileType.builtIn,
  );

  /// Apple Foundation Models (iOS/macOS).
  static InferenceModelSpec get appleFoundationModels => InferenceModelSpec(
    name: 'apple-foundation-models',
    modelSource: ModelSource.bundled('apple-foundation-models'),
    modelType: ModelType.general,
    fileType: ModelFileType.builtIn,
  );

  /// Windows AI Foundry (Phi Silica). No counterpart exists in
  /// flutter_gemma_builtin_ai — Windows is what this engine adds.
  static InferenceModelSpec get windowsAiFoundry => InferenceModelSpec(
    name: 'windows-ai-foundry',
    modelSource: ModelSource.bundled('windows-ai-foundry'),
    modelType: ModelType.general,
    fileType: ModelFileType.builtIn,
  );

  /// Gemini Nano via the Chrome Prompt API (desktop Chrome / Chromium-Edge).
  static InferenceModelSpec get chromePromptApi => InferenceModelSpec(
    name: 'chrome-prompt-api',
    modelSource: ModelSource.bundled('chrome-prompt-api'),
    modelType: ModelType.general,
    fileType: ModelFileType.builtIn,
  );

  /// Every built-in spec, for apps that build their own model list.
  static List<InferenceModelSpec> get all => [
    geminiNano,
    appleFoundationModels,
    windowsAiFoundry,
    chromePromptApi,
  ];

  /// The spec for the platform this app is running on.
  ///
  /// Null on a platform with no built-in model (Linux, Fuchsia), so callers
  /// fall back to a downloaded model rather than installing a spec nothing
  /// can run. This answers identity only — whether the model is usable on
  /// *this device* is a separate runtime question, `LocalAi.availability()`.
  static InferenceModelSpec? get forCurrentPlatform {
    if (kIsWeb) return chromePromptApi;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => geminiNano,
      TargetPlatform.iOS || TargetPlatform.macOS => appleFoundationModels,
      TargetPlatform.windows => windowsAiFoundry,
      TargetPlatform.linux || TargetPlatform.fuchsia => null,
    };
  }
}
