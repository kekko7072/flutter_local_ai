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
  private var channel: FlutterMethodChannel?
  
  #if canImport(FoundationModels)
  @available(iOS 26.0, macOS 26.0, *)
  actor ModelManager {
    var cachedModel: SystemLanguageModel?
    var session: LanguageModelSession?
    var instructions: String = "You are a helpful assistant. Provide concise answers."
    var registeredTools: [any Tool] = []

    func loadModel() async throws -> SystemLanguageModel {
      // Return cached model if available
      if let cached = cachedModel {
        return cached
      }
      
      // Load the default system language model
      let model = SystemLanguageModel.default
      cachedModel = model
      return model
    }

    func checkAvailability() async -> Bool {
      do {
        let model = try await loadModel()
        switch model.availability {
        case .available:
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

    func updateRegisteredTools(from payload: [[String: Any]], channel: FlutterMethodChannel) throws {
      let parsedTools = try payload.map { try FlutterTool(from: $0, channel: channel) }
      registeredTools = parsedTools
      
      // Ensure the session picks up new tools on the next generation call
      session = nil
    }

    func initializeSession(instructions: String) async throws {
      // Load the model
      let model = try await loadModel()
      
      // Store instructions
      self.instructions = instructions
      
      // Create a customized session with explicit parameters
      let newSession = LanguageModelSession(
        model: model,
        tools: registeredTools,
        instructions: instructions
      )
      
      // Cache the session for future use
      session = newSession
    }

    func generateText(
      prompt: String,
      maxTokens: Int,
      temperature: Double?
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
  }

  private var modelManager: Any?
  
  override init() {
    super.init()
    if #available(iOS 26.0, macOS 26.0, *) {
      modelManager = ModelManager()
    }
  }
  #endif
  
  public static func register(with registrar: FlutterPluginRegistrar) {
    #if os(OSX)
    let channel = FlutterMethodChannel(name: "flutter_local_ai", binaryMessenger: registrar.messenger)
    #elseif os(iOS)
    let channel = FlutterMethodChannel(name: "flutter_local_ai", binaryMessenger: registrar.messenger())
    #endif
    let instance = FlutterLocalAiPlugin()
    instance.channel = channel
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformInfo":
      getPlatformInfo(result: result)
    case "isAvailable":
      checkAvailability(result: result)
    case "initialize":
      initialize(call: call, result: result)
    case "generateText":
      generateText(call: call, result: result)
    case "registerTools":
      registerTools(call: call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func getPlatformInfo(result: @escaping FlutterResult) {
    #if os(iOS)
    let platform = "ios"
    #elseif os(OSX)
    let platform = "macos"
    #else
    let platform = "unknown"
    #endif

    #if canImport(FoundationModels)
    let configured = true
    #else
    let configured = false
    #endif

    let supportsFoundationModels: Bool
    if #available(iOS 26.0, macOS 26.0, *) {
      supportsFoundationModels = true
    } else {
      supportsFoundationModels = false
    }

    result([
      "backend": "apple_foundation_models",
      "platform": platform,
      "apiName": "Apple Foundation Models",
      "supportsToolCalling": supportsFoundationModels,
      "supportsModelDownload": false,
      "supportsPlayStoreRedirect": false,
      "isConfigured": configured
    ])
  }

  private func checkAvailability(result: @escaping FlutterResult) {
    #if canImport(FoundationModels)
    if #available(iOS 26.0, macOS 26.0, *) {
      guard let manager = modelManager as? ModelManager else {
        result(false)
        return
      }
      Task {
        let available = await manager.checkAvailability()
        result(available)
      }
    } else {
      result(false)
    }
    #else
    result(false)
    #endif
  }

  private func registerTools(call: FlutterMethodCall, result: @escaping FlutterResult) {
    #if canImport(FoundationModels)
    if #available(iOS 26.0, macOS 26.0, *) {
      guard let toolsPayload = call.arguments as? [[String: Any]] else {
        result(FlutterError(
          code: "INVALID_ARGUMENT",
          message: "Tools array is required",
          details: nil
        ))
        return
      }
      
      guard let manager = modelManager as? ModelManager, let channel = channel else {
        result(FlutterError(
          code: "PluginError",
          message: "Internal model manager or channel missing",
          details: nil
        ))
        return
      }
      
      Task {
        do {
          try await manager.updateRegisteredTools(from: toolsPayload, channel: channel)
          result(true)
        } catch {
          result(FlutterError(
            code: "TOOL_REGISTRATION_FAILED",
            message: "Failed to register tools: \(error.localizedDescription)",
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
      
      guard let manager = modelManager as? ModelManager else {
         result(FlutterError(
          code: "PluginError",
          message: "Internal model manager missing",
          details: nil
        ))
        return
      }
      
      // Get instructions if provided
      let instructionsText = args["instructions"] as? String ?? "You are a helpful assistant. Provide concise answers."
      
      Task {
        do {
          try await manager.initializeSession(instructions: instructionsText)
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
      
      guard let manager = modelManager as? ModelManager else {
         result(FlutterError(
          code: "PluginError",
          message: "Internal model manager missing",
          details: nil
        ))
        return
      }

      let configMap = args["config"] as? [String: Any]
      let maxTokens = configMap?["maxTokens"] as? Int ?? 100
      let temperature = configMap?["temperature"] as? Double

      Task {
        do {
          let response = try await manager.generateText(
            prompt: prompt,
            maxTokens: maxTokens,
            temperature: temperature
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
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
private struct FlutterToolArguments: ConvertibleFromGeneratedContent {
  let content: GeneratedContent
  
  init(_ content: GeneratedContent) throws {
    self.content = content
  }
  
  func toJSONObject() throws -> Any {
    let data = Data(content.jsonString.utf8)
    return try JSONSerialization.jsonObject(with: data, options: [])
  }
}

@available(iOS 26.0, macOS 26.0, *)
private struct FlutterTool: Tool {
  typealias Arguments = FlutterToolArguments
  typealias Output = GeneratedContent
  
  let name: String
  let description: String
  let parameters: GenerationSchema
  weak var channel: FlutterMethodChannel?
  
  init(from dictionary: [String: Any], channel: FlutterMethodChannel) throws {
    guard let name = dictionary["name"] as? String, !name.isEmpty else {
      throw FlutterToolParsingError.missingName
    }
    
    self.name = name
    self.description = dictionary["description"] as? String ?? ""
    let parametersPayload = dictionary["parameters"] as? [[String: Any]] ?? []
    self.parameters = try FlutterTool.buildSchema(
      toolName: name,
      toolDescription: description,
      payload: parametersPayload
    )
    self.channel = channel
  }
  
  func call(arguments: FlutterToolArguments) async throws -> GeneratedContent {
    guard let channel = channel else {
      throw FlutterToolParsingError.channelMissing
    }
    
    let serializedArguments: Any
    do {
      serializedArguments = try arguments.toJSONObject()
    } catch {
      throw FlutterToolParsingError.serializationFailed("Unable to serialize tool arguments: \(error.localizedDescription)")
    }
    
    let request: [String: Any] = [
      "toolName": name,
      "arguments": serializedArguments
    ]
    
    return try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.main.async {
        channel.invokeMethod("onToolCall", arguments: request) { result in
          if let error = result as? FlutterError {
            continuation.resume(throwing: FlutterTool.toNSError(error))
            return
          }
          
          if let error = result as? NSError {
            continuation.resume(throwing: error)
            return
          }
          
          guard let resultValue = result else {
            continuation.resume(throwing: FlutterToolParsingError.missingResult)
            return
          }
          
          do {
            let content = try FlutterTool.convertResultToGeneratedContent(resultValue)
            continuation.resume(returning: content)
          } catch {
            continuation.resume(throwing: error)
          }
        }
      }
    }
  }
  
  private static func toNSError(_ error: FlutterError) -> NSError {
    NSError(
      domain: "FlutterToolError",
      code: 0,
      userInfo: [
        NSLocalizedDescriptionKey: error.message ?? error.code,
        "details": error.details ?? ""
      ]
    )
  }
  
  private static func buildSchema(
    toolName: String,
    toolDescription: String,
    payload: [[String: Any]]
  ) throws -> GenerationSchema {
    let parameters = try payload.map { try FlutterToolParameter(from: $0) }
    let properties = try parameters.map { parameter in
      let schema = try FlutterTool.schema(for: parameter.type)
      return DynamicGenerationSchema.Property(
        name: parameter.name,
        description: parameter.description,
        schema: schema,
        isOptional: parameter.isOptional
      )
    }
    
    let root = DynamicGenerationSchema(
      name: toolName,
      description: toolDescription.isEmpty ? nil : toolDescription,
      properties: properties
    )
    
    return try GenerationSchema(root: root, dependencies: [])
  }
  
  private static func schema(for type: FlutterToolParameter.ParameterType) throws -> DynamicGenerationSchema {
    switch type {
    case .string:
      return DynamicGenerationSchema(type: String.self)
    case .integer:
      return DynamicGenerationSchema(type: Int.self)
    case .number:
      return DynamicGenerationSchema(type: Double.self)
    case .boolean:
      return DynamicGenerationSchema(type: Bool.self)
    }
  }
  
  private static func convertResultToGeneratedContent(_ result: Any) throws -> GeneratedContent {
    if let stringValue = result as? String {
      return GeneratedContent(stringValue)
    }
    
    if let boolValue = result as? Bool {
      return GeneratedContent(boolValue)
    }
    
    if let numberValue = result as? NSNumber {
      if CFGetTypeID(numberValue) == CFBooleanGetTypeID() {
        return GeneratedContent(numberValue.boolValue)
      } else {
        return GeneratedContent(numberValue.doubleValue)
      }
    }
    
    if result is NSNull {
      return try GeneratedContent(json: "null")
    }
    
    if JSONSerialization.isValidJSONObject(result) {
      let data = try JSONSerialization.data(withJSONObject: result, options: [])
      guard let jsonString = String(data: data, encoding: .utf8) else {
        throw FlutterToolParsingError.serializationFailed("Could not encode tool result to JSON.")
      }
      return try GeneratedContent(json: jsonString)
    }
    
    throw FlutterToolParsingError.serializationFailed("Unsupported tool result type \(type(of: result))")
  }
}

@available(iOS 26.0, macOS 26.0, *)
private struct FlutterToolParameter {
  enum ParameterType: String {
    case string
    case integer
    case number
    case boolean
  }
  
  let name: String
  let description: String?
  let type: ParameterType
  let isOptional: Bool
  
  init(from dictionary: [String: Any]) throws {
    guard let name = dictionary["name"] as? String, !name.isEmpty else {
      throw FlutterToolParsingError.invalidParameterDefinition("Parameter name is required")
    }
    self.name = name
    self.description = dictionary["description"] as? String
    
    let typeString = (dictionary["type"] as? String ?? "string").lowercased()
    guard let type = ParameterType(rawValue: typeString) else {
      throw FlutterToolParsingError.unsupportedParameterType(typeString)
    }
    self.type = type
    
    self.isOptional = dictionary["optional"] as? Bool ?? false
  }
}

@available(iOS 26.0, macOS 26.0, *)
private enum FlutterToolParsingError: Error, LocalizedError {
  case missingName
  case channelMissing
  case missingResult
  case invalidParameterDefinition(String)
  case unsupportedParameterType(String)
  case serializationFailed(String)
  
  var errorDescription: String? {
    switch self {
    case .missingName:
      return "Tool name is required."
    case .channelMissing:
      return "Method channel not available to execute tool."
    case .missingResult:
      return "Tool returned no result."
    case .invalidParameterDefinition(let message):
      return message
    case .unsupportedParameterType(let type):
      return "Unsupported parameter type '\(type)'."
    case .serializationFailed(let message):
      return message
    }
  }
}
#endif
