import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_gemma/core/extensions.dart';
import 'package:flutter_gemma/core/message.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/flutter_gemma_interface.dart'
    show InferenceModelSession, SessionMetrics;
import 'package:flutter_local_ai/flutter_local_ai.dart';

/// Adapts a [LocalAiSession] to flutter_gemma's [InferenceModelSession].
///
/// Thin by design: the buffering, streaming, cancellation and token-count
/// semantics all live in flutter_local_ai, and this class only translates
/// flutter_gemma's [Message] into the text and images the session takes.
class LocalAiGemmaSession extends InferenceModelSession {
  LocalAiGemmaSession({
    required LocalAiSession session,
    required this.modelType,
    required this.fileType,
    required this.supportImage,
    required void Function() onClose,
  })  : _session = session,
        _onClose = onClose;

  final LocalAiSession _session;
  final ModelType modelType;
  final ModelFileType fileType;
  final bool supportImage;
  final void Function() _onClose;

  /// The underlying flutter_local_ai session, for callers that want the
  /// capabilities flutter_gemma's interface has no slot for — schema-
  /// constrained output, in particular.
  LocalAiSession get localAiSession => _session;

  @override
  Future<void> addQueryChunk(Message message) async {
    final prompt = message.transformToChatPrompt(
      type: modelType,
      fileType: fileType,
    );
    // Images first, so the host has them buffered before the text that
    // refers to them — the ordering the native multimodal requests expect.
    if (message.hasImage && supportImage) {
      final images = message.images.isNotEmpty
          ? message.images
          : (message.imageBytes != null
              ? <Uint8List>[message.imageBytes!]
              : const <Uint8List>[]);
      for (final image in images) {
        await _session.addImage(image);
      }
    }
    await _session.addQueryChunk(prompt);
  }

  @override
  Future<String> getResponse() => _session.getResponse();

  @override
  Stream<String> getResponseAsync() => _session.getResponseAsync();

  @override
  Future<int> sizeInTokens(String text) => _session.sizeInTokens(text);

  @override
  Future<void> stopGeneration() => _session.stopGeneration();

  /// Built-in OS models expose no benchmark counters, so there is nothing
  /// truthful to report here. Empty metrics beat invented ones; use
  /// [sizeInTokens] for the one number that is real.
  @override
  SessionMetrics getSessionMetrics() => SessionMetrics();

  @override
  Future<void> close() async {
    _onClose();
    await _session.close();
  }
}
