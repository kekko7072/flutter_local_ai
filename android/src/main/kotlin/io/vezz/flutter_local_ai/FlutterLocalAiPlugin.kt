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
import kotlinx.coroutines.withContext
import kotlinx.coroutines.flow.collect

/** FlutterLocalAiPlugin */
class FlutterLocalAiPlugin: FlutterPlugin, MethodCallHandler {
  private lateinit var channel: MethodChannel
  private var generativeModel: GenerativeModel? = null
  private var instructions: String? = null
  private val coroutineScope = CoroutineScope(Dispatchers.Main + SupervisorJob())
  private lateinit var context: Context

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
        if (prompt == null) {
          result.error("INVALID_ARGUMENT", "Prompt is required", null)
          return
        }

        coroutineScope.launch {
          try {
            val response = generateTextAsync(prompt, configMap)
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
        if (prompt == null || requestId == null) {
          result.error("INVALID_ARGUMENT", "Prompt and request id are required", null)
          return
        }

        // The method call returns immediately; output is delivered through the
        // onGenerateTextChunk / Done / Error callbacks tagged with the id.
        result.success(null)
        coroutineScope.launch {
          try {
            generateTextStreamAsync(requestId, prompt, configMap)
            emitStreamEvent("onGenerateTextDone", mapOf("id" to requestId))
          } catch (e: Exception) {
            emitStreamEvent(
              "onGenerateTextError",
              mapOf("id" to requestId, "message" to (e.message ?: "Unknown error"))
            )
          }
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
      "supportsToolCalling" to false,
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
      if (e.errorCode == GenAiException.ErrorCode.AICORE_INCOMPATIBLE) {
        throw IllegalStateException(
          "Google AICore or MLKit is not installed or version is too low. Error code: -101.", e
        )
      }
      throw e
    } catch (e: Exception) {
      Log.e("FlutterLocalAi", "downloadModel generic error: ${e.message}", e)
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
    configMap: Map<String, Any>?
  ): Map<String, Any> = withContext(Dispatchers.IO) {
    try {
      if (generativeModel == null) {
        generativeModel = Generation.getClient()
      }

      val fullPrompt = if (instructions != null) {
        "${instructions}\n\n$prompt"
      } else {
        prompt
      }

      // ML Kit's genai-prompt API hard-caps maxOutputTokens at [1, 256] and
      // throws IllegalArgumentException outside that range; clamp defensively.
      val maxOutputTokensValue = (configMap?.get("maxTokens") as? Number)?.toInt()
        ?.coerceIn(1, 256)
      val temperatureValue = (configMap?.get("temperature") as? Number)?.toFloat()

      val request = generateContentRequest(TextPart(fullPrompt)) {
        if (maxOutputTokensValue != null) maxOutputTokens = maxOutputTokensValue
        if (temperatureValue != null) temperature = temperatureValue
      }

      val startTime = System.currentTimeMillis()
      val response: GenerateContentResponse = generativeModel!!.generateContent(request)
      val generationTime = System.currentTimeMillis() - startTime

      val generatedText = response.candidates.firstOrNull()?.text ?: ""
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
    configMap: Map<String, Any>?
  ) = withContext(Dispatchers.IO) {
    try {
      if (generativeModel == null) {
        generativeModel = Generation.getClient()
      }

      val fullPrompt = if (instructions != null) {
        "${instructions}\n\n$prompt"
      } else {
        prompt
      }

      // Same [1, 256] clamp as generateTextAsync — see the note there.
      val maxOutputTokensValue = (configMap?.get("maxTokens") as? Number)?.toInt()
        ?.coerceIn(1, 256)
      val temperatureValue = (configMap?.get("temperature") as? Number)?.toFloat()

      val request = generateContentRequest(TextPart(fullPrompt)) {
        if (maxOutputTokensValue != null) maxOutputTokens = maxOutputTokensValue
        if (temperatureValue != null) temperature = temperatureValue
      }

      // ML Kit's StreamingCallback delivers newly generated text only, which
      // is exactly the delta contract of onGenerateTextChunk.
      generativeModel!!.generateContent(request, StreamingCallback { newText ->
        emitStreamEvent("onGenerateTextChunk", mapOf("id" to requestId, "text" to newText))
      })
      Unit
    } catch (e: Exception) {
      Log.e("FlutterLocalAi", "generateTextStream error: ${e.javaClass.simpleName} - ${e.message}", e)

      if (e is GenAiException && e.errorCode == GenAiException.ErrorCode.AICORE_INCOMPATIBLE) {
        throw Exception("AICore is not installed or version is too low (Error -101).")
      }

      throw Exception("Error generating text: ${e.message}")
    }
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
  }
}
