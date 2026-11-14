# Apple setup

The plugin retains iOS 13 and macOS 12 deployment floors. Foundation Models
requires eligible Apple Intelligence hardware, enabled Apple Intelligence,
ready model assets, and OS 26+. Build with Xcode 26+; PCC requires an OS 27 SDK
and iOS/macOS 27 runtime.

`cloudOnly` uses `PrivateCloudComputeLanguageModel`. `preferOnDevice` tries
`SystemLanguageModel` then PCC. `preferCloud` tries PCC then the system model.
Request Apple's managed `com.apple.developer.private-cloud-compute` entitlement
and sign the app with it. There is no public API for an iOS app to inspect its
own managed entitlement, so check `privateCloudAvailability` for preflight and
still handle a signing/configuration failure when creating or using a session.

PCC needs connectivity and is subject to service availability, rate limits,
timeouts, and daily per-user quota. The plugin maps these to stable generation
error codes. Validate on a physical eligible device; simulator/build success
does not validate entitlement or service access.
