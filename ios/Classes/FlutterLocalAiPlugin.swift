import Flutter
import UIKit
import Foundation

#if canImport(GenAI)
import GenAI
#endif

public class FlutterLocalAiPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "flutter_local_ai", binaryMessenger: registrar.messenger())
    let instance = FlutterLocalAiPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isAvailable":
      checkAvailability(result: result)
    case "generateText":
      generateText(call: call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func checkAvailability(result: @escaping FlutterResult) {
    #if canImport(GenAI)
    // Check if GenAI is available on iOS 18+
    if #available(iOS 18.0, *) {
      result(true)
    } else {
      result(false)
    }
    #else
    result(false)
    #endif
  }

  private func generateText(call: FlutterMethodCall, result: @escaping FlutterResult) {
    #if canImport(GenAI)
    if #available(iOS 18.0, *) {
      guard let args = call.arguments as? [String: Any],
            let prompt = args["prompt"] as? String else {
        result(FlutterError(
          code: "INVALID_ARGUMENT",
          message: "Prompt is required",
          details: nil
        ))
        return
      }

      let configMap = args["config"] as? [String: Any]
      let maxTokens = configMap?["maxTokens"] as? Int ?? 100
      let temperature = configMap?["temperature"] as? Double
      let topP = configMap?["topP"] as? Double
      let topK = configMap?["topK"] as? Int

      Task {
        do {
          let response = try await generateTextAsync(
            prompt: prompt,
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP,
            topK: topK
          )
          result(response)
        } catch {
          result(FlutterError(
            code: "GENERATION_ERROR",
            message: "Error generating text: \(error.localizedDescription)",
            details: nil
          ))
        }
      }
    } else {
      result(FlutterError(
        code: "UNSUPPORTED_VERSION",
        message: "GenAI requires iOS 18.0 or later",
        details: nil
      ))
    }
    #else
    result(FlutterError(
      code: "NOT_AVAILABLE",
      message: "GenAI framework is not available",
      details: nil
    ))
    #endif
  }

  @available(iOS 18.0, *)
  #if canImport(GenAI)
  private func generateTextAsync(
    prompt: String,
    maxTokens: Int,
    temperature: Double?,
    topP: Double?,
    topK: Int?
  ) async throws -> [String: Any] {
    // Note: The actual GenAI API implementation will depend on Apple's final API
    // This is a placeholder structure based on typical GenAI patterns
    
    // For now, we'll use a fallback implementation
    // In production, you would use the actual GenAI framework APIs like:
    // let model = try await GenAIModel.load(...)
    // let response = try await model.generate(prompt: prompt, config: config)
    
    // Placeholder implementation - replace with actual GenAI API calls when available
    let startTime = Date()
    
    // Simulate async generation (replace with actual GenAI API)
    try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
    
    // This is a placeholder - replace with actual GenAI response
    // For now, return a simple echo response
    let generatedText = "Generated response for: \(prompt)"
    let generationTime = Int(Date().timeIntervalSince(startTime) * 1000)
    
    return [
      "text": generatedText,
      "generationTimeMs": generationTime,
      "tokenCount": generatedText.split(separator: " ").count
    ]
  }
  #endif
}
