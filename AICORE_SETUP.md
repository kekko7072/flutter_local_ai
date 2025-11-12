# AICore Setup Guide for Android

## What is AICore?

AICore is Google's system-level component that provides on-device AI capabilities for Android devices. It's required for ML Kit GenAI (Gemini Nano) to function.

## Common Error: -101

If you see error code `-101`, it means:
- AICore is not installed on your device
- AICore version is too low and needs to be updated

## Quick Fix

### 1. Install AICore from Play Store

**Method 1: Direct Link**
Open this link on your Android device:
https://play.google.com/store/apps/details?id=com.google.android.aicore

**Method 2: Search**
1. Open Google Play Store
2. Search for "Google AICore"
3. Install or update to the latest version

### 2. Verify Installation

Connect your device and run:
```bash
adb shell pm list packages | grep aicore
```

Expected output:
```
package:com.google.android.aicore
```

### 3. Check Version

```bash
adb shell dumpsys package com.google.android.aicore | grep versionName
```

### 4. Manual Installation (If Play Store Unavailable)

1. Download AICore APK from a trusted source
2. Install via adb:
   ```bash
   adb install -r google-aicore.apk
   ```

## Device Requirements

✅ **Minimum Requirements:**
- Android 8.0 (API 26) or higher
- Sufficient RAM and storage
- Device supports on-device AI features

❌ **Known Limitations:**
- Most Android emulators don't support AICore
- Some older or low-end devices may not be compatible
- Regional availability may vary

## Testing Your App

### Step 1: Check Availability
```dart
final aiEngine = FlutterLocalAi();
final isAvailable = await aiEngine.isAvailable();

if (!isAvailable) {
  print('AICore not installed - Error -101');
  // Direct user to install AICore
}
```

### Step 2: Handle Errors Gracefully
```dart
try {
  await aiEngine.initialize(
    instructions: 'You are a helpful assistant',
  );
} catch (e) {
  if (e.toString().contains('-101')) {
    // Show dialog to install AICore
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('AICore Required'),
        content: Text('Please install Google AICore from the Play Store to use AI features.'),
        actions: [
          TextButton(
            onPressed: () {
              // Open Play Store
              launch('https://play.google.com/store/apps/details?id=com.google.android.aicore');
            },
            child: Text('Install'),
          ),
        ],
      ),
    );
  }
}
```

## Troubleshooting

### Problem: AICore installed but still getting -101

**Solution:**
1. Update AICore to the latest version
2. Restart your device
3. Clear app cache and data
4. Reinstall your application

### Problem: AICore not available in Play Store

**Solution:**
- AICore may not be available in all regions yet
- Try using a VPN to access different Play Store regions
- Use manual APK installation method

### Problem: Works on one device but not another

**Solution:**
- Different devices have different AICore compatibility
- Check device specifications and Android version
- Some manufacturers may have restrictions

## For Developers

### Adding Error Handling in Your App

Always check `isAvailable()` before using AI features:

```dart
class MyAIService {
  final _aiEngine = FlutterLocalAi();
  
  Future<void> setup() async {
    try {
      final available = await _aiEngine.isAvailable();
      
      if (!available) {
        throw Exception('AICore not available. Please install from Play Store.');
      }
      
      await _aiEngine.initialize(
        instructions: 'Your instructions here',
      );
    } catch (e) {
      // Log error and notify user
      print('AI setup failed: $e');
      rethrow;
    }
  }
}
```

### User Experience Best Practices

1. **Check on App Start**: Verify AICore availability early
2. **Clear Messaging**: Inform users why AICore is needed
3. **Easy Installation**: Provide direct link to Play Store
4. **Graceful Degradation**: Offer alternative features if AI isn't available
5. **Status Indicators**: Show clear status (Available/Not Available/Installing)

## Additional Resources

- [ML Kit GenAI Documentation](https://developers.google.com/ml-kit/genai/prompt/android)
- [Google AICore on Play Store](https://play.google.com/store/apps/details?id=com.google.android.aicore)
- [Flutter Local AI GitHub](https://github.com/kekko7072/flutter_local_ai)

## Support

If you continue to experience issues after following this guide:
1. Check device compatibility
2. Verify Android version (API 26+)
3. Try on a different device
4. Check the issue tracker on GitHub

