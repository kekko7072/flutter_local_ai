package com.example.flutter_local_ai

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
  private val coroutineScope = CoroutineScope(Dispatchers.Main)

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_local_ai")
    channel.setMethodCallHandler(this)
  }

  override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
    when (call.method) {
      "isAvailable" -> {
        try {
          // Check if ML Kit GenAI is available
          val available = try {
            // Try to create a model instance to check availability
            val model = GenerativeModel.builder()
              .setModelName("gemini-2.0-flash-exp")
              .build()
            true
          } catch (e: Exception) {
            false
          }
          result.success(available)
        } catch (e: Exception) {
          result.error("UNAVAILABLE", "Error checking availability: ${e.message}", null)
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

      // Build generation config
      val generationConfigBuilder = GenerationConfig.Builder()
      configMap?.let { config ->
        config["maxTokens"]?.let { 
          generationConfigBuilder.setMaxOutputTokens((it as Number).toInt())
        }
        config["temperature"]?.let { 
          generationConfigBuilder.setTemperature((it as Number).toDouble())
        }
        config["topP"]?.let { 
          generationConfigBuilder.setTopP((it as Number).toDouble())
        }
        config["topK"]?.let { 
          generationConfigBuilder.setTopK((it as Number).toInt())
        }
      }
      val generationConfig = generationConfigBuilder.build()

      // Create request
      val request = GenerateContentRequest.Builder()
        .addContent(prompt)
        .setGenerationConfig(generationConfig)
        .build()

      // Generate content (ML Kit GenAI uses Task API)
      val startTime = System.currentTimeMillis()
      val task = generativeModel!!.generateContent(request)
      val response: GenerateContentResponse = task.await()
      val generationTime = System.currentTimeMillis() - startTime

      val generatedText = response.text ?: ""
      val tokenCount = response.usageMetadata?.totalTokenCount ?: 0
      
      mapOf(
        "text" to generatedText,
        "generationTimeMs" to generationTime,
        "tokenCount" to tokenCount
      )
    } catch (e: Exception) {
      throw Exception("Failed to generate text: ${e.message}")
    }
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    generativeModel = null
  }
}
