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
import com.google.mlkit.genai.prompt.generateContentRequest
import com.google.mlkit.genai.prompt.FeatureStatus
import com.google.mlkit.genai.prompt.GenAiException
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
      "openAICorePlayStore" -> {
        try {
          openAICoreInPlayStore()
          result.success(true)
        } catch (e: Exception) {
          result.error("PLAY_STORE_ERROR", "Could not open Play Store: ${e.message}", null)
        }
      }
      else -> {
        result.notImplemented()
      }
    }
  }

  private suspend fun checkAvailability(): Boolean = withContext(Dispatchers.IO) {
    // Use the context to get the client, consistent with best practices
    val model = com.google.mlkit.genai.prompt.Generation.getClient(context)
    try {
      when (model.checkStatus()) {
        FeatureStatus.AVAILABLE -> true
        FeatureStatus.DOWNLOADABLE,
        FeatureStatus.DOWNLOADING,
        FeatureStatus.UNAVAILABLE -> false
        else -> false
      }
    } catch (e: GenAiException) {
      // Log the actual error for debugging
      Log.e("FlutterLocalAi", "checkAvailability error: ${e.message}", e)

      if (e.errorCode == GenAiException.ErrorCode.AICORE_INCOMPATIBLE) { // -101
         // Throw specific exception to be handled by caller or just return false
         // Since the original signature returns Boolean, we should probably just Log and return false
         // or if we want to propagate the error message, we need to change how this is called.
         // However, the caller catches Exception (line 46) and returns error.
         // So throwing here will result in result.error("UNAVAILABLE", ...)
         throw IllegalStateException(
             "Google AICore 未安装或版本过低（-101）。请安装/更新 Google AICore。", e
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
  
  private fun extractErrorCode(message: String): Int? {
    // Extract error code from messages like "Error code: -101" or "(-101)" or "-101"
    val regex = Regex("""[(\s](-?\d+)[)\s]""")
    val match = regex.find(message)
    return match?.groupValues?.get(1)?.toIntOrNull()
  }

  private suspend fun initializeModel(instructionsArg: String?) = withContext(Dispatchers.IO) {
    try {
      // Store instructions if provided (for consistency with iOS API)
      instructions = instructionsArg
      
      // Initialize model if not already done
      if (generativeModel == null) {
        generativeModel = com.google.mlkit.genai.prompt.Generation.getClient()
      }
    } catch (e: Exception) {
      // Log the actual error for debugging
      Log.e("FlutterLocalAi", "initializeModel error: ${e.javaClass.simpleName} - ${e.message}", e)
      
      val errorMessage = e.message ?: ""
      val errorCode = extractErrorCode(errorMessage)
      
      if (errorCode == -101) {
        throw Exception("AICore is not installed or version is too low (Error -101). Please install or update Google AICore from the Play Store: https://play.google.com/store/apps/details?id=com.google.android.aicore")
      }
      
      // Re-throw the original exception for other errors
      throw Exception("Failed to initialize model: ${e.message}")
    }
  }

  private suspend fun generateTextAsync(
    prompt: String,
    configMap: Map<String, Any>?
  ): Map<String, Any> = withContext(Dispatchers.IO) {
    try {
      // Initialize model if not already done
      if (generativeModel == null) {
        generativeModel = com.google.mlkit.genai.prompt.Generation.getClient()
      }

      // Build the prompt with instructions if available
      val fullPrompt = if (instructions != null) {
        "${instructions}\n\n$prompt"
      } else {
        prompt
      }

      // Extract generation config parameters
      val maxOutputTokensValue = configMap?.get("maxTokens")?.let { (it as Number).toInt() }
      val temperatureValue = configMap?.get("temperature")?.let { (it as Number).toDouble()?.toFloat() }

      // Create request using generateContentRequest utility function
      // https://developers.google.com/ml-kit/genai/prompt/android/get-started
      val request = generateContentRequest(TextPart(fullPrompt)) {
        maxOutputTokens = maxOutputTokensValue
        temperature = temperatureValue
      }

      // Generate content - the API returns GenerateContentResponse directly (suspending function)
      val startTime = System.currentTimeMillis()
      val response: GenerateContentResponse = generativeModel!!.generateContent(request)
      val generationTime = System.currentTimeMillis() - startTime

      // Extract response text from candidates
      val generatedText = response.candidates.firstOrNull()?.text ?: ""
      
      // Token count is not directly available in the response
      // Use word count as an approximation
      val tokenCount = generatedText.split(" ").filter { it.isNotEmpty() }.size

      // Return response matching AiResponse model structure
      mapOf(
        "text" to generatedText,
        "generationTimeMs" to generationTime,
        "tokenCount" to tokenCount
      )
    } catch (e: Exception) {
      // Log the actual error for debugging
      Log.e("FlutterLocalAi", "generateText error: ${e.javaClass.simpleName} - ${e.message}", e)
      
      val errorMessage = e.message ?: ""
      val errorCode = extractErrorCode(errorMessage)
      
      if (errorCode == -101) {
        throw Exception("AICore is not installed or version is too low (Error -101). Please install or update Google AICore from the Play Store: https://play.google.com/store/apps/details?id=com.google.android.aicore")
      }
      
      // For other errors, provide the actual error message
      throw Exception("Error generating text: ${e.message}")
    }
  }

  private fun openAICoreInPlayStore() {
    if (!::context.isInitialized) {
      throw Exception("Context not initialized")
    }
    
    val packageName = "com.google.android.aicore"
    try {
      // Try to open in Play Store app
      val intent = Intent(Intent.ACTION_VIEW).apply {
        data = Uri.parse("market://details?id=$packageName")
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      }
      if (intent.resolveActivity(context.packageManager) != null) {
        context.startActivity(intent)
      } else {
        // If Play Store app not available, open in browser
        val browserIntent = Intent(Intent.ACTION_VIEW).apply {
          data = Uri.parse("https://play.google.com/store/apps/details?id=$packageName")
          addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(browserIntent)
      }
    } catch (e: ActivityNotFoundException) {
      // If Play Store app not available, open in browser
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
