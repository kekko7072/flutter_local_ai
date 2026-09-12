/// flutter_gemma inference engine backed by the OS built-in model, through
/// [flutter_local_ai](https://pub.dev/packages/flutter_local_ai).
///
/// Gemini Nano via ML Kit GenAI on Android, Apple Foundation Models on
/// iOS/macOS, Windows AI Foundry on Windows, and Gemini Nano via the Chrome
/// Prompt API on the web. No app checkpoint is bundled; the OS manages the weights
/// and may download system assets during preparation.
///
/// ```dart
/// await FlutterGemma.initialize(
///   inferenceEngines: const [LocalAiEngine()],
/// );
///
/// await FlutterGemma.installModel(
///   modelType: ModelType.general,
///   fileType: ModelFileType.builtIn,
/// ).fromBundled(LocalAiModels.forCurrentPlatform!.name).install();
///
/// await LocalAi.ensureReady(onProgress: (p) => debugPrint('$p%'));
///
/// final model = await FlutterGemma.getActiveModel(maxTokens: 4096);
/// final session = await model.createSession();
/// await session.addQueryChunk(const Message(text: 'Hello!', isUser: true));
/// final response = await session.getResponse();
/// ```
library;

export 'package:flutter_local_ai/flutter_local_ai.dart'
    show
        LocalAi,
        LocalAiAvailability,
        LocalAiBackendCapabilities,
        LocalAiBackendKind,
        LocalAiModel,
        LocalAiSession,
        LocalAiUnavailableException,
        LocalAiUnsupportedException;

export 'src/builtin_ai_compat.dart';
export 'src/local_ai_engine.dart';
export 'src/local_ai_gemma_model.dart' show LocalAiGemmaModel;
export 'src/local_ai_gemma_session.dart' show LocalAiGemmaSession;
export 'src/local_ai_hugging_face_resolver.dart';
export 'src/local_ai_models.dart';
