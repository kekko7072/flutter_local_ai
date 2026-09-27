import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../models/schema_validation.dart';
import 'local_ai_host_api.dart';

/// A generation session on the OS built-in model.
///
/// Sessions are keyed by [sessionId]; generated tokens arrive on the host's
/// shared event stream tagged with that id, so a session consumes only its
/// own output. Turn shape is buffer-then-generate: [addQueryChunk] (and
/// [addImage]) accumulate the turn, then one of the generate calls consumes
/// it.
class LocalAiSession {
  LocalAiSession({
    required this.sessionId,
    required this._host,
    required this._onClose,
  });

  final int sessionId;
  final LocalAiHost _host;
  final void Function() _onClose;

  bool _isClosed = false;

  /// Whether [close] has run. A closed session throws on every operation
  /// rather than silently reopening native state.
  bool get isClosed => _isClosed;

  void _assertOpen() {
    if (_isClosed) {
      throw StateError('Session $sessionId is closed.');
    }
  }

  /// Adds text to the pending turn. Call repeatedly to build a turn from
  /// parts; the next generate call consumes everything accumulated.
  Future<void> addQueryChunk(String text) {
    _assertOpen();
    return _host.addQueryChunk(sessionId: sessionId, text: text);
  }

  /// Adds an image to the pending turn.
  ///
  /// Throws [LocalAiUnsupportedException] where the host has no vision path
  /// (iOS/macOS 26, web). Check `LocalAi.capabilities().supportsVision`
  /// first. Add images before the text they belong to, matching how the
  /// native hosts assemble a multimodal request.
  Future<void> addImage(Uint8List imageBytes) {
    _assertOpen();
    return _host.addImage(sessionId: sessionId, imageBytes: imageBytes);
  }

  /// Generates the full response for the pending turn.
  ///
  /// [overrides] varies sampling for this call only, leaving the session's
  /// own settings alone. Hosts that fix sampling per session (the Chrome
  /// Prompt API) log once and ignore it.
  Future<String> getResponse({LocalAiGenerationOverrides? overrides}) {
    _assertOpen();
    return _host.generateResponse(sessionId, overrides: _meaningful(overrides));
  }

  /// Generates the response as a stream of deltas — each event is the newly
  /// produced text, not the running total.
  ///
  /// Cancelling the subscription detaches the Dart side; call
  /// [stopGeneration] to actually stop the model decoding.
  Stream<String> getResponseAsync({LocalAiGenerationOverrides? overrides}) {
    _assertOpen();

    // A StreamController rather than `async*` so cleanup runs on done, on
    // error AND on consumer cancel — an abandoned stream must still drop its
    // subscription to the shared host event stream.
    final controller = StreamController<String>();
    StreamSubscription<LocalAiHostEvent>? subscription;
    var finished = false;

    Future<void> cleanup() async {
      if (finished) return;
      finished = true;
      await subscription?.cancel();
    }

    controller.onListen = () {
      subscription = _host.events.listen(
        (event) {
          if (controller.isClosed) return;
          switch (event) {
            case LocalAiTokenEvent(:final sessionId, :final partialResult)
                when sessionId == this.sessionId:
              if (partialResult.isNotEmpty) controller.add(partialResult);
              if (event.done) {
                cleanup();
                controller.close();
              }
            case LocalAiErrorEvent(:final sessionId, :final message)
                when sessionId == this.sessionId:
              controller.addError(LocalAiGenerationException(message));
              cleanup();
              controller.close();
            default:
            // Another session's event, or download progress. Not ours.
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!controller.isClosed) controller.addError(error, stackTrace);
          cleanup();
          if (!controller.isClosed) controller.close();
        },
      );

      // Kick off generation. A synchronous native failure — before any event
      // is emitted — must surface here rather than hang the stream forever.
      _host
          .generateResponseAsync(sessionId, overrides: _meaningful(overrides))
          .catchError((Object error, StackTrace stackTrace) {
            if (!controller.isClosed) controller.addError(error, stackTrace);
            cleanup();
            if (!controller.isClosed) controller.close();
          });
    };

    controller.onCancel = cleanup;

    return controller.stream;
  }

  /// Generates a response constrained to [schema] (a JSON Schema document)
  /// and returns the raw JSON text.
  ///
  /// Throws [LocalAiUnsupportedException] on hosts reporting
  /// `supportsStructuredOutput: false` (the Android typed schema API is
  /// not bridged to this dynamic Dart schema interface). [schema] is validated in Dart first, so an unsupported construct
  /// fails with a path-qualified [ArgumentError] rather than an opaque native
  /// error after the round trip.
  Future<String> getStructuredResponse(
    Map<String, dynamic> schema, {
    LocalAiGenerationOverrides? overrides,
  }) {
    _assertOpen();
    validateGenerationSchema(schema);
    return _host.generateStructuredResponse(
      sessionId: sessionId,
      schemaJson: jsonEncode(schema),
      overrides: _meaningful(overrides),
    );
  }

  /// Stops the current generation at the model, not just at the Dart
  /// subscription. Safe to call when nothing is generating.
  Future<void> stopGeneration() => _host.stopGeneration(sessionId);

  /// Token count for [text].
  ///
  /// Exact where the host has a tokenizer. Where it doesn't — Apple below
  /// iOS/macOS 26.4, or a build made with an older Xcode — this falls back to
  /// a `length / 4` estimate so token budgeting degrades instead of failing;
  /// `LocalAi.capabilities().supportsTokenCount` says which you are getting.
  Future<int> sizeInTokens(String text) async {
    _assertOpen();
    try {
      return await _host.countTokens(sessionId: sessionId, text: text);
    } on LocalAiTokenizerUnavailable {
      return (text.length / 4).ceil();
    }
  }

  /// Normalizes an override that overrides nothing to null, so every host
  /// sees either null or a real change. Sending an empty one would make a
  /// host rebuild its options for no reason — and on Apple, rebuilding can
  /// flip the sampling mode off greedy.
  static LocalAiGenerationOverrides? _meaningful(
    LocalAiGenerationOverrides? overrides,
  ) => overrides == null || overrides.isEmpty ? null : overrides;

  Future<void>? _closing;

  /// Releases the native session. Idempotent; a failed close can be retried.
  Future<void> close() => _closing ??= () async {
    _isClosed = true;
    try {
      await _host.closeSession(sessionId);
    } catch (_) {
      _isClosed = false;
      _closing = null;
      rethrow;
    }
    _onClose();
  }();
}

/// A failure reported by the model during generation, delivered on the
/// response stream for the session that caused it.
class LocalAiGenerationException implements Exception {
  LocalAiGenerationException(this.message);

  final String message;

  @override
  String toString() => 'LocalAiGenerationException: $message';
}
