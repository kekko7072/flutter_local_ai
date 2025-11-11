package io.vezz.flutter_local_ai

import androidx.annotation.NonNull
import com.google.mlkit.genai.GenerativeModel
import com.google.mlkit.genai.generativeai.GenerateContentRequest
import com.google.mlkit.genai.generativeai.GenerateContentResponse
import com.google.mlkit.genai.generativeai.GenerationConfig
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.tasks.await

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
      // Try to create a model instance to check availability
      // Using the default model name for ML Kit GenAI
      val testModel = GenerativeModel.builder()
        .setModelName("gemini-2.0-flash-exp")
        .build()
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
      generativeModel = GenerativeModel.builder()
        .setModelName("gemini-2.0-flash-exp")
        .build()
    }
  }

  private suspend fun generateTextAsync(
    prompt: String,
    configMap: Map<String, Any>?
  ): Map<String, Any> = withContext(Dispatchers.IO) {
    try {
      // Initialize model if not already done
      if (generativeModel == null) {
        generativeModel = GenerativeModel.builder()
          .setModelName("gemini-2.0-flash-exp")
          .build()
      }

      // Build generation config according to GenerationConfig model
      // Only maxTokens and temperature are supported
      val generationConfigBuilder = GenerationConfig.Builder()
      configMap?.let { config ->
        config["maxTokens"]?.let { 
          generationConfigBuilder.setMaxOutputTokens((it as Number).toInt())
        }
        config["temperature"]?.let { 
          generationConfigBuilder.setTemperature((it as Number).toDouble())
        }
      }
      val generationConfig = generationConfigBuilder.build()

      // Build the prompt with instructions if available
      val fullPrompt = if (instructions != null) {
        "${instructions}\n\n$prompt"
      } else {
        prompt
      }

      // Create request according to ML Kit GenAI API
      // https://developers.google.com/ml-kit/genai/prompt/android/get-started
      val request = GenerateContentRequest.Builder()
        .addContent(fullPrompt)
        .setGenerationConfig(generationConfig)
        .build()

      // Generate content (ML Kit GenAI uses Task API)
      val startTime = System.currentTimeMillis()
      val task = generativeModel!!.generateContent(request)
      val response: GenerateContentResponse = task.await()
      val generationTime = System.currentTimeMillis() - startTime

      // Extract response text
      val generatedText = response.text ?: ""
      
      // Get token count from usage metadata if available
      val tokenCount = response.usageMetadata?.totalTokenCount

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
    generativeModel = null
    instructions = null
  }
}
