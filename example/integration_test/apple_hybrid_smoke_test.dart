import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_local_ai/flutter_local_ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  for (final policy in [
    LocalAiExecutionPolicy.onDeviceOnly,
    LocalAiExecutionPolicy.preferOnDevice,
  ]) {
    testWidgets('Apple $policy reports its actual execution location', (
      tester,
    ) async {
      if (!Platform.isIOS && !Platform.isMacOS) return;
      final availability = await LocalAi.availability();
      if (availability != LocalAiAvailability.available) {
        if (policy == LocalAiExecutionPolicy.onDeviceOnly) {
          await expectLater(
            LocalAiModel.create(executionPolicy: policy),
            throwsA(
              isA<PlatformException>().having(
                (error) => error.code,
                'code',
                'ON_DEVICE_MODEL_UNAVAILABLE',
              ),
            ),
          );
          return;
        } else {
          final caps = await LocalAi.capabilities();
          if (caps.privateCloudAvailability !=
              LocalAiPrivateCloudAvailability.available) {
            await expectLater(
              LocalAiModel.create(executionPolicy: policy),
              throwsA(isA<PlatformException>()),
            );
            return;
          }
        }
      }
      final model = await LocalAiModel.create(executionPolicy: policy);
      try {
        final session = await model.openSession();
        try {
          await session.addQueryChunk('Reply with exactly: APPLE LOCAL OK');
          final result = await session.getResponseWithMetadata();
          expect(result.text, isNotEmpty);
          expect(
            result.executionLocation,
            availability == LocalAiAvailability.available
                ? LocalAiExecutionLocation.onDevice
                : LocalAiExecutionLocation.privateCloudCompute,
          );
        } finally {
          await session.close();
        }
      } finally {
        await model.close();
      }
    }, timeout: const Timeout(Duration(minutes: 3)));
  }
}
