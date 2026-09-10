import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_local_ai/flutter_local_ai.dart';

/// A scriptable [LocalAiHost] for tests: records what the Dart layer sent and
/// lets a test push events back as a real host would.
class FakeLocalAiHost implements LocalAiHost {
  FakeLocalAiHost({
    this.availability = LocalAiAvailability.available,
    this.capabilities = const LocalAiBackendCapabilities(
      backend: LocalAiBackendKind.appleFoundationModels,
      platform: 'test',
      apiName: 'Fake',
      supportsTokenCount: true,
    ),
  });

  LocalAiAvailability availability;
  LocalAiBackendCapabilities capabilities;

  final _events = StreamController<LocalAiHostEvent>.broadcast();

  final List<String> calls = [];
  final Map<int, StringBuffer> transcripts = {};
  final Map<int, List<Uint8List>> images = {};
  final List<int> closedSessions = [];

  /// Sessions created, in order, with the arguments they were created with.
  final List<Map<String, Object?>> createdSessions = [];

  String response = 'ok';

  /// Sampling the last generate call carried, so tests can assert that a
  /// GenerationConfig reached the host instead of being dropped.
  LocalAiGenerationOverrides? lastOverrides;
  Object? countTokensError;
  int countTokensResult = 7;

  void emit(LocalAiHostEvent event) => _events.add(event);

  @override
  Stream<LocalAiHostEvent> get events => _events.stream;

  @override
  Future<LocalAiAvailability> checkAvailability() async {
    calls.add('checkAvailability');
    return availability;
  }

  @override
  Future<String> availabilityReason() async => 'because';

  @override
  Future<LocalAiBackendCapabilities> getBackendInfo() async => capabilities;

  @override
  Future<void> downloadFeature() async => calls.add('downloadFeature');

  @override
  Future<bool> openAICorePlayStore() async => false;

  @override
  Future<void> createModel({required bool supportImage}) async =>
      calls.add('createModel(supportImage: $supportImage)');

  @override
  Future<void> closeModel() async => calls.add('closeModel');

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
    calls.add('createSession($sessionId)');
    createdSessions.add({
      'sessionId': sessionId,
      'temperature': temperature,
      'topK': topK,
      'topP': topP,
      'maxOutputTokens': maxOutputTokens,
      'systemInstruction': systemInstruction,
      'tools': tools?.map((t) => t.name).toList(),
    });
    transcripts[sessionId] = StringBuffer();
  }

  @override
  Future<void> closeSession(int sessionId) async {
    calls.add('closeSession($sessionId)');
    closedSessions.add(sessionId);
    transcripts.remove(sessionId);
  }

  @override
  Future<void> addQueryChunk({
    required int sessionId,
    required String text,
  }) async {
    transcripts.putIfAbsent(sessionId, StringBuffer.new).write(text);
  }

  @override
  Future<void> addImage({
    required int sessionId,
    required Uint8List imageBytes,
  }) async {
    images.putIfAbsent(sessionId, () => []).add(imageBytes);
  }

  @override
  Future<String> generateResponse(
    int sessionId, {
    LocalAiGenerationOverrides? overrides,
  }) async {
    calls.add('generateResponse($sessionId)');
    lastOverrides = overrides;
    return response;
  }

  @override
  Future<void> generateResponseAsync(
    int sessionId, {
    LocalAiGenerationOverrides? overrides,
  }) async {
    calls.add('generateResponseAsync($sessionId)');
    lastOverrides = overrides;
  }

  @override
  Future<String> generateStructuredResponse({
    required int sessionId,
    required String schemaJson,
    LocalAiGenerationOverrides? overrides,
  }) async {
    calls.add('generateStructuredResponse($sessionId, $schemaJson)');
    lastOverrides = overrides;
    return response;
  }

  @override
  Future<void> stopGeneration(int sessionId) async =>
      calls.add('stopGeneration($sessionId)');

  @override
  Future<int> countTokens(String text) async {
    final error = countTokensError;
    if (error != null) throw error;
    return countTokensResult;
  }

  Future<void> dispose() => _events.close();
}
