enum LocalAiBackend {
  androidMlKitGenAi,
  appleFoundationModels,
  windowsAiFoundry,
  windowsAiFoundryUnconfigured,
  unsupported,
}

LocalAiBackend localAiBackendFromString(String? value) {
  switch (value) {
    case 'android_mlkit_genai':
      return LocalAiBackend.androidMlKitGenAi;
    case 'apple_foundation_models':
      return LocalAiBackend.appleFoundationModels;
    case 'windows_ai_foundry':
      return LocalAiBackend.windowsAiFoundry;
    case 'windows_ai_foundry_unconfigured':
      return LocalAiBackend.windowsAiFoundryUnconfigured;
    default:
      return LocalAiBackend.unsupported;
  }
}

class LocalAiPlatformInfo {
  final LocalAiBackend backend;
  final String platform;
  final String apiName;
  final bool supportsToolCalling;
  final bool supportsModelDownload;
  final bool supportsPlayStoreRedirect;
  final bool isConfigured;

  const LocalAiPlatformInfo({
    required this.backend,
    required this.platform,
    required this.apiName,
    required this.supportsToolCalling,
    required this.supportsModelDownload,
    required this.supportsPlayStoreRedirect,
    required this.isConfigured,
  });

  factory LocalAiPlatformInfo.fromMap(Map<String, dynamic> map) {
    return LocalAiPlatformInfo(
      backend: localAiBackendFromString(map['backend']?.toString()),
      platform: map['platform']?.toString() ?? 'unknown',
      apiName: map['apiName']?.toString() ?? 'Unknown',
      supportsToolCalling: map['supportsToolCalling'] as bool? ?? false,
      supportsModelDownload: map['supportsModelDownload'] as bool? ?? false,
      supportsPlayStoreRedirect:
          map['supportsPlayStoreRedirect'] as bool? ?? false,
      isConfigured: map['isConfigured'] as bool? ?? false,
    );
  }
}
