import 'models/ai_response.dart';
import 'flutter_local_ai_platform_interface.dart';
import 'models/generation_config.dart';
import 'models/tool.dart';

/// Main class for interacting with local AI
class FlutterLocalAi {
  /// Check if local AI is available on the device
  Future<bool> isAvailable() => FlutterLocalAiPlatform.instance.isAvailable();

  /// Initialize the model and create a session with instruction text
  ///
  /// [instructions] - Optional instruction text for the session (default: "You are a helpful assistant. Provide concise answers.")
  ///
  /// Returns true if initialization was successful
  Future<bool> initialize({String? instructions}) =>
      FlutterLocalAiPlatform.instance.initialize(instructions: instructions);

  /// Generate text from a prompt
  ///
  /// [prompt] - The input text prompt
  /// [config] - Optional generation configuration
  ///
  /// Returns an [AiResponse] with the generated text
  Future<AiResponse> generateText({
    required String prompt,
    GenerationConfig? config,
  }) =>
      FlutterLocalAiPlatform.instance.generateText(
        prompt: prompt,
        config: config,
      );

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
  Future<bool> openAICorePlayStore() =>
      FlutterLocalAiPlatform.instance.openAICorePlayStore();

  /// Register Dart tools to be exposed to the native model (Darwin only).
  Future<void> registerTools(List<LocalAiTool> tools) =>
      FlutterLocalAiPlatform.instance.registerTools(tools);
}
