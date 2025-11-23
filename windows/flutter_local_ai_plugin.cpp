#include "flutter_local_ai_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <winrt/Windows.Foundation.h>
#include <memory>
#include <sstream>
#include <string>
#include <map>
#include <chrono>

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using winrt::Windows::Foundation::IAsyncOperation;

class FlutterLocalAiPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  FlutterLocalAiPlugin();

  virtual ~FlutterLocalAiPlugin();

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // Method handlers
  void IsAvailable(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void Initialize(const flutter::EncodableMap& args, std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void GenerateText(const flutter::EncodableMap& args, std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // Helper methods
  bool CheckWindowsAIAvailability();

  // State
  std::string instructions_;
  bool is_initialized_;
};

// static
void FlutterLocalAiPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "flutter_local_ai",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<FlutterLocalAiPlugin>();

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

FlutterLocalAiPlugin::FlutterLocalAiPlugin() 
    : instructions_("You are a helpful assistant. Provide concise answers."),
      is_initialized_(false) {
}

FlutterLocalAiPlugin::~FlutterLocalAiPlugin() {}

void FlutterLocalAiPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name().compare("isAvailable") == 0) {
    IsAvailable(std::move(result));
  } else if (method_call.method_name().compare("initialize") == 0) {
    const auto* args = std::get_if<EncodableMap>(method_call.arguments());
    if (args) {
      Initialize(*args, std::move(result));
    } else {
      result->Error("INVALID_ARGUMENT", "Arguments are required");
    }
  } else if (method_call.method_name().compare("generateText") == 0) {
    const auto* args = std::get_if<EncodableMap>(method_call.arguments());
    if (args) {
      GenerateText(*args, std::move(result));
    } else {
      result->Error("INVALID_ARGUMENT", "Arguments are required");
    }
  } else if (method_call.method_name().compare("openAICorePlayStore") == 0) {
    // Not applicable on Windows
    result->Success(false);
  } else {
    result->NotImplemented();
  }
}

void FlutterLocalAiPlugin::IsAvailable(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  try {
    bool available = CheckWindowsAIAvailability();
    result->Success(flutter::EncodableValue(available));
  } catch (const std::exception& e) {
    result->Error("UNAVAILABLE", std::string("Error checking availability: ") + e.what());
  }
}

void FlutterLocalAiPlugin::Initialize(
    const flutter::EncodableMap& args,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  try {
    // Get instructions if provided
    auto instructions_it = args.find(EncodableValue("instructions"));
    if (instructions_it != args.end()) {
      const auto* instructions_ptr = std::get_if<std::string>(&instructions_it->second);
      if (instructions_ptr) {
        instructions_ = *instructions_ptr;
      }
    }
    
    // Note: Windows AI APIs for text generation may require different initialization
    // This is a placeholder implementation that checks availability
    // Actual implementation would depend on the specific Windows AI API being used
    
    if (CheckWindowsAIAvailability()) {
      is_initialized_ = true;
      result->Success(flutter::EncodableValue(true));
    } else {
      result->Error("INITIALIZATION_ERROR", "Windows AI is not available on this system. Requires Windows 11 22H2 (build 22621) or later.");
    }
  } catch (const std::exception& e) {
    result->Error("INITIALIZATION_ERROR", std::string("Error initializing: ") + e.what());
  }
}

void FlutterLocalAiPlugin::GenerateText(
    const flutter::EncodableMap& args,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  try {
    if (!is_initialized_) {
      result->Error("NOT_INITIALIZED", "AI engine not initialized. Call initialize() first.");
      return;
    }
    
    // Get prompt
    auto prompt_it = args.find(EncodableValue("prompt"));
    if (prompt_it == args.end()) {
      result->Error("INVALID_ARGUMENT", "Prompt is required");
      return;
    }
    const auto* prompt_ptr = std::get_if<std::string>(&prompt_it->second);
    if (!prompt_ptr) {
      result->Error("INVALID_ARGUMENT", "Prompt must be a string");
      return;
    }
    std::string prompt = *prompt_ptr;
    
    // Get config
    int maxTokens = 100;
    double temperature = 0.7;
    
    auto config_it = args.find(EncodableValue("config"));
    if (config_it != args.end()) {
      const auto* config_ptr = std::get_if<EncodableMap>(&config_it->second);
      if (config_ptr) {
        auto max_tokens_it = config_ptr->find(EncodableValue("maxTokens"));
        if (max_tokens_it != config_ptr->end()) {
          const auto* max_tokens_ptr = std::get_if<int>(&max_tokens_it->second);
          if (max_tokens_ptr) {
            maxTokens = *max_tokens_ptr;
          }
        }
        
        auto temp_it = config_ptr->find(EncodableValue("temperature"));
        if (temp_it != config_ptr->end()) {
          const auto* temp_ptr = std::get_if<double>(&temp_it->second);
          if (temp_ptr) {
            temperature = *temp_ptr;
          }
        }
      }
    }
    
    // Build full prompt with instructions
    std::string fullPrompt = instructions_ + "\n\n" + prompt;
    
    // Note: This is a placeholder implementation
    // Windows AI APIs for text generation would need to be implemented here
    // The actual API depends on which Windows AI service is being used
    // Windows AI Foundry / Windows Copilot Runtime APIs would be called here
    
    // For now, return a placeholder response indicating Windows AI is not fully implemented
    // In a real implementation, this would call the Windows AI API (e.g., Windows Copilot Runtime)
    
    auto startTime = std::chrono::high_resolution_clock::now();
    
    // TODO: Implement actual Windows AI API call here
    // This would use Windows Copilot Runtime or Windows AI Foundry APIs
    // Example (pseudo-code):
    // auto aiService = Windows::AI::TextGeneration::GetDefault();
    // auto result = await aiService.GenerateTextAsync(fullPrompt, maxTokens, temperature);
    
    auto endTime = std::chrono::high_resolution_clock::now();
    auto generationTime = std::chrono::duration_cast<std::chrono::milliseconds>(endTime - startTime).count();
    
    EncodableMap response;
    response[EncodableValue("text")] = EncodableValue(
        "Windows AI API integration is in progress. "
        "Windows AI Foundry APIs for text generation are being integrated. "
        "Please check the Windows AI documentation for the latest APIs.");
    response[EncodableValue("tokenCount")] = EncodableValue(0);
    response[EncodableValue("generationTimeMs")] = EncodableValue(static_cast<int>(generationTime));
    
    result->Success(flutter::EncodableValue(response));
    
  } catch (const std::exception& e) {
    result->Error("GENERATION_ERROR", std::string("Error generating text: ") + e.what());
  }
}

bool FlutterLocalAiPlugin::CheckWindowsAIAvailability() {
  try {
    // Check if Windows AI APIs are available
    // This is a basic check - actual implementation would depend on the specific API
    
    // For Windows 11 22H2 and later, Windows AI APIs should be available
    // We can check the OS version or try to load the Windows AI libraries
    
    OSVERSIONINFOEXW osvi = {};
    osvi.dwOSVersionInfoSize = sizeof(osvi);
    
    if (GetVersionExW(reinterpret_cast<OSVERSIONINFO*>(&osvi))) {
      // Windows 11 is version 10.0 with build 22000 or higher
      // Windows AI APIs are available on Windows 11 22H2 (build 22621) and later
      if (osvi.dwMajorVersion >= 10 && osvi.dwBuildNumber >= 22621) {
        return true;
      }
    }
    
    return false;
  } catch (...) {
    return false;
  }
}

}  // namespace

void FlutterLocalAiPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  FlutterLocalAiPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
