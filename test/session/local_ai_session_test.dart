import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart' show MissingPluginException;
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

      expect(
        host.session(session.sessionId)!.transcript.toString(),
        'Hello world',
      );
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

    test('a failed close can be retried', () async {
      final model = await newModel();
      final session = await model.openSession();
      host.closeSessionError = StateError('teardown failed');

      await expectLater(session.close(), throwsStateError);
      expect(session.isClosed, isFalse);
      expect(model.sessions, contains(session));

      host.closeSessionError = null;
      await session.close();
      expect(session.isClosed, isTrue);
      expect(model.sessions, isEmpty);
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
      final done = session
          .getResponseAsync()
          .listen(chunks.add)
          .asFuture<void>();
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

    test('scopes the count to the session asking', () async {
      final model = await newModel();
      await model.openSession();
      final second = await model.openSession();

      await second.sizeInTokens('whatever');

      // The web arm measures on this id; without it the count ran on
      // whichever session happened to be open first.
      expect(host.countTokensSessionIds, [second.sessionId]);
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

    test('a schema and a bound tool reach the host together', () async {
      final model = await newModel();
      final session = await model.openSession(
        tools: [
          LocalAiTool(
            name: 'lookup',
            description: 'Local lookup',
            parameters: const [],
            onCall: (_) async => 'found',
          ),
        ],
      );

      await session.getStructuredResponse({
        'type': 'object',
        'properties': {
          'value': {'type': 'string'},
        },
      });

      // Tools belong to the session, the schema to the call. Apple binds tools
      // when the session is built and cannot add them to a live one, so a
      // structured call that dropped them to constrain the output would leave
      // the session unable to call a tool for the rest of its life.
      final created = host.session(session.sessionId)!;
      expect(created.toolNames, ['lookup']);
      expect(created.lastSchemaJson, contains('"value":{"type":"string"}'));
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

    test('a backend with no vision path refuses image support', () async {
      // Web and Windows both report this: local_ai_host_web.dart hard-codes
      // `supportsVision: false` because the Prompt API's multimodal path is
      // not reachable from an ordinary page as of Chrome 151, and
      // local_ai_session_service.cpp does the same. Set the flag explicitly
      // rather than leaning on its default — the refusal in
      // `_HostModelState.acquire` reads that one field, not the backend kind
      // beside it.
      host.capabilities = const LocalAiBackendCapabilities(
        backend: LocalAiBackendKind.chromePromptApi,
        platform: 'web',
        apiName: 'Chrome Prompt API (Gemini Nano)',
        supportsVision: false,
      );

      await expectLater(
        newModel(supportImage: true),
        throwsA(
          isA<LocalAiUnsupportedException>().having(
            (e) => e.capability,
            'capability',
            'vision',
          ),
        ),
      );
      // Refused before the model is created, so the caller is not left with a
      // native handle it never received a reference to.
      expect(host.calls, isNot(contains('createModel')));
    });

    test('an image owner upgrades the model every owner shares', () async {
      await newModel();
      await newModel(supportImage: true);

      // One native model backs all owners, so the second one cannot get its
      // multimodal path without re-creating the model already open.
      expect(host.calls.where((call) => call == 'createModel'), hasLength(2));
      expect(host.modelSupportsImage, isTrue);

      host.calls.clear();
      await newModel();

      // A text-only owner arriving later must not cost the image owner its
      // multimodal path. `_HostModelState.acquire` re-creates only when the
      // model is unowned or when an image owner finds a text-only one, so
      // this owner must not reach `createModel` at all. The hosts would
      // survive a redundant create — Apple's is a no-op, Android's reuses its
      // cached client — but reaching it would mean the guard had stopped
      // tracking who is holding what, which is the invariant under test.
      expect(host.calls, isNot(contains('createModel')));
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
        tools: [
          LocalAiTool(
            name: 'lookup',
            description: 'Local lookup',
            parameters: const [],
            onCall: (_) async => 'found',
          ),
        ],
      );

      final created = host.sessions.single;
      expect(created.temperature, 0.4);
      expect(created.topK, 12);
      expect(created.topP, 0.85);
      expect(created.maxOutputTokens, 256);
      expect(created.systemInstruction, 'Be brief.');
      // Apple binds tools when the session is built, so a `tools:` dropped on
      // the way down cannot be handed over later in the turn — the model just
      // never calls them.
      expect(created.toolNames, ['lookup']);
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

    test(
      'per-call sampling reaches the host without touching the session',
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
      },
    );

    test('an override that changes nothing is not sent', () async {
      final model = await newModel();
      final session = await model.openSession();

      await session.getResponse(overrides: const LocalAiGenerationOverrides());

      // An empty override would make a host rebuild its options for no
      // reason, and on Apple that can flip the sampling mode.
      expect(host.lastOverrides, isNull);
    });

    test('structured generation carries overrides too', () async {
      final model = await newModel();
      final session = await model.openSession();

      await session.getStructuredResponse(const {
        'type': 'object',
      }, overrides: const LocalAiGenerationOverrides(maxOutputTokens: 16));

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

  group('LocalAi.availabilityReason', () {
    test('returns the host sentence', () async {
      host.reason = 'Enable AICore.';
      expect(await LocalAi.availabilityReason(), 'Enable AICore.');
    });

    test('never throws, like availability()', () async {
      // An unregistered plugin: availability() reports unavailableOther
      // there, and the reason must not throw beside it.
      host.availabilityReasonError = MissingPluginException('no plugin');

      expect(
        await LocalAi.availabilityReason(),
        contains('not available on this platform'),
      );
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
        throwsA(
          isA<LocalAiUnavailableException>().having(
            (e) => e.status,
            'status',
            LocalAiAvailability.unavailableDeviceUnsupported,
          ),
        ),
      );
      expect(host.calls, isNot(contains('downloadFeature')));
    });

    test(
      'kicks off a download and completes when it becomes available',
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
      },
    );

    test('fails fast when the download cannot be started', () async {
      host.availability = LocalAiAvailability.downloadable;
      host.downloadFeatureError = LocalAiUserActivationRequiredException(
        'needs a gesture',
      );

      // Availability keeps reading `downloadable` after a refused start, so
      // before this the call sat out its whole timeout and then blamed a slow
      // download. A timeout far longer than the test proves it did not wait.
      await expectLater(
        LocalAi.ensureReady(timeout: const Duration(minutes: 10)),
        throwsA(
          isA<LocalAiUserActivationRequiredException>().having(
            (e) => e.status,
            'status',
            LocalAiAvailability.downloadable,
          ),
        ),
      );
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
  }) async => throw StateError('native refused');
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
