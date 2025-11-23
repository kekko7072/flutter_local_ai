<div align="center">
  <img src="logo.png" alt="flutter_local_ai logo" width="200">
</div>

<div align="center">

# Flutter Local AI

A Flutter package that provides a unified API for local AI inference on Android with [*ML Kit GenAI*](https://developer.android.com/ai/gemini-nano/ml-kit-genai) and on Apple Platforms using [*Foundation Models*](https://developer.apple.com/documentation/FoundationModels) .

</div>

<div align="center">
  <img src="video.gif" alt="flutter_local_ai video" width="200">
</div>



## ✨ Unique Advantage

**This package has the unique advantage of using native OS APIs without downloading or adding any additional layer to the application.**

- **iOS**: Uses Apple's built-in FoundationModels framework (iOS 26.0+) - no model downloads required
- **Android**: Uses Google's ML Kit GenAI (Gemini Nano) - leverages the native on-device model
- **Zero Model Downloads**: No need to bundle large model files with your app
- **Native Performance**: Direct access to OS-optimized AI capabilities
- **Smaller App Size**: Models are part of the operating system, not your app bundle

## Platform Support

| Feature            | iOS / macOS (26+) | Android (API 26+) |
|--------------------|-------------------|-------------------|
| Text generation    | ✅                | ✅                 |
| Summarization*     | 🚧 Planned        | 🚧 Planned         |
| Image generation   | 🚧 Planned        | ❌                 |
| Tool call          | ❌                | ❌                 |

*Summarization is achieved through text-generation prompts and shares the same API surface.

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
  flutter_local_ai: 0.0.1-dev.8
```

### Android Setup

Requires Android API level 26 (Android 8.0 Oreo) or higher.

#### Step 1: Configure Minimum SDK Version

Set the minimum SDK version in your `android/app/build.gradle` or `android/app/build.gradle.kts`:

**For `build.gradle.kts` (Kotlin DSL):**
```kotlin
android {
    defaultConfig {
        minSdk = 26 // Required for ML Kit GenAI
    }
    
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    
    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }
}

dependencies {
    implementation("com.google.mlkit:genai-prompt:1.0.0-alpha1")
    implementation("com.google.android.gms:play-services-tasks:18.0.2")
}
```

**For `build.gradle` (Groovy DSL):**
```groovy
android {
    defaultConfig {
        minSdkVersion 26 // Required for ML Kit GenAI
    }
    
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_11
        targetCompatibility JavaVersion.VERSION_11
    }
    
    kotlinOptions {
        jvmTarget = '11'
    }
}

dependencies {
    implementation 'com.google.mlkit:genai-prompt:1.0.0-alpha1'
    implementation 'com.google.android.gms:play-services-tasks:18.0.2'
}
```

#### Step 2: Add AICore Library Declaration

Add the AICore library declaration to your `android/app/src/main/AndroidManifest.xml`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:label="your_app_name"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher">
        
        <!-- Required for ML Kit GenAI -->
        <uses-library android:name="com.google.android.aicore" android:required="false" />
        
        <!-- Your activities here -->
    </application>
</manifest>
```

**Important:** The `android:required="false"` attribute allows your app to run even if AICore is not installed. You should check availability programmatically (see below).

#### Step 3: Sync Your Project

Sync your project with Gradle files:
```bash
flutter pub get
flutter clean
flutter build apk
```

#### Step 4: Understanding Google AICore Requirement

Android's ML Kit GenAI requires **Google AICore** to be installed on the device. AICore is a separate system-level app that provides on-device AI capabilities (similar to Google Play Services).

**What is AICore?**
- A system-level Android app that provides on-device AI capabilities
- Includes Gemini Nano model for local inference
- Not installed by default on all devices
- Available through Google Play Store
- Similar to Google Play Services in how it works

**Error Code -101**: If you encounter error code -101, it means:
- AICore is not installed on the device, OR
- The installed AICore version is too low

**How to Handle AICore Not Installed:**

The plugin provides a helper method to open the Play Store:

```dart
final aiEngine = FlutterLocalAi();

try {
  final isAvailable = await aiEngine.isAvailable();
  if (!isAvailable) {
    print('Local AI is not available on this device');
    // Show user-friendly message
    return;
  }
  
  // Proceed with AI operations
  await aiEngine.initialize(instructions: 'You are a helpful assistant.');
  
} catch (e) {
  // Check if it's an AICore error (error code -101)
  if (e.toString().contains('-101') || e.toString().contains('AICore')) {
    // Show a dialog to the user explaining they need to install AICore
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('AICore Required'),
        content: Text(
          'Google AICore is required for on-device AI features.\n\n'
          'Would you like to install it from the Play Store?'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await aiEngine.openAICorePlayStore();
            },
            child: Text('Install AICore'),
          ),
        ],
      ),
    );
  } else {
    print('Error: $e');
  }
}
```

**Manual Installation:**
Users can manually install AICore from:
- **Play Store**: https://play.google.com/store/apps/details?id=com.google.android.aicore
- **Package Name**: `com.google.android.aicore`

**Important Notes:**
- AICore is currently in limited availability and may not be available on all devices or in all regions
- Always check `isAvailable()` before using AI features
- Provide fallback options in your app when AICore is not available
- The `android:required="false"` in AndroidManifest allows your app to run even without AICore

#### Debugging AICore Issues

If you're getting an AICore error on a device where AICore **IS** installed, the actual problem may be different (model not downloaded, permissions, etc.). The plugin now provides detailed error logging:

**View error details in Android Logcat:**
```bash
adb logcat -s FlutterLocalAi:E
```

The logs will show the actual exception type and error message, helping you identify the real issue. See `DEBUGGING_AICORE.md` for a complete debugging guide.

### iOS Setup

Requires iOS 26.0 or higher.

This plugin uses Swift Package Manager (SPM) for dependency management on iOS. The FoundationModels framework is automatically integrated by Flutter when you build your project.

#### Configuration Steps:

1. Open your iOS project in Xcode:
   - Open `ios/Runner.xcodeproj` in Xcode
   - Select the "Runner" project in the navigator
   - Under "Targets" → "Runner" → "General"
   - Set **Minimum Deployments** → **iOS** to **26.0**

2. In your `ios/Runner.xcodeproj/project.pbxproj`, verify that `IPHONEOS_DEPLOYMENT_TARGET` is set to `26.0`:

```
IPHONEOS_DEPLOYMENT_TARGET = 26.0;
```

3. If you encounter issues with SPM integration:

```bash
cd ios
flutter pub get
flutter clean
flutter build ios
```

### macOS Setup

Requires macOS 26.0 or higher.

The plugin uses Swift Package Manager (SPM) for dependency management on macOS. The FoundationModels framework is automatically integrated by Flutter when you build your project.

#### Configuration Steps:

1. Open your macOS project in Xcode:
   - Open `macos/Runner.xcodeproj` in Xcode
   - Select the "Runner" project in the navigator
   - Under "Targets" → "Runner" → "General"
   - Set **Minimum Deployments** → **macOS** to **26.0**

2. In your `macos/Runner.xcodeproj/project.pbxproj`, verify that `MACOSX_DEPLOYMENT_TARGET` is set to `26.0`:

```
MACOSX_DEPLOYMENT_TARGET = 26.0;
```

3. If you encounter issues with SPM integration:

```bash
cd macos
flutter pub get
flutter clean
flutter build macos
```

## Usage

> **Note:** Text generation is available on iOS 26.0+, macOS 26.0+, and Android API 26+ (requires Google AICore to be installed).

### Basic Usage

```dart
import 'package:flutter_local_ai/flutter_local_ai.dart';

// Initialize the AI engine
final aiEngine = FlutterLocalAi();

// Check if Local AI is available on this device
final isAvailable = await aiEngine.isAvailable();
if (!isAvailable) {
  print('Local AI is not available on this device');
  print('iOS/macOS: Requires iOS 26.0+ or macOS 26.0+');
  print('Android: Requires API 26+ and Google AICore installed');
  return;
}

// Initialize the model with custom instructions
// This is required and creates a LanguageModelSession
await aiEngine.initialize(
  instructions: 'You are a helpful assistant. Provide concise answers.',
);

// Generate text with the simple method (returns just the text string)
final text = await aiEngine.generateTextSimple(
  prompt: 'Write a short story about a robot',
  maxTokens: 200,
);
print(text);
```

### Advanced Usage with Configuration

```dart
import 'package:flutter_local_ai/flutter_local_ai.dart';

final aiEngine = FlutterLocalAi();

// Check availability
if (!await aiEngine.isAvailable()) {
  print('Local AI is not available on this device');
  return;
}

// Initialize with custom instructions
await aiEngine.initialize(
  instructions: 'You are an expert in science and technology. Provide detailed, accurate explanations.',
);

// Generate text with detailed configuration
final response = await aiEngine.generateText(
  prompt: 'Explain quantum computing in simple terms',
  config: const GenerationConfig(
    maxTokens: 300,
    temperature: 0.7,  // Controls randomness (0.0 = deterministic, 1.0 = very random)
    topP: 0.9,         // Nucleus sampling parameter
    topK: 40,          // Top-K sampling parameter
  ),
);

// Access detailed response information
print('Generated text: ${response.text}');
print('Token count: ${response.tokenCount}');
print('Generation time: ${response.generationTimeMs}ms');
```

### Streaming Text Generation (Coming Soon)

Streaming support for real-time text generation is planned for a future release.

### Complete Example

Here's a complete example showing error handling and best practices:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_local_ai/flutter_local_ai.dart';

class LocalAiExample extends StatefulWidget {
  @override
  _LocalAiExampleState createState() => _LocalAiExampleState();
}

class _LocalAiExampleState extends State<LocalAiExample> {
  final aiEngine = FlutterLocalAi();
  bool isInitialized = false;
  String? result;
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _initializeAi();
  }

  Future<void> _initializeAi() async {
    try {
      final isAvailable = await aiEngine.isAvailable();
      if (!isAvailable) {
        setState(() {
          result = 'Local AI is not available on this device. Requires iOS 26.0+ or macOS 26.0+';
        });
        return;
      }

      await aiEngine.initialize(
        instructions: 'You are a helpful assistant. Provide concise and accurate answers.',
      );

      setState(() {
        isInitialized = true;
        result = 'AI initialized successfully!';
      });
    } catch (e) {
      setState(() {
        result = 'Error initializing AI: $e';
      });
    }
  }

  Future<void> _generateText(String prompt) async {
    if (!isInitialized) {
      setState(() {
        result = 'AI is not initialized yet';
      });
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      final response = await aiEngine.generateText(
        prompt: prompt,
        config: const GenerationConfig(
          maxTokens: 200,
          temperature: 0.7,
        ),
      );

      setState(() {
        result = response.text;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        result = 'Error generating text: $e';
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Flutter Local AI')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            ElevatedButton(
              onPressed: isLoading ? null : () => _generateText('Tell me a joke'),
              child: const Text('Generate Joke'),
            ),
            const SizedBox(height: 20),
            if (isLoading)
              const CircularProgressIndicator()
            else if (result != null)
              Text(result!),
          ],
        ),
      ),
    );
  }
}
```

### Platform-Specific Notes

#### iOS & macOS

- **Initialization is required**: You must call `initialize()` before generating text. This creates a `LanguageModelSession` with your custom instructions.
- **Session reuse**: The session is cached and reused for subsequent generation calls until you call `initialize()` again with new instructions.
- **Automatic fallback**: If you don't call `initialize()` explicitly, it will be called automatically with default instructions when you first generate text. However, it's recommended to call it explicitly to set your custom instructions.
- **Model availability**: The FoundationModels framework is automatically available on devices running iOS 26.0+ or macOS 26.0+.

#### Android

- **AICore Required**: Google AICore must be installed on the device for ML Kit GenAI to work
- **Availability Check**: Always call `isAvailable()` before using AI features
- **Error Handling**: Handle error code -101 (AICore not installed) gracefully
- **Initialization**: `initialize()` is optional on Android but recommended for consistency
- **Model Access**: Uses Gemini Nano via ML Kit GenAI - no model downloads required

**Example with AICore Error Handling:**
```dart
final aiEngine = FlutterLocalAi();

try {
  final isAvailable = await aiEngine.isAvailable();
  if (!isAvailable) {
    // Show user-friendly message
    print('Local AI is not available. AICore may not be installed.');
    return;
  }
  
  await aiEngine.initialize(
    instructions: 'You are a helpful assistant.',
  );
  
  final response = await aiEngine.generateText(
    prompt: 'Hello!',
    config: const GenerationConfig(maxTokens: 100),
  );
  
  print(response.text);
} catch (e) {
  // Handle AICore error (-101)
  if (e.toString().contains('-101') || e.toString().contains('AICore')) {
    // Open Play Store to install AICore
    await aiEngine.openAICorePlayStore();
  } else {
    print('Error: $e');
  }
}
```

## API Reference

### `FlutterLocalAi`

Main class for interacting with local AI.

#### Methods

- `Future<bool> isAvailable()` - Check if local AI is available on the device
- `Future<bool> initialize({String? instructions})` - Initialize the model and create a session with instruction text (required for iOS, recommended for Android)
- `Future<AiResponse> generateText({required String prompt, GenerationConfig? config})` - Generate text from a prompt with optional configuration
- `Future<String> generateTextSimple({required String prompt, int maxTokens = 100})` - Convenience method to generate text and return just the string
- `Future<bool> openAICorePlayStore()` - Open Google AICore in the Play Store (Android only, useful when error -101 occurs)

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

The Android implementation uses ML Kit GenAI (Gemini Nano) via Google AICore.

**Key Android Requirements:**
- Android 8.0 (API level 26) or higher
- Google AICore installed on the device
- Java 11 or higher (configured in build.gradle)
- Kotlin JVM target 11

**Android Implementation Details:**
- Uses `com.google.mlkit.genai.prompt.Generation.getClient()` for model access
- Handles AICore availability checking and error detection
- Provides automatic error code -101 detection
- Includes Play Store integration for AICore installation
- Uses coroutines with SupervisorJob for async operations
- Properly manages GenerativeModel lifecycle

**Android Error Handling:**
- Error code -101: AICore not installed or version too low
- Detailed error logging via Android Logcat (`adb logcat -s FlutterLocalAi:E`)
- Graceful degradation when AICore is unavailable

**Android Configuration:**
The plugin automatically registers via Flutter's `GeneratedPluginRegistrant`. No manual registration needed in MainActivity.

### iOS
The iOS implementation uses Apple's FoundationModels framework (iOS 26.0+). The implementation:

- Uses `SystemLanguageModel.default` for model access
- Creates a `LanguageModelSession` with custom instructions
- Handles model availability checking
- Provides on-device text generation with configurable parameters

**Key iOS Requirements:**
- iOS 26.0 or later
- Xcode 16.0 or later
- FoundationModels framework (automatically available on supported devices)

**iOS Initialization:**
On iOS, you must call `initialize()` before generating text. This creates a `LanguageModelSession` with your custom instructions. The session is cached and reused for subsequent generation calls.

```dart
// Required on iOS
await aiEngine.initialize(
  instructions: 'Your custom instructions here',
);
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
