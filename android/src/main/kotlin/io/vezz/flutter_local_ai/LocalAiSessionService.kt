package io.vezz.flutter_local_ai

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.util.Log
import com.google.firebase.Firebase
import com.google.firebase.FirebaseApp
import com.google.firebase.ai.type.PublicPreviewAPI
import com.google.firebase.ai.InferenceMode
import com.google.firebase.ai.OnDeviceConfig
import com.google.firebase.ai.ai
import com.google.firebase.ai.type.GenerativeBackend
import com.google.firebase.ai.type.content
import com.google.firebase.ai.type.generationConfig
import com.google.mlkit.genai.common.DownloadStatus
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.common.GenAiException
import com.google.mlkit.genai.prompt.Generation
import com.google.mlkit.genai.prompt.Content
import com.google.mlkit.genai.prompt.SystemInstruction
import com.google.mlkit.genai.prompt.GenerativeModel
import com.google.mlkit.genai.prompt.ImagePart
import com.google.mlkit.genai.prompt.TextPart
import com.google.mlkit.genai.prompt.generateContentRequest
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Session half of the flutter_local_ai host, over ML Kit GenAI (Gemini Nano
 * via AICore).
 *
 * The Prompt API is single-turn — it keeps no history of its own — so each
 * session holds a transcript that is replayed on every generate, with the
 * model's own turn appended back so the next turn sees it. Tokens and
 * download progress leave through one shared [EventChannel], tagged with the
 * session id, and generation errors travel as tagged DATA events rather than
 * channel errors: a channel error would reach every session and lose the id.
 */
internal class LocalAiSessionService(
  private val context: Context
) : LocalAiService, EventChannel.StreamHandler {

  private companion object {
    const val TAG = "FlutterLocalAi"
    const val AICORE_PACKAGE = "com.google.android.aicore"

    /** ML Kit rejects maxOutputTokens outside this range. */
    const val MAX_OUTPUT_TOKENS_MIN = 1
    const val MAX_OUTPUT_TOKENS_MAX = 4096
  }

  private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
  private var eventSink: EventChannel.EventSink? = null

  @Volatile
  private var generativeModel: GenerativeModel? = null
  private val modelLock = Any()
  private val generationMutex = Mutex()

  /** `Generation.getClient()` is cheap and idempotent; one instance serves
   *  status checks, download and every session's generation. */
  private fun client(): GenerativeModel = synchronized(modelLock) {
    generativeModel ?: Generation.getClient().also { generativeModel = it }
  }

  private class SessionState(
    val temperature: Float,
    val topK: Int,
    val maxOutputTokens: Int?,
    val systemInstruction: String?,
    val executionPolicy: LocalAiExecutionPolicy,
    val androidCloudModelName: String?,
  ) {
    val transcript = StringBuilder()
    val images = mutableListOf<Bitmap>()

    /** Where the pending turn begins — the transcript length as of the last
     *  committed turn. A generate that fails or is cancelled with nothing to
     *  show rewinds here, so the abandoned prompt is not left at the tail for
     *  the next turn to concatenate onto. */
    @Volatile
    var turnStart: Int = 0

    @Volatile
    var job: Job? = null


  }

  private val sessions = mutableMapOf<Long, SessionState>()
  private val sessionsLock = Any()

  private fun requireSession(sessionId: Long): SessionState =
    synchronized(sessionsLock) {
      sessions[sessionId] ?: throw FlutterError(
        "SESSION_NOT_FOUND",
        "No session with id $sessionId. It was closed, or never created.",
        null
      )
    }

  fun cleanup() {
    scope.cancel()
    synchronized(sessionsLock) {
      sessions.values.forEach { it.job?.cancel() }
      sessions.clear()
    }
    synchronized(modelLock) {
      runCatching { generativeModel?.close() }
      generativeModel = null
    }
  }

  // === EventChannel.StreamHandler ===

  override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
    eventSink = events
  }

  override fun onCancel(arguments: Any?) {
    eventSink = null
  }

  /** Posts on the main thread — EventSink is not thread-safe. Never closes
   *  the sink: it is shared across every session. */
  private fun postEvent(payload: Map<String, Any?>) {
    scope.launch(Dispatchers.Main) { eventSink?.success(payload) }
  }

  private fun postToken(sessionId: Long, text: String) = postEvent(
    mapOf("partialResult" to text, "done" to false, "sessionId" to sessionId)
  )

  private fun postDone(sessionId: Long) = postEvent(
    mapOf("partialResult" to "", "done" to true, "sessionId" to sessionId)
  )

  private fun postError(sessionId: Long, e: Exception) = postEvent(
    mapOf(
      "code" to "ERROR",
      "message" to (e.message ?: "Generation failed"),
      "sessionId" to sessionId,
    ) + genAiDetails(e)
  )

  /** ML Kit's own code for a [GenAiException], and how long it asks the app
   *  to wait before retrying (zero when it doesn't say), so the app can tell
   *  `BUSY` (retry with backoff) from a long-duration quota or blocked
   *  background use. Empty for any other exception. */
  private fun genAiDetails(e: Exception): Map<String, Any> =
    if (e is GenAiException) {
      mapOf("errorCode" to e.errorCode, "retryDelayMs" to e.retryDelay.toMillis())
    } else if (e.javaClass.name.startsWith("com.google.firebase.ai.")) {
      mapOf("errorCode" to e.javaClass.simpleName)
    } else emptyMap()

  /** A generate failure as Dart sees it: a [GenAiException] becomes
   *  `GENERATION_ERROR` (the code the Windows host already uses) carrying
   *  [genAiDetails]. Anything else passes through unchanged. */
  private fun generationFailure(e: Exception): Throwable =
    if (e is GenAiException) {
      FlutterError("GENERATION_ERROR", e.message ?: "Generation failed", genAiDetails(e))
    } else if (e.javaClass.name.startsWith("com.google.firebase.ai.")) {
      FlutterError(
        "GENERATION_ERROR",
        e.message ?: "Firebase AI Logic generation failed",
        mapOf("errorCode" to e.javaClass.simpleName),
      )
    } else e

  // === Availability ===

  private suspend fun featureStatus(): Int = client().checkStatus()

  override fun checkAvailability(callback: (Result<AvailabilityStatus>) -> Unit) {
    scope.launch {
      try {
        val status = when (featureStatus()) {
          FeatureStatus.AVAILABLE -> AvailabilityStatus.AVAILABLE
          FeatureStatus.DOWNLOADABLE -> AvailabilityStatus.DOWNLOADABLE
          FeatureStatus.DOWNLOADING -> AvailabilityStatus.DOWNLOADING
          FeatureStatus.UNAVAILABLE ->
            AvailabilityStatus.UNAVAILABLE_DEVICE_UNSUPPORTED
          else -> AvailabilityStatus.UNAVAILABLE_OTHER
        }
        callback(Result.success(status))
      } catch (e: Exception) {
        // The probe's contract is to resolve, never throw — an unclassified
        // status lets Dart degrade instead of the caller crashing.
        Log.w(TAG, "checkStatus failed: ${e.message}")
        callback(Result.success(AvailabilityStatus.UNAVAILABLE_OTHER))
      }
    }
  }

  override fun availabilityReason(callback: (Result<String>) -> Unit) {
    scope.launch {
      try {
        val reason = when (featureStatus()) {
          FeatureStatus.AVAILABLE -> "Gemini Nano is ready."
          FeatureStatus.DOWNLOADABLE ->
            "Gemini Nano is not on this device yet. Call LocalAi.ensureReady() " +
              "to download it."
          FeatureStatus.DOWNLOADING ->
            "Gemini Nano is downloading. Call LocalAi.ensureReady() and wait."
          FeatureStatus.UNAVAILABLE ->
            "AICore reports Gemini Nano as unavailable: either this device " +
              "does not support the Prompt API, or AICore has not finished " +
              "setting it up. Supported devices are listed at " +
              "https://developers.google.com/ml-kit/genai#prompt-device " +
              "(no emulators, no unlocked bootloaders). On a listed device, " +
              "stay online and check again later; setup can take hours."
          else -> "AICore reported an unrecognised feature status."
        }
        callback(Result.success(reason))
      } catch (e: GenAiException) {
        callback(
          Result.success(
            if (e.errorCode == GenAiException.ErrorCode.AICORE_INCOMPATIBLE) {
              "Google AICore is missing or too old (error -101). Update it " +
                "from the Play Store — LocalAi.openAICorePlayStore() opens it."
            } else {
              "AICore could not be reached: ${e.message}"
            }
          )
        )
      } catch (e: Exception) {
        callback(Result.success("AICore could not be reached: ${e.message}"))
      }
    }
  }

  override fun getBackendInfo(callback: (Result<LocalAiBackendInfo>) -> Unit) {
    callback(
      Result.success(
        LocalAiBackendInfo(
          backend = LocalAiBackend.ANDROID_ML_KIT_GEN_AI,
          platform = "android",
          apiName = "Google ML Kit GenAI (AICore)",
          // Current ML Kit exposes tool declarations, but this plugin has no
          // reliable typed Dart callback/result-reinjection loop yet. Do not
          // advertise partial support that behaves differently from Apple.
          supportsToolCalling = false,
          supportsStructuredOutput = false,
          supportsVision = true,
          supportsTokenCount = true,
          supportsModelDownload = true,
          supportsPlayStoreRedirect = true,
          supportsPrivateCloudCompute = false,
          privateCloudAvailability =
            LocalAiPrivateCloudAvailability.UNAVAILABLE_OTHER,
          isConfigured = true,
        )
      )
    )
  }

  override fun downloadFeature(callback: (Result<Unit>) -> Unit) {
    scope.launch {
      // The pigeon reply must fire exactly once. Some download flows finish
      // with no terminal status at all (the feature was already present), so
      // without the post-collect fallback the Dart future would hang until
      // ensureReady's timeout.
      val replied = AtomicBoolean(false)
      fun reply(result: Result<Unit>) {
        if (replied.compareAndSet(false, true)) callback(result)
      }
      // DownloadStarted carries the total; DownloadProgress carries only the
      // running counter. Hold the total from the opening status so Dart can
      // report a real percentage. Stays 0 if the flow somehow starts at
      // DownloadProgress, and Dart then reports a null percent as before.
      var bytesTotal = 0L
      try {
        client().download().collect { status ->
          when (status) {
            is DownloadStatus.DownloadStarted -> {
              bytesTotal = status.bytesToDownload
              Log.d(TAG, "Gemini Nano download started ($bytesTotal bytes)")
            }

            is DownloadStatus.DownloadProgress ->
              postEvent(
                mapOf(
                  "code" to "DOWNLOAD_PROGRESS",
                  "bytesDownloaded" to status.totalBytesDownloaded,
                  "bytesTotal" to bytesTotal,
                )
              )

            is DownloadStatus.DownloadCompleted -> reply(Result.success(Unit))

            is DownloadStatus.DownloadFailed -> {
              Log.e(TAG, "Gemini Nano download failed: ${status.e.message}")
              reply(Result.failure(status.e))
            }
          }
        }
        reply(Result.success(Unit))
      } catch (e: Exception) {
        reply(Result.failure(e))
      }
    }
  }

  override fun openAICorePlayStore(callback: (Result<Boolean>) -> Unit) {
    try {
      val market = Intent(Intent.ACTION_VIEW).apply {
        data = Uri.parse("market://details?id=$AICORE_PACKAGE")
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      }
      if (market.resolveActivity(context.packageManager) != null) {
        context.startActivity(market)
      } else {
        context.startActivity(playStoreWebIntent())
      }
      callback(Result.success(true))
    } catch (e: ActivityNotFoundException) {
      // No Play Store app; the web listing still works on most devices.
      try {
        context.startActivity(playStoreWebIntent())
        callback(Result.success(true))
      } catch (inner: Exception) {
        callback(Result.success(false))
      }
    } catch (e: Exception) {
      callback(Result.success(false))
    }
  }

  private fun playStoreWebIntent() = Intent(Intent.ACTION_VIEW).apply {
    data = Uri.parse("https://play.google.com/store/apps/details?id=$AICORE_PACKAGE")
    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
  }

  private fun androidSelection(
    policy: LocalAiExecutionPolicy,
    cloudModelName: String?,
  ): LocalAiModelSelection {
    if (policy == LocalAiExecutionPolicy.ON_DEVICE_ONLY) {
      return LocalAiModelSelection(
        executionLocation = LocalAiExecutionLocation.ON_DEVICE,
        provider = "Google ML Kit GenAI (Gemini Nano via AICore)",
        fallbackUsed = false,
      )
    }
    if (cloudModelName.isNullOrBlank()) {
      throw FlutterError(
        "ANDROID_CLOUD_MODEL_REQUIRED",
        "Android cloud-capable policies require " +
          "LocalAiAndroidConfiguration(cloudModelName: ...).",
        null,
      )
    }
    try {
      FirebaseApp.getInstance()
    } catch (e: Exception) {
      throw FlutterError(
        "FIREBASE_AI_NOT_CONFIGURED",
        "Firebase is not initialized. Add google-services.json, initialize " +
          "Firebase, enable Firebase AI Logic, and configure App Check.",
        e.message,
      )
    }
    return when (policy) {
      LocalAiExecutionPolicy.CLOUD_ONLY -> LocalAiModelSelection(
        executionLocation = LocalAiExecutionLocation.FIREBASE_AI_LOGIC_CLOUD,
        provider = "Firebase AI Logic ($cloudModelName)",
        fallbackUsed = false,
      )
      LocalAiExecutionPolicy.PREFER_ON_DEVICE,
      LocalAiExecutionPolicy.PREFER_CLOUD -> LocalAiModelSelection(
        executionLocation = LocalAiExecutionLocation.UNDETERMINED,
        provider = "Firebase AI Logic hybrid ($cloudModelName)",
        fallbackUsed = false,
      )
      LocalAiExecutionPolicy.ON_DEVICE_ONLY -> error("handled above")
    }
  }

  // === Model lifecycle ===

  override fun createModel(
    supportImage: Boolean,
    executionPolicy: LocalAiExecutionPolicy,
    androidCloudModelName: String?,
    callback: (Result<LocalAiModelSelection>) -> Unit
  ) {
    val selection = try { androidSelection(executionPolicy, androidCloudModelName) }
      catch (e: Exception) { callback(Result.failure(e)); return }
    scope.launch {
      try {
        // Do not touch AICore for cloudOnly: a device that cannot run Nano
        // must still be able to use Firebase cloud inference. The hybrid SDK
        // owns local-provider initialization for preference policies.
        if (executionPolicy == LocalAiExecutionPolicy.ON_DEVICE_ONLY) client()
        callback(Result.success(selection))
      } catch (e: Exception) {
        callback(Result.failure(e))
      }
    }
  }

  override fun closeModel(callback: (Result<Unit>) -> Unit) {
    scope.launch {
      try {
        synchronized(sessionsLock) {
          sessions.values.forEach { it.job?.cancel() }
          sessions.clear()
        }
        synchronized(modelLock) {
          runCatching { generativeModel?.close() }
          generativeModel = null
        }
        callback(Result.success(Unit))
      } catch (e: Exception) {
        callback(Result.failure(e))
      }
    }
  }

  // === Sessions ===

  override fun createSession(
    sessionId: Long,
    executionPolicy: LocalAiExecutionPolicy,
    androidCloudModelName: String?,
    temperature: Double,
    topK: Long,
    topP: Double?,
    maxOutputTokens: Long?,
    systemInstruction: String?,
    tools: List<ToolSpec>?,
    callback: (Result<LocalAiModelSelection>) -> Unit
  ) {
    val selection = try { androidSelection(executionPolicy, androidCloudModelName) }
      catch (e: Exception) { callback(Result.failure(e)); return }
    if (!tools.isNullOrEmpty()) {
      // Failing loudly beats advertising declarations without the reliable
      // Dart callback/result-reinjection/cancellation loop Apple provides.
      callback(
        Result.failure(
          FlutterError(
            "TOOL_CALLING_UNSUPPORTED",
            "Android tool calling is not bridged reliably yet. Check " +
              "LocalAi.capabilities().supportsToolCalling before passing tools.",
            null
          )
        )
      )
      return
    }
    try {
      // topP has no Prompt API builder parameter. It is accepted for
      // cross-platform parity and deliberately not applied, rather than
      // silently mapped onto topK.
      val state = SessionState(
        temperature = temperature.toFloat(),
        topK = topK.toInt(),
        maxOutputTokens = maxOutputTokens
          ?.toInt()
          ?.coerceIn(MAX_OUTPUT_TOKENS_MIN, MAX_OUTPUT_TOKENS_MAX),
        systemInstruction = systemInstruction,
        executionPolicy = executionPolicy,
        androidCloudModelName = androidCloudModelName,
      )
      synchronized(sessionsLock) {
        sessions[sessionId]?.job?.cancel()
        sessions[sessionId] = state
      }
      callback(Result.success(selection))
    } catch (e: Exception) {
      callback(Result.failure(e))
    }
  }

  override fun closeSession(sessionId: Long, callback: (Result<Unit>) -> Unit) {
    try {
      val removed = synchronized(sessionsLock) { sessions.remove(sessionId) }
      removed?.job?.cancel()
      // Closing mid-stream must terminate that stream: the job cancel alone
      // is silent to Dart, which would leave a consumer hanging.
      if (removed != null) postDone(sessionId)
      callback(Result.success(Unit))
    } catch (e: Exception) {
      callback(Result.failure(e))
    }
  }

  override fun addQueryChunk(
    sessionId: Long,
    text: String,
    callback: (Result<Unit>) -> Unit
  ) {
    try {
      requireSession(sessionId).also { requireIdle(it) }.transcript.append(text)
      callback(Result.success(Unit))
    } catch (e: Exception) {
      callback(Result.failure(e))
    }
  }

  override fun addImage(
    sessionId: Long,
    imageBytes: ByteArray,
    callback: (Result<Unit>) -> Unit
  ) {
    try {
      val state = requireSession(sessionId).also { requireIdle(it) }
      val bitmap = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
        ?: throw FlutterError(
          "IMAGE_DECODE_FAILED",
          "Could not decode the supplied image bytes.",
          null
        )
      state.images.add(bitmap)
      callback(Result.success(Unit))
    } catch (e: Exception) {
      callback(Result.failure(e))
    }
  }

  private fun requireIdle(state: SessionState) {
    if (state.job?.isActive == true) {
      throw FlutterError("SESSION_BUSY", "This session is already generating.", null)
    }
  }

  // === Generation ===

  /**
   * Per-call sampling, falling back to whatever the session was created with.
   * ML Kit takes options per request, so a caller can vary one turn without
   * disturbing the conversation.
   */
  private class EffectiveOptions(
    state: SessionState,
    overrides: GenerationOverrides?
  ) {
    val temperature: Float =
      overrides?.temperature?.toFloat() ?: state.temperature
    val topK: Int = overrides?.topK?.toInt() ?: state.topK
    val maxOutputTokens: Int? =
      overrides?.maxOutputTokens
        ?.toInt()
        ?.coerceIn(MAX_OUTPUT_TOKENS_MIN, MAX_OUTPUT_TOKENS_MAX)
        ?: state.maxOutputTokens
    // topP has no Prompt API builder parameter, on the session or the
    // request. Accepted for cross-platform parity and deliberately dropped
    // rather than mapped onto topK, which means something else.
  }

  private suspend fun buildRequest(state: SessionState, overrides: GenerationOverrides?) =
    EffectiveOptions(state, overrides).let { options ->
      val instruction = state.systemInstruction
      val nativeSystem = !instruction.isNullOrEmpty() && client().isSystemPromptAvailable()
      val prompt = if (!nativeSystem && !instruction.isNullOrEmpty()) {
        instruction + "\n\n" + state.transcript.toString()
      } else state.transcript.toString()
      val content = Content.Builder().apply {
        state.images.forEach { image(it) }
        text(prompt)
      }.build()
      generateContentRequest(content) {
        if (nativeSystem) systemInstruction = SystemInstruction(instruction)
        temperature = options.temperature
        topK = options.topK
        options.maxOutputTokens?.let { maxOutputTokens = it }
      }
    }

  /** Records the model's turn and clears the consumed image, so the next
   *  turn starts from a clean multimodal slate. */
  private fun commitTurn(state: SessionState, text: String) {
    state.transcript.append("\n\n").append(text).append("\n\n")
    state.images.clear()
    state.turnStart = state.transcript.length
  }

  /** Undoes the pending turn's prompt after a generate that produced nothing.
   *  Images are deliberately kept: the caller still holds the turn and a
   *  retry re-adds only the text. */
  private fun rewindTurn(state: SessionState) {
    if (state.transcript.length > state.turnStart) {
      state.transcript.setLength(state.turnStart)
    }
  }

  @OptIn(PublicPreviewAPI::class)
  private suspend fun generateHybrid(
    state: SessionState,
    overrides: GenerationOverrides?,
  ): LocalAiGenerationResult {
    val options = EffectiveOptions(state, overrides)
    val mode = when (state.executionPolicy) {
      LocalAiExecutionPolicy.CLOUD_ONLY -> InferenceMode.ONLY_IN_CLOUD
      LocalAiExecutionPolicy.PREFER_ON_DEVICE -> InferenceMode.PREFER_ON_DEVICE
      LocalAiExecutionPolicy.PREFER_CLOUD -> InferenceMode.PREFER_IN_CLOUD
      LocalAiExecutionPolicy.ON_DEVICE_ONLY -> error("Use the ML Kit path")
    }
    val cloudModel = state.androidCloudModelName
      ?: throw FlutterError("ANDROID_CLOUD_MODEL_REQUIRED", "Missing cloud model.", null)
    val generationConfig = generationConfig {
      temperature = options.temperature
      topK = options.topK
      options.maxOutputTokens?.let { maxOutputTokens = it }
    }
    val onDeviceConfig = OnDeviceConfig(
      mode = mode,
      maxOutputTokens = options.maxOutputTokens,
      temperature = options.temperature,
      topK = options.topK,
    )
    val model = Firebase.ai(backend = GenerativeBackend.googleAI()).generativeModel(
      modelName = cloudModel,
      generationConfig = generationConfig,
      onDeviceConfig = onDeviceConfig,
    )
    val instruction = state.systemInstruction
    val prompt = if (instruction.isNullOrEmpty()) state.transcript.toString()
      else instruction + "\n\n" + state.transcript.toString()
    val input = content {
      state.images.forEach { image(it) }
      text(prompt)
    }
    val result = model.generateContent(input)
    val text = result.text.orEmpty()
    val usedCloud = result.inferenceSource.toString() == "IN_CLOUD"
    commitTurn(state, text)
    return LocalAiGenerationResult(
      text = text,
      executionLocation = if (usedCloud)
        LocalAiExecutionLocation.FIREBASE_AI_LOGIC_CLOUD
      else LocalAiExecutionLocation.ON_DEVICE,
      provider = if (usedCloud) "Firebase AI Logic ($cloudModel)"
      else "Gemini Nano via Firebase AI Logic and AICore",
    )
  }

  override fun generateResponse(
    sessionId: Long,
    overrides: GenerationOverrides?,
    callback: (Result<LocalAiGenerationResult>) -> Unit
  ) {
    val state = try {
      requireSession(sessionId).also { requireIdle(it) }
    } catch (e: Exception) {
      callback(Result.failure(e))
      return
    }
    state.job = scope.launch(start = CoroutineStart.LAZY) {
      try {
        val result = generationMutex.withLock {
          try {
            if (state.executionPolicy == LocalAiExecutionPolicy.ON_DEVICE_ONLY) {
              val response = client().generateContent(buildRequest(state, overrides))
              val text = response.candidates.firstOrNull()?.text.orEmpty()
              commitTurn(state, text)
              LocalAiGenerationResult(
                text = text,
                executionLocation = LocalAiExecutionLocation.ON_DEVICE,
                provider = "Google ML Kit GenAI (Gemini Nano via AICore)",
              )
            } else {
              generateHybrid(state, overrides)
            }
          } catch (e: Exception) {
            // Nothing was committed, so drop the prompt this turn appended
            // rather than leaving it for the next turn to run onto. This
            // stays inside the lock: once it is released the next turn can
            // be reading the transcript, and rewinding under it would cut
            // text this turn never appended.
            rewindTurn(state)
            throw e
          }
        }
        callback(Result.success(result))
      } catch (e: Exception) {
        callback(Result.failure(generationFailure(e)))
      }
    }
    state.job!!.start()
  }

  override fun generateResponseAsync(
    sessionId: Long,
    overrides: GenerationOverrides?,
    callback: (Result<Unit>) -> Unit
  ) {
    val state = try {
      requireSession(sessionId).also { requireIdle(it) }
    } catch (e: Exception) {
      callback(Result.failure(e))
      return
    }

    state.job = scope.launch(start = CoroutineStart.LAZY) {
      val generated = StringBuilder()
      try {
        generationMutex.withLock {
          try {
            if (state.executionPolicy == LocalAiExecutionPolicy.ON_DEVICE_ONLY) {
              client().generateContentStream(buildRequest(state, overrides)).collect { chunk ->
                val piece = chunk.candidates.firstOrNull()?.text.orEmpty()
                if (piece.isNotEmpty()) {
                  generated.append(piece)
                  postToken(sessionId, piece)
                }
              }
              commitTurn(state, generated.toString())
            } else {
              // Firebase's experimental hybrid stream does not expose its
              // final inference source until the response completes. Emit
              // the completed answer as one stream chunk so routing and
              // transcript state remain exact in the alpha API.
              val result = generateHybrid(state, overrides)
              generated.append(result.text)
              if (result.text.isNotEmpty()) postToken(sessionId, result.text)
            }
          } catch (e: CancellationException) {
            // Cooperative cancellation from stopGeneration. The consumer has
            // already seen whatever streamed, so keep it as the model's turn;
            // with nothing streamed, drop the prompt instead. Both run inside
            // the lock, and stopGeneration joins this job before it answers
            // Dart, so the next turn cannot be touching the transcript yet.
            if (generated.isNotEmpty()) commitTurn(state, generated.toString())
            else rewindTurn(state)
            throw e
          } catch (e: Exception) {
            rewindTurn(state)
            throw e
          }
        }
        postDone(sessionId)
      } catch (e: CancellationException) {
        // Not a failure — stopGeneration posts the single completion event
        // on that path.
        throw e
      } catch (e: Exception) {
        postError(sessionId, e)
      }
    }
    state.job!!.start()
    callback(Result.success(Unit))
  }

  override fun generateStructuredResponse(
    sessionId: Long,
    schemaJson: String,
    overrides: GenerationOverrides?,
    callback: (Result<String>) -> Unit
  ) {
    callback(
      Result.failure(
        FlutterError(
          "STRUCTURED_OUTPUT_UNSUPPORTED",
          "Dynamic Dart JSON schemas are not yet bridged to ML Kit's " +
            "Kotlin typed structured-output API. Check " +
            "LocalAi.capabilities().supportsStructuredOutput first.",
          null
        )
      )
    )
  }

  override fun stopGeneration(sessionId: Long, callback: (Result<Unit>) -> Unit) {
    val job = try {
      synchronized(sessionsLock) { sessions[sessionId] }?.job
    } catch (e: Exception) {
      callback(Result.failure(e))
      return
    }
    // Nothing decoding: no stream to close and no turn to settle. Safe to
    // call, and it stays a no-op rather than posting a second DONE.
    if (job == null || !job.isActive) {
      callback(Result.success(Unit))
      return
    }
    scope.launch {
      try {
        // Join, don't just cancel. A cancelled Job reports isActive == false
        // while its handler is still settling the transcript on another
        // dispatcher; returning to Dart before that lands would let the next
        // addQueryChunk race it. Awaiting stopGeneration must mean the turn
        // is finished.
        job.cancelAndJoin()
        // Close the Dart stream cleanly; the cancelled job stays silent.
        postDone(sessionId)
        callback(Result.success(Unit))
      } catch (e: Exception) {
        callback(Result.failure(e))
      }
    }
  }

  override fun countTokens(
    sessionId: Long,
    text: String,
    callback: (Result<Long>) -> Unit
  ) {
    val state = try { requireSession(sessionId) } catch (e: Exception) {
      callback(Result.failure(e)); return
    }
    if (state.executionPolicy != LocalAiExecutionPolicy.ON_DEVICE_ONLY) {
      callback(Result.failure(FlutterError(
        "TOKENIZER_UNAVAILABLE",
        "Hybrid token counts are not comparable between the on-device and cloud models.",
        null,
      )))
      return
    }
    scope.launch {
      try {
        val response = client().countTokens(generateContentRequest(TextPart(text)) {})
        callback(Result.success(response.totalTokens.toLong()))
      } catch (e: Exception) {
        callback(Result.failure(e))
      }
    }
  }

  // Per device: the limit counts input and output together, so a request's
  // `countTokens` plus its answer must stay within it.
  override fun tokenLimit(sessionId: Long, callback: (Result<Long?>) -> Unit) {
    val state = try { requireSession(sessionId) } catch (e: Exception) {
      callback(Result.failure(e)); return
    }
    if (state.executionPolicy != LocalAiExecutionPolicy.ON_DEVICE_ONLY) {
      callback(Result.success(null))
      return
    }
    scope.launch {
      try {
        callback(Result.success(client().getTokenLimit().toLong()))
      } catch (e: Exception) {
        callback(Result.failure(e))
      }
    }
  }
}
