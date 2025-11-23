# flutter_local_ai_example

Example application demonstrating the usage of the `flutter_local_ai` package.

## Supported Platforms

This example app supports:
- **Android** (API 26+, requires Google AICore)
- **iOS** (iOS 26.0+)
- **macOS** (macOS 26.0+)
- **Windows** (Windows 11 22H2+, build 22621 or later)

## Getting Started

### Prerequisites

- Flutter SDK (>=3.19.0)
- Dart SDK (>=3.0.0)

### Platform-Specific Requirements

#### Android
- Android Studio or Android SDK
- Minimum SDK version: 26
- Google AICore installed on device (or emulator with Play Store)

#### iOS/macOS
- Xcode 16.0 or later
- iOS 26.0+ / macOS 26.0+ deployment target

#### Windows
- Visual Studio 2022 with C++ development tools
- Windows 11 SDK (10.0.22621.0 or later)
- CMake 3.14 or later
- Windows 11 22H2 (build 22621) or later

### Running the Example

1. Get dependencies:
   ```bash
   flutter pub get
   ```

2. Run on your preferred platform:
   ```bash
   # Android
   flutter run -d android
   
   # iOS
   flutter run -d ios
   
   # macOS
   flutter run -d macos
   
   # Windows
   flutter run -d windows
   ```

## Features Demonstrated

- Checking AI availability on the device
- Initializing the AI model with custom instructions
- Generating text with configurable parameters
- Error handling for platform-specific issues (e.g., AICore on Android)
- UI feedback for initialization and generation states

## Notes

- On Android, if AICore is not installed, the app will show a dialog to open the Play Store
- On iOS/macOS, initialization is required before generating text
- On Windows, the AI API integration is in progress - the structure is ready for full implementation
