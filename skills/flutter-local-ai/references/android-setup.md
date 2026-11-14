# Android setup

Use minSdk 26, Kotlin 2.3.21, JVM 11, and the current compiler options DSL.
AICore/Private Compute Core runs Gemini Nano locally; it is not a cloud service.

Cloud and hybrid policies use Firebase AI Logic. The host app must register
with Firebase, include `google-services.json`, enable AI Logic, initialize
Firebase, and configure Firebase App Check. Use the App Check debug provider
only in debug builds and register its token without committing it. Use Play
Integrity or another production attestation provider for releases.

Always pass an explicit cloud model:

```dart
android: const LocalAiAndroidConfiguration(
  cloudModelName: 'gemini-3.5-flash-lite',
)
```

Firebase Android has no default cloud model. Missing model configuration is
`ANDROID_CLOUD_MODEL_REQUIRED`; missing Firebase initialization is
`FIREBASE_AI_NOT_CONFIGURED`. Android hybrid is experimental and the vendor
API is single-turn; flutter_local_ai replays its transcript. Function calling
remains unsupported because tools do not provide Apple-equivalent local
callback and reinjection semantics.
