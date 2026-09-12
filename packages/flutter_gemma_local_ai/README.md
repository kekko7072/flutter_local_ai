# flutter_gemma_local_ai

A [flutter_gemma](https://pub.dev/packages/flutter_gemma) inference engine that
runs against the **model the platform already ships**, instead of a bundled
Gemma checkpoint — Gemini Nano through ML Kit GenAI on Android, Apple
Foundation Models on iOS and macOS, Windows AI Foundry on Windows, and Gemini
Nano through the Chrome Prompt API on the web.

No checkpoint is bundled by the application: the OS manages model weights,
and initial preparation may download system assets.
Installing a built-in model records which one you want, and
`LocalAi.ensureReady()` makes sure the feature itself is switched on.

The engine is a thin adapter over
[flutter_local_ai](https://pub.dev/packages/flutter_local_ai), which owns the
native code for all four platforms.

## Supported platforms

| Platform | Model | Minimum | Notes |
|---|---|---|---|
| Android | Gemini Nano (ML Kit GenAI / AICore) | Supported AICore devices | Needs `minSdk 26`, Kotlin 2.3.21 |
| iOS / macOS | Apple Foundation Models | iPhone 15 Pro+, Apple silicon Macs | Needs Apple Intelligence enabled in Settings; OS 26+ |
| Windows | Windows AI Foundry (Phi Silica) | Windows 11 24H2, Copilot+ PC | Needs App SDK setup and device validation — see below |
| Web | Gemini Nano (Chrome Prompt API) | Desktop Chrome / Chromium-Edge | Needs an origin-trial token or `chrome://flags/#prompt-api-for-gemini-nano` |

Availability is a property of the device, OS and browser at runtime — never
something a build can promise. Always probe before creating a model.

## Quick start

```dart
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_local_ai/flutter_gemma_local_ai.dart';

void main() async {
  await FlutterGemma.initialize(
    inferenceEngines: const [LocalAiEngine()],
  );
  runApp(const MyApp());
}
```

Install the built-in model for this platform. There is no file, so the install
just records identity:

```dart
final spec = LocalAiModels.forCurrentPlatform;
if (spec != null) {
  await FlutterGemma.installModel(
    modelType: ModelType.general,
    fileType: ModelFileType.builtIn,
  ).fromBundled(spec.name).install();
}
```

Make sure the OS feature is ready. On Android this also drives the first-run
download:

```dart
await LocalAi.ensureReady(
  onProgress: (percent) => debugPrint('Preparing built-in AI: $percent%'),
);
```

Then use it exactly like any other flutter_gemma engine:

```dart
final model = await FlutterGemma.getActiveModel(maxTokens: 4096);
final session = await model.createSession();
await session.addQueryChunk(const Message(text: 'Hello!', isUser: true));
final response = await session.getResponse();
```

## Falling back to a bundled model

Register both engines and let availability decide which model to install. The
code downstream of the choice is identical:

```dart
await FlutterGemma.initialize(
  inferenceEngines: const [LocalAiEngine(), LiteRtLmEngine()],
);

if (await LocalAi.availability() == LocalAiAvailability.available) {
  await FlutterGemma.installModel(
    modelType: ModelType.general,
    fileType: ModelFileType.builtIn,
  ).fromBundled(LocalAiModels.forCurrentPlatform!.name).install();
} else {
  // Install a downloaded model instead.
}
```

## Feature parity

| Feature | Android | iOS / macOS | Windows | Web |
|---|---|---|---|---|
| Streaming responses | ✅ | ✅ | ⚠️ one chunk | ✅ |
| Vision (image input) | ✅ | ⚠️ OS 27 SDK + runtime | ❌ | ❌ |
| Audio input | ❌ | ❌ | ❌ | ❌ |
| Function calling | ⚠️ prompt protocol | ⚠️ prompt protocol | ⚠️ prompt protocol | ⚠️ prompt protocol |
| Thinking mode | ❌ | ❌ | ❌ | ❌ |
| `sizeInTokens` | ✅ native | ✅ on OS 26.4+, built with Xcode 26.4+ | ⚠️ estimate | ✅ native |
| LoRA weights | ❌ | ❌ | ❌ | ❌ |
| Concurrent sessions | ✅ | ✅ | ✅ | ✅ |

Where a native count is unavailable, `sizeInTokens` returns a `length / 4`
estimate rather than failing, so token budgeting degrades instead of breaking.
`LocalAi.capabilities()` tells you which you are getting on the device in
front of you — prefer it over a platform check, because the same binary
answers differently across OS versions.

"Prompt-based" function calling means flutter_gemma's `InferenceChat` weaves
tool declarations into the prompt and parses the calls back out. **This engine
deliberately does not forward flutter_gemma `tools` to the OS's own tool
runner**, even on Apple, where one exists: `InferenceChat` already owns the
tool loop, and running a second loop natively for the same turn would produce
two competing sets of calls. If you want Apple's native function calling, use
flutter_local_ai's own API, where you own the loop.

Windows streaming currently arrives as a single final chunk. Inference runs
asynchronously so the platform message loop can process cancellation.
Windows still needs native build and hardware validation.

## Windows setup

The host application supplies Windows App SDK 2.0+ runtime deployment,
C++/WinRT projections and package capabilities. Enable the plugin with
`FLUTTER_LOCAL_AI_WINDOWS_AI` and `FLUTTER_LOCAL_AI_WINRT_INCLUDE_DIR`.
See the [full setup and readiness review](../../doc/gemma-readiness.md).
The default build reports `windowsAiFoundryUnconfigured`.

## Web setup

There is no script tag to add: `LanguageModel` is a global the browser exposes
when the Prompt API is enabled. What you need is for it to be *on*:

- **Production** — register for the [Prompt API origin
  trial](https://developer.chrome.com/origintrials) and add the token to
  `web/index.html`:
  ```html
  <meta http-equiv="origin-trial" content="YOUR_TOKEN_HERE">
  ```
- **Local development** — enable
  `chrome://flags/#prompt-api-for-gemini-nano` and restart Chrome.

Whether the Prompt API is still gated on ordinary web pages changes over time,
so probe with `LocalAi.availability()` rather than assuming.

## Troubleshooting

`LocalAi.availability()` and `LocalAi.ensureReady()` report a
`LocalAiAvailability`; `ensureReady` throws `LocalAiUnavailableException`
carrying the status that caused the failure.

| Status | Meaning | What the user can do |
|---|---|---|
| `available` | Ready now. | — |
| `downloadable` | The feature exists but isn't downloaded. | `LocalAi.ensureReady()` fetches it and reports progress. |
| `downloading` | A download is already running. | `LocalAi.ensureReady()` waits for it; it starts no second one. |
| `unavailableDeviceUnsupported` | No AICore, no Apple Intelligence hardware, no Copilot+ NPU, or no Prompt API. | Fall back to a bundled model. |
| `unavailableOsTooOld` | The OS is below the model's floor. | Update the OS, or fall back. |
| `unavailableDisabled` | Present but switched off. | Enable Apple Intelligence in Settings, or the AICore toggle. |
| `unavailableOther` | Unclassified. | Fall back; check device logs. Chrome's bare `'unavailable'` lands here — it does not say why. |

`ensureReady()` throws immediately for every `unavailable*` status without
attempting a download: none of them can be fixed by waiting.

## Migrating from flutter_gemma_builtin_ai

Replace the dependency and import, and register only one built-in engine.
This adapter requires Flutter 3.44 / Dart 3.12 and targets Gemma 1.8.
The old public names are exported as aliases:

```dart
// import 'package:flutter_gemma_builtin_ai/flutter_gemma_builtin_ai.dart';
import 'package:flutter_gemma_local_ai/flutter_gemma_local_ai.dart';

await FlutterGemma.initialize(inferenceEngines: const [BuiltInAiEngine()]);
await BuiltInAi.ensureReady();
```

`BuiltInAiEngine`, `BuiltInAi`, `BuiltInAiModels`, `BuiltInAiAvailability` and
`BuiltInAiUnavailableException`, plus `BuiltInAiHuggingFaceResolver`, all keep working. New code should use the
`LocalAi*` names, which also reach Windows and the extra model specs.

## Keeping flutter_local_ai features

Native tools, dynamic schema output, per-call options and genUI remain in
flutter_local_ai. Use `LocalAiGemmaModel.localAiModel` to open a native session,
or `LocalAiGemmaSession.localAiSession` for structured output on an existing
session. Gate optional functionality on `LocalAi.capabilities()`.

`LocalAiUiGenerator` can run alongside Gemma chats without replacing their
conversations. Its `genUiInstructions` and `parseModelOutput` also let a
downloaded Gemma fallback produce the same UI specs. See the
[integration review](../../doc/gemma-readiness.md) for examples, tests and
features not yet exposed from the latest OS APIs.

## License

MIT
