# flutter_gemma_local_ai

A [flutter_gemma](https://pub.dev/packages/flutter_gemma) inference engine that
runs against the **model the platform already ships**, instead of a bundled
Gemma checkpoint — Gemini Nano through ML Kit GenAI on Android, Apple
Foundation Models on iOS and macOS, Windows AI Foundry on Windows, and Gemini
Nano through the Chrome Prompt API on the web.

Nothing is downloaded and nothing is bundled: the OS owns the weights.
Installing a built-in model records which one you want, and
`LocalAi.ensureReady()` makes sure the feature itself is switched on.

The engine is a thin adapter over
[flutter_local_ai](https://pub.dev/packages/flutter_local_ai), which owns the
native code for all four platforms.

## Supported platforms

| Platform | Model | Minimum | Notes |
|---|---|---|---|
| Android | Gemini Nano (ML Kit GenAI / AICore) | Pixel 9+, Galaxy S25+ | Needs `minSdk 26` |
| iOS / macOS | Apple Foundation Models | iPhone 15 Pro+, Apple silicon Macs | Needs Apple Intelligence enabled in Settings; OS 26+ |
| Windows | Windows AI Foundry (Phi Silica) | Windows 11 24H2, Copilot+ PC | Needs the Windows AI SDK headers — see below |
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
| Vision (image input) | ✅ | ❌ needs OS 27 | ❌ | ❌ |
| Audio input | ❌ | ❌ | ❌ | ❌ |
| Function calling | ✅ prompt-based | ✅ prompt-based | ✅ prompt-based | ✅ prompt-based |
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

Windows streaming arrives as a single chunk followed by completion. The
Flutter Windows embedding requires the event sink to be used from the platform
thread, and this plugin has no task runner to marshal back through, so the
generation call is awaited synchronously. The stream API is honest about
finishing; it just is not incremental.

## Windows setup

Windows AI is compile-gated. Until the WinRT headers are present the backend
reports itself as `windowsAiFoundryUnconfigured` and refuses to generate,
rather than silently doing nothing. To enable it, generate the headers with
`cppwinrt.exe` (or install the Windows AI SDK NuGet package), add them to the
plugin's include path, and build with `WINDOWS_AI_AVAILABLE=1`.

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

Change the import. The old names are exported as aliases:

```dart
// import 'package:flutter_gemma_builtin_ai/flutter_gemma_builtin_ai.dart';
import 'package:flutter_gemma_local_ai/flutter_gemma_local_ai.dart';

await FlutterGemma.initialize(inferenceEngines: const [BuiltInAiEngine()]);
await BuiltInAi.ensureReady();
```

`BuiltInAiEngine`, `BuiltInAi`, `BuiltInAiModels`, `BuiltInAiAvailability` and
`BuiltInAiUnavailableException` all keep working. New code should use the
`LocalAi*` names, which also reach Windows and the extra model specs.

## License

MIT
