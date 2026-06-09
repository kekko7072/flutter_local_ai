import 'package:flutter_local_ai/flutter_local_ai.dart';
import 'package:flutter_local_ai/src/flutter_local_ai_method_channel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FlutterLocalAiPlatform', () {
    group('.instance', () {
      test('defaults to method channel implementation', () {
        expect(FlutterLocalAiPlatform.instance,
            isA<MethodChannelFlutterLocalAi>());
      });

      test('rejects implementations without valid token', () {
        final originalInstance = FlutterLocalAiPlatform.instance;

        expect(
          () => FlutterLocalAiPlatform.instance =
              ImplementsFlutterLocalAiPlatform(),
          throwsA(isA<AssertionError>()),
        );

        FlutterLocalAiPlatform.instance = originalInstance;
      });
    });
  });
}

class ImplementsFlutterLocalAiPlatform implements FlutterLocalAiPlatform {
  @override
  Future<AiResponse> generateText(
      {required String prompt, GenerationConfig? config}) {
    throw UnimplementedError();
  }

  @override
  Future<bool> initialize({String? instructions}) {
    throw UnimplementedError();
  }

  @override
  Future<bool> isAvailable() {
    throw UnimplementedError();
  }

  @override
  Future<String> availabilityReason() {
    throw UnimplementedError();
  }

  @override
  Future<bool> openAICorePlayStore() {
    throw UnimplementedError();
  }

  @override
  Future<void> registerTools(List<LocalAiTool> tools) {
    throw UnimplementedError();
  }

  @override
  Future<LocalAiPlatformInfo> getPlatformInfo() {
    throw UnimplementedError();
  }

  @override
  Future<ModelFeatureStatus> getModelStatus() {
    throw UnimplementedError();
  }

  @override
  Stream<ModelDownloadStatus> downloadModel() {
    throw UnimplementedError();
  }
}
