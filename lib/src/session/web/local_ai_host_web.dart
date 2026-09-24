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

  /// The controller behind the generation currently running, or null when the
  /// session is idle.
  ///
  /// Non-null also *reserves* the session's single generation slot. Chrome's
  /// session is one-turn-at-a-time, and before this reservation a second
  /// generation simply overwrote the field: the first controller was orphaned,
  /// so `stopGeneration` could no longer abort the turn that was actually
  /// decoding.
  AbortController? inFlight;

  /// Completes when the turn holding [inFlight] releases it, so work that
  /// must not overlap a generation (token counting) can wait its turn.
  Completer<void>? _turnDone;

  /// Takes the generation slot for [controller].
  void reserve(AbortController controller) {
    inFlight = controller;
    _turnDone = Completer<void>();
  }

  /// Gives the slot back, but only if [controller] still owns it — a turn
  /// that was superseded or whose session was closed must not null out a
  /// newer turn's reservation.
  void release(AbortController controller) {
    if (!identical(inFlight, controller)) return;
    inFlight = null;
    _turnDone?.complete();
    _turnDone = null;
  }

  /// Resolves once no turn is generating on this session.
  Future<void> whenIdle() async {
    while (inFlight != null) {
      await _turnDone!.future;
    }
  }

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
  /// [hasUserActivation] defaults to [hasTransientUserActivation]; tests
  /// replace it because a test runner never has a real user gesture.
  WebLocalAiHost({bool Function()? hasUserActivation})
    : _hasUserActivation = hasUserActivation ?? _readUserActivation;

  static bool _readUserActivation() => hasTransientUserActivation;

  final bool Function() _hasUserActivation;
  final _events = StreamController<LocalAiHostEvent>.broadcast();
  final Map<int, _WebSession> _sessions = {};

  bool _supportImage = false;
  bool _warnedOverrides = false;
  bool _warnedClamp = false;

  @override
  Stream<LocalAiHostEvent> get events => _events.stream;

  _WebSession _require(int sessionId) {
    final session = _sessions[sessionId];
    if (session == null) {
      throw StateError('No built-in AI session with id $sessionId');
    }
    return session;
  }

  /// Rejects a second generation on a session that is already decoding.
  ///
  /// The native hosts answer the same misuse with a `SESSION_BUSY` platform
  /// error (Android's `requireIdle`); here it is a [StateError], the same type
  /// [_require] uses for the other way of calling this host wrong. Failing is
  /// the point: the alternative is two turns racing one Chrome session, with
  /// the earlier one unstoppable and both writing into the same tagged event
  /// stream.
  void _requireIdle(_WebSession state, int sessionId) {
    if (state.inFlight == null) return;
    throw StateError(
      'Session $sessionId is already generating. The Chrome Prompt API runs '
      'one turn at a time per session: await the current response, or call '
      'stopGeneration(), before starting another.',
    );
  }

  void _emitDone(int sessionId) => _events.add(
    LocalAiTokenEvent(sessionId: sessionId, partialResult: '', done: true),
  );

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
        // Experimental and unreliable in Chrome 151. Reported false rather
        // than emulated: createSession throws on a tool list instead of
        // weaving one into the prompt, for the reason the Android arm gives.
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
    // Chrome starts a download only inside a user gesture, and outside one
    // `create()` rejects — which ensureReady would otherwise see only as a
    // download that never finishes. Checked up front so the caller is told
    // *why*; the NotAllowedError mapping below covers browsers without the
    // userActivation API and activation that lapsed before `create()` ran.
    if (!_hasUserActivation()) throw _userActivationRequired();
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
    final PromptSession session;
    try {
      session = await LanguageModel.create(options).toDart;
    } catch (e) {
      if (isNotAllowedError(e)) throw _userActivationRequired();
      rethrow;
    }
    session.destroy();
  }

  static LocalAiUserActivationRequiredException _userActivationRequired() =>
      LocalAiUserActivationRequiredException(
        'Chrome only starts the Gemini Nano download inside a user gesture. '
        'Call LocalAi.ensureReady() from a click or key handler (for example '
        'an "Enable AI" button), not at start-up.',
      );

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
            'reliably route. Gate tools on '
            'LocalAiBackendCapabilities.supportsToolCalling and fall back to '
            'another backend where it is false.',
      );
    }
    // topP and maxOutputTokens have no Prompt API equivalent. They are
    // accepted for cross-platform API parity and deliberately dropped rather
    // than faked — sampling stays whatever temperature/topK select.
    final (clampedTemperature, clampedTopK) = await _clampSampler(
      temperature: temperature,
      topK: topK,
    );
    final options = buildCreateOptions(
      systemInstruction: systemInstruction,
      temperature: clampedTemperature,
      topK: clampedTopK,
      expectedInputTypes: _supportImage ? const ['text', 'image'] : null,
    );
    _sessions[sessionId] = _WebSession(
      await LanguageModel.create(options).toDart,
    );
  }

  /// Brings [temperature] and [topK] under the ceilings this browser
  /// advertises, so a caller carrying cross-platform defaults can still open a
  /// session.
  ///
  /// Chrome rejects a `create()` whose sampling exceeds `maxTemperature` /
  /// `maxTopK` outright — a temperature of 2.0 that is ordinary on Android
  /// otherwise means no web session at all, with a JS error naming neither the
  /// offending knob nor the limit.
  ///
  /// `params()` is best-effort throughout: Chrome 151 dropped the static
  /// ([hasLanguageModelParams] is false there), and a build that keeps it may
  /// still reject or omit a bound. Every one of those skips the clamp and
  /// passes the caller's values through — `create()` is the source of truth
  /// for what is acceptable, this only turns a common rejection into a
  /// working session.
  Future<(double, int)> _clampSampler({
    required double temperature,
    required int topK,
  }) async {
    if (!hasLanguageModelParams) return (temperature, topK);
    try {
      final bounds = readSamplerBounds(await LanguageModel.params().toDart);
      final maxTemperature = bounds.maxTemperature;
      final maxTopK = bounds.maxTopK;
      final clampedTemperature =
          maxTemperature != null && temperature > maxTemperature
          ? maxTemperature
          : temperature;
      final clampedTopK = maxTopK != null && topK > maxTopK ? maxTopK : topK;
      if (clampedTemperature != temperature || clampedTopK != topK) {
        _warnClampedOnce(clampedTemperature, clampedTopK);
      }
      return (clampedTemperature, clampedTopK);
    } catch (_) {
      return (temperature, topK);
    }
  }

  /// Says once that sampling was lowered. Once, not per session: an app that
  /// opens a session per turn would otherwise print this on every message.
  void _warnClampedOnce(double temperature, int topK) {
    if (_warnedClamp) return;
    _warnedClamp = true;
    // ignore: avoid_print
    print(
      '[flutter_local_ai/web] Clamped sampling to the maximum this browser '
      'reports (temperature=$temperature, topK=$topK). Chrome rejects a '
      'session whose temperature or topK is above its advertised limit.',
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
    _requireIdle(state, sessionId);
    _warnOverridesIgnored(overrides);
    final controller = AbortController();
    state.reserve(controller);
    try {
      final options = buildPromptOptions(signal: controller.signal);
      final response = await state.session
          .prompt(state.takeTranscript().toJS, options)
          .toDart;
      return response.toDart;
    } catch (e) {
      // stopGeneration() aborts the whole non-streaming call, so there is no
      // partial text to hand back — the empty string is the turn, the same
      // shape the native hosts settle a cancelled turn with. Surfacing the
      // DOMException instead would throw at an app that only pressed stop.
      if (isAbortError(e)) return '';
      rethrow;
    } finally {
      state.release(controller);
    }
  }

  @override
  Future<void> generateResponseAsync(
    int sessionId, {
    LocalAiGenerationOverrides? overrides,
  }) async {
    final state = _require(sessionId);
    _requireIdle(state, sessionId);
    _warnOverridesIgnored(overrides);
    final controller = AbortController();
    state.reserve(controller);

    final JSObject stream;
    try {
      final options = buildPromptOptions(signal: controller.signal);
      stream = state.session.promptStreaming(
        state.takeTranscript().toJS,
        options,
      );
    } catch (_) {
      // promptStreaming threw before a stream existed. Release the slot here,
      // or the session stays wedged as "already generating" for every later
      // turn, then let the caller see the failure.
      state.release(controller);
      rethrow;
    }

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
        _emitDone(sessionId);
      } catch (e) {
        if (isAbortError(e)) {
          // stopGeneration() aborted this read; the user asked for the turn to
          // end, which is not a failure. Emit the completion the contract
          // requires so the session's stream closes cleanly, exactly as the
          // native hosts do on cancel (Android posts a single done after
          // cancelAndJoin, Apple posts done and the cancelled task stays
          // silent). Without this the app gets a thrown error for pressing
          // stop.
          _emitDone(sessionId);
        } else {
          _events.add(
            LocalAiErrorEvent(sessionId: sessionId, message: e.toString()),
          );
        }
      } finally {
        state.release(controller);
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
    _requireIdle(state, sessionId);
    _warnOverridesIgnored(overrides);
    final controller = AbortController();
    state.reserve(controller);
    try {
      final options = buildPromptOptions(
        responseConstraint: jsonDecode(schemaJson),
        signal: controller.signal,
      );
      final response = await state.session
          .prompt(state.takeTranscript().toJS, options)
          .toDart;
      return response.toDart;
    } catch (e) {
      // Same cancellation posture as generateResponse: an aborted turn has no
      // JSON to return, and the caller asked for it to stop. Callers that
      // parse the result must treat '' as "stopped", not as a document.
      if (isAbortError(e)) return '';
      rethrow;
    } finally {
      state.release(controller);
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
  Future<int> countTokens({
    required int sessionId,
    required String text,
  }) async {
    // Measured on the caller's own session, and not while it is decoding:
    // Chrome runs one operation at a time per session, and a measurement
    // cutting into a `promptStreaming` turn is not what either caller asked
    // for.
    await _require(sessionId).whenIdle();
    // Closed while we waited: report it the way any other call on a closed
    // session is reported.
    final session = _require(sessionId).session;
    // `measureContextUsage` first: it is the current spec name, and calling
    // only the legacy `measureInputUsage` fails on a current Chrome, where
    // that name no longer exists. Each name is probed before it is called so a
    // build that has neither is reported as "no tokenizer here" rather than
    // as an opaque JS `TypeError: … is not a function`.
    if (session.hasMeasureContextUsage) {
      final usage = await session.measureContextUsage(text.toJS).toDart;
      return usage.toDartDouble.round();
    }
    if (session.hasMeasureInputUsage) {
      final usage = await session.measureInputUsage(text.toJS).toDart;
      return usage.toDartDouble.round();
    }
    throw LocalAiTokenizerUnavailable(
      'This browser exposes neither measureContextUsage (current) nor '
      'measureInputUsage (legacy) on a Prompt API session, so there is no '
      'tokenizer to ask.',
    );
  }
}

/// The host for this platform.
LocalAiHost createLocalAiHost() => WebLocalAiHost();
