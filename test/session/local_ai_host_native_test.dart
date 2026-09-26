import 'package:flutter/services.dart';
import 'package:flutter_local_ai/flutter_local_ai.dart';
import 'package:flutter_local_ai/src/session/local_ai_host_native.dart';
import 'package:flutter_test/flutter_test.dart';

const _prefix = 'dev.flutter.pigeon.flutter_local_ai.LocalAiService.';

/// Answers pigeon calls to [method] with a platform error, the way a host
/// that throws `FlutterError(code, message)` does.
void _replyWithError(String method, String code, String message) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler(
        '$_prefix$method',
        (_) async => const StandardMessageCodec().encodeMessage(<Object?>[
          code,
          message,
          null,
        ]),
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final method in [
      'generateResponse',
      'generateResponseAsync',
      'generateStructuredResponse',
      'addQueryChunk',
      'closeSession',
    ]) {
      messenger.setMockMessageHandler('$_prefix$method', null);
    }
  });

  group('SESSION_BUSY', () {
    // The web host throws the same type directly; a caller writes one catch.
    Matcher busyOn(int sessionId) => throwsA(
      isA<LocalAiSessionBusyException>()
          .having((e) => e.sessionId, 'sessionId', sessionId)
          .having((e) => e.message, 'message', 'already generating'),
    );

    test('maps on generateResponse', () async {
      _replyWithError('generateResponse', 'SESSION_BUSY', 'already generating');
      await expectLater(NativeLocalAiHost().generateResponse(3), busyOn(3));
    });

    test('maps on generateResponseAsync', () async {
      _replyWithError(
        'generateResponseAsync',
        'SESSION_BUSY',
        'already generating',
      );
      await expectLater(
        NativeLocalAiHost().generateResponseAsync(3),
        busyOn(3),
      );
    });

    test('maps on generateStructuredResponse', () async {
      _replyWithError(
        'generateStructuredResponse',
        'SESSION_BUSY',
        'already generating',
      );
      await expectLater(
        NativeLocalAiHost().generateStructuredResponse(
          sessionId: 3,
          schemaJson: '{}',
        ),
        busyOn(3),
      );
    });

    test('maps on addQueryChunk, which Android also guards', () async {
      _replyWithError('addQueryChunk', 'SESSION_BUSY', 'already generating');
      await expectLater(
        NativeLocalAiHost().addQueryChunk(sessionId: 3, text: 'x'),
        busyOn(3),
      );
    });

    test('leaves every other platform error alone', () async {
      _replyWithError('generateResponse', 'ERROR', 'model failed');
      await expectLater(
        NativeLocalAiHost().generateResponse(3),
        throwsA(
          isA<PlatformException>().having((e) => e.code, 'code', 'ERROR'),
        ),
      );
    });
  });

  test('a failed closeSession propagates to the caller', () async {
    _replyWithError('closeSession', 'ERROR', 'teardown failed');
    await expectLater(
      NativeLocalAiHost().closeSession(3),
      throwsA(isA<PlatformException>()),
    );
  });
}
