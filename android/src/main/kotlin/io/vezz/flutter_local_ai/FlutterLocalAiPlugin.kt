package io.vezz.flutter_local_ai

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

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
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
      false
    }
  }

  private suspend fun initializeModel(instructionsArg: String?) = withContext(Dispatchers.IO) {
    // Store instructions if provided (for consistency with iOS API)
    instructions = instructionsArg
    
    // Initialize model if not already done
    if (generativeModel == null) {
      generativeModel = com.google.mlkit.genai.prompt.Generation.getClient()
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
      throw Exception("Failed to generate text: ${e.message}")
    }
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    generativeModel?.close()
    generativeModel = null
    instructions = null
  }
}
