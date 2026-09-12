/// flutter_gemma inference engine backed by the OS built-in model.
///
/// Gemini Nano via ML Kit GenAI on Android, Apple Foundation Models on
/// iOS/macOS, Windows AI Foundry on Windows, and Gemini Nano via the Chrome
/// Prompt API on the web. No app checkpoint is bundled; the OS manages the
/// weights and may download system assets during preparation.
///
/// This entry point re-exports the whole core library, so a flutter_gemma app
/// imports this one file and still reaches [LocalAiTool], [LocalAiSession] and
/// the rest of the native surface — including the parts flutter_gemma's own
/// interfaces do not expose.
///
/// ```dart
/// import 'package:flutter_gemma/flutter_gemma.dart';
/// import 'package:flutter_local_ai/gemma.dart';
///
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

export 'flutter_local_ai.dart';

export 'src/gemma/builtin_ai_compat.dart';
export 'src/gemma/local_ai_engine.dart';
export 'src/gemma/local_ai_gemma_model.dart' show LocalAiGemmaModel;
export 'src/gemma/local_ai_gemma_session.dart' show LocalAiGemmaSession;
export 'src/gemma/local_ai_hugging_face_resolver.dart';
export 'src/gemma/local_ai_models.dart';
