<div align="center">
  <img src="logo.png" alt="flutter_local_ai logo" width="200">
</div>

<div align="center">

# Flutter Local AI

A Flutter package that provides a unified API for local AI inference on Android with [*ML Kit GenAI*](https://developers.google.com/ml-kit/genai), on Apple Platforms using [*Foundation Models*](https://developer.apple.com/documentation/FoundationModels), and on Windows using [*Windows AI APIs*](https://learn.microsoft.com/en-us/windows/ai/) (Windows AI Foundry).

Text generation (blocking or streamed), structured JSON outputs, tool calling, and **generative UI**: the on-device model can design small typed-block UI modules that render with the [`genui`](https://pub.dev/packages/genui) runtime — and, with tool calls, operate them afterwards.

`#ai` `#genui` `#structured-outputs` `#on-device-ai` `#gemini-nano` `#foundation-models`

</div>

<div align="center">
  <img src="video.gif" alt="flutter_local_ai video" width="200">
</div>



## ✨ Unique Advantage

**This package uses OS-managed models through native APIs, with no app-bundled model checkpoint.**

- **iOS**: Uses Apple's built-in FoundationModels framework (iOS 26.0+) - system-managed preparation may be required
- **Android**: Uses Google's ML Kit GenAI (Gemini Nano) - leverages the native on-device model
- **Windows**: Uses Windows AI APIs (Windows AI Foundry) - the build resolves the Windows App SDK itself; running needs a Copilot+ PC or supported GPU and a packaged app
- **Web**: Uses Chrome's Prompt API (Gemini Nano in the browser) - no script to load and no model to ship; the API is still trialled, so it needs an origin-trial token or a Chrome flag
- **No bundled checkpoints**: The OS may download model assets during preparation
- **Native Performance**: Direct access to OS-optimized AI capabilities
- **Smaller App Size**: The OS manages model weights; the app still includes the plugin and SDK dependencies
- **Structured Outputs**: On Apple platforms, Windows and Chrome, constrain generation to a JSON Schema and read the decoded object with `AiResponse.json`
- **Generative UI**: Turn a natural-language goal into a renderable [`genui`](https://pub.dev/packages/genui) module spec, on-device, identically on Apple FoundationModels and Android Gemini Nano (Pixel, Samsung, Xiaomi, OnePlus and [more](https://developers.google.com/ml-kit/genai))

## Platform Support

| Feature            | iOS / macOS (26+) | Android (API 26+) | Windows (11 25H2+, Copilot+ / supported GPU) | Web (Chrome) |
|--------------------|-------------------|-------------------|--------------------|--------------|
| Text generation    | ✅                | ✅                 | ⚠️ unverified on device | ✅      |
| Streaming          | ✅                | ✅                 | ⚠️ single chunk    | ✅           |
| Structured outputs | ✅                | ❌ ML Kit is compile-time only | ⚠️ native, unverified | ✅ |
| Image input        | ⚠️ OS 27 SDK + runtime    | ✅                 | ❌                 | ❌           |
| Generative UI (genUI) | ✅             | ✅                 | 🚧 Planned         | 🚧 Planned   |
| Summarization*     | 🚧 Planned        | 🚧 Planned         | 🚧 Planned         | 🚧 Planned   |
| Image generation   | 🚧 Planned        | ❌                 | 🚧 Planned         | ❌           |
| Tool calls         | ✅ native         | ❌ no ML Kit API   | ❌ no Windows AI API | ❌         |
| Exact token counts | ✅ OS 26.4+       | ✅                 | ❌ estimate        | ✅           |
| Concurrent sessions | ✅               | ✅                 | ✅                 | ✅           |

*Summarization is achieved through text-generation prompts and shares the same API surface.

"Unverified" means the code compiles against the vendor SDK but has not yet
run on a device that meets the vendor's hardware requirements; see
[known limitations and fallbacks](#known-limitations-and-fallbacks) for what
each ❌ is blocked on, and [platform support](doc/platform-support.md) for the
detail.

Every row is a *runtime* property, not a build-time one — the same binary
reports image input as unavailable on iOS 26; an OS 27 SDK build can enable
it on iOS 27. That new branch still needs Xcode 27/device validation. Ask the
device rather than the platform:

```dart
final caps = await LocalAi.capabilities();
if (caps.supportsVision) { /* ... */ }
```

## Two APIs

Two surfaces, one implementation: the prompt-oriented API is a facade over
the session layer, not a second code path. Pick by what you need.

**`FlutterLocalAi`** — the original one-shot API. One process-wide session,
`generateText` / `generateTextStream`, native tool calling, schema-constrained
output, genUI specs. Unchanged and fully supported.

**`LocalAiModel` / `LocalAiSession`** — the session API. Several independent
conversations at once, a turn built from parts (`addQueryChunk`, `addImage`)
and then generated, real cancellation, exact token counts, and explicit
lifecycle. This is the surface that adapters can use to share the same
native implementation.

```dart
await LocalAi.ensureReady(onProgress: (p) => debugPrint('$p%'));

final model = await LocalAiModel.create(maxTokens: 4096);
final session = await model.openSession(systemInstruction: 'Be concise.');

await session.addQueryChunk('Summarize this in one line: ...');
await for (final chunk in session.getResponseAsync()) {
  stdout.write(chunk);
}

await session.close();
await model.close();
```

## Relationship to flutter_gemma

This is a standalone plugin: it depends on no `flutter_gemma` package, and
owns its native backends and Chrome Prompt API arm outright. The bridge that
lets flutter_gemma treat the OS model as one of its inference engines is
[`flutter_gemma_builtin_ai`](https://github.com/DenisovAV/flutter_gemma/tree/main/packages/flutter_gemma_builtin_ai),
which lives in the flutter_gemma repository — so a flutter_gemma interface
change and the bridge that follows it ship together, in one upstream PR. The
dependency only ever points that way: the bridge may depend on this package,
this package never depends on flutter_gemma. If you already use that package,
nothing changes: it keeps its own name, imports and `BuiltInAi*` API. If you
only want the OS model, depend on this package alone and skip flutter_gemma's
plugin, downloader and SDK floor.

See [platform support](doc/platform-support.md) for what each backend can
actually do, what it needs at build time, and what has been verified.

## Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  flutter_local_ai:
    git:
      url: https://github.com/kekko7072/flutter_local_ai.git
```

Or if published to pub.dev:

```yaml
dependencies:
  flutter_local_ai: latest
```

### Android setup

Use `minSdk = 26` and Kotlin **2.3.21** in the consuming app. ML Kit Prompt
API beta4 is built with Kotlin 2.3 metadata. See the repository's Android
example for a complete configuration. Use the current compiler DSL:

```kotlin
kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
    }
}
```

The plugin supplies `com.google.mlkit:genai-prompt:1.0.0-beta4` and its
transitive dependencies; do not copy older ML Kit version pins into the app.
Compatible AICore hardware and model availability are required for inference.
API 26 is an installation floor, not a hardware compatibility guarantee.
Use `LocalAi.availability()` / `LocalAi.ensureReady()` and Google's current
[Prompt API setup guide](https://developers.google.com/ml-kit/genai/prompt/android/get-started).

### Apple setup

The native plugin's deployment floors remain iOS 13 and macOS 12, so an app
can offer a fallback on older systems. Flutter and other dependencies may
set a higher app floor. Inference requires **iOS/macOS 26+**, eligible Apple
Intelligence hardware, enabled Apple Intelligence, and ready model assets.

Build with Xcode 26 or newer for Foundation Models. Xcode 26.4 plus OS 26.4
enables exact token counts. Image input is guarded behind the OS 27 SDK /
Swift 6.4 compiler and OS 27 runtime; that branch still needs validation with
Xcode 27. Always inspect `LocalAi.capabilities()` before enabling images.

### Windows setup

No CMake or NuGet work is needed to *build*: `flutter build windows` resolves
the Windows App SDK's C++/WinRT projection on its own. It looks for
`Microsoft.WindowsAppSDK.AI` and `Microsoft.Windows.CppWinRT` in the local
NuGet cache, downloads them from nuget.org into the build tree when they are
not there, generates the projection with `cppwinrt.exe`, and compiles the
Windows AI arm. When that cannot happen — no network and no cache — the build
prints a `flutter_local_ai:` warning and falls back to the unconfigured plugin,
which reports `windowsAiFoundryUnconfigured` at runtime instead of failing to
compile. Environment variables steer it without touching CMake:

| Variable | Effect |
|---|---|
| `FLUTTER_LOCAL_AI_WINDOWS_AI` | `AUTO` (default), `ON` (a missing projection fails the build) or `OFF` (skip, no download) |
| `FLUTTER_LOCAL_AI_NUGET_DOWNLOAD` | `OFF` to forbid the nuget.org download and rely on the NuGet cache |
| `FLUTTER_LOCAL_AI_WINRT_INCLUDE_DIR` | A projection you generated yourself (contains `winrt/Microsoft.Windows.AI.Text.h`) |

The full list, including pinning the SDK version, is in
[doc/platform-support.md](doc/platform-support.md#build-requirements).

*Running* is gated by Microsoft, not by the build, and none of it can be
automated by a plugin:

- **Hardware and OS.** A Copilot+ PC (NPU), or an NVIDIA RTX 30+/AMD Radeon
  GPU with the vendor's latest driver and Developer Mode on; Windows 11 25H2
  (build 26200.7309) or later.
- **Package identity.** Windows AI APIs refuse unpackaged processes. Package
  the app as MSIX (the [`msix`](https://pub.dev/packages/msix) package builds
  one from a Flutter app), then add the `systemAIModels` capability, the
  `Microsoft.WindowsAppRuntime` framework dependency for the SDK version you
  built against, and a `MaxVersionTested` of at least `10.0.26226.0` to its
  `AppxManifest.xml` — `dart run msix:build`, edit, `dart run msix:pack`. A
  plain `flutter run` therefore reports `unavailableOther`, and
  `LocalAi.availabilityReason()` names the activation failure.
- **Windows App Runtime.** Framework-dependent MSIX pulls it in; otherwise
  install it from Microsoft's runtime installer. The stable channel also
  needs a Limited Access Feature token from Microsoft for Phi Silica; the
  experimental channel does not.

[Microsoft's setup guide](https://learn.microsoft.com/en-us/windows/ai/apis/get-started)
and [troubleshooting page](https://learn.microsoft.com/en-us/windows/ai/apis/troubleshooting)
are the source of truth for these. Preparation may download large
system-managed assets. Streaming currently delivers one final chunk while
inference runs asynchronously; cancellation targets the active WinRT operation.
The Windows arm compiles in CI but has not yet run on qualifying hardware —
treat it as unverified until it has.

### Web (Chrome) setup

There is nothing to add to the build. The plugin declares web support in its
pubspec, and the web arm talks to Chrome's **Prompt API** (`self.LanguageModel`)
straight through `dart:js_interop` — no platform channel, no `<script>` tag in
`index.html`, no asset to host. `flutter build web` picks the arm up on its own,
and a build for another platform is unaffected.

*Running* is gated by the browser, not by the build:

- **Browser.** A desktop Chromium-based browser (Chrome or Edge) that exposes
  the Prompt API. The API is still trialled, so it appears either behind an
  [origin-trial token](https://developer.chrome.com/docs/ai/prompt-api) for
  your site or, for local development, behind
  `chrome://flags/#prompt-api-for-gemini-nano`. Firefox, Safari and mobile
  Chrome do not define `LanguageModel` at all; the arm reports
  `unavailableDeviceUnsupported` there instead of throwing.
- **Device.** Chrome's own floors for Gemini Nano — roughly 22 GB free disk
  and an eligible GPU. Chrome collapses every one of those into a bare
  `'unavailable'` with no reason attached, which is why
  `LocalAi.availabilityReason()` returns the list of common causes rather
  than a single diagnosis.
- **Download.** The weights are the browser's, not the app's.
  `LocalAi.ensureReady()` creates a throwaway session to trigger (and dedupe)
  Chrome's download and reports progress as a 0-100 fraction shaped like the
  native hosts' byte pair.

Probe before you use it, exactly as on the other platforms:

```dart
if (await LocalAi.availability() != LocalAiAvailability.available) {
  print(await LocalAi.availabilityReason());
  return; // fall back to a server or a bundled model
}
```

What the web arm does and does not do, all of it reported by
`LocalAi.capabilities()` rather than assumed:

| Works | Does not |
|---|---|
| Text generation and incremental streaming deltas | Image input — the Prompt API's multimodal path is not usable from an ordinary page as of Chrome 151, and `addImage` throws |
| Cancellation of any in-flight request (`AbortController`) | Native tool calling — the `tools` option is behind an experimental flag and does not reliably route, so `openSession(tools: …)` throws rather than emulating one |
| Schema-constrained output via `responseConstraint`, which Android cannot do | Per-call `LocalAiGenerationOverrides` — Chrome fixes sampling at `create()`, so the host warns once and generates with the session's own settings |
| Exact token counts (`measureContextUsage`, or `measureInputUsage` on older builds), measured against an open session | `topP` and `maxOutputTokens` — accepted for API parity and dropped, not faked |
| Several concurrent sessions | Two turns at once *in one session*: Chrome runs one at a time, and a second `generate` throws instead of racing |

Two behaviours differ from Android and Windows and are worth knowing before
you port code. Chrome's `LanguageModel` session keeps the transcript itself,
so this host sends only the pending turn — replaying the history, as the
stateless native APIs require, would feed every earlier message back a second
time. And the context limit is therefore the browser session's `inputQuota`,
not something this package trims. Sampling above what the browser advertises
is clamped to its ceiling (with a one-time warning) instead of failing the
`create()`.

`flutter_local_ai`'s own example app has no `web/` target checked in yet; run
`flutter create --platforms web .` inside `example/` to add one before
`flutter run -d chrome`.

## Usage

> Availability also depends on hardware, model preparation, user settings and SDK configuration. Gate optional features on runtime capabilities.

### Basic Usage

```dart
import 'package:flutter_local_ai/flutter_local_ai.dart';

// Initialize the AI engine
final aiEngine = FlutterLocalAi();

// Check if Local AI is available on this device
final isAvailable = await aiEngine.isAvailable();
if (!isAvailable) {
  print('Local AI is not available on this device');
  print('iOS/macOS: Requires iOS 26.0+ or macOS 26.0+');
  print('Android: Requires API 26+ and Google AICore installed');
  print('Windows: Requires a Copilot+ PC or supported GPU, Windows 11 25H2+, and a packaged app');
  return;
}

// Initialize the model with custom instructions
// This is required and creates a LanguageModelSession
await aiEngine.initialize(
  instructions: 'You are a helpful assistant. Provide concise answers.',
);

// Generate text with the simple method (returns just the text string)
final text = await aiEngine.generateTextSimple(
  prompt: 'Write a short story about a robot',
  maxTokens: 200,
);
print(text);
```

### Advanced Usage with Configuration

```dart
import 'package:flutter_local_ai/flutter_local_ai.dart';

final aiEngine = FlutterLocalAi();

// Check availability
if (!await aiEngine.isAvailable()) {
  print('Local AI is not available on this device');
  return;
}

// Initialize with custom instructions
await aiEngine.initialize(
  instructions: 'You are an expert in science and technology. Provide detailed, accurate explanations.',
);

// Generate text with detailed configuration
final response = await aiEngine.generateText(
  prompt: 'Explain quantum computing in simple terms',
  config: const GenerationConfig(
    maxTokens: 300,
    temperature: 0.7,  // Controls randomness (0.0 = deterministic, 1.0 = very random)
    topP: 0.9,         // Nucleus sampling parameter
    topK: 40,          // Top-K sampling parameter
  ),
);

// Access detailed response information
print('Generated text: ${response.text}');
print('Token count: ${response.tokenCount}');
print('Generation time: ${response.generationTimeMs}ms');
```

### Tool Calls (Apple platforms)

Tool calling lets the on-device model invoke Dart functions you define. Define tools in Dart, register them, and return JSON-serializable data from the handler:

- **iOS 26.0+ / macOS 26.0+**: native — tools are passed to Apple FoundationModels as `Tool` objects with a generation schema, so the model is constrained to produce valid calls.
- **Android**: Native Dart tool callbacks are not bridged by this package. `registerTools` fails on this backend; gate on `getPlatformInfo().supportsToolCalling`. Current Kotlin SDK capabilities and experimental reference APIs must not be assumed to work through Dart automatically.

Register an empty list to disable tool use again.

```dart
import 'package:flutter_local_ai/flutter_local_ai.dart';

final aiEngine = FlutterLocalAi();

await aiEngine.registerTools([
  LocalAiTool(
    name: 'searchBreadDatabase',
    description: 'Searches a local database for bread recipes.',
    parameters: const [
      ToolParameter(
        name: 'searchTerm',
        type: ToolArgumentType.string,
        description: 'Type of bread to search for',
      ),
      ToolParameter(
        name: 'limit',
        type: ToolArgumentType.integer,
        description: 'Number of recipes to return',
      ),
    ],
    onCall: (arguments) async {
      final term = arguments['searchTerm'] as String? ?? '';
      final limit = (arguments['limit'] as num?)?.toInt() ?? 3;
      // Replace with your own lookup logic.
      return List.generate(
        limit,
        (index) => 'Recipe ${index + 1} for "$term"',
      );
    },
  ),
]);

await aiEngine.initialize(
  instructions: 'You are a helpful baking assistant. Use tools when needed.',
);

final response = await aiEngine.generateText(
  prompt: 'Find 2 sourdough recipes I might like.',
);
print(response.text);
```

#### Declarations that need more than a scalar

The flat `parameters` list covers scalars. When a parameter is a set of named
choices, a list, or a nested object, declare the whole thing as JSON Schema
with `parameterSchema` instead — the same subset `GenerationConfig.schema`
accepts, translated by the same native builder, so on Apple the model is
*constrained* to the declaration rather than asked to respect it:

```dart
LocalAiTool(
  name: 'paintWall',
  description: 'Paints a wall in one of the stocked colours.',
  parameterSchema: const {
    'type': 'object',
    'properties': {
      'colour': {
        'description': 'One of the stocked colours',
        'enum': ['red', 'green', 'blue', 'white', 'black', 'teal'],
      },
      'coats': {'type': 'integer'},
      'trim': {
        'type': 'object',
        'properties': {
          'colour': {'type': 'string'},
          'gloss': {'type': 'boolean'},
        },
        'required': ['colour'],
      },
    },
    'required': ['colour'],
  },
  onCall: (arguments) async => {'ok': true},
);
```

Supply `parameters` or `parameterSchema`, never both. The schema is validated
in Dart before the platform channel, so an unsupported construct fails with a
path-qualified `ArgumentError` naming the tool.

#### What `onCall` may do

- **Take as long as it needs.** The native host suspends the turn for the
  whole of `onCall` and imposes no timeout, so waiting on a human to approve
  an action is supported. A confirm-before-acting flow is written by returning
  a `Future` that completes when the user answers.
- **Be cancelled.** `session.stopGeneration()` unwinds a suspended tool call
  instead of waiting for it; the `Future` is abandoned, so a tool holding a
  resource releases it itself.
- **Refuse.** Throwing `LocalAiToolException` — or any exception — hands the
  model a readable `{"error": "..."}` tool result rather than failing the
  turn, which is what a declined confirmation or a permission error should
  look like in an agent loop:

  ```dart
  onCall: (arguments) async {
    if (!await confirmWithUser()) {
      throw const LocalAiToolException('The user declined this action.');
    }
    return {'ok': true};
  }
  ```

### Structured Outputs (Apple platforms)

Pass a JSON Schema through `GenerationConfig` to *constrain* generation to valid
JSON instead of free-form text. On Apple FoundationModels this uses the same
schema-constrained generation that powers tool calling, so the model is forced to
emit a value matching your schema.

- **iOS 26.0+ / macOS 26.0+**: native. The schema is translated into a
  FoundationModels `GenerationSchema` and the JSON is returned in
  `AiResponse.text`; use `AiResponse.json` to get it decoded as a `Map`.
- **Windows**: native, through `LanguageModel.GenerateStructuredJsonResponseAsync`
  (Windows App SDK 2.0+). The schema is passed to the OS as JSON Schema text.
  A response the OS finishes but that strays from the schema throws
  `STRUCTURED_OUTPUT_INVALID`, with the model's text in the error `details`.
  Compiled in CI, not yet run on qualifying hardware.
- **Android**: not available. ML Kit's structured output is generated at
  compile time from annotated Kotlin classes (KSP); there is no runtime schema
  API for a Dart map to be translated into. Supplying a `schema` (or
  `responseFormat: ResponseFormat.json`) throws `STRUCTURED_OUTPUT_UNSUPPORTED`.
  Gate on `getPlatformInfo().supportsStructuredOutput` in cross-platform code.

Supported schema constructs: nested objects (with `required`), arrays (including
`minItems` / `maxItems`), string enums, and the scalar types (`string`,
`integer`, `number`, `boolean`). `description` is honored on properties. A schema
using any construct outside this subset is rejected with an `ArgumentError` in
Dart — before the platform channel — so you get a clear, path-qualified message
instead of an opaque native failure.

Supplying a `schema` implies JSON mode: you don't need to also set
`responseFormat: ResponseFormat.json` (though you can), and the value sent to the
backend is always self-consistent.

> **Streaming:** schema-constrained output is **not** available through
> `generateTextStream` on any backend yet. Apple's native structured streaming
> API is not exposed by this package. Passing a `schema` to
> `generateTextStream` returns a stream that errors immediately — use
> `generateText` for structured output, or stream without a schema.

```dart
final platform = await aiEngine.getPlatformInfo();
if (!platform.supportsStructuredOutput) {
  // Fall back to text generation or a backend-specific parser.
  return;
}

final response = await aiEngine.generateText(
  prompt: 'Summarize this support ticket: "App crashes on launch after update."',
  config: const GenerationConfig(
    maxTokens: 300,
    responseFormat: ResponseFormat.json, // default is ResponseFormat.text
    schema: {
      'type': 'object',
      'properties': {
        'title': {'type': 'string', 'description': 'Short headline'},
        'priority': {
          'enum': ['low', 'med', 'high'],
        },
        'tags': {
          'type': 'array',
          'items': {'type': 'string'},
        },
      },
      'required': ['title'],
    },
  ),
);

final data = response.json; // Map<String, dynamic>? — decoded JSON object
print(data?['title']);

// For a schema whose root is an array or scalar, use decodedJson instead —
// .json only returns object roots.
final value = response.decodedJson; // Object? — any decoded JSON value
```

> Note: `ResponseFormat.json` requires a non-null `schema` — Apple can only
> constrain output when given a schema to constrain it to.

### Generative UI (genUI)

`flutter_local_ai` can turn a natural-language goal into a small, renderable UI
module entirely on-device. The local model decides which typed blocks best
express the goal and emits a JSON spec, which you can render with the
[`genui`](https://pub.dev/packages/genui) runtime or your own widgets.

The same typed-block schema and renderer work on Apple Foundation Models and
Android Gemini Nano. Each module uses a short-lived session with its own
instructions, preserving ongoing chats. Android uses native system
instructions when AICore supports them, otherwise a prompt prefix. Generation
uses a 900-token budget and compact JSON; output is parsed and validated
before rendering. Model quality and platform capabilities still differ.

```dart
import 'package:flutter_local_ai/flutter_local_ai.dart';

final aiEngine = FlutterLocalAi();
final generator = LocalAiUiGenerator(aiEngine);

// Generate a module from a goal. Returns null on any failure (model
// unavailable, generation blocked, invalid output) so you can fall back to a
// deterministic UI.
final GenUiModuleSpec? module = await generator.generateModule(
  'Save \$500 for a weekend trip',
  principles: 'Keep it simple and low-pressure', // optional design steering
  language: 'Italian',          // optional: force all user-facing copy
  onText: (raw) => print(raw),  // optional: live decode for progress UI
);

if (module == null) {
  // Inspect why and fall back.
  debugPrint('genUI unavailable: ${generator.lastError}');
} else {
  print(module.title);                 // e.g. "Weekend trip fund"
  print(module.blocks);                 // typed blocks: amount, progress, ...
  final json = module.toModuleJson();   // shape for your renderer
  // final components = module.toComponentMaps(); // A2UI tree, as plain maps
}

// The detected backend is available for labelling.
print(generator.backend); // LocalAiBackend.androidMlKitGenAi / appleFoundationModels
```

A `GenUiModuleSpec` is a stack of typed blocks (`amount`, `progress`,
`checklist`, `week`, `stat`, `list`, `lessons`, `reminder`, `calc`, `docs`,
`note`) that the model picks to fit the goal. The output is validated before it
is returned, and on small on-device models a truncated response is repaired
where possible so a partial module still renders.

#### genUI + tool calls: generated UI the model can operate (Apple platforms)

The two features compose: generate a module with `LocalAiUiGenerator`, then
register the module's mutations as tools — the same on-device model that
designed the UI can now act on it from natural language ("add 50 to the trip
fund"), with your `onCall` handlers applying the state changes:

```dart
// 1. The generated module's state lives in your app (here: a progress block).
var value = 300.0;

// 2. Expose its mutations as tools for one chat turn.
await aiEngine.registerTools([
  LocalAiTool(
    name: 'add_to_progress',
    description: 'Add an amount to the savings progress.',
    parameters: const [
      ToolParameter(
        name: 'amount',
        type: ToolArgumentType.number,
        description: 'Amount to add',
      ),
    ],
    onCall: (args) {
      value += (args['amount'] as num).toDouble();
      return {'ok': true, 'value': value}; // grounds the model's confirmation
    },
  ),
]);

// 3. One generation = the whole turn: the model calls the tool, reads the
//    result, and answers in plain text. Scope the registration to the turn —
//    clear it afterwards so later generations (e.g. genUI) stay tool-free.
try {
  final res = await aiEngine.generateText(
    prompt: 'CURRENT STATE: {"value": $value, "target": 600}\n\n'
        'USER MESSAGE: "add 50 to my trip fund"',
    instructions: 'You operate a savings tracker. Use the tools to apply '
        'changes, then confirm in one short sentence.',
  );
  print(res.text); // "Done — your trip fund is at $350 of $600."
} finally {
  await aiEngine.registerTools(const []);
}
```

This is the pattern behind a genUI chat: hand the model the module state (the
`toModuleJson()` shape) plus per-block tools, and every dashboard edit the UI
can do becomes something the model can do too.

#### Reusing the genUI engine with other backends

The schema and parser are exposed as statics so any on-device backend (for
example a downloaded Gemma model via `flutter_gemma`) can drive the exact same
genUI generation:

```dart
// The system instructions (module/block schema) to pass to your own model.
final instructions = LocalAiUiGenerator.genUiInstructions;

// Parse and validate raw model text into a GenUiModuleSpec (handles code
// fences, leading/trailing prose, and truncated/closing-bracket repair).
final GenUiModuleSpec? spec = LocalAiUiGenerator.parseModelOutput(rawModelText);
```

### Streaming Text Generation

`generateTextStream` yields delta chunks as the model decodes — ideal for
typing the answer into the UI live, or for the genUI generator's `onText`
preview. On Apple it maps to FoundationModels' streamed snapshots, on Android
to ML Kit's `StreamingCallback`.

```dart
final buffer = StringBuffer();
await for (final chunk in aiEngine.generateTextStream(
  prompt: 'Write a two-line poem about autumn',
  config: const GenerationConfig(maxTokens: 120, temperature: 0.7),
  instructions: 'You are a poet.', // optional one-shot session, see below
)) {
  buffer.write(chunk);
  print(buffer); // cumulative text so far
}
```

Notes:
- The optional `instructions:` parameter (also on `generateText`) runs the call
  in a **one-shot throwaway session** with exactly those instructions — nothing
  accumulates in the session created by `initialize`. Use it for stateless
  callers that carry their own context in the prompt (on Apple, a shared
  session's transcript counts toward the 4096-token context window).

### Complete Example

Here's a complete example showing error handling and best practices:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_local_ai/flutter_local_ai.dart';

class LocalAiExample extends StatefulWidget {
  @override
  _LocalAiExampleState createState() => _LocalAiExampleState();
}

class _LocalAiExampleState extends State<LocalAiExample> {
  final aiEngine = FlutterLocalAi();
  bool isInitialized = false;
  String? result;
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _initializeAi();
  }

  Future<void> _initializeAi() async {
    try {
      final isAvailable = await aiEngine.isAvailable();
      if (!isAvailable) {
        setState(() {
          result = 'Local AI is not available on this device. Requires iOS 26.0+ or macOS 26.0+';
        });
        return;
      }

      await aiEngine.initialize(
        instructions: 'You are a helpful assistant. Provide concise and accurate answers.',
      );

      setState(() {
        isInitialized = true;
        result = 'AI initialized successfully!';
      });
    } catch (e) {
      setState(() {
        result = 'Error initializing AI: $e';
      });
    }
  }

  Future<void> _generateText(String prompt) async {
    if (!isInitialized) {
      setState(() {
        result = 'AI is not initialized yet';
      });
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      final response = await aiEngine.generateText(
        prompt: prompt,
        config: const GenerationConfig(
          maxTokens: 200,
          temperature: 0.7,
        ),
      );

      setState(() {
        result = response.text;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        result = 'Error generating text: $e';
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Flutter Local AI')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            ElevatedButton(
              onPressed: isLoading ? null : () => _generateText('Tell me a joke'),
              child: const Text('Generate Joke'),
            ),
            const SizedBox(height: 20),
            if (isLoading)
              const CircularProgressIndicator()
            else if (result != null)
              Text(result!),
          ],
        ),
      ),
    );
  }
}
```

### Platform-Specific Notes

#### iOS & macOS

- **Initialization**: Call `initialize()` to set shared conversation instructions, or pass per-call instructions for an independent turn.
- **Session reuse**: The session is cached and reused for subsequent generation calls until you call `initialize()` again with new instructions.
- **Automatic fallback**: If you don't call `initialize()` explicitly, it will be called automatically with default instructions when you first generate text. However, it's recommended to call it explicitly to set your custom instructions.
- **Model availability**: Requires OS 26+, eligible hardware and enabled, ready Apple Intelligence.
- **Structured outputs and tool calls**: Both are native FoundationModels features. Check `getPlatformInfo().supportsStructuredOutput` before passing a schema in cross-platform code.

#### Android

- **AICore Required**: Google AICore must be installed on the device for ML Kit GenAI to work
- **Availability Check**: Always call `isAvailable()` before using AI features
- **Error Handling**: Handle error code -101 (AICore not installed) gracefully
- **Initialization**: `initialize()` is optional on Android but recommended for consistency
- **Model Access**: Uses Gemini Nano via ML Kit GenAI; model preparation can download system assets.
- **Structured outputs and tool calls**: ML Kit offers neither a runtime schema API nor function calling for Gemini Nano, so this package cannot bridge them; see [known limitations](#known-limitations-and-fallbacks). Gate these on capabilities.

#### Windows

- The build configures itself (see [Windows setup](#windows-setup)); the host app owns packaging, the `systemAIModels` capability and the Windows App Runtime.
- Probe availability before generation; OS version alone is insufficient, and `LocalAi.availabilityReason()` names an activation failure.
- Full responses and the one-chunk stream run asynchronously and can be cancelled.
- Structured output is native (`GenerateStructuredJsonResponseAsync`); native tools are not exposed by Windows AI.
- The arm compiles in CI; device validation on Copilot+ hardware remains a release requirement.

#### Web (Chrome)

- Nothing to configure at build time (see [Web setup](#web-chrome-setup)); the
  gates are the browser's — the Prompt API being enabled, disk space and GPU.
- `LocalAi.availabilityReason()` explains a missing `LanguageModel` global and
  Chrome's reasonless `'unavailable'`; `ensureReady()` drives the download.
- The browser session owns the conversation, so only the pending turn is sent
  and the context limit is its `inputQuota`.
- Structured output is native (`responseConstraint`); image input and tool
  calling are not exposed, and per-call sampling overrides cannot apply.
- One generation at a time per session; `stopGeneration()` aborts the request
  and settles the turn empty rather than throwing.

**Example with AICore Error Handling:**
```dart
final aiEngine = FlutterLocalAi();

try {
  final isAvailable = await aiEngine.isAvailable();
  if (!isAvailable) {
    // Show user-friendly message
    print('Local AI is not available. AICore may not be installed.');
    return;
  }
  
  await aiEngine.initialize(
    instructions: 'You are a helpful assistant.',
  );
  
  final response = await aiEngine.generateText(
    prompt: 'Hello!',
    config: const GenerationConfig(maxTokens: 100),
  );
  
  print(response.text);
} catch (e) {
  // Handle AICore error (-101)
  if (e.toString().contains('-101') || e.toString().contains('AICore')) {
    // Open Play Store to install AICore
    await aiEngine.openAICorePlayStore();
  } else {
    print('Error: $e');
  }
}
```

## Known limitations and fallbacks

Each of these is a property of the vendor API, not a gap this package can
close on its own. In every case the right move is to ask
`LocalAi.availability()` / `LocalAi.capabilities()` at runtime and fall back
to another backend — the flutter_gemma bridge above being the obvious one.

- **iOS and macOS below 26.** Apple Foundation Models exist only from OS 26,
  and no polyfill can conjure the system model on iOS 17 or 18. The package
  still installs and links on older OSes (its deployment floor is iOS 13 /
  macOS 12): `LocalAi.availability()` returns `unavailableOsTooOld`,
  `capabilities()` reports every feature as unsupported, and a call that
  needs the model throws a `LocalAiUnavailableException` rather than
  crashing. Ship a bundled-model fallback for those users, or gate the
  feature.
- **Android tool calls and structured output.** ML Kit's Prompt API has no
  function-calling surface for Gemini Nano, and its structured output is
  compiled from annotated Kotlin classes with KSP — there is no runtime
  schema object for a Dart map to become. A prompt-woven emulation was tried
  and rejected: Gemini Nano answered in prose instead of performing the call
  often enough that the capability flag would have lied.
- **Windows tool calls.** Windows AI Foundry exposes no function-calling API.
- **Web outside Chrome, and Chrome without the Prompt API.** The arm is the
  Prompt API; no other browser ships it, and Chrome itself exposes
  `LanguageModel` only behind an origin trial or a flag while the API is
  trialled. Without the global, `LocalAi.availability()` returns
  `unavailableDeviceUnsupported` and `capabilities()` reports the backend as
  unsupported — the page still builds and runs, so gate the feature and fall
  back. Image input and tool calling stay unavailable even where the API is
  enabled: Chrome's multimodal path is not reachable from an ordinary page,
  and its `tools` option is experimental and does not reliably route.
- **Bring-your-own models on Android and Windows.** Out of scope by design:
  this package is the OS-model layer, deliberately without a model
  downloader, GGUF loader or inference runtime. For Llama, Phi, Qwen and
  friends use [flutter_gemma](https://pub.dev/packages/flutter_gemma), whose
  [`flutter_gemma_builtin_ai`](https://github.com/DenisovAV/flutter_gemma/tree/main/packages/flutter_gemma_builtin_ai)
  bridge lets the OS model and a downloaded model sit behind one interface.

## API Reference

### `FlutterLocalAi`

Main class for interacting with local AI.

#### Methods

- `Future<bool> isAvailable()` - Check if local AI is available on the device
- `Future<String> availabilityReason()` - A human-readable reason when it is not (eligibility, model downloadable/downloading, OS version…)
- `Future<bool> initialize({String? instructions})` - Initialize the model and create a session with instruction text (required for iOS, recommended for Android)
- `Future<AiResponse> generateText({required String prompt, GenerationConfig? config, String? instructions})` - Generate text; per-call `instructions` run a one-shot throwaway session
- `Stream<String> generateTextStream({required String prompt, GenerationConfig? config, String? instructions})` - Generate text as a stream of delta chunks
- `Future<String> generateTextSimple({required String prompt, int maxTokens = 100})` - Convenience method to generate text and return just the string
- `Future<void> registerTools(List<LocalAiTool> tools)` - Register Dart tools the model may call during generation (Apple platforms only; pass `const []` to clear)
- `Future<LocalAiPlatformInfo> getPlatformInfo()` - The detected backend and its capabilities (`supportsToolCalling`, `supportsStructuredOutput`, `supportsModelDownload`, …)
- `Future<ModelFeatureStatus> getModelStatus()` - `available` / `downloadable` / `downloading` / `unavailable` (Android Gemini Nano)
- `Stream<ModelDownloadStatus> downloadModel()` - Request the one-time on-device model download and observe its progress; failures always surface on the stream
- `Future<bool> openAICorePlayStore()` - Open Google AICore in the Play Store (Android only, useful when error -101 occurs)

### `LocalAiTool` / `ToolParameter`

A Dart-defined tool the on-device model can invoke (see Tool Calls above).

- `LocalAiTool({required name, required description, parameters, parameterSchema, required onCall})` - `onCall` receives the model's arguments as a `Map<String, dynamic>` and returns JSON-serializable data fed back to the model. Declare parameters as either a flat `parameters` list or a `parameterSchema`, not both
- `ToolParameter({required name, type, description, optional})` - typed scalar parameter (`ToolArgumentType.string/integer/number/boolean`)
- `parameterSchema` (`Map<String, dynamic>?`) - the parameters as a JSON Schema object, for nested objects, arrays and string enums. Validated in Dart, then translated natively by the same builder that backs structured output
- `resolvedParameterSchema` - the declaration actually sent: `parameterSchema`, or the object schema the flat list describes
- `LocalAiToolException(message, {details})` - thrown from `onCall` to hand the model a readable tool error instead of failing the turn. Any other exception is reported the same way

### `GenerationConfig`

Configuration for text generation.

- `maxTokens` (int, default: 100) - Maximum number of tokens to generate
- `temperature` (double?, optional) - Temperature for generation (0.0 to 1.0)
- `topP` (double?, optional) - Top-p (nucleus) sampling. On Apple maps to `.random(probabilityThreshold:)`
- `topK` (int?, optional) - Top-k sampling. On Apple maps to `.random(top:)` and takes precedence over `topP`
- `responseFormat` (`ResponseFormat`, default: `text`) - `text` for free-form output, or `json` for schema-constrained JSON (Apple only). `json` requires a non-null `schema`
- `schema` (`Map<String, dynamic>?`, optional) - JSON Schema the output is constrained to (Apple only; see Structured Outputs above). Supplying a schema implies JSON mode and is validated in Dart before the platform channel

> Sampling precedence on Apple: topK > topP > temperature > greedy. `.greedy` is
> never combined with a temperature (that pairing throws on-device).

### `AiResponse`

Response from AI generation.

- `text` (String) - The generated text (or the JSON string when structured output was requested)
- `json` (`Map<String, dynamic>?`) - `text` decoded as a JSON object, or `null` if it isn't one
- `decodedJson` (`Object?`) - `text` decoded as any JSON value (object, array, scalar), or `null` if it isn't valid JSON — use for schemas whose root is an array or scalar
- `tokenCount` (int?) - Token count used
- `generationTimeMs` (int?) - Generation time in milliseconds

### `LocalAiPlatformInfo`

Detected backend metadata and capability flags returned by `getPlatformInfo()`.

- `backend` (`LocalAiBackend`) - The active backend (`appleFoundationModels`, `androidMlKitGenAi`, `windowsAiFoundry`, `windowsAiFoundryUnconfigured`, or `unsupported`)
- `supportsToolCalling` (bool) - Whether `registerTools` can expose Dart tools to the native model
- `supportsStructuredOutput` (bool) - Whether `GenerationConfig.schema` / `ResponseFormat.json` can constrain the model to JSON output
- `supportsModelDownload` (bool) - Whether `downloadModel()` can request an on-device model download
- `supportsPlayStoreRedirect` (bool) - Whether `openAICorePlayStore()` can redirect to Google AICore
- `isConfigured` (bool) - Whether the native backend is compiled/configured for the current platform

### `LocalAiUiGenerator`

Turns a natural-language goal into a `GenUiModuleSpec` using the on-device model
(Apple FoundationModels or Android ML Kit GenAI / Gemini Nano).

- `LocalAiUiGenerator([FlutterLocalAi? ai])` - Create a generator (reuses or creates an engine)
- `Future<GenUiModuleSpec?> generateModule(String goal, {String? principles, String? language, void Function(String)? onText})` - Generate a module; `language` forces all user-facing copy into that language, `onText` streams the raw decode for live progress UI; returns `null` on any failure
- `LocalAiBackend get backend` - The detected on-device backend
- `bool? get available` - Whether the model reported itself available (cached)
- `String? get lastError` - The last platform error encountered, for diagnostics
- `static String get genUiInstructions` - The module/block schema instructions, for reuse with other backends
- `static GenUiModuleSpec? parseModelOutput(String text)` - Parse + validate raw model text (handles fences, prose, truncation)

### `GenUiModuleSpec`

A validated genUI module produced by the local model.

- `title`, `icon`, `tone`, `blurb` (String) - Module header fields
- `blocks` (List<Map<String, dynamic>>) - Ordered typed blocks
- `Map<String, dynamic> toModuleJson()` - Shape for a typed-block renderer
- `List<Map<String, dynamic>> toComponentMaps()` - An A2UI component tree as
  plain `id`/`type`/`properties` maps. Wrap each entry in `genui`'s `Component`
  to feed a `Surface` — see the doc comment for the three-line adaptation.

## Implementation notes

Both public Dart APIs — and any external adapter written against them — use
one session host per platform. Each conversation has a distinct ID, and the
native resource remains alive until all model owners close. Android serializes
generation over the AICore client; Apple keeps separate Foundation Models
sessions. Windows uses C++/WinRT asynchronous operations from the Flutter
runner's STA.

Apple translates the supported dynamic JSON Schema subset to
`GenerationSchema` and binds Dart tools at session creation; Windows and web
hand the JSON Schema text to the OS (`GenerateStructuredJsonResponseAsync`
and `responseConstraint`). Android's Kotlin/KSP structured output has no
runtime form to bridge. See the
[platform coverage and remaining gaps](doc/platform-support.md#platform-coverage-and-remaining-gaps)
for current API versions, supported features, and what is still unverified.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
