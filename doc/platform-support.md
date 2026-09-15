# Platform support

What each OS backend actually does, what it needs at build time, and what has
been verified so far. The Apple, Android and Windows claims were checked
against the linked vendor documentation on **12 September 2026**; the Web
claims are read off this package's own Chrome Prompt API arm in
`lib/src/session/web/`, not off a documentation review with that date.

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
| Text / conversation | OS 26+ native sessions | beta4, host replays the transcript | App SDK 2.0+, host replays the transcript | Chrome Prompt API, browser session owns the history |
| Streaming | Incremental deltas | Incremental deltas | One final chunk, asynchronously delivered | Incremental deltas |
| Cancellation | Full, stream, structured tasks | Full and stream jobs | Async model creation/generation | `AbortController` on every request |
| Image input | OS 27 + SDK/compiler gate; unverified branch | Multiple image parts | Not exposed | Not exposed |
| Native Dart tools | Supported | Not bridged | Not exposed | Not exposed |
| Dynamic Dart JSON schema | Supported subset | Not bridged | Not exposed | `responseConstraint` |
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

Windows GPU support has additional experimental OS/SDK requirements. A Copilot+
label or a Windows version check alone does not establish readiness. This
package does not expose the newer experimental structured-output APIs,
embeddings, LoRA, image generation, or other Windows AI features. Its
`LanguageModelOptions` path has no output-token limit, so `maxOutputTokens`
cannot be enforced there. See [Windows setup](https://learn.microsoft.com/en-us/windows/ai/apis/get-started),
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
- Windows: provide matching App SDK 2.0+ C++/WinRT projections and runtime
  deployment/bootstrap in the host app. Configure these **before** Flutter adds
  the plugin:

```cmake
set(FLUTTER_LOCAL_AI_WINDOWS_AI ON CACHE BOOL "" FORCE)
set(FLUTTER_LOCAL_AI_WINRT_INCLUDE_DIR "C:/path/to/generated" CACHE PATH "" FORCE)
```

The directory must contain `winrt/Microsoft.Windows.AI.Text.h` and its
dependency projections. Headers alone do not deploy the runtime. Follow
Microsoft's packaging guidance, including `systemAIModels` capability and
manifest target requirements. The normal Flutter runner initializes COM as an
STA; preserve this when using a custom runner. The default build remains
unconfigured and reports that state rather than claiming usable inference.

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
- Not run: the Windows native build and runtime; the Apple OS 27 image branch;
  end-to-end device inference on **any** platform, Android, Apple, Windows and
  Chrome alike.

Nothing above substitutes for running a real app on a real device. Before
depending on a platform in production, cover availability and preparation, two
simultaneous sessions, cancellation followed by another turn, image ordering,
schema validation, genUI generation during an ongoing conversation, and closing
then recreating the model. Devices that report the backend as unavailable need
a usable fallback path. The OS 27 image branch and the experimental Windows GPU
path each need their own device pass.
