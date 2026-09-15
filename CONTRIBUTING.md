# Contributing

## Layout

One standalone package lives here: `flutter_local_ai`.

| Import | What it is |
|---|---|
| `package:flutter_local_ai/flutter_local_ai.dart` | The plugin: native hosts plus the Dart API |
| `package:flutter_local_ai/testing.dart` | A fake host for tests of the public API |

This package must not depend on or import `flutter_gemma`, including its
internal paths. The inference engine, the Gemma model/session wrappers and the
model specs live in
[`flutter_gemma_builtin_ai`](https://github.com/DenisovAV/flutter_gemma/tree/main/packages/flutter_gemma_builtin_ai)
in the flutter_gemma repository. The dependency arrow has one legal direction:
the adapter depends on this package, never the reverse — a PR that adds
`flutter_gemma` to this `pubspec.yaml` is wrong regardless of what it buys.
Keeping the direction that way means an app that only wants the OS model never
pulls in flutter_gemma's native plugin and downloaders, and a change to a
flutter_gemma interface — some of which are still internal paths within 1.x —
ships together with the adapter fix in one upstream PR. The adapter keeps its
own package name, imports and `BuiltInAi*` API, so its users have nothing to
migrate.

What each backend supports, what it needs at build time and what is still
unverified is in [doc/platform-support.md](doc/platform-support.md).

## Architecture in one paragraph

`pigeon.dart` defines the wire. Each platform implements the generated
`LocalAiService` in a single session service (`LocalAiSessionService` in
Kotlin, Swift and C++), and streams tokens over one `flutter_local_ai_events`
channel tagged with a session id. In Dart, one arm-neutral `LocalAiHost`
interface is implemented twice — over pigeon natively, over Chrome's Prompt
API on the web — and everything above it (`LocalAiModel`, `LocalAiSession`,
the `LocalAi` availability facade and the `FlutterLocalAi` prompt facade) is
written once against that interface. External adapters use the public Dart
API and share these backends.

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

### The web arm

`test/web/` covers the Chrome Prompt API host against a fake `LanguageModel`,
and is marked `@TestOn('browser')` — `flutter test` skips those files rather
than running them, so they cost the default run nothing:

```sh
flutter test --platform chrome test/web
```

That command needs a checkout whose Flutter web target is configured; without
one it stalls at `loading` instead of reporting a failure, so a stall there is
the harness, not the suite. The web sources themselves are covered by
`flutter analyze` and by compiling an app that depends on this package for the
web, which is the check to fall back on:

```sh
flutter build web   # in an app with a path dependency on this package
```

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
