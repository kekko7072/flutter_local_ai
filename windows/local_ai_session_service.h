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

namespace flutter_local_ai {

// Session half of the flutter_local_ai host on Windows, over Windows AI
// Foundry (Phi Silica).
//
// Windows AI is compile-gated behind WINDOWS_AI_AVAILABLE: the WinRT headers
// have to be generated or installed from the Windows AI SDK. When the gate is
// off, every call that would need the model fails with a message saying so,
// and GetBackendInfo reports `windowsAiFoundryUnconfigured` — Dart callers see
// an honest "this build cannot run it" rather than a silent no-op.
//
// Everything runs on the platform thread. Windows AI's generation call is
// awaited synchronously, so no background thread ever touches the EventSink,
// which the Flutter Windows embedding requires to be used from the platform
// thread only. The cost is that GenerateResponseAsync delivers the response as
// a single chunk followed by `done` rather than token by token.
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
  struct SessionState {
    std::string transcript;
    double temperature = 0.8;
    int64_t max_output_tokens = 0;  // 0 means "no cap requested".
  };

  SessionState* Find(int64_t session_id);

  // Runs one turn against Windows AI, returning the generated text. Sets
  // `error` and returns false when the model is unreachable. `overrides`,
  // when present, replaces the session's sampling for this call only.
  bool Generate(SessionState* state,
                const flutter_local_ai_pigeon::GenerationOverrides* overrides,
                std::string* out,
                std::string* error);

  void PostEvent(const flutter::EncodableMap& payload);
  void PostDone(int64_t session_id);

  std::map<int64_t, SessionState> sessions_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>>
      event_channel_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> event_sink_;
};

}  // namespace flutter_local_ai

#endif  // FLUTTER_PLUGIN_LOCAL_AI_SESSION_SERVICE_H_
