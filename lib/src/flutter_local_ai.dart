import 'dart:async';

import 'models/ai_response.dart';
import 'models/generation_config.dart';
import 'models/model_status.dart';
import 'models/platform_info.dart';
import 'models/tool.dart';
import 'session/local_ai.dart';
import 'session/local_ai_host.dart';
import 'session/local_ai_model.dart';
import 'session/local_ai_runtime.dart';
import 'session/local_ai_session.dart';

/// Prompt-oriented entry point to the OS built-in model.
///
/// One conversation, one call per turn. Everything here runs on the same
/// session machinery as [LocalAiModel] — this is a shorter path through it,
/// not a second implementation. Reach for [LocalAiModel] directly when you
/// need several conversations at once, image input, cancellation, or explicit
/// lifecycle control.
///
/// State is process-wide: every `FlutterLocalAi()` shares one model and one
/// session, because the OS model itself is a single process-wide resource.
/// Constructing more instances is free and changes nothing.
class FlutterLocalAi {
  /// [host] is a test seam; production code omits it and gets the platform
  /// host.
  FlutterLocalAi({LocalAiHost? host}) : _explicitHost = host;

  final LocalAiHost? _explicitHost;

  LocalAiHost get _host => _explicitHost ?? localAiHost;

  static const _defaultInstructions =
      'You are a helpful assistant. Provide concise answers.';

  // Shared across instances: see the class doc.
  static LocalAiModel? _model;
  static LocalAiSession? _session;
  static String _instructions = _defaultInstructions;
  static List<LocalAiTool> _tools = const [];

  /// Drops the shared model and session. Tests only — production code has no
  /// reason to tear the OS model down and rebuild it.
  static Future<void> debugReset() async {
    _session = null;
    final model = _model;
    _model = null;
    _instructions = _defaultInstructions;
    _tools = const [];
    await model?.close();
  }

  Future<LocalAiModel> _ensureModel() async =>
      _model ??= await LocalAiModel.create(host: _host);

  /// The shared session, created on first use so callers that never call
  /// [initialize] still work.
  Future<LocalAiSession> _ensureSession() async {
    final existing = _session;
    if (existing != null && !existing.isClosed) return existing;
    final model = await _ensureModel();
    final session = await model.openSession(
      systemInstruction: _instructions,
      tools: _tools.isEmpty ? null : _tools,
    );
    _session = session;
    return session;
  }

  /// Whether the OS model can be used right now.
  ///
  /// Never throws: every failure mode — no eligible device, a feature that
  /// needs downloading, an OS that is too old — answers false. Use
  /// [availabilityReason] to tell the user which it was, or
  /// [LocalAi.availability] for the machine-readable status.
  Future<bool> isAvailable() async =>
      await LocalAi.availability(host: _host) == LocalAiAvailability.available;

  /// One human-readable sentence naming what the user would have to change —
  /// enable Apple Intelligence, update the OS, use an eligible device.
  Future<String> availabilityReason() async {
    try {
      return await _host.availabilityReason();
    } catch (e) {
      return 'The built-in model could not be reached: $e';
    }
  }

  /// What the running backend supports.
  ///
  /// [LocalAi.capabilities] returns the same information in richer form,
  /// including vision and exact-token-count support, which this view has no
  /// fields for.
  Future<LocalAiPlatformInfo> getPlatformInfo() async {
    try {
      return LocalAiPlatformInfo.fromCapabilities(await _host.getBackendInfo());
    } catch (_) {
      return LocalAiPlatformInfo.unsupported;
    }
  }

  /// Loads the model and starts a fresh conversation with [instructions].
  ///
  /// Optional: the first [generateText] creates a session on its own with
  /// default instructions. Calling this again discards the current
  /// conversation and starts a new one, which is the way to change
  /// instructions mid-run.
  ///
  /// Returns true on success; throws when the model cannot be loaded.
  Future<bool> initialize({String? instructions}) async {
    try {
      _instructions = instructions ?? _defaultInstructions;
      final previous = _session;
      _session = null;
      await previous?.close();
      await _ensureSession();
      return true;
    } catch (e) {
      throw Exception('Failed to initialize: $e');
    }
  }

  /// Generates a response to [prompt].
  ///
  /// [instructions] runs the call statelessly: a throwaway session with
  /// exactly those instructions, leaving the shared conversation untouched
  /// and contributing nothing to its context window. Callers that manage
  /// their own conversation history should always pass it.
  ///
  /// Without [instructions] the call joins the shared conversation, so
  /// successive calls see each other — on every platform. (Before the session
  /// rewrite, Android silently discarded history here while Apple kept it.)
  ///
  /// A [GenerationConfig.schema] constrains output to that schema on backends
  /// that support it, and throws on those that do not — check
  /// `getPlatformInfo().supportsStructuredOutput` first. The schema is
  /// validated in Dart before any platform call, so an unsupported construct
  /// fails with a path-qualified [ArgumentError] rather than an opaque native
  /// error.
  Future<AiResponse> generateText({
    required String prompt,
    GenerationConfig? config,
    String? instructions,
  }) async {
    config?.validateSchema();
    final started = DateTime.now();
    try {
      final session = instructions != null
          ? await _openOneShot(instructions)
          : await _ensureSession();
      try {
        await session.addQueryChunk(prompt);
        final overrides = _overridesFor(config);
        final schema = config?.schema;
        final text = config?.requestsStructuredOutput ?? false
            ? await session.getStructuredResponse(schema!, overrides: overrides)
            : await session.getResponse(overrides: overrides);
        return AiResponse(
          text: text,
          tokenCount: await _countOrNull(session, text),
          generationTimeMs: DateTime.now().difference(started).inMilliseconds,
        );
      } finally {
        // A one-shot session must not outlive its call, or the OS keeps a
        // context alive for a conversation nobody will continue.
        if (instructions != null) await session.close();
      }
    } on ArgumentError {
      rethrow;
    } catch (e) {
      throw Exception('Failed to generate text: $e');
    }
  }

  /// Streams the response to [prompt] as deltas — each event is the new text,
  /// not the running total.
  ///
  /// [instructions] behaves as in [generateText]. Backends with no streaming
  /// path surface an error on the stream instead, so callers can fall back to
  /// [generateText].
  ///
  /// Schema-constrained streaming is rejected up front on every backend: no
  /// OS model can constrain streamed output today, and returning free-form
  /// text from a call that asked for JSON would be worse than failing.
  Stream<String> generateTextStream({
    required String prompt,
    GenerationConfig? config,
    String? instructions,
  }) {
    if (config?.requestsStructuredOutput ?? false) {
      return Stream<String>.error(
        ArgumentError.value(
          config,
          'config',
          'Streaming structured (JSON/schema) output is not supported on any '
              'backend yet. Use generateText() for schema-constrained output, '
              'or call generateTextStream() without a schema / '
              'ResponseFormat.json.',
        ),
      );
    }

    // A StreamController rather than `async*` so the one-shot session is
    // closed on cancel as well as on done and error.
    final controller = StreamController<String>();
    LocalAiSession? oneShot;

    controller.onListen = () async {
      try {
        final session = instructions != null
            ? (oneShot = await _openOneShot(instructions))
            : await _ensureSession();
        await session.addQueryChunk(prompt);
        await controller.addStream(
          session.getResponseAsync(overrides: _overridesFor(config)),
        );
      } catch (e, stackTrace) {
        if (!controller.isClosed) controller.addError(e, stackTrace);
      } finally {
        await oneShot?.close();
        oneShot = null;
        if (!controller.isClosed) await controller.close();
      }
    };
    controller.onCancel = () async {
      await oneShot?.close();
      oneShot = null;
    };

    return controller.stream;
  }

  /// Convenience wrapper over [generateText] returning just the text.
  Future<String> generateTextSimple({
    required String prompt,
    int maxTokens = 100,
  }) async {
    final response = await generateText(
      prompt: prompt,
      config: GenerationConfig(maxTokens: maxTokens),
    );
    return response.text;
  }

  /// Opens Google AICore in the Play Store, for the Android case where AICore
  /// is missing or too old (error -101). False on every other platform.
  Future<bool> openAICorePlayStore() async {
    try {
      return await _host.openAICorePlayStore();
    } catch (_) {
      return false;
    }
  }

  /// Registers Dart tools the model may call during generation.
  ///
  /// Native function calling, not prompt emulation — supported where
  /// `getPlatformInfo().supportsToolCalling` is true (Apple FoundationModels)
  /// and rejected elsewhere rather than silently ignored. Pass an empty list
  /// to stop offering tools.
  ///
  /// Tools bind when a session is created, because Apple's FoundationModels
  /// cannot add them to a live one, so this restarts the shared conversation.
  Future<void> registerTools(List<LocalAiTool> tools) async {
    _tools = List.unmodifiable(tools);
    final previous = _session;
    _session = null;
    await previous?.close();
    // Surfaces an unsupported-tools failure here, at the call the developer
    // can act on, rather than at some later generate.
    if (_tools.isNotEmpty) await _ensureSession();
  }

  /// Whether the OS model is present, downloadable, or being downloaded.
  Future<ModelFeatureStatus> getModelStatus() async {
    switch (await LocalAi.availability(host: _host)) {
      case LocalAiAvailability.available:
        return ModelFeatureStatus.available;
      case LocalAiAvailability.downloadable:
        return ModelFeatureStatus.downloadable;
      case LocalAiAvailability.downloading:
        return ModelFeatureStatus.downloading;
      case LocalAiAvailability.unavailableDeviceUnsupported:
      case LocalAiAvailability.unavailableOsTooOld:
      case LocalAiAvailability.unavailableDisabled:
        return ModelFeatureStatus.unavailable;
      case LocalAiAvailability.unavailableOther:
        return ModelFeatureStatus.unknown;
    }
  }

  /// Downloads the OS model if it is not present yet, reporting progress.
  ///
  /// The stream always terminates with [ModelDownloadStatusType.completed] or
  /// [ModelDownloadStatusType.failed] — a watcher never spins forever waiting
  /// for an event the platform did not send.
  ///
  /// [LocalAi.ensureReady] is the same operation as a future with percentage
  /// progress.
  Stream<ModelDownloadStatus> downloadModel() {
    final controller = StreamController<ModelDownloadStatus>();
    StreamSubscription<LocalAiHostEvent>? progress;

    controller.onListen = () async {
      controller.add(
        const ModelDownloadStatus(type: ModelDownloadStatusType.started),
      );
      progress = _host.events.listen(
        (event) {
          if (event is LocalAiDownloadProgressEvent && !controller.isClosed) {
            controller.add(ModelDownloadStatus(
              type: ModelDownloadStatusType.progress,
              totalBytesDownloaded: event.bytesDownloaded,
            ));
          }
        },
        // Progress is advisory; ensureReady below owns the outcome.
        onError: (Object _) {},
      );
      try {
        await LocalAi.ensureReady(host: _host);
        controller.add(
          const ModelDownloadStatus(type: ModelDownloadStatusType.completed),
        );
      } catch (e) {
        controller.add(ModelDownloadStatus(
          type: ModelDownloadStatusType.failed,
          errorMessage: '$e',
        ));
      } finally {
        await progress?.cancel();
        progress = null;
        if (!controller.isClosed) await controller.close();
      }
    };
    controller.onCancel = () async {
      await progress?.cancel();
      progress = null;
    };

    return controller.stream;
  }

  /// A throwaway session carrying exactly [instructions], for a stateless
  /// call. Registered tools still apply — a one-shot call should be able to
  /// use them. Sampling rides on the generate call rather than being baked
  /// in here, so both session paths honour [GenerationConfig] identically.
  Future<LocalAiSession> _openOneShot(String instructions) async {
    final model = await _ensureModel();
    return model.openSession(
      systemInstruction: instructions,
      tools: _tools.isEmpty ? null : _tools,
    );
  }

  /// Translates a [GenerationConfig] into per-call sampling. Returns null
  /// when there is nothing to override, so the session's own settings stand.
  ///
  /// `maxTokens` maps to `maxOutputTokens` — a cap on what is GENERATED, not
  /// the context window.
  static LocalAiGenerationOverrides? _overridesFor(GenerationConfig? config) {
    if (config == null) return null;
    final overrides = LocalAiGenerationOverrides(
      temperature: config.temperature,
      topP: config.topP,
      topK: config.topK,
      maxOutputTokens: config.maxTokens,
    );
    return overrides.isEmpty ? null : overrides;
  }

  /// Token count for [text], or null when counting itself fails. A failed
  /// count must not fail a generation that already succeeded.
  Future<int?> _countOrNull(LocalAiSession session, String text) async {
    try {
      return await session.sizeInTokens(text);
    } catch (_) {
      return null;
    }
  }
}
