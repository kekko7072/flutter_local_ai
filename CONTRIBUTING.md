# Contributing

## Layout

One published package lives here: `flutter_local_ai`, with two entry points.

| Import | What it is |
|---|---|
| `package:flutter_local_ai/flutter_local_ai.dart` | The plugin: native hosts plus the Dart API |
| `package:flutter_local_ai/gemma.dart` | A flutter_gemma inference engine over the above, plus a full re-export of the core |

`lib/src/gemma/` is the only code that imports `flutter_gemma`. Dart has no
optional dependencies and no structural typing, so implementing
`InferenceEngineProvider` makes `flutter_gemma` a dependency of the whole
package — which is also where the Dart >=3.12 / Flutter >=3.44 floor comes
from.

## Architecture in one paragraph

`pigeon.dart` defines the wire. Each platform implements the generated
`LocalAiService` in a single session service (`LocalAiSessionService` in
Kotlin, Swift and C++), and streams tokens over one `flutter_local_ai_events`
channel tagged with a session id. In Dart, one arm-neutral `LocalAiHost`
interface is implemented twice — over pigeon natively, over Chrome's Prompt
API on the web — and everything above it (`LocalAiModel`, `LocalAiSession`,
the `LocalAi` availability facade, the `FlutterLocalAi` prompt facade, and the
flutter_gemma bridge) is written once against that interface.

Two rules keep it that way:

- **No second channel.** Both Dart surfaces go through `LocalAiHost`. A
  parallel path is how the two drifted apart before, with `generateText`
  keeping history on Apple and discarding it on Android.
- **Capabilities are runtime, not compile-time.** The same binary reports
  vision as unavailable on iOS 26 and available on 27. Ask
  `LocalAi.capabilities()`, never `Platform.isX`.

## Changing the wire

`pigeon.dart` is the source of truth for the Dart, Kotlin, Swift and C++
bindings. After editing it:

```sh
flutter pub get
dart run pigeon --input pigeon.dart
dart format .
```

CI regenerates and fails on any diff, so a hand-edit to a `.g.` file does not
survive review.

Enum member order is frozen — **append only**. A released app can hold a
mismatched Dart/native pair across a hot restart, and reordering silently
remaps values rather than failing.

## Tests

```sh
flutter test
```

There is no OS model behind `flutter test` on any platform, so tests drive a
substitute host:

```dart
import 'package:flutter_local_ai/testing.dart';

final host = FakeLocalAiHost()..response = 'hello';
debugLocalAiHost = host;
addTearDown(() async {
  debugLocalAiHost = null;
  await host.dispose();
});
```

`FakeLocalAiHost` is published API, not a test-tree helper — apps built on
this package need it for exactly the same reason. Extend it rather than
writing a second double.

Nothing generates tokens on its own, so a streaming test plays the platform's
part with `host.emitToken(...)` / `emitDone(...)` / `emitError(...)`.

## Native code

The native hosts are not exercised by `flutter test` — it runs on the host
VM, with no AICore, FoundationModels or Windows AI behind it. Changes to
Kotlin, Swift or C++ need a real build on a real device:

```sh
cd example && flutter run          # -d <device>
```

Windows AI is compile-gated behind `WINDOWS_AI_AVAILABLE`; with the gate off
the backend reports `windowsAiFoundryUnconfigured` and refuses to generate,
which is the expected state until the WinRT headers are generated.

## Releasing

Publishing is driven by tags, and pub.dev authenticates the run by its OIDC
identity — there is no token in this repository.

```sh
git tag v0.1.0 && git push origin v0.1.0
```

The workflow refuses to publish when the tag and `pubspec.yaml` disagree.
The package must have this repository and the `v*` tag pattern registered on
pub.dev under **Admin → Automated publishing** first.
