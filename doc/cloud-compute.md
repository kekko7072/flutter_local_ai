# Cloud compute alpha

Version 0.5.0 introduces an alpha execution-policy API. Existing calls remain
strictly on-device. Validate cloud behavior on physical devices before release.

## One Dart policy, platform-native providers

| Policy | Apple | Android |
|---|---|---|
| `onDeviceOnly` | SystemLanguageModel only | Gemini Nano through AICore only |
| `cloudOnly` | Private Cloud Compute only | Firebase AI Logic cloud only |
| `preferOnDevice` | system model, then PCC | Nano, then Firebase cloud |
| `preferCloud` | PCC, then system model | Firebase cloud, then Nano when offline |

One request is handled by one provider; platforms may retry it on the fallback
provider. They do not split prompt content between local and cloud. Read
`LocalAiGenerationResult.executionLocation` for the provider that actually
answered a non-streaming request.

## Apple Private Cloud Compute

PCC requires an iOS/macOS 27 SDK and runtime, eligible Apple Intelligence
hardware and region, network access, and Apple's managed
`com.apple.developer.private-cloud-compute` entitlement. Request and add that
entitlement in the host app. Check `privateCloudAvailability`, but still
handle session/generation failure: Apple does not expose an API for an iOS app
to inspect its own signing entitlement. PCC has service, rate, timeout, and
daily per-user quota limits. Physical-device validation is required.

## Android Firebase AI Logic hybrid

Private Compute Core and AICore protect and run Nano locally; they are not a
cloud service. The plugin includes Firebase AI Logic `18.2.0` and the
experimental on-device extension `16.0.0-beta08`. The host app must:

1. Register the Android app in Firebase and add `google-services.json`.
2. Open Firebase Console → AI Logic → Get started to enable the Vertex AI in
   Firebase API (`firebasevertexai.googleapis.com`) for the project. Allow a few
   minutes for activation. Choose the Gemini Developer API or Agent Platform API.
3. Configure Firebase App Check. Use its debug provider only in debug builds,
   register the debug token without committing it, and use Play Integrity or
   another production provider for releases.
4. Initialize Firebase and pass an explicit supported cloud model:

```dart
final model = await LocalAiModel.create(
  executionPolicy: LocalAiExecutionPolicy.preferOnDevice,
  android: const LocalAiAndroidConfiguration(
    cloudModelName: 'gemini-3.5-flash-lite',
  ),
);
```

Firebase Android has no default cloud model. Missing model configuration uses
`ANDROID_CLOUD_MODEL_REQUIRED`; missing Firebase setup uses
`FIREBASE_AI_NOT_CONFIGURED`. Firebase decides per request using the policy,
Nano/model availability, request capabilities, network state, and provider
errors. Hybrid token counts are estimates because local and cloud tokenizers
differ. Android tools remain disabled until callback and result-reinjection
semantics can match Apple. Hybrid streaming currently emits the completed
answer as one chunk while this experimental SDK stabilizes.

## Privacy and product behavior

Before selecting a cloud-capable policy, disclose that prompts may leave the
device and name the provider. Offer `onDeviceOnly` where practical. Avoid
unnecessary secrets or personal data, log routing metadata without prompt
contents, and handle offline, quota, timeout, permission/entitlement, and
unavailable-model errors explicitly.

## Test the example

The example defaults to `onDeviceOnly`, so it runs without cloud setup. Open
the **Sessions** tab, choose a policy, and open the model. Cloud-capable turns
show the actual response location/provider under the session title.

Apple test prerequisites: Xcode/OS 27, eligible hardware and region, Apple
Intelligence enabled, network access, and a signing profile containing the
managed PCC entitlement. Run the opt-in real-service smoke test with:

```bash
cd example
flutter test integration_test/apple_hybrid_smoke_test.dart -d macos
flutter test integration_test/apple_pcc_smoke_test.dart -d macos \
  --dart-define=RUN_PCC_SMOKE=1
```

The test is opt-in so ordinary CI does not depend on a cloud service or
entitlement. A model can report available/open before a signing, network,
quota, or service problem appears on the first generation.

Android test prerequisites: an AICore-supported physical device for local
fallback plus the Firebase project, AI Logic, `google-services.json`, App
Check provider/token, and cloud model described above. Select the policy in
the example and confirm the displayed last-response location. Do not paste an
API key into Dart: Firebase configuration and App Check belong to the native
host app and Firebase console.

On a connected Android device, these tests check the example screen, hybrid
selection, real hybrid routing, and explicit cloud generation respectively:

```bash
cd example
flutter test integration_test/android_example_ui_test.dart -d DEVICE_ID
flutter test integration_test/android_hybrid_smoke_test.dart -d DEVICE_ID \
  --dart-define=RUN_ANDROID_HYBRID_GENERATION=1
flutter test integration_test/android_cloud_smoke_test.dart -d DEVICE_ID
```

Run integration tests sequentially: Flutter shares example build artifacts
between runs. The cloud-only test requires a registered App Check token; the
hybrid test may succeed locally when Nano is available. Reinstalling a debug
app can generate a new App Check token. If Firebase rejects the token during
an integration test, register the token printed by that installed build, or
keep the normal example app installed and retry there without reinstalling.
