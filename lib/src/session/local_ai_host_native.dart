import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/tool.dart';
import '../pigeon/local_ai_api.g.dart' as wire;
import 'local_ai_host_api.dart';
import 'local_ai_tool_registry.dart';

/// Tokens, generation errors and download progress from the native hosts.
/// A single channel for every session (payloads carry `sessionId`), matching
/// the shape flutter_gemma_builtin_ai uses, so the native demux logic is the
/// same one that has already been proven against AICore and FoundationModels.
const _eventChannel = EventChannel('flutter_local_ai_events');

LocalAiAvailability _availabilityFromWire(wire.AvailabilityStatus status) =>
    switch (status) {
      wire.AvailabilityStatus.available => LocalAiAvailability.available,
      wire.AvailabilityStatus.downloadable => LocalAiAvailability.downloadable,
      wire.AvailabilityStatus.downloading => LocalAiAvailability.downloading,
      wire.AvailabilityStatus.unavailableDeviceUnsupported =>
        LocalAiAvailability.unavailableDeviceUnsupported,
      wire.AvailabilityStatus.unavailableOsTooOld =>
        LocalAiAvailability.unavailableOsTooOld,
      wire.AvailabilityStatus.unavailableDisabled =>
        LocalAiAvailability.unavailableDisabled,
      wire.AvailabilityStatus.unavailableOther =>
        LocalAiAvailability.unavailableOther,
    };

LocalAiBackendKind _backendFromWire(
  wire.LocalAiBackend backend,
) => switch (backend) {
  wire.LocalAiBackend.androidMlKitGenAi => LocalAiBackendKind.androidMlKitGenAi,
  wire.LocalAiBackend.appleFoundationModels =>
    LocalAiBackendKind.appleFoundationModels,
  wire.LocalAiBackend.windowsAiFoundry => LocalAiBackendKind.windowsAiFoundry,
  wire.LocalAiBackend.windowsAiFoundryUnconfigured =>
    LocalAiBackendKind.windowsAiFoundryUnconfigured,
  wire.LocalAiBackend.chromePromptApi => LocalAiBackendKind.chromePromptApi,
  wire.LocalAiBackend.unsupported => LocalAiBackendKind.unsupported,
};

wire.GenerationOverrides? _overridesToWire(
  LocalAiGenerationOverrides? overrides,
) => overrides == null || overrides.isEmpty
    ? null
    : wire.GenerationOverrides(
        temperature: overrides.temperature,
        topP: overrides.topP,
        topK: overrides.topK,
        maxOutputTokens: overrides.maxOutputTokens,
      );

wire.ToolSpec _toolToWire(LocalAiTool tool) => wire.ToolSpec(
  name: tool.name,
  description: tool.description,
  // The whole declaration, as JSON Schema: the host builds the tool's
  // parameter schema with the same builder it uses for structured output, so
  // a nested object, a list or a string enum survives the trip instead of
  // flattening to a bare scalar.
  parametersSchemaJson: jsonEncode(tool.resolvedParameterSchema),
);

/// Native host: pigeon for calls, one EventChannel for streamed output.
///
/// Also serves as the Dart end of the tool-calling callback — the native side
/// suspends generation, asks us to run a tool, and resumes with the result.
class NativeLocalAiHost implements LocalAiHost, wire.LocalAiToolRunner {
  NativeLocalAiHost() {
    wire.LocalAiToolRunner.setUp(this);
  }

  final _service = wire.LocalAiService();

  final _tools = LocalAiToolRegistry();

  Stream<LocalAiHostEvent>? _events;

  @override
  Stream<LocalAiHostEvent> get events =>
      _events ??= _eventChannel.receiveBroadcastStream().transform(
        StreamTransformer<dynamic, LocalAiHostEvent>.fromHandlers(
          handleData: (event, sink) {
            final parsed = _parseEvent(event);
            if (parsed != null) sink.add(parsed);
          },
        ),
      );

  LocalAiHostEvent? _parseEvent(Object? event) {
    if (event is! Map) return null;
    if (event['code'] == 'DOWNLOAD_PROGRESS') {
      return LocalAiDownloadProgressEvent(
        bytesDownloaded: (event['bytesDownloaded'] as num?)?.toInt() ?? 0,
        bytesTotal: (event['bytesTotal'] as num?)?.toInt() ?? 0,
      );
    }
    final sessionId = (event['sessionId'] as num?)?.toInt();
    // Anything session-scoped without an id can't be routed; dropping it is
    // better than guessing an owner.
    if (sessionId == null) return null;
    if (event['code'] == 'ERROR') {
      return LocalAiErrorEvent(
        sessionId: sessionId,
        message: event['message']?.toString() ?? 'Unknown generation error',
      );
    }
    return LocalAiTokenEvent(
      sessionId: sessionId,
      partialResult: event['partialResult'] as String? ?? '',
      done: event['done'] == true,
    );
  }

  @override
  Future<String?> onToolCall(
    int sessionId,
    String toolName,
    String argumentsJson,
  ) async {
    try {
      return await _tools.invoke(sessionId, toolName, argumentsJson);
    } on UnknownToolException catch (e) {
      // Crosses back to native as a platform error the model can be told
      // about, rather than an arbitrary Dart exception unwinding through it.
      throw PlatformException(code: 'TOOL_NOT_FOUND', message: '$e');
    }
  }

  @override
  Future<LocalAiAvailability> checkAvailability() async =>
      _availabilityFromWire(await _service.checkAvailability());

  @override
  Future<String> availabilityReason() => _service.availabilityReason();

  @override
  Future<LocalAiBackendCapabilities> getBackendInfo() async {
    final info = await _service.getBackendInfo();
    return LocalAiBackendCapabilities(
      backend: _backendFromWire(info.backend),
      platform: info.platform,
      apiName: info.apiName,
      supportsToolCalling: info.supportsToolCalling,
      supportsStructuredOutput: info.supportsStructuredOutput,
      supportsVision: info.supportsVision,
      supportsTokenCount: info.supportsTokenCount,
      supportsModelDownload: info.supportsModelDownload,
      supportsPlayStoreRedirect: info.supportsPlayStoreRedirect,
      isConfigured: info.isConfigured,
    );
  }

  @override
  Future<void> downloadFeature() => _service.downloadFeature();

  @override
  Future<bool> openAICorePlayStore() => _service.openAICorePlayStore();

  @override
  Future<void> createModel({required bool supportImage}) =>
      _service.createModel(supportImage: supportImage);

  @override
  Future<void> closeModel() async {
    // Every session dies with the model; drop their handlers so a late native
    // callback can't reach a tool the app considers unregistered.
    _tools.clear();
    await _service.closeModel();
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
    _tools.register(sessionId, tools);
    try {
      await _service.createSession(
        sessionId: sessionId,
        temperature: temperature,
        topK: topK,
        topP: topP,
        maxOutputTokens: maxOutputTokens,
        systemInstruction: systemInstruction,
        tools: tools?.map(_toolToWire).toList(),
      );
    } catch (_) {
      // The native session doesn't exist, so nothing can call these.
      _tools.forget(sessionId);
      rethrow;
    }
  }

  @override
  Future<void> closeSession(int sessionId) async {
    await _service.closeSession(sessionId);
    _tools.forget(sessionId); // Not before: a failed close must stay retryable.
  }

  @override
  Future<void> addQueryChunk({required int sessionId, required String text}) =>
      _busy(
        sessionId,
        _service.addQueryChunk(sessionId: sessionId, text: text),
      );

  @override
  Future<void> addImage({
    required int sessionId,
    required Uint8List imageBytes,
  }) => _busy(
    sessionId,
    _service.addImage(sessionId: sessionId, imageBytes: imageBytes),
  );

  @override
  Future<String> generateResponse(
    int sessionId, {
    LocalAiGenerationOverrides? overrides,
  }) => _busy(
    sessionId,
    _service.generateResponse(sessionId, _overridesToWire(overrides)),
  );

  @override
  Future<void> generateResponseAsync(
    int sessionId, {
    LocalAiGenerationOverrides? overrides,
  }) => _busy(
    sessionId,
    _service.generateResponseAsync(sessionId, _overridesToWire(overrides)),
  );

  @override
  Future<String> generateStructuredResponse({
    required int sessionId,
    required String schemaJson,
    LocalAiGenerationOverrides? overrides,
  }) => _busy(
    sessionId,
    _service.generateStructuredResponse(
      sessionId: sessionId,
      schemaJson: schemaJson,
      overrides: _overridesToWire(overrides),
    ),
  );

  /// Maps `SESSION_BUSY` to the type the web host throws for the same misuse.
  static Future<T> _busy<T>(int sessionId, Future<T> call) => call.catchError(
    (Object e) => throw LocalAiSessionBusyException(
      sessionId,
      (e as PlatformException).message ?? 'Session is busy.',
    ),
    test: (e) => e is PlatformException && e.code == 'SESSION_BUSY',
  );

  @override
  Future<void> stopGeneration(int sessionId) =>
      _service.stopGeneration(sessionId);

  @override
  Future<int> countTokens({
    required int sessionId,
    required String text,
  }) async {
    // Every native tokenizer is model-wide, so [sessionId] stays on this side
    // of the channel.
    try {
      return await _service.countTokens(text);
    } on PlatformException catch (e) {
      // `channel-error` / `null-error` are pigeon infrastructure failures — the
      // plugin isn't registered, or this platform has no implementation. Those
      // are wiring bugs, so let them through rather than masking a broken
      // install as a plausible-looking token count.
      if (e.code != 'TOKENIZER_UNAVAILABLE') rethrow;
      throw LocalAiTokenizerUnavailable(e.message ?? e.code);
    }
  }
}

/// The host for this platform.
LocalAiHost createLocalAiHost() => NativeLocalAiHost();
