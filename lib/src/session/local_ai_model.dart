import 'dart:async';

import '../models/tool.dart';
import 'local_ai_host.dart';
import 'local_ai_runtime.dart';
import 'local_ai_session.dart';

/// A loaded OS built-in model.
///
/// The OS owns the weights, so this is a thin session factory rather than
/// anything that holds a checkpoint. One model backs any number of
/// [openSession] sessions, each with its own conversation context;
/// generation across them is serialized by the host.
class LocalAiModel {
  LocalAiModel._({
    required LocalAiHost host,
    required this.maxTokens,
    required this.supportImage,
  }) : _host = host;

  /// Loads the OS model.
  ///
  /// The model must already be ready — call `LocalAi.ensureReady()` first.
  /// [maxTokens] is the context window (input plus output) and is advisory on
  /// hosts that fix their own; [supportImage] asks the host to prepare a
  /// multimodal path, and throws where none exists.
  static Future<LocalAiModel> create({
    int maxTokens = 4096,
    bool supportImage = false,
    LocalAiHost? host,
  }) async {
    final resolved = host ?? localAiHost;
    await resolved.createModel(supportImage: supportImage);
    return LocalAiModel._(
      host: resolved,
      maxTokens: maxTokens,
      supportImage: supportImage,
    );
  }

  final LocalAiHost _host;

  /// Context window in tokens: input plus generated output.
  final int maxTokens;

  final bool supportImage;

  final Map<int, LocalAiSession> _sessions = {};

  /// Monotonic session-id generator. Ids are never reused within a model, so
  /// a late event from a closed session can't be misrouted to a new one.
  int _nextSessionId = 1;

  bool _isClosed = false;

  /// Live sessions, in creation order.
  List<LocalAiSession> get sessions => List.unmodifiable(_sessions.values);

  /// Opens an independent session with its own context.
  ///
  /// [tools] are bound at construction because Apple's FoundationModels
  /// cannot add tools to a live session; hosts reporting
  /// `supportsToolCalling: false` throw [LocalAiUnsupportedException] when
  /// tools are supplied.
  Future<LocalAiSession> openSession({
    double temperature = 0.8,
    int topK = 1,
    double? topP,
    int? maxOutputTokens,
    String? systemInstruction,
    List<LocalAiTool>? tools,
  }) async {
    if (_isClosed) {
      throw StateError('Model is closed. Create a new one to use it again.');
    }
    final sessionId = _nextSessionId++;
    await _host.createSession(
      sessionId: sessionId,
      temperature: temperature,
      topK: topK,
      topP: topP,
      maxOutputTokens: maxOutputTokens,
      systemInstruction: systemInstruction,
      tools: tools,
    );
    final session = LocalAiSession(
      sessionId: sessionId,
      host: _host,
      onClose: () => _sessions.remove(sessionId),
    );
    _sessions[sessionId] = session;
    return session;
  }

  /// Closes every session, then releases the model. Idempotent.
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    // Close the model even if a session's native close throws — otherwise the
    // OS resource leaks behind a model the app already considers gone.
    try {
      for (final session in List.of(_sessions.values)) {
        await session.close();
      }
    } finally {
      _sessions.clear();
      await _host.closeModel();
    }
  }
}
