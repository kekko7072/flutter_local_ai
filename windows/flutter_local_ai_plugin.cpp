// Define FLUTTER_PLUGIN_IMPL before including the header to ensure proper DLL export
#define FLUTTER_PLUGIN_IMPL
#include "flutter_local_ai/flutter_local_ai_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/base.h>

// Windows AI headers - Uncomment the line below when Windows AI SDK is available
// The Windows AI headers need to be generated using cppwinrt.exe or installed via NuGet package
// To generate headers: cppwinrt.exe -input "path/to/Microsoft.Windows.AI.winmd" -output "generated"
// Then add the generated headers path to CMakeLists.txt include directories
// 
// Uncomment this line when Windows AI headers are available:
// #include <winrt/Microsoft.Windows.AI.h>

// Define WINDOWS_AI_AVAILABLE based on whether headers are included
// Set to 1 if you've uncommented the include above, 0 otherwise
#ifndef WINDOWS_AI_AVAILABLE
  #define WINDOWS_AI_AVAILABLE 0
#endif
#include <memory>
#include <sstream>
#include <string>
#include <map>
#include <chrono>
#include <future>
#include <mutex>

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using winrt::Windows::Foundation::IAsyncOperation;

#if WINDOWS_AI_AVAILABLE
using winrt::Microsoft::Windows::AI::LanguageModel;
using winrt::Microsoft::Windows::AI::LanguageModelOptions;
using winrt::Microsoft::Windows::AI::LanguageModelSkill;
using winrt::Microsoft::Windows::AI::LanguageModelResult;
#endif

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
  void GetPlatformInfo(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void IsAvailable(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void Initialize(const flutter::EncodableMap& args, std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void GenerateText(const flutter::EncodableMap& args, std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // Helper methods
  bool CheckWindowsAIAvailability();
#if WINDOWS_AI_AVAILABLE
  winrt::Windows::Foundation::IAsyncAction InitializeLanguageModelAsync();
#endif

  // State
  std::string instructions_;
  bool is_initialized_;
#if WINDOWS_AI_AVAILABLE
  LanguageModel language_model_{ nullptr };
#endif
  std::mutex model_mutex_;
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
  } else if (method_call.method_name().compare("getPlatformInfo") == 0) {
    GetPlatformInfo(std::move(result));
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

void FlutterLocalAiPlugin::GetPlatformInfo(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  EncodableMap response;
  response[EncodableValue("platform")] = EncodableValue("windows");
  response[EncodableValue("supportsToolCalling")] = EncodableValue(false);
  response[EncodableValue("supportsModelDownload")] = EncodableValue(false);
  response[EncodableValue("supportsPlayStoreRedirect")] = EncodableValue(false);
#if WINDOWS_AI_AVAILABLE
  response[EncodableValue("backend")] = EncodableValue("windows_ai_foundry");
  response[EncodableValue("apiName")] = EncodableValue("Windows AI Foundry");
  response[EncodableValue("isConfigured")] = EncodableValue(true);
#else
  response[EncodableValue("backend")] = EncodableValue("windows_ai_foundry_unconfigured");
  response[EncodableValue("apiName")] = EncodableValue("Windows AI Foundry (SDK not configured)");
  response[EncodableValue("isConfigured")] = EncodableValue(false);
#endif
  result->Success(flutter::EncodableValue(response));
}

void FlutterLocalAiPlugin::IsAvailable(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  try {
    // Try to create a LanguageModel to check if Windows AI is available
    auto check_available = [this]() -> bool {
      try {
        // Try to create a LanguageModel synchronously (this will fail if not available)
        // We'll use a simpler check - try to access the API
        return CheckWindowsAIAvailability();
      } catch (...) {
        return false;
      }
    };
    
    bool available = check_available();
    result->Success(flutter::EncodableValue(available));
  } catch (const std::exception& e) {
    result->Error("UNAVAILABLE", std::string("Error checking availability: ") + e.what());
  } catch (...) {
    result->Error("UNAVAILABLE", "Windows AI is not available on this system.");
  }
}

void FlutterLocalAiPlugin::Initialize(
    const flutter::EncodableMap& args,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
#if WINDOWS_AI_AVAILABLE
  try {
    // Get instructions if provided
    auto instructions_it = args.find(EncodableValue("instructions"));
    if (instructions_it != args.end()) {
      const auto* instructions_ptr = std::get_if<std::string>(&instructions_it->second);
      if (instructions_ptr) {
        instructions_ = *instructions_ptr;
      }
    }
    
    // Create LanguageModel asynchronously
    InitializeLanguageModelAsync().get();
    
    std::lock_guard<std::mutex> lock(model_mutex_);
    if (language_model_ != nullptr) {
      is_initialized_ = true;
      result->Success(flutter::EncodableValue(true));
    } else {
      result->Error("INITIALIZATION_ERROR", "Failed to create LanguageModel. Windows AI may not be available on this system.");
    }
  } catch (const winrt::hresult_error& e) {
    std::string error_msg = "Error initializing Windows AI: ";
    error_msg += winrt::to_string(e.message());
    result->Error("INITIALIZATION_ERROR", error_msg);
  } catch (const std::exception& e) {
    result->Error("INITIALIZATION_ERROR", std::string("Error initializing: ") + e.what());
  } catch (...) {
    result->Error("INITIALIZATION_ERROR", "Unknown error during initialization.");
  }
#else
  result->Error("INITIALIZATION_ERROR", 
    "Windows AI headers are not available. "
    "Please install the Windows AI SDK or generate WinRT headers using cppwinrt.exe. "
    "See README for instructions.");
#endif
}

#if WINDOWS_AI_AVAILABLE
winrt::Windows::Foundation::IAsyncAction FlutterLocalAiPlugin::InitializeLanguageModelAsync() {
  try {
    // Create LanguageModel using CreateAsync
    language_model_ = co_await LanguageModel::CreateAsync();
  } catch (...) {
    language_model_ = nullptr;
    throw;
  }
}
#endif

void FlutterLocalAiPlugin::GenerateText(
    const flutter::EncodableMap& args,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
#if WINDOWS_AI_AVAILABLE
  try {
    std::lock_guard<std::mutex> lock(model_mutex_);
    
    if (!is_initialized_ || language_model_ == nullptr) {
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
    
    // Build full prompt with instructions if provided
    std::string fullPrompt = prompt;
    if (!instructions_.empty()) {
      fullPrompt = instructions_ + "\n\n" + prompt;
    }
    
    // Convert std::string to winrt::hstring
    winrt::hstring prompt_hstring = winrt::to_hstring(fullPrompt);
    
    // Create LanguageModelOptions
    LanguageModelOptions options;
    // Note: LanguageModelSkill enum values may vary - using a default skill
    // For general text generation, we might not need a specific skill
    // If the API requires it, we can set it based on the use case
    
    auto startTime = std::chrono::high_resolution_clock::now();
    
    // Generate response using Windows AI LanguageModel
    // Note: We need to call the async method and wait for it synchronously
    // This is acceptable for Flutter method channels which expect synchronous responses
    LanguageModelResult model_result = language_model_.GenerateResponseAsync(options, prompt_hstring).get();
    
    auto endTime = std::chrono::high_resolution_clock::now();
    auto generationTime = std::chrono::duration_cast<std::chrono::milliseconds>(endTime - startTime).count();
    
    // Extract the generated text from the result
    winrt::hstring generated_text = model_result.Text();
    std::string result_text = winrt::to_string(generated_text);
    
    // Estimate token count (rough approximation)
    // Windows AI API might provide this, but if not, we estimate
    int token_count = static_cast<int>(result_text.length() / 4); // Rough estimate
    
    EncodableMap response;
    response[EncodableValue("text")] = EncodableValue(result_text);
    response[EncodableValue("tokenCount")] = EncodableValue(token_count);
    response[EncodableValue("generationTimeMs")] = EncodableValue(static_cast<int>(generationTime));
    
    result->Success(flutter::EncodableValue(response));
    
  } catch (const winrt::hresult_error& e) {
    std::string error_msg = "Windows AI error: ";
    error_msg += winrt::to_string(e.message());
    result->Error("GENERATION_ERROR", error_msg);
  } catch (const std::exception& e) {
    result->Error("GENERATION_ERROR", std::string("Error generating text: ") + e.what());
  } catch (...) {
    result->Error("GENERATION_ERROR", "Unknown error during text generation.");
  }
#else
  result->Error("GENERATION_ERROR", 
    "Windows AI APIs are not available. "
    "Please install the Windows AI SDK or generate WinRT headers using cppwinrt.exe.");
#endif
}

bool FlutterLocalAiPlugin::CheckWindowsAIAvailability() {
#if WINDOWS_AI_AVAILABLE
  try {
    // First check OS version - Windows AI requires Windows 11 24H2 or later
    OSVERSIONINFOEXW osvi = {};
    osvi.dwOSVersionInfoSize = sizeof(osvi);
    
    if (GetVersionExW(reinterpret_cast<OSVERSIONINFO*>(&osvi))) {
      // Windows AI APIs are available on Windows 11 24H2 (build 26100) and later
      // Some features may be available on earlier builds, but 24H2 is the recommended minimum
      if (osvi.dwMajorVersion >= 10 && osvi.dwBuildNumber >= 26100) {
        // Try to create a LanguageModel to verify the API is actually available
        try {
          LanguageModel test_model = LanguageModel::CreateAsync().get();
          return test_model != nullptr;
        } catch (...) {
          // API might not be available even on supported OS versions
          return false;
        }
      }
    }
    
    return false;
  } catch (...) {
    return false;
  }
#else
  // Windows AI headers not available
  return false;
#endif
}

}  // namespace

void FlutterLocalAiPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  FlutterLocalAiPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
