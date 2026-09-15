package io.vezz.flutter_local_ai

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.util.Log
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

  private fun postError(sessionId: Long, message: String) = postEvent(
    mapOf("code" to "ERROR", "message" to message, "sessionId" to sessionId)
  )

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
            "This device does not support Gemini Nano through AICore. It needs " +
              "a Pixel 9 or newer, a Galaxy S25 or newer, or another AICore " +
              "device."
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
          // The Prompt API is text/image-in, text-out: no function calling
          // and no schema constraint. Revisit when Agent Mode reaches it.
          supportsToolCalling = false,
          supportsStructuredOutput = false,
          supportsVision = true,
          supportsTokenCount = true,
          supportsModelDownload = true,
          supportsPlayStoreRedirect = true,
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

  // === Model lifecycle ===

  override fun createModel(supportImage: Boolean, callback: (Result<Unit>) -> Unit) {
    scope.launch {
      try {
        // The OS owns the weights; this only wires up the AICore client.
        // supportImage is advisory — multimodality is decided per request.
        client()
        callback(Result.success(Unit))
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
    temperature: Double,
    topK: Long,
    topP: Double?,
    maxOutputTokens: Long?,
    systemInstruction: String?,
    tools: List<ToolSpec>?,
    callback: (Result<Unit>) -> Unit
  ) {
    if (!tools.isNullOrEmpty()) {
      // Prompt-emulated tool use was tried and dropped: Gemini Nano does not
      // follow a JSON call protocol reliably enough to be worth pretending.
      // Failing loudly beats a caller waiting for tool execution that never
      // happens.
      callback(
        Result.failure(
          FlutterError(
            "TOOL_CALLING_UNSUPPORTED",
            "The ML Kit GenAI Prompt API has no function calling. Check " +
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
      )
      synchronized(sessionsLock) {
        sessions[sessionId]?.job?.cancel()
        sessions[sessionId] = state
      }
      callback(Result.success(Unit))
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

  override fun generateResponse(
    sessionId: Long,
    overrides: GenerationOverrides?,
    callback: (Result<String>) -> Unit
  ) {
    val state = try {
      requireSession(sessionId).also { requireIdle(it) }
    } catch (e: Exception) {
      callback(Result.failure(e))
      return
    }
    state.job = scope.launch(start = CoroutineStart.LAZY) {
      try {
        val text = generationMutex.withLock {
          try {
            val response = client().generateContent(buildRequest(state, overrides))
            response.candidates.firstOrNull()?.text.orEmpty().also { commitTurn(state, it) }
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
        callback(Result.success(text))
      } catch (e: Exception) {
        callback(Result.failure(e))
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
            client().generateContentStream(buildRequest(state, overrides)).collect { chunk ->
              val piece = chunk.candidates.firstOrNull()?.text.orEmpty()
              if (piece.isNotEmpty()) {
                generated.append(piece)
                postToken(sessionId, piece)
              }
            }
            commitTurn(state, generated.toString())
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
        postError(sessionId, e.message ?: "Generation failed")
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

  override fun countTokens(text: String, callback: (Result<Long>) -> Unit) {
    scope.launch {
      try {
        val response = client().countTokens(generateContentRequest(TextPart(text)) {})
        callback(Result.success(response.totalTokens.toLong()))
      } catch (e: Exception) {
        callback(Result.failure(e))
      }
    }
  }
}
