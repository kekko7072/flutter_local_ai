import 'dart:async';
import 'package:flutter/services.dart';
import 'models/ai_response.dart';
import 'models/generation_config.dart';

/// Main class for interacting with local AI
class FlutterLocalAi {
  static const MethodChannel _channel = MethodChannel('flutter_local_ai');

  /// Check if local AI is available on the device
  Future<bool> isAvailable() async {
    try {
      final result = await _channel.invokeMethod<bool>('isAvailable');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Initialize the model and create a session with instruction text
  ///
  /// [instructions] - Optional instruction text for the session (default: "You are a helpful assistant. Provide concise answers.")
  ///
  /// Returns true if initialization was successful
  Future<bool> initialize({String? instructions}) async {
    try {
      final arguments = {
        if (instructions != null) 'instructions': instructions,
      };

      final result = await _channel.invokeMethod<bool>('initialize', arguments);
      return result ?? false;
    } on PlatformException catch (e) {
      throw Exception('Failed to initialize: ${e.message}');
    }
  }

  /// Generate text from a prompt
  ///
  /// [prompt] - The input text prompt
  /// [config] - Optional generation configuration
  ///
  /// Returns an [AiResponse] with the generated text
  Future<AiResponse> generateText({
    required String prompt,
    GenerationConfig? config,
  }) async {
    try {
      final arguments = {
        'prompt': prompt,
        if (config != null) 'config': config.toMap(),
      };

      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        'generateText',
        arguments,
      );

      if (result == null) {
        throw Exception('Failed to generate text: null response');
      }

      return AiResponse.fromMap(Map<String, dynamic>.from(result));
    } on PlatformException catch (e) {
      throw Exception('Failed to generate text: ${e.message}');
    }
  }

  /// Generate text with a simple prompt (convenience method)
  ///
  /// [prompt] - The input text prompt
  /// [maxTokens] - Maximum number of tokens to generate (default: 100)
  ///
  /// Returns the generated text as a String
  Future<String> generateTextSimple({
    required String prompt,
    int maxTokens = 100,
  }) async {
    final response = await generateText(
      prompt: prompt,
      config: GenerationConfig(maxTokens: maxTokens),
    );
    return response.text;
  }

  /// Open Google AICore in the Play Store (Android only)
  ///
  /// This is useful when the user gets an error that AICore is not installed
  /// or the version is too low (error code -101).
  ///
  /// Returns true if the Play Store was opened successfully
  Future<bool> openAICorePlayStore() async {
    try {
      final result = await _channel.invokeMethod<bool>('openAICorePlayStore');
      return result ?? false;
    } on PlatformException catch (e) {
      // If platform doesn't support this (e.g., iOS), fail silently
      if (e.code == 'unimplemented') {
        return false;
      }
      throw Exception('Failed to open Play Store: ${e.message}');
    }
  }
}
