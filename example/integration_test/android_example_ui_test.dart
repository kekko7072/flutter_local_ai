import 'dart:io';

// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_local_ai_example/main.dart' as app;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> exercisePolicy(
    WidgetTester tester, {
    required String policy,
    required String expectedLocation,
    required bool allowAppCheckError,
  }) async {
    if (!Platform.isAndroid) return;
    await tester.pumpWidget(const app.MyApp());
    await tester.pumpAndSettle(const Duration(seconds: 5));

    await tester.tap(find.text('Sessions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(policy));
    await tester.pumpAndSettle();
    expect(find.text('Android Firebase cloud model'), findsOneWidget);

    await tester.ensureVisible(find.text('Open model'));
    await tester.tap(find.text('Open model'));
    await tester.pumpAndSettle(const Duration(seconds: 10));

    final error = find.textContaining('Could not open the model');
    expect(error, findsNothing);
    expect(find.textContaining('Model open'), findsOneWidget);

    final prompt = find.widgetWithText(TextField, 'Prompt for session A');
    await tester.ensureVisible(prompt);
    await tester.enterText(prompt, 'Reply with exactly: ANDROID CLOUD OK');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.ensureVisible(find.text('Send').first);
    await tester.tap(find.text('Send').first);

    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (DateTime.now().isBefore(deadline) &&
        find
            .textContaining('Last response · $expectedLocation')
            .evaluate()
            .isEmpty &&
        find.textContaining('App Check token is invalid').evaluate().isEmpty) {
      await tester.pump(const Duration(milliseconds: 250));
    }

    if (find
        .textContaining('Last response · $expectedLocation')
        .evaluate()
        .isNotEmpty) {
      expect(find.textContaining('Last response'), findsWidgets);
    } else if (allowAppCheckError) {
      expect(find.textContaining('App Check token is invalid'), findsWidgets);
    } else {
      fail('No $expectedLocation response appeared in the example.');
    }
  }

  testWidgets(
    'example cloud policy shows response or App Check error',
    (tester) => exercisePolicy(
      tester,
      policy: 'cloudOnly',
      expectedLocation: 'firebaseAiLogicCloud',
      allowAppCheckError: true,
    ),
    timeout: const Timeout(Duration(minutes: 3)),
  );

  testWidgets(
    'example hybrid policy shows the on-device provider',
    (tester) => exercisePolicy(
      tester,
      policy: 'preferOnDevice',
      expectedLocation: 'onDevice',
      allowAppCheckError: false,
    ),
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
