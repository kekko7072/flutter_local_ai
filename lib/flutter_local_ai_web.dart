import 'package:flutter_web_plugins/flutter_web_plugins.dart';

/// Web registration for flutter_local_ai.
///
/// There is nothing to wire up: the web arm talks to Chrome's Prompt API
/// (`self.LanguageModel`) directly through JS interop, with no platform
/// channel and no script to load. This class exists so the plugin can declare
/// `web` support in its pubspec — without it, Flutter reports the plugin as
/// unsupported on web and apps see a misleading build-time warning.
class FlutterLocalAiWeb {
  static void registerWith(Registrar registrar) {
    // Intentionally empty — see the class doc.
  }
}
