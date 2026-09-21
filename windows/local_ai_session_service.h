#ifndef FLUTTER_PLUGIN_LOCAL_AI_SESSION_SERVICE_H_
#define FLUTTER_PLUGIN_LOCAL_AI_SESSION_SERVICE_H_

#include <flutter/binary_messenger.h>
#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/encodable_value.h>

#include <map>
#include <memory>
#include <mutex>
#include <string>

#include "local_ai_pigeon.g.h"

#if WINDOWS_AI_AVAILABLE
#include <winrt/Microsoft.Windows.AI.Text.h>
#include <winrt/Windows.Foundation.h>
#endif

namespace flutter_local_ai {

// Session half of the flutter_local_ai host on Windows, over Windows AI
// Foundry (Phi Silica).
//
// Windows AI is compile-gated behind WINDOWS_AI_AVAILABLE. The build resolves
// the Windows App SDK's C++/WinRT projection itself (see
// cmake/windows_ai.cmake); when it cannot, the gate is off, every call that
// would need the model fails with a message saying so, and GetBackendInfo
// reports `windowsAiFoundryUnconfigured` — Dart callers see an honest "this
// build cannot run it" rather than a silent no-op.
//
// With the gate on, availability is still the OS's answer: the App Runtime
// has to be deployed and the app packaged with identity and the
// `systemAIModels` capability, or the very first WinRT activation fails.
// That failure is kept so AvailabilityReason can name it.
//
// Text generation uses LanguageModel.GenerateResponseAsync; schema-constrained
// output uses GenerateStructuredJsonResponseAsync (Windows App SDK 2.0+),
// which is why the projection floor is 2.0.
//
// The Flutter Windows runner initializes a COM STA on the platform thread.
// WinRT coroutines resume there; inference never blocks the message loop.
// Streaming currently delivers one final chunk. Native token progress remains
// a follow-up until its ordering is validated on a Windows device.
class LocalAiSessionService : public flutter_local_ai_pigeon::LocalAiService {
 public:
  LocalAiSessionService();
  ~LocalAiSessionService() override;

  LocalAiSessionService(const LocalAiSessionService&) = delete;
  LocalAiSessionService& operator=(const LocalAiSessionService&) = delete;

  // Wires the pigeon host API and the shared event channel.
  static std::unique_ptr<LocalAiSessionService> Register(
      flutter::BinaryMessenger* messenger);

  void CheckAvailability(
      std::function<void(
          flutter_local_ai_pigeon::ErrorOr<
              flutter_local_ai_pigeon::AvailabilityStatus> reply)> result)
      override;
  void AvailabilityReason(
      std::function<void(flutter_local_ai_pigeon::ErrorOr<std::string> reply)>
          result) override;
  void GetBackendInfo(
      std::function<void(flutter_local_ai_pigeon::ErrorOr<
                         flutter_local_ai_pigeon::LocalAiBackendInfo> reply)>
          result) override;
  void DownloadFeature(
      std::function<
          void(std::optional<flutter_local_ai_pigeon::FlutterError> reply)>
          result) override;
  void OpenAICorePlayStore(
      std::function<void(flutter_local_ai_pigeon::ErrorOr<bool> reply)> result)
      override;
  void CreateModel(
      bool support_image,
      std::function<
          void(std::optional<flutter_local_ai_pigeon::FlutterError> reply)>
          result) override;
  void CloseModel(
      std::function<
          void(std::optional<flutter_local_ai_pigeon::FlutterError> reply)>
          result) override;
  void CreateSession(
      int64_t session_id,
      double temperature,
      int64_t top_k,
      const double* top_p,
      const int64_t* max_output_tokens,
      const std::string* system_instruction,
      const flutter::EncodableList* tools,
      std::function<
          void(std::optional<flutter_local_ai_pigeon::FlutterError> reply)>
          result) override;
  void CloseSession(
      int64_t session_id,
      std::function<
          void(std::optional<flutter_local_ai_pigeon::FlutterError> reply)>
          result) override;
  void AddQueryChunk(
      int64_t session_id,
      const std::string& text,
      std::function<
          void(std::optional<flutter_local_ai_pigeon::FlutterError> reply)>
          result) override;
  void AddImage(
      int64_t session_id,
      const std::vector<uint8_t>& image_bytes,
      std::function<
          void(std::optional<flutter_local_ai_pigeon::FlutterError> reply)>
          result) override;
  void GenerateResponse(
      int64_t session_id,
      const flutter_local_ai_pigeon::GenerationOverrides* overrides,
      std::function<void(flutter_local_ai_pigeon::ErrorOr<std::string> reply)>
          result) override;
  void GenerateResponseAsync(
      int64_t session_id,
      const flutter_local_ai_pigeon::GenerationOverrides* overrides,
      std::function<
          void(std::optional<flutter_local_ai_pigeon::FlutterError> reply)>
          result) override;
  void GenerateStructuredResponse(
      int64_t session_id,
      const std::string& schema_json,
      const flutter_local_ai_pigeon::GenerationOverrides* overrides,
      std::function<void(flutter_local_ai_pigeon::ErrorOr<std::string> reply)>
          result) override;
  void StopGeneration(
      int64_t session_id,
      std::function<
          void(std::optional<flutter_local_ai_pigeon::FlutterError> reply)>
          result) override;
  void CountTokens(
      const std::string& text,
      std::function<void(flutter_local_ai_pigeon::ErrorOr<int64_t> reply)>
          result) override;

 private:
  // The Windows AI model has no server-side history, so each session replays
  // its own transcript and appends the model's turn back onto it.
  struct RunState {
    bool cancelled = false;
#if WINDOWS_AI_AVAILABLE
    winrt::Windows::Foundation::IAsyncInfo operation{nullptr};
#endif
  };
  struct SessionState {
    std::string transcript;
    double temperature = 0.8;
    int64_t top_k = 1;
    std::optional<double> top_p;
    std::shared_ptr<RunState> active;
    int64_t max_output_tokens = 0;  // 0 means "no cap requested".
  };

  SessionState* Find(int64_t session_id);

#if WINDOWS_AI_AVAILABLE
  // One coroutine for both text and schema-constrained turns: `schema_json`
  // empty means plain GenerateResponseAsync.
  winrt::fire_and_forget Generate(
      int64_t session_id, std::string prompt, std::string schema_json,
      double temperature, int64_t top_k, std::optional<double> top_p,
      std::shared_ptr<RunState> run,
      std::function<void(flutter_local_ai_pigeon::ErrorOr<std::string>)> result);
  winrt::fire_and_forget Prepare(
      std::function<void(std::optional<flutter_local_ai_pigeon::FlutterError>)> result);
#endif
  void StartGeneration(
      int64_t session_id,
      const std::string& schema_json,
      const flutter_local_ai_pigeon::GenerationOverrides* overrides,
      std::function<void(flutter_local_ai_pigeon::ErrorOr<std::string>)> result);
  static void Cancel(const std::shared_ptr<RunState>& run);
  std::shared_ptr<int> lifetime_ = std::make_shared<int>(0);
  bool preparing_ = false;
  // Why the last CheckAvailability probe threw, if it did — e.g. "Class not
  // registered" when the Windows App Runtime is missing. Empty otherwise.
  std::string last_probe_error_;

  void PostEvent(const flutter::EncodableMap& payload);
  void PostToken(int64_t session_id, const std::string& text);
  void PostDone(int64_t session_id);
  void PostError(int64_t session_id, const std::string& message);

  std::map<int64_t, SessionState> sessions_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>>
      event_channel_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> event_sink_;
};

}  // namespace flutter_local_ai

#endif  // FLUTTER_PLUGIN_LOCAL_AI_SESSION_SERVICE_H_
