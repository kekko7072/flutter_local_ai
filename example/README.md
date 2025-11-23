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
- **Copilot+ PC** with NPU capable of 40+ TOPS (required)
- Visual Studio 2022 with C++ development tools
- Windows 11 SDK (10.0.26100.0 or later)
- CMake 3.14 or later
- Windows 11 24H2 (build 26100) or later
- **Note**: Windows AI headers need to be configured (see main README for instructions)

**What are Copilot+ PCs?**
Copilot+ PCs are Windows 11 devices with a high-performance Neural Processing Unit (NPU) capable of 40+ trillion operations per second (TOPS). Supported devices include Microsoft Surface Laptop/Pro Copilot+ PC, HP OmniBook X 14, Dell XPS 13, Lenovo Yoga Slim 7x, Samsung Galaxy Book4 Edge, and others. See [Windows AI NPU Devices](https://learn.microsoft.com/en-us/windows/ai/npu-devices/) for the complete list.

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
- On Windows, the app will compile and run, but Windows AI features require:
  - **Copilot+ PC** with NPU capable of 40+ TOPS
  - Windows AI SDK or `Microsoft.Windows.AI.winmd` file
  - Generated C++/WinRT headers (using `cppwinrt.exe`)
  - Headers configured in the plugin's CMakeLists.txt
  - See the main README for detailed setup instructions
- The app will show helpful error messages if Windows AI headers are not configured
- **Windows ML**: The plugin uses Windows ML for NPU acceleration, which automatically detects hardware and downloads required Execution Providers (EPs) via Windows Update
- **Performance**: Windows AI APIs leverage the NPU for optimal performance and battery life. The system automatically selects the best Execution Provider (QNN for Qualcomm, OpenVINO for Intel) and falls back to GPU/CPU if needed
- For more information, see: [Develop AI applications for Copilot+ PCs](https://learn.microsoft.com/en-us/windows/ai/develop-ai-apps-for-copilot-plus-pcs)
