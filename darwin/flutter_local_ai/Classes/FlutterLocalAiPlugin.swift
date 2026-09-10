import Foundation

#if os(OSX)
  @preconcurrency import FlutterMacOS
#elseif os(iOS)
  @preconcurrency import Flutter
#endif

/// Registration for flutter_local_ai on iOS and macOS.
///
/// All behaviour lives in `LocalAiSessionService`: one pigeon host API and one
/// event channel, driven from Dart by both the prompt-oriented
/// `FlutterLocalAi` facade and the session API. There is deliberately no
/// second method channel — a parallel implementation of the same generation
/// logic is where the two surfaces drift apart.
@objc public class FlutterLocalAiPlugin: NSObject, FlutterPlugin {
  /// Retains the service for the lifetime of the process. Pigeon's `setUp`
  /// keeps only a weak reference to the handler, and `FlutterEventChannel`
  /// does not retain its stream handler either, so without this the service
  /// would deallocate as soon as `register` returned and every call would
  /// fail with a channel error.
  private static var sessionService: LocalAiSessionService?

  public static func register(with registrar: FlutterPluginRegistrar) {
    #if os(OSX)
      let messenger = registrar.messenger
    #elseif os(iOS)
      let messenger = registrar.messenger()
    #endif

    let service = LocalAiSessionService(
      toolRunner: LocalAiToolRunner(binaryMessenger: messenger))
    sessionService = service
    LocalAiServiceSetup.setUp(binaryMessenger: messenger, api: service)
    FlutterEventChannel(name: "flutter_local_ai_events", binaryMessenger: messenger)
      .setStreamHandler(service)
  }
}
