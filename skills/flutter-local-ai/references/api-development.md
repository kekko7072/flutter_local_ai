# API development

Use `FlutterLocalAi` for the simple facade and `LocalAiModel` /
`LocalAiSession` for explicit lifecycle, concurrent conversations, images,
cancellation, token information, and execution policies.

```dart
final caps = await LocalAi.capabilities();
final model = await LocalAiModel.create(
  executionPolicy: LocalAiExecutionPolicy.preferOnDevice,
  android: const LocalAiAndroidConfiguration(
    cloudModelName: 'gemini-3.5-flash-lite',
  ),
);
final session = await model.openSession(systemInstruction: 'Be concise.');
try {
  await session.addQueryChunk('Explain the result.');
  final result = await session.getResponseWithMetadata();
  print('${result.executionLocation}: ${result.text}');
} finally {
  await session.close();
  await model.close();
}
```

Policies are `onDeviceOnly`, `cloudOnly`, `preferOnDevice`, and `preferCloud`.
The default never uses a network model. Model/session location is an initial
selection; response metadata is authoritative for hybrid requests.

Gate vision, structured output, tools, and exact token counting on capabilities.
Android tools are unsupported. Hybrid token counts use an estimate because
local and cloud tokenizers differ. Test app logic with `FakeLocalAiHost` and
configure `policySelections`; assert policy, fallback, provider, and response
location. Catch `LocalAiGenerationException` and branch on stable `errorCode`,
not message text.
