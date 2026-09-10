## 0.1.0

Initial release.

* `LocalAiEngine` implements flutter_gemma's `InferenceEngineProvider`, backed
  by `flutter_local_ai`, so the OS built-in model appears behind the same
  `FlutterGemma` facade as any bundled checkpoint.
* Android (Gemini Nano via ML Kit GenAI), iOS/macOS (Apple Foundation Models),
  Windows (AI Foundry) and web (Chrome Prompt API).
* Both flutter_gemma session lanes: `createSession` keeps the singleton,
  `openSession` returns detached sessions for concurrent conversations.
* `LocalAiModels` specs, including Windows and web, plus
  `forCurrentPlatform`.
* `LocalAiHuggingFaceResolver` reserves the `ModelFileType.builtIn` Hugging
  Face slot so resolving one explains why it cannot work.
* `BuiltInAi*` aliases make migrating from `flutter_gemma_builtin_ai` a
  changed import.
