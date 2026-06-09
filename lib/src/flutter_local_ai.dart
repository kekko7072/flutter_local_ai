import 'dart:async';
import 'package:flutter/services.dart';
import 'models/ai_response.dart';
import 'models/generation_config.dart';
import 'models/model_status.dart';
import 'models/platform_info.dart';
import 'models/tool.dart';

/// Main class for interacting with local AI
class FlutterLocalAi {
  static const MethodChannel _channel = MethodChannel('flutter_local_ai');
  static bool _toolHandlerRegistered = false;
  static final Map<String, LocalAiTool> _registeredTools = {};
  static final StreamController<ModelDownloadStatus>
      _downloadStatusController = StreamController.broadcast();

  FlutterLocalAi() {
    _registerToolHandlerIfNeeded();
  }

  static void _registerToolHandlerIfNeeded() {
    if (_toolHandlerRegistered) return;
    _channel.setMethodCallHandler(_handlePlatformMethod);
    _toolHandlerRegistered = true;
  }

  static Future<dynamic> _handlePlatformMethod(MethodCall call) async {
    if (call.method == 'onToolCall') {
      final args = (call.arguments as Map?) ?? {};
      final toolName = args['toolName']?.toString();
      final rawArgs = args['arguments'];

      if (toolName == null) {
        throw PlatformException(
          code: 'INVALID_TOOL_REQUEST',
          message: 'Tool name was not provided by native layer.',
        );
      }

      final tool = _registeredTools[toolName];
      if (tool == null) {
        throw PlatformException(
          code: 'TOOL_NOT_FOUND',
          message: 'No Dart tool registered with name $toolName',
        );
      }

      final parsedArgs = _normalizeArguments(rawArgs);
      return await tool.onCall(parsedArgs);
    }

    if (call.method == 'onDownloadStatus') {
      final args = (call.arguments as Map?) ?? {};
      final status =
          ModelDownloadStatus.fromMap(Map<String, dynamic>.from(args));
      _downloadStatusController.add(status);
      return null;
    }

    return null;
  }

  static Map<String, dynamic> _normalizeArguments(Object? rawArgs) {
    if (rawArgs == null) {
      return {};
    }

    if (rawArgs is Map) {
      return rawArgs.map((key, value) => MapEntry(key.toString(), value));
    }

    return {};
  }

  /// Check if local AI is available on the device
  Future<bool> isAvailable() async {
    try {
      final result = await _channel.invokeMethod<bool>('isAvailable');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Returns platform-specific local AI backend information.
  Future<LocalAiPlatformInfo> getPlatformInfo() async {
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        'getPlatformInfo',
      );
      if (result == null) {
        return const LocalAiPlatformInfo(
          backend: LocalAiBackend.unsupported,
          platform: 'unknown',
          apiName: 'Unknown',
          supportsToolCalling: false,
          supportsModelDownload: false,
          supportsPlayStoreRedirect: false,
          isConfigured: false,
        );
      }
      return LocalAiPlatformInfo.fromMap(Map<String, dynamic>.from(result));
    } on PlatformException {
      return const LocalAiPlatformInfo(
        backend: LocalAiBackend.unsupported,
        platform: 'unknown',
        apiName: 'Unknown',
        supportsToolCalling: false,
        supportsModelDownload: false,
        supportsPlayStoreRedirect: false,
        isConfigured: false,
      );
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

  /// Register Dart tools to be exposed to the native model (Darwin only).
  Future<void> registerTools(List<LocalAiTool> tools) async {
    _registerToolHandlerIfNeeded();

    _registeredTools
      ..clear()
      ..addEntries(tools.map((tool) => MapEntry(tool.name, tool)));

    await _channel.invokeMethod<bool>(
      'registerTools',
      tools.map((tool) => tool.toMap()).toList(),
    );
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

  /// Check the model status (Android only).
  Future<ModelFeatureStatus> getModelStatus() async {
    try {
      final result = await _channel.invokeMethod<String>('getModelStatus');
      return modelFeatureStatusFromString(result);
    } on PlatformException catch (e) {
      throw Exception('Failed to get model status: ${e.message}');
    }
  }

  /// Download the model if needed (Android only).
  ///
  /// Returns a stream of download status updates.
  Stream<ModelDownloadStatus> downloadModel() {
    _channel.invokeMethod<void>('downloadModel');
    return _downloadStatusController.stream;
  }
}
