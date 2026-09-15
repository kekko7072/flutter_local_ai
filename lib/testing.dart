/// Test doubles for code built on flutter_local_ai.
///
/// Kept out of the main library so production code never pulls a fake in by
/// accident:
///
/// ```dart
/// import 'package:flutter_local_ai/testing.dart';
/// ```
///
/// There is no OS model behind `flutter test` on any platform, so without a
/// substitute host every AI path in an app is untestable. Install one with
/// `debugLocalAiHost`, which the main library exports.
library;

export 'src/testing/fake_local_ai_host.dart';
