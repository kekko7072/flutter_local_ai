package io.vezz.flutter_local_ai

import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel

/**
 * Registration for flutter_local_ai on Android.
 *
 * All behaviour lives in [LocalAiSessionService]: one pigeon host API and one
 * event channel, driven from Dart by both the prompt-oriented `FlutterLocalAi`
 * facade and the session API. There is deliberately no second method channel —
 * a parallel implementation of the same generation logic is where the two
 * surfaces drift apart.
 */
class FlutterLocalAiPlugin : FlutterPlugin {
  private var sessionService: LocalAiSessionService? = null
  private var events: EventChannel? = null

  override fun onAttachedToEngine(
    @NonNull binding: FlutterPlugin.FlutterPluginBinding
  ) {
    val service = LocalAiSessionService(binding.applicationContext)
    sessionService = service
    LocalAiService.setUp(binding.binaryMessenger, service)
    events = EventChannel(binding.binaryMessenger, "flutter_local_ai_events")
      .apply { setStreamHandler(service) }
  }

  override fun onDetachedFromEngine(
    @NonNull binding: FlutterPlugin.FlutterPluginBinding
  ) {
    LocalAiService.setUp(binding.binaryMessenger, null)
    events?.setStreamHandler(null)
    events = null
    sessionService?.cleanup()
    sessionService = null
  }
}
