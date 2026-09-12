# Flutter Gemma integration readiness

Reviewed against flutter_gemma **1.8.0**, flutter_gemma_builtin_ai **0.2.1**, and the linked platform documentation on **12 September 2026**.

## Decision

The existing adapter is compatible with Flutter Gemma's engine interfaces, and the fixes in this review make it safer to use alongside flutter_local_ai's own features. It is **not yet a blanket production sign-off for every platform or every newly announced OS feature**. Android native compilation, Apple OS 26 SDK typechecking, and Dart tests are covered; Windows and the Apple OS 27 branch still require their respective build environments and device validation.

The integration remains:

```text
FlutterGemma → LocalAiEngine → flutter_local_ai → OS-owned model
                                      ↑
                       native tools / schemas / genUI
```

Flutter Gemma owns model selection and its chat protocol. flutter_local_ai continues to own all native backends, native tool dispatch, dynamic schema translation, session lifecycle, runtime capabilities, and generative UI composition/parsing. These features were retained; they were not moved into Gemma or removed. Existing license files remain unchanged.

## What was fixed

- Model handles now share a native resource with reference counting. Session IDs are unique for the lifetime of the host, including after model replacement. Closing Gemma's model no longer destroys an active facade/genUI model, or vice versa.
- Model shutdown waits for session creation and attempts to close every session even if another close fails.
- genUI uses its own per-request instructions without resetting the application's shared chat. Its Android budget is now 900 output tokens rather than the obsolete 256-token cap.
- Adapter metadata now targets Gemma 1.8 / Dart 3.12 / Flutter 3.44. Migration exports include `BuiltInAiHuggingFaceResolver`.
- Unsupported audio and disabled image messages fail before silently losing their contents. Session and per-message image limits are enforced; singleton session creation is serialized. LoRA requests are rejected.
- Android uses beta4, multiple image parts, native system instructions where supported (prompt fallback elsewhere), and the SDK's 4096-token output ceiling. Generation is serialized across the shared AICore client; cancellation tracks both full and streamed responses.
- Apple fixes the service access-control build error, retains native tools/schemas/token counting, tracks cancellation for full and structured responses, and adds image attachments behind OS 27 and compiler gates.
- Windows uses `Microsoft.Windows.AI.Text`, `GetReadyState`, `EnsureReadyAsync`, and the current prompt-first generation signature. Generation no longer blocks the platform message loop. Sampling options, response status checks, and cancellable async operations are wired. SDK support has explicit CMake configuration.

## Migrating the consumer

Use `package:flutter_local_ai/gemma.dart` in place of `flutter_gemma_builtin_ai`, and register **one** engine for `ModelFileType.builtIn`:

```dart
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_local_ai/gemma.dart';

await FlutterGemma.initialize(inferenceEngines: const [LocalAiEngine()]);
final spec = LocalAiModels.forCurrentPlatform;
if (spec == null) throw UnsupportedError('No OS model backend on this platform');
await LocalAi.ensureReady();
await FlutterGemma.installModel(
  modelType: ModelType.general,
  fileType: ModelFileType.builtIn,
).fromBundled(spec.name).install();
final model = await FlutterGemma.getActiveModel(maxTokens: 4096);
```

The `BuiltInAi*` migration names are also exported. Dependency replacement and registration still have to be made in the consuming Gemma app/package. This repository does not modify or publish the creator's upstream package. The engine ships inside `flutter_local_ai` itself, so there is one package to depend on and one to publish.

Models are OS-managed, not bundled checkpoints. Preparation can download system assets. An app should explain and obtain consent for sizeable downloads before calling `ensureReady`, especially the Windows GPU model. Availability does not follow from OS version alone.

## Preserving the additional capabilities

Gemma's `InferenceModelSession` does not expose dynamic JSON schemas or Dart native-tool callbacks. Use the engine's public escape hatches on the same underlying model. `gemma.dart` re-exports the whole core library, so one import covers `LocalAiGemmaModel`, `LocalAiTool` and the session API:

```dart
import 'package:flutter_local_ai/gemma.dart';
// model is the result of FlutterGemma.getActiveModel().
final local = (model as LocalAiGemmaModel).localAiModel;
final native = await local.openSession(
  systemInstruction: 'Use the available local data.',
  tools: [LocalAiTool(
    name: 'readStatus', description: 'Read application status',
    parameters: const [], onCall: (_) async => {'status': 'ready'},
  )],
);
try {
  await native.addQueryChunk('Read the status and report it.');
  final json = await native.getStructuredResponse({
    'type': 'object', 'properties': {'status': {'type': 'string'}},
    'required': ['status'],
  });
} finally {
  await native.close();
}
```

Gate tools and schemas on `LocalAi.capabilities()` first. The example needs a backend supporting both, such as Apple Foundation Models. `LocalAiGemmaSession.localAiSession` also exposes schemas for an existing Gemma session. Direct native opens bypass the adapter limit; manage their number explicitly.

`LocalAiUiGenerator` remains available alongside Gemma. Its public `genUiInstructions` and `parseModelOutput` also allow a downloaded Gemma fallback to create the same `GenUiModuleSpec` and genui component tree.

Gemma's `InferenceChat` has a separate prompt-based function-call protocol. The adapter does **not** automatically translate its `Tool` objects into Apple tools. Do not assume prompt-based tool reliability is equivalent to native constrained calls. Direct `createSession(tools: ...)` does not itself run a tool loop; use Gemma chat or native sessions deliberately. Native tools in this package currently describe primitive arguments only.

## Platform coverage and remaining gaps

| Capability | Apple | Android | Windows |
|---|---|---|---|
| Text / conversation | OS 26+ native sessions | beta4 with transcript replay | App SDK 2.0+ with transcript replay |
| Streaming | Incremental deltas | Incremental deltas | One final chunk, asynchronously delivered |
| Cancellation | Full, stream, structured tasks | Full and stream jobs | Async model creation/generation |
| Image input | OS 27 + SDK/compiler gate; unverified branch | Multiple image parts | Not exposed |
| Native Dart tools | Supported | Not bridged | Not exposed |
| Dynamic Dart JSON schema | Supported subset | Not bridged | Not exposed |
| Exact text token count | OS / SDK 26.4+ | SDK tokenizer | Estimate |
| Explicit thinking control | Not exposed | Not bridged | Not exposed |

Apple's latest updates also introduce DynamicProfile, ToolCallingMode, new error types, system Vision tools, custom LanguageModel implementations, and Private Cloud Compute. Those APIs are not all exposed by this package. The OS-provided on-device model updates automatically; model behavior still needs prompt regression testing. Private Cloud Compute is a cloud path and is intentionally not silently selected by this local-only backend. Native structured streaming and runtime context-size reporting remain follow-ups. The OS 27 image branch requires Swift 6.4+ with a matching SDK, then runtime iOS/macOS 27; running OS 27 alone with an older build does not enable vision. See [Apple's updates](https://developer.apple.com/documentation/updates/foundationmodels) and [multimodal prompting](https://developer.apple.com/documentation/foundationmodels/analyzing-images-with-multimodal-prompting).

Android's current SDK exposes thinking, caching and typed structured output in addition to the features used here. The structured-output guide requires Kotlin types and KSP; this package has not implemented a runtime Dart-schema bridge. Experimental Kotlin tool declarations in reference documentation do not establish a working Dart callback bridge. Feature-specific ML Kit APIs and Android AppFunctions are separate integrations, not substitutes for this LLM engine. See the [Android solution guide](https://developer.android.com/ai/overview#ai-solution-guide), [Prompt API setup](https://developers.google.com/ml-kit/genai/prompt/android/get-started), [request reference](https://developers.google.com/android/reference/kotlin/com/google/mlkit/genai/prompt/GenerateContentRequest), and [typed output guide](https://developers.google.com/ml-kit/genai/prompt/android/structured-output).

Windows GPU support has additional experimental OS/SDK requirements. A Copilot+ label or a Windows version check alone does not establish readiness. This adapter does not expose the newer experimental structured-output APIs, embeddings, LoRA, image generation, or other Windows AI features. Its LanguageModelOptions path has no output-token limit, so `maxOutputTokens` cannot be enforced there. See [Windows setup](https://learn.microsoft.com/en-us/windows/ai/apis/get-started), [Phi Silica](https://learn.microsoft.com/en-us/windows/ai/apis/phi-silica), and [LanguageModelOptions](https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.windows.ai.text.languagemodeloptions?view=windows-app-sdk-2.0).

## Build requirements

- Adapter: Flutter 3.44+ / Dart 3.12+, Gemma 1.8.x compatible API.
- Android: minSdk 26; Kotlin **2.3.21** and its `compilerOptions` DSL (the beta4 artifact has Kotlin 2.3 metadata). The example shows these settings. Let the Prompt API resolve its matching common and coroutine dependencies rather than pinning older versions.
- Apple: plugin deployment floor remains iOS 13 / macOS 12; the application's Flutter and other plugins may require a higher floor. Foundation Models requires OS 26 at runtime. Xcode 26.4 enables exact token counting; the new image path requires an OS 27 SDK.
- Windows: provide matching App SDK 2.0+ C++/WinRT projections and runtime deployment/bootstrap in the host app. Configure these **before** Flutter adds the plugin:

```cmake
set(FLUTTER_LOCAL_AI_WINDOWS_AI ON CACHE BOOL "" FORCE)
set(FLUTTER_LOCAL_AI_WINRT_INCLUDE_DIR "C:/path/to/generated" CACHE PATH "" FORCE)
```

The directory must contain `winrt/Microsoft.Windows.AI.Text.h` and its dependency projections. Headers alone do not deploy the runtime. Follow Microsoft's packaging guidance, including `systemAIModels` capability and manifest target requirements. The normal Flutter runner initializes COM as an STA; preserve this when using a custom runner. The default build remains unconfigured and reports that state rather than claiming usable inference.

## Validation and release gates

- Dart tests: 135 passed in one suite — model coexistence and shutdown races, plus, against Gemma 1.8.0, migration names, modality rejection, limits, concurrent singleton creation, native tools/schema access and Gemma chat tool-protocol parsing.
- Dart analysis: no issues in the checked package sources.
- Android: `:flutter_local_ai:compileDebugKotlin` succeeded with Kotlin 2.3.21 / ML Kit beta4. This is plugin compilation, not a complete release APK or device inference test.
- Apple: all plugin Swift sources typecheck with Xcode 26.4 against an iOS 15 target in Swift 5 language mode. This checks guarded backward deployment; it does not compile the OS 27 branch or run inference.
- The publish dry-run found no validation errors; only uncommitted changes were flagged. No package was published.
- Not run: Windows native build/runtime; Apple OS 27 build/runtime; Android, Apple, Windows and Chrome end-to-end inference; publishing.

Before announcing replacement readiness, build and run the consuming Gemma app on supported devices. Cover availability/preparation, two simultaneous chats, cancellation then another turn, image ordering, prompt tools versus native tools, schema validation, genUI during chat, and closing/recreating the active model. Unsupported devices should retain a usable fallback. Additional device tests are required for the OS 27 model and experimental Windows GPU path.
