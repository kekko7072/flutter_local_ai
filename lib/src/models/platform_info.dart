import '../session/local_ai_host.dart';

/// Which OS API is answering.
enum LocalAiBackend {
  androidMlKitGenAi,
  appleFoundationModels,
  windowsAiFoundry,

  /// Windows AI Foundry is present but the build could not resolve the
  /// Windows App SDK projection, so no inference can run.
  windowsAiFoundryUnconfigured,

  /// Gemini Nano through the Chrome Prompt API.
  chromePromptApi,
  unsupported,
}

/// What the running backend supports, in the shape [FlutterLocalAi] reports
/// it.
///
/// A view over [LocalAiBackendCapabilities], which is the single source of
/// truth and carries more — vision and exact-token-count support have no
/// fields here. Reach for `LocalAi.capabilities()` when you need those; this
/// type stays for the prompt-oriented API and for genUI.
class LocalAiPlatformInfo {
  const LocalAiPlatformInfo({
    required this.backend,
    required this.platform,
    required this.apiName,
    required this.supportsToolCalling,
    required this.supportsModelDownload,
    required this.supportsPlayStoreRedirect,
    required this.isConfigured,
    this.supportsStructuredOutput = false,
  });

  /// Narrows [capabilities] to this view.
  factory LocalAiPlatformInfo.fromCapabilities(
    LocalAiBackendCapabilities capabilities,
  ) => LocalAiPlatformInfo(
    backend: switch (capabilities.backend) {
      LocalAiBackendKind.androidMlKitGenAi => LocalAiBackend.androidMlKitGenAi,
      LocalAiBackendKind.appleFoundationModels =>
        LocalAiBackend.appleFoundationModels,
      LocalAiBackendKind.windowsAiFoundry => LocalAiBackend.windowsAiFoundry,
      LocalAiBackendKind.windowsAiFoundryUnconfigured =>
        LocalAiBackend.windowsAiFoundryUnconfigured,
      LocalAiBackendKind.chromePromptApi => LocalAiBackend.chromePromptApi,
      LocalAiBackendKind.unsupported => LocalAiBackend.unsupported,
    },
    platform: capabilities.platform,
    apiName: capabilities.apiName,
    supportsToolCalling: capabilities.supportsToolCalling,
    supportsModelDownload: capabilities.supportsModelDownload,
    supportsPlayStoreRedirect: capabilities.supportsPlayStoreRedirect,
    isConfigured: capabilities.isConfigured,
    supportsStructuredOutput: capabilities.supportsStructuredOutput,
  );

  final LocalAiBackend backend;
  final String platform;
  final String apiName;

  /// Native function calling, not prompt emulation.
  final bool supportsToolCalling;
  final bool supportsModelDownload;
  final bool supportsPlayStoreRedirect;

  /// The backend is present AND this build can drive it.
  final bool isConfigured;

  /// Whether generation can be constrained to a `GenerationConfig.schema`.
  final bool supportsStructuredOutput;

  /// What a platform with no built-in model reports.
  static const unsupported = LocalAiPlatformInfo(
    backend: LocalAiBackend.unsupported,
    platform: 'unknown',
    apiName: 'Unknown',
    supportsToolCalling: false,
    supportsModelDownload: false,
    supportsPlayStoreRedirect: false,
    isConfigured: false,
  );
}
