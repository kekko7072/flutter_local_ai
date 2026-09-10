import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_local_ai/flutter_local_ai.dart';

/// Minimal scriptable host. Deliberately a local copy rather than an import
/// from flutter_local_ai's own test tree — test doubles are not published API.
class FakeLocalAiHost implements LocalAiHost {
  FakeLocalAiHost({this.availability = LocalAiAvailability.available});

  LocalAiAvailability availability;

  final _events = StreamController<LocalAiHostEvent>.broadcast();

  final List<String> calls = [];
  final Map<int, StringBuffer> transcripts = {};
  final Map<int, List<Uint8List>> images = {};
  final List<Map<String, Object?>> createdSessions = [];
  final List<int> closedSessions = [];

  String response = 'ok';

  /// Sampling the last generate call carried, so tests can assert that a
  /// GenerationConfig reached the host instead of being dropped.
  LocalAiGenerationOverrides? lastOverrides;

  void emit(LocalAiHostEvent event) => _events.add(event);

  @override
  Stream<LocalAiHostEvent> get events => _events.stream;

  @override
  Future<LocalAiAvailability> checkAvailability() async => availability;

  @override
  Future<String> availabilityReason() async => 'because';

  @override
  Future<LocalAiBackendCapabilities> getBackendInfo() async =>
      const LocalAiBackendCapabilities(
        backend: LocalAiBackendKind.appleFoundationModels,
        platform: 'test',
        apiName: 'Fake',
      );

  @override
  Future<void> downloadFeature() async => calls.add('downloadFeature');

  @override
  Future<bool> openAICorePlayStore() async => false;

  @override
  Future<void> createModel({required bool supportImage}) async =>
      calls.add('createModel');

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
    createdSessions.add({
      'sessionId': sessionId,
      'temperature': temperature,
      'topK': topK,
      'systemInstruction': systemInstruction,
      'maxOutputTokens': maxOutputTokens,
      'tools': tools?.map((t) => t.name).toList(),
    });
    transcripts[sessionId] = StringBuffer();
  }

  @override
  Future<void> closeSession(int sessionId) async {
    closedSessions.add(sessionId);
    transcripts.remove(sessionId);
  }

  @override
  Future<void> addQueryChunk({
    required int sessionId,
    required String text,
  }) async =>
      transcripts.putIfAbsent(sessionId, StringBuffer.new).write(text);

  @override
  Future<void> addImage({
    required int sessionId,
    required Uint8List imageBytes,
  }) async =>
      images.putIfAbsent(sessionId, () => []).add(imageBytes);

  @override
  Future<String> generateResponse(
    int sessionId, {
    LocalAiGenerationOverrides? overrides,
  }) async {
    lastOverrides = overrides;
    return response;
  }

  @override
  Future<void> generateResponseAsync(
    int sessionId, {
    LocalAiGenerationOverrides? overrides,
  }) async {
    lastOverrides = overrides;
  }

  @override
  Future<String> generateStructuredResponse({
    required int sessionId,
    required String schemaJson,
    LocalAiGenerationOverrides? overrides,
  }) async {
    lastOverrides = overrides;
    return response;
  }

  @override
  Future<void> stopGeneration(int sessionId) async =>
      calls.add('stopGeneration($sessionId)');

  @override
  Future<int> countTokens(String text) async => 5;

  Future<void> dispose() => _events.close();
}
