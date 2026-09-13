@TestOn('browser')
library;

import 'dart:js_interop';

import 'package:flutter_local_ai/src/session/web/prompt_api_interop.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_prompt_api.dart';

/// Drains [chunks] through [pumpTextStream] and returns what the caller was
/// handed, so a test reads as "browser streamed X, the app saw Y".
Future<List<String>> drain(List<String> chunks) async {
  final seen = <String>[];
  await pumpTextStream(fakeTextStream(chunks), seen.add);
  return seen;
}

void main() {
  group('pumpTextStream delta/cumulative guard', () {
    test('passes a spec-shaped delta stream through untouched', () async {
      expect(await drain(['Hel', 'lo', ' world']), ['Hel', 'lo', ' world']);
    });

    test('reduces a cumulative stream to deltas', () async {
      // What an early Chrome build actually puts on the wire for the same
      // answer. Emitted verbatim, the app would render
      // 'HelHelloHello world'.
      expect(await drain(toCumulative(['Hel', 'lo', ' world'])), [
        'Hel',
        'lo',
        ' world',
      ]);
    });

    test('emits a single-chunk stream verbatim', () async {
      // One chunk never reaches the chunk-2 decision, so it must still be
      // delivered rather than held back waiting to classify.
      expect(await drain(['Hello']), ['Hello']);
    });

    test(
      'holds the delta verdict when a later chunk repeats the prefix',
      () async {
        // Chunk 2 ('lo') does not start with chunk 1, so the stream is delta.
        // Chunk 3 happens to start with everything emitted so far ('Hello');
        // deciding per chunk would read it as cumulative and swallow 'Hello'
        // out of the middle of the answer. The verdict is taken once.
        expect(await drain(['Hel', 'lo', 'Hello again']), [
          'Hel',
          'lo',
          'Hello again',
        ]);
      },
    );

    test('keeps a shorter chunk whole once the stream is cumulative', () async {
      // 'Hello' classifies the stream as cumulative; 'Hi' is shorter than the
      // accumulation, so it is not a cumulative chunk at all. Taking it raw
      // beats a negative-length substring.
      expect(await drain(['Hel', 'Hello', 'Hi']), ['Hel', 'lo', 'Hi']);
    });

    test('skips empty chunks without disturbing the decision', () async {
      expect(await drain(['Hel', '', 'lo']), ['Hel', 'lo']);
    });

    test('propagates a reader failure to the caller', () async {
      await expectLater(
        pumpTextStream(fakeTextStream(['a'], rejectAfter: 1), (_) {}),
        throwsA(anything),
      );
    });
  });

  group('isAbortError', () {
    test('matches a DOMException named AbortError', () {
      expect(isAbortError(fakeDomException('AbortError', 'aborted')), isTrue);
    });

    test('rejects another error whose message merely says AbortError', () {
      // The reason the check is on `name` alone: a real decode failure that
      // mentions AbortError in prose must stay an error, or the user is shown
      // an empty successful turn instead of what went wrong.
      expect(
        isAbortError(
          fakeDomException('NotReadableError', 'not an AbortError, honest'),
        ),
        isFalse,
      );
    });

    test('rejects a DOMException-shaped error with a different name', () {
      expect(isAbortError(fakeDomException('InvalidStateError')), isFalse);
    });

    test('rejects a Dart error', () {
      expect(isAbortError(StateError('nope')), isFalse);
    });
  });

  group('hasLanguageModelParams', () {
    setUp(FakeLanguageModel.uninstall);
    tearDown(FakeLanguageModel.uninstall);

    test('is false when the Prompt API is absent entirely', () {
      expect(hasLanguageModel, isFalse);
      expect(hasLanguageModelParams, isFalse);
    });

    test('is false on a build that dropped the static params()', () {
      FakeLanguageModel(includeParams: false).install();
      expect(hasLanguageModel, isTrue);
      expect(hasLanguageModelParams, isFalse);
    });

    test('is true on a build that still exposes params()', () {
      FakeLanguageModel().install();
      expect(hasLanguageModelParams, isTrue);
    });
  });

  group('readSamplerBounds', () {
    test('reads both ceilings when the build reports them', () async {
      FakeLanguageModel(maxTemperature: 1.5, maxTopK: 4).install();
      addTearDown(FakeLanguageModel.uninstall);

      final bounds = readSamplerBounds(await LanguageModel.params().toDart);
      expect(bounds.maxTemperature, 1.5);
      expect(bounds.maxTopK, 4);
    });

    test('reports an omitted ceiling as absent rather than zero', () async {
      FakeLanguageModel(maxTemperature: null, maxTopK: 4).install();
      addTearDown(FakeLanguageModel.uninstall);

      final bounds = readSamplerBounds(await LanguageModel.params().toDart);
      expect(bounds.maxTemperature, isNull);
      expect(bounds.maxTopK, 4);
    });
  });
}
