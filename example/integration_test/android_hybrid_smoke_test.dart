import 'dart:io';

import 'package:flutter_local_ai/flutter_local_ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android hybrid exposes configured policy and selection', (
    tester,
  ) async {
    if (!Platform.isAndroid) return;
    final caps = await LocalAi.capabilities();
    final availability = await LocalAi.availability();
    expect(caps.apiName, isNotEmpty);
    // ignore: avoid_print
    print('Android on-device availability: ${availability.name}');

    final model = await LocalAiModel.create(
      executionPolicy: LocalAiExecutionPolicy.preferOnDevice,
      android: const LocalAiAndroidConfiguration(
        cloudModelName: 'gemini-3.5-flash-lite',
      ),
    );
    try {
      expect(model.executionPolicy, LocalAiExecutionPolicy.preferOnDevice);
      expect(model.executionLocation, LocalAiExecutionLocation.undetermined);
      expect(model.provider, contains('Firebase AI Logic hybrid'));
    } finally {
      await model.close();
    }
  });

  testWidgets('Android hybrid reports the provider used for a response', (
    tester,
  ) async {
    if (!Platform.isAndroid ||
        const String.fromEnvironment('RUN_ANDROID_HYBRID_GENERATION') != '1') {
      return;
    }
    final model = await LocalAiModel.create(
      executionPolicy: LocalAiExecutionPolicy.preferOnDevice,
      android: const LocalAiAndroidConfiguration(
        cloudModelName: 'gemini-3.5-flash-lite',
      ),
    );
    try {
      final session = await model.openSession();
      try {
        await session.addQueryChunk('Reply with exactly: HYBRID OK');
        final result = await session.getResponseWithMetadata();
        expect(result.text, isNotEmpty);
        expect(
          result.executionLocation,
          isIn([
            LocalAiExecutionLocation.onDevice,
            LocalAiExecutionLocation.firebaseAiLogicCloud,
          ]),
        );
        // This is the decisive observation: the hybrid SDK picks the route
        // for each response, so report the returned location and provider.
        // ignore: avoid_print
        print(
          'Android hybrid route: ${result.executionLocation.name} '
          '(${result.provider})',
        );
      } finally {
        await session.close();
      }
    } finally {
      await model.close();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
