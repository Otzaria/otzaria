import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/book_identity.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/plugins/bridge/plugin_semantic_api.dart';
import 'package:otzaria/semantic_search/models/semantic_availability.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart' as engine;

final _berakhot = TextBook(id: 7, title: 'ברכות');

Book? _find(Map<String, dynamic> identity) =>
    identity['bookId'] == 'ברכות' || identity['id'] == 7 ? _berakhot : null;

engine.SemanticNearestInput _parse(Map<String, dynamic> args) =>
    PluginSemanticApi.parseNearest(
      args,
      findBook: _find,
      bookPaths: ['id:7'],
    );

Matcher _invalid(String fragment) => throwsA(
  predicate(
    (Object? error) =>
        '$error'.contains('error.invalid_params') &&
        '$error'.contains(fragment),
    'error.invalid_params containing "$fragment"',
  ),
);

String _vector(List<double> values) {
  final data = ByteData(values.length * 4);
  for (var i = 0; i < values.length; i++) {
    data.setFloat32(i * 4, values[i], Endian.little);
  }
  return base64.encode(data.buffer.asUint8List());
}

engine.SemanticNearestHit _hit(int segment, {Float32List? pointScores}) =>
    engine.SemanticNearestHit(
      filePath: BookIdentity.indexedFilePath(_berakhot),
      id: BigInt.from(segment),
      title: 'ברכות',
      reference: 'ברכות ב.',
      segment: BigInt.from(segment),
      isPdf: false,
      matchedWindow: 0,
      score: 0.5,
      point: 0,
      pointScores: pointScores ?? Float32List(0),
    );

engine.SemanticNearestResponse _response({
  List<engine.SemanticNearestHit> hits = const [],
  List<engine.SemanticNearestList> perPoint = const [],
}) => engine.SemanticNearestResponse(
  hits: hits,
  perPoint: perPoint,
  generation: BigInt.from(4),
  vectorsLibraryVersion: 30,
  unresolved: 1,
  staleDropped: 0,
  truncated: false,
  embedMs: BigInt.one,
  scanMs: BigInt.two,
  resolveMs: BigInt.from(3),
  rescoreMs: BigInt.zero,
);

void main() {
  group('parseNearest', () {
    test('ברירות המחדל: רשימה אחת, 50 לכל נקודה, כל הספרייה', () {
      final input = _parse({
        'from': [
          {'text': 'אמר רבא'},
        ],
      });
      expect(input.points.single.text, 'אמר רבא');
      expect(input.points.single.asPassage, isFalse);
      expect(input.topK, PluginSemanticApi.defaultK);
      expect(input.pool, engine.SemanticPool.best);
      expect(input.maxCandidates, PluginSemanticApi.defaultMaxCandidates);
      expect(input.rescore, isFalse);
      expect(input.minScore, isNull);
      expect(input.exclude, isEmpty);
      expect(input.facets, ['/']);
    });

    test('נקודת קטע, וקטור, טווח להשמטה והיקף', () {
      final input = _parse({
        'from': [
          {'text': 'שורה', 'as': 'passage'},
          {
            'vector': _vector([0.5, -1, 2]),
          },
        ],
        'k': 7,
        'rescore': true,
        'minScore': 0.3,
        'exclude': [
          {'bookId': 'ברכות', 'from': 3, 'to': 9},
        ],
        'categories': ['/תלמוד בבלי'],
      });
      expect(input.points[0].asPassage, isTrue);
      expect(input.points[1].vector, [0.5, -1, 2]);
      expect(input.topK, 7);
      expect(input.rescore, isTrue);
      expect(input.minScore, closeTo(0.3, 1e-9));
      final span = input.exclude.single;
      expect(span.filePath, BookIdentity.indexedFilePath(_berakhot));
      expect(span.fromSegment, BigInt.from(3));
      expect(span.toSegment, BigInt.from(9));
      expect(input.facets, isNot(contains('/')));
    });

    test('perPoint אינו מקבל rescore ו-maxCandidates', () {
      final base = {
        'from': [
          {'text': 'א'},
        ],
        'pool': 'perPoint',
      };
      expect(_parse(base).pool, engine.SemanticPool.perPoint);
      expect(() => _parse({...base, 'rescore': true}), _invalid('rescore'));
      expect(
        () => _parse({...base, 'maxCandidates': 10}),
        _invalid('maxCandidates'),
      );
    });

    test('perPoint חסום בסך השורות של כל הרשימות', () {
      expect(
        () => _parse({
          'from': [
            for (var i = 0; i < 64; i++) {'text': '$i'},
          ],
          'pool': 'perPoint',
          'k': 2000,
        }),
        _invalid('points × k'),
      );
    });

    test('קלט שגוי נדחה ולא נבלע', () {
      final text = {'text': 'א'};
      for (final (args, fragment) in [
        (<String, dynamic>{}, 'from'),
        (
          {
            'from': [
              for (var i = 0; i < 65; i++) {'text': '$i'},
            ],
          },
          'at most 64',
        ),
        (
          {
            'from': [
              {
                'text': 'א',
                'vector': _vector([1]),
              },
            ],
          },
          'exactly one',
        ),
        (
          {
            'from': [
              {'text': '  '},
            ],
          },
          'non-empty',
        ),
        (
          {
            'from': [
              {'text': 'א', 'as': 'document'},
            ],
          },
          '"query" or "passage"',
        ),
        (
          {
            'from': [
              {'vector': 'AAA='},
            ],
          },
          'float32',
        ),
        (
          {
            'from': [text],
            'k': 0,
          },
          'k must be between',
        ),
        (
          {
            'from': [text],
            'k': 2.5,
          },
          'whole number',
        ),
        (
          {
            'from': [text],
            'pool': 'all',
          },
          'pool',
        ),
        (
          {
            'from': [text],
            'minScore': 'high',
          },
          'minScore',
        ),
        (
          {
            'from': [text],
            'exclude': [
              {'bookId': 'ברכות', 'from': 5, 'to': 2},
            ],
          },
          'must not exceed to',
        ),
        (
          {
            'from': [text],
            'limit': 5,
          },
          'unknown parameter "limit"',
        ),
      ]) {
        expect(() => _parse(args), _invalid(fragment), reason: '$args');
      }
    });

    test('ספר לא מוכר ב-exclude הוא not_found', () {
      expect(
        () => _parse({
          'from': [
            {'text': 'א'},
          ],
          'exclude': [
            {'bookId': 'שבת', 'from': 0, 'to': 1},
          ],
        }),
        throwsA(predicate((Object? e) => '$e'.contains('error.not_found'))),
      );
    });
  });

  test('היקף לפי קטגוריה ומחבר מצטרף למפתחות האינדקס הרשמיים', () {
    final input = _parse({
      'from': [
        {'text': 'א'},
      ],
      'facets': ['/תלמוד', '/author/רש״י', '/base'],
    });
    expect(input.facets, ['/תלמוד', '/author/רש״י', '/base']);
    expect(input.bookPaths, ['id:7']);
  });

  test('היקף והחרגות דוחים זהות של ספר אישי או ממסד מצורף', () {
    for (final source in [BookSource.user, BookSource.attached('extra')]) {
      final book = TextBook(id: 8, title: 'פרטי', source: source);
      for (final field in ['books', 'exclude']) {
        expect(
          () => PluginSemanticApi.parseNearest(
            {
              'from': [
                {'text': 'א'},
              ],
              field: [
                {
                  'id': 8,
                  'source': source.wireKey,
                  if (field == 'exclude') ...{'from': 0, 'to': 2},
                },
              ],
            },
            findBook: (_) => book,
            bookPaths: ['id:7'],
          ),
          throwsA(predicate((Object? e) => '$e'.contains('error.not_found'))),
        );
      }
    }
  });

  test('ספר מקובץ רגיל מסונן גם כשמקור ברירת המחדל שלו רשמי', () {
    expect(TextBook(title: 'קובץ אישי').hasOfficialSemanticIdentity, isFalse);
    expect(
      TextBook(
        id: 8,
        title: 'קובץ אישי',
        filePath: '/book.txt',
      ).hasOfficialSemanticIdentity,
      isFalse,
    );
    expect(
      PdfBook(title: 'פרטי', path: '/book.pdf').hasOfficialSemanticIdentity,
      isFalse,
    );
    expect(
      PdfBook(
        title: 'ברכות',
        path: '/book.pdf',
        externalLibraryId: 'talmud-pdf:ברכות',
      ).hasOfficialSemanticIdentity,
      isTrue,
    );
  });

  group('responseChunks', () {
    final byPath = {BookIdentity.indexedFilePath(_berakhot): _berakhot};

    test('שורות בקבוצות של 500, ואחריהן done', () {
      final chunks = PluginSemanticApi.responseChunks(
        _response(hits: [for (var i = 0; i < 1001; i++) _hit(i)]),
        byPath,
        rescored: false,
      );
      expect(chunks.map((c) => c['type']), ['hits', 'hits', 'hits', 'done']);
      expect(
        [for (final c in chunks.take(3)) (c['hits'] as List).length],
        [500, 500, 1],
      );
      final first = (chunks.first['hits'] as List).first as Map;
      expect(first['bookId'], 'ברכות');
      expect(first['id'], 7);
      expect(first['index'], 0);
      expect(first['window'], 0);
      expect(first.containsKey('point'), isTrue);
      expect(first.containsKey('pointScores'), isFalse);
      expect(first.containsKey('text'), isFalse);
      final done = chunks.last;
      expect(done['generation'], 4);
      expect(done['clipped'], isFalse);
    });

    test('perPoint: רשימה לכל נקודה, גם ריקה', () {
      final chunks = PluginSemanticApi.responseChunks(
        _response(
          perPoint: [
            engine.SemanticNearestList(hits: [_hit(1)]),
            const engine.SemanticNearestList(hits: []),
          ],
        ),
        byPath,
        rescored: false,
      );
      expect([for (final c in chunks) c['point']], [0, 1, null]);
      expect(chunks.elementAt(1)['hits'], isEmpty);
    });

    test('ציון בלי וקטור הוא null; זהות חסרה או אישית מושמטת', () {
      final hit = _hit(
        2,
        pointScores: Float32List.fromList([0.25, double.nan]),
      );
      final json = PluginSemanticApi.hitToJson(hit, byPath, rescored: true);
      expect(json?['pointScores'], [0.25, null]);
      expect(
        PluginSemanticApi.hitToJson(hit, const {}, rescored: true),
        isNull,
      );
      final personal = TextBook(id: 7, title: 'ברכות', source: BookSource.user);
      expect(
        PluginSemanticApi.hitToJson(hit, {
          hit.filePath: personal,
        }, rescored: true),
        isNull,
      );
    });

    test('יותר מ-maxHits שורות נחתכות ומסומנות', () {
      final chunks = PluginSemanticApi.responseChunks(
        _response(
          hits: [
            for (var i = 0; i < PluginSemanticApi.maxHits + 3; i++) _hit(i),
          ],
        ),
        byPath,
        rescored: false,
      );
      final sent = chunks
          .where((c) => c['type'] == 'hits')
          .fold<int>(0, (sum, c) => sum + (c['hits'] as List).length);
      expect(sent, PluginSemanticApi.maxHits);
      expect(chunks.last['clipped'], isTrue);
    });
  });

  group('status and tokens', () {
    test('ready רק כשאפשר לחפש; בלי הסכמה תמיד consentRequired', () {
      expect(
        PluginSemanticApi.phaseOf(
          const SemanticAvailability(
            phase: SemanticAvailabilityPhase.ready,
            consentGranted: true,
          ),
        ),
        'ready',
      );
      expect(
        PluginSemanticApi.phaseOf(
          const SemanticAvailability(
            phase: SemanticAvailabilityPhase.needsDownload,
            consentGranted: false,
          ),
        ),
        'consentRequired',
      );
      expect(
        PluginSemanticApi.phaseOf(
          const SemanticAvailability(
            phase: SemanticAvailabilityPhase.hidden,
            consentGranted: false,
          ),
        ),
        'hidden',
      );
    });

    test('countTokens בודק את הטקסטים', () {
      expect(
        PluginSemanticApi.parseTokenTexts({
          'texts': ['א', 'ב'],
        }),
        ['א', 'ב'],
      );
      expect(
        () => PluginSemanticApi.parseTokenTexts({'texts': []}),
        _invalid('texts'),
      );
      expect(
        () => PluginSemanticApi.parseTokenTexts({
          'texts': ['א', 3],
        }),
        _invalid('texts'),
      );
      expect(
        () => PluginSemanticApi.parseTokenTexts({
          'texts': ['א'],
          'as': 'query',
        }),
        _invalid('unknown parameter'),
      );
    });

    test('רק ספרים רשמיים מהקטלוג כלולים בכיסוי', () {
      final officialPath = BookIdentity.indexedFilePath(_berakhot);
      final personal = TextBook(id: 8, title: 'אישי', source: BookSource.user);
      final personalPath = BookIdentity.indexedFilePath(personal);
      final json = PluginSemanticApi.coveredBooksToJson(
        {officialPath, personalPath, 'id:999'},
        {officialPath: _berakhot, personalPath: personal},
      );
      expect((json['books'] as List).single['title'], 'ברכות');
    });
  });
}
