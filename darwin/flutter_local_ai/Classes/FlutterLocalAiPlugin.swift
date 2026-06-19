import Foundation

#if os(OSX)
@preconcurrency import FlutterMacOS
#elseif os(iOS)
@preconcurrency import Flutter
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

    /// Human-readable reason for the current availability state, so callers can
    /// tell the user exactly what to enable (Apple Intelligence, model download,
    /// an eligible device, a supported language/region…).
    func availabilityReasonString() async -> String {
      let model = (try? await loadModel()) ?? SystemLanguageModel.default
      switch model.availability {
      case .available:
        return "available"
      case .unavailable(let reason):
        return "unavailable: \(String(reflecting: reason))"
      @unknown default:
        return "unknown"
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

    /// The session one generation call runs on. With one-shot [instructions]
    /// a throwaway session is built just for this call: LanguageModelSession
    /// accumulates every prompt + response of its transcript toward the
    /// 4096-token window, so stateless callers (which carry their own context
    /// in the prompt) must not ride — or pollute — the cached session.
    func sessionFor(oneShot: String?) async throws -> LanguageModelSession {
      if let oneShot = oneShot {
        let model = try await loadModel()
        return LanguageModelSession(
          model: model,
          tools: registeredTools,
          instructions: oneShot
        )
      }
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
      return session
    }

    /// Builds `GenerationOptions` from the requested sampling knobs.
    ///
    /// Sampling modes are mutually exclusive, and `.greedy` must NOT be combined
    /// with a temperature (that pairing throws a GenerationError on-device).
    /// Precedence: topK > topP > temperature > greedy. When a top-k/top-p mode
    /// is chosen, a positive temperature is allowed to ride alongside it.
    static func makeOptions(
      maxTokens: Int,
      temperature: Double?,
      topP: Double?,
      topK: Int?
    ) -> GenerationOptions {
      let positiveTemp = (temperature ?? 0) > 0 ? temperature : nil
      if let topK = topK {
        return GenerationOptions(
          sampling: .random(top: topK),
          temperature: positiveTemp,
          maximumResponseTokens: maxTokens
        )
      }
      if let topP = topP {
        return GenerationOptions(
          sampling: .random(probabilityThreshold: topP),
          temperature: positiveTemp,
          maximumResponseTokens: maxTokens
        )
      }
      if let temp = positiveTemp {
        return GenerationOptions(temperature: temp, maximumResponseTokens: maxTokens)
      }
      return GenerationOptions(sampling: .greedy, maximumResponseTokens: maxTokens)
    }

    func generateText(
      prompt: String,
      maxTokens: Int,
      temperature: Double?,
      topP: Double? = nil,
      topK: Int? = nil,
      schema: [String: Any]? = nil,
      instructions oneShot: String? = nil
    ) async throws -> [String: Any] {
      let startTime = Date()
      let session = try await sessionFor(oneShot: oneShot)

      let options = ModelManager.makeOptions(
        maxTokens: maxTokens,
        temperature: temperature,
        topP: topP,
        topK: topK
      )

      // Generate text. On any failure, surface a fully-reflected description so
      // the concrete error case (guardrail, missing assets, etc.) is diagnosable.
      // When a schema is supplied, generation is constrained to it and the
      // resulting JSON is returned as the text payload.
      let generatedText: String
      do {
        if let schema = schema {
          let generationSchema = try SchemaBuilder.generationSchema(
            from: schema, rootName: "Output")
          let response = try await session.respond(
            to: prompt, schema: generationSchema, options: options)
          generatedText = response.content.jsonString
        } else {
          let response = try await session.respond(to: prompt, options: options)
          generatedText = response.content
        }
      } catch {
        throw NSError(
          domain: "FlutterLocalAiPlugin",
          code: 3,
          userInfo: [NSLocalizedDescriptionKey:
            "respond failed :: reflected=\(String(reflecting: error)) :: localized=\(error.localizedDescription)"]
        )
      }
      
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

    /// Streaming counterpart of `generateText`: forwards each newly decoded
    /// text fragment to `onDelta` as the model produces it, returning once the
    /// generation completes.
    func generateTextStream(
      prompt: String,
      maxTokens: Int,
      temperature: Double?,
      topP: Double? = nil,
      topK: Int? = nil,
      instructions oneShot: String? = nil,
      onDelta: @Sendable @escaping (String) -> Void
    ) async throws {
      let session = try await sessionFor(oneShot: oneShot)

      let options = ModelManager.makeOptions(
        maxTokens: maxTokens,
        temperature: temperature,
        topP: topP,
        topK: topK
      )

      do {
        let stream = session.streamResponse(to: prompt, options: options)
        // Each snapshot carries the cumulative text so far; forward only the
        // newly appended suffix so the channel speaks in deltas.
        var emitted = ""
        for try await partial in stream {
          let full = partial.content
          guard full.count > emitted.count, full.hasPrefix(emitted) else { continue }
          onDelta(String(full.dropFirst(emitted.count)))
          emitted = full
        }
      } catch {
        throw NSError(
          domain: "FlutterLocalAiPlugin",
          code: 3,
          userInfo: [NSLocalizedDescriptionKey:
            "streamResponse failed :: reflected=\(String(reflecting: error)) :: localized=\(error.localizedDescription)"]
        )
      }
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
    case "availabilityReason":
      availabilityReason(result: result)
    case "initialize":
      initialize(call: call, result: result)
    case "generateText":
      generateText(call: call, result: result)
    case "generateTextStream":
      generateTextStream(call: call, result: result)
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
      "supportsStructuredOutput": supportsFoundationModels,
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

  private func availabilityReason(result: @escaping FlutterResult) {
    #if canImport(FoundationModels)
    if #available(iOS 26.0, macOS 26.0, *) {
      guard let manager = modelManager as? ModelManager else {
        result("unavailable: no model manager")
        return
      }
      Task {
        let reason = await manager.availabilityReasonString()
        result(reason)
      }
    } else {
      result("unavailable: requires iOS 26.0 / macOS 26.0 or later")
    }
    #else
    result("unavailable: FoundationModels framework not compiled in")
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
      let topP = configMap?["topP"] as? Double
      let topK = configMap?["topK"] as? Int
      let schema = configMap?["schema"] as? [String: Any]
      let oneShot = args["instructions"] as? String

      Task {
        do {
          let response = try await manager.generateText(
            prompt: prompt,
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP,
            topK: topK,
            schema: schema,
            instructions: oneShot
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

  private func generateTextStream(call: FlutterMethodCall, result: @escaping FlutterResult) {
    #if canImport(FoundationModels)
    if #available(iOS 26.0, macOS 26.0, *) {
      guard let args = call.arguments as? [String: Any],
            let prompt = args["prompt"] as? String,
            let requestId = args["id"] as? Int else {
        result(FlutterError(
          code: "INVALID_ARGUMENT",
          message: "Prompt and request id are required",
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

      let configMap = args["config"] as? [String: Any]
      let maxTokens = configMap?["maxTokens"] as? Int ?? 100
      let temperature = configMap?["temperature"] as? Double
      let topP = configMap?["topP"] as? Double
      let topK = configMap?["topK"] as? Int
      let oneShot = args["instructions"] as? String

      // The method call returns immediately; output is delivered through the
      // onGenerateTextChunk / Done / Error callbacks tagged with the id.
      result(nil)

      Task {
        do {
          try await manager.generateTextStream(
            prompt: prompt,
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP,
            topK: topK,
            instructions: oneShot
          ) { delta in
            DispatchQueue.main.async {
              channel.invokeMethod(
                "onGenerateTextChunk",
                arguments: ["id": requestId, "text": delta]
              )
            }
          }
          DispatchQueue.main.async {
            channel.invokeMethod("onGenerateTextDone", arguments: ["id": requestId])
          }
        } catch {
          DispatchQueue.main.async {
            channel.invokeMethod(
              "onGenerateTextError",
              arguments: ["id": requestId, "message": error.localizedDescription]
            )
          }
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

/// Translates a raw JSON Schema map (as supplied through `GenerationConfig`) into
/// a FoundationModels `GenerationSchema`, so generation can be constrained to it.
///
/// This is the structured-output counterpart of `FlutterTool.buildSchema`, but
/// recursive: it supports nested objects, arrays, and string enums in addition to
/// the scalar types tool parameters allow. Tree-shaped schemas nest inline via
/// `Property.schema`, so the root needs no separate `dependencies`.
@available(iOS 26.0, macOS 26.0, *)
private enum SchemaBuilder {
  static func generationSchema(
    from json: [String: Any],
    rootName: String
  ) throws -> GenerationSchema {
    let root = try node(from: json, name: rootName)
    return try GenerationSchema(root: root, dependencies: [])
  }

  private static func node(
    from json: [String: Any],
    name: String
  ) throws -> DynamicGenerationSchema {
    let description = json["description"] as? String

    // `enum` may appear with or without an explicit `type` in JSON Schema; treat
    // it as a string-choice constraint regardless.
    if let choices = json["enum"] as? [Any] {
      let strings = choices.compactMap { $0 as? String }
      guard strings.count == choices.count, !strings.isEmpty else {
        throw SchemaError.unsupported(
          "Only non-empty string enum values are supported (at `\(name)`).")
      }
      return DynamicGenerationSchema(name: name, description: description, anyOf: strings)
    }

    let type = (json["type"] as? String)?.lowercased() ?? "object"
    switch type {
    case "object":
      let properties = json["properties"] as? [String: Any] ?? [:]
      let required = Set(
        (json["required"] as? [Any])?.compactMap { $0 as? String } ?? [])
      let props: [DynamicGenerationSchema.Property] = try properties.map { key, value in
        guard let child = value as? [String: Any] else {
          throw SchemaError.unsupported("Property `\(key)` must be an object schema.")
        }
        return DynamicGenerationSchema.Property(
          name: key,
          description: child["description"] as? String,
          schema: try node(from: child, name: "\(name)_\(key)"),
          isOptional: !required.contains(key)
        )
      }
      return DynamicGenerationSchema(
        name: name, description: description, properties: props)

    case "array":
      guard let items = json["items"] as? [String: Any] else {
        throw SchemaError.unsupported("Array `\(name)` requires an `items` schema.")
      }
      return DynamicGenerationSchema(
        arrayOf: try node(from: items, name: "\(name)_item"),
        minimumElements: json["minItems"] as? Int,
        maximumElements: json["maxItems"] as? Int
      )

    case "string":
      return DynamicGenerationSchema(type: String.self)
    case "integer":
      return DynamicGenerationSchema(type: Int.self)
    case "number":
      return DynamicGenerationSchema(type: Double.self)
    case "boolean":
      return DynamicGenerationSchema(type: Bool.self)
    default:
      throw SchemaError.unsupported("Unsupported schema type `\(type)` at `\(name)`.")
    }
  }

  enum SchemaError: Error, LocalizedError {
    case unsupported(String)

    var errorDescription: String? {
      switch self {
      case .unsupported(let message):
        return message
      }
    }
  }
}
#endif
