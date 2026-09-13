@JS()
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// JS interop for the Chrome **Prompt API** (`self.LanguageModel`).
///
/// There is no script to load: `LanguageModel` is a bare global the browser
/// exposes when the Prompt API is enabled (origin trial, `chrome://flags`, or
/// an extension context). The single feature-detection seam every entry point
/// must gate on is [hasLanguageModel] — without it, touching `LanguageModel`
/// throws a JS `ReferenceError` on Firefox, Safari and mobile Chrome.
///
/// The surface has churned across Chrome releases, so members that exist on
/// some builds and not others get their own `'name' in object` probe
/// ([hasLanguageModelParams], [PromptSessionMembers]) rather than a blind
/// call: a missing member throws `TypeError: … is not a function`, which tells
/// a user nothing about which build they are on.
///
/// Mirrors https://developer.chrome.com/docs/ai/prompt-api:
/// ```js
/// await LanguageModel.availability(opts?)   // 'unavailable' | 'downloadable'
///                                           // | 'downloading' | 'available'
/// await LanguageModel.create(opts?)
/// await LanguageModel.params()              // pre-151 builds only
/// await session.prompt(input, opts?)
/// session.promptStreaming(input, opts?)     // ReadableStream<string>
/// await session.measureContextUsage(input)  // legacy: measureInputUsage
/// session.destroy()
/// ```
@JS('LanguageModel')
extension type LanguageModel._(JSObject _) implements JSObject {
  external static JSPromise<JSString> availability([JSObject? options]);
  external static JSPromise<PromptSession> create([JSObject? options]);

  /// Sampler bounds (`maxTemperature`, `maxTopK`, `defaultTopK`, …), read
  /// through [readSamplerBounds].
  ///
  /// Gate every call on [hasLanguageModelParams]: Chrome 151 dropped this
  /// static, keeping only `availability` and `create`, so calling it blind
  /// throws on every session creation.
  external static JSPromise<JSObject> params();
}

extension type PromptSession._(JSObject _) implements JSObject {
  external JSPromise<JSString> prompt(JSAny input, [JSObject? options]);

  /// A `ReadableStream<string>`. Typed as an opaque [JSObject] because
  /// `dart:js_interop` has no ReadableStream type; drained by
  /// [pumpTextStream], which also normalises the chunk shape.
  external JSObject promptStreaming(JSAny input, [JSObject? options]);

  /// Synchronous per spec — releases the session immediately.
  external void destroy();

  /// Token cost of [input]. The **current** spec name; gate on
  /// [PromptSessionMembers.hasMeasureContextUsage].
  external JSPromise<JSNumber> measureContextUsage(
    JSAny input, [
    JSObject? options,
  ]);

  /// The name earlier builds shipped, kept only as a fallback; gate on
  /// [PromptSessionMembers.hasMeasureInputUsage].
  external JSPromise<JSNumber> measureInputUsage(
    JSAny input, [
    JSObject? options,
  ]);

  external double get inputQuota;
  external double get inputUsage;
}

/// Presence probes for the session members Chrome renamed mid-flight.
///
/// Chrome renamed `measureInputUsage` to `measureContextUsage`. A build
/// exposes one or the other, so both names need a probe: calling the one this
/// build lacks fails with an opaque JS `TypeError` instead of a token count.
extension PromptSessionMembers on PromptSession {
  /// `'measureContextUsage' in session` — the current spec name, tried first.
  bool get hasMeasureContextUsage => has('measureContextUsage');

  /// `'measureInputUsage' in session` — the legacy name. Current Chrome no
  /// longer defines it, so code that knows only this name fails there.
  bool get hasMeasureInputUsage => has('measureInputUsage');
}

/// Cancels an in-flight `create` / `prompt` / `promptStreaming` (passed as
/// `signal` in the options object).
extension type AbortController._(JSObject _) implements JSObject {
  external factory AbortController();

  external JSObject get signal;
  external void abort([JSAny? reason]);
}

/// `'LanguageModel' in self`. False on every browser without the Prompt API,
/// which callers map to `unavailableDeviceUnsupported` rather than throwing.
bool get hasLanguageModel => globalContext.has('LanguageModel');

/// `'params' in LanguageModel`.
///
/// The static `params()` shipped in early Prompt API builds and was removed by
/// Chrome 151. Gate the sampler clamp on this so a modern browser skips it
/// silently instead of throwing `TypeError: LanguageModel.params is not a
/// function` on every `createSession`; `create()` validates the sampling
/// regardless, so skipping the clamp costs only the friendlier error.
bool get hasLanguageModelParams {
  if (!hasLanguageModel) return false;
  return globalContext
      .getProperty<JSObject>('LanguageModel'.toJS)
      .has('params');
}

/// The sampler ceilings [LanguageModel.params] reports, as far as this build
/// reports them at all.
///
/// Each bound is read behind `has` rather than through a nullable external
/// getter: an absent JS property is `undefined`, which is not `null` under
/// dart2wasm, so a nullable getter would hand back a bound that is not there
/// and clamp sampling to garbage. A null field here means "this build
/// advertises no such ceiling", which skips that clamp.
({double? maxTemperature, int? maxTopK}) readSamplerBounds(JSObject params) => (
  maxTemperature: params.has('maxTemperature')
      ? params.getProperty<JSNumber>('maxTemperature'.toJS).toDartDouble
      : null,
  maxTopK: params.has('maxTopK')
      ? params.getProperty<JSNumber>('maxTopK'.toJS).toDartInt
      : null,
);

/// Whether [error] is the JS `AbortError` that `AbortController.abort()`
/// produces on an in-flight `prompt()` / `promptStreaming()` — i.e. the user
/// pressing stop, not a generation failure.
///
/// Matches **only** the structured `DOMException.name`. A substring test on
/// the stringified error would classify a genuine failure whose message merely
/// mentions `AbortError` as a clean stop, and the caller would report an
/// empty, successful-looking turn instead of the error that actually happened
/// — exactly the outcome this check exists to prevent. No `is`/`as` runtime
/// check against an interop type either (unreliable across compile modes):
/// attempt the property read and treat anything not JS-shaped as "not an
/// abort".
bool isAbortError(Object error) {
  try {
    final name = (error as JSObject)
        .getProperty<JSString?>('name'.toJS)
        ?.toDart;
    return name == 'AbortError';
  } catch (_) {
    return false;
  }
}

/// Builds the `create()` options object.
///
/// `temperature` and `topK` are emitted only together — the Prompt API
/// rejects one without the other. [onDownloadProgress] is wired through the
/// `monitor` callback, whose `downloadprogress` event carries `loaded` as a
/// 0..1 fraction.
JSObject buildCreateOptions({
  String? systemInstruction,
  double? temperature,
  int? topK,
  List<String>? expectedInputTypes,
  JSObject? signal,
  void Function(double loaded)? onDownloadProgress,
}) {
  final map = <String, Object?>{
    if (systemInstruction != null && systemInstruction.isNotEmpty)
      'initialPrompts': [
        {'role': 'system', 'content': systemInstruction},
      ],
    if (temperature != null && topK != null) ...{
      'temperature': temperature,
      'topK': topK,
    },
    if (expectedInputTypes != null && expectedInputTypes.isNotEmpty)
      'expectedInputs': [
        for (final type in expectedInputTypes) {'type': type},
      ],
    'signal': ?signal,
  };
  final options = map.jsify()! as JSObject;
  if (onDownloadProgress != null) {
    options.setProperty(
      'monitor'.toJS,
      ((JSObject monitor) {
        monitor.callMethod(
          'addEventListener'.toJS,
          'downloadprogress'.toJS,
          ((JSObject event) {
            onDownloadProgress(
              event.getProperty<JSNumber>('loaded'.toJS).toDartDouble,
            );
          }).toJS,
        );
      }).toJS,
    );
  }
  return options;
}

/// Builds the `prompt()` / `promptStreaming()` options object, or null when
/// there is nothing to pass.
JSObject? buildPromptOptions({Object? responseConstraint, JSObject? signal}) {
  final map = <String, Object?>{
    'responseConstraint': ?responseConstraint,
    'signal': ?signal,
  };
  if (map.isEmpty) return null;
  return map.jsify()! as JSObject;
}

extension type _StreamReadResult._(JSObject _) implements JSObject {
  external bool get done;
  external JSAny? get value;
}

extension type _StreamReader._(JSObject _) implements JSObject {
  external JSPromise<_StreamReadResult> read();
  external JSPromise<JSAny?> cancel([JSAny? reason]);
}

/// Drains a `ReadableStream<string>`, invoking [onChunk] once per non-empty
/// **delta**, then completing. Any reader error propagates to the caller,
/// which decides whether it is a clean stop ([isAbortError]) or a tagged error
/// event.
///
/// The Prompt API spec says every chunk is a delta — only the newly generated
/// text — but early and some current Chrome builds stream *cumulative* chunks,
/// re-sending the whole response so far. Emitting those verbatim gives the app
/// `'Hel'`, `'Hello'`, `'Hello wor'`, which a caller concatenating deltas —
/// what `LocalAiTokenEvent.partialResult` promises — renders as
/// `'HelHelloHello wor'`: every streamed answer visibly duplicating and
/// growing.
///
/// The shape is therefore decided **once, on the second chunk**: if chunk 2
/// starts with chunk 1 the stream is cumulative, otherwise it is delta, and
/// that verdict holds for the rest of the stream. One chunk is not enough to
/// tell the shapes apart, and re-deciding per chunk would be worse, not
/// better: a delta stream whose next chunk happens to begin with everything
/// emitted so far would be misread as cumulative, and re-deciding opens that
/// window at *every* chunk instead of only the second. On real subword streams
/// the second chunk almost never repeats the first, so deciding there narrows
/// the misclassification window about as far as it can go.
Future<void> pumpTextStream(
  JSObject stream,
  void Function(String chunk) onChunk,
) async {
  final reader = stream.callMethod<_StreamReader>('getReader'.toJS);
  // Everything handed to [onChunk] so far, reassembled — the prefix a
  // cumulative chunk would repeat.
  var emitted = '';
  var seenChunk = false;
  // null until the second chunk decides; then held for the whole stream.
  bool? cumulative;
  try {
    while (true) {
      final result = await reader.read().toDart;
      if (result.done) return;
      final value = result.value;
      if (value == null) continue;
      final chunk = (value as JSString).toDart;
      if (chunk.isEmpty) continue;

      final String delta;
      if (!seenChunk) {
        // Nothing to compare against yet; both shapes start the same way.
        seenChunk = true;
        delta = chunk;
        emitted = chunk;
      } else {
        cumulative ??= chunk.startsWith(emitted);
        if (cumulative) {
          // A cumulative chunk shorter than what it supposedly accumulates is
          // not cumulative at all — take it raw rather than crash on a
          // negative substring.
          delta = chunk.length >= emitted.length
              ? chunk.substring(emitted.length)
              : chunk;
          emitted = chunk;
        } else {
          delta = chunk;
          emitted += chunk;
        }
      }
      if (delta.isNotEmpty) onChunk(delta);
    }
  } finally {
    // Releases the underlying source even when the loop exits early; a
    // cancel() on an already-closed stream is a no-op, so this is safe on the
    // normal path too.
    try {
      reader.cancel();
    } catch (_) {
      // Best effort: the stream is already gone.
    }
  }
}
