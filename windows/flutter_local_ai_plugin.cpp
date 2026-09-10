// Define FLUTTER_PLUGIN_IMPL before including the header to ensure proper DLL export
#define FLUTTER_PLUGIN_IMPL
#include "flutter_local_ai/flutter_local_ai_plugin.h"

#include <flutter/plugin_registrar_windows.h>

#include <memory>

#include "local_ai_session_service.h"

namespace {

// Registration for flutter_local_ai on Windows.
//
// All behaviour lives in LocalAiSessionService: one pigeon host API and one
// event channel, driven from Dart by both the prompt-oriented FlutterLocalAi
// facade and the session API. There is deliberately no second method channel —
// a parallel implementation of the same generation logic is where the two
// surfaces drift apart.
class FlutterLocalAiPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar) {
    auto plugin = std::make_unique<FlutterLocalAiPlugin>();
    // Owned by the plugin so it lives exactly as long as the engine
    // attachment: pigeon's SetUp keeps only a raw pointer.
    plugin->session_service_ =
        flutter_local_ai::LocalAiSessionService::Register(registrar->messenger());
    registrar->AddPlugin(std::move(plugin));
  }

  FlutterLocalAiPlugin() = default;
  ~FlutterLocalAiPlugin() override = default;

  FlutterLocalAiPlugin(const FlutterLocalAiPlugin&) = delete;
  FlutterLocalAiPlugin& operator=(const FlutterLocalAiPlugin&) = delete;

 private:
  std::unique_ptr<flutter_local_ai::LocalAiSessionService> session_service_;
};

}  // namespace

void FlutterLocalAiPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  FlutterLocalAiPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
