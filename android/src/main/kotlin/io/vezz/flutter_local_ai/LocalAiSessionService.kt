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
import com.google.mlkit.genai.prompt.GenerativeModel
import com.google.mlkit.genai.prompt.ImagePart
import com.google.mlkit.genai.prompt.TextPart
import com.google.mlkit.genai.prompt.generateContentRequest
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
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
    const val MAX_OUTPUT_TOKENS_MAX = 256
  }

  private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
  private var eventSink: EventChannel.EventSink? = null

  @Volatile
  private var generativeModel: GenerativeModel? = null
  private val modelLock = Any()

  /** `Generation.getClient()` is cheap and idempotent; one instance serves
   *  status checks, download and every session's generation. */
  private fun client(): GenerativeModel = synchronized(modelLock) {
    generativeModel ?: Generation.getClient().also { generativeModel = it }
  }

  private class SessionState(
    val temperature: Float,
    val topK: Int,
    val maxOutputTokens: Int?,
    systemInstruction: String?,
  ) {
    val transcript = StringBuilder()
    val images = mutableListOf<Bitmap>()

    @Volatile
    var job: Job? = null

    init {
      if (!systemInstruction.isNullOrEmpty()) {
        transcript.append(systemInstruction).append("\n\n")
      }
    }
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

  private fun postDone(sessionId: Long) = postEvent(
    mapOf("partialResult" to "", "done" to true, "sessionId" to sessionId)
  )

  // === Availability ===

  private fun featureStatus(): FeatureStatus = client().checkStatus()

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
      try {
        client().download().collect { status ->
          when (status) {
            is DownloadStatus.DownloadStarted ->
              Log.d(TAG, "Gemini Nano download started")

            is DownloadStatus.DownloadProgress ->
              // ML Kit gives a running byte counter but no reliable total, so
              // bytesTotal is 0 and Dart shows no percentage — it polls
              // availability for the terminal signal instead.
              postEvent(
                mapOf(
                  "code" to "DOWNLOAD_PROGRESS",
                  "bytesDownloaded" to status.totalBytesDownloaded,
                  "bytesTotal" to 0L,
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
      requireSession(sessionId).transcript.append(text)
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
      val state = requireSession(sessionId)
      if (state.images.isNotEmpty()) {
        throw FlutterError(
          "TOO_MANY_IMAGES",
          "ML Kit GenAI accepts at most one image per turn.",
          null
        )
      }
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

  // === Generation ===

  private fun buildRequest(state: SessionState) =
    if (state.images.isNotEmpty()) {
      generateContentRequest(
        ImagePart(state.images.first()),
        TextPart(state.transcript.toString())
      ) {
        temperature = state.temperature
        topK = state.topK
        state.maxOutputTokens?.let { maxOutputTokens = it }
      }
    } else {
      generateContentRequest(TextPart(state.transcript.toString())) {
        temperature = state.temperature
        topK = state.topK
        state.maxOutputTokens?.let { maxOutputTokens = it }
      }
    }

  /** Records the model's turn and clears the consumed image, so the next
   *  turn starts from a clean multimodal slate. */
  private fun commitTurn(state: SessionState, text: String) {
    state.transcript.append(text)
    state.images.clear()
  }

  override fun generateResponse(sessionId: Long, callback: (Result<String>) -> Unit) {
    scope.launch {
      try {
        val state = requireSession(sessionId)
        val response = client().generateContent(buildRequest(state))
        val text = response.candidates.firstOrNull()?.text.orEmpty()
        commitTurn(state, text)
        callback(Result.success(text))
      } catch (e: Exception) {
        callback(Result.failure(e))
      }
    }
  }

  override fun generateResponseAsync(sessionId: Long, callback: (Result<Unit>) -> Unit) {
    val state = try {
      requireSession(sessionId)
    } catch (e: Exception) {
      callback(Result.failure(e))
      return
    }

    state.job = scope.launch {
      val generated = StringBuilder()
      try {
        client().generateContentStream(buildRequest(state)).collect { chunk ->
          val piece = chunk.candidates.firstOrNull()?.text.orEmpty()
          if (piece.isNotEmpty()) {
            generated.append(piece)
            postEvent(
              mapOf(
                "partialResult" to piece,
                "done" to false,
                "sessionId" to sessionId,
              )
            )
          }
        }
        commitTurn(state, generated.toString())
        postDone(sessionId)
      } catch (e: CancellationException) {
        // Cooperative cancellation from stopGeneration — not a failure.
        // stopGeneration posts the single completion event on that path.
        throw e
      } catch (e: Exception) {
        postEvent(
          mapOf(
            "code" to "ERROR",
            "message" to (e.message ?: "Generation failed"),
            "sessionId" to sessionId,
          )
        )
      }
    }
    callback(Result.success(Unit))
  }

  override fun generateStructuredResponse(
    sessionId: Long,
    schemaJson: String,
    callback: (Result<String>) -> Unit
  ) {
    callback(
      Result.failure(
        FlutterError(
          "STRUCTURED_OUTPUT_UNSUPPORTED",
          "Schema-constrained output is not available on Android: the ML Kit " +
            "GenAI Prompt API is text-out only. Check " +
            "LocalAi.capabilities().supportsStructuredOutput first.",
          null
        )
      )
    )
  }

  override fun stopGeneration(sessionId: Long, callback: (Result<Unit>) -> Unit) {
    try {
      val state = synchronized(sessionsLock) { sessions[sessionId] }
      state?.job?.cancel()
      // Close the Dart stream cleanly; the cancelled job stays silent.
      if (state != null) postDone(sessionId)
      callback(Result.success(Unit))
    } catch (e: Exception) {
      callback(Result.failure(e))
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
