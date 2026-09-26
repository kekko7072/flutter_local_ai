import Foundation
import ImageIO

#if os(OSX)
  @preconcurrency import FlutterMacOS
#elseif os(iOS)
  @preconcurrency import Flutter
#endif

#if canImport(FoundationModels)
  import FoundationModels
#endif

/// Converts the CUMULATIVE snapshots `LanguageModelSession.streamResponse`
/// emits into per-chunk deltas.
///
/// Apple yields each element as the accumulated string so far, while the
/// event-channel contract is that every `partialResult` is only the new text.
/// Counting `Character`s (grapheme clusters) means a snapshot that merely
/// re-normalizes earlier text yields an empty delta instead of corrupting the
/// offset. One per generation.
struct SnapshotDeltaConverter {
  private var emitted: Int = 0

  mutating func delta(from cumulative: String) -> String {
    let count = cumulative.count
    guard count > emitted else {
      // No growth, or a shrink from re-normalization. Keep the cursor at the
      // high-water mark so a later grow still lines up.
      emitted = max(emitted, count)
      return ""
    }
    let tail = String(cumulative.dropFirst(emitted))
    emitted = count
    return tail
  }
}

/// Session half of the flutter_local_ai host, over Apple FoundationModels.
///
/// Unlike Android's single-turn Prompt API, a `LanguageModelSession` keeps its
/// own transcript across calls, so this buffers only the CURRENT turn and
/// clears it once sent — no history replay.
///
/// Three properties of the event stream that the Dart demux depends on:
///   1. every data event carries a `sessionId`;
///   2. completion is a tagged data event `{partialResult: "", done: true}`,
///      never `FlutterEndOfEventStream` — the channel is shared across
///      sessions, so ending it would end everyone's stream;
///   3. generation failures are the tagged data event `{code: "ERROR", ...}`,
///      never a channel error, which would reach every session and lose the id.
///
/// FoundationModels exists only on iOS/macOS 26+, while this package builds
/// from the iOS 13 / macOS 12 floor in Package.swift. Every use is therefore
/// `#available`-gated and sessions are stored type-erased (`[Int64: Any]`), so
/// this class itself compiles all the way down.
class LocalAiSessionService: NSObject, LocalAiService, FlutterStreamHandler {

  #if canImport(FoundationModels)
    /// Only ever constructed inside an `#available(iOS 26.0, macOS 26.0, *)`
    /// branch, then boxed as `Any`.
    ///
    /// `pendingText` and `task` are mutated without a per-field lock because
    /// pigeon's message handlers dispatch serially on the platform thread on
    /// Darwin, so no two calls for one session overlap. That assumption must
    /// be revisited if pigeon dispatch ever moves off the main queue.
    @available(iOS 26.0, macOS 26.0, *)
    private final class SessionState {
      let session: LanguageModelSession
      let options: GenerationOptions
      /// The knobs `options` was built from. GenerationOptions exposes no
      /// readable sampling mode, so a per-call override that touches one
      /// field could not otherwise preserve the others.
      let temperature: Double?
      let topK: Int?
      let topP: Double?
      let maxOutputTokens: Int?
      var pendingText: String = ""
      var pendingImages: [(CGImage, CGImagePropertyOrientation?)] = []
      var task: Task<Void, Never>?
      /// The turn this session is generating, or nil when idle. Read and
      /// written only on the main queue, like `pendingText`; a finishing task
      /// clears it by hopping back there, and only if it is still its own
      /// turn, so a stopped turn unwinding late cannot free its successor.
      var activeTurn: UInt64?

      init(
        session: LanguageModelSession,
        options: GenerationOptions,
        temperature: Double?,
        topK: Int?,
        topP: Double?,
        maxOutputTokens: Int?
      ) {
        self.session = session
        self.options = options
        self.temperature = temperature
        self.topK = topK
        self.topP = topP
        self.maxOutputTokens = maxOutputTokens
      }
    }
  #endif

  /// Type-erased so this property's type never names FoundationModels.
  private var sessions: [Int64: Any] = [:]
  private let sessionsLock = NSLock()

  private var eventSink: FlutterEventSink?
  private let sinkLock = NSLock()

  /// Dart end of the tool-calling callback. Set by the plugin at registration.
  private let toolRunner: LocalAiToolRunner

  public init(toolRunner: LocalAiToolRunner) {
    self.toolRunner = toolRunner
    super.init()
  }

  // MARK: - FlutterStreamHandler

  func onListen(
    withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    sinkLock.lock()
    eventSink = events
    sinkLock.unlock()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sinkLock.lock()
    eventSink = nil
    sinkLock.unlock()
    return nil
  }

  /// Posts on the main thread — a `FlutterEventSink` must be called from the
  /// platform thread. Never closes the channel: it is shared across sessions.
  private func postEvent(_ payload: [String: Any?]) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      self.sinkLock.lock()
      let sink = self.eventSink
      self.sinkLock.unlock()
      sink?(payload)
    }
  }

  #if canImport(FoundationModels)
    /// Monotonic turn ids; see `SessionState.activeTurn`. Main queue only.
    private var nextTurn: UInt64 = 0

    /// Claims `state` for a new turn, or nil if one is already running.
    /// Rejecting matches Android's `requireIdle` and the web host: letting the
    /// second turn through would overwrite `state.task`, leaving the first
    /// running with nothing that can stop it.
    @available(iOS 26.0, macOS 26.0, *)
    private func beginTurn(_ state: SessionState) -> UInt64? {
      if state.activeTurn != nil { return nil }
      nextTurn += 1
      state.activeTurn = nextTurn
      return nextTurn
    }

    /// Releases `turn`, then runs `then` — both on the main queue, in that
    /// order, so the caller that learns the turn is over can start the next
    /// one without racing the release.
    @available(iOS 26.0, macOS 26.0, *)
    private static func endTurn(
      _ state: SessionState, _ turn: UInt64, then: @escaping () -> Void = {}
    ) {
      DispatchQueue.main.async {
        if state.activeTurn == turn { state.activeTurn = nil }
        then()
      }
    }

    private static func sessionBusyError(_ sessionId: Int64) -> PigeonError {
      PigeonError(
        code: "SESSION_BUSY",
        message: "Session \(sessionId) is already generating.",
        details: nil)
    }
  #endif

  private func postToken(_ sessionId: Int64, _ text: String) {
    postEvent(["partialResult": text, "done": false, "sessionId": sessionId])
  }

  private func postDone(_ sessionId: Int64) {
    postEvent(["partialResult": "", "done": true, "sessionId": sessionId])
  }

  private func postError(_ sessionId: Int64, _ message: String) {
    postEvent(["code": "ERROR", "message": message, "sessionId": sessionId])
  }

  #if canImport(FoundationModels)
    /// Sampling for one call: the session's own options unless `overrides`
    /// replaces a field. FoundationModels takes options per `respond`, so a
    /// caller can vary one turn without disturbing the conversation.
    ///
    /// `.greedy` must not carry a temperature — that pairing throws
    /// on-device — so an override that introduces a temperature also moves
    /// the mode off greedy, and one that only sets a cap keeps whatever the
    /// session chose.
    @available(iOS 26.0, macOS 26.0, *)
    private static func options(
      for state: SessionState, overrides: GenerationOverrides?
    ) -> GenerationOptions {
      guard let overrides = overrides else { return state.options }

      let temperature = overrides.temperature ?? state.temperature
      let positiveTemperature = (temperature ?? 0) > 0 ? temperature : nil
      let maxTokens = overrides.maxOutputTokens.map { Int($0) }
        ?? state.maxOutputTokens
      let topK = overrides.topK.map { Int($0) } ?? state.topK
      let topP = overrides.topP ?? state.topP

      if let topK = topK, topK > 0 {
        return GenerationOptions(
          sampling: .random(top: topK),
          temperature: positiveTemperature,
          maximumResponseTokens: maxTokens)
      }
      if let topP = topP {
        return GenerationOptions(
          sampling: .random(probabilityThreshold: topP),
          temperature: positiveTemperature,
          maximumResponseTokens: maxTokens)
      }
      if let temperature = positiveTemperature {
        return GenerationOptions(
          temperature: temperature, maximumResponseTokens: maxTokens)
      }
      return GenerationOptions(
        sampling: .greedy, maximumResponseTokens: maxTokens)
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func state(for sessionId: Int64) -> SessionState? {
      sessionsLock.lock()
      defer { sessionsLock.unlock() }
      return sessions[sessionId] as? SessionState
    }
  #endif

  // MARK: - Availability

  func checkAvailability(
    completion: @escaping (Result<AvailabilityStatus, Error>) -> Void
  ) {
    #if canImport(FoundationModels)
      guard #available(iOS 26.0, macOS 26.0, *) else {
        completion(.success(.unavailableOsTooOld))
        return
      }
      let status: AvailabilityStatus
      switch SystemLanguageModel.default.availability {
      case .available:
        status = .available
      case .unavailable(.deviceNotEligible):
        status = .unavailableDeviceUnsupported
      case .unavailable(.appleIntelligenceNotEnabled):
        status = .unavailableDisabled
      case .unavailable(.modelNotReady):
        // Apple Intelligence is still fetching or preparing assets. Dart's
        // ensureReady treats this as downloading and polls until available.
        status = .downloading
      case .unavailable:
        status = .unavailableOther
      }
      completion(.success(status))
    #else
      completion(.success(.unavailableOsTooOld))
    #endif
  }

  func availabilityReason(completion: @escaping (Result<String, Error>) -> Void) {
    #if canImport(FoundationModels)
      guard #available(iOS 26.0, macOS 26.0, *) else {
        completion(
          .success(
            "Apple Foundation Models needs iOS 26 or macOS 26. Update the OS, "
              + "or fall back to a downloaded model."))
        return
      }
      switch SystemLanguageModel.default.availability {
      case .available:
        completion(.success("Apple Foundation Models is ready."))
      case .unavailable(.deviceNotEligible):
        completion(
          .success(
            "This device cannot run Apple Intelligence. It needs an iPhone 15 "
              + "Pro or newer, or an Apple silicon Mac."))
      case .unavailable(.appleIntelligenceNotEnabled):
        completion(
          .success(
            "Apple Intelligence is turned off. Enable it in Settings > Apple "
              + "Intelligence & Siri."))
      case .unavailable(.modelNotReady):
        completion(
          .success(
            "Apple Intelligence is still downloading or preparing its model. "
              + "This finishes on its own — try again shortly."))
      case .unavailable(let reason):
        completion(
          .success("Apple Foundation Models is unavailable: \(String(reflecting: reason))"))
      }
    #else
      completion(
        .success(
          "This build has no FoundationModels framework, so the OS model "
            + "cannot be reached."))
    #endif
  }

  func getBackendInfo(
    completion: @escaping (Result<LocalAiBackendInfo, Error>) -> Void
  ) {
    #if canImport(FoundationModels)
      let configured: Bool
      if #available(iOS 26.0, macOS 26.0, *) {
        if case .available = SystemLanguageModel.default.availability {
          configured = true
        } else {
          configured = false
        }
      } else {
        configured = false
      }
      // Tools and dynamic schemas are Foundation Models features, so they
      // need the OS that ships the framework — not merely an SDK that can
      // see it. Reporting them unconditionally made an iOS 25 device
      // advertise both while every call failed OS_TOO_OLD, which defeats
      // the capability gate callers are told to check.
      var toolCalling = false
      var structuredOutput = false
      if #available(iOS 26.0, macOS 26.0, *) {
        toolCalling = true
        structuredOutput = true
      }
      // Exact token counts need BOTH an SDK that declares
      // SystemLanguageModel.tokenCount and an OS that has it — see
      // countTokens for why the compiler version is the usable proxy.
      var vision = false
      #if compiler(>=6.4)
        if #available(iOS 27.0, macOS 27.0, *) { vision = true }
      #endif
      var tokenCount = false
      #if compiler(>=6.3)
        if #available(iOS 26.4, macOS 26.4, *) { tokenCount = true }
      #endif
      completion(
        .success(
          LocalAiBackendInfo(
            backend: .appleFoundationModels,
            platform: platformName(),
            apiName: "Apple Foundation Models",
            supportsToolCalling: toolCalling,
            supportsStructuredOutput: structuredOutput,
            // Image input needs FoundationModels.Attachment, which exists
            // only on OS 27. See addImage.
            supportsVision: vision,
            supportsTokenCount: tokenCount,
            // Apple Intelligence downloads are user-driven in Settings; no
            // app-triggerable download exists.
            supportsModelDownload: false,
            supportsPlayStoreRedirect: false,
            isConfigured: configured)))
    #else
      completion(
        .success(
          LocalAiBackendInfo(
            backend: .unsupported,
            platform: platformName(),
            apiName: "Unavailable",
            supportsToolCalling: false,
            supportsStructuredOutput: false,
            supportsVision: false,
            supportsTokenCount: false,
            supportsModelDownload: false,
            supportsPlayStoreRedirect: false,
            isConfigured: false)))
    #endif
  }

  private func platformName() -> String {
    #if os(OSX)
      return "macos"
    #else
      return "ios"
    #endif
  }

  /// No-op on Darwin: there is no app-triggerable download. The user enables
  /// Apple Intelligence in Settings, and `.modelNotReady` resolves on its own,
  /// which Dart's ensureReady polls for. Returning success immediately sends
  /// it straight to polling.
  func downloadFeature(completion: @escaping (Result<Void, Error>) -> Void) {
    completion(.success(()))
  }

  func openAICorePlayStore(completion: @escaping (Result<Bool, Error>) -> Void) {
    completion(.success(false))
  }

  // MARK: - Model lifecycle

  /// The OS owns the weights, so there is no model handle to allocate.
  /// Sessions are created lazily; `supportImage` is advisory because
  /// multimodality is decided per turn.
  func createModel(
    supportImage: Bool, completion: @escaping (Result<Void, Error>) -> Void
  ) {
    completion(.success(()))
  }

  func closeModel(completion: @escaping (Result<Void, Error>) -> Void) {
    sessionsLock.lock()
    let boxed = Array(sessions.values)
    sessions.removeAll()
    sessionsLock.unlock()
    #if canImport(FoundationModels)
      if #available(iOS 26.0, macOS 26.0, *) {
        for box in boxed { (box as? SessionState)?.task?.cancel() }
      }
    #endif
    completion(.success(()))
  }

  // MARK: - Sessions

  func createSession(
    sessionId: Int64,
    temperature: Double,
    topK: Int64,
    topP: Double?,
    maxOutputTokens: Int64?,
    systemInstruction: String?,
    tools: [ToolSpec]?,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    #if canImport(FoundationModels)
      guard #available(iOS 26.0, macOS 26.0, *) else {
        completion(.failure(Self.osTooOldError()))
        return
      }

      // Sampling modes are mutually exclusive and `.greedy` must not carry a
      // temperature — that pairing throws on-device. Precedence matches the
      // legacy path: topK, then topP, then plain temperature, then greedy.
      let positiveTemperature = temperature > 0 ? temperature : nil
      let maxTokens: Int? = maxOutputTokens.map { Int($0) }
      let options: GenerationOptions
      if topK > 0 {
        options = GenerationOptions(
          sampling: .random(top: Int(topK)),
          temperature: positiveTemperature,
          maximumResponseTokens: maxTokens)
      } else if let topP = topP {
        options = GenerationOptions(
          sampling: .random(probabilityThreshold: topP),
          temperature: positiveTemperature,
          maximumResponseTokens: maxTokens)
      } else if let temp = positiveTemperature {
        options = GenerationOptions(
          temperature: temp, maximumResponseTokens: maxTokens)
      } else {
        options = GenerationOptions(
          sampling: .greedy, maximumResponseTokens: maxTokens)
      }

      let instructions = (systemInstruction?.isEmpty == false) ? systemInstruction : nil
      let session: LanguageModelSession
      do {
        // Tools bind at construction: FoundationModels cannot add them to a
        // live session, which is why the wire takes them here.
        let bound = try (tools ?? []).map {
          try PigeonBackedTool(spec: $0, sessionId: sessionId, runner: toolRunner)
        }
        session = bound.isEmpty
          ? LanguageModelSession(instructions: instructions)
          : LanguageModelSession(tools: bound, instructions: instructions)
      } catch {
        completion(
          .failure(
            PigeonError(
              code: "TOOL_DEFINITION_INVALID",
              message: error.localizedDescription,
              details: nil)))
        return
      }

      let state = SessionState(
        session: session,
        options: options,
        temperature: positiveTemperature,
        topK: topK > 0 ? Int(topK) : nil,
        topP: topP,
        maxOutputTokens: maxTokens)
      sessionsLock.lock()
      // Replace any session already at this id, cancelling its in-flight work.
      (sessions[sessionId] as? SessionState)?.task?.cancel()
      sessions[sessionId] = state
      sessionsLock.unlock()
      completion(.success(()))
    #else
      completion(.failure(Self.osTooOldError()))
    #endif
  }

  func closeSession(
    sessionId: Int64, completion: @escaping (Result<Void, Error>) -> Void
  ) {
    sessionsLock.lock()
    let removed = sessions.removeValue(forKey: sessionId)
    sessionsLock.unlock()
    #if canImport(FoundationModels)
      if #available(iOS 26.0, macOS 26.0, *) {
        (removed as? SessionState)?.task?.cancel()
      }
    #endif
    // Closing mid-stream must terminate that stream; cancelling the task
    // alone is silent to Dart and would leave a consumer hanging.
    if removed != nil { postDone(sessionId) }
    completion(.success(()))
  }

  func addQueryChunk(
    sessionId: Int64, text: String, completion: @escaping (Result<Void, Error>) -> Void
  ) {
    #if canImport(FoundationModels)
      guard #available(iOS 26.0, macOS 26.0, *),
        let state = state(for: sessionId)
      else {
        completion(.failure(Self.sessionMissingError(sessionId)))
        return
      }
      state.pendingText += text
      completion(.success(()))
    #else
      completion(.failure(Self.sessionMissingError(sessionId)))
    #endif
  }

  /// Image attachments require both the OS 27 SDK and an OS 27 runtime.
  func addImage(
    sessionId: Int64,
    imageBytes: FlutterStandardTypedData,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    #if canImport(FoundationModels) && compiler(>=6.4)
      if #available(iOS 27.0, macOS 27.0, *) {
        guard let state = state(for: sessionId) else {
          completion(.failure(Self.sessionMissingError(sessionId)))
          return
        }
        guard let source = CGImageSourceCreateWithData(imageBytes.data as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
          completion(.failure(PigeonError(code: "IMAGE_DECODE_FAILED",
            message: "Could not decode the supplied image bytes.", details: nil)))
          return
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = (properties?[kCGImagePropertyOrientation] as? UInt32)
          .flatMap { CGImagePropertyOrientation(rawValue: $0) }
        state.pendingImages.append((image, orientation))
        completion(.success(()))
        return
      }
    #endif
    completion(.failure(PigeonError(code: "IMAGE_UNSUPPORTED_OS",
      message: "Image input requires an OS 27 SDK build and iOS 27 / macOS 27.",
      details: nil)))
  }

  #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private static func takePrompt(_ state: SessionState) -> Prompt {
      let text = state.pendingText
      let images = state.pendingImages
      state.pendingText = ""
      state.pendingImages = []
      #if compiler(>=6.4)
        if #available(iOS 27.0, macOS 27.0, *) {
          return Prompt {
            for (image, orientation) in images {
              Attachment(image, orientation: orientation)
            }
            text
          }
        }
      #endif
      return Prompt(text)
    }
  #endif

  // MARK: - Generation

  func generateResponse(
    sessionId: Int64,
    overrides: GenerationOverrides?,
    completion: @escaping (Result<String, Error>) -> Void
  ) {
    #if canImport(FoundationModels)
      guard #available(iOS 26.0, macOS 26.0, *),
        let state = state(for: sessionId)
      else {
        completion(.failure(Self.sessionMissingError(sessionId)))
        return
      }
      guard let turn = beginTurn(state) else {
        completion(.failure(Self.sessionBusyError(sessionId)))
        return
      }
      let prompt = Self.takePrompt(state)

      state.task = Task {
        let result: Result<String, Error>
        do {
          let response = try await state.session.respond(
            to: prompt,
            options: Self.options(for: state, overrides: overrides))
          try Task.checkCancellation()
          result = .success(response.content)
        } catch {
          result = .failure(
            PigeonError(
              code: "ERROR",
              message: Self.describeGenerationError(error),
              details: nil))
        }
        Self.endTurn(state, turn) { completion(result) }
      }
    #else
      completion(.failure(Self.sessionMissingError(sessionId)))
    #endif
  }

  func generateResponseAsync(
    sessionId: Int64,
    overrides: GenerationOverrides?,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    #if canImport(FoundationModels)
      guard #available(iOS 26.0, macOS 26.0, *),
        let state = state(for: sessionId)
      else {
        completion(.failure(Self.sessionMissingError(sessionId)))
        return
      }
      guard let turn = beginTurn(state) else {
        completion(.failure(Self.sessionBusyError(sessionId)))
        return
      }
      let prompt = Self.takePrompt(state)

      var converter = SnapshotDeltaConverter()
      state.task = Task { [weak self] in
        // Covers the cancelled exits. The done and error paths release
        // explicitly first, so the release is queued ahead of the event and
        // Dart never sees the turn end while the session still reads as busy.
        defer { Self.endTurn(state, turn) }
        guard let self = self else { return }
        do {
          let stream = state.session.streamResponse(
            to: prompt,
            options: Self.options(for: state, overrides: overrides))
          for try await snapshot in stream {
            if Task.isCancelled { break }
            let delta = converter.delta(from: snapshot.content)
            if !delta.isEmpty {
              self.postToken(sessionId, delta)
            }
          }
          // stopGeneration already posted the single completion on the cancel
          // path; a second one would close an already-closed Dart stream.
          if Task.isCancelled { return }
          Self.endTurn(state, turn)
          self.postDone(sessionId)
        } catch is CancellationError {
          return
        } catch {
          // A cancelled turn can also surface as whatever the framework wraps
          // the cancellation in — a tool call unwinding on `stopGeneration`
          // is the common case. Stopping is not a generation failure, and
          // `stopGeneration` has already posted the one completion.
          if Task.isCancelled { return }
          Self.endTurn(state, turn)
          self.postError(sessionId, Self.describeGenerationError(error))
        }
      }
      completion(.success(()))
    #else
      completion(.failure(Self.sessionMissingError(sessionId)))
    #endif
  }

  func generateStructuredResponse(
    sessionId: Int64,
    schemaJson: String,
    overrides: GenerationOverrides?,
    completion: @escaping (Result<String, Error>) -> Void
  ) {
    #if canImport(FoundationModels)
      guard #available(iOS 26.0, macOS 26.0, *),
        let state = state(for: sessionId)
      else {
        completion(.failure(Self.sessionMissingError(sessionId)))
        return
      }

      let schemaMap: [String: Any]
      do {
        let parsed = try JSONSerialization.jsonObject(with: Data(schemaJson.utf8))
        guard let map = parsed as? [String: Any] else {
          throw PigeonError(
            code: "SCHEMA_INVALID",
            message: "The response schema must be a JSON object.",
            details: nil)
        }
        schemaMap = map
      } catch {
        completion(
          .failure(
            PigeonError(
              code: "SCHEMA_INVALID",
              message: "Could not parse the response schema: \(error.localizedDescription)",
              details: nil)))
        return
      }

      guard let turn = beginTurn(state) else {
        completion(.failure(Self.sessionBusyError(sessionId)))
        return
      }
      let prompt = Self.takePrompt(state)

      state.task = Task {
        let result: Result<String, Error>
        do {
          let schema = try SchemaBuilder.generationSchema(
            from: schemaMap, rootName: "Output")
          let response = try await state.session.respond(
            to: prompt,
            schema: schema,
            options: Self.options(for: state, overrides: overrides))
          try Task.checkCancellation()
          result = .success(response.content.jsonString)
        } catch {
          result = .failure(
            PigeonError(
              code: "ERROR",
              message: Self.describeGenerationError(error),
              details: nil))
        }
        Self.endTurn(state, turn) { completion(result) }
      }
    #else
      completion(.failure(Self.sessionMissingError(sessionId)))
    #endif
  }

  func stopGeneration(
    sessionId: Int64, completion: @escaping (Result<Void, Error>) -> Void
  ) {
    #if canImport(FoundationModels)
      if #available(iOS 26.0, macOS 26.0, *), let state = state(for: sessionId) {
        state.task?.cancel()
        // Idle as soon as stop is asked for, as on Android, where a cancelled
        // job stops reporting active at once: the done posted below tells Dart
        // the turn is over, so the next one must be accepted.
        state.activeTurn = nil
      }
    #endif
    // The single completion signal on the stop path, so the Dart stream
    // closes cleanly rather than waiting for output that will not come.
    postDone(sessionId)
    completion(.success(()))
  }

  func countTokens(text: String, completion: @escaping (Result<Int64, Error>) -> Void) {
    #if canImport(FoundationModels)
      // `SystemLanguageModel.tokenCount(for:)` is @available(iOS 26.4,
      // macOS 26.4), stricter than the framework's own 26.0 floor.
      //
      // `#available` alone is not enough: it is a RUNTIME check that permits
      // calling a newer API, but the declaration must still exist in the SDK
      // being compiled against. It does not exist in the 26.0-26.3 SDKs, so
      // Xcode 26.1 would fail the build outright — for every consumer of this
      // package, whether or not they ever count tokens.
      //
      // Swift has no SDK-version conditional. The toolchain ships with the
      // SDK, so the compiler version is the usable proxy. The gate is biased
      // toward the fallback on purpose: an SDK that has the API but ships an
      // older compiler loses exact counts, which is a worse number rather
      // than a broken build.
      #if compiler(>=6.3)
        guard #available(iOS 26.4, macOS 26.4, *) else {
          completion(
            .failure(Self.tokenizerUnavailable("it requires iOS or macOS 26.4 or newer")))
          return
        }
        Task {
          do {
            let count = try await SystemLanguageModel.default.tokenCount(for: text)
            completion(.success(Int64(count)))
          } catch {
            completion(
              .failure(
                PigeonError(
                  code: "TOKENIZER_ERROR",
                  message: error.localizedDescription,
                  details: nil)))
          }
        }
      #else
        completion(
          .failure(
            Self.tokenizerUnavailable(
              "this package was built against an SDK without "
                + "SystemLanguageModel.tokenCount (Xcode 26.4 or newer provides it)")))
      #endif
    #else
      completion(
        .failure(Self.tokenizerUnavailable("FoundationModels is not available in this build")))
    #endif
  }

  // MARK: - Errors

  // `.failure` must carry a Swift.Error. `PigeonError` does; `FlutterError`
  // conforms only on iOS, not macOS, so it cannot be used in this shared
  // source set — it stays confined to the two FlutterStreamHandler returns
  // above, where the protocol requires it.
  private static func sessionMissingError(_ sessionId: Int64) -> PigeonError {
    PigeonError(
      code: "SESSION_NOT_FOUND",
      message: "No session with id \(sessionId). It was closed, or never created.",
      details: nil)
  }

  private static func osTooOldError() -> PigeonError {
    PigeonError(
      code: "OS_TOO_OLD",
      message: "Apple Foundation Models requires iOS 26 or macOS 26 or newer.",
      details: nil)
  }

  /// Signals that Dart should fall back to its character estimate. Two causes,
  /// one signal: the SDK we were built against lacks `tokenCount`, or the OS
  /// we are running on is older than 26.4.
  private static func tokenizerUnavailable(_ why: String) -> PigeonError {
    PigeonError(
      code: "TOKENIZER_UNAVAILABLE",
      message: "Token counting is unavailable: \(why)",
      details: nil)
  }

  private static func describeGenerationError(_ error: Error) -> String {
    #if canImport(FoundationModels)
      if #available(iOS 26.0, macOS 26.0, *) {
        if let generationError = error as? LanguageModelSession.GenerationError {
          switch generationError {
          case .exceededContextWindowSize:
            return "The conversation exceeded the model's context window. "
              + "Start a new session or shorten the input."
          case .assetsUnavailable:
            return "The on-device model assets are unavailable. Check that "
              + "Apple Intelligence is enabled and has finished downloading."
          case .guardrailViolation:
            return "The request was blocked by the model's safety guardrails."
          case .unsupportedGuide:
            return "The requested generation guide is not supported."
          case .unsupportedLanguageOrLocale:
            return "The requested language or locale is not supported by the model."
          case .decodingFailure:
            return "The model's response could not be decoded."
          case .rateLimited:
            return "The model is rate limited. Retry shortly."
          case .concurrentRequests:
            return "Another request is already running on this session. Wait "
              + "for it to finish before starting another."
          case .refusal:
            return "The model refused to respond to this request."
          @unknown default:
            return generationError.errorDescription ?? "Generation failed."
          }
        }
      }
    #endif
    return error.localizedDescription
  }
}

#if canImport(FoundationModels)

  /// The one continuation a suspended tool call is waiting on, resumed exactly
  /// once — by Dart answering, or by the turn being cancelled, whichever comes
  /// first. The loser is dropped rather than resuming a spent continuation,
  /// which would trap.
  private final class PendingToolCall: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String?, Error>?
    private var isCancelled = false

    func attach(_ continuation: CheckedContinuation<String?, Error>) {
      lock.lock()
      // Cancellation can land before the continuation exists: the handler runs
      // immediately when the task is already cancelled.
      if isCancelled {
        lock.unlock()
        continuation.resume(throwing: CancellationError())
        return
      }
      self.continuation = continuation
      lock.unlock()
    }

    func finish(_ result: Result<String?, Error>) {
      lock.lock()
      let continuation = self.continuation
      self.continuation = nil
      lock.unlock()
      continuation?.resume(with: result)
    }

    func cancel() {
      lock.lock()
      isCancelled = true
      let continuation = self.continuation
      self.continuation = nil
      lock.unlock()
      continuation?.resume(throwing: CancellationError())
    }
  }

  @available(iOS 26.0, macOS 26.0, *)
  private struct PigeonToolArguments: ConvertibleFromGeneratedContent {
    let content: GeneratedContent

    init(_ content: GeneratedContent) throws {
      self.content = content
    }
  }

  /// A FoundationModels tool whose body runs in Dart.
  ///
  /// The model calls this, the host suspends, Dart executes the registered
  /// handler, and the JSON result is fed back as `GeneratedContent`. Bound to
  /// one session id so a tool call can never reach another session's handler.
  @available(iOS 26.0, macOS 26.0, *)
  // Immutable tool state; the non-Sendable messenger is accessed exclusively
  // on DispatchQueue.main in call(arguments:).
  private struct PigeonBackedTool: Tool, @unchecked Sendable {
    typealias Arguments = PigeonToolArguments
    typealias Output = GeneratedContent

    let name: String
    let description: String
    let parameters: GenerationSchema
    let sessionId: Int64
    let runner: LocalAiToolRunner

    init(spec: ToolSpec, sessionId: Int64, runner: LocalAiToolRunner) throws {
      self.name = spec.name
      self.description = spec.description
      self.sessionId = sessionId
      self.runner = runner

      // The declaration arrives whole, as JSON Schema, and goes through the
      // same builder structured output uses — so a nested object, a list or a
      // string enum constrains the model here exactly as it does there,
      // instead of being flattened to a scalar on the way down.
      var json = try PigeonBackedTool.parametersObject(from: spec.parametersSchemaJson)
      if json["description"] == nil, !spec.description.isEmpty {
        json["description"] = spec.description
      }
      self.parameters = try SchemaBuilder.generationSchema(from: json, rootName: spec.name)
    }

    private static func parametersObject(from schemaJson: String) throws -> [String: Any] {
      guard let data = schemaJson.data(using: .utf8),
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
      else {
        throw SchemaBuilder.SchemaError.unsupported(
          "A tool's parameters must be a JSON Schema object.")
      }
      return object
    }

    func call(arguments: PigeonToolArguments) async throws -> GeneratedContent {
      let argumentsJson = arguments.content.jsonString
      let name = self.name
      let sessionId = self.sessionId

      // No timeout: a tool body may legitimately sit for as long as it takes a
      // person to approve the action. Cancellation is the way out, and it has
      // to be wired explicitly — a task suspended on a continuation does not
      // unwind on its own, so without this handler `stopGeneration` would wait
      // for a tool call that may never be answered.
      let pending = PendingToolCall()
      let resultJson: String? = try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
          pending.attach(continuation)
          // The pigeon channel must be driven from the platform thread.
          DispatchQueue.main.async {
            self.runner.onToolCall(
              sessionId: sessionId, toolName: name, argumentsJson: argumentsJson
            ) { result in
              switch result {
              case .success(let json):
                pending.finish(.success(json))
              case .failure(let error):
                pending.finish(.failure(error))
              }
            }
          }
        }
      } onCancel: {
        pending.cancel()
      }

      // A tool that yields nothing still has to answer the model with
      // something well-formed, or generation stalls on an empty turn.
      guard let json = resultJson else {
        return try GeneratedContent(json: "null")
      }
      return try GeneratedContent(json: json)
    }
  }

#endif
