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
/// Mirrors https://developer.chrome.com/docs/ai/prompt-api:
/// ```js
/// await LanguageModel.availability(opts?)   // 'unavailable' | 'downloadable'
///                                           // | 'downloading' | 'available'
/// await LanguageModel.create(opts?)
/// await session.prompt(input, opts?)
/// session.promptStreaming(input, opts?)     // ReadableStream<string>
/// await session.measureInputUsage(input)
/// session.destroy()
/// ```
@JS('LanguageModel')
extension type LanguageModel._(JSObject _) implements JSObject {
  external static JSPromise<JSString> availability([JSObject? options]);
  external static JSPromise<PromptSession> create([JSObject? options]);
}

extension type PromptSession._(JSObject _) implements JSObject {
  external JSPromise<JSString> prompt(JSAny input, [JSObject? options]);

  /// A `ReadableStream<string>` of deltas. Typed as an opaque [JSObject]
  /// because `dart:js_interop` has no ReadableStream type; drained by
  /// [pumpTextStream].
  external JSObject promptStreaming(JSAny input, [JSObject? options]);

  /// Synchronous per spec — releases the session immediately.
  external void destroy();

  external JSPromise<JSNumber> measureInputUsage(
    JSAny input, [
    JSObject? options,
  ]);

  external double get inputQuota;
  external double get inputUsage;
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
    if (signal != null) 'signal': signal,
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
    if (responseConstraint != null) 'responseConstraint': responseConstraint,
    if (signal != null) 'signal': signal,
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

/// Drains a `ReadableStream<string>`, invoking [onChunk] for each non-empty
/// delta, then completing. Any reader error propagates to the caller, which
/// turns it into a tagged error event.
Future<void> pumpTextStream(
  JSObject stream,
  void Function(String chunk) onChunk,
) async {
  final reader = stream.callMethod<_StreamReader>('getReader'.toJS);
  try {
    while (true) {
      final result = await reader.read().toDart;
      if (result.done) return;
      final value = result.value;
      if (value == null) continue;
      final chunk = (value as JSString).toDart;
      if (chunk.isNotEmpty) onChunk(chunk);
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
