@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:flutter_local_ai/src/session/local_ai_host.dart';
import 'package:flutter_local_ai/src/session/web/local_ai_host_web.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_prompt_api.dart';

/// Collects the host's tagged events for one session and completes once the
/// turn terminates, either way — a `done: true` token or an error event.
class _Turn {
  _Turn(WebLocalAiHost host, int sessionId, {void Function(String)? onToken}) {
    _subscription = host.events.listen((event) {
      switch (event) {
        case LocalAiTokenEvent(:final partialResult, :final done)
            when event.sessionId == sessionId:
          if (partialResult.isNotEmpty) {
            tokens.add(partialResult);
            onToken?.call(partialResult);
          }
          if (done && !_finished.isCompleted) _finished.complete();
        case LocalAiErrorEvent(:final message)
            when event.sessionId == sessionId:
          errors.add(message);
          if (!_finished.isCompleted) _finished.complete();
        default:
      }
    });
  }

  final tokens = <String>[];
  final errors = <String>[];
  final _finished = Completer<void>();
  late final StreamSubscription<LocalAiHostEvent> _subscription;

  Future<void> get finished =>
      _finished.future.timeout(const Duration(seconds: 5));

  Future<void> dispose() => _subscription.cancel();
}

Future<WebLocalAiHost> openSession(
  FakeLanguageModel languageModel, {
  int sessionId = 1,
  double temperature = 0.8,
  int topK = 3,
  String prompt = 'hi',
}) async {
  languageModel.install();
  final host = WebLocalAiHost();
  await host.createModel(supportImage: false);
  await host.createSession(
    sessionId: sessionId,
    temperature: temperature,
    topK: topK,
  );
  await host.addQueryChunk(sessionId: sessionId, text: prompt);
  return host;
}

void main() {
  setUp(FakeLanguageModel.uninstall);
  tearDown(FakeLanguageModel.uninstall);

  group('streaming', () {
    test('emits each delta then a single done event', () async {
      final host = await openSession(
        FakeLanguageModel(
          create: ([options]) =>
              FakeSession(streamChunks: (_) => ['Hel', 'lo']),
        ),
      );
      final turn = _Turn(host, 1);
      addTearDown(turn.dispose);

      await host.generateResponseAsync(1);
      await turn.finished;

      expect(turn.tokens, ['Hel', 'lo']);
      expect(turn.errors, isEmpty);
    });

    test('normalises a cumulative stream into deltas', () async {
      final host = await openSession(
        FakeLanguageModel(
          create: ([options]) => FakeSession(
            streamChunks: (_) => ['Hel', 'lo'],
            cumulativeStream: true, // the fake sends ['Hel', 'Hello']
          ),
        ),
      );
      final turn = _Turn(host, 1);
      addTearDown(turn.dispose);

      await host.generateResponseAsync(1);
      await turn.finished;

      expect(turn.tokens, ['Hel', 'lo']);
    });

    test('stopGeneration ends the turn with done, not an error', () async {
      final host = await openSession(
        FakeLanguageModel(
          create: ([options]) =>
              FakeSession(streamChunks: (_) => ['a', 'b', 'c', 'd', 'e']),
        ),
      );
      late final _Turn turn;
      turn = _Turn(
        host,
        1,
        // Stop as soon as the first delta lands, the way a user hits the stop
        // button mid-answer.
        onToken: (_) {
          if (turn.tokens.length == 1) unawaited(host.stopGeneration(1));
        },
      );
      addTearDown(turn.dispose);

      await host.generateResponseAsync(1);
      await turn.finished;

      // The abort must close the turn cleanly: before the AbortError guard the
      // rejected promptStreaming became a LocalAiErrorEvent, so pressing stop
      // threw at the app.
      expect(turn.errors, isEmpty);
      expect(turn.tokens, isNotEmpty);
      expect(turn.tokens.length, lessThan(5));
    });

    test('a genuine stream failure is still a tagged error event', () async {
      final host = await openSession(
        FakeLanguageModel(
          create: ([options]) => FakeSession(
            streamChunks: (_) => ['a', 'b'],
            streamRejectAfter: 1,
          ),
        ),
      );
      final turn = _Turn(host, 1);
      addTearDown(turn.dispose);

      await host.generateResponseAsync(1);
      await turn.finished;

      expect(turn.tokens, ['a']);
      expect(turn.errors, hasLength(1));
    });

    test('releases the generation slot after the turn ends', () async {
      final host = await openSession(
        FakeLanguageModel(
          create: ([options]) => FakeSession(streamChunks: (_) => ['a']),
        ),
      );
      final turn = _Turn(host, 1);
      addTearDown(turn.dispose);

      await host.generateResponseAsync(1);
      await turn.finished;

      // A wedged slot would make every later turn on this session throw.
      await host.addQueryChunk(sessionId: 1, text: 'again');
      await expectLater(host.generateResponseAsync(1), completes);
    });
  });

  group('non-streaming', () {
    test('returns the response text', () async {
      final host = await openSession(
        FakeLanguageModel(
          create: ([options]) =>
              FakeSession(onPrompt: (input) => 'echo:$input'),
        ),
      );
      expect(await host.generateResponse(1), 'echo:hi');
    });

    test('stopGeneration resolves as an empty turn, not a throw', () async {
      final host = await openSession(
        FakeLanguageModel(
          create: ([options]) => FakeSession(onPrompt: (_) => 'never seen'),
        ),
      );

      final pending = host.generateResponse(1);
      await host.stopGeneration(1);

      // An aborted prompt() discards the whole call, so there is no partial
      // text; the empty string is the cancelled turn.
      expect(await pending, isEmpty);
    });

    test('a genuine prompt failure still throws', () async {
      final host = await openSession(
        FakeLanguageModel(
          create: ([options]) => FakeSession(
            promptRejectsWith: ('NotReadableError', 'contains AbortError'),
          ),
        ),
      );

      // Named NotReadableError but with AbortError in the message: a substring
      // match would turn this failure into a successful empty answer.
      await expectLater(host.generateResponse(1), throwsA(anything));
    });

    test('structured generation stops as an empty turn too', () async {
      final host = await openSession(
        FakeLanguageModel(
          create: ([options]) => FakeSession(onPrompt: (_) => '{"a":1}'),
        ),
      );

      final pending = host.generateStructuredResponse(
        sessionId: 1,
        schemaJson: '{"type":"object"}',
      );
      await host.stopGeneration(1);

      expect(await pending, isEmpty);
    });
  });

  group('single in-flight generation per session', () {
    test('rejects a second generation while one is running', () async {
      final host = await openSession(
        FakeLanguageModel(
          create: ([options]) =>
              FakeSession(streamChunks: (_) => ['a', 'b', 'c']),
        ),
      );
      final turn = _Turn(host, 1);
      addTearDown(turn.dispose);

      await host.generateResponseAsync(1);
      await expectLater(host.generateResponse(1), throwsA(isA<StateError>()));

      await turn.finished;
    });

    test('leaves the first turn abortable', () async {
      late final FakeSession session;
      final host = await openSession(
        FakeLanguageModel(
          create: ([options]) =>
              session = FakeSession(streamChunks: (_) => ['a', 'b', 'c', 'd']),
        ),
      );
      final turn = _Turn(host, 1);
      addTearDown(turn.dispose);

      await host.generateResponseAsync(1);
      await expectLater(
        host.generateResponseAsync(1),
        throwsA(isA<StateError>()),
      );
      await host.stopGeneration(1);
      await turn.finished;

      // Before the guard the second call overwrote inFlight, orphaning the
      // controller that actually owned the running generation.
      expect(isSignalAborted(session.lastStreamingSignal), isTrue);
      expect(turn.errors, isEmpty);
    });

    test('does not consume the transcript when it refuses', () async {
      final host = await openSession(
        FakeLanguageModel(
          create: ([options]) =>
              FakeSession(streamChunks: (_) => ['a'], onPrompt: (i) => i),
        ),
      );
      final turn = _Turn(host, 1);
      addTearDown(turn.dispose);

      await host.generateResponseAsync(1);
      await expectLater(host.generateResponse(1), throwsA(isA<StateError>()));
      await turn.finished;

      // The refused call must not have drained the queued chunks, or the
      // retry would prompt with nothing.
      expect(await host.generateResponse(1), 'hi');
    });
  });

  group('sampler clamp', () {
    test('lowers temperature and topK to the advertised maxima', () async {
      final languageModel = FakeLanguageModel(maxTemperature: 1.0, maxTopK: 3);
      await openSession(languageModel, temperature: 2.0, topK: 8);

      final options = languageModel.createOptions.single!.dartify()! as Map;
      expect(options['temperature'], 1.0);
      expect(options['topK'], 3);
    });

    test('leaves sampling below the maxima alone', () async {
      final languageModel = FakeLanguageModel(maxTemperature: 2.0, maxTopK: 8);
      await openSession(languageModel, temperature: 0.4, topK: 2);

      final options = languageModel.createOptions.single!.dartify()! as Map;
      expect(options['temperature'], 0.4);
      expect(options['topK'], 2);
    });

    test('skips the clamp on a build without params()', () async {
      // Chrome 151 dropped the static; calling it there throws a TypeError on
      // every createSession, so the clamp has to be feature-detected.
      final languageModel = FakeLanguageModel(includeParams: false);
      await openSession(languageModel, temperature: 2.0, topK: 8);

      final options = languageModel.createOptions.single!.dartify()! as Map;
      expect(options['temperature'], 2.0);
      expect(options['topK'], 8);
      expect(languageModel.paramsCalls, 0);
    });

    test('skips a ceiling the build does not report', () async {
      final languageModel = FakeLanguageModel(maxTemperature: null, maxTopK: 3);
      await openSession(languageModel, temperature: 2.0, topK: 8);

      final options = languageModel.createOptions.single!.dartify()! as Map;
      expect(options['temperature'], 2.0);
      expect(options['topK'], 3);
    });
  });

  group('countTokens', () {
    test('prefers measureContextUsage, the current spec name', () async {
      late final FakeSession session;
      final host = await openSession(
        FakeLanguageModel(
          create: ([options]) => session = FakeSession(
            measureMembers: const ['measureContextUsage', 'measureInputUsage'],
          ),
        ),
      );

      expect(await host.countTokens(sessionId: 1, text: 'abcd'), 4);
      expect(session.measureCalls, ['measureContextUsage']);
    });

    test('falls back to the legacy measureInputUsage', () async {
      late final FakeSession session;
      final host = await openSession(
        FakeLanguageModel(
          create: ([options]) => session = FakeSession(
            measureMembers: const ['measureInputUsage'],
          ),
        ),
      );

      expect(await host.countTokens(sessionId: 1, text: 'abcd'), 4);
      expect(session.measureCalls, ['measureInputUsage']);
    });

    test('measures on the session it is asked about', () async {
      final sessions = <FakeSession>[];
      final languageModel = FakeLanguageModel(
        create: ([options]) {
          final session = FakeSession();
          sessions.add(session);
          return session;
        },
      );
      final host = await openSession(languageModel);
      await host.createSession(sessionId: 2, temperature: 0.8, topK: 3);

      expect(await host.countTokens(sessionId: 2, text: 'abcd'), 4);
      // Before, it borrowed the first open session whatever the caller was.
      expect(sessions.first.measureCalls, isEmpty);
      expect(sessions.last.measureCalls, ['measureContextUsage']);
    });

    test('waits for the session to finish generating', () async {
      late final FakeSession session;
      final host = await openSession(
        FakeLanguageModel(
          create: ([options]) =>
              session = FakeSession(streamChunks: (_) => ['a', 'b', 'c']),
        ),
      );
      final turn = _Turn(host, 1);
      addTearDown(turn.dispose);
      var turnEnded = false;
      unawaited(turn.finished.then((_) => turnEnded = true));

      await host.generateResponseAsync(1);
      final count = host.countTokens(sessionId: 1, text: 'abcd');

      expect(await count, 4);
      // Measured only once the stream had drained, never mid-turn.
      expect(turnEnded, isTrue);
      expect(session.measureCalls, ['measureContextUsage']);
    });

    test('rejects an unknown session', () async {
      final host = await openSession(FakeLanguageModel());

      await expectLater(
        host.countTokens(sessionId: 99, text: 'abcd'),
        throwsA(isA<StateError>()),
      );
    });

    test('reports no tokenizer when the build exposes neither', () async {
      final host = await openSession(
        FakeLanguageModel(
          create: ([options]) => FakeSession(measureMembers: const []),
        ),
      );

      // Naming the missing methods beats the opaque JS
      // "measureInputUsage is not a function" the blind call produced.
      await expectLater(
        host.countTokens(sessionId: 1, text: 'abcd'),
        throwsA(isA<LocalAiTokenizerUnavailable>()),
      );
    });
  });

  group('downloadFeature', () {
    test('refuses outside a user gesture without calling create()', () async {
      final languageModel = FakeLanguageModel(availability: 'downloadable')
        ..install();
      final host = WebLocalAiHost(hasUserActivation: () => false);

      await expectLater(
        host.downloadFeature(),
        throwsA(
          isA<LocalAiUserActivationRequiredException>().having(
            (e) => e.status,
            'status',
            LocalAiAvailability.downloadable,
          ),
        ),
      );
      expect(languageModel.createOptions, isEmpty);
    });

    test('maps Chrome\'s NotAllowedError to the same exception', () async {
      // A browser without navigator.userActivation, or activation that lapsed
      // before create() ran: Chrome itself is the one to refuse.
      FakeLanguageModel(
        availability: 'downloadable',
        createRejectsWith: ('NotAllowedError', 'Requires a user gesture'),
      ).install();
      final host = WebLocalAiHost(hasUserActivation: () => true);

      await expectLater(
        host.downloadFeature(),
        throwsA(isA<LocalAiUserActivationRequiredException>()),
      );
    });

    test('starts the download inside a user gesture', () async {
      final languageModel = FakeLanguageModel(availability: 'downloadable')
        ..install();
      final host = WebLocalAiHost(hasUserActivation: () => true);

      await host.downloadFeature();

      expect(languageModel.createOptions, hasLength(1));
      expect(languageModel.lastSession!.destroyCount, 1);
    });

    test('lets any other create() failure through unchanged', () async {
      FakeLanguageModel(
        createRejectsWith: ('QuotaExceededError', 'disk full'),
      ).install();
      final host = WebLocalAiHost(hasUserActivation: () => true);

      await expectLater(
        host.downloadFeature(),
        throwsA(isNot(isA<LocalAiUnavailableException>())),
      );
    });
  });
}
