import Foundation

#if os(OSX)
import FlutterMacOS
#elseif os(iOS)
import Flutter
#endif

#if canImport(FoundationModels)
import FoundationModels
#endif

@objc public class FlutterLocalAiPlugin: NSObject, FlutterPlugin {
  #if canImport(FoundationModels)
  @available(iOS 26.0, macOS 26.0, *)
  private var cachedModel: SystemLanguageModel?
  
  @available(iOS 26.0, macOS 26.0, *)
  private var session: LanguageModelSession?
  
  @available(iOS 26.0, macOS 26.0, *)
  private var instructions: String = "You are a helpful assistant. Provide concise answers."
  #endif
  
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "flutter_local_ai", binaryMessenger: registrar.messenger())
    let instance = FlutterLocalAiPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isAvailable":
      checkAvailability(result: result)
    case "initialize":
      initialize(call: call, result: result)
    case "generateText":
      generateText(call: call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func checkAvailability(result: @escaping FlutterResult) {
    #if canImport(FoundationModels)
    if #available(iOS 26.0, macOS 26.0, *) {
      Task {
        do {
          let available = try await checkModelAvailability()
          result(available)
        } catch {
          result(false)
        }
      }
    } else {
      result(false)
    }
    #else
    result(false)
    #endif
  }

  #if canImport(FoundationModels)
  @available(iOS 26.0, macOS 26.0, *)
  private func checkModelAvailability() async throws -> Bool {
    do {
      let model = try await loadModel()
      switch model.availability {
        case .available:
            // Model is ready to use
            return true
        case .unavailable(let reason):
            print("Model is unavailable: \(reason)")
            return false
        @unknown default:
            print("Model is unavailable: \(model.availability)")
            return false
        }
    } catch {
      return false
    }
  }
  #endif

  private func initialize(call: FlutterMethodCall, result: @escaping FlutterResult) {
    #if canImport(FoundationModels)
    if #available(iOS 26.0, macOS 26.0, *) {
      guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(
          code: "INVALID_ARGUMENT",
          message: "Arguments are required",
          details: nil
        ))
        return
      }
      
      // Get instructions if provided
      let instructionsText = args["instructions"] as? String ?? "You are a helpful assistant. Provide concise answers."
      
      Task {
        do {
          try await initializeSession(instructions: instructionsText)
          result(true)
        } catch {
          result(FlutterError(
            code: "INITIALIZATION_ERROR",
            message: "Error initializing model: \(error.localizedDescription)",
            details: nil
          ))
        }
      }
    } else {
      result(FlutterError(
        code: "UNSUPPORTED_VERSION",
        message: "FoundationModels requires iOS 26.0 or macOS 26.0 or later",
        details: nil
      ))
    }
    #else
    result(FlutterError(
      code: "NOT_AVAILABLE",
      message: "FoundationModels framework is not available",
      details: nil
    ))
    #endif
  }

  private func generateText(call: FlutterMethodCall, result: @escaping FlutterResult) {
    #if canImport(FoundationModels)
    if #available(iOS 26.0, macOS 26.0, *) {
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

      Task {
        do {
          let response = try await generateTextAsync(
            prompt: prompt,
            maxTokens: maxTokens,
            temperature: temperature,
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
        message: "FoundationModels requires iOS 26.0 or macOS 26.0 or later",
        details: nil
      ))
    }
    #else
    result(FlutterError(
      code: "NOT_AVAILABLE",
      message: "FoundationModels framework is not available",
      details: nil
    ))
    #endif
  }

  #if canImport(FoundationModels)
  @available(iOS 26.0, macOS 26.0, *)
  private func loadModel() async throws -> SystemLanguageModel {
    // Return cached model if available
    if let cached = cachedModel {
      return cached
    }
    
    // Load the default system language model
    let model = SystemLanguageModel.default
    cachedModel = model
    return model
  }
  
  @available(iOS 26.0, macOS 26.0, *)
  private func initializeSession(instructions: String) async throws {
    // Load the model
    let model = try await loadModel()
    
    // Store instructions
    self.instructions = instructions
    
    // Create a customized session with explicit parameters
    let newSession = LanguageModelSession(
      instructions: instructions
    )
    
    // Cache the session for future use
    self.session = newSession
  }
  
  @available(iOS 26.0, macOS 26.0, *)
  private func generateTextAsync(
    prompt: String,
    maxTokens: Int,
    temperature: Double?,
  ) async throws -> [String: Any] {
    let startTime = Date()
    
    // Ensure session is initialized
    if session == nil {
      try await initializeSession(instructions: instructions)
    }
    
    guard let session = session else {
      throw NSError(
        domain: "FlutterLocalAiPlugin",
        code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Session not initialized. Call initialize first."]
      )
    }
    
    // Use the session to generate text
    let response = try await session.respond(to: prompt, options: .init(sampling: .greedy, temperature: temperature ?? 0.7, maximumResponseTokens: maxTokens))
    let generatedText = response.content
    
    // Calculate generation time in milliseconds
    let generationTime = Int(Date().timeIntervalSince(startTime) * 1000)
    
    // Estimate token count (approximate based on word count)
    let tokenCount = generatedText.split(separator: " ").count
    
    // Return the response in the format expected by Flutter
    return [
      "text": generatedText,
      "generationTimeMs": generationTime,
      "tokenCount": tokenCount
    ]
  }
  #endif
}
