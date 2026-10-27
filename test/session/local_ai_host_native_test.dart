import 'package:flutter/services.dart';
import 'package:flutter_local_ai/flutter_local_ai.dart';
import 'package:flutter_local_ai/src/session/local_ai_host_native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Makes the native [method] fail with platform error [code] and
  /// [details].
  void failWith(
    String code, {
    Object? details,
    String method = 'generateResponse',
  }) => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler(
        'dev.flutter.pigeon.flutter_local_ai.LocalAiService.$method',
        (_) async =>
            const StandardMessageCodec().encodeMessage([code, 'msg', details]),
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

  test('still catchable the way 0.2.0 callers caught it', () {
    final e = LocalAiSessionBusyException(3, 'busy');
    expect(e, isA<StateError>());
    expect(
      e,
      isA<PlatformException>().having((e) => e.code, 'code', 'SESSION_BUSY'),
    );
  });

  test('GENERATION_ERROR maps to LocalAiGenerationException', () async {
    failWith(
      'GENERATION_ERROR',
      details: {'errorCode': 9, 'retryDelayMs': 1500},
    );
    await expectLater(
      NativeLocalAiHost().generateResponse(3),
      throwsA(
        isA<LocalAiGenerationException>()
            .having((e) => e.errorCode, 'errorCode', 9)
            .having(
              (e) => e.retryDelay,
              'retryDelay',
              const Duration(milliseconds: 1500),
            )
            .having((e) => e.message, 'message', 'msg'),
      ),
    );
  });

  test('an Apple error case name comes through as the error code', () async {
    failWith('GENERATION_ERROR', details: {'errorCode': 'rateLimited'});
    await expectLater(
      NativeLocalAiHost().generateResponse(3),
      throwsA(
        isA<LocalAiGenerationException>()
            .having((e) => e.errorCode, 'errorCode', 'rateLimited')
            .having((e) => e.retryDelay, 'retryDelay', isNull),
      ),
    );
  });

  test(
    'a GENERATION_ERROR without details (Windows) has no error code',
    () async {
      failWith('GENERATION_ERROR');
      await expectLater(
        NativeLocalAiHost().generateResponse(3),
        throwsA(
          isA<LocalAiGenerationException>().having(
            (e) => e.errorCode,
            'errorCode',
            isNull,
          ),
        ),
      );
    },
  );

  test('structured generation maps GENERATION_ERROR too', () async {
    failWith(
      'GENERATION_ERROR',
      details: {'errorCode': 27},
      method: 'generateStructuredResponse',
    );
    await expectLater(
      NativeLocalAiHost().generateStructuredResponse(
        sessionId: 3,
        schemaJson: '{}',
      ),
      throwsA(
        isA<LocalAiGenerationException>().having(
          (e) => e.errorCode,
          'errorCode',
          27,
        ),
      ),
    );
  });

  test('LocalAiGenerationException is still a PlatformException', () {
    final e = LocalAiGenerationException(
      'busy',
      errorCode: 9,
      retryDelay: const Duration(seconds: 2),
    );
    expect(
      e,
      isA<PlatformException>()
          .having((e) => e.code, 'code', 'GENERATION_ERROR')
          .having((e) => e.details, 'details', {
            'errorCode': 9,
            'retryDelayMs': 2000,
          }),
    );
  });

  group('streamed errors', () {
    const events = EventChannel('flutter_local_ai_events');

    /// Plays one native event on the shared events channel.
    void emitNative(Map<String, Object?> event) =>
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockStreamHandler(
              events,
              MockStreamHandler.inline(
                onListen: (_, sink) => sink.success(event),
              ),
            );

    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(events, null),
    );

    test('carry the error code and retry delay', () async {
      emitNative({
        'code': 'ERROR',
        'sessionId': 3,
        'message': 'busy',
        'errorCode': 9,
        'retryDelayMs': 1500,
      });
      expect(
        await NativeLocalAiHost().events.first,
        isA<LocalAiErrorEvent>()
            .having((e) => e.sessionId, 'sessionId', 3)
            .having((e) => e.errorCode, 'errorCode', 9)
            .having(
              (e) => e.retryDelay,
              'retryDelay',
              const Duration(milliseconds: 1500),
            ),
      );
    });

    test('a zero retry delay means none', () async {
      emitNative({
        'code': 'ERROR',
        'sessionId': 3,
        'message': 'busy',
        'errorCode': 9,
        'retryDelayMs': 0,
      });
      expect(
        await NativeLocalAiHost().events.first,
        isA<LocalAiErrorEvent>().having(
          (e) => e.retryDelay,
          'retryDelay',
          isNull,
        ),
      );
    });

    test('without a code stay code-less', () async {
      emitNative({'code': 'ERROR', 'sessionId': 3, 'message': 'boom'});
      expect(
        await NativeLocalAiHost().events.first,
        isA<LocalAiErrorEvent>()
            .having((e) => e.errorCode, 'errorCode', isNull)
            .having((e) => e.retryDelay, 'retryDelay', isNull),
      );
    });
  });

  test('other platform errors pass through', () async {
    failWith('ERROR');
    await expectLater(
      NativeLocalAiHost().generateResponse(3),
      throwsA(isA<PlatformException>()),
    );
  });

  group('tokenLimit', () {
    /// Makes the native `tokenLimit` answer [limit].
    void answer(int? limit) => TestDefaultBinaryMessengerBinding
        .instance
        .defaultBinaryMessenger
        .setMockMessageHandler(
          'dev.flutter.pigeon.flutter_local_ai.LocalAiService.tokenLimit',
          (_) async => const StandardMessageCodec().encodeMessage([limit]),
        );

    test('passes the native limit through', () async {
      answer(4096);
      expect(await NativeLocalAiHost().tokenLimit(sessionId: 3), 4096);
    });

    test('is null where the host reports none', () async {
      answer(null);
      expect(await NativeLocalAiHost().tokenLimit(sessionId: 3), isNull);
    });

    test('a native failure reaches the caller', () async {
      failWith('GenAiException', method: 'tokenLimit');
      await expectLater(
        NativeLocalAiHost().tokenLimit(sessionId: 3),
        throwsA(isA<PlatformException>()),
      );
    });
  });
}
