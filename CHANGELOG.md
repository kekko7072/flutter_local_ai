## 0.0.11

### genUI — localized generation
* `LocalAiUiGenerator.generateModule` gains an optional `language` parameter (an
  English language name such as "Italian" or "German"). When set, the prompt
  instructs the on-device model to write all user-facing copy — title, blurb and
  every block label, item and note — in that language, so generated modules match
  the app's locale. Omitting it preserves the previous behaviour.

## 0.0.10

### genUI — reliable generation on Android (Gemini Nano)
* Fixed the "model did not return JSON" failure on Android. Gemini Nano caps
  output at 256 tokens, so a verbose module was being truncated mid-JSON. The
  genUI prompt is now backend-aware: on Android it asks for compact, minified
  JSON with at most 3 blocks and shorter strings, and runs at a lower
  temperature (0.2) for more reliable structure — keeping output well within the
  token budget.
* Made `LocalAiUiGenerator`'s JSON extraction tolerant of small-model quirks: it
  now repairs JSON truncated by the output cap (cutting at the last complete
  block and closing the open brackets) and strips trailing commas (via
  `replaceAllMapped` — `replaceAll` does not expand `$1`), so a partial response
  still renders instead of being discarded.
* Verified end-to-end on a Google Pixel 10 (Android 16, Gemini Nano via AICore):
  multiple goals now produce valid, rendered modules.

### Tests
* Fixed the test suite: updated the platform-interface fake to implement the new
  `availabilityReason()` member, and added regression coverage for
  `LocalAiUiGenerator.parseModelOutput` (clean / fenced / prose / trailing-comma
  / truncated-and-repaired / invalid inputs).

### Generative UI in the example app
* The example app now has a **Generative UI** tab (alongside Text) that turns a
  goal into a rendered on-device module, with backend labelling and a JSON view.

### Platform & docs
* Raised the macOS deployment target (Podfile `10.15` → `12.0`) and refreshed
  dependencies; pins the project to Flutter 3.41.9 via FVM.
* Documented genUI in the README (Platform Support table, a Generative UI usage
  guide, and `LocalAiUiGenerator` / `GenUiModuleSpec` API reference).

## 0.0.9

### genUI reuse
* Exposed `LocalAiUiGenerator.genUiInstructions` (the module/block schema) and
  `LocalAiUiGenerator.parseModelOutput(text)` so any on-device backend (e.g. a
  downloaded Gemma model via flutter_gemma) can drive the same genUI generation.

## 0.0.8

### genUI on Android (Pixel)
* `LocalAiUiGenerator` is now backend-aware and works on Android ML Kit GenAI /
  Gemini Nano (e.g. Google Pixel) as well as Apple FoundationModels — the genUI
  schema is delivered via instructions (prepended to the prompt natively on
  Android), and the output-token budget is tuned per backend.
* Added `availabilityReason` on Android (maps `FeatureStatus` →
  available/downloadable/downloading/unavailable) for accurate UI status.

## 0.0.7

### genUI integration
* Added a `genui` integration so the package can turn a natural-language goal
  into a renderable module spec: `LocalAiUiGenerator` (on-device, via
  FoundationModels) and `GenUiModuleSpec` (typed blocks → `genui` components).
* Added `availabilityReason()` (Dart + Apple native) to report exactly why the
  model is unavailable (e.g. `deviceNotEligible`, Apple Intelligence disabled).

### Apple platforms - Generation fix
* Fixed a FoundationModels `GenerationError` caused by combining `.greedy`
  sampling with a temperature; options are now chosen exclusively. Generation
  failures now surface a fully-reflected, diagnosable error description.

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
