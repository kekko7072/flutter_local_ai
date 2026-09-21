# Platform support

What each OS backend actually does, what it needs at build time, and what has
been verified so far. The Apple and Android claims were checked against the
linked vendor documentation on **12 September 2026**, the Windows claims on
**21 September 2026** (Windows App SDK 2.5.5 metadata and the Windows AI API
docs); the Web claims are read off this package's own Chrome Prompt API arm in
`lib/src/session/web/`, not off a documentation review with a date.

Every entry below is a property of the running host, not of the package. The
same binary reports vision as unavailable on iOS 26 and available on iOS 27,
and reports Windows as unconfigured unless the host app supplied the App SDK
projections. Ask `LocalAi.capabilities()` and gate optional features on the
answer, rather than on `Platform.isX` or an OS version check — a capability
table read at compile time is how a feature ships enabled on a device that
cannot run it.

The weights are OS-managed; this package bundles no checkpoint.
`LocalAi.ensureReady()` can therefore start a sizeable system download — the
Windows GPU model most of all — so explain what is about to happen and obtain
the user's consent before calling it. Availability does not follow from the OS
version alone.

## Platform coverage and remaining gaps

| Capability | Apple | Android | Windows | Web |
|---|---|---|---|---|
| Text / conversation | OS 26+ native sessions | beta4, host replays the transcript | App SDK 2.0+ (build resolves it), host replays the transcript | Chrome Prompt API, browser session owns the history |
| Streaming | Incremental deltas | Incremental deltas | One final chunk, asynchronously delivered | Incremental deltas |
| Cancellation | Full, stream, structured tasks | Full and stream jobs | Async model creation/generation | `AbortController` on every request |
| Image input | OS 27 + SDK/compiler gate; unverified branch | Multiple image parts | Not exposed | Not exposed |
| Native Dart tools | Supported | Not bridged | Not exposed | Not exposed |
| Dynamic Dart JSON schema | Supported subset | No runtime API to bridge | `GenerateStructuredJsonResponseAsync`, unverified on device | `responseConstraint` |
| Exact text token count | OS / SDK 26.4+ | SDK tokenizer | Estimate | `measureInputUsage` |
| Explicit thinking control | Not exposed | Not bridged | Not exposed | Not exposed |

Apple's latest updates also introduce DynamicProfile, ToolCallingMode, new
error types, system Vision tools, custom LanguageModel implementations, and
Private Cloud Compute. Those APIs are not all exposed by this package. The
OS-provided on-device model updates automatically; model behavior still needs
prompt regression testing. Private Cloud Compute is a cloud path and is
intentionally not silently selected by this local-only backend. Native
structured streaming and runtime context-size reporting remain follow-ups. The
OS 27 image branch requires Swift 6.4+ with a matching SDK, then runtime
iOS/macOS 27; running OS 27 alone with an older build does not enable vision.
See [Apple's updates](https://developer.apple.com/documentation/updates/foundationmodels)
and [multimodal prompting](https://developer.apple.com/documentation/foundationmodels/analyzing-images-with-multimodal-prompting).

Android's current SDK exposes thinking, caching and typed structured output in
addition to the features used here. The structured-output guide requires Kotlin
types and KSP; this package has not implemented a runtime Dart-schema bridge.
Experimental Kotlin tool declarations in reference documentation do not
establish a working Dart callback bridge. Feature-specific ML Kit APIs and
Android AppFunctions are separate integrations, not substitutes for this LLM
backend. See the [Android solution guide](https://developer.android.com/ai/overview#ai-solution-guide),
[Prompt API setup](https://developers.google.com/ml-kit/genai/prompt/android/get-started),
[request reference](https://developers.google.com/android/reference/kotlin/com/google/mlkit/genai/prompt/GenerateContentRequest),
and [typed output guide](https://developers.google.com/ml-kit/genai/prompt/android/structured-output).

Windows is gated by Microsoft at runtime far more than at build time. Phi
Silica needs a Copilot+ PC (NPU) or, with Developer Mode and the vendor's
latest driver, an NVIDIA RTX 30+ / AMD Radeon GPU; Windows 11 25H2 (build
26200.7309) or later; and a process with package identity that declares the
`systemAIModels` capability — an unpackaged `flutter run` is refused. The
stable Windows App SDK channel additionally requires a Limited Access Feature
token from Microsoft for Phi Silica; the experimental channel does not. A
Copilot+ label or a Windows version check alone does not establish readiness,
which is why `LocalAi.availabilityReason()` reports the actual activation
failure (typically "Class not registered" when the Windows App Runtime is
absent or the app has no identity).

Structured output uses `LanguageModel.GenerateStructuredJsonResponseAsync`
(App SDK 2.0+, the projection floor this package generates against): the
Dart schema is validated, serialised and handed to the OS as JSON Schema text.
A `CompleteWithInvalidStructure` result surfaces as `STRUCTURED_OUTPUT_INVALID`
with the model's text in the error details. This package does not expose
Windows AI's embeddings, LoRA adapters, text intelligence skills, image
generation, or other features, and Windows AI has no function-calling API.
Its `LanguageModelOptions` path has no output-token limit, so
`maxOutputTokens` cannot be enforced there. See [Windows setup](https://learn.microsoft.com/en-us/windows/ai/apis/get-started),
[troubleshooting](https://learn.microsoft.com/en-us/windows/ai/apis/troubleshooting),
[Phi Silica](https://learn.microsoft.com/en-us/windows/ai/apis/phi-silica), and
[LanguageModelOptions](https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.windows.ai.text.languagemodeloptions?view=windows-app-sdk-2.0).

Chrome's Prompt API fixes sampling when the session is created, so per-call
`LocalAiGenerationOverrides` cannot be honoured there; the web host warns once
rather than pretending they applied.

Who owns the conversation also differs. The Android and Windows hosts keep the
whole transcript and resend it on every generate, because their APIs are
stateless per call. The web host does not: `addQueryChunk` buffers only the
pending turn, each generate drains that buffer and passes it to `prompt()`,
and Chrome's `LanguageModel` session retains the history itself. Replaying the
transcript there would feed every earlier turn back a second time. The
practical consequence is that the web arm's context limit is the browser
session's `inputQuota`, not something this package trims.

The web arm's availability gates are the browser's own — free disk space, an
eligible GPU, and an origin-trial token where the API is still trialled —
which is why `LocalAi.availabilityReason()` exists instead of a version check.

## Build requirements

- Package: Dart 3.8+ / Flutter 3.32+. This is the floor the package resolves
  and analyzes at; the repository itself develops on a newer SDK (see
  [FVM_SETUP.md](../FVM_SETUP.md)).
- Android: minSdk 26; Kotlin **2.3.21** and its `compilerOptions` DSL (the
  beta4 artifact has Kotlin 2.3 metadata). The example shows these settings.
  Let the Prompt API resolve its matching common and coroutine dependencies
  rather than pinning older versions.
- Apple: plugin deployment floor remains iOS 13 / macOS 12; the application's
  Flutter and other plugins may require a higher floor. Foundation Models
  requires OS 26 at runtime. Xcode 26.4 enables exact token counting; the new
  image path requires an OS 27 SDK.
- Windows: Visual Studio 2022 with the Desktop C++ workload and a Windows
  10/11 SDK, as Flutter itself requires. The plugin's
  `windows/cmake/windows_ai.cmake` resolves the App SDK projection at
  configure time, in this order:
  1. `FLUTTER_LOCAL_AI_WINRT_INCLUDE_DIR`, a directory you generated yourself
     that contains `winrt/Microsoft.Windows.AI.Text.h`.
  2. `Microsoft.WindowsAppSDK.AI` (2.5.5) and `Microsoft.Windows.CppWinRT`
     (2.0.250303.1) from the NuGet global packages folder
     (`%NUGET_PACKAGES%` or `%USERPROFILE%\.nuget\packages`), else
     downloaded from nuget.org into `build/windows/<arch>/flutter_local_ai/`.
     `cppwinrt.exe` then generates the projection (Windows SDK plus the App
     SDK AI namespaces, so `winrt/base.h` and the namespaces agree on a
     version) once per build tree.
  3. Nothing: a `flutter_local_ai:` warning and the unconfigured build, which
     reports `windowsAiFoundryUnconfigured` at runtime.

  Every knob is a CMake cache variable that can also be set as an environment
  variable of the same name, which is how a Flutter app steers it without
  editing CMake:

  | Variable | Default | Meaning |
  |---|---|---|
  | `FLUTTER_LOCAL_AI_WINDOWS_AI` | `AUTO` | `ON` makes an unresolved projection a configure error; `OFF` skips the whole step |
  | `FLUTTER_LOCAL_AI_NUGET_DOWNLOAD` | `ON` | `OFF` forbids the nuget.org fetch |
  | `FLUTTER_LOCAL_AI_WINRT_INCLUDE_DIR` | — | A ready-made projection directory |
  | `FLUTTER_LOCAL_AI_WINDOWS_APP_SDK_AI_DIR` | — | An extracted `Microsoft.WindowsAppSDK.AI` package (has `metadata/`) |
  | `FLUTTER_LOCAL_AI_WINDOWS_APP_SDK_AI_VERSION` | `2.5.5` | NuGet version to look up or download; 2.0 is the floor |
  | `FLUTTER_LOCAL_AI_CPPWINRT_EXE` | — | A `cppwinrt.exe` to run instead of the NuGet one |
  | `FLUTTER_LOCAL_AI_CPPWINRT_VERSION` | `2.0.250303.1` | `Microsoft.Windows.CppWinRT` version to look up or download |

  The pre-0.1.1 form — `set(FLUTTER_LOCAL_AI_WINDOWS_AI ON CACHE BOOL "" FORCE)`
  plus `FLUTTER_LOCAL_AI_WINRT_INCLUDE_DIR` in the app's CMake — still works
  and takes precedence.

  Headers do not deploy the runtime or grant identity. Package the app as
  MSIX with the `systemAIModels` capability (`systemai` namespace), a
  `PackageDependency` on the `Microsoft.WindowsAppRuntime` framework package
  matching the SDK you built against, and `MaxVersionTested` of at least
  `10.0.26226.0`, following [Microsoft's packaging guidance](https://learn.microsoft.com/en-us/windows/ai/apis/get-started).
  The normal Flutter runner initializes COM as an STA; preserve this when
  using a custom runner.

## Native tools and dynamic schemas

Both surfaces expose tools and schemas: `FlutterLocalAi.registerTools` plus a
`GenerationConfig.schema`, or the session API shown here. The session API is
what this example uses because the facade owns exactly one shared
conversation, and `registerTools` has to restart it — Apple's FoundationModels
binds tools when a session is constructed and cannot add them to a live one,
so changing the tool list means building a new session and losing the
transcript. Opening a session yourself makes that binding explicit and leaves
any other conversation running.

```dart
import 'package:flutter_local_ai/flutter_local_ai.dart';

Future<String> readStatusAsJson() async {
  await LocalAi.ensureReady();
  final model = await LocalAiModel.create(maxTokens: 4096);
  final session = await model.openSession(
    systemInstruction: 'Use the available local data.',
    tools: [
      LocalAiTool(
        name: 'readStatus',
        description: 'Read application status',
        parameters: const [],
        onCall: (_) async => {'status': 'ready'},
      ),
    ],
  );
  try {
    await session.addQueryChunk('Read the status and report it.');
    return await session.getStructuredResponse({
      'type': 'object',
      'properties': {
        'status': {'type': 'string'},
      },
      'required': ['status'],
    });
  } finally {
    await session.close();
    await model.close();
  }
}
```

Gate both on `LocalAi.capabilities()` first: this example needs a backend
supporting tools *and* schemas, which today means Apple Foundation Models.
Hosts reporting `supportsToolCalling: false` throw when tools are supplied, and
`getStructuredResponse` throws where `supportsStructuredOutput` is false.

Native tools in this package describe primitive arguments only — string,
integer, number, boolean. A tool that wants a nested object has to accept a
JSON string and parse it itself. There is no prompt-woven fallback: a host
without native tool calling throws rather than emulating one, because a
prompt-based function-call protocol is not equivalent to a constrained native
call and proved unreliable enough on Gemini Nano that the model answered in
prose instead of performing the call.

`LocalAiUiGenerator`'s `genUiInstructions` and `parseModelOutput` are public
statics, so a different on-device backend — a downloaded model, for example —
can produce the same `GenUiModuleSpec` and component tree as the OS model does.

## Validation and release gates

- Dart tests: the suite passes under `flutter test`. A count is not pinned
  here because it goes stale on the next test added.
- Dart analysis: no issues in the checked package sources.
- Android: `:flutter_local_ai:compileDebugKotlin` succeeded with Kotlin 2.3.21
  / ML Kit beta4. This is plugin compilation, not a complete release APK or a
  device inference test.
- Apple: all plugin Swift sources typecheck with Xcode 26.4 against an iOS 15
  target in Swift 5 language mode. This checks guarded backward deployment; it
  does not compile the OS 27 branch or run inference.
- Windows: CI builds the example with `flutter build windows` twice on a
  GitHub `windows-latest` runner — once letting the plugin resolve the
  projection (download + `cppwinrt.exe` + the `WINDOWS_AI_AVAILABLE=1` arm)
  and once with `FLUTTER_LOCAL_AI_WINDOWS_AI=OFF`. This is compilation of
  both arms, not a device inference test.
- Not run: the Windows runtime on Copilot+ hardware; the Apple OS 27 image
  branch; end-to-end device inference on **any** platform, Android, Apple,
  Windows and Chrome alike.

Nothing above substitutes for running a real app on a real device. Before
depending on a platform in production, cover availability and preparation, two
simultaneous sessions, cancellation followed by another turn, image ordering,
schema validation, genUI generation during an ongoing conversation, and closing
then recreating the model. Devices that report the backend as unavailable need
a usable fallback path. The OS 27 image branch, Windows structured output and
the experimental Windows GPU path each need their own device pass.
