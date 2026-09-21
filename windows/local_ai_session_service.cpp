#include "local_ai_session_service.h"

#include <flutter/event_stream_handler_functions.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <cstdio>
#include <utility>

#ifndef WINDOWS_AI_AVAILABLE
#define WINDOWS_AI_AVAILABLE 0
#endif

#if WINDOWS_AI_AVAILABLE
#include <winrt/Microsoft.Windows.AI.h>
#include <winrt/Microsoft.Windows.AI.Text.h>
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
      "This build has no Windows App SDK projection, so no inference can run. "
      "The plugin's CMake resolves it on its own (NuGet cache or a download "
      "of Microsoft.WindowsAppSDK.AI); look for 'flutter_local_ai:' in the "
      "build output for why that did not happen, or set "
      "FLUTTER_LOCAL_AI_WINRT_INCLUDE_DIR. See doc/platform-support.md.");
}
#else
// A one-line description of a failed WinRT call for error messages.
std::string Describe(const winrt::hresult_error& e) {
  char code[16];
  std::snprintf(code, sizeof code, "0x%08X",
                static_cast<unsigned>(e.code().value));
  return winrt::to_string(e.message()) + " (" + code + ")";
}

// Statuses shared by LanguageModelResponseStatus and
// GenerateStructuredJsonResponseStatus; the two enums agree on these values.
std::optional<FlutterError> ErrorForStatus(int status, bool structured) {
  using winrt::Microsoft::Windows::AI::Text::LanguageModelResponseStatus;
  switch (static_cast<LanguageModelResponseStatus>(status)) {
    case LanguageModelResponseStatus::Complete:
      return std::nullopt;
    case LanguageModelResponseStatus::BlockedByPolicy:
      return FlutterError("GENERATION_BLOCKED",
          "Generative AI is blocked by system or user policy on this device.");
    case LanguageModelResponseStatus::PromptLargerThanContext:
      return FlutterError("PROMPT_TOO_LONG",
          "The conversation no longer fits the Windows AI context window. "
          "Close the session and start a new one.");
    case LanguageModelResponseStatus::PromptBlockedByContentModeration:
      return FlutterError("GENERATION_BLOCKED",
          "The prompt was blocked by Windows content moderation.");
    case LanguageModelResponseStatus::ResponseBlockedByContentModeration:
      return FlutterError("GENERATION_BLOCKED",
          "The response was blocked by Windows content moderation.");
    default:
      return FlutterError("GENERATION_ERROR",
          std::string("Windows AI did not complete the ") +
              (structured ? "structured " : "") + "response (status " +
              std::to_string(status) + ").");
  }
}
#endif

}  // namespace

LocalAiSessionService::LocalAiSessionService() = default;

LocalAiSessionService::~LocalAiSessionService() {
  lifetime_.reset();
  for (auto& [id, state] : sessions_) Cancel(state.active);
}

void LocalAiSessionService::Cancel(const std::shared_ptr<RunState>& run) {
  if (!run) return;
  run->cancelled = true;
#if WINDOWS_AI_AVAILABLE
  if (run->operation) { try { run->operation.Cancel(); } catch (...) {} }
#endif
}

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

void LocalAiSessionService::PostToken(int64_t session_id,
                                      const std::string& text) {
  PostEvent(EncodableMap{
      {EncodableValue("partialResult"), EncodableValue(text)},
      {EncodableValue("done"), EncodableValue(false)},
      {EncodableValue("sessionId"), EncodableValue(session_id)},
  });
}

void LocalAiSessionService::PostDone(int64_t session_id) {
  PostEvent(EncodableMap{
      {EncodableValue("partialResult"), EncodableValue("")},
      {EncodableValue("done"), EncodableValue(true)},
      {EncodableValue("sessionId"), EncodableValue(session_id)},
  });
}

void LocalAiSessionService::PostError(int64_t session_id,
                                      const std::string& message) {
  PostEvent(EncodableMap{
      {EncodableValue("code"), EncodableValue("ERROR")},
      {EncodableValue("message"), EncodableValue(message)},
      {EncodableValue("sessionId"), EncodableValue(session_id)},
  });
}

// === Availability ===

void LocalAiSessionService::CheckAvailability(
    std::function<void(ErrorOr<AvailabilityStatus> reply)> result) {
#if WINDOWS_AI_AVAILABLE
  try {
    using winrt::Microsoft::Windows::AI::AIFeatureReadyState;
    using winrt::Microsoft::Windows::AI::Text::LanguageModel;
    switch (LanguageModel::GetReadyState()) {
      case AIFeatureReadyState::Ready: result(AvailabilityStatus::kAvailable); break;
      case AIFeatureReadyState::NotReady:
        result(preparing_ ? AvailabilityStatus::kDownloading : AvailabilityStatus::kDownloadable); break;
      case AIFeatureReadyState::DisabledByUser:
        result(AvailabilityStatus::kUnavailableDisabled); break;
      case AIFeatureReadyState::OSUpdateNeeded:
        result(AvailabilityStatus::kUnavailableOsTooOld); break;
      case AIFeatureReadyState::NotSupportedOnCurrentSystem:
      case AIFeatureReadyState::NotCompatibleWithSystemHardware:
        result(AvailabilityStatus::kUnavailableDeviceUnsupported); break;
      default: result(AvailabilityStatus::kUnavailableOther); break;
    }
    last_probe_error_.clear();
  } catch (const winrt::hresult_error& e) {
    // The probe's contract is to resolve, never throw. The usual cause here
    // is "Class not registered": the app has no Windows App Runtime to
    // activate LanguageModel from, or no package identity to do it with.
    last_probe_error_ = Describe(e);
    result(AvailabilityStatus::kUnavailableOther);
  } catch (...) {
    last_probe_error_ = "unknown failure";
    result(AvailabilityStatus::kUnavailableOther);
  }
#else
  result(AvailabilityStatus::kUnavailableDeviceUnsupported);
#endif
}

void LocalAiSessionService::AvailabilityReason(
    std::function<void(ErrorOr<std::string> reply)> result) {
#if WINDOWS_AI_AVAILABLE
  // CheckAvailability answers synchronously, so `this` outlives the lambda.
  CheckAvailability([this, result](ErrorOr<AvailabilityStatus> status) {
    if (status.has_error()) { result(std::string("Windows AI readiness check failed.")); return; }
    switch (status.value()) {
      case AvailabilityStatus::kAvailable: result(std::string("Windows AI is ready.")); break;
      case AvailabilityStatus::kDownloadable:
      case AvailabilityStatus::kDownloading:
        result(std::string("The Windows AI model needs preparation. Call LocalAi.ensureReady after obtaining consent for any download.")); break;
      case AvailabilityStatus::kUnavailableDisabled:
        result(std::string("The Windows AI model is disabled by the user.")); break;
      case AvailabilityStatus::kUnavailableOsTooOld:
        result(std::string("The Windows AI model requires an OS update.")); break;
      case AvailabilityStatus::kUnavailableDeviceUnsupported:
        result(std::string("This device cannot run the Windows AI model: it needs a Copilot+ PC (NPU) or a supported GPU, and Windows 11 25H2 or later.")); break;
      default:
        if (last_probe_error_.empty()) {
          result(std::string("Windows AI reported an unclassified state. Check supported hardware, the Windows App Runtime, and the systemAIModels package capability."));
        } else {
          result("Windows AI could not be reached: " + last_probe_error_ +
                 ". The app must be packaged with identity, declare the "
                 "systemAIModels capability and depend on the Windows App "
                 "Runtime that matches the SDK it was built against.");
        }
        break;
    }
  });
#else
  result(std::string(
      "This build has no Windows App SDK projection, so the OS model cannot "
      "be reached. The build output explains why the plugin could not "
      "resolve one; see doc/platform-support.md."));
#endif
}

void LocalAiSessionService::GetBackendInfo(
    std::function<void(ErrorOr<LocalAiBackendInfo> reply)> result) {
#if WINDOWS_AI_AVAILABLE
  LocalAiBackendInfo info(
      LocalAiBackend::kWindowsAiFoundry, "windows", "Windows AI Foundry",
      /*supports_tool_calling=*/false,
      // LanguageModel.GenerateStructuredJsonResponseAsync, App SDK 2.0+.
      /*supports_structured_output=*/true,
      /*supports_vision=*/false,
      /*supports_token_count=*/false,
      /*supports_model_download=*/true,
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
#if WINDOWS_AI_AVAILABLE
  Prepare(std::move(result));
#else
  result(NotConfigured());
#endif
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
  for (auto& [id, state] : sessions_) { Cancel(state.active); PostDone(id); }
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
  state.top_k = top_k;
  if (top_p) state.top_p = *top_p;
  state.max_output_tokens =
      max_output_tokens != nullptr ? *max_output_tokens : 0;
  if (system_instruction != nullptr && !system_instruction->empty()) {
    state.transcript = *system_instruction + "\n\n";
  }

  sessions_[session_id] = std::move(state);
  result(std::nullopt);
}

void LocalAiSessionService::CloseSession(
    int64_t session_id,
    std::function<void(std::optional<FlutterError> reply)> result) {
  if (auto* state = Find(session_id)) Cancel(state->active);
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

#if WINDOWS_AI_AVAILABLE
winrt::fire_and_forget LocalAiSessionService::Prepare(
    std::function<void(std::optional<FlutterError>)> result) {
  std::weak_ptr<int> lifetime = lifetime_;
  if (preparing_) { result(std::nullopt); co_return; }
  preparing_ = true;
  std::optional<FlutterError> error;
  try {
    const auto ready = co_await winrt::Microsoft::Windows::AI::Text::LanguageModel::EnsureReadyAsync();
    if (ready.Status() != winrt::Microsoft::Windows::AI::AIFeatureReadyResultState::Success) {
      error = FlutterError("MODEL_PREPARATION_FAILED", "Windows AI preparation failed; check Windows Update and model availability.");
    }
  } catch (const winrt::hresult_error& e) {
    error = FlutterError("MODEL_PREPARATION_FAILED", winrt::to_string(e.message()));
  } catch (...) {
    error = FlutterError("MODEL_PREPARATION_FAILED", "Windows AI preparation failed.");
  }
  if (lifetime.expired()) co_return;
  preparing_ = false;
  result(error);
}

winrt::fire_and_forget LocalAiSessionService::Generate(
    int64_t session_id, std::string prompt, std::string schema_json,
    double temperature, int64_t top_k, std::optional<double> top_p,
    std::shared_ptr<RunState> run,
    std::function<void(ErrorOr<std::string>)> result) {
  std::weak_ptr<int> lifetime = lifetime_;
  std::string text;
  std::optional<FlutterError> error;
  winrt::Microsoft::Windows::AI::Text::LanguageModel model{nullptr};
  const bool structured = !schema_json.empty();
  try {
    using namespace winrt::Microsoft::Windows::AI::Text;
    auto creating = LanguageModel::CreateAsync();
    run->operation = creating.as<winrt::Windows::Foundation::IAsyncInfo>();
    model = co_await creating;
    if (run->cancelled) throw winrt::hresult_canceled();
    LanguageModelOptions options;
    options.Temperature(static_cast<float>(temperature));
    options.TopK(static_cast<uint32_t>(top_k));
    if (top_p) options.TopP(static_cast<float>(*top_p));
    if (structured) {
      auto generating = model.GenerateStructuredJsonResponseAsync(
          winrt::to_hstring(prompt), winrt::to_hstring(schema_json), options);
      run->operation = generating.as<winrt::Windows::Foundation::IAsyncInfo>();
      const auto response = co_await generating;
      if (run->cancelled) throw winrt::hresult_canceled();
      const auto status = response.Status();
      if (status == GenerateStructuredJsonResponseStatus::CompleteWithInvalidStructure) {
        // The model finished but strayed from the schema. The text travels in
        // `details` so a caller that wants to salvage it still can.
        error = FlutterError(
            "STRUCTURED_OUTPUT_INVALID",
            "Windows AI produced output that does not conform to the schema.",
            EncodableValue(winrt::to_string(response.Text())));
      } else {
        error = ErrorForStatus(static_cast<int>(status), /*structured=*/true);
        if (!error) text = winrt::to_string(response.Text());
      }
    } else {
      auto generating = model.GenerateResponseAsync(winrt::to_hstring(prompt), options);
      run->operation = generating.as<winrt::Windows::Foundation::IAsyncInfo>();
      const auto response = co_await generating;
      if (run->cancelled) throw winrt::hresult_canceled();
      error = ErrorForStatus(static_cast<int>(response.Status()), /*structured=*/false);
      if (!error) text = winrt::to_string(response.Text());
    }
  } catch (const winrt::hresult_canceled&) {
    error = FlutterError("CANCELLED", "Generation was cancelled.");
  } catch (const winrt::hresult_no_interface&) {
    // The projection knows the method but the installed Windows App Runtime
    // predates it: a 1.x runtime under a 2.x build.
    error = FlutterError(
        structured ? "STRUCTURED_OUTPUT_UNSUPPORTED" : "GENERATION_ERROR",
        "The installed Windows App Runtime is older than the SDK this app was "
        "built against; it lacks " +
            std::string(structured ? "GenerateStructuredJsonResponseAsync"
                                   : "the LanguageModel interface") +
            ". Deploy the matching runtime.");
  } catch (const winrt::hresult_error& e) {
    error = FlutterError("GENERATION_ERROR", Describe(e));
  } catch (...) {
    error = FlutterError("GENERATION_ERROR", "Windows AI generation failed.");
  }
  run->operation = nullptr;
  if (model) { try { model.Close(); } catch (...) {} }
  if (lifetime.expired()) co_return;
  if (auto* state = Find(session_id); state && state->active == run) {
    state->active.reset();
    if (!error && !run->cancelled) state->transcript += "\n\n" + text + "\n\n";
  }
  if (error) result(ErrorOr<std::string>(*error));
  else result(text);
}
#endif

void LocalAiSessionService::StartGeneration(
    int64_t session_id,
    const std::string& schema_json,
    const flutter_local_ai_pigeon::GenerationOverrides* overrides,
    std::function<void(ErrorOr<std::string>)> result) {
  auto* state = Find(session_id);
  if (!state) { result(SessionMissing(session_id)); return; }
#if WINDOWS_AI_AVAILABLE
  if (state->active) { result(FlutterError("SESSION_BUSY", "This session is already generating.")); return; }
  auto run = std::make_shared<RunState>();
  state->active = run;
  const auto temperature = overrides && overrides->temperature() ? *overrides->temperature() : state->temperature;
  const auto top_k = overrides && overrides->top_k() ? *overrides->top_k() : state->top_k;
  const auto top_p = overrides && overrides->top_p() ? std::optional<double>(*overrides->top_p()) : state->top_p;
  // The current Windows LanguageModelOptions has no max-output-token field.
  Generate(session_id, state->transcript, schema_json, temperature, top_k, top_p, run, std::move(result));
#else
  (void)schema_json;
  (void)overrides;
  result(NotConfigured());
#endif
}

void LocalAiSessionService::GenerateResponse(
    int64_t session_id,
    const flutter_local_ai_pigeon::GenerationOverrides* overrides,
    std::function<void(ErrorOr<std::string>)> result) {
  StartGeneration(session_id, /*schema_json=*/"", overrides, std::move(result));
}

void LocalAiSessionService::GenerateResponseAsync(
    int64_t session_id,
    const flutter_local_ai_pigeon::GenerationOverrides* overrides,
    std::function<void(std::optional<FlutterError>)> result) {
  if (!Find(session_id)) { result(SessionMissing(session_id)); return; }
  result(std::nullopt);
  StartGeneration(session_id, /*schema_json=*/"", overrides, [this, session_id](ErrorOr<std::string> response) {
    if (response.has_error()) {
      if (response.error().code() != "CANCELLED") PostError(session_id, response.error().message());
      return;
    }
    if (!response.value().empty()) PostToken(session_id, response.value());
    PostDone(session_id);
  });
}

void LocalAiSessionService::GenerateStructuredResponse(
    int64_t session_id,
    const std::string& schema_json,
    const flutter_local_ai_pigeon::GenerationOverrides* overrides,
    std::function<void(ErrorOr<std::string> reply)> result) {
  if (schema_json.empty()) {
    result(ErrorOr<std::string>(FlutterError(
        "INVALID_SCHEMA", "A structured response needs a non-empty schema.")));
    return;
  }
  // Windows constrains decoding to the schema natively; the transcript is
  // replayed exactly as for a text turn and the JSON is appended as the
  // model's reply, so the conversation continues past it.
  StartGeneration(session_id, schema_json, overrides, std::move(result));
}

void LocalAiSessionService::StopGeneration(
    int64_t session_id,
    std::function<void(std::optional<FlutterError> reply)> result) {
  if (auto* state = Find(session_id)) Cancel(state->active);
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
