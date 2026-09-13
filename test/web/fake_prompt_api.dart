@JS()
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Test-only scaffolding for the web arm: a hand-built `self.LanguageModel`
/// planted on [globalContext], so `flutter test --platform chrome` exercises
/// the real interop and the real `AbortController` without downloading Gemini
/// Nano (or needing a browser that ships the Prompt API at all).
///
/// Only `LanguageModel` is faked. Signals, promises and the ReadableStream
/// protocol are the browser's own, which is the point: the delta/cumulative
/// guard and the AbortError close path are driven by genuine JS rejections.

/// A `JSPromise<T>` with full control over when and how it settles.
///
/// `Future<T>.toJS` cannot do this: it wraps a rejection in a boxed Dart error
/// object, so there is no way to reject with a DOMException-shaped
/// `{name: 'AbortError'}` — the exact shape the production code classifies on.
JSPromise<T> jsPromiseOf<T extends JSAny?>(
  void Function(
    void Function(T value) resolve,
    void Function(JSAny? reason) reject,
  )
  executor,
) {
  return JSPromise<T>(
    ((JSFunction resolve, JSFunction reject) {
      executor(
        (value) => resolve.callAsFunction(resolve, value),
        (reason) => reject.callAsFunction(reject, reason),
      );
    }).toJS,
  );
}

/// A DOMException-shaped rejection reason: `{name, message}`.
JSObject fakeDomException(String name, [String message = '']) {
  final error = JSObject();
  error.setProperty('name'.toJS, name.toJS);
  error.setProperty('message'.toJS, message.toJS);
  return error;
}

/// Reads `aborted` off a real browser `AbortSignal`. The production host
/// builds a genuine `AbortController`, so this reflects real abort state.
bool isSignalAborted(JSObject? signal) =>
    signal?.getProperty<JSBoolean?>('aborted'.toJS)?.toDart ?? false;

/// A `ReadableStream<string>` over [chunks].
///
/// Rejects `read()` with an `AbortError` as soon as [signal] is aborted, which
/// is what Chrome does to an in-flight `promptStreaming`. [rejectAfter] rejects
/// with [rejectName] once that many chunks have been delivered, to exercise the
/// path where a failure is *not* a cancellation.
JSObject fakeTextStream(
  List<String> chunks, {
  JSObject? signal,
  int? rejectAfter,
  String rejectName = 'NotReadableError',
}) {
  var index = 0;
  var cancelled = false;

  JSObject doneResult() {
    final result = JSObject();
    result.setProperty('done'.toJS, true.toJS);
    return result;
  }

  JSPromise<JSObject> read() => jsPromiseOf<JSObject>((resolve, reject) async {
    // A timer, not a microtask: an abort scheduled by a listener reacting
    // to the previous chunk must land before this read decides.
    await Future<void>.delayed(Duration.zero);
    if (cancelled) {
      resolve(doneResult());
      return;
    }
    if (isSignalAborted(signal)) {
      reject(fakeDomException('AbortError', 'The operation was aborted.'));
      return;
    }
    if (rejectAfter != null && index >= rejectAfter) {
      reject(fakeDomException(rejectName, 'decoder died'));
      return;
    }
    if (index >= chunks.length) {
      resolve(doneResult());
      return;
    }
    final result = JSObject();
    result.setProperty('done'.toJS, false.toJS);
    result.setProperty('value'.toJS, chunks[index++].toJS);
    resolve(result);
  });

  final reader = JSObject();
  reader.setProperty('read'.toJS, (() => read()).toJS);
  reader.setProperty(
    'cancel'.toJS,
    (([JSAny? reason]) {
      cancelled = true;
      return jsPromiseOf<JSAny?>((resolve, reject) => resolve(null));
    }).toJS,
  );

  final stream = JSObject();
  stream.setProperty('getReader'.toJS, (() => reader).toJS);
  return stream;
}

/// Turns deltas into the cumulative shape early Chrome builds stream:
/// `['Hel', 'lo']` becomes `['Hel', 'Hello']`.
List<String> toCumulative(List<String> deltas) {
  var accumulated = '';
  return [for (final delta in deltas) accumulated += delta];
}

/// A fake `LanguageModelSession`. Any correctly shaped JSObject satisfies the
/// production `PromptSession` extension type — it is a compile-time view with
/// no runtime tag.
class FakeSession {
  FakeSession({
    this.onPrompt,
    this.promptRejectsWith,
    this.streamChunks,
    this.cumulativeStream = false,
    this.streamRejectAfter,
    this.streamRejectName = 'NotReadableError',
    this.measureMembers = const ['measureContextUsage'],
  }) {
    jsObject = JSObject();
    jsObject.setProperty('destroy'.toJS, (() => destroyCount++).toJS);
    jsObject.setProperty(
      'prompt'.toJS,
      ((JSString input, [JSObject? options]) {
        promptCalls.add(input.toDart);
        final signal = options?.getProperty<JSObject?>('signal'.toJS);
        lastPromptSignal = signal;
        return jsPromiseOf<JSString>((resolve, reject) async {
          await Future<void>.delayed(Duration.zero);
          if (isSignalAborted(signal)) {
            reject(
              fakeDomException('AbortError', 'The operation was aborted.'),
            );
            return;
          }
          final rejection = promptRejectsWith;
          if (rejection != null) {
            reject(fakeDomException(rejection.$1, rejection.$2));
            return;
          }
          resolve((onPrompt?.call(input.toDart) ?? '').toJS);
        });
      }).toJS,
    );
    jsObject.setProperty(
      'promptStreaming'.toJS,
      ((JSString input, [JSObject? options]) {
        promptStreamingCalls.add(input.toDart);
        final signal = options?.getProperty<JSObject?>('signal'.toJS);
        lastStreamingSignal = signal;
        final deltas = streamChunks?.call(input.toDart) ?? const <String>[];
        return fakeTextStream(
          cumulativeStream ? toCumulative(deltas) : deltas,
          signal: signal,
          rejectAfter: streamRejectAfter,
          rejectName: streamRejectName,
        );
      }).toJS,
    );
    for (final member in measureMembers) {
      jsObject.setProperty(
        member.toJS,
        ((JSString input, [JSObject? options]) {
          measureCalls.add(member);
          return jsPromiseOf<JSNumber>(
            (resolve, reject) => resolve(input.toDart.length.toDouble().toJS),
          );
        }).toJS,
      );
    }
  }

  final String Function(String input)? onPrompt;

  /// `(name, message)` to reject `prompt()` with instead of resolving.
  final (String, String)? promptRejectsWith;
  final List<String> Function(String input)? streamChunks;
  final bool cumulativeStream;
  final int? streamRejectAfter;
  final String streamRejectName;

  /// Which of `measureContextUsage` / `measureInputUsage` this build defines.
  /// An empty list is a build that can't measure at all.
  final List<String> measureMembers;

  late final JSObject jsObject;
  final List<String> promptCalls = [];
  final List<String> promptStreamingCalls = [];
  final List<String> measureCalls = [];
  JSObject? lastPromptSignal;
  JSObject? lastStreamingSignal;
  int destroyCount = 0;
}

/// A fake `self.LanguageModel`, planted on [globalContext] by [install].
class FakeLanguageModel {
  FakeLanguageModel({
    String availability = 'available',
    FakeSession Function([JSObject? options])? create,
    double? maxTemperature = 2.0,
    int? maxTopK = 8,
    bool includeParams = true,
  }) {
    _jsObject = JSObject();
    _jsObject.setProperty(
      'availability'.toJS,
      (([JSObject? options]) => jsPromiseOf<JSString>(
        (resolve, reject) => resolve(availability.toJS),
      )).toJS,
    );
    _jsObject.setProperty(
      'create'.toJS,
      (([JSObject? options]) {
        createOptions.add(options);
        final session = create?.call(options) ?? FakeSession();
        lastSession = session;
        return jsPromiseOf<JSObject>(
          (resolve, reject) => resolve(session.jsObject),
        );
      }).toJS,
    );
    if (includeParams) {
      _jsObject.setProperty(
        'params'.toJS,
        (() {
          paramsCalls++;
          final params = JSObject();
          if (maxTemperature != null) {
            params.setProperty('maxTemperature'.toJS, maxTemperature.toJS);
          }
          if (maxTopK != null) {
            params.setProperty('maxTopK'.toJS, maxTopK.toJS);
          }
          return jsPromiseOf<JSObject>((resolve, reject) => resolve(params));
        }).toJS,
      );
    }
  }

  late final JSObject _jsObject;

  /// The options object handed to each `create()` call, newest last.
  final List<JSObject?> createOptions = [];
  FakeSession? lastSession;
  int paramsCalls = 0;

  void install() => globalContext.setProperty('LanguageModel'.toJS, _jsObject);

  /// Removes `LanguageModel` outright — true absence, not `undefined`, which
  /// is what an unsupported browser looks like to `'LanguageModel' in self`.
  static void uninstall() => globalContext.delete('LanguageModel'.toJS);
}
