import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_local_ai/flutter_local_ai.dart';
import 'package:flutter_local_ai/testing.dart';
import 'package:flutter_test/flutter_test.dart';

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

  Future<LocalAiModel> newModel({bool supportImage = false}) =>
      LocalAiModel.create(supportImage: supportImage, host: host);

  group('sessions', () {
    test('each session gets a distinct id, never reused after close', () async {
      final model = await newModel();
      final first = await model.openSession();
      await first.close();
      final second = await model.openSession();

      expect(first.sessionId, 1);
      // A recycled id would let a late event from `first` land on `second`.
      expect(second.sessionId, 2);
    });

    test('chunks accumulate into one turn', () async {
      final model = await newModel();
      final session = await model.openSession();

      await session.addQueryChunk('Hello ');
      await session.addQueryChunk('world');

      expect(host.session(session.sessionId)!.transcript.toString(),
          'Hello world');
    });

    test('a closed session refuses further work', () async {
      final model = await newModel();
      final session = await model.openSession();
      await session.close();

      expect(session.isClosed, isTrue);
      expect(() => session.addQueryChunk('x'), throwsStateError);
      expect(session.getResponse, throwsStateError);
    });

    test('close is idempotent', () async {
      final model = await newModel();
      final session = await model.openSession();

      await session.close();
      await session.close();

      expect(host.closedIds.where((id) => id == session.sessionId).length, 1);
    });

    test('closing the model closes every open session', () async {
      final model = await newModel();
      final a = await model.openSession();
      final b = await model.openSession();

      await model.close();

      expect(host.closedIds, containsAll([a.sessionId, b.sessionId]));
      expect(host.modelClosed, isTrue);
      expect(model.sessions, isEmpty);
    });

    test('a closed model refuses new sessions', () async {
      final model = await newModel();
      await model.close();

      expect(model.openSession, throwsStateError);
    });
  });

  group('streaming', () {
    test('a session receives only its own tokens', () async {
      final model = await newModel();
      final a = await model.openSession();
      final b = await model.openSession();

      final aChunks = <String>[];
      final bChunks = <String>[];
      final aDone = a.getResponseAsync().listen(aChunks.add).asFuture<void>();
      final bDone = b.getResponseAsync().listen(bChunks.add).asFuture<void>();
      await pumpEventQueue();

      // Interleaved, as two concurrent generations on one host would be.
      host.emitToken(a.sessionId, 'a1');
      host.emitToken(b.sessionId, 'b1');
      host.emitDone(a.sessionId, text: 'a2');
      host.emitDone(b.sessionId, text: 'b2');
      await Future.wait([aDone, bDone]);

      expect(aChunks, ['a1', 'a2']);
      expect(bChunks, ['b1', 'b2']);
    });

    test('empty deltas are dropped but still close the stream', () async {
      final model = await newModel();
      final session = await model.openSession();

      final chunks = <String>[];
      final done =
          session.getResponseAsync().listen(chunks.add).asFuture<void>();
      await pumpEventQueue();

      host.emitToken(session.sessionId, 'hi');
      // The terminal event carries no text — a common host shape.
      host.emitDone(session.sessionId);
      await done;

      expect(chunks, ['hi']);
    });

    test('a tagged error event surfaces on that session only', () async {
      final model = await newModel();
      final a = await model.openSession();
      final b = await model.openSession();

      final bChunks = <String>[];
      final bSub = b.getResponseAsync().listen(bChunks.add);
      final aErrors = <Object>[];
      // Not `asFuture`: it replaces the subscription's onError handler, so
      // the error would escape as an unhandled future error instead of
      // reaching `aErrors`.
      final aDone = Completer<void>();
      a.getResponseAsync().listen(
            (_) {},
            onError: aErrors.add,
            onDone: aDone.complete,
          );
      await pumpEventQueue();

      host.emitError(a.sessionId, 'model exploded');
      await aDone.future;

      expect(aErrors.single, isA<LocalAiGenerationException>());
      expect(bChunks, isEmpty);
      await bSub.cancel();
    });

    test('a failure to start generation surfaces on the stream', () async {
      final model = await newModel();
      final session = await model.openSession();
      final failing = _FailingStartHost(host);
      final failingSession = LocalAiSession(
        sessionId: session.sessionId,
        host: failing,
        onClose: () {},
      );

      await expectLater(
        failingSession.getResponseAsync(),
        emitsError(isA<StateError>()),
      );
    });
  });

  group('token counting', () {
    test('uses the host count when a tokenizer exists', () async {
      host.countTokensResult = 42;
      final model = await newModel();
      final session = await model.openSession();

      expect(await session.sizeInTokens('whatever'), 42);
    });

    test('falls back to an estimate when the host has no tokenizer', () async {
      host.countTokensError = LocalAiTokenizerUnavailable('no tokenizer');
      final model = await newModel();
      final session = await model.openSession();

      // length 8 / 4
      expect(await session.sizeInTokens('12345678'), 2);
    });

    test('does not mask a transport failure as an estimate', () async {
      host.countTokensError = StateError('channel is broken');
      final model = await newModel();
      final session = await model.openSession();

      expect(() => session.sizeInTokens('12345678'), throwsStateError);
    });
  });

  group('structured output', () {
    test('validates the schema before reaching the host', () async {
      final model = await newModel();
      final session = await model.openSession();

      expect(
        () => session.getStructuredResponse({'type': 'wat'}),
        throwsArgumentError,
      );
      expect(host.calls, isNot(contains('generateStructuredResponse')));
    });

    test('sends a valid schema as JSON', () async {
      final model = await newModel();
      final session = await model.openSession();

      await session.getStructuredResponse({
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
        },
      });

      expect(
        host.session(session.sessionId)!.lastSchemaJson,
        contains('"properties":{"name":{"type":"string"}}'),
      );
    });
  });

  group('images', () {
    test('images are buffered against the owning session', () async {
      final model = await newModel(supportImage: true);
      final session = await model.openSession();
      final bytes = Uint8List.fromList([1, 2, 3]);

      await session.addImage(bytes);

      expect(host.session(session.sessionId)!.images, [bytes]);
    });
  });

  group('model', () {
    test('image support is requested of the host up front', () async {
      await newModel(supportImage: true);

      // The host has to prepare a multimodal path before any session exists.
      expect(host.modelSupportsImage, isTrue);
    });

    test('closing the model releases it at the host', () async {
      final model = await newModel();
      await model.close();

      expect(host.modelClosed, isTrue);
    });

    test('closing twice is a no-op', () async {
      final model = await newModel();
      await model.close();
      host.calls.clear();
      await model.close();

      expect(host.calls, isEmpty);
    });

    test('session options reach the host', () async {
      final model = await newModel();
      await model.openSession(
        temperature: 0.4,
        topK: 12,
        topP: 0.85,
        maxOutputTokens: 256,
        systemInstruction: 'Be brief.',
      );

      final created = host.sessions.single;
      expect(created.temperature, 0.4);
      expect(created.topK, 12);
      expect(created.topP, 0.85);
      expect(created.maxOutputTokens, 256);
      expect(created.systemInstruction, 'Be brief.');
    });

    test('a host that rejects the session does not leave one behind', () async {
      final model = await newModel();
      host.createSessionError = StateError('tools unsupported');

      await expectLater(model.openSession(), throwsStateError);
      expect(model.sessions, isEmpty);
    });
  });

  group('generation controls', () {
    test('stopGeneration reaches the host', () async {
      final model = await newModel();
      final session = await model.openSession();

      await session.stopGeneration();

      expect(host.calls, contains('stopGeneration'));
    });

    test('stopGeneration on a closed session still reaches the host', () async {
      final model = await newModel();
      final session = await model.openSession();
      await session.close();

      // Deliberately not guarded: a stop racing a close must not throw, or
      // every cancel path needs its own try/catch.
      await session.stopGeneration();

      expect(host.calls, contains('stopGeneration'));
    });

    test('per-call sampling reaches the host without touching the session',
        () async {
      final model = await newModel();
      final session = await model.openSession(temperature: 0.9);

      await session.getResponse(
        overrides: const LocalAiGenerationOverrides(
          temperature: 0.1,
          maxOutputTokens: 32,
        ),
      );

      expect(host.lastOverrides?.temperature, 0.1);
      expect(host.lastOverrides?.maxOutputTokens, 32);
      expect(host.sessions.single.temperature, 0.9);
    });

    test('an override that changes nothing is not sent', () async {
      final model = await newModel();
      final session = await model.openSession();

      await session.getResponse(
        overrides: const LocalAiGenerationOverrides(),
      );

      // An empty override would make a host rebuild its options for no
      // reason, and on Apple that can flip the sampling mode.
      expect(host.lastOverrides, isNull);
    });

    test('structured generation carries overrides too', () async {
      final model = await newModel();
      final session = await model.openSession();

      await session.getStructuredResponse(
        const {'type': 'object'},
        overrides: const LocalAiGenerationOverrides(maxOutputTokens: 16),
      );

      expect(host.lastOverrides?.maxOutputTokens, 16);
    });
  });

  group('LocalAiAvailability', () {
    test('only downloadable and downloading are worth waiting on', () {
      expect(LocalAiAvailability.downloadable.isTransient, isTrue);
      expect(LocalAiAvailability.downloading.isTransient, isTrue);

      for (final terminal in [
        LocalAiAvailability.available,
        LocalAiAvailability.unavailableDeviceUnsupported,
        LocalAiAvailability.unavailableOsTooOld,
        LocalAiAvailability.unavailableDisabled,
        LocalAiAvailability.unavailableOther,
      ]) {
        expect(terminal.isTransient, isFalse, reason: '$terminal');
      }
    });
  });

  group('LocalAi.ensureReady', () {
    test('returns immediately when already available', () async {
      await LocalAi.ensureReady();
      expect(host.calls, isNot(contains('downloadFeature')));
    });

    test('throws without downloading on a terminal state', () async {
      host.availability = LocalAiAvailability.unavailableDeviceUnsupported;

      await expectLater(
        LocalAi.ensureReady(),
        throwsA(isA<LocalAiUnavailableException>().having(
          (e) => e.status,
          'status',
          LocalAiAvailability.unavailableDeviceUnsupported,
        )),
      );
      expect(host.calls, isNot(contains('downloadFeature')));
    });

    test('kicks off a download and completes when it becomes available',
        () async {
      host.availability = LocalAiAvailability.downloadable;
      final percents = <int>[];

      final ready = LocalAi.ensureReady(onProgress: percents.add);
      await pumpEventQueue();
      host.emitDownloadProgress(50, bytesTotal: 100);
      await pumpEventQueue();
      host.availability = LocalAiAvailability.available;
      await ready;

      expect(host.calls, contains('downloadFeature'));
      expect(percents, contains(50));
    });

    test('joins an in-flight download instead of starting a second', () async {
      host.availability = LocalAiAvailability.downloading;

      final ready = LocalAi.ensureReady();
      await pumpEventQueue();
      host.availability = LocalAiAvailability.available;
      await ready;

      expect(host.calls, isNot(contains('downloadFeature')));
    });
  });
}

/// A host whose `generateResponseAsync` fails before emitting anything —
/// the case where a stream would otherwise hang forever.
class _FailingStartHost extends _DelegatingHost {
  _FailingStartHost(super.inner);

  @override
  Future<void> generateResponseAsync(
    int sessionId, {
    LocalAiGenerationOverrides? overrides,
  }) async =>
      throw StateError('native refused');
}

class _DelegatingHost implements LocalAiHost {
  _DelegatingHost(this.inner);

  final LocalAiHost inner;

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');

  @override
  Stream<LocalAiHostEvent> get events => inner.events;
}
