// Wire contract between the flutter_local_ai Dart layer and its native hosts.
//
// Regenerate with:  dart run pigeon --input pigeon.dart
//
// The session half of this API (createModel/createSession/addQueryChunk/
// generateResponse[Async]/stopGeneration/countTokens/close*) is deliberately
// shape-compatible with flutter_gemma_builtin_ai's `BuiltInAiService`, so the
// `flutter_gemma_local_ai` bridge is a thin adapter and this package can stand
// in for that one under flutter_gemma. Everything past `countTokens` is a
// flutter_local_ai addition (backend introspection, native tool calling,
// schema-constrained output).
//
// Enum member order is FROZEN — append only. The native hosts and the Dart
// layer are generated from this file together, but a released app can hold a
// mixed pair across a hot restart, and reordering silently remaps values.
import 'package:pigeon/pigeon.dart';

/// Availability of the OS built-in model. Mirrors
/// `flutter_gemma_builtin_ai`'s `AvailabilityStatus` one-to-one so the bridge
/// can map it across without a lookup table.
enum AvailabilityStatus {
  available,
  downloadable,
  downloading,
  unavailableDeviceUnsupported,
  unavailableOsTooOld,

  /// The feature exists but the user turned it off — Apple Intelligence in
  /// Settings, or the AICore/Gemini Nano toggle on Android.
  unavailableDisabled,
  unavailableOther,
}

/// Which OS API is answering. `unsupported` is the honest answer on a platform
/// with no built-in model rather than a guess.
enum LocalAiBackend {
  androidMlKitGenAi,
  appleFoundationModels,
  windowsAiFoundry,

  /// Windows AI Foundry is present but the plugin was built without the
  /// Windows AI SDK headers, so no inference can run.
  windowsAiFoundryUnconfigured,
  chromePromptApi,
  unsupported,
}

/// What the *running* host can actually do. Every field is a runtime property
/// of this device + OS + build, never a compile-time assumption: the same
/// binary reports `supportsVision: false` on iOS 26 and `true` on iOS 27.
class LocalAiBackendInfo {
  LocalAiBackendInfo({
    required this.backend,
    required this.platform,
    required this.apiName,
    required this.supportsToolCalling,
    required this.supportsStructuredOutput,
    required this.supportsVision,
    required this.supportsTokenCount,
    required this.supportsModelDownload,
    required this.supportsPlayStoreRedirect,
    required this.isConfigured,
  });

  LocalAiBackend backend;
  String platform;
  String apiName;

  /// Native function calling (Apple `Tool`). False where tool use has to be
  /// woven into the prompt instead.
  bool supportsToolCalling;

  /// Generation constrained to a JSON schema (Apple `GenerationSchema`,
  /// Chrome's `responseConstraint`).
  bool supportsStructuredOutput;
  bool supportsVision;

  /// A real tokenizer is reachable, so `countTokens` is exact rather than a
  /// character heuristic.
  bool supportsTokenCount;
  bool supportsModelDownload;
  bool supportsPlayStoreRedirect;

  /// The backend is present AND this build can drive it.
  bool isConfigured;
}

enum ToolArgumentKind { string, integer, number, boolean }

class ToolParameterSpec {
  ToolParameterSpec({
    required this.name,
    required this.kind,
    required this.optional,
    this.description,
  });

  String name;
  ToolArgumentKind kind;
  bool optional;
  String? description;
}

class ToolSpec {
  ToolSpec({
    required this.name,
    required this.description,
    required this.parameters,
  });

  String name;
  String description;
  List<ToolParameterSpec> parameters;
}

@ConfigurePigeon(PigeonOptions(
  dartOut: 'lib/src/pigeon/local_ai_api.g.dart',
  dartPackageName: 'flutter_local_ai',
  kotlinOut:
      'android/src/main/kotlin/io/vezz/flutter_local_ai/LocalAiPigeon.g.kt',
  kotlinOptions: KotlinOptions(package: 'io.vezz.flutter_local_ai'),
  swiftOut: 'darwin/flutter_local_ai/Classes/LocalAiPigeon.g.swift',
  swiftOptions: SwiftOptions(),
  cppHeaderOut: 'windows/local_ai_pigeon.g.h',
  cppSourceOut: 'windows/local_ai_pigeon.g.cpp',
  cppOptions: CppOptions(namespace: 'flutter_local_ai_pigeon'),
))
@HostApi()
abstract class LocalAiService {
  // --- Availability -------------------------------------------------------

  @async
  AvailabilityStatus checkAvailability();

  /// One human-readable sentence naming what the user would have to change —
  /// enable Apple Intelligence, update the OS, use an eligible device. Shown
  /// in UI, so it is prose, not a status code.
  @async
  String availabilityReason();

  @async
  LocalAiBackendInfo getBackendInfo();

  /// Starts the OS feature download (AICore). Progress arrives on the event
  /// channel as `{code: DOWNLOAD_PROGRESS, bytesDownloaded, bytesTotal}`.
  /// No-op on darwin, where readiness is user-controlled in Settings.
  @async
  void downloadFeature();

  /// Opens Google AICore in the Play Store. False on every non-Android host.
  @async
  bool openAICorePlayStore();

  // --- Model lifecycle ----------------------------------------------------

  @async
  void createModel({required bool supportImage});

  @async
  void closeModel();

  // --- Sessions -----------------------------------------------------------

  /// Sessions are keyed by a caller-allocated [sessionId]; every generated
  /// token on the event channel carries it back so concurrent sessions can be
  /// demultiplexed.
  ///
  /// [tools] must be supplied here rather than per-request: Apple binds tools
  /// at `LanguageModelSession` construction and cannot add them to a live
  /// session.
  @async
  void createSession({
    required int sessionId,
    required double temperature,
    required int topK,
    double? topP,
    int? maxOutputTokens,
    String? systemInstruction,
    List<ToolSpec>? tools,
  });

  @async
  void closeSession(int sessionId);

  @async
  void addQueryChunk({required int sessionId, required String text});

  @async
  void addImage({required int sessionId, required Uint8List imageBytes});

  // --- Generation ---------------------------------------------------------

  @async
  String generateResponse(int sessionId);

  /// Streams the response; tokens arrive on the event channel as
  /// `{sessionId, partialResult, done}` and failures as
  /// `{sessionId, code: ERROR, message}`.
  @async
  void generateResponseAsync(int sessionId);

  /// Generation constrained to [schemaJson] (a JSON Schema document). Hosts
  /// reporting `supportsStructuredOutput: false` fail this call rather than
  /// silently returning prose.
  @async
  String generateStructuredResponse({
    required int sessionId,
    required String schemaJson,
  });

  @async
  void stopGeneration(int sessionId);

  /// Exact token count where the host has a tokenizer. Hosts reporting
  /// `supportsTokenCount: false` fail with `TOKENIZER_UNAVAILABLE`, which the
  /// Dart layer turns into a documented character-based estimate.
  @async
  int countTokens(String text);
}

/// Host → Dart callback for native tool calling. The host suspends generation,
/// asks Dart to run the tool, and feeds the result back to the model.
@FlutterApi()
abstract class LocalAiToolRunner {
  /// [argumentsJson] is a JSON object of the arguments the model produced.
  /// Returns the tool's result encoded as JSON, or null when the tool yields
  /// nothing.
  @async
  String? onToolCall(int sessionId, String toolName, String argumentsJson);
}
