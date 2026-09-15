import 'dart:async';
import 'dart:convert';

import '../models/tool.dart';

/// Thrown when the model asks for a tool this registry has never heard of.
///
/// A distinct type so the host can map it to a platform error the model sees,
/// rather than letting a stray `StateError` unwind through native code.
class UnknownToolException implements Exception {
  UnknownToolException(this.sessionId, this.toolName);

  final int sessionId;
  final String toolName;

  @override
  String toString() =>
      'UnknownToolException: no tool named "$toolName" is registered for '
      'session $sessionId.';
}

/// Which Dart tools each session offers, and how a native tool call reaches
/// one.
///
/// Split out of the host so the dispatch rules — JSON in, JSON out, scoped
/// per session, forgotten when the session goes — are testable without a
/// platform channel, and stated once instead of per platform.
class LocalAiToolRegistry {
  final Map<int, Map<String, LocalAiTool>> _bySession = {};

  /// Whether any session currently offers tools.
  bool get isEmpty => _bySession.isEmpty;

  /// Offers [tools] on [sessionId]. An empty or null list registers nothing,
  /// so a session without tools costs no bookkeeping.
  void register(int sessionId, List<LocalAiTool>? tools) {
    if (tools == null || tools.isEmpty) {
      _bySession.remove(sessionId);
      return;
    }
    _bySession[sessionId] = {for (final tool in tools) tool.name: tool};
  }

  /// Forgets [sessionId]'s tools, so a late native callback cannot invoke a
  /// handler the app considers gone.
  void forget(int sessionId) => _bySession.remove(sessionId);

  /// Forgets every session. Used when the model itself closes, which takes
  /// all of its sessions with it.
  void clear() => _bySession.clear();

  /// Runs the tool the model asked for and encodes its result.
  ///
  /// [argumentsJson] is the JSON object the model produced; a blank or
  /// non-object payload becomes an empty argument map rather than an error,
  /// because a zero-argument tool is legitimate. The return value is JSON, or
  /// null when the tool yields nothing.
  ///
  /// Throws [UnknownToolException] if [toolName] is not registered for
  /// [sessionId] — including when it is registered for a *different* session,
  /// which must not be reachable from here.
  Future<String?> invoke(
    int sessionId,
    String toolName,
    String argumentsJson,
  ) async {
    final tool = _bySession[sessionId]?[toolName];
    if (tool == null) throw UnknownToolException(sessionId, toolName);
    final result = await tool.onCall(_decodeArguments(argumentsJson));
    return result == null ? null : jsonEncode(result);
  }

  static Map<String, dynamic> _decodeArguments(String argumentsJson) {
    if (argumentsJson.isEmpty) return {};
    final Object? decoded;
    try {
      decoded = jsonDecode(argumentsJson);
    } on FormatException {
      // The model produced something that is not JSON at all. An empty
      // argument map lets the tool decide, which beats failing the whole
      // generation over a malformed call.
      return {};
    }
    if (decoded is! Map) return {};
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }
}
