import 'dart:async';

import 'local_ai_host.dart';
import 'local_ai_runtime.dart';

/// Probing and preparing the OS built-in model.
///
/// Availability is a runtime property of the device, OS and browser — never
/// something a build can guarantee — so call [availability] or [ensureReady]
/// before creating a model, on every platform.
abstract final class LocalAi {
  /// Bounds the availability probe. On a device whose OS AI stack has never
  /// initialized (a freshly provisioned or CI device where AICore has no
  /// Phenotype metadata yet), the native status call can block instead of
  /// returning, which would hang every caller that gates on it.
  ///
  /// Overridable for tests only.
  static Duration debugProbeTimeout = const Duration(seconds: 20);

  /// Current availability of the OS built-in model.
  ///
  /// Never throws and never hangs: a probe that doesn't return within
  /// [debugProbeTimeout] resolves to
  /// [LocalAiAvailability.unavailableOther] so callers can degrade.
  static Future<LocalAiAvailability> availability({LocalAiHost? host}) async {
    try {
      return await (host ?? localAiHost)
          .checkAvailability()
          .timeout(debugProbeTimeout);
    } on TimeoutException {
      return LocalAiAvailability.unavailableOther;
    } catch (_) {
      return LocalAiAvailability.unavailableOther;
    }
  }

  /// One human-readable sentence naming what the user would have to change.
  static Future<String> availabilityReason({LocalAiHost? host}) =>
      (host ?? localAiHost).availabilityReason();

  /// What the running host can actually do — vision, tools, schemas, exact
  /// token counts. Gate optional features on this rather than on
  /// `Platform.isX`: the same binary answers differently across OS versions.
  static Future<LocalAiBackendCapabilities> capabilities({
    LocalAiHost? host,
  }) =>
      (host ?? localAiHost).getBackendInfo();

  /// Ensures the OS model is ready, downloading it when the OS exposes it as
  /// [LocalAiAvailability.downloadable].
  ///
  /// - [LocalAiAvailability.available] returns immediately.
  /// - Any `unavailable*` throws [LocalAiUnavailableException] without
  ///   attempting a download — those states can't be fixed by waiting.
  /// - [LocalAiAvailability.downloadable] kicks off the download;
  ///   [LocalAiAvailability.downloading] joins the one already running.
  ///
  /// [onProgress] receives 0..100. [timeout] bounds the whole wait.
  static Future<void> ensureReady({
    void Function(int percent)? onProgress,
    Duration timeout = const Duration(minutes: 10),
    LocalAiHost? host,
  }) async {
    final resolved = host ?? localAiHost;
    final initial = await availability(host: resolved);
    switch (initial) {
      case LocalAiAvailability.available:
        return;
      case LocalAiAvailability.unavailableDeviceUnsupported:
      case LocalAiAvailability.unavailableOsTooOld:
      case LocalAiAvailability.unavailableDisabled:
      case LocalAiAvailability.unavailableOther:
        throw LocalAiUnavailableException(
          initial,
          'Built-in AI is not available: $initial',
        );
      case LocalAiAvailability.downloadable:
      case LocalAiAvailability.downloading:
        await _download(
          host: resolved,
          kickOff: initial == LocalAiAvailability.downloadable,
          onProgress: onProgress,
          timeout: timeout,
        );
    }
  }

  static Future<void> _download({
    required LocalAiHost host,
    required bool kickOff,
    required void Function(int percent)? onProgress,
    required Duration timeout,
  }) async {
    final ready = Completer<void>();
    StreamSubscription<LocalAiHostEvent>? progressSub;
    // Set in the `finally` below so the detached poll loop stops once we have
    // given up, instead of spinning for the life of the isolate.
    var settled = false;

    if (onProgress != null) {
      progressSub = host.events.listen(
        (event) {
          if (event is LocalAiDownloadProgressEvent) {
            final percent = event.percent;
            if (percent != null) onProgress(percent);
          }
        },
        onError: (Object _) {
          // Progress is advisory; the poll loop below owns the outcome.
        },
      );
    }

    Future<void> poll() async {
      try {
        while (!settled && !ready.isCompleted) {
          switch (await availability(host: host)) {
            case LocalAiAvailability.available:
              if (!ready.isCompleted) ready.complete();
              return;
            case LocalAiAvailability.downloadable:
            case LocalAiAvailability.downloading:
              await Future<void>.delayed(const Duration(milliseconds: 200));
            case LocalAiAvailability.unavailableDeviceUnsupported:
            case LocalAiAvailability.unavailableOsTooOld:
            case LocalAiAvailability.unavailableDisabled:
            case LocalAiAvailability.unavailableOther:
              if (!ready.isCompleted) {
                ready.completeError(
                  LocalAiUnavailableException(
                    LocalAiAvailability.unavailableOther,
                    'Built-in AI became unavailable during download.',
                  ),
                );
              }
              return;
          }
        }
      } catch (e, stackTrace) {
        if (!ready.isCompleted) ready.completeError(e, stackTrace);
      }
    }

    try {
      if (kickOff) {
        // Fire-and-forget on purpose. The OS routes the AICore feature
        // download through a system-managed queue that can sit silent for
        // minutes — or, on a CI device, never get a scheduler slot — and ML
        // Kit's download() gives no terminal-emission guarantee, so awaiting
        // it can hang. Availability polling is the readiness signal; a silent
        // failure surfaces there or via [timeout].
        unawaited(
          host.downloadFeature().catchError((Object _) {
            // Swallowed here so a kick-off failure can't escape a detached
            // future; poll() observes the real outcome.
          }),
        );
      }
      unawaited(poll());
      await ready.future.timeout(
        timeout,
        onTimeout: () => throw TimeoutException(
          'Built-in AI feature download did not complete in $timeout',
          timeout,
        ),
      );
    } finally {
      settled = true;
      await progressSub?.cancel();
    }
  }

  /// Opens Google AICore in the Play Store, for the Android case where AICore
  /// is missing or too old. False on every other platform.
  static Future<bool> openAICorePlayStore({LocalAiHost? host}) =>
      (host ?? localAiHost).openAICorePlayStore();
}
