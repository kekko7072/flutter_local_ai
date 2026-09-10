#include "local_ai_session_service.h"

#include <flutter/event_stream_handler_functions.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <utility>

#ifndef WINDOWS_AI_AVAILABLE
#define WINDOWS_AI_AVAILABLE 0
#endif

#if WINDOWS_AI_AVAILABLE
#include <winrt/Microsoft.Windows.AI.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/base.h>
#endif

namespace flutter_local_ai {

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter_local_ai_pigeon::AvailabilityStatus;
using flutter_local_ai_pigeon::ErrorOr;
using flutter_local_ai_pigeon::FlutterError;
using flutter_local_ai_pigeon::LocalAiBackend;
using flutter_local_ai_pigeon::LocalAiBackendInfo;

constexpr char kEventChannel[] = "flutter_local_ai_events";

FlutterError SessionMissing(int64_t session_id) {
  return FlutterError(
      "SESSION_NOT_FOUND",
      "No session with id " + std::to_string(session_id) +
          ". It was closed, or never created.");
}

#if !WINDOWS_AI_AVAILABLE
FlutterError NotConfigured() {
  return FlutterError(
      "WINDOWS_AI_NOT_CONFIGURED",
      "This build has no Windows AI SDK headers, so no inference can run. "
      "Generate the WinRT headers with cppwinrt.exe (or install the Windows "
      "AI SDK NuGet package) and rebuild with WINDOWS_AI_AVAILABLE=1.");
}
#endif

}  // namespace

LocalAiSessionService::LocalAiSessionService() = default;

LocalAiSessionService::~LocalAiSessionService() = default;

std::unique_ptr<LocalAiSessionService> LocalAiSessionService::Register(
    flutter::BinaryMessenger* messenger) {
  auto service = std::make_unique<LocalAiSessionService>();
  flutter_local_ai_pigeon::LocalAiService::SetUp(messenger, service.get());

  service->event_channel_ =
      std::make_unique<flutter::EventChannel<EncodableValue>>(
          messenger, kEventChannel,
          &flutter::StandardMethodCodec::GetInstance());

  auto* raw = service.get();
  service->event_channel_->SetStreamHandler(
      std::make_unique<flutter::StreamHandlerFunctions<EncodableValue>>(
          [raw](const EncodableValue*,
                std::unique_ptr<flutter::EventSink<EncodableValue>>&& events)
              -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
            raw->event_sink_ = std::move(events);
            return nullptr;
          },
          [raw](const EncodableValue*)
              -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
            raw->event_sink_.reset();
            return nullptr;
          }));
  return service;
}

LocalAiSessionService::SessionState* LocalAiSessionService::Find(
    int64_t session_id) {
  auto it = sessions_.find(session_id);
  return it == sessions_.end() ? nullptr : &it->second;
}

void LocalAiSessionService::PostEvent(const EncodableMap& payload) {
  // Always called from the platform thread — see the class comment.
  if (event_sink_) {
    event_sink_->Success(EncodableValue(payload));
  }
}

void LocalAiSessionService::PostDone(int64_t session_id) {
  PostEvent(EncodableMap{
      {EncodableValue("partialResult"), EncodableValue("")},
      {EncodableValue("done"), EncodableValue(true)},
      {EncodableValue("sessionId"), EncodableValue(session_id)},
  });
}

// === Availability ===

void LocalAiSessionService::CheckAvailability(
    std::function<void(ErrorOr<AvailabilityStatus> reply)> result) {
#if WINDOWS_AI_AVAILABLE
  try {
    // Windows AI needs Windows 11 24H2 (build 26100) or newer.
    OSVERSIONINFOEXW osvi = {};
    osvi.dwOSVersionInfoSize = sizeof(osvi);
    if (!GetVersionExW(reinterpret_cast<OSVERSIONINFO*>(&osvi)) ||
        osvi.dwMajorVersion < 10 || osvi.dwBuildNumber < 26100) {
      result(AvailabilityStatus::kUnavailableOsTooOld);
      return;
    }
    auto model =
        winrt::Microsoft::Windows::AI::LanguageModel::CreateAsync().get();
    result(model != nullptr ? AvailabilityStatus::kAvailable
                            : AvailabilityStatus::kUnavailableDeviceUnsupported);
  } catch (...) {
    // The probe's contract is to resolve, never throw.
    result(AvailabilityStatus::kUnavailableOther);
  }
#else
  result(AvailabilityStatus::kUnavailableDeviceUnsupported);
#endif
}

void LocalAiSessionService::AvailabilityReason(
    std::function<void(ErrorOr<std::string> reply)> result) {
#if WINDOWS_AI_AVAILABLE
  OSVERSIONINFOEXW osvi = {};
  osvi.dwOSVersionInfoSize = sizeof(osvi);
  if (GetVersionExW(reinterpret_cast<OSVERSIONINFO*>(&osvi)) &&
      (osvi.dwMajorVersion < 10 || osvi.dwBuildNumber < 26100)) {
    result(std::string(
        "Windows AI needs Windows 11 24H2 (build 26100) or newer. Update "
        "Windows, or fall back to a downloaded model."));
    return;
  }
  try {
    auto model =
        winrt::Microsoft::Windows::AI::LanguageModel::CreateAsync().get();
    if (model != nullptr) {
      result(std::string("Windows AI Foundry is ready."));
      return;
    }
  } catch (...) {
    // Fall through to the generic message below.
  }
  result(std::string(
      "Windows AI Foundry could not start a language model on this PC. It "
      "needs a Copilot+ device with an NPU."));
#else
  result(std::string(
      "This build has no Windows AI SDK headers, so the OS model cannot be "
      "reached. See the README for generating the WinRT headers."));
#endif
}

void LocalAiSessionService::GetBackendInfo(
    std::function<void(ErrorOr<LocalAiBackendInfo> reply)> result) {
#if WINDOWS_AI_AVAILABLE
  LocalAiBackendInfo info(
      LocalAiBackend::kWindowsAiFoundry, "windows", "Windows AI Foundry",
      /*supports_tool_calling=*/false,
      // Windows AI generation is text-out; it cannot constrain to a schema.
      /*supports_structured_output=*/false,
      /*supports_vision=*/false,
      /*supports_token_count=*/false,
      // Windows AI ships as a system component; there is nothing for an app
      // to download.
      /*supports_model_download=*/false,
      /*supports_play_store_redirect=*/false,
      /*is_configured=*/true);
#else
  LocalAiBackendInfo info(
      LocalAiBackend::kWindowsAiFoundryUnconfigured, "windows",
      "Windows AI Foundry (SDK not configured)",
      /*supports_tool_calling=*/false,
      /*supports_structured_output=*/false,
      /*supports_vision=*/false,
      /*supports_token_count=*/false,
      /*supports_model_download=*/false,
      /*supports_play_store_redirect=*/false,
      /*is_configured=*/false);
#endif
  result(info);
}

void LocalAiSessionService::DownloadFeature(
    std::function<void(std::optional<FlutterError> reply)> result) {
  // Nothing to download: Windows AI is a system component. Returning success
  // sends Dart's ensureReady straight to polling availability.
  result(std::nullopt);
}

void LocalAiSessionService::OpenAICorePlayStore(
    std::function<void(ErrorOr<bool> reply)> result) {
  result(false);
}

// === Model lifecycle ===

void LocalAiSessionService::CreateModel(
    bool support_image,
    std::function<void(std::optional<FlutterError> reply)> result) {
  if (support_image) {
    result(FlutterError(
        "VISION_UNSUPPORTED",
        "Windows AI Foundry has no image input in this plugin. Check "
        "LocalAi.capabilities().supportsVision before enabling it."));
    return;
  }
#if WINDOWS_AI_AVAILABLE
  result(std::nullopt);
#else
  result(NotConfigured());
#endif
}

void LocalAiSessionService::CloseModel(
    std::function<void(std::optional<FlutterError> reply)> result) {
  sessions_.clear();
  result(std::nullopt);
}

// === Sessions ===

void LocalAiSessionService::CreateSession(
    int64_t session_id,
    double temperature,
    int64_t top_k,
    const double* top_p,
    const int64_t* max_output_tokens,
    const std::string* system_instruction,
    const EncodableList* tools,
    std::function<void(std::optional<FlutterError> reply)> result) {
  if (tools != nullptr && !tools->empty()) {
    result(FlutterError(
        "TOOL_CALLING_UNSUPPORTED",
        "Windows AI Foundry exposes no function-calling API. Check "
        "LocalAi.capabilities().supportsToolCalling before passing tools."));
    return;
  }

  SessionState state;
  state.temperature = temperature;
  state.max_output_tokens =
      max_output_tokens != nullptr ? *max_output_tokens : 0;
  if (system_instruction != nullptr && !system_instruction->empty()) {
    state.transcript = *system_instruction + "\n\n";
  }
  // top_k and top_p have no Windows AI counterpart. They are accepted for
  // cross-platform parity and deliberately not applied, rather than mapped
  // onto something that means something else.
  (void)top_k;
  (void)top_p;

  sessions_[session_id] = std::move(state);
  result(std::nullopt);
}

void LocalAiSessionService::CloseSession(
    int64_t session_id,
    std::function<void(std::optional<FlutterError> reply)> result) {
  const bool existed = sessions_.erase(session_id) > 0;
  // Closing mid-stream must terminate that stream, or a Dart consumer hangs.
  if (existed) PostDone(session_id);
  result(std::nullopt);
}

void LocalAiSessionService::AddQueryChunk(
    int64_t session_id,
    const std::string& text,
    std::function<void(std::optional<FlutterError> reply)> result) {
  SessionState* state = Find(session_id);
  if (state == nullptr) {
    result(SessionMissing(session_id));
    return;
  }
  state->transcript += text;
  result(std::nullopt);
}

void LocalAiSessionService::AddImage(
    int64_t session_id,
    const std::vector<uint8_t>& image_bytes,
    std::function<void(std::optional<FlutterError> reply)> result) {
  result(FlutterError(
      "VISION_UNSUPPORTED",
      "Windows AI Foundry has no image input in this plugin."));
}

// === Generation ===

bool LocalAiSessionService::Generate(
    SessionState* state,
    const flutter_local_ai_pigeon::GenerationOverrides* overrides,
    std::string* out,
    std::string* error) {
#if WINDOWS_AI_AVAILABLE
  try {
    auto model =
        winrt::Microsoft::Windows::AI::LanguageModel::CreateAsync().get();
    if (model == nullptr) {
      *error = "Windows AI could not start a language model on this PC.";
      return false;
    }
    winrt::Microsoft::Windows::AI::LanguageModelOptions options;
    // Windows AI's LanguageModelOptions exposes no sampling knobs in the
    // surface this plugin targets, so per-call overrides have nowhere to go.
    // Accepted for cross-platform parity and dropped, rather than mapped
    // onto something that means something else.
    (void)overrides;
    // The generation call is awaited synchronously so the reply and every
    // event stay on the platform thread — see the class comment.
    auto response = model
                        .GenerateResponseAsync(
                            options, winrt::to_hstring(state->transcript))
                        .get();
    *out = winrt::to_string(response.Text());
    return true;
  } catch (const winrt::hresult_error& e) {
    *error = "Windows AI error: " + winrt::to_string(e.message());
    return false;
  } catch (const std::exception& e) {
    *error = std::string("Windows AI error: ") + e.what();
    return false;
  } catch (...) {
    *error = "Unknown Windows AI error during generation.";
    return false;
  }
#else
  (void)state;
  (void)overrides;
  (void)out;
  *error =
      "This build has no Windows AI SDK headers, so no inference can run.";
  return false;
#endif
}

void LocalAiSessionService::GenerateResponse(
    int64_t session_id,
    const flutter_local_ai_pigeon::GenerationOverrides* overrides,
    std::function<void(ErrorOr<std::string> reply)> result) {
  SessionState* state = Find(session_id);
  if (state == nullptr) {
    result(ErrorOr<std::string>(SessionMissing(session_id)));
    return;
  }
  std::string text;
  std::string error;
  if (!Generate(state, overrides, &text, &error)) {
    result(ErrorOr<std::string>(FlutterError("GENERATION_ERROR", error)));
    return;
  }
  // Windows AI keeps no history of its own, so the model's turn is appended
  // back onto the transcript for the next turn to see.
  state->transcript += text;
  result(text);
}

void LocalAiSessionService::GenerateResponseAsync(
    int64_t session_id,
    const flutter_local_ai_pigeon::GenerationOverrides* overrides,
    std::function<void(std::optional<FlutterError> reply)> result) {
  SessionState* state = Find(session_id);
  if (state == nullptr) {
    result(SessionMissing(session_id));
    return;
  }
  // Acknowledge first: the Dart contract is that this call starts generation
  // and output arrives on the event channel.
  result(std::nullopt);

  std::string text;
  std::string error;
  if (!Generate(state, overrides, &text, &error)) {
    PostEvent(EncodableMap{
        {EncodableValue("code"), EncodableValue("ERROR")},
        {EncodableValue("message"), EncodableValue(error)},
        {EncodableValue("sessionId"), EncodableValue(session_id)},
    });
    return;
  }
  state->transcript += text;
  // One chunk rather than token-by-token: Windows AI is awaited
  // synchronously so nothing off the platform thread touches the sink.
  if (!text.empty()) {
    PostEvent(EncodableMap{
        {EncodableValue("partialResult"), EncodableValue(text)},
        {EncodableValue("done"), EncodableValue(false)},
        {EncodableValue("sessionId"), EncodableValue(session_id)},
    });
  }
  PostDone(session_id);
}

void LocalAiSessionService::GenerateStructuredResponse(
    int64_t session_id,
    const std::string& schema_json,
    const flutter_local_ai_pigeon::GenerationOverrides* overrides,
    std::function<void(ErrorOr<std::string> reply)> result) {
  result(ErrorOr<std::string>(FlutterError(
      "STRUCTURED_OUTPUT_UNSUPPORTED",
      "Schema-constrained output is not available on Windows AI Foundry, "
      "which is text-out only. Check "
      "LocalAi.capabilities().supportsStructuredOutput first.")));
}

void LocalAiSessionService::StopGeneration(
    int64_t session_id,
    std::function<void(std::optional<FlutterError> reply)> result) {
  // Generation is synchronous on the platform thread, so by the time this
  // call is dispatched the turn it would cancel has already finished. The
  // completion event still goes out so a Dart stream closes cleanly either
  // way; there is nothing left to interrupt.
  PostDone(session_id);
  result(std::nullopt);
}

void LocalAiSessionService::CountTokens(
    const std::string& text,
    std::function<void(ErrorOr<int64_t> reply)> result) {
  result(ErrorOr<int64_t>(FlutterError(
      "TOKENIZER_UNAVAILABLE",
      "Windows AI Foundry exposes no tokenizer, so exact counts are not "
      "available. Dart falls back to a character estimate.")));
}

}  // namespace flutter_local_ai
