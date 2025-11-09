import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_ai_example/main.dart';

void main() {
  testWidgets('Flutter Local AI Example smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    // Verify that the app title is displayed
    expect(find.text('Flutter Local AI Example'), findsOneWidget);

    // Verify that the availability check UI is present
    expect(find.text('Local AI is available'), findsOneWidget);

    // Verify that the prompt text field is present
    expect(find.byType(TextField), findsOneWidget);

    // Verify that the generate button is present
    expect(find.text('Generate Text'), findsOneWidget);
  });

  testWidgets('User can enter prompt and tap generate', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    // Find the text field and enter text
    final textField = find.byType(TextField);
    expect(textField, findsOneWidget);

    await tester.enterText(textField, 'Test prompt');
    await tester.pump();

    // Verify text was entered
    expect(find.text('Test prompt'), findsOneWidget);

    // Find and tap the generate button
    final generateButton = find.text('Generate Text');
    expect(generateButton, findsOneWidget);

    await tester.tap(generateButton);
    await tester.pump();

    // Note: Actual generation will fail in tests without platform channels
    // This test verifies the UI interaction works
  });
}
