import 'dart:io';

import 'package:flutter_local_ai/flutter_local_ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Apple PCC cloudOnly returns cloud metadata',
    (tester) async {
      if (!Platform.isMacOS && !Platform.isIOS) return;
      if (const String.fromEnvironment('RUN_PCC_SMOKE') != '1') return;

      final model = await LocalAiModel.create(
        executionPolicy: LocalAiExecutionPolicy.cloudOnly,
      );
      try {
        final session = await model.openSession();
        try {
          await session.addQueryChunk('Reply with exactly: PCC OK');
          final result = await session.getResponseWithMetadata();
          expect(
            result.executionLocation,
            LocalAiExecutionLocation.privateCloudCompute,
          );
          expect(result.text, isNotEmpty);
        } finally {
          await session.close();
        }
      } finally {
        await model.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
