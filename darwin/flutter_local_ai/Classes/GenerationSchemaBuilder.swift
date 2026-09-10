import Foundation

#if canImport(FoundationModels)
  import FoundationModels
#endif

#if canImport(FoundationModels)

/// Translates a raw JSON Schema map (as supplied through `GenerationConfig`) into
/// a FoundationModels `GenerationSchema`, so generation can be constrained to it.
///
/// Recursive, unlike the flat parameter schemas a tool declaration needs: it
/// supports nested objects, arrays and string enums as well as the scalars.
/// Tree-shaped schemas nest inline via `Property.schema`, so the root needs no
/// separate `dependencies`.
@available(iOS 26.0, macOS 26.0, *)
enum SchemaBuilder {
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
