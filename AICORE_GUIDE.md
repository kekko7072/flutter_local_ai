# Android AICore Error Guide (Error Code -101)

## Understanding the Error

**Error Code -101** means that **Google AICore** is either:
- Not installed on the Android device, OR
- Installed but the version is too low

## What is Google AICore?

Google AICore is a system-level Android app that provides on-device AI capabilities. It's similar to Google Play Services - it runs in the background and enables AI features without requiring apps to bundle large AI models.

### Key Points:
- **Separate Installation**: AICore is not installed by default on all Android devices
- **System-Level App**: It runs as a background service
- **Model Provider**: It includes Gemini Nano for on-device AI inference
- **Limited Availability**: Currently in gradual rollout, not available on all devices/regions

## Solution 1: Programmatic Handling (Recommended)

The plugin now includes a helper method to handle this gracefully:

```dart
import 'package:flutter_local_ai/flutter_local_ai.dart';

final aiEngine = FlutterLocalAi();

try {
  final isAvailable = await aiEngine.isAvailable();
  
  if (!isAvailable) {
    print('Local AI is not available on this device');
    return;
  }
  
  // Proceed with initialization and text generation
  await aiEngine.initialize(
    instructions: 'You are a helpful assistant.',
  );
  
} catch (e) {
  // Check if it's an AICore error
  if (e.toString().contains('-101') || e.toString().contains('AICore')) {
    // Show user a dialog explaining they need AICore
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('AICore Required'),
        content: Text(
          'Google AICore is required for on-device AI but it\'s not '
          'installed or the version is too low.\n\n'
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
              // Open Play Store to install AICore
              await aiEngine.openAICorePlayStore();
            },
            child: Text('Open Play Store'),
          ),
        ],
      ),
    );
  } else {
    print('Error: $e');
  }
}
```

## Solution 2: Manual Installation

Users can manually install AICore from:
- **Play Store**: https://play.google.com/store/apps/details?id=com.google.android.aicore
- **Package Name**: `com.google.android.aicore`

## Implementation Details

### New Method: `openAICorePlayStore()`

This method has been added to the `FlutterLocalAi` class:

```dart
/// Open Google AICore in the Play Store (Android only)
///
/// This is useful when the user gets an error that AICore is not installed
/// or the version is too low (error code -101).
///
/// Returns true if the Play Store was opened successfully
Future<bool> openAICorePlayStore() async {
  // Opens Play Store or browser fallback
}
```

### Android Implementation

The Kotlin plugin automatically:
1. Detects AICore errors (error code -101)
2. Provides helpful error messages
3. Opens the Play Store when `openAICorePlayStore()` is called

## Best Practices

### 1. Check Availability Early
```dart
@override
void initState() {
  super.initState();
  _checkAiAvailability();
}

Future<void> _checkAiAvailability() async {
  try {
    final isAvailable = await aiEngine.isAvailable();
    if (isAvailable) {
      // Proceed with initialization
    } else {
      // Show message to user
    }
  } catch (e) {
    // Handle AICore error
  }
}
```

### 2. Provide Clear User Messaging
Don't just show a technical error. Explain:
- What AICore is
- Why it's needed
- How to install it
- That it's a one-time setup

### 3. Graceful Degradation
Consider providing fallback options:
- Cloud-based AI API fallback
- Limited functionality without AI
- Clear feature availability indicators

### 4. Test on Multiple Devices
AICore availability varies by:
- Device manufacturer
- Android version
- Geographic region
- Google Play Services status

## Device Compatibility

### Supported Devices
- Android 8.0 (API level 26) or higher
- Google Play Services installed
- Sufficient storage space for AICore
- Device supported by Google's rollout plan

### Known Limitations
- Not available on all devices yet (gradual rollout)
- Some regions may have limited availability
- Requires recent Google Play Services version
- Device must meet Google's hardware requirements

## Troubleshooting

### Error Persists After Installing AICore
1. **Restart the app**: AICore may need the app to restart
2. **Update AICore**: Check Play Store for updates
3. **Update Google Play Services**: Ensure it's up to date
4. **Device compatibility**: Verify device is supported

### AICore Not Available in Play Store
- Device may not be supported yet
- Region may not be included in rollout
- Consider implementing fallback solution

### Installation Fails
- Check device storage space
- Verify Google Play Services is working
- Try clearing Play Store cache

## Example Implementation

See the example app (`example/lib/main.dart`) for a complete implementation showing:
- Availability checking with error handling
- User-friendly AICore error dialog
- Play Store integration
- Graceful error recovery

## Additional Resources

- [ML Kit GenAI Documentation](https://developers.google.com/ml-kit/genai/prompt/android)
- [Google AICore on Play Store](https://play.google.com/store/apps/details?id=com.google.android.aicore)
- [Flutter Local AI Package](https://github.com/kekko7072/flutter_local_ai)

## Summary

The AICore -101 error is expected behavior when AICore is not installed. The solution is to:
1. Detect the error gracefully
2. Inform users about AICore
3. Guide them to install it from Play Store
4. Handle the installation flow smoothly

This provides a better user experience than showing cryptic error messages.

