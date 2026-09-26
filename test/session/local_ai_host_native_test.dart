import 'package:flutter/services.dart';
import 'package:flutter_local_ai/flutter_local_ai.dart';
import 'package:flutter_local_ai/src/session/local_ai_host_native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Makes the native generateResponse fail with platform error [code].
  void failWith(String code) => TestDefaultBinaryMessengerBinding
      .instance
      .defaultBinaryMessenger
      .setMockMessageHandler(
        'dev.flutter.pigeon.flutter_local_ai.LocalAiService.generateResponse',
        (_) async =>
            const StandardMessageCodec().encodeMessage([code, 'msg', null]),
      );

  test('SESSION_BUSY maps to LocalAiSessionBusyException', () async {
    failWith('SESSION_BUSY');
    await expectLater(
      NativeLocalAiHost().generateResponse(3),
      throwsA(
        isA<LocalAiSessionBusyException>().having((e) => e.sessionId, 'id', 3),
      ),
    );
  });

  test('other platform errors pass through', () async {
    failWith('ERROR');
    await expectLater(
      NativeLocalAiHost().generateResponse(3),
      throwsA(isA<PlatformException>()),
    );
  });
}
