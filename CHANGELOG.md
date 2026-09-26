## Unreleased

Answers [#26](https://github.com/kekko7072/flutter_local_ai/issues/26).

* **Breaking:** a call on a session that is still generating throws
  `LocalAiSessionBusyException` on every platform. It was a `StateError` on
  the web and a `SESSION_BUSY` `PlatformException` on Android and Windows;
  Apple had no guard, so a second turn orphaned the first.
  *Migration:* catch `LocalAiSessionBusyException` instead.
* A failed `LocalAiSession.close()` rethrows and leaves the session open, so
  it can be retried. `FakeLocalAiHost.closeSessionError` simulates it.
* The web host warns once when `topP` or `maxOutputTokens` is dropped.

## 0.2.0

Answers [#24](https://github.com/kekko7072/flutter_local_ai/issues/24): a web
hang, the Android `kotlin-android` line, token counting scoped to a session,
and an availability probe that could throw.

### Breaking changes

* **Minimum SDK is now Flutter 3.44 / Dart 3.12**, up from Flutter 3.32 /
  Dart 3.8. Flutter 3.44 is the first release that applies the Kotlin Gradle
  Plugin (KGP) to plugin subprojects itself, so `android/build.gradle` no
  longer runs `apply plugin: 'kotlin-android'`. A plugin that applies KGP
  itself is a hard configuration error under AGP 9 with built-in Kotlin, and
  it fails the whole app build, not just the plugin.
  *Migration:* upgrade the app to Flutter 3.44 or later. Apps that must stay
  on an older Flutter can stay on 0.1.x.
* **`LocalAiHost.countTokens` takes named arguments:**
  `countTokens({required int sessionId, required String text})` instead of
  `countTokens(String text)`. This only affects code that implements
  `LocalAiHost` itself; `LocalAiSession.sizeInTokens` passes its own id.
  *Migration:* add the `sessionId` parameter to your override. A host with a
  model-wide tokenizer can ignore it, as the native hosts do.
* **`ensureReady()` fails when the download cannot be started.** Before, a
  `downloadFeature()` that threw was ignored and polling waited out the full
  `timeout` (10 minutes by default), then threw a `TimeoutException`. Now
  `ensureReady()` rethrows the host's error as soon as the kick-off fails.
  This applies on every platform.
  *Migration:* nothing, if you already handle errors from `ensureReady()`.
  Code that caught only `TimeoutException` should also catch the host error,
  or `LocalAiUnavailableException` on the web.

### New

* `LocalAiUserActivationRequiredException`, a `LocalAiUnavailableException`
  whose `status` is `downloadable`. The web arm throws it when Chrome would
  refuse to start the Gemini Nano download because no user gesture is active.
  Catch it and ask the user to press a button that calls `ensureReady()`.
* `FakeLocalAiHost` (from `package:flutter_local_ai/testing.dart`) gains
  `downloadFeatureError`, `availabilityReasonError` and
  `countTokensSessionIds`, so apps can test these paths.

### Fixes

* **Web: `ensureReady()` outside a user gesture fails straight away**
  instead of hanging for ten minutes and blaming a slow download. The web
  host checks `navigator.userActivation.isActive` before calling `create()`,
  and maps Chrome's `NotAllowedError` to
  `LocalAiUserActivationRequiredException` for browsers without that API.
  Call `ensureReady()` from a click or key handler, not at start-up.
* **Web: token counts use the right session.** `sizeInTokens` used to
  measure on whichever session was opened first, and could run in the middle
  of a streaming turn. It now measures on the calling session, after any
  turn in progress there finishes.
* **`LocalAi.availabilityReason()` never throws,** matching `availability()`.
  On a platform with no registered plugin it returns a sentence instead of
  throwing `MissingPluginException`. It uses the same `debugProbeTimeout`
  bound as `availability()`.

### Internal

* The web test suite runs again, and CI and publish now run it on Chrome.
  The files that were `local_ai_host.dart` and `fake_local_ai_host.dart`
  under `lib/src/` are renamed to `local_ai_host_api.dart` and
  `local_ai_host_fake.dart`, because `flutter test --platform chrome` serves
  any path containing `host.dart.js` as its own runner script. As a result,
  every browser test that loaded them hung at "loading". Code that imports
  only the public libraries (`flutter_local_ai.dart`, `testing.dart`) is not
  affected; deep `src/` imports need the new names.
* The example app runs on the web. It had no `web/` platform folder, and it
  called `dart:io`'s `Platform.isAndroid` during `build()`, which throws in a
  browser and left a blank page. It now uses `defaultTargetPlatform` and
  `kIsWeb`, and CI builds it for the web.
* `LocalAiSession` and `LocalAiModel` use Dart 3.12 private named
  parameters instead of longhand initializer lists.
* The CI and publish floor legs now run Flutter `3.44.0` exactly.

## 0.1.2

* Tool errors now build their `details` key with a null-aware map element
  (`'details': ?encodableDetails`) instead of an `if` null check, clearing
  the `use_null_aware_elements` lint pub.dev's analysis reported against
  0.1.1. No behaviour change.

## 0.1.1

### Windows

* **Zero-config build.** `flutter build windows` now resolves the Windows
  App SDK's C++/WinRT projection on its own: `Microsoft.WindowsAppSDK.AI`
  2.5.5 and `Microsoft.Windows.CppWinRT` 2.0.250303.1 from the NuGet cache,
  or downloaded from nuget.org into the build tree, then projected with
  `cppwinrt.exe` once per build tree. No CMake edits, no NuGet in Visual
  Studio. When that cannot happen (offline, no cache) the build warns and
  falls back to the unconfigured plugin exactly as before, so nothing that
  built yesterday stops building. `FLUTTER_LOCAL_AI_WINDOWS_AI=ON|OFF`,
  `FLUTTER_LOCAL_AI_NUGET_DOWNLOAD=OFF` and the pre-existing
  `FLUTTER_LOCAL_AI_WINRT_INCLUDE_DIR` steer it, as environment variables or
  cache entries. See `doc/platform-support.md`.
* **Structured output**, natively, through
  `LanguageModel.GenerateStructuredJsonResponseAsync` (App SDK 2.0+).
  `supportsStructuredOutput` is now `true` on a configured Windows build. A
  response that completes but strays from the schema throws
  `STRUCTURED_OUTPUT_INVALID`, with the model's text in the error details.
* **Diagnosable availability.** `LocalAi.availabilityReason()` reports the
  actual WinRT activation failure ("Class not registered (0x80040154)") and
  what it means — no Windows App Runtime, or no package identity — instead
  of a generic hint. Generation statuses map to `GENERATION_BLOCKED` and
  `PROMPT_TOO_LONG` rather than a bare status number; an older runtime under
  a newer build surfaces as such instead of as a generic failure.
* **CI compiles the arm.** A `windows-latest` job builds the example twice,
  with the projection resolved and with it forced off. Previously nothing
  compiled the Windows C++ at all. It is still not a device pass: the
  runtime needs a Copilot+ PC or supported GPU, Windows 11 25H2+, and an
  MSIX-packaged app with the `systemAIModels` capability, none of which a
  plugin can supply.

### Documentation

* A **known limitations and fallbacks** section in the README spells out
  what each ❌ in the platform table is blocked on: Foundation Models exist
  only from OS 26 (older OSes get `unavailableOsTooOld`, not a crash);
  ML Kit's structured output is compile-time KSP with no runtime schema to
  bridge and has no function calling for Gemini Nano; Windows AI has no
  tool API; bring-your-own models belong to flutter_gemma and its
  `flutter_gemma_builtin_ai` bridge, not this package.
* The Windows setup section describes the Flutter-side flow — env vars,
  `msix` packaging with `systemAIModels` — and Microsoft's runtime
  requirements, instead of a generic CMake/NuGet recipe.
* The example's "Windows AI setup required" dialog no longer describes steps
  that stopped existing in 0.1.0.

### Tool declarations carry their schema

* **`LocalAiTool.parameterSchema`.** A tool can now declare its parameters as
  a JSON Schema object instead of a flat list of scalars, so a constraint the
  flat form cannot express — a string enum, a list, a nested object — reaches
  the model intact. It is the same subset `GenerationConfig.schema` accepts,
  validated in Dart with a path-qualified error and translated on Apple by
  the same `SchemaBuilder` that backs structured output, so the model is
  *constrained* to the declaration rather than asked to respect it. The flat
  `parameters` list still works and now lowers to the same schema; supply one
  or the other, not both.

### Tool errors are an answer, not a failed turn

* A tool body that throws no longer aborts generation. The error is encoded
  as a `{"error": "..."}` tool result the model reads and can respond to,
  which is what a declined confirmation or a denied permission looks like in
  an agent loop. `LocalAiToolException(message, {details})` is the deliberate
  spelling; any other exception is reported the same way, as is a result that
  will not JSON-encode.
* **A suspended tool call is cancellable.** `stopGeneration()` now unwinds a
  turn waiting on `onCall` instead of waiting for it to answer. There is no
  timeout on the native side, by design: a tool may sit for as long as a
  person takes to approve an action.

### Testing

* **`FakeLocalAiHost.invokeTool`** plays the model's half of a tool call,
  through the same registry the native host dispatches with — so an adapter's
  tool loop, including its refusal and suspension paths, is testable off
  device. `FakeLocalAiSession` now exposes the `tools` it was opened with and
  their `toolSchemas`, and a fake configured without `supportsToolCalling`
  rejects a session that binds tools, as a real host does.

### Behaviour and wire changes

No source change is needed to move from 0.1.0: `LocalAiTool.parameters` is
now optional rather than required, and `ToolParameter` / `ToolArgumentType`
are untouched. Two things behind the API did change.

* A tool body that throws used to fail the turn and now answers the model
  instead. Code relying on an exception to abort generation should call
  `stopGeneration()` explicitly.
* Wire: `ToolSpec` carries `parametersSchemaJson` instead of a
  `List<ToolParameterSpec>`, and `ToolParameterSpec` / `ToolArgumentKind` are
  gone from `pigeon.dart`. Nothing outside this package's own native hosts
  reads the wire, but a hot restart across this upgrade needs a full rebuild
  rather than a reload.

## 0.1.0

A rewrite onto one architecture, exposing a standalone OS-model layer that
external adapters can use through the public session API.

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
* **Per-call sampling on the wire.** `LocalAiGenerationOverrides` lets one
  call vary temperature or length without disturbing the conversation, which
  is how both Apple's `respond(options:)` and ML Kit's request builder
  already work.

### Platform backends

* **Android.** Prompt API beta4 / Kotlin 2.3.21, with multiple images, native
  system instructions where AICore supports them, an expanded output budget
  and cancellable, serialized generation.
* **Android.** A real download total from `DownloadStarted.bytesToDownload`,
  so `ensureReady(onProgress:)` reports a percentage rather than an unknown.
* **Android.** The transcript is settled when a turn fails or is cancelled:
  partial streamed text is committed, otherwise the abandoned prompt is
  dropped instead of being left for the next turn to resend.
  `stopGeneration` joins the cancelled job before it answers Dart.
* **Apple.** Fixed service access control; full and structured responses are
  cancellable; an OS 27 SDK-gated image attachment path (awaiting OS 27
  validation).
* **Apple.** Tool calling and structured output are reported only on
  iOS/macOS 26+ rather than unconditionally, so the capability gate is
  usable on an older OS instead of promising what the runtime cannot do.
* **Windows.** The App SDK 2.0 Text namespace, readiness/preparation, async
  generation/cancellation and explicit CMake setup (awaiting Windows
  build/device validation).
* Native model ownership is shared across the facade, the session API and
  genUI: session IDs no longer collide, in-flight session creation is awaited
  on shutdown, and closing one owner can no longer destroy another's live
  model.
* genUI instructions stay isolated from ongoing conversations, so generating
  a module no longer rewrites the chat the user is in.

### Documentation

* Per-platform coverage, build requirements and what remains unverified are
  documented in `doc/platform-support.md`.

### Breaking

* **Drop the `genui` dependency.** `GenUiModuleSpec.toComponents()` becomes
  `toComponentMaps()`, returning plain maps instead of genui's typed
  `Component`, so the package no longer pulls a renderer — and its native
  plugins — into apps that only generate text. The doc comment carries the
  three-line adaptation for genui users.
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
* The SDK floor moves to Dart 3.8 / Flutter 3.32, set by the `flutter_lints`
  6 development tooling, whose own pubspec declares `sdk: ^3.8.0` — 3.8 being
  what Flutter 3.32 ships. The web arm does not push it higher: its
  `extension type` / `dart:js_interop` interop has been stable since Dart
  3.3, and its null-aware elements land exactly on 3.8.

### Preserved

Native Apple tool calling, schema-constrained output with Dart-side schema
validation, Windows AI Foundry, genUI module specs, AICore availability
reasons and the Play Store redirect all carry over unchanged, and are now
reachable from the session API as well.

## 0.0.16

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
