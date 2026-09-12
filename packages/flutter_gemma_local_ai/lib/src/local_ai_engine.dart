import 'package:flutter_gemma/core/model.dart' show ModelFileType;
import 'package:flutter_gemma/core/model_management/model_specs.dart'
    show InferenceModelSpec;
import 'package:flutter_gemma/core/registry/hugging_face_resolver.dart'
    show HuggingFaceResolver;
import 'package:flutter_gemma/core/registry/hugging_face_resolver_source.dart'
    show HuggingFaceResolverSource;
import 'package:flutter_gemma/core/registry/inference_engine_provider.dart';
import 'package:flutter_gemma/core/registry/runtime_config.dart';
import 'package:flutter_gemma/flutter_gemma_interface.dart' show InferenceModel;
import 'package:flutter_local_ai/flutter_local_ai.dart';

import 'local_ai_gemma_model.dart';
import 'local_ai_hugging_face_resolver.dart';

/// flutter_gemma inference engine backed by the OS built-in model, through
/// flutter_local_ai.
///
/// Register it at startup, alongside whatever other engines the app uses:
///
/// ```dart
/// await FlutterGemma.initialize(
///   inferenceEngines: const [LocalAiEngine()],
/// );
/// ```
///
/// A pure factory: it verifies the OS model is ready, asks the host to load
/// it, and hands back a bare model. Core owns the singleton lifecycle through
/// `InferenceModel.addCloseListener`.
class LocalAiEngine
    implements InferenceEngineProvider, HuggingFaceResolverSource {
  const LocalAiEngine();

  @override
  String get name => 'LocalAI';

  @override
  int get priority => 0;

  @override
  HuggingFaceResolver get huggingFaceResolver =>
      const LocalAiHuggingFaceResolver();

  @override
  bool canHandle(InferenceModelSpec spec) =>
      spec.fileType == ModelFileType.builtIn;

  @override
  Future<InferenceModel> createModel(
    InferenceModelSpec spec,
    RuntimeConfig config,
  ) async {
    if (config.supportAudio) {
      throw UnsupportedError('Audio input is not exposed by flutter_local_ai.');
    }
    if (config.loraRanks?.isNotEmpty ?? false) {
      throw UnsupportedError(
        'LoRA ranks cannot be configured for the OS model.',
      );
    }
    // Readiness is a hard precondition here, not something to wait out: the
    // OS feature download can take minutes and belongs to app startup, where
    // it can show progress. Callers drive it with LocalAi.ensureReady().
    final status = await LocalAi.availability();
    if (status != LocalAiAvailability.available) {
      throw LocalAiUnavailableException(
        status,
        'The built-in model "${spec.name}" is not available ($status). Call '
        'LocalAi.ensureReady() before creating the model.',
      );
    }

    final model = await LocalAiModel.create(
      maxTokens: config.maxTokens,
      supportImage: config.supportImage,
    );

    return LocalAiGemmaModel(
      model: model,
      modelType: spec.modelType,
      fileType: spec.fileType,
      maxTokens: config.maxTokens,
      supportImage: config.supportImage,
      maxNumImages: config.maxNumImages,
      maxConcurrentSessions: config.maxConcurrentSessions,
    );
  }
}
