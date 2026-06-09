import 'dart:async';

import 'package:flutter/services.dart';
import 'flutter_local_ai_platform_interface.dart';
import 'models/ai_response.dart';
import 'models/generation_config.dart';
import 'models/model_status.dart';
import 'models/platform_info.dart';
import 'models/tool.dart';

class MethodChannelFlutterLocalAi extends FlutterLocalAiPlatform {
  final MethodChannel methodChannel = const MethodChannel('flutter_local_ai');
  bool _toolHandlerRegistered = false;

  final Map<String, LocalAiTool> _registeredTools = {};

  final StreamController<ModelDownloadStatus> _downloadStatusController =
      StreamController.broadcast();

  void _registerToolHandlerIfNeeded() {
    if (_toolHandlerRegistered) return;
    methodChannel.setMethodCallHandler(_handlePlatformMethod);
    _toolHandlerRegistered = true;
  }

  Future<dynamic> _handlePlatformMethod(MethodCall call) async {
    if (call.method == 'onDownloadStatus') {
      final args = (call.arguments as Map?) ?? {};
      final status =
          ModelDownloadStatus.fromMap(Map<String, dynamic>.from(args));
      _downloadStatusController.add(status);
      return null;
    }

    if (call.method != 'onToolCall') {
      return null;
    }

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
    return tool.onCall(parsedArgs);
  }

  Map<String, dynamic> _normalizeArguments(Object? rawArgs) {
    if (rawArgs == null) {
      return {};
    }

    if (rawArgs is Map) {
      return rawArgs.map((key, value) => MapEntry(key.toString(), value));
    }

    return {};
  }

  @override
  Future<bool> isAvailable() async {
    try {
      final result = await methodChannel.invokeMethod<bool>('isAvailable');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> initialize({String? instructions}) async {
    try {
      final arguments = {
        if (instructions != null) 'instructions': instructions
      };
      final result =
          await methodChannel.invokeMethod<bool>('initialize', arguments);
      return result ?? false;
    } on PlatformException catch (exception) {
      throw Exception('Failed to initialize: ${exception.message}');
    }
  }

  @override
  Future<AiResponse> generateText({
    required String prompt,
    GenerationConfig? config,
  }) async {
    try {
      final arguments = {
        'prompt': prompt,
        if (config != null) 'config': config.toMap()
      };

      final result = await methodChannel.invokeMethod<Map<Object?, Object?>>(
        'generateText',
        arguments,
      );

      if (result == null) {
        throw Exception('Failed to generate text: null response');
      }

      return AiResponse.fromMap(Map<String, dynamic>.from(result));
    } on PlatformException catch (exception) {
      throw Exception('Failed to generate text: ${exception.message}');
    }
  }

  @override
  Future<bool> openAICorePlayStore() async {
    try {
      final result =
          await methodChannel.invokeMethod<bool>('openAICorePlayStore');
      return result ?? false;
    } on PlatformException catch (exception) {
      if (exception.code == 'unimplemented') {
        return false;
      }
      throw Exception('Failed to open Play Store: ${exception.message}');
    }
  }

  @override
  Future<void> registerTools(List<LocalAiTool> tools) async {
    _registerToolHandlerIfNeeded();

    _registeredTools
      ..clear()
      ..addEntries(tools.map((tool) => MapEntry(tool.name, tool)));

    await methodChannel.invokeMethod<bool>(
      'registerTools',
      tools.map((tool) => tool.toMap()).toList(),
    );
  }

  @override
  Future<LocalAiPlatformInfo> getPlatformInfo() async {
    try {
      final result = await methodChannel.invokeMethod<Map<Object?, Object?>>(
        'getPlatformInfo',
      );
      if (result == null) {
        return _unsupportedPlatformInfo;
      }
      return LocalAiPlatformInfo.fromMap(Map<String, dynamic>.from(result));
    } on PlatformException {
      return _unsupportedPlatformInfo;
    }
  }

  @override
  Future<ModelFeatureStatus> getModelStatus() async {
    try {
      final result = await methodChannel.invokeMethod<String>('getModelStatus');
      return modelFeatureStatusFromString(result);
    } on PlatformException catch (exception) {
      throw Exception('Failed to get model status: ${exception.message}');
    }
  }

  @override
  Stream<ModelDownloadStatus> downloadModel() {
    // Ensure the platform call handler is active so 'onDownloadStatus'
    // callbacks are delivered even if registerTools() was never called.
    _registerToolHandlerIfNeeded();
    methodChannel.invokeMethod<void>('downloadModel');
    return _downloadStatusController.stream;
  }

  static const LocalAiPlatformInfo _unsupportedPlatformInfo =
      LocalAiPlatformInfo(
    backend: LocalAiBackend.unsupported,
    platform: 'unknown',
    apiName: 'Unknown',
    supportsToolCalling: false,
    supportsModelDownload: false,
    supportsPlayStoreRedirect: false,
    isConfigured: false,
  );
}
