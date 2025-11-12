# Debugging AICore Issues on Android

## Problem: False Positive AICore Error

If you're getting an AICore error on a device where AICore **IS** installed, this guide will help you debug the actual issue.

## What Changed

### Improved Error Detection

The plugin now:
1. ✅ **Logs detailed error information** to Android Logcat
2. ✅ **Only triggers AICore error for actual -101 error codes**
3. ✅ **Shows real error messages** for other issues
4. ✅ **Uses precise error code extraction** instead of string matching

### Previous Problem

The old code was:
```kotlin
if (errorMessage.contains("-101") || errorMessage.contains("AICore")) {
  // Triggered for ANY error mentioning these strings
}
```

This would trigger false positives if:
- Any error message happened to contain "AICore" or "-101"
- The actual problem was something else (model not downloaded, permissions, etc.)

### New Solution

Now it extracts the actual numeric error code:
```kotlin
val errorCode = extractErrorCode(errorMessage)
if (errorCode == -101) {  // Only exact -101 match
  // Show AICore installation message
}
```

## How to Debug

### Step 1: View Android Logcat

The plugin now logs detailed error information. To view it:

**Using Android Studio:**
1. Open Android Studio
2. Run your app on the device
3. Open the **Logcat** tab at the bottom
4. Filter by tag: `FlutterLocalAi`
5. Try the action that causes the error
6. Look for error logs with full exception details

**Using Command Line:**
```bash
# View logs in real-time
adb logcat -s FlutterLocalAi:E

# Or view all logs and filter
adb logcat | grep FlutterLocalAi
```

### Step 2: Identify the Real Error

Look for log entries like:
```
E/FlutterLocalAi: checkAvailability error: IllegalStateException - Model not downloaded
E/FlutterLocalAi: initializeModel error: SecurityException - Permission denied
E/FlutterLocalAi: generateText error: TimeoutException - Request timed out
```

The log will show:
- **Exception type** (e.g., IllegalStateException, SecurityException)
- **Error message** (the actual problem)
- **Full stack trace** (where it happened)

### Common Real Errors (Not AICore)

#### 1. Model Not Downloaded
```
Error: Model not downloaded or not available
```

**Solution:** 
- The Gemini Nano model may need to be downloaded by AICore
- This can take time after installing AICore
- Go to Settings > Google > Google AI and check model status

#### 2. Permission Issues
```
Error: Permission denied
```

**Solution:**
- Check app permissions
- AICore may need specific permissions
- Try: Settings > Apps > AICore > Permissions

#### 3. Service Not Ready
```
Error: Service not ready or binding failed
```

**Solution:**
- AICore service might be starting up
- Restart the device
- Wait a few minutes after installing AICore

#### 4. Device Not Supported
```
Error: Device not supported or feature not available
```

**Solution:**
- Some devices/Android versions may not support all features
- Check device compatibility
- Ensure Android version is recent enough

## Step 3: Test the Fix

1. **Clean and rebuild your app:**
```bash
cd example
flutter clean
flutter pub get
flutter run
```

2. **Try the AI operation** that was failing

3. **Check Logcat** for the detailed error

4. **You should now see:**
   - ✅ Detailed error logs in Logcat
   - ✅ Accurate error messages (not false AICore warnings)
   - ✅ Only see AICore error if it's actually error code -101

## Example Logcat Output

### Actual -101 Error (AICore issue):
```
E/FlutterLocalAi: checkAvailability error: RemoteException - Error code: -101
```
**Result:** Shows AICore installation dialog ✅

### Other Errors (Not AICore):
```
E/FlutterLocalAi: initializeModel error: IllegalStateException - Model not ready
```
**Result:** Shows actual error message, no AICore dialog ✅

## Checking AICore Status

### Method 1: Settings
```
Settings > Google > Google AI
```
Look for:
- AICore status
- Model download status
- Available features

### Method 2: Package Manager
```bash
# Check if AICore is installed
adb shell pm list packages | grep aicore

# Should show:
# package:com.google.android.aicore
```

### Method 3: App Info
```bash
# Get detailed AICore info
adb shell dumpsys package com.google.android.aicore
```

## Still Having Issues?

If AICore is installed but still not working:

### 1. Update Everything
```bash
# Check for AICore updates in Play Store
# Or via command line:
adb shell am start -a android.intent.action.VIEW -d "market://details?id=com.google.android.aicore"
```

### 2. Clear AICore Data
```bash
adb shell pm clear com.google.android.aicore
```
Then reinstall/restart AICore

### 3. Check Google Play Services
AICore depends on Google Play Services:
```bash
adb shell pm list packages | grep gms
```

### 4. Device Logs
Get full device logs:
```bash
adb logcat > device_logs.txt
```
Then search for "aicore", "mlkit", or "genai"

## Sharing Debug Information

If you need help, share:
1. **Device model and Android version**
2. **AICore version** (from Play Store or package info)
3. **Logcat output** with FlutterLocalAi errors
4. **Full error message** from the app

## Summary of Changes

| Before | After |
|--------|-------|
| Checked if error contains "-101" string | Extracts actual numeric error code |
| No logging | Detailed error logging to Logcat |
| Generic error messages | Specific error messages per issue |
| False positives | Accurate error detection |

## Next Steps

1. ✅ Run your app
2. ✅ Check Logcat when error occurs
3. ✅ Share the actual error message if you need help
4. ✅ The error should now be accurate!

The false AICore error should be fixed now. You'll see the **real** error message that explains what's actually wrong on your Samsung device.

