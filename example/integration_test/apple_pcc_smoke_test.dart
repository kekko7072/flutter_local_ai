import 'dart:io';

// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_ai_example/main.dart' as app;
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('cloudOnly generates through Apple Private Cloud Compute', (
    tester,
  ) async {
    if (!Platform.isMacOS ||
        Platform.environment['FLUTTER_LOCAL_AI_RUN_PCC_SMOKE'] != '1') {
      return;
    }

    await tester.pumpWidget(const app.MyApp());
    await tester.pumpAndSettle(const Duration(seconds: 5));

    await tester.tap(find.text('Sessions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('cloudOnly'));
    await tester.tap(find.text('Open model'));
    await tester.pumpAndSettle(const Duration(seconds: 10));

    expect(find.textContaining('Apple Private Cloud Compute'), findsOneWidget);

    final prompt = find.byType(TextField).first;
    await tester.ensureVisible(prompt);
    await tester.enterText(prompt, 'Reply with exactly: PCC OK');
    final send = find.text('Send').first;
    await tester.ensureVisible(send);
    await tester.tap(send);

    final deadline = DateTime.now().add(const Duration(seconds: 90));
    while (DateTime.now().isBefore(deadline) &&
        find
            .textContaining('Last response · privateCloudCompute')
            .evaluate()
            .isEmpty) {
      await tester.pump(const Duration(milliseconds: 250));
    }

    if (find
        .textContaining('Last response · privateCloudCompute')
        .evaluate()
        .isEmpty) {
      final visibleText = tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data)
          .whereType<String>()
          .where((text) => text.contains('Session A:'));
      fail('PCC did not answer. Example errors: ${visibleText.join(' | ')}');
    }

    expect(
      find.textContaining('Last response · privateCloudCompute'),
      findsOneWidget,
    );
    expect(find.textContaining('PCC OK'), findsWidgets);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
