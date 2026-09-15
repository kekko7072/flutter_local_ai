// There is no OS model behind a widget test, and the app probes for one as
// soon as it starts. Driving the published fake host keeps that probe from
// hanging on a platform channel nothing answers — the same seam an app's own
// tests would use.

import 'package:flutter_local_ai/flutter_local_ai.dart';
import 'package:flutter_local_ai/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_local_ai_example/main.dart';

void main() {
  late FakeLocalAiHost host;

  setUp(() {
    host = FakeLocalAiHost();
    debugLocalAiHost = host;
  });

  tearDown(() async {
    debugLocalAiHost = null;
    await host.dispose();
  });

  testWidgets('the example offers all three surfaces', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('Generative UI'), findsOneWidget);
    expect(find.text('Text'), findsOneWidget);
    expect(find.text('Sessions'), findsOneWidget);
  });
}
