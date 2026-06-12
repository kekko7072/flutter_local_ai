package io.vezz.flutter_local_ai

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import androidx.annotation.NonNull
import com.google.mlkit.genai.prompt.GenerativeModel
import com.google.mlkit.genai.prompt.GenerateContentResponse
import com.google.mlkit.genai.prompt.TextPart
import com.google.mlkit.genai.prompt.Generation
import com.google.mlkit.genai.prompt.generateContentRequest
import com.google.mlkit.genai.common.DownloadStatus
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.common.GenAiException
import com.google.mlkit.genai.common.StreamingCallback
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.flow.collect
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import org.json.JSONArray
import org.json.JSONObject

/** FlutterLocalAiPlugin */
class FlutterLocalAiPlugin: FlutterPlugin, MethodCallHandler {
  private lateinit var channel: MethodChannel
  private var generativeModel: GenerativeModel? = null
  private var instructions: String? = null
  private val coroutineScope = CoroutineScope(Dispatchers.Main + SupervisorJob())
  private lateinit var context: Context

  // Written on the platform thread (registerTools), read from IO coroutines.
  @Volatile
  private var registeredTools: List<RegisteredTool> = emptyList()

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    context = flutterPluginBinding.applicationContext
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_local_ai")
    channel.setMethodCallHandler(this)
  }

  override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
    when (call.method) {
      "isAvailable" -> {
        coroutineScope.launch {
          try {
            val available = checkAvailability()
            result.success(available)
          } catch (e: Exception) {
            result.error("UNAVAILABLE", "Error checking availability: ${e.message}", null)
          }
        }
      }
      "getPlatformInfo" -> {
        result.success(getPlatformInfo())
      }
      "initialize" -> {
        val instructionsArg = call.argument<String>("instructions")
        coroutineScope.launch {
          try {
            initializeModel(instructionsArg)
            result.success(true)
          } catch (e: Exception) {
            result.error("INITIALIZATION_ERROR", "Error initializing model: ${e.message}", null)
          }
        }
      }
      "generateText" -> {
        val prompt = call.argument<String>("prompt")
        val configMap = call.argument<Map<String, Any>>("config")
        val oneShot = call.argument<String>("instructions")
        if (prompt == null) {
          result.error("INVALID_ARGUMENT", "Prompt is required", null)
          return
        }

        coroutineScope.launch {
          try {
            val response = generateTextAsync(prompt, configMap, oneShot)
            result.success(response)
          } catch (e: Exception) {
            result.error("GENERATION_ERROR", "Error generating text: ${e.message}", null)
          }
        }
      }
      "generateTextStream" -> {
        val prompt = call.argument<String>("prompt")
        val requestId = call.argument<Int>("id")
        val configMap = call.argument<Map<String, Any>>("config")
        val oneShot = call.argument<String>("instructions")
        if (prompt == null || requestId == null) {
          result.error("INVALID_ARGUMENT", "Prompt and request id are required", null)
          return
        }

        // The method call returns immediately; output is delivered through the
        // onGenerateTextChunk / Done / Error callbacks tagged with the id.
        result.success(null)
        coroutineScope.launch {
          try {
            generateTextStreamAsync(requestId, prompt, configMap, oneShot)
            emitStreamEvent("onGenerateTextDone", mapOf("id" to requestId))
          } catch (e: Exception) {
            emitStreamEvent(
              "onGenerateTextError",
              mapOf("id" to requestId, "message" to (e.message ?: "Unknown error"))
            )
          }
        }
      }
      "registerTools" -> {
        try {
          registeredTools = parseToolPayload(call.arguments)
          result.success(true)
        } catch (e: Exception) {
          result.error("TOOL_REGISTRATION_FAILED", "Failed to register tools: ${e.message}", null)
        }
      }
      "openAICorePlayStore" -> {
        try {
          openAICoreInPlayStore()
          result.success(true)
        } catch (e: Exception) {
          result.error("PLAY_STORE_ERROR", "Could not open Play Store: ${e.message}", null)
        }
      }
      "getModelStatus" -> {
        coroutineScope.launch {
          try {
            val status = getModelStatus()
            result.success(status)
          } catch (e: Exception) {
            result.error("STATUS_ERROR", "Error checking model status: ${e.message}", null)
          }
        }
      }
      "availabilityReason" -> {
        coroutineScope.launch {
          try {
            val status = getModelStatus()
            val reason = when (status) {
              "available" -> "available"
              "downloadable" -> "unavailable: model downloadable (call downloadModel)"
              "downloading" -> "unavailable: model downloading"
              "unavailable" -> "unavailable: not supported on this device"
              else -> "unavailable: $status"
            }
            result.success(reason)
          } catch (e: Exception) {
            result.success("unavailable: ${e.message}")
          }
        }
      }
      "downloadModel" -> {
        coroutineScope.launch {
          try {
            downloadModel()
            result.success(true)
          } catch (e: Exception) {
            result.error("DOWNLOAD_ERROR", "Error downloading model: ${e.message}", null)
          }
        }
      }
      else -> {
        result.notImplemented()
      }
    }
  }

  private fun getPlatformInfo(): Map<String, Any> {
    return mapOf(
      "backend" to "android_mlkit_genai",
      "platform" to "android",
      "apiName" to "Google ML Kit GenAI (AICore)",
      // Emulated: the Prompt API has no native function calling, so tool use is
      // driven through a prompted JSON protocol — see runToolLoop().
      "supportsToolCalling" to true,
      "supportsModelDownload" to true,
      "supportsPlayStoreRedirect" to true,
      "isConfigured" to true
    )
  }

  private suspend fun checkAvailability(): Boolean = withContext(Dispatchers.IO) {
    val model = Generation.getClient()
    try {
      when (model.checkStatus()) {
        FeatureStatus.AVAILABLE -> true
        FeatureStatus.DOWNLOADABLE,
        FeatureStatus.DOWNLOADING,
        FeatureStatus.UNAVAILABLE -> false
        else -> false
      }
    } catch (e: GenAiException) {
      Log.e("FlutterLocalAi", "checkAvailability error: ${e.message}", e)

      if (e.errorCode == GenAiException.ErrorCode.AICORE_INCOMPATIBLE) {
        throw IllegalStateException(
          "Google AICore or MLKit is not installed or version is too low. Error code: -101.", e
        )
      }
      false
    } catch (e: Exception) {
      Log.e("FlutterLocalAi", "checkAvailability generic error: ${e.message}", e)
      false
    } finally {
      model.close()
    }
  }

  private suspend fun getModelStatus(): String = withContext(Dispatchers.IO) {
    val model = Generation.getClient()
    try {
      return@withContext when (model.checkStatus()) {
        FeatureStatus.AVAILABLE -> "available"
        FeatureStatus.DOWNLOADABLE -> "downloadable"
        FeatureStatus.DOWNLOADING -> "downloading"
        FeatureStatus.UNAVAILABLE -> "unavailable"
        else -> "unknown"
      }
    } catch (e: GenAiException) {
      Log.e("FlutterLocalAi", "getModelStatus error: ${e.message}", e)

      if (e.errorCode == GenAiException.ErrorCode.AICORE_INCOMPATIBLE) {
        throw IllegalStateException(
          "Google AICore or MLKit is not installed or version is too low. Error code: -101.", e
        )
      }
      return@withContext "unknown"
    } catch (e: Exception) {
      Log.e("FlutterLocalAi", "getModelStatus generic error: ${e.message}", e)
      return@withContext "unknown"
    } finally {
      model.close()
    }
  }

  private fun emitDownloadStatus(payload: Map<String, Any?>) {
    coroutineScope.launch(Dispatchers.Main) {
      channel.invokeMethod("onDownloadStatus", payload)
    }
  }

  private suspend fun downloadModel() = withContext(Dispatchers.IO) {
    val model = Generation.getClient()
    try {
      // Idempotent: a model that's already on the device just reports done, so
      // callers can re-invoke after relaunch/retry without special-casing.
      if (model.checkStatus() == FeatureStatus.AVAILABLE) {
        emitDownloadStatus(mapOf("status" to "completed"))
        return@withContext
      }
      model.download().collect { status ->
        when (status) {
          is DownloadStatus.DownloadStarted -> {
            emitDownloadStatus(mapOf("status" to "started"))
          }
          is DownloadStatus.DownloadProgress -> {
            emitDownloadStatus(
              mapOf(
                "status" to "progress",
                "totalBytesDownloaded" to status.totalBytesDownloaded
              )
            )
          }
          is DownloadStatus.DownloadCompleted -> {
            emitDownloadStatus(mapOf("status" to "completed"))
          }
          is DownloadStatus.DownloadFailed -> {
            emitDownloadStatus(
              mapOf(
                "status" to "failed",
                "errorMessage" to (status.e.message ?: "Unknown error")
              )
            )
          }
          else -> {
            emitDownloadStatus(mapOf("status" to "unknown"))
          }
        }
      }
    } catch (e: GenAiException) {
      Log.e("FlutterLocalAi", "downloadModel error: ${e.message}", e)
      // The status stream is what UIs watch — a failure that only surfaced on
      // the method-call result would leave them spinning forever.
      val message = if (e.errorCode == GenAiException.ErrorCode.AICORE_INCOMPATIBLE) {
        "Google AICore or MLKit is not installed or version is too low. Error code: -101."
      } else {
        e.message ?: "Unknown error"
      }
      emitDownloadStatus(mapOf("status" to "failed", "errorMessage" to message))
      if (e.errorCode == GenAiException.ErrorCode.AICORE_INCOMPATIBLE) {
        throw IllegalStateException(message, e)
      }
      throw e
    } catch (e: Exception) {
      Log.e("FlutterLocalAi", "downloadModel generic error: ${e.message}", e)
      emitDownloadStatus(
        mapOf("status" to "failed", "errorMessage" to (e.message ?: "Unknown error"))
      )
      throw e
    } finally {
      model.close()
    }
  }

  private fun extractErrorCode(message: String): Int? {
    val regex = Regex("""[(\s](-?\d+)[)\s]""")
    val match = regex.find(message)
    return match?.groupValues?.get(1)?.toIntOrNull()
  }

  private suspend fun initializeModel(instructionsArg: String?) = withContext(Dispatchers.IO) {
    try {
      instructions = instructionsArg

      if (generativeModel == null) {
        generativeModel = Generation.getClient()
      }
    } catch (e: Exception) {
      Log.e("FlutterLocalAi", "initializeModel error: ${e.javaClass.simpleName} - ${e.message}", e)

      // Check for AICore incompatible error
      if (e is GenAiException && e.errorCode == GenAiException.ErrorCode.AICORE_INCOMPATIBLE) {
        throw Exception("AICore is not installed or version is too low (Error -101).")
      }

      val errorMessage = e.message ?: ""
      val errorCode = extractErrorCode(errorMessage)

      if (errorCode == -101) {
        throw Exception("AICore is not installed or version is too low (Error -101). Please install or update Google AICore from the Play Store.")
      }

      throw Exception("Failed to initialize model: ${e.message}")
    }
  }

  private suspend fun generateTextAsync(
    prompt: String,
    configMap: Map<String, Any>?,
    oneShotInstructions: String? = null
  ): Map<String, Any> = withContext(Dispatchers.IO) {
    try {
      if (generativeModel == null) {
        generativeModel = Generation.getClient()
      }

      // ML Kit generations are already stateless; per-call instructions just
      // replace the session-level ones for this prompt (one-shot parity with
      // the Apple backend).
      val fullPrompt = buildFullPrompt(prompt, oneShotInstructions)

      // ML Kit's genai-prompt API hard-caps maxOutputTokens at [1, 256] and
      // throws IllegalArgumentException outside that range; clamp defensively.
      val maxOutputTokensValue = (configMap?.get("maxTokens") as? Number)?.toInt()
        ?.coerceIn(1, 256)
      val temperatureValue = (configMap?.get("temperature") as? Number)?.toFloat()

      val startTime = System.currentTimeMillis()
      val generatedText = if (registeredTools.isEmpty()) {
        runGeneration(fullPrompt, maxOutputTokensValue, temperatureValue)
      } else {
        runToolLoop(fullPrompt, maxOutputTokensValue, temperatureValue)
      }
      val generationTime = System.currentTimeMillis() - startTime
      val tokenCount = generatedText.split(" ").filter { it.isNotEmpty() }.size

      mapOf(
        "text" to generatedText,
        "generationTimeMs" to generationTime,
        "tokenCount" to tokenCount
      )
    } catch (e: Exception) {
      Log.e("FlutterLocalAi", "generateText error: ${e.javaClass.simpleName} - ${e.message}", e)

      if (e is GenAiException && e.errorCode == GenAiException.ErrorCode.AICORE_INCOMPATIBLE) {
        throw Exception("AICore is not installed or version is too low (Error -101).")
      }

      throw Exception("Error generating text: ${e.message}")
    }
  }

  private fun emitStreamEvent(method: String, payload: Map<String, Any?>) {
    coroutineScope.launch(Dispatchers.Main) {
      channel.invokeMethod(method, payload)
    }
  }

  private suspend fun generateTextStreamAsync(
    requestId: Int,
    prompt: String,
    configMap: Map<String, Any>?,
    oneShotInstructions: String? = null
  ) = withContext(Dispatchers.IO) {
    try {
      if (generativeModel == null) {
        generativeModel = Generation.getClient()
      }

      // Same one-shot semantics as generateTextAsync.
      val fullPrompt = buildFullPrompt(prompt, oneShotInstructions)

      // Same [1, 256] clamp as generateTextAsync — see the note there.
      val maxOutputTokensValue = (configMap?.get("maxTokens") as? Number)?.toInt()
        ?.coerceIn(1, 256)
      val temperatureValue = (configMap?.get("temperature") as? Number)?.toFloat()

      if (registeredTools.isEmpty()) {
        val request = generateContentRequest(TextPart(fullPrompt)) {
          if (maxOutputTokensValue != null) maxOutputTokens = maxOutputTokensValue
          if (temperatureValue != null) temperature = temperatureValue
        }

        // ML Kit's StreamingCallback delivers newly generated text only, which
        // is exactly the delta contract of onGenerateTextChunk.
        generativeModel!!.generateContent(request, StreamingCallback { newText ->
          emitStreamEvent("onGenerateTextChunk", mapOf("id" to requestId, "text" to newText))
        })
      } else {
        // A round's output is only known to be a tool call (vs. the final
        // answer) once it's complete, so with tools registered the stream
        // degrades to buffered delivery: one chunk with the final text.
        val finalText = runToolLoop(fullPrompt, maxOutputTokensValue, temperatureValue)
        if (finalText.isNotEmpty()) {
          emitStreamEvent("onGenerateTextChunk", mapOf("id" to requestId, "text" to finalText))
        }
      }
      Unit
    } catch (e: Exception) {
      Log.e("FlutterLocalAi", "generateTextStream error: ${e.javaClass.simpleName} - ${e.message}", e)

      if (e is GenAiException && e.errorCode == GenAiException.ErrorCode.AICORE_INCOMPATIBLE) {
        throw Exception("AICore is not installed or version is too low (Error -101).")
      }

      throw Exception("Error generating text: ${e.message}")
    }
  }

  private fun buildFullPrompt(prompt: String, oneShotInstructions: String?): String {
    val effectiveInstructions = oneShotInstructions ?: instructions
    val toolInstructions = if (registeredTools.isNotEmpty()) buildToolInstructions() else null
    return listOfNotNull(effectiveInstructions, toolInstructions, prompt).joinToString("\n\n")
  }

  private suspend fun runGeneration(
    prompt: String,
    maxOutputTokensValue: Int?,
    temperatureValue: Float?
  ): String {
    val request = generateContentRequest(TextPart(prompt)) {
      if (maxOutputTokensValue != null) maxOutputTokens = maxOutputTokensValue
      if (temperatureValue != null) temperature = temperatureValue
    }
    val response: GenerateContentResponse = generativeModel!!.generateContent(request)
    return response.candidates.firstOrNull()?.text ?: ""
  }

  // --- Tool calling (emulated) ---------------------------------------------
  //
  // The Prompt API has no native function calling, so tools work through a
  // prompted protocol: the model is told it may reply with a one-line JSON
  // tool call, that call is executed by the registered Dart handler through
  // the same onToolCall channel round-trip the Apple backend uses, and the
  // result is appended to the transcript for the next round.

  private fun parseToolPayload(arguments: Any?): List<RegisteredTool> {
    val payload = arguments as? List<*> ?: return emptyList()
    return payload.mapNotNull { raw ->
      val map = raw as? Map<*, *> ?: return@mapNotNull null
      val name = map["name"] as? String ?: return@mapNotNull null
      val parameters = (map["parameters"] as? List<*>)?.mapNotNull { entry ->
        (entry as? Map<*, *>)?.entries?.associate { it.key.toString() to it.value }
      } ?: emptyList()
      RegisteredTool(
        name = name,
        description = map["description"] as? String ?: "",
        parameters = parameters
      )
    }
  }

  private fun buildToolInstructions(): String {
    val toolLines = registeredTools.joinToString("\n") { tool ->
      val signature = tool.parameters.joinToString(", ") { parameter ->
        val optionalMark = if (parameter["optional"] == true) "?" else ""
        "${parameter["name"]}$optionalMark: ${parameter["type"] ?: "string"}"
      }
      val parameterDocs = tool.parameters.mapNotNull { parameter ->
        val description = parameter["description"] as? String ?: return@mapNotNull null
        "${parameter["name"]}: $description"
      }
      val docs = if (parameterDocs.isEmpty()) "" else " (${parameterDocs.joinToString("; ")})"
      "- ${tool.name}($signature): ${tool.description}$docs"
    }
    return "You can call tools.\nAvailable tools:\n$toolLines\n" +
      "To call a tool reply with ONLY this JSON on one line and nothing else:\n" +
      "{\"tool\": \"<tool name>\", \"args\": {\"<parameter>\": <value>}}\n" +
      "When the conversation contains \"Tool result:\", use it to answer in " +
      "plain text instead of repeating that call."
  }

  /** Returns the registered tool + arguments when [output] is a tool call. */
  private fun parseToolCall(output: String): Pair<RegisteredTool, JSONObject>? {
    if (registeredTools.isEmpty()) return null
    var text = output.trim()
    if (text.startsWith("```")) {
      text = text.removePrefix("```json").removePrefix("```").trim()
        .removeSuffix("```").trim()
    }
    val start = text.indexOf('{')
    val end = text.lastIndexOf('}')
    if (start == -1 || end <= start) return null
    val json = try {
      JSONObject(text.substring(start, end + 1))
    } catch (e: Exception) {
      return null
    }
    // Small models drift on the envelope; accept a {"tool_call": {...}}
    // wrapper and "name"/"arguments" key aliases.
    val callObject = json.optJSONObject("tool_call") ?: json
    val toolName = callObject.optString("tool").ifEmpty { callObject.optString("name") }
    // Only a name matching a registered tool counts as a call — that keeps
    // legitimate JSON answers (e.g. genUI module specs) from being hijacked.
    val tool = registeredTools.find { it.name == toolName } ?: return null
    val args = callObject.optJSONObject("args")
      ?: callObject.optJSONObject("arguments")
      ?: JSONObject()
    return tool to args
  }

  private suspend fun runToolLoop(
    initialPrompt: String,
    maxOutputTokensValue: Int?,
    temperatureValue: Float?
  ): String {
    val transcript = StringBuilder(initialPrompt)
    repeat(MAX_TOOL_ROUNDS) {
      val output = runGeneration(transcript.toString(), maxOutputTokensValue, temperatureValue)
      val (tool, args) = parseToolCall(output) ?: return output
      val toolResult = try {
        invokeDartTool(tool, args)
      } catch (e: Exception) {
        Log.e("FlutterLocalAi", "Tool ${tool.name} failed: ${e.message}", e)
        // The model still gets something to answer with instead of the
        // whole generation dying on a tool failure.
        "Error: ${e.message}"
      }
      transcript
        .append("\n").append(output.trim())
        .append("\nTool result: ").append(toolResultToPromptText(toolResult))
        .append("\nUse the tool result to answer in plain text, or call another tool if needed.")
    }
    // Tool budget exhausted — force a plain-text answer.
    transcript.append("\nAnswer now in plain text. Do not call any more tools.")
    return runGeneration(transcript.toString(), maxOutputTokensValue, temperatureValue)
  }

  private suspend fun invokeDartTool(tool: RegisteredTool, args: JSONObject): Any? =
    // Platform channels must be invoked from the main thread.
    withContext(Dispatchers.Main) {
      suspendCancellableCoroutine { continuation ->
        val payload = mapOf(
          "toolName" to tool.name,
          "arguments" to jsonToChannelValue(args)
        )
        channel.invokeMethod("onToolCall", payload, object : Result {
          override fun success(result: Any?) {
            continuation.resume(result)
          }

          override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
            continuation.resumeWithException(Exception(errorMessage ?: errorCode))
          }

          override fun notImplemented() {
            continuation.resumeWithException(Exception("No Dart handler for onToolCall"))
          }
        })
      }
    }

  private fun jsonToChannelValue(value: Any?): Any? = when (value) {
    null, JSONObject.NULL -> null
    is JSONObject -> value.keys().asSequence()
      .associateWith { key -> jsonToChannelValue(value.get(key)) }
    is JSONArray -> (0 until value.length()).map { jsonToChannelValue(value.get(it)) }
    else -> value
  }

  private fun toolResultToPromptText(result: Any?): String = when (result) {
    null -> "null"
    is String -> result
    else -> JSONObject.wrap(result)?.toString() ?: result.toString()
  }

  private fun openAICoreInPlayStore() {
    if (!::context.isInitialized) {
      throw Exception("Context not initialized")
    }

    val packageName = "com.google.android.aicore"
    try {
      val intent = Intent(Intent.ACTION_VIEW).apply {
        data = Uri.parse("market://details?id=$packageName")
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      }
      if (intent.resolveActivity(context.packageManager) != null) {
        context.startActivity(intent)
      } else {
        val browserIntent = Intent(Intent.ACTION_VIEW).apply {
          data = Uri.parse("https://play.google.com/store/apps/details?id=$packageName")
          addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(browserIntent)
      }
    } catch (e: ActivityNotFoundException) {
      val intent = Intent(Intent.ACTION_VIEW).apply {
        data = Uri.parse("https://play.google.com/store/apps/details?id=$packageName")
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      }
      context.startActivity(intent)
    }
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    coroutineScope.cancel()
    generativeModel?.close()
    generativeModel = null
    instructions = null
    registeredTools = emptyList()
  }

  private companion object {
    // Hard ceiling on tool round-trips per generation — keeps a model that
    // loops on tool JSON from spinning forever inside Nano's small context.
    const val MAX_TOOL_ROUNDS = 3
  }
}

/** Tool definition mirrored from the Dart-side LocalAiTool. */
private data class RegisteredTool(
  val name: String,
  val description: String,
  val parameters: List<Map<String, Any?>>
)
