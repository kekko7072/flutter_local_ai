import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/tool.dart';
import '../pigeon/local_ai_api.g.dart' as wire;
import 'local_ai_host.dart';

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

LocalAiBackendKind _backendFromWire(wire.LocalAiBackend backend) =>
    switch (backend) {
      wire.LocalAiBackend.androidMlKitGenAi =>
        LocalAiBackendKind.androidMlKitGenAi,
      wire.LocalAiBackend.appleFoundationModels =>
        LocalAiBackendKind.appleFoundationModels,
      wire.LocalAiBackend.windowsAiFoundry =>
        LocalAiBackendKind.windowsAiFoundry,
      wire.LocalAiBackend.windowsAiFoundryUnconfigured =>
        LocalAiBackendKind.windowsAiFoundryUnconfigured,
      wire.LocalAiBackend.chromePromptApi =>
        LocalAiBackendKind.chromePromptApi,
      wire.LocalAiBackend.unsupported => LocalAiBackendKind.unsupported,
    };

wire.ToolArgumentKind _kindFromType(ToolArgumentType type) => switch (type) {
      ToolArgumentType.string => wire.ToolArgumentKind.string,
      ToolArgumentType.integer => wire.ToolArgumentKind.integer,
      ToolArgumentType.number => wire.ToolArgumentKind.number,
      ToolArgumentType.boolean => wire.ToolArgumentKind.boolean,
    };

wire.ToolSpec _toolToWire(LocalAiTool tool) => wire.ToolSpec(
      name: tool.name,
      description: tool.description,
      parameters: [
        for (final parameter in tool.parameters)
          wire.ToolParameterSpec(
            name: parameter.name,
            kind: _kindFromType(parameter.type),
            optional: parameter.optional,
            description: parameter.description,
          ),
      ],
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

  /// Tools by session, so a tool call arriving for one session can never
  /// invoke another session's handler.
  final Map<int, Map<String, LocalAiTool>> _toolsBySession = {};

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
    final tool = _toolsBySession[sessionId]?[toolName];
    if (tool == null) {
      throw PlatformException(
        code: 'TOOL_NOT_FOUND',
        message: 'No tool named "$toolName" is registered for session '
            '$sessionId.',
      );
    }
    final decoded = argumentsJson.isEmpty ? null : jsonDecode(argumentsJson);
    final arguments = decoded is Map
        ? decoded.map((key, value) => MapEntry(key.toString(), value))
        : <String, dynamic>{};
    final result = await tool.onCall(arguments);
    return result == null ? null : jsonEncode(result);
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
    _toolsBySession.clear();
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
    if (tools != null && tools.isNotEmpty) {
      _toolsBySession[sessionId] = {
        for (final tool in tools) tool.name: tool,
      };
    }
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
      _toolsBySession.remove(sessionId);
      rethrow;
    }
  }

  @override
  Future<void> closeSession(int sessionId) async {
    _toolsBySession.remove(sessionId);
    await _service.closeSession(sessionId);
  }

  @override
  Future<void> addQueryChunk({
    required int sessionId,
    required String text,
  }) =>
      _service.addQueryChunk(sessionId: sessionId, text: text);

  @override
  Future<void> addImage({
    required int sessionId,
    required Uint8List imageBytes,
  }) =>
      _service.addImage(sessionId: sessionId, imageBytes: imageBytes);

  @override
  Future<String> generateResponse(int sessionId) =>
      _service.generateResponse(sessionId);

  @override
  Future<void> generateResponseAsync(int sessionId) =>
      _service.generateResponseAsync(sessionId);

  @override
  Future<String> generateStructuredResponse({
    required int sessionId,
    required String schemaJson,
  }) =>
      _service.generateStructuredResponse(
        sessionId: sessionId,
        schemaJson: schemaJson,
      );

  @override
  Future<void> stopGeneration(int sessionId) =>
      _service.stopGeneration(sessionId);

  @override
  Future<int> countTokens(String text) async {
    try {
      return await _service.countTokens(text);
    } on PlatformException catch (e) {
      // `channel-error` / `null-error` are pigeon infrastructure failures — the
      // plugin isn't registered, or this platform has no implementation. Those
      // are wiring bugs, so let them through rather than masking a broken
      // install as a plausible-looking token count.
      if (e.code == 'channel-error' || e.code == 'null-error') rethrow;
      throw LocalAiTokenizerUnavailable(e.message ?? e.code);
    }
  }
}

/// The host for this platform.
LocalAiHost createLocalAiHost() => NativeLocalAiHost();
