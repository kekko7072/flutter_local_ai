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
    required this._host,
    required this.maxTokens,
    required this.supportImage,
    required this._state,
  });

  static final _states = Expando<_HostModelState>();

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
    final state = _states[resolved] ??= _HostModelState(resolved);
    await state.acquire(supportImage);
    return LocalAiModel._(
      host: resolved,
      maxTokens: maxTokens,
      supportImage: supportImage,
      state: state,
    );
  }

  final LocalAiHost _host;
  final _HostModelState _state;
  final Set<Future<void>> _pendingOpens = {};
  Future<void>? _closing;

  /// Context window in tokens: input plus generated output.
  final int maxTokens;

  final bool supportImage;

  final Map<int, LocalAiSession> _sessions = {};

  bool _isClosed = false;

  /// Live sessions, in creation order.
  List<LocalAiSession> get sessions => List.unmodifiable(_sessions.values);

  /// Opens an independent session with its own context.
  ///
  /// [tools] are bound at construction because Apple's FoundationModels
  /// cannot add tools to a live session; hosts reporting
  /// `supportsToolCalling: false` throw [LocalAiUnsupportedException] when
  /// tools are supplied. A tool declaring its parameters as a JSON Schema has
  /// that schema validated here, so an unsupported construct fails with a
  /// path-qualified [ArgumentError] naming the tool rather than opaquely
  /// inside the native session.
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
    for (final tool in tools ?? const <LocalAiTool>[]) {
      tool.validateParameterSchema();
    }
    final sessionId = _state.nextSessionId++;
    final opening = _host.createSession(
      sessionId: sessionId,
      temperature: temperature,
      topK: topK,
      topP: topP,
      maxOutputTokens: maxOutputTokens,
      systemInstruction: systemInstruction,
      tools: tools,
    );
    final settled = Completer<void>();
    _pendingOpens.add(settled.future);
    try {
      await opening;
      if (_isClosed) {
        await _host.closeSession(sessionId);
        throw StateError('Model closed while the session was opening.');
      }
    } finally {
      _pendingOpens.remove(settled.future);
      settled.complete();
    }
    final session = LocalAiSession(
      sessionId: sessionId,
      host: _host,
      onClose: () => _sessions.remove(sessionId),
    );
    _sessions[sessionId] = session;
    return session;
  }

  /// Closes every session, then releases the model. Idempotent.
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _isClosed = true;
    // Close the model even if a session's native close throws — otherwise the
    // OS resource leaks behind a model the app already considers gone.
    try {
      await Future.wait(
        _pendingOpens.map((opening) async {
          try {
            await opening;
          } catch (_) {
            /* The opener reports the error. */
          }
        }),
      );
      Object? firstError;
      StackTrace? firstStack;
      for (final session in List.of(_sessions.values)) {
        try {
          await session.close();
        } catch (error, stack) {
          firstError ??= error;
          firstStack ??= stack;
        }
      }
      if (firstError != null) {
        Error.throwWithStackTrace(firstError, firstStack!);
      }
    } finally {
      _sessions.clear();
      await _state.release();
    }
  }
}

/// Both Dart APIs and external adapters share one native host. Its resources
/// must outlive every model owner, and session IDs must never collide across
/// owners.
class _HostModelState {
  _HostModelState(this.host);
  final LocalAiHost host;
  int nextSessionId = 1;
  int _owners = 0;
  bool _supportsImage = false;
  Future<void> _tail = Future.value();

  Future<void> _serialize(Future<void> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> acquire(bool supportImage) => _serialize(() async {
    if (supportImage && !(await host.getBackendInfo()).supportsVision) {
      throw LocalAiUnsupportedException(
        'vision',
        'This backend does not support image input.',
      );
    }
    if (_owners == 0 || (supportImage && !_supportsImage)) {
      await host.createModel(supportImage: supportImage || _supportsImage);
      _supportsImage = supportImage || _supportsImage;
    }
    _owners++;
  });

  Future<void> release() => _serialize(() async {
    if (--_owners == 0) {
      _supportsImage = false;
      await host.closeModel();
    }
  });
}
