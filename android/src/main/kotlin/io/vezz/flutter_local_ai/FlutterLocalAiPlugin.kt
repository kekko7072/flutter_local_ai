package io.vezz.flutter_local_ai

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import androidx.annotation.NonNull
import com.google.mlkit.genai.prompt.GenerativeModel
import com.google.mlkit.genai.prompt.GenerateContentRequest
import com.google.mlkit.genai.prompt.GenerateContentResponse
import com.google.mlkit.genai.prompt.TextPart
import com.google.mlkit.genai.prompt.generateContentRequest
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** FlutterLocalAiPlugin */
class FlutterLocalAiPlugin: FlutterPlugin, MethodCallHandler {
  private lateinit var channel : MethodChannel
  private var generativeModel: GenerativeModel? = null
  private var instructions: String? = null
  private val coroutineScope = CoroutineScope(Dispatchers.Main)
  private var flutterPluginBinding: FlutterPlugin.FlutterPluginBinding? = null

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    this.flutterPluginBinding = flutterPluginBinding
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
    try {
      // Try to get the GenerativeModel client
      val testModel = com.google.mlkit.genai.prompt.Generation.getClient()
      testModel.close()
      true
    } catch (e: Exception) {
      // Log the actual error for debugging
      android.util.Log.e("FlutterLocalAi", "checkAvailability error: ${e.javaClass.simpleName} - ${e.message}", e)
      
      // More specific AICore error detection
      // Check for specific error code -101 which indicates AICore issues
      val errorMessage = e.message ?: ""
      val errorCode = extractErrorCode(errorMessage)
      
      if (errorCode == -101) {
        // Specifically error code -101 = AICore not installed or too old
        throw Exception("AICore is not installed or version is too low. Error code: -101. Please install or update Google AICore from the Play Store.")
      }
      
      // For other errors, just return false without throwing
      // This allows the app to handle other issues gracefully
      false
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
      android.util.Log.e("FlutterLocalAi", "initializeModel error: ${e.javaClass.simpleName} - ${e.message}", e)
      
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
      // Based on the example: result.candidates.first().text
      val generatedText = response.candidates.firstOrNull()?.text ?: ""
      
      // Token count is not directly available in the response
      // Use word count as an approximation
      val tokenCount = generatedText.split(" ").size

      // Return response matching AiResponse model structure
      mapOf(
        "text" to generatedText,
        "generationTimeMs" to generationTime,
        "tokenCount" to (tokenCount ?: generatedText.split(" ").size) // Fallback to word count if token count unavailable
      )
    } catch (e: Exception) {
      // Log the actual error for debugging
      android.util.Log.e("FlutterLocalAi", "generateText error: ${e.javaClass.simpleName} - ${e.message}", e)
      
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
    val context = flutterPluginBinding?.applicationContext 
      ?: throw Exception("Application context not available")
    
    val packageName = "com.google.android.aicore"
    try {
      // Try to open in Play Store app
      val intent = Intent(Intent.ACTION_VIEW).apply {
        data = Uri.parse("market://details?id=$packageName")
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      }
      context.startActivity(intent)
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
    generativeModel?.close()
    generativeModel = null
    instructions = null
    flutterPluginBinding = null
  }
}
