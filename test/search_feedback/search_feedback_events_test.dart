import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search_feedback/search_feedback_api.dart';
import 'package:otzaria/search_feedback/search_feedback_events.dart';

import 'search_feedback_test_support.dart';

void main() {
  final now = kStart.add(const Duration(milliseconds: 1500));
  late SearchFeedbackEventBuilder builder;

  setUp(() {
    var n = 0;
    builder = SearchFeedbackEventBuilder(
      clock: () => now,
      newId: () => 'event_${(n++).toString().padLeft(4, '0')}',
    );
  });

  group('ids and time', () {
    test('new ids are 128-bit base64url and match the protocol pattern', () {
      final id = newSearchFeedbackId(Random(1));
      expect(id, hasLength(22));
      expect(isValidSearchFeedbackId(id), isTrue);
      expect(isValidSearchFeedbackId('short'), isFalse);
      expect(isValidSearchFeedbackId('has space here'), isFalse);
    });

    test('ISO time is UTC with exactly milliseconds', () {
      final time = DateTime.utc(2026, 10, 2, 10, 0, 0, 7, 999);
      expect(searchFeedbackIsoTime(time), '2026-10-02T10:00:00.007Z');
    });
  });

  group('search event', () {
    test('maps params, response and Amendment A fields', () {
      final event = builder.search(
        searchContext(
          ranking: {
            'alpha': 0.5,
            'nan': double.nan,
            'alphaByQueryType': {'short': 0.3, 'long': 0.7},
          },
          fallbackKind: 'x' * 100,
        ),
      )!;
      expect(event['type'], 'search');
      expect(event['eventId'], 'event_0000');
      expect(event['clientTime'], '2026-10-02T10:00:01.500Z');
      expect(event['msSinceSearch'], 1500);
      expect(event['queryLength'], 'שבת שלום'.length);
      expect(event['queryWordCount'], 2);
      final params = event['params'] as Map;
      expect(params['scope'], {
        'facets': ['/תנך'],
        'allLibrary': false,
      });
      expect(params['ranking'], {
        'alpha': 0.5,
        'nan': null,
        'alphaByQueryType': {'short': 0.3, 'long': 0.7},
      });
      final response = event['response'] as Map;
      expect(response['fallbackKind'], hasLength(64));
      expect(response['latencyMs'], 120);
      expect(() => jsonEncode(event), returnsNormally);
    });

    test('query is truncated to 500 chars', () {
      final event = builder.search(searchContext(query: 'א' * 900))!;
      expect(event['query'], hasLength(500));
      expect(event['queryLength'], 500);
    });

    test('an invalid searchSessionId produces no event', () {
      expect(builder.search(searchContext(id: 'bad id')), isNull);
    });

    test('ranking is capped at 40 keys', () {
      final ranking = {for (var i = 0; i < 60; i++) 'k$i': i};
      final event = builder.search(searchContext(ranking: ranking))!;
      expect((event['params'] as Map)['ranking'] as Map, hasLength(40));
    });
  });

  group('user-book filtering', () {
    test('results_shown drops user-book results', () {
      final event = builder.resultsShown(searchContext(), 0, [
        result(rank: 1),
        result(rank: 2, isUserBook: true, title: 'ספר אישי'),
        result(rank: 3),
      ])!;
      final results = event['results'] as List;
      expect(results.map((r) => (r as Map)['rank']), [1, 3]);
      expect(jsonEncode(event), isNot(contains('ספר אישי')));
    });

    test('a page made only of user books is not sent', () {
      expect(
        builder.resultsShown(searchContext(), 0, [
          result(isUserBook: true),
        ]),
        isNull,
      );
    });

    test('an empty page is still reported (zero-results signal)', () {
      final event = builder.resultsShown(searchContext(), 0, const [])!;
      expect(event['results'], isEmpty);
    });

    test('open and vote on a user book are skipped entirely', () {
      final userBook = result(isUserBook: true);
      expect(
        builder.open(
          searchContext(),
          userBook,
          SearchFeedbackOpenVia.click,
          'open_abcdefgh',
        ),
        isNull,
      );
      expect(
        builder.vote(searchContext(), userBook, SearchFeedbackVote.like),
        isNull,
      );
    });
  });

  group('length limits', () {
    test('ResultFull fields are truncated and lists capped', () {
      final event = builder.open(
        searchContext(),
        result(
          title: 'ת' * 400,
          reference: 'ר' * 400,
          snippet: 'ק' * 3000,
          passage: 'פ' * 25000,
          matched: List.filled(80, 'מ' * 300),
          fused: double.infinity,
        ),
        SearchFeedbackOpenVia.preview,
        'open_abcdefgh',
      )!;
      final full = event['result'] as Map;
      expect(full['title'], hasLength(300));
      expect(full['reference'], hasLength(300));
      expect(full['snippetText'], hasLength(2000));
      expect(full['passageText'], hasLength(20000));
      expect(full['passageTextSource'], 'line');
      expect(full['matchedText'] as List, hasLength(50));
      expect((full['matchedText'] as List).first, hasLength(200));
      expect(full['fusedScore'], isNull, reason: 'non-finite → null');
      expect(event['via'], 'preview');
    });

    test('missing passage falls back to the snippet', () {
      final event = builder.vote(
        searchContext(),
        result(snippet: 'קטע'),
        SearchFeedbackVote.cleared,
      )!;
      final full = event['result'] as Map;
      expect(full['passageText'], 'קטע');
      expect(full['passageTextSource'], 'snippet');
      expect(event['vote'], 'cleared');
    });

    test('results are capped at 100 and ranks preserved', () {
      final event = builder.resultsShown(searchContext(), 100, [
        for (var i = 0; i < 150; i++) result(rank: 101 + i),
      ])!;
      final results = event['results'] as List;
      expect(results, hasLength(100));
      expect((results.first as Map)['rank'], 101);
      expect(event['offset'], 100);
    });

    test('an oversized page shrinks snippets to fit the event budget', () {
      final event = builder.resultsShown(searchContext(), 0, [
        for (var i = 0; i < 100; i++)
          result(rank: i + 1, snippet: 'ש' * 2000, title: 'ת' * 300),
      ])!;
      final size = searchFeedbackJsonEncode(event).length;
      expect(size, lessThanOrEqualTo(SearchFeedbackLimits.eventBytes));
      expect(
        ((event['results'] as List).first as Map)['snippetText'],
        hasLength(lessThan(2000)),
      );
    });

    test('truncation never splits a surrogate pair', () {
      final text = '${'a' * 9}😀';
      expect(truncateForSearchFeedback(text, 10), 'a' * 9);
    });
  });

  group('dwell', () {
    test('caps at 30 minutes with endReason capped', () {
      final event = builder.dwell(
        searchContext(),
        'open_abcdefgh',
        const Duration(hours: 2),
        SearchFeedbackDwellEnd.tabClosed,
      )!;
      expect(event['dwellMs'], 30 * 60 * 1000);
      expect(event['endReason'], 'capped');
    });

    test('maps end reasons to snake_case', () {
      final event = builder.dwell(
        searchContext(),
        'open_abcdefgh',
        const Duration(seconds: 45),
        SearchFeedbackDwellEnd.returnedToResults,
      )!;
      expect(event['dwellMs'], 45000);
      expect(event['endReason'], 'returned_to_results');
    });
  });

  group('client context', () {
    test('engine uses the Amendment A fields only', () {
      final engine = searchFeedbackEngineJson(searchContext().engine);
      expect(engine.keys, {
        'state',
        'modelFamilyId',
        'modelQuantization',
        'modelPackageChecksum',
        'embeddingDim',
        'vectorsReleaseTag',
        'vectorsLibraryVersion',
        'vectorSegments',
      });
      expect(engine['modelFamilyId'], 'family@abc');
    });

    test('coarse OS version keeps only version numbers', () {
      expect(
        coarseOsVersion('"Windows 10 Pro" 10.0 (Build 26200)'),
        '10.0.26200',
      );
      expect(
        coarseOsVersion('Linux 6.5.0-14-generic #14-Ubuntu SMP my-host'),
        '6.5.0',
      );
      expect(coarseOsVersion('Version 14.2.1 (Build 23C71)'), '14.2.1');
      expect(coarseOsVersion('my-hostname'), 'unknown');
    });
  });

  test('wire JSON escapes all non-ASCII characters', () {
    final encoded = searchFeedbackJsonEncode({'q': 'שלום 😀'});
    expect(encoded.codeUnits.every((c) => c < 0x80), isTrue);
    expect(jsonDecode(encoded), {'q': 'שלום 😀'});
  });

  group('contract validation', () {
    test('invalid required enums drop the search event', () {
      expect(builder.search(searchContext(retrievalMode: 'magic')), isNull);
      expect(builder.search(searchContext(lexicalMode: 'Exact')), isNull);
      expect(builder.search(searchContext(executedMode: 'other')), isNull);
    });

    test('grouping is kept when valid and nulled otherwise', () {
      Object? grouping(String? value) =>
          (builder.search(searchContext(grouping: value))!['params']
              as Map)['grouping'];
      expect(grouping('sameSection'), 'sameSection');
      expect(grouping('identicalText'), 'identicalText');
      expect(grouping('weird'), isNull);
      expect(grouping(null), isNull);
    });

    test('fuzzyMaxDistance and pageSize are clamped', () {
      final params =
          builder.search(
                searchContext(fuzzyMaxDistance: 99, pageSize: 5000),
              )!['params']
              as Map;
      expect(params['fuzzyMaxDistance'], 10);
      expect(params['pageSize'], 1000);
    });

    test('ranking keys outside the pattern are dropped', () {
      final event = builder.search(
        searchContext(
          ranking: {
            'alpha': 1,
            '1bad': 2,
            'with-dash': 3,
            'x' * 65: 4,
            'nested': {'ok_key': 1, 'bad key': 2},
          },
        ),
      )!;
      expect((event['params'] as Map)['ranking'], {
        'alpha': 1,
        'nested': {'ok_key': 1},
      });
    });

    test('results with an unknown source or negative segment are dropped', () {
      final event = builder.resultsShown(searchContext(), 0, [
        result(rank: 1),
        result(rank: 2, source: 'magic'),
        result(rank: 3, segment: -1),
      ])!;
      expect((event['results'] as List).map((r) => (r as Map)['rank']), [1]);
      expect(
        builder.vote(
          searchContext(),
          result(source: 'x'),
          SearchFeedbackVote.like,
        ),
        isNull,
      );
      expect(
        builder.resultsShown(searchContext(), 0, [result(segment: -2)]),
        isNull,
      );
    });

    test('passageTextSource falls back to a valid value', () {
      final full =
          builder.open(
                searchContext(),
                result(passage: 'פסקה', passageSource: 'paragraph'),
                SearchFeedbackOpenVia.click,
                'open_abcdefgh',
              )!['result']
              as Map;
      expect(full['passageTextSource'], 'line');
    });

    test('engine checksum and embeddingDim are validated', () {
      final valid = 'A' * 64;
      expect(
        searchFeedbackEngineJson(
          SemanticEngineSnapshot(modelPackageChecksum: valid, embeddingDim: 0),
        ),
        allOf(
          containsPair('modelPackageChecksum', 'a' * 64),
          containsPair('embeddingDim', null),
        ),
      );
      expect(
        searchFeedbackEngineJson(
          const SemanticEngineSnapshot(modelPackageChecksum: 'abc123'),
        )['modelPackageChecksum'],
        isNull,
      );
    });
  });
}
