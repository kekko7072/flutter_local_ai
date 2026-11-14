import 'dart:io';

import 'package:flutter_local_ai/flutter_local_ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Firebase AI Logic cloudOnly returns cloud metadata',
    (tester) async {
      if (!Platform.isAndroid) return;
      final model = await LocalAiModel.create(
        executionPolicy: LocalAiExecutionPolicy.cloudOnly,
        android: const LocalAiAndroidConfiguration(
          cloudModelName: 'gemini-3.5-flash-lite',
        ),
      );
      try {
        final session = await model.openSession();
        try {
          await session.addQueryChunk('Reply with exactly: ANDROID CLOUD OK');
          final result = await session.getResponseWithMetadata();
          expect(
            result.executionLocation,
            LocalAiExecutionLocation.firebaseAiLogicCloud,
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
