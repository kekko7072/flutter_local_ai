## ⚠️ Warning
### This package is still under active development and is not yet stable.

# flutter_local_ai
A Flutter package that provides a unified API for local AI inference on Android with [*ML Kit GenAI*](https://developer.android.com/ai/gemini-nano/ml-kit-genai) and on Apple Platforms using [*Foundation Models*](https://developer.apple.com/documentation/FoundationModels) .

## Features

- 🤖 Local AI inference on both Android and Apple Platfomrs
- 📱 Platform-specific optimizations
- 🔒 Privacy-first: all processing happens on-device
- 🚀 Easy-to-use Dart API

## Getting Started

### Android Setup

Add the following to your `android/app/build.gradle`:

```gradle
dependencies {
    implementation 'com.google.mlkit:genai:1.0.0'
}
```

### iOS Setup

Requires iOS 26.0+ and Xcode 16.0+.

Add the following to your `ios/Podfile`:

```ruby
platform :ios, '26.0'
```

## Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  flutter_local_ai:
    git:
      url: https://github.com/kekko7072/flutter_local_ai.git
```

Or if published to pub.dev:

```yaml
dependencies:
  flutter_local_ai: ^(latest-version)
```

## Usage

### Basic Usage

```dart
import 'package:flutter_local_ai/flutter_local_ai.dart';

// Initialize the AI engine
final aiEngine = FlutterLocalAi();

// Check availability
final isAvailable = await aiEngine.isAvailable();
if (!isAvailable) {
  print('Local AI is not available on this device');
  return;
}

// Generate text with simple method
final text = await aiEngine.generateTextSimple(
  prompt: 'Write a short story about a robot',
  maxTokens: 200,
);
print(text);
```

### Advanced Usage

```dart
import 'package:flutter_local_ai/flutter_local_ai.dart';

final aiEngine = FlutterLocalAi();

// Generate text with configuration
final response = await aiEngine.generateText(
  prompt: 'Explain quantum computing in simple terms',
  config: const GenerationConfig(
    maxTokens: 300,
    temperature: 0.7,
    topP: 0.9,
    topK: 40,
  ),
);

print('Generated text: ${response.text}');
print('Token count: ${response.tokenCount}');
print('Generation time: ${response.generationTimeMs}ms');
```

## API Reference

### `FlutterLocalAi`

Main class for interacting with local AI.

#### Methods

- `Future<bool> isAvailable()` - Check if local AI is available on the device
- `Future<AiResponse> generateText({required String prompt, GenerationConfig? config})` - Generate text from a prompt with optional configuration
- `Future<String> generateTextSimple({required String prompt, int maxTokens = 100})` - Convenience method to generate text and return just the string

### `GenerationConfig`

Configuration for text generation.

- `maxTokens` (int, default: 100) - Maximum number of tokens to generate
- `temperature` (double?, optional) - Temperature for generation (0.0 to 1.0)
- `topP` (double?, optional) - Top-p sampling parameter
- `topK` (int?, optional) - Top-k sampling parameter

### `AiResponse`

Response from AI generation.

- `text` (String) - The generated text
- `tokenCount` (int?) - Token count used
- `generationTimeMs` (int?) - Generation time in milliseconds

## Implementation Notes

### Android
The Android implementation uses ML Kit GenAI (Gemini Nano). The API structure may need to be verified against the latest ML Kit GenAI documentation as the API might evolve.

### iOS
The iOS implementation currently includes a placeholder for Apple's GenAI framework (iOS 26+). Once Apple releases the final GenAI API documentation and framework, the `generateTextAsync` method in `FlutterLocalAiPlugin.swift` should be updated with the actual API calls.

**Note:** The iOS implementation structure is ready, but you'll need to replace the placeholder implementation with the actual GenAI framework API calls when Apple's documentation is available.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT
# flutter_local_ai
