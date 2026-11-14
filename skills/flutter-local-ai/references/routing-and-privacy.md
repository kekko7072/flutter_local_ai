# Routing and privacy

No policy splits one prompt between local and cloud. A request is attempted on
one provider and may be retried on the fallback provider when policy permits.

| Policy | Apple | Android |
|---|---|---|
| `onDeviceOnly` | system model only | AICore/Nano only |
| `cloudOnly` | PCC only | Firebase cloud only |
| `preferOnDevice` | system model, then PCC | Nano, then Firebase cloud |
| `preferCloud` | PCC, then system model | Firebase cloud, then Nano when offline |

Apple's PCC model availability and entitlement govern routing. Firebase also
considers Nano availability, request capability (for example input too large
or unsupported), the configured cloud model, network state, and service
errors. Read `LocalAiGenerationResult.executionLocation` after every request
that needs an audit trail.

Before a cloud-capable policy, tell users that input may leave the device and
identify the provider. Offer `onDeviceOnly` where practical. Avoid sending
secrets or unnecessary personal data, follow platform privacy disclosures,
and log the location/provider without logging prompt contents. Treat 0.5.0
cloud routing as alpha until validated on representative physical devices.
