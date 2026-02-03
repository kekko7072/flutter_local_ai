## 0.0.6

### Android - Availability & Dependencies
* Added `genai-common` dependency to align with updated ML Kit GenAI APIs. (Contributed by [kaitotokyo](https://github.com/kaitotokyo))
* Fixed availability checks by using `Generation.getClient()` and `FeatureStatus`/`GenAiException` from `genai-common`, with improved AICore incompatible handling. (Contributed by [kaitotokyo](https://github.com/kaitotokyo))
* Made generation config parsing safer and only apply `maxOutputTokens`/`temperature` when provided. (Contributed by [kaitotokyo](https://github.com/kaitotokyo))

## 0.0.5

### Apple platforms - Thread Safety
* Introduced a `ModelManager` actor for thread-safe FoundationModels access, session initialization, tool registration, and text generation. (Contributed by [kaitotokyo](https://github.com/kaitotokyo))

### Android - Availability Check
* Improved availability checks using `FeatureStatus`, better `GenAiException` handling, and ensured the model client is closed. (Contributed by [kaitotokyo](https://github.com/kaitotokyo))
* Updated AICore/MLKit incompatibility error message for clarity. (Contributed by [kaitotokyo](https://github.com/kaitotokyo))

## 0.0.4

### Apple platforms - Improvements 
* Lowered iOS and macOS deployment targets to allow plugin compilation on older OS versions; runtime still reports unsupported below 26.0.


## 0.0.3

### Apple platforms - Tool Support
* ✅ **Tools API support (iOS & macOS only)** - Added support for tool execution on Apple platforms; Android and Windows tooling support is planned

## 0.0.2

### Windows - Initial Support
* ✅ **Added Windows platform support** - Initial implementation structure for Windows AI APIs (Windows AI Foundry)
* ✅ **Windows plugin structure** - Created C++/WinRT plugin implementation with method channel handlers
* ✅ **Windows version checking** - Added availability check for Windows 11 22H2 (build 22621) or later
* ✅ **CMake build configuration** - Added Windows CMakeLists.txt for plugin compilation
* ✅ **Example app Windows support** - Added Windows platform to example app
* ✅ **Documentation updates** - Added Windows setup instructions and platform-specific notes to README

### Improvements
* Updated package description to include Windows AI APIs
* Added Windows to platform support table
* Comprehensive Windows implementation documentation

### Status
* Windows AI API integration structure is in place and ready for full implementation
* Plugin provides availability checking, initialization flow, and error handling
* Ready for Windows AI Foundry API integration when APIs become available

## 0.0.1-dev.9

### Android - Complete Implementation
* ✅ **Completed Android support** - Full working implementation using ML Kit GenAI (Gemini Nano)
* ✅ **Improved FlutterLocalAiPlugin.kt** - Enhanced with proper context management, coroutine scope handling, and error detection
* ✅ **Java 11 support** - Updated build.gradle to require Java 11 (required for ML Kit GenAI)
* ✅ **AICore integration** - Added proper AICore library declaration and error handling
* ✅ **Play Store integration** - Added `openAICorePlayStore()` method to help users install AICore
* ✅ **Enhanced error handling** - Improved error code -101 detection and user-friendly error messages
* ✅ **Dependencies** - Added `play-services-tasks:18.0.2` dependency
* ✅ **Example app updates** - Added AICore library declaration and dependencies to example app
* ✅ **Comprehensive documentation** - Updated README.md with complete Android setup instructions, AICore handling guide, and code examples

### Improvements
* Better token counting (filtering empty strings)
* Improved Play Store opening logic with proper activity resolution
* Proper cleanup in `onDetachedFromEngine` (canceling coroutine scope)
* Enhanced logging for debugging AICore issues

### Documentation
* Complete Android setup guide with step-by-step instructions
* AICore requirement explanation and handling examples
* Platform-specific usage examples
* Error handling best practices
* Updated platform support table (Android now shows ✅)

## 0.0.1-dev.8
* Wip on Android
* First usage of AICore 

## 0.0.1-dev.7
* Added support to macOS
* Migrated to Swift Package Manager

## 0.0.1-dev.6

* Enhanced documentation

## 0.0.1-dev.5

* Improved Android logic

## 0.0.1-dev.4

* Improved iOS logic

## 0.0.1-dev.3

* Enhanced documentation

## 0.0.1-dev.2

* Added development warning

## 0.0.1-dev.1

* Initial beta release
* Android implementation using ML Kit GenAI
* iOS implementation structure (placeholder for Apple GenAI API)
* Dart API for text generation
* Example app included
* Comprehensive test suite
