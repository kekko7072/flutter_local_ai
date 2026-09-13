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

      expect(await host.countTokens('abcd'), 4);
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

      expect(await host.countTokens('abcd'), 4);
      expect(session.measureCalls, ['measureInputUsage']);
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
        host.countTokens('abcd'),
        throwsA(isA<LocalAiTokenizerUnavailable>()),
      );
    });
  });
}
