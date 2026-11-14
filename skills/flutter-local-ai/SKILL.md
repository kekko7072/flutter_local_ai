---
name: flutter-local-ai
description: Develop, configure, test, or review Flutter apps using flutter_local_ai for Apple Foundation Models/PCC, Android Gemini Nano/Firebase AI Logic hybrid, Windows AI Foundry, or Chrome Prompt API.
---

# flutter_local_ai developer guide

Use this skill when an app needs OS-managed or hybrid AI with no bundled model
checkpoint. Preserve the privacy-safe default: `LocalAiModel.create()` is
`onDeviceOnly`; never opt into cloud inference implicitly.

Read only the references needed for the task:

- API design, sessions, metadata, errors, tests: [references/api-development.md](references/api-development.md)
- Apple setup and PCC entitlement: [references/apple-setup.md](references/apple-setup.md)
- Android AICore and Firebase hybrid setup: [references/android-setup.md](references/android-setup.md)
- Routing, privacy, and product disclosure: [references/routing-and-privacy.md](references/routing-and-privacy.md)

Always query `LocalAi.capabilities()` at runtime. Do not infer capability from
`Platform.isX`, an OS version, or the policy alone. Use
`getResponseWithMetadata()` when the app must know whether a hybrid request was
local or cloud. Keep Android tool calling disabled until the package advertises
`supportsToolCalling`; do not simulate a weaker prompt-based substitute.

0.5.0 cloud support is alpha. Require physical-device validation and explicit
privacy/UI disclosure before treating cloud-capable policies as production
ready.
