import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import '../../models/tool.dart';
import '../local_ai_host.dart';
import 'prompt_api_interop.dart';

/// Per-session browser state: the Prompt API session, the transcript chunks
/// queued since the last generation, and the controller that cancels an
/// in-flight generation.
class _WebSession {
  _WebSession(this.session);

  final PromptSession session;
  final StringBuffer transcript = StringBuffer();
  AbortController? inFlight;

  /// Drains the queued chunks — a generation consumes them, exactly as the
  /// native hosts consume their buffered transcript.
  String takeTranscript() {
    final text = transcript.toString();
    transcript.clear();
    return text;
  }
}

/// Web host, over Chrome's Prompt API.
///
/// Diverges from the native hosts in three documented ways, all reflected in
/// [getBackendInfo]: no image input (the Prompt API's multimodal path is not
/// usable from a page as of Chrome 151), no native tool calling (its `tools`
/// option is behind an experimental flag and does not reliably route), but it
/// *does* support schema-constrained output via `responseConstraint`, which
/// Android cannot do.
class WebLocalAiHost implements LocalAiHost {
  final _events = StreamController<LocalAiHostEvent>.broadcast();
  final Map<int, _WebSession> _sessions = {};

  bool _supportImage = false;
  bool _warnedOverrides = false;

  @override
  Stream<LocalAiHostEvent> get events => _events.stream;

  _WebSession _require(int sessionId) {
    final session = _sessions[sessionId];
    if (session == null) {
      throw StateError('No built-in AI session with id $sessionId');
    }
    return session;
  }

  @override
  Future<LocalAiAvailability> checkAvailability() async {
    if (!hasLanguageModel) {
      return LocalAiAvailability.unavailableDeviceUnsupported;
    }
    try {
      final status = (await LanguageModel.availability().toDart).toDart;
      return switch (status) {
        'available' => LocalAiAvailability.available,
        'downloadable' => LocalAiAvailability.downloadable,
        'downloading' => LocalAiAvailability.downloading,
        // Chrome's 'unavailable' carries no reason — disk floor, VRAM, or a
        // missing origin trial all collapse into it, so the unclassified
        // bucket is the honest mapping.
        _ => LocalAiAvailability.unavailableOther,
      };
    } catch (_) {
      // The probe's contract is to resolve, never throw: a rejected promise
      // (transient browser/permission failure) is unclassified, not fatal.
      return LocalAiAvailability.unavailableOther;
    }
  }

  @override
  Future<String> availabilityReason() async {
    if (!hasLanguageModel) {
      return 'This browser does not expose the Prompt API. Use desktop '
          'Chrome or Chromium-Edge with the Prompt API enabled (origin trial '
          'token, or chrome://flags/#prompt-api-for-gemini-nano).';
    }
    return switch (await checkAvailability()) {
      LocalAiAvailability.available => 'Gemini Nano is ready.',
      LocalAiAvailability.downloadable =>
        'Gemini Nano is not downloaded yet. Call LocalAi.ensureReady() to '
            'fetch it.',
      LocalAiAvailability.downloading =>
        'Gemini Nano is downloading. Call LocalAi.ensureReady() and wait.',
      _ =>
        'The Prompt API reported the model as unavailable without a '
            'reason. Common causes are too little free disk (~22 GB needed), '
            'an ineligible GPU, or a missing origin-trial token.',
    };
  }

  @override
  Future<LocalAiBackendCapabilities> getBackendInfo() async =>
      LocalAiBackendCapabilities(
        backend: hasLanguageModel
            ? LocalAiBackendKind.chromePromptApi
            : LocalAiBackendKind.unsupported,
        platform: 'web',
        apiName: 'Chrome Prompt API (Gemini Nano)',
        // Experimental and unreliable in Chrome 151 — the bridge weaves tools
        // into the prompt instead.
        supportsToolCalling: false,
        supportsStructuredOutput: true,
        supportsVision: false,
        supportsTokenCount: true,
        supportsModelDownload: true,
        supportsPlayStoreRedirect: false,
        isConfigured: hasLanguageModel,
      );

  @override
  Future<void> downloadFeature() async {
    if (!hasLanguageModel) {
      throw LocalAiUnavailableException(
        LocalAiAvailability.unavailableDeviceUnsupported,
        'The Prompt API is not available in this browser.',
      );
    }
    // `create()` performs (and dedupes) the download; there is no separate
    // kick-off call. The bootstrap session is disposed once it resolves —
    // Chrome keeps the weights cached regardless.
    final options = buildCreateOptions(
      onDownloadProgress: (loaded) {
        // `loaded` is a 0..1 fraction; scale to a byte-shaped pair so the
        // event matches what the native hosts emit.
        _events.add(
          LocalAiDownloadProgressEvent(
            bytesDownloaded: (loaded * 100).clamp(0, 100).round(),
            bytesTotal: 100,
          ),
        );
      },
    );
    final session = await LanguageModel.create(options).toDart;
    session.destroy();
  }

  @override
  Future<bool> openAICorePlayStore() async => false;

  @override
  Future<void> createModel({required bool supportImage}) async {
    if (!hasLanguageModel) {
      throw LocalAiUnavailableException(
        LocalAiAvailability.unavailableDeviceUnsupported,
        'The Prompt API is not available in this browser.',
      );
    }
    _supportImage = supportImage;
  }

  @override
  Future<void> closeModel() async {
    for (final session in _sessions.values) {
      session.session.destroy();
    }
    _sessions.clear();
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
      throw LocalAiUnsupportedException(
        'toolCalling',
        'Chrome\'s Prompt API has no production tool-calling surface; its '
            '`tools` option is behind an experimental flag and does not '
            'reliably route. Use prompt-woven tools instead.',
      );
    }
    // topP and maxOutputTokens have no Prompt API equivalent. They are
    // accepted for cross-platform API parity and deliberately dropped rather
    // than faked — sampling stays whatever temperature/topK select.
    final options = buildCreateOptions(
      systemInstruction: systemInstruction,
      temperature: temperature,
      topK: topK,
      expectedInputTypes: _supportImage ? const ['text', 'image'] : null,
    );
    _sessions[sessionId] = _WebSession(
      await LanguageModel.create(options).toDart,
    );
  }

  @override
  Future<void> closeSession(int sessionId) async {
    _sessions.remove(sessionId)?.session.destroy();
  }

  @override
  Future<void> addQueryChunk({
    required int sessionId,
    required String text,
  }) async {
    _require(sessionId).transcript.write(text);
  }

  @override
  Future<void> addImage({
    required int sessionId,
    required Uint8List imageBytes,
  }) async {
    throw LocalAiUnsupportedException(
      'vision',
      'Image input is not supported on the web arm: the Prompt API\'s '
          'multimodal path is not usable from an ordinary page as of Chrome '
          '151. Check LocalAiBackendCapabilities.supportsVision first.',
    );
  }

  @override
  Future<String> generateResponse(
    int sessionId, {
    LocalAiGenerationOverrides? overrides,
  }) async {
    final state = _require(sessionId);
    _warnOverridesIgnored(overrides);
    final controller = AbortController();
    state.inFlight = controller;
    try {
      final options = buildPromptOptions(signal: controller.signal);
      final response = await state.session
          .prompt(state.takeTranscript().toJS, options)
          .toDart;
      return response.toDart;
    } finally {
      state.inFlight = null;
    }
  }

  @override
  Future<void> generateResponseAsync(
    int sessionId, {
    LocalAiGenerationOverrides? overrides,
  }) async {
    final state = _require(sessionId);
    _warnOverridesIgnored(overrides);
    final controller = AbortController();
    state.inFlight = controller;
    final options = buildPromptOptions(signal: controller.signal);
    final stream = state.session.promptStreaming(
      state.takeTranscript().toJS,
      options,
    );

    // Deliberately not awaited: the contract is that this call *starts*
    // generation and output arrives on the event stream, matching the native
    // hosts. Errors become tagged error events rather than escaping here,
    // where nothing is listening for them.
    unawaited(() async {
      try {
        await pumpTextStream(stream, (chunk) {
          _events.add(
            LocalAiTokenEvent(
              sessionId: sessionId,
              partialResult: chunk,
              done: false,
            ),
          );
        });
        _events.add(
          LocalAiTokenEvent(
            sessionId: sessionId,
            partialResult: '',
            done: true,
          ),
        );
      } catch (e) {
        _events.add(
          LocalAiErrorEvent(sessionId: sessionId, message: e.toString()),
        );
      } finally {
        state.inFlight = null;
      }
    }());
  }

  @override
  Future<String> generateStructuredResponse({
    required int sessionId,
    required String schemaJson,
    LocalAiGenerationOverrides? overrides,
  }) async {
    final state = _require(sessionId);
    _warnOverridesIgnored(overrides);
    final controller = AbortController();
    state.inFlight = controller;
    try {
      final options = buildPromptOptions(
        responseConstraint: jsonDecode(schemaJson),
        signal: controller.signal,
      );
      final response = await state.session
          .prompt(state.takeTranscript().toJS, options)
          .toDart;
      return response.toDart;
    } finally {
      state.inFlight = null;
    }
  }

  @override
  Future<void> stopGeneration(int sessionId) async {
    _sessions[sessionId]?.inFlight?.abort();
  }

  /// Chrome fixes sampling at `create()`; `prompt()` takes no temperature or
  /// topK. Rather than silently ignore an override, say so once — repeating
  /// it per token would drown the console.
  void _warnOverridesIgnored(LocalAiGenerationOverrides? overrides) {
    if (overrides == null || overrides.isEmpty || _warnedOverrides) return;
    _warnedOverrides = true;
    // ignore: avoid_print
    print(
      '[flutter_local_ai/web] Per-call sampling overrides are ignored: the '
      'Chrome Prompt API fixes temperature and topK when the session is '
      'created. Create a session with the sampling you want instead.',
    );
  }

  @override
  Future<int> countTokens(String text) async {
    // measureInputUsage is a session method, so borrow any live session; with
    // none open there is nothing to measure against.
    final state = _sessions.values.firstOrNull;
    if (state == null) {
      throw LocalAiTokenizerUnavailable(
        'Counting tokens on the web arm needs an open session — '
        'measureInputUsage is a session method.',
      );
    }
    final usage = await state.session.measureInputUsage(text.toJS).toDart;
    return usage.toDartDouble.round();
  }
}

/// The host for this platform.
LocalAiHost createLocalAiHost() => WebLocalAiHost();
