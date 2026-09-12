## Unreleased

- Verify the adapter against flutter_gemma 1.8.0 and retain migration aliases.
- Share native model ownership across Gemma, the facade and genUI; avoid
  session ID collisions and wait for in-flight session creation on shutdown.
- Keep genUI instructions isolated from ongoing conversations.
- Upgrade Android Prompt API to beta4 / Kotlin 2.3.21, with multiple images,
  native system instructions when available, expanded output budget and
  cancellable, serialized generation.
- Fix Apple service access control; cancel full/structured responses and add
  an OS 27 SDK-gated image attachment path (awaiting OS 27 validation).
- Update Windows to the App SDK 2.0 Text namespace, readiness/preparation,
  async generation/cancellation and explicit CMake setup (awaiting Windows
  build/device validation).
- Document remaining API gaps and release checks in doc/gemma-readiness.md.

## 0.1.0

A rewrite onto one architecture, and the OS-model layer under
[flutter_gemma](https://pub.dev/packages/flutter_gemma) via the new
`flutter_gemma_local_ai` bridge package in this repository.

### One implementation instead of two

Every platform previously carried two paths: a hand-rolled method channel
with its own generation logic, and nothing else. Both Dart surfaces now run
on a single pigeon-typed session host per platform.

* `FlutterLocalAi` is now a thin facade over the session layer rather than a
  parallel implementation. Its API is unchanged; there is simply one place
  where generation happens.
* The Android plugin drops from 515 to 39 lines, the Apple plugin from 932 to
  38, and Windows from 373 to 48. What is left is registration.
* The native contract lives in `pigeon.dart`, generated for Dart, Kotlin,
  Swift and C++. Its session half is shape-compatible with
  `flutter_gemma_builtin_ai`'s `BuiltInAiService`.

### New capability

* **Session API.** `LocalAiModel` mints `LocalAiSession`s that buffer a turn
  (`addQueryChunk` / `addImage`) then generate it, with `stopGeneration`,
  `sizeInTokens` and `close`. Several conversations can be open at once.
* **Availability facade.** `LocalAi.availability()`, `LocalAi.ensureReady()`
  with download progress, and `LocalAi.capabilities()`. Capabilities are
  reported by the running host, not assumed per platform — the same binary
  answers differently across OS versions.
* **Web.** A Chrome Prompt API arm, including schema-constrained output via
  `responseConstraint`, alongside Apple's native schema path.
* **Images.** `addImage` on Android. Apple needs OS 27 and reports
  `supportsVision: false` until then.
* **Exact token counts.** Native on Android and Apple 26.4+; elsewhere
  `sizeInTokens` falls back to a documented `length / 4` estimate rather than
  failing.
* **Cancellation.** `stopGeneration` reaches the model, not just the Dart
  subscription.
* **Per-call sampling on the wire.** `GenerationOverrides` lets one call vary
  temperature or length without disturbing the conversation, which is how
  both Apple's `respond(options:)` and ML Kit's request builder already work.

### Breaking

* `FlutterLocalAiPlatform` and `MethodChannelFlutterLocalAi` are removed. The
  platform seam is now `LocalAiHost`; tests substitute one with
  `debugLocalAiHost`.
* `LocalAiPlatformInfo.fromMap` is replaced by
  `LocalAiPlatformInfo.fromCapabilities`. The type is now a narrowed view of
  `LocalAiBackendCapabilities`, which is the single source of truth.
* `LocalAiBackend` gains `chromePromptApi`, so exhaustive switches over it
  need a new case.
* **Behaviour:** `generateText` without `instructions` now continues one
  shared conversation on *every* platform. Apple already did; Android
  silently discarded history. Pass `instructions:` for a stateless call, as
  the docs have always described.
* `registerTools` now restarts the shared conversation, because Apple's
  FoundationModels binds tools when a session is constructed and cannot add
  them to a live one.
* The SDK floor moves to Dart 3.6 / Flutter 3.27, required by the
  `extension type` and `dart:js_interop` the web arm is written against.

### Preserved

Native Apple tool calling, schema-constrained output with Dart-side schema
validation, Windows AI Foundry, genUI module specs, AICore availability
reasons and the Play Store redirect all carry over unchanged, and are now
reachable from the session API as well.

## 0.0.15

### Structured (JSON-schema) outputs

* **Apple (iOS 26 / macOS 26):** native schema-constrained generation. A JSON
  Schema passed through `GenerationConfig.schema` is translated into a
  FoundationModels `GenerationSchema`, so the model is forced to emit matching
  JSON. Supported constructs: nested objects (with `required`), arrays (with
  `minItems` / `maxItems`), string enums, and the scalar types. Read the result
  with `AiResponse.json` (object roots) or `AiResponse.decodedJson` (any root).
* **Android / Windows:** unchanged — these backends are text-out only and report
  `supportsStructuredOutput: false`. Passing a `schema` (or
  `ResponseFormat.json`) throws `STRUCTURED_OUTPUT_UNSUPPORTED`. The ML Kit GenAI
  on-device Prompt API does not currently expose a `responseSchema` /
  `responseMimeType`; gate on `getPlatformInfo().supportsStructuredOutput`.

### Hardening of the structured-output API

* A `schema` now implies JSON mode consistently: you no longer have to also set
  `responseFormat: ResponseFormat.json`, and `GenerationConfig.toMap()` never
  sends a schema paired with a `text` format (`effectiveResponseFormat` /
  `requestsStructuredOutput` expose this).
* Schemas are validated in Dart **before** the platform channel
  (`GenerationConfig.validateSchema()`), so unsupported constructs fail fast with
  a path-qualified `ArgumentError` instead of an opaque native error.
* `AiResponse.decodedJson` decodes a root array or scalar; `AiResponse.json`
  stays object-only for backwards compatibility.
* `generateTextStream` now rejects schema-constrained requests up front (no
  backend can constrain streamed output yet) instead of silently returning
  free-form text — the returned stream errors immediately. Use `generateText`
  for structured output.

## 0.0.14

### Android: tool calling is explicitly unsupported
* `registerTools()` on Android now fails with a clear `UNSUPPORTED` error
  instead of pretending to work. The ML Kit GenAI Prompt API has no function
  calling — text/image in, text out only (verified against the
  `genai-prompt:1.0.0-beta2` API surface) — and a prompt-emulated JSON call
  protocol proved too unreliable on Gemini Nano to ship: the model answers in
  prose instead of performing the call. Gate on
  `getPlatformInfo().supportsToolCalling` (false on Android); revisit when
  Gemma 4 / Agent Mode reaches the Prompt API surface.
* The example app shows the tool-calls toggle only on iOS/macOS, and
  `debugPrint`s every request and response — including the genUI tab's raw
  model output, so generation issues are inspectable from the console.

### Android: widest available device support + robust model download
* Bumped `com.google.mlkit:genai-prompt` from `1.0.0-alpha1` to `1.0.0-beta2`.
  alpha1 only resolved the Prompt API feature on Pixel 9 devices, so
  `checkStatus()` never reported `DOWNLOADABLE` on anything else; beta2 carries
  the full current supported-device list — Pixel 9/10 series plus Samsung
  (Galaxy Z Fold7 / Z TriFold, S26 series), Honor, iQOO, Lenovo, Motorola,
  OnePlus, OPPO, POCO, realme, vivo and Xiaomi flagships (nano-v2 / nano-v3).
* Aligned `com.google.mlkit:genai-common` with the `1.0.0-beta3` version that
  `genai-prompt:1.0.0-beta2` declares in its POM (it's the artifact resolving
  per-device feature configs; the previous explicit `beta2` pin understated the
  actually-resolved version) and `play-services-tasks` with the POM's `18.2.0`
  floor.
* Documented the supported-device matrix in the README, including that any
  API 26+ device can install the app and gracefully degrades via
  `isAvailable()` / `getModelStatus()` on unsupported hardware.
* `downloadModel()` failures now always surface on the download status stream:
  the Android implementation emits a `failed` status (with the error message)
  before propagating the exception, and the Dart layer converts a failed
  `downloadModel` method call into a `failed` status as a last resort. UIs
  watching the stream can no longer hang on a silent native error.
* `downloadModel()` is idempotent: when the model is already downloaded it
  emits `completed` immediately instead of erroring.

## 0.0.13

### Stateless one-shot generation
* `generateText` and `generateTextStream` gain an optional `instructions`
  parameter. When given, the call runs in a throwaway session with exactly
  those instructions: nothing accumulates in the shared session created by
  `initialize`, and its instructions stay untouched. Apple's
  `LanguageModelSession` keeps every prompt + response of its transcript
  counting toward the 4096-token context window, so stateless callers that
  carry their own context in the prompt would otherwise hit
  `exceededContextWindowSize` after a few calls. On Android ML Kit (already
  stateless per call) the one-shot instructions simply replace the
  session-level ones for that prompt.
* `LocalAiUiGenerator` now generates every module one-shot, so repeated
  generations no longer fill the shared session's context window.

## 0.0.12

### Streaming text generation
* New `FlutterLocalAi.generateTextStream(prompt:, config:)` returns a
  `Stream<String>` of delta chunks as the on-device model decodes, closing when
  the generation completes. Implemented on Apple FoundationModels
  (`LanguageModelSession.streamResponse`, cumulative snapshots converted to
  deltas) and Android ML Kit GenAI (`generateContent` with a
  `StreamingCallback`). Backends without a streaming implementation surface an
  error on the stream so callers can fall back to `generateText`.
* `LocalAiUiGenerator.generateModule` gains an optional `onText` callback that
  receives the cumulative raw model output while the module is being generated
  (for live progress/preview UI). When the platform cannot stream, generation
  silently degrades to the previous blocking call.

## 0.0.11

### genUI — localized generation
* `LocalAiUiGenerator.generateModule` gains an optional `language` parameter (an
  English language name such as "Italian" or "German"). When set, the prompt
  instructs the on-device model to write all user-facing copy — title, blurb and
  every block label, item and note — in that language, so generated modules match
  the app's locale. Omitting it preserves the previous behaviour.

## 0.0.10

### genUI — reliable generation on Android (Gemini Nano)
* Fixed the "model did not return JSON" failure on Android. Gemini Nano caps
  output at 256 tokens, so a verbose module was being truncated mid-JSON. The
  genUI prompt is now backend-aware: on Android it asks for compact, minified
  JSON with at most 3 blocks and shorter strings, and runs at a lower
  temperature (0.2) for more reliable structure — keeping output well within the
  token budget.
* Made `LocalAiUiGenerator`'s JSON extraction tolerant of small-model quirks: it
  now repairs JSON truncated by the output cap (cutting at the last complete
  block and closing the open brackets) and strips trailing commas (via
  `replaceAllMapped` — `replaceAll` does not expand `$1`), so a partial response
  still renders instead of being discarded.
* Verified end-to-end on a Google Pixel 10 (Android 16, Gemini Nano via AICore):
  multiple goals now produce valid, rendered modules.

### Tests
* Fixed the test suite: updated the platform-interface fake to implement the new
  `availabilityReason()` member, and added regression coverage for
  `LocalAiUiGenerator.parseModelOutput` (clean / fenced / prose / trailing-comma
  / truncated-and-repaired / invalid inputs).

### Generative UI in the example app
* The example app now has a **Generative UI** tab (alongside Text) that turns a
  goal into a rendered on-device module, with backend labelling and a JSON view.

### Platform & docs
* Raised the macOS deployment target (Podfile `10.15` → `12.0`) and refreshed
  dependencies; pins the project to Flutter 3.41.9 via FVM.
* Documented genUI in the README (Platform Support table, a Generative UI usage
  guide, and `LocalAiUiGenerator` / `GenUiModuleSpec` API reference).

## 0.0.9

### genUI reuse
* Exposed `LocalAiUiGenerator.genUiInstructions` (the module/block schema) and
  `LocalAiUiGenerator.parseModelOutput(text)` so any on-device backend (e.g. a
  downloaded Gemma model via flutter_gemma) can drive the same genUI generation.

## 0.0.8

### genUI on Android (Pixel)
* `LocalAiUiGenerator` is now backend-aware and works on Android ML Kit GenAI /
  Gemini Nano (e.g. Google Pixel) as well as Apple FoundationModels — the genUI
  schema is delivered via instructions (prepended to the prompt natively on
  Android), and the output-token budget is tuned per backend.
* Added `availabilityReason` on Android (maps `FeatureStatus` →
  available/downloadable/downloading/unavailable) for accurate UI status.

## 0.0.7

### genUI integration
* Added a `genui` integration so the package can turn a natural-language goal
  into a renderable module spec: `LocalAiUiGenerator` (on-device, via
  FoundationModels) and `GenUiModuleSpec` (typed blocks → `genui` components).
* Added `availabilityReason()` (Dart + Apple native) to report exactly why the
  model is unavailable (e.g. `deviceNotEligible`, Apple Intelligence disabled).

### Apple platforms - Generation fix
* Fixed a FoundationModels `GenerationError` caused by combining `.greedy`
  sampling with a temperature; options are now chosen exclusively. Generation
  failures now surface a fully-reflected, diagnosable error description.

## 0.0.6

### Android - Availability & Dependencies
* Added `genai-common` dependency to align with updated ML Kit GenAI APIs. (Contributed by [kaitotokyo](https://github.com/kaitotokyo))
* Fixed availability checks by using `Generation.getClient()` and `FeatureStatus`/`GenAiException` from `genai-common`, with improved AICore incompatible handling. (Contributed by [kaitotokyo](https://github.com/kaitotokyo))
* Made generation config parsing safer and only apply `maxOutputTokens`/`temperature` when provided. (Contributed by [kaitotokyo](https://github.com/kaitotokyo))

## 0.0.5

### Apple platforms - Thread Safety
* Introduced a `ModelManager` actor for thread-safe FoundationModels access, session initialization, tool registration, and text generation. (Contributed by [kaitotokyo](https://github.com/kaitotokyo))

### Android - Availability Check
* Improved availability checks using `FeatureStatus`, better `GenAiException` handling, and ensured the model client is closed. (Contributed by [kaitotokyo](https://github.com/kaitotokyo))
* Updated AICore/MLKit incompatibility error message for clarity. (Contributed by [kaitotokyo](https://github.com/kaitotokyo))

## 0.0.4

### Apple platforms - Improvements 
* Lowered iOS and macOS deployment targets to allow plugin compilation on older OS versions; runtime still reports unsupported below 26.0.


## 0.0.3

### Apple platforms - Tool Support
* ✅ **Tools API support (iOS & macOS only)** - Added support for tool execution on Apple platforms; Android and Windows tooling support is planned

## 0.0.2

### Windows - Initial Support
* ✅ **Added Windows platform support** - Initial implementation structure for Windows AI APIs (Windows AI Foundry)
* ✅ **Windows plugin structure** - Created C++/WinRT plugin implementation with method channel handlers
* ✅ **Windows version checking** - Added availability check for Windows 11 22H2 (build 22621) or later
* ✅ **CMake build configuration** - Added Windows CMakeLists.txt for plugin compilation
* ✅ **Example app Windows support** - Added Windows platform to example app
* ✅ **Documentation updates** - Added Windows setup instructions and platform-specific notes to README

### Improvements
* Updated package description to include Windows AI APIs
* Added Windows to platform support table
* Comprehensive Windows implementation documentation

### Status
* Windows AI API integration structure is in place and ready for full implementation
* Plugin provides availability checking, initialization flow, and error handling
* Ready for Windows AI Foundry API integration when APIs become available

## 0.0.1-dev.9

### Android - Complete Implementation
* ✅ **Completed Android support** - Full working implementation using ML Kit GenAI (Gemini Nano)
* ✅ **Improved FlutterLocalAiPlugin.kt** - Enhanced with proper context management, coroutine scope handling, and error detection
* ✅ **Java 11 support** - Updated build.gradle to require Java 11 (required for ML Kit GenAI)
* ✅ **AICore integration** - Added proper AICore library declaration and error handling
* ✅ **Play Store integration** - Added `openAICorePlayStore()` method to help users install AICore
* ✅ **Enhanced error handling** - Improved error code -101 detection and user-friendly error messages
* ✅ **Dependencies** - Added `play-services-tasks:18.0.2` dependency
* ✅ **Example app updates** - Added AICore library declaration and dependencies to example app
* ✅ **Comprehensive documentation** - Updated README.md with complete Android setup instructions, AICore handling guide, and code examples

### Improvements
* Better token counting (filtering empty strings)
* Improved Play Store opening logic with proper activity resolution
* Proper cleanup in `onDetachedFromEngine` (canceling coroutine scope)
* Enhanced logging for debugging AICore issues

### Documentation
* Complete Android setup guide with step-by-step instructions
* AICore requirement explanation and handling examples
* Platform-specific usage examples
* Error handling best practices
* Updated platform support table (Android now shows ✅)

## 0.0.1-dev.8
* Wip on Android
* First usage of AICore 

## 0.0.1-dev.7
* Added support to macOS
* Migrated to Swift Package Manager

## 0.0.1-dev.6

* Enhanced documentation

## 0.0.1-dev.5

* Improved Android logic

## 0.0.1-dev.4

* Improved iOS logic

## 0.0.1-dev.3

* Enhanced documentation

## 0.0.1-dev.2

* Added development warning

## 0.0.1-dev.1

* Initial beta release
* Android implementation using ML Kit GenAI
* iOS implementation structure (placeholder for Apple GenAI API)
* Dart API for text generation
* Example app included
* Comprehensive test suite
