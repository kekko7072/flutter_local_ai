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

  Future<bool> initialize({String? instructions});

  Future<AiResponse> generateText({
    required String prompt,
    GenerationConfig? config,
  });

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
