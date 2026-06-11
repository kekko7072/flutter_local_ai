import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'flutter_local_ai_method_channel.dart';
import 'models/ai_response.dart';
import 'models/generation_config.dart';
import 'models/model_status.dart';
import 'models/platform_info.dart';
import 'models/tool.dart';

abstract class FlutterLocalAiPlatform extends PlatformInterface {
  FlutterLocalAiPlatform() : super(token: _token);

  static final Object _token = Object();
  static FlutterLocalAiPlatform _instance = MethodChannelFlutterLocalAi();

  static FlutterLocalAiPlatform get instance => _instance;

  static set instance(FlutterLocalAiPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<bool> isAvailable();

  /// Human-readable reason for the current availability state.
  Future<String> availabilityReason() {
    throw UnimplementedError('availabilityReason() has not been implemented.');
  }

  Future<bool> initialize({String? instructions});

  /// [instructions] (when given) runs this call statelessly: a throwaway
  /// session with exactly these instructions, leaving no transcript behind
  /// and never touching the shared session created by [initialize].
  Future<AiResponse> generateText({
    required String prompt,
    GenerationConfig? config,
    String? instructions,
  });

  /// Generate text from a prompt, streaming the output as the model decodes.
  ///
  /// Emits delta chunks (only the newly generated text) and closes when the
  /// generation completes. Backends without a streaming implementation surface
  /// an error on the stream instead — callers can fall back to [generateText].
  /// [instructions] mirrors [generateText]'s stateless one-shot mode.
  Stream<String> generateTextStream({
    required String prompt,
    GenerationConfig? config,
    String? instructions,
  }) {
    throw UnimplementedError('generateTextStream() has not been implemented.');
  }

  Future<bool> openAICorePlayStore();

  Future<void> registerTools(List<LocalAiTool> tools);

  /// Returns platform-specific local AI backend information.
  Future<LocalAiPlatformInfo> getPlatformInfo() {
    throw UnimplementedError('getPlatformInfo() has not been implemented.');
  }

  /// Check the model status (Android only).
  Future<ModelFeatureStatus> getModelStatus() {
    throw UnimplementedError('getModelStatus() has not been implemented.');
  }

  /// Download the model if needed (Android only).
  ///
  /// Returns a stream of download status updates.
  Stream<ModelDownloadStatus> downloadModel() {
    throw UnimplementedError('downloadModel() has not been implemented.');
  }
}
