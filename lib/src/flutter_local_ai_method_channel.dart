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

  /// Live text-generation streams keyed by request id, so concurrent
  /// generations don't cross their chunks.
  final Map<int, StreamController<String>> _textStreams = {};
  int _nextTextStreamId = 0;

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

    if (call.method == 'onGenerateTextChunk' ||
        call.method == 'onGenerateTextDone' ||
        call.method == 'onGenerateTextError') {
      final args = (call.arguments as Map?) ?? {};
      final id = (args['id'] as num?)?.toInt();
      switch (call.method) {
        case 'onGenerateTextChunk':
          final text = args['text']?.toString() ?? '';
          if (text.isNotEmpty) _textStreams[id]?.add(text);
        case 'onGenerateTextDone':
          _textStreams.remove(id)?.close();
        case 'onGenerateTextError':
          final controller = _textStreams.remove(id);
          if (controller != null && !controller.isClosed) {
            controller
              ..addError(
                  Exception('Failed to generate text: ${args['message']}'))
              ..close();
          }
      }
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
  Future<String> availabilityReason() async {
    try {
      final result =
          await methodChannel.invokeMethod<String>('availabilityReason');
      return result ?? 'unknown';
    } on PlatformException catch (exception) {
      return 'unavailable: ${exception.message}';
    } catch (e) {
      return 'unavailable: $e';
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
    String? instructions,
  }) async {
    try {
      final arguments = {
        'prompt': prompt,
        if (config != null) 'config': config.toMap(),
        if (instructions != null) 'instructions': instructions,
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
  Stream<String> generateTextStream({
    required String prompt,
    GenerationConfig? config,
    String? instructions,
  }) {
    _registerToolHandlerIfNeeded();
    final id = _nextTextStreamId++;
    final controller = StreamController<String>();
    _textStreams[id] = controller;
    controller
      ..onListen = () {
        methodChannel.invokeMethod<void>('generateTextStream', {
          'id': id,
          'prompt': prompt,
          if (config != null) 'config': config.toMap(),
          if (instructions != null) 'instructions': instructions,
        }).catchError((Object error) {
          // The launch itself failed (no native streaming implementation, bad
          // arguments…) — surface it on the stream so callers can fall back.
          final live = _textStreams.remove(id);
          if (live != null && !live.isClosed) {
            live
              ..addError(Exception('Failed to generate text: $error'))
              ..close();
          }
        });
      }
      // A cancelled listener just stops caring — the native generation runs to
      // completion and its remaining callbacks land on a forgotten id.
      ..onCancel = () => _textStreams.remove(id);
    return controller.stream;
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
