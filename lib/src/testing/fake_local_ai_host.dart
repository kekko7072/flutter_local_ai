import 'dart:async';
import 'dart:typed_data';

import '../models/tool.dart';
import '../session/local_ai_host.dart';

/// One session the fake was asked to create, and everything sent to it.
///
/// Assert against this rather than against call strings: it survives a
/// rename, and it says what the code under test actually did.
class FakeLocalAiSession {
  FakeLocalAiSession({
    required this.id,
    required this.temperature,
    required this.topK,
    this.topP,
    this.maxOutputTokens,
    this.systemInstruction,
    this.toolNames = const [],
  });

  final int id;
  final double temperature;
  final int topK;
  final double? topP;
  final int? maxOutputTokens;
  final String? systemInstruction;
  final List<String> toolNames;

  /// Everything `addQueryChunk` appended, in order.
  final StringBuffer transcript = StringBuffer();

  /// Everything `addImage` appended, in order.
  final List<Uint8List> images = [];

  /// Sampling the most recent generate call on this session carried, or null
  /// when it inherited the session's own.
  LocalAiGenerationOverrides? lastOverrides;

  /// The schema the most recent structured call carried, as raw JSON.
  String? lastSchemaJson;

  bool closed = false;

  @override
  String toString() => 'FakeLocalAiSession($id, closed: $closed)';
}

/// A scriptable [LocalAiHost] that records what reached it and lets a test
/// push events back the way a real platform would.
///
/// Published rather than hidden in this package's own tests: an app built on
/// flutter_local_ai cannot otherwise exercise its AI paths in a unit test,
/// because there is no OS model behind `flutter test`.
///
/// ```dart
/// final host = FakeLocalAiHost()..response = 'hello';
/// debugLocalAiHost = host;
/// addTearDown(() async {
///   debugLocalAiHost = null;
///   await host.dispose();
/// });
///
/// expect((await FlutterLocalAi().generateText(prompt: 'hi')).text, 'hello');
/// expect(host.sessions.single.transcript.toString(), 'hi');
/// ```
///
/// Streaming needs the test to play the platform's part, because nothing
/// generates tokens on its own:
///
/// ```dart
/// final chunks = <String>[];
/// final done = session.getResponseAsync().listen(chunks.add).asFuture<void>();
/// await pumpEventQueue();
/// host.emitToken(1, 'partial');
/// host.emitDone(1);
/// await done;
/// ```
class FakeLocalAiHost implements LocalAiHost {
  FakeLocalAiHost({
    this.availability = LocalAiAvailability.available,
    LocalAiBackendCapabilities? capabilities,
  }) : capabilities = capabilities ?? defaultCapabilities;

  /// A capable backend, so a test opts *out* of a feature rather than having
  /// to opt in to all of them.
  static const defaultCapabilities = LocalAiBackendCapabilities(
    backend: LocalAiBackendKind.appleFoundationModels,
    platform: 'fake',
    apiName: 'Fake',
    supportsToolCalling: true,
    supportsStructuredOutput: true,
    supportsVision: true,
    supportsTokenCount: true,
    isConfigured: true,
  );

  /// What [checkAvailability] answers. Mutate mid-test to model a download
  /// finishing.
  LocalAiAvailability availability;

  /// What [getBackendInfo] answers.
  LocalAiBackendCapabilities capabilities;

  /// What [availabilityReason] answers.
  String reason = 'Fake host.';

  /// What every non-streaming generate call returns.
  String response = 'ok';

  /// What [countTokens] returns, unless [countTokensError] is set.
  int countTokensResult = 7;

  /// Thrown by [countTokens] when set. Use [LocalAiTokenizerUnavailable] to
  /// model a host with no tokenizer, or any other error to model a broken
  /// channel.
  Object? countTokensError;

  /// Thrown by [createSession] when set — models a host rejecting tools or
  /// an unsupported configuration.
  Object? createSessionError;

  final _events = StreamController<LocalAiHostEvent>.broadcast();

  /// Method names in call order, for the few assertions that are genuinely
  /// about sequencing. Prefer [sessions] for anything else.
  final List<String> calls = [];

  /// Every session created, in order, open or closed.
  final List<FakeLocalAiSession> sessions = [];

  /// Ids of sessions that were closed, in the order they closed.
  final List<int> closedIds = [];

  /// Whether [closeModel] ran.
  bool modelClosed = false;

  /// Whether [createModel] was asked for image support.
  bool? modelSupportsImage;

  /// The most recent generate call's sampling, across all sessions.
  LocalAiGenerationOverrides? lastOverrides;

  /// The session with [id], or null when it was never created.
  FakeLocalAiSession? session(int id) =>
      sessions.where((s) => s.id == id).firstOrNull;

  FakeLocalAiSession _require(int id) {
    final found = session(id);
    if (found == null || found.closed) {
      throw StateError('No open fake session with id $id.');
    }
    return found;
  }

  // --- driving the fake ---------------------------------------------------

  /// Pushes a raw event. The typed helpers below cover the usual cases.
  void emit(LocalAiHostEvent event) => _events.add(event);

  /// A delta on [sessionId].
  void emitToken(int sessionId, String text) => emit(
    LocalAiTokenEvent(sessionId: sessionId, partialResult: text, done: false),
  );

  /// The terminal event for [sessionId], optionally carrying a last delta.
  void emitDone(int sessionId, {String text = ''}) => emit(
    LocalAiTokenEvent(sessionId: sessionId, partialResult: text, done: true),
  );

  /// A generation failure on [sessionId].
  void emitError(int sessionId, String message) =>
      emit(LocalAiErrorEvent(sessionId: sessionId, message: message));

  /// Download progress. [bytesTotal] of 0 models a host that reports no
  /// total, which is what Android does.
  void emitDownloadProgress(int bytesDownloaded, {int bytesTotal = 0}) => emit(
    LocalAiDownloadProgressEvent(
      bytesDownloaded: bytesDownloaded,
      bytesTotal: bytesTotal,
    ),
  );

  /// Closes the event stream. Call from a tear-down.
  Future<void> dispose() => _events.close();

  // --- LocalAiHost --------------------------------------------------------

  @override
  Stream<LocalAiHostEvent> get events => _events.stream;

  @override
  Future<LocalAiAvailability> checkAvailability() async {
    calls.add('checkAvailability');
    return availability;
  }

  @override
  Future<String> availabilityReason() async => reason;

  @override
  Future<LocalAiBackendCapabilities> getBackendInfo() async => capabilities;

  @override
  Future<void> downloadFeature() async => calls.add('downloadFeature');

  @override
  Future<bool> openAICorePlayStore() async {
    calls.add('openAICorePlayStore');
    return capabilities.supportsPlayStoreRedirect;
  }

  @override
  Future<void> createModel({required bool supportImage}) async {
    calls.add('createModel');
    modelSupportsImage = supportImage;
  }

  @override
  Future<void> closeModel() async {
    calls.add('closeModel');
    modelClosed = true;
  }

  @override
  Future<void> createSession({
    required int sessionId,
    required double temperature,
    required int topK,
    double? topP,
    int? maxOutputTokens,
    String? systemInstruction,
    List<LocalAiTool>? tools,
  }) async {
    calls.add('createSession');
    final error = createSessionError;
    if (error != null) throw error;
    sessions.add(
      FakeLocalAiSession(
        id: sessionId,
        temperature: temperature,
        topK: topK,
        topP: topP,
        maxOutputTokens: maxOutputTokens,
        systemInstruction: systemInstruction,
        toolNames: [for (final tool in tools ?? const []) tool.name],
      ),
    );
  }

  @override
  Future<void> closeSession(int sessionId) async {
    calls.add('closeSession');
    // Tolerates an unknown id the way a real host does: closing twice, or
    // closing after the model went away, must not throw.
    session(sessionId)?.closed = true;
    closedIds.add(sessionId);
  }

  @override
  Future<void> addQueryChunk({
    required int sessionId,
    required String text,
  }) async => _require(sessionId).transcript.write(text);

  @override
  Future<void> addImage({
    required int sessionId,
    required Uint8List imageBytes,
  }) async => _require(sessionId).images.add(imageBytes);

  @override
  Future<String> generateResponse(
    int sessionId, {
    LocalAiGenerationOverrides? overrides,
  }) async {
    calls.add('generateResponse');
    _record(sessionId, overrides);
    return response;
  }

  @override
  Future<void> generateResponseAsync(
    int sessionId, {
    LocalAiGenerationOverrides? overrides,
  }) async {
    calls.add('generateResponseAsync');
    _record(sessionId, overrides);
  }

  @override
  Future<String> generateStructuredResponse({
    required int sessionId,
    required String schemaJson,
    LocalAiGenerationOverrides? overrides,
  }) async {
    calls.add('generateStructuredResponse');
    _record(sessionId, overrides).lastSchemaJson = schemaJson;
    return response;
  }

  @override
  Future<void> stopGeneration(int sessionId) async =>
      calls.add('stopGeneration');

  @override
  Future<int> countTokens(String text) async {
    calls.add('countTokens');
    final error = countTokensError;
    if (error != null) throw error;
    return countTokensResult;
  }

  FakeLocalAiSession _record(
    int sessionId,
    LocalAiGenerationOverrides? overrides,
  ) {
    lastOverrides = overrides;
    return _require(sessionId)..lastOverrides = overrides;
  }
}
