# FVM Setup Guide

This project uses FVM (Flutter Version Management) to manage Flutter SDK versions.

## Prerequisites

Install FVM if you haven't already:

```bash
# Using Homebrew (macOS)
brew tap leoafarias/fvm
brew install fvm

# Or using pub (Dart)
dart pub global activate fvm
```

## Initial Setup

1. **Install the Flutter version specified in the config:**
   ```bash
   fvm install
   ```

2. **Use FVM for this project:**
   ```bash
   fvm use
   ```

3. **Verify the Flutter version:**
   ```bash
   fvm flutter --version
   ```

## Daily Usage

After the initial setup, you can use FVM commands:

- **Run Flutter commands:**
  ```bash
  fvm flutter pub get
  fvm flutter run
  fvm flutter build
  ```

- **Or use the FVM alias (if configured):**
  ```bash
  fvm flutter --version
  ```

## Changing Flutter Version

To change the Flutter version for this project:

1. **Update the version in `.fvmrc`:**
   ```json
   {
     "flutter": "3.44.8"
   }
   ```

2. **Install and use the new version:**
   ```bash
   fvm install
   fvm use
   ```

## IDE Configuration

### VS Code

Add to your `.vscode/settings.json`:
```json
{
  "dart.flutterSdkPath": ".fvm/flutter_sdk",
  "search.exclude": {
    "**/.fvm": true
  },
  "files.watcherExclude": {
    "**/.fvm": true
  }
}
```

### Android Studio / IntelliJ

1. Go to `File` > `Settings` > `Languages & Frameworks` > `Flutter`
2. Set the Flutter SDK path to: `.fvm/flutter_sdk`

## Current Configuration

- **Flutter SDK Version:** 3.44.8 (as specified in `.fvmrc`)
- **Minimum Required:** >=3.44.0 / Dart >=3.12.0, inherited from
  `flutter_gemma` 1.8.0, which the engine in `lib/gemma.dart` depends on.
  A version below 3.44 cannot resolve the package.

## What Gets Shared vs. Not Shared

### ✅ **Shared (Committed to Git):**
- `.fvmrc` - The Flutter version specification (e.g., "3.44.8")
- `pubspec.yaml` - Flutter SDK constraints (e.g., `flutter: ">=3.44.0"`)
- Other project-level configs (analysis_options.yaml, etc.)

**This ensures all team members use the same Flutter version.**

### ❌ **NOT Shared (Gitignored):**
- `.fvm/flutter_sdk/` - The actual Flutter SDK binaries (each developer downloads locally)
- `.fvm/.flutter-version` - Internal FVM tracking file
- User-specific Flutter settings (pub cache, IDE settings, etc.)

**Each developer must run `fvm install` to download the Flutter SDK locally.**

## Notes

- The Flutter SDK binaries are NOT shared (too large, platform-specific)
- The Flutter version specification IS shared (ensures team consistency)
- Always use `fvm flutter` commands instead of direct `flutter` commands when working on this project
- When a team member clones the repo, they need to run `fvm install` to get the Flutter SDK
