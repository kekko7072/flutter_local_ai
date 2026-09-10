import 'dart:typed_data';

import '../models/tool.dart';

/// Availability of the OS built-in model, as surfaced to app code.
///
/// Deliberately a hand-written mirror of the pigeon wire enum rather than a
/// re-export: the wire enum is regenerated from `pigeon.dart` and must stay
/// free to grow, while this one is public API. The two are kept aligned by
/// `availabilityFromWire` in the native host.
///
/// The web host maps Chrome's four `LanguageModel.availability()` states onto
/// this same set, so [unavailableOsTooOld] and [unavailableDisabled] never
/// occur there — Chrome folds both into [unavailableDeviceUnsupported] /
/// [unavailableOther].
enum LocalAiAvailability {
  /// Ready to use now.
  available,

  /// The feature exists but hasn't been downloaded — `LocalAi.ensureReady()`
  /// triggers it.
  downloadable,

  /// A download is already running; wait rather than starting another.
  downloading,

  /// No AICore (Android), no Apple Intelligence hardware, or no Prompt API
  /// (web). Fall back to a bundled model — this device can't run the built-in
  /// one.
  unavailableDeviceUnsupported,

  /// The OS is below the floor the built-in model requires.
  unavailableOsTooOld,

  /// Present but switched off by the user (Apple Intelligence in Settings, or
  /// the AICore toggle).
  unavailableDisabled,

  /// Unclassified failure. Check device logs; fall back to a bundled model.
  unavailableOther;

  /// Whether this state can still become [available] by waiting or
  /// downloading, as opposed to a terminal `unavailable*`.
  bool get isTransient =>
      this == LocalAiAvailability.downloadable ||
      this == LocalAiAvailability.downloading;
}

/// Thrown when the OS model can't be made ready. [status] is the terminal
/// availability that caused it.
class LocalAiUnavailableException implements Exception {
  LocalAiUnavailableException(this.status, this.message);

  final LocalAiAvailability status;
  final String message;

  @override
  String toString() => 'LocalAiUnavailableException($status): $message';
}

/// Thrown when the running host doesn't implement a capability the call needs
/// — vision on iOS 26, a JSON schema on Android, native tools on web. Callers
/// gate on [LocalAiBackendCapabilities] to avoid it; it names the capability
/// so the message stays actionable when they don't.
class LocalAiUnsupportedException implements Exception {
  LocalAiUnsupportedException(this.capability, this.message);

  /// e.g. `'vision'`, `'structuredOutput'`, `'toolCalling'`.
  final String capability;
  final String message;

  @override
  String toString() => 'LocalAiUnsupportedException($capability): $message';
}

/// Which OS API is answering.
enum LocalAiBackendKind {
  androidMlKitGenAi,
  appleFoundationModels,
  windowsAiFoundry,

  /// Windows AI Foundry is present but this build lacks the Windows AI SDK
  /// headers, so no inference can run.
  windowsAiFoundryUnconfigured,
  chromePromptApi,
  unsupported,
}

/// What the *running* host can do. Every field is a runtime property of this
/// device + OS + build: the same binary reports `supportsVision: false` on
/// iOS 26 and `true` on iOS 27.
class LocalAiBackendCapabilities {
  const LocalAiBackendCapabilities({
    required this.backend,
    required this.platform,
    required this.apiName,
    this.supportsToolCalling = false,
    this.supportsStructuredOutput = false,
    this.supportsVision = false,
    this.supportsTokenCount = false,
    this.supportsModelDownload = false,
    this.supportsPlayStoreRedirect = false,
    this.isConfigured = false,
  });

  final LocalAiBackendKind backend;
  final String platform;
  final String apiName;

  /// Native function calling. False where tool use has to be woven into the
  /// prompt instead.
  final bool supportsToolCalling;

  /// Generation constrained to a JSON schema.
  final bool supportsStructuredOutput;
  final bool supportsVision;

  /// A real tokenizer is reachable, so token counts are exact rather than a
  /// character estimate.
  final bool supportsTokenCount;
  final bool supportsModelDownload;
  final bool supportsPlayStoreRedirect;

  /// The backend is present AND this build can drive it.
  final bool isConfigured;

  static const unsupported = LocalAiBackendCapabilities(
    backend: LocalAiBackendKind.unsupported,
    platform: 'unknown',
    apiName: 'Unknown',
  );
}

/// An event from the host, tagged with the session it belongs to.
sealed class LocalAiHostEvent {
  const LocalAiHostEvent();
}

/// A slice of generated text. [partialResult] is a delta, not the running
/// total, and [done] marks the final event of a generation.
class LocalAiTokenEvent extends LocalAiHostEvent {
  const LocalAiTokenEvent({
    required this.sessionId,
    required this.partialResult,
    required this.done,
  });

  final int sessionId;
  final String partialResult;
  final bool done;
}

/// A generation failure, delivered as a tagged data event rather than a stream
/// error so it reaches only the session that caused it.
class LocalAiErrorEvent extends LocalAiHostEvent {
  const LocalAiErrorEvent({required this.sessionId, required this.message});

  final int sessionId;
  final String message;
}

/// Progress of the OS feature download. Not session-scoped.
class LocalAiDownloadProgressEvent extends LocalAiHostEvent {
  const LocalAiDownloadProgressEvent({
    required this.bytesDownloaded,
    required this.bytesTotal,
  });

  final int bytesDownloaded;
  final int bytesTotal;

  /// 0..100, or null when the host reports no total to divide by.
  int? get percent => bytesTotal > 0
      ? ((bytesDownloaded / bytesTotal) * 100).clamp(0, 100).round()
      : null;
}

/// The operations a platform host must provide. Implemented twice — over
/// pigeon on Android/iOS/macOS/Windows, and over Chrome's Prompt API on web —
/// so everything above this line is written once.
abstract class LocalAiHost {
  /// Host events for every session, plus download progress. Broadcast: each
  /// session filters by its own id.
  Stream<LocalAiHostEvent> get events;

  Future<LocalAiAvailability> checkAvailability();

  Future<String> availabilityReason();

  Future<LocalAiBackendCapabilities> getBackendInfo();

  Future<void> downloadFeature();

  Future<bool> openAICorePlayStore();

  Future<void> createModel({required bool supportImage});

  Future<void> closeModel();

  Future<void> createSession({
    required int sessionId,
    required double temperature,
    required int topK,
    double? topP,
    int? maxOutputTokens,
    String? systemInstruction,
    List<LocalAiTool>? tools,
  });

  Future<void> closeSession(int sessionId);

  Future<void> addQueryChunk({required int sessionId, required String text});

  Future<void> addImage({
    required int sessionId,
    required Uint8List imageBytes,
  });

  Future<String> generateResponse(int sessionId);

  Future<void> generateResponseAsync(int sessionId);

  Future<String> generateStructuredResponse({
    required int sessionId,
    required String schemaJson,
  });

  Future<void> stopGeneration(int sessionId);

  /// Exact count where the host has a tokenizer; throws
  /// [LocalAiTokenizerUnavailable] where it doesn't, so the caller decides
  /// whether to estimate.
  Future<int> countTokens(String text);
}

/// Thrown by [LocalAiHost.countTokens] when the host has no tokenizer to ask.
/// Distinct from a transport failure so `LocalAiSession.sizeInTokens` can fall
/// back to an estimate for this case only, and surface real wiring bugs.
class LocalAiTokenizerUnavailable implements Exception {
  LocalAiTokenizerUnavailable(this.message);

  final String message;

  @override
  String toString() => 'LocalAiTokenizerUnavailable: $message';
}
