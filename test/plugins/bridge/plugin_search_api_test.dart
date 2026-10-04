import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/plugins/bridge/plugin_search_api.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/utils/facet_helper.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart' as engine;

import '../../support/search_engine_test_init.dart';

Future<void> main() async {
  // validateAgainstQuery מפצל את השאילתה דרך מנוע ה-Rust; הבדיקות שלו
  // מדולגות כשאין build נייטיבי זמין.
  final engineReady = await tryInitSearchEngine();

  group('PluginSearchRequest.fromArgs', () {
    test('ברירות מחדל תואמות את החיפוש המדויק של האפליקציה', () {
      final request = PluginSearchRequest.fromArgs({'query': 'ואהבת'});

      expect(request.searchMode, SearchMode.exact);
      expect(request.order, engine.ResultsOrder.relevance);
      expect(request.proximityScope, engine.SearchScope.wordDistance);
      expect(request.wordMatchMode, engine.WordMatchMode.all);
      expect(request.grouping, isNull);
      expect(request.limit, PluginSearchApi.defaultLimit);
      expect(request.offset, 0);
    });

    test('שאילתה ריקה נדחית', () {
      expect(
        () => PluginSearchRequest.fromArgs({'query': '   '}),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('error.invalid_params'),
          ),
        ),
      );
    });

    test('ערך enum לא מוכר מחזיר invalid_params ולא נופל לברירת מחדל', () {
      expect(
        () => PluginSearchRequest.fromArgs({'query': 'א', 'mode': 'regex'}),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            allOf(contains('error.invalid_params'), contains('regex')),
          ),
        ),
      );
    });

    test('limit נחתך לתקרה ו-offset שלילי נדחה', () {
      final request = PluginSearchRequest.fromArgs({
        'query': 'א',
        'limit': 5000,
      });
      expect(request.limit, PluginSearchApi.maxLimit);

      expect(
        () => PluginSearchRequest.fromArgs({'query': 'א', 'offset': -1}),
        throwsA(isA<Exception>()),
      );
    });

    test('חלון דפדוף מוגבל כדי למנוע הקצאה לא חסומה במנוע', () {
      final boundary = PluginSearchRequest.fromArgs({
        'query': 'א',
        'limit': PluginSearchApi.maxLimit,
        'offset': PluginSearchApi.maxResultWindow - PluginSearchApi.maxLimit,
      });
      expect(
        boundary.offset + boundary.limit,
        PluginSearchApi.maxResultWindow,
      );

      expect(
        () => PluginSearchRequest.fromArgs({
          'query': 'א',
          'limit': PluginSearchApi.maxLimit,
          'offset':
              PluginSearchApi.maxResultWindow - PluginSearchApi.maxLimit + 1,
        }),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('offset + limit'),
          ),
        ),
      );
    });

    test('negativeDistance/negativeProximityScope יורשים מהחיוביים', () {
      final request = PluginSearchRequest.fromArgs({
        'query': 'א',
        'mode': 'advanced',
        'distance': 4,
        'proximityScope': 'sameParagraph',
      });

      expect(request.negativeDistance, 4);
      expect(request.negativeProximityScope, engine.SearchScope.sameParagraph);
    });

    test('אפשרות מילה שאינה קיימת מחזירה invalid_params', () {
      expect(
        () => PluginSearchRequest.fromArgs({
          'query': 'א',
          'options': {'אפשרות מומצאת': true},
        }),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('unknown search option'),
          ),
        ),
      );
    });

    test('customSpacing מקבל רק זוג מילים סמוכות וערך לא-שלילי', () {
      Map<String, dynamic> withSpacing(Map<String, String> spacing) => {
        'query': 'א ב ג',
        'mode': 'advanced',
        'customSpacing': spacing,
      };

      expect(
        () => PluginSearchRequest.fromArgs(withSpacing({'first': '2'})),
        throwsA(isA<Exception>()),
      );
      // זוג לא-סמוך: המנוע היה מחיל את הערך על מרווחים אחרים בשקט.
      expect(
        () => PluginSearchRequest.fromArgs(withSpacing({'0-2': '2'})),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('adjacent'),
          ),
        ),
      );
      expect(
        () => PluginSearchRequest.fromArgs(withSpacing({'0-1': '-1'})),
        throwsA(isA<Exception>()),
      );
      expect(
        PluginSearchRequest.fromArgs(withSpacing({'1-2': '3'})).customSpacing,
        {'1-2': '3'},
      );
    });

    test('מספר שברי או לא-סופי נדחה במקום להיחתך', () {
      for (final limit in [1.9, double.nan, double.infinity]) {
        expect(
          () => PluginSearchRequest.fromArgs({'query': 'א', 'limit': limit}),
          throwsA(isA<Exception>()),
          reason: 'limit=$limit',
        );
      }
    });

    test('distance שלילי נדחה — המנוע מצפה ל-u32', () {
      expect(
        () => PluginSearchRequest.fromArgs({
          'query': 'א',
          'mode': 'advanced',
          'distance': -1,
        }),
        throwsA(isA<Exception>()),
      );
    });

    test('חיפוש מקורב דוחה מרחק שהמנוע ממילא היה חותך', () {
      expect(
        () => PluginSearchRequest.fromArgs({
          'query': 'א',
          'mode': 'fuzzy',
          'distance': PluginSearchApi.fuzzyMaxDistance + 1,
        }),
        throwsA(isA<Exception>()),
      );
    });

    test('wordMatchCount חוקי רק עם atLeast בחיפוש מתקדם', () {
      expect(
        () => PluginSearchRequest.fromArgs({
          'query': 'א ב',
          'wordMatchCount': 1,
        }),
        throwsA(isA<Exception>()),
      );

      final request = PluginSearchRequest.fromArgs({
        'query': 'א ב',
        'mode': 'advanced',
        'wordMatchMode': 'atLeast',
        'wordMatchCount': 1,
      });
      expect(request.wordMatchCount, 1);
    });

    test('פרמטר לא מוכר וטיפוסי קלט שגויים נדחים', () {
      for (final args in <Map<String, dynamic>>[
        {'query': 'א', 'limti': 5},
        {'query': 7},
        {'query': 'א', 'includeBookCounts': 'true'},
        {
          'query': 'א',
          'mode': 'advanced',
          'alternativeWords': {
            '0': [7],
          },
        },
      ]) {
        expect(
          () => PluginSearchRequest.fromArgs(args),
          throwsA(isA<Exception>()),
          reason: '$args',
        );
      }
    });

    test('פרמטרים בלעדיים-למתקדם נדחים במצב שאינו מתקדם', () {
      const advancedOnly = {
        'negativeQuery': 'לא',
        'alternativeWords': {
          '0': ['ב'],
        },
        'customSpacing': {'0-1': '2'},
        'proximityScope': 'sameParagraph',
        'wordMatchMode': 'anyWord',
      };

      for (final entry in advancedOnly.entries) {
        expect(
          () => PluginSearchRequest.fromArgs({
            'query': 'א ב',
            entry.key: entry.value,
          }),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              allOf(contains(entry.key), contains('advanced')),
            ),
          ),
          reason: entry.key,
        );
      }
    });

    test('אפשרויות מילה נדחות במצב מקורב, ואפשרות מתקדמת נדחית במדויק', () {
      expect(
        () => PluginSearchRequest.fromArgs({
          'query': 'ואהבת',
          'mode': 'fuzzy',
          'options': {'חלק ממילה': true},
        }),
        throwsA(isA<Exception>()),
      );

      expect(
        () => PluginSearchRequest.fromArgs({
          'query': 'ואהבת',
          'wordOptions': {
            'ואהבת_0': {'ראשי תיבות': true},
          },
        }),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('ראשי תיבות'),
          ),
        ),
      );
    });

    test('alternativeWords ממופה לפי אינדקס מילה מספרי', () {
      final request = PluginSearchRequest.fromArgs({
        'query': 'ואהבת לרעך',
        'mode': 'advanced',
        'alternativeWords': {
          '0': ['אהבת'],
        },
      });

      expect(request.alternativeWords, {
        0: ['אהבת'],
      });
    });

    test('grouping ממופה לערך המנוע', () {
      final request = PluginSearchRequest.fromArgs({
        'query': 'א',
        'grouping': 'identicalText',
      });
      expect(request.grouping, engine.ResultGrouping.identicalText);
    });

    test(
      'אפשרויות פר-מילה גוברות על הגלובליות',
      () {
        final request = PluginSearchRequest.fromArgs({
          'query': 'ואהבת',
          'mode': 'advanced',
          'options': {'קידומות': true},
          'wordOptions': {
            'ואהבת_0': {'סיומות': true},
          },
        });

        expect(request.effectiveSearchOptions, {
          'ואהבת_0': {'סיומות': true},
        });
      },
      skip: engineReady ? false : searchEngineSkipReason,
    );

    test(
      'אפשרות פר-מילה אינה מוחקת אפשרויות גלובליות ממילים אחרות',
      () {
        final request = PluginSearchRequest.fromArgs({
          'query': 'ואהבת לרעך',
          'mode': 'advanced',
          'options': {'קידומות': true},
          'wordOptions': {
            'ואהבת_0': {'סיומות': true},
          },
        });

        expect(request.effectiveSearchOptions, {
          'ואהבת_0': {'סיומות': true},
          'לרעך_1': {'קידומות': true},
        });
      },
      skip: engineReady ? false : searchEngineSkipReason,
    );

    test('המצב המדויק מקבל את אפשרויות המילה שלו', () {
      final request = PluginSearchRequest.fromArgs({
        'query': 'ואהבת',
        'wordOptions': {
          'ואהבת_0': {'חלק ממילה': true},
        },
      });

      expect(request.effectiveSearchOptions, {
        'ואהבת_0': {'חלק ממילה': true},
      });
    });
  });

  group('PluginSearchRequest.validateAgainstQuery', () {
    test(
      'מפתח פר-מילה שאינו תואם לשאילתה נדחה',
      () {
        final request = PluginSearchRequest.fromArgs({
          'query': 'ואהבת לרעך',
          'mode': 'advanced',
          'wordOptions': {
            'wrong_99': {'חלק ממילה': true},
          },
        });

        expect(
          request.validateAgainstQuery,
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('error.invalid_params'),
            ),
          ),
        );
      },
      skip: engineReady ? false : searchEngineSkipReason,
    );

    test(
      'אינדקס מילה חלופית מחוץ לטווח נדחה',
      () {
        final request = PluginSearchRequest.fromArgs({
          'query': 'ואהבת לרעך',
          'mode': 'advanced',
          'alternativeWords': {
            '5': ['אהבת'],
          },
        });

        expect(request.validateAgainstQuery, throwsA(isA<Exception>()));
      },
      skip: engineReady ? false : searchEngineSkipReason,
    );

    test('מפתחות תואמים עוברים', () {
      final request = PluginSearchRequest.fromArgs({
        'query': 'ואהבת לרעך',
        'mode': 'advanced',
        'wordOptions': {
          'ואהבת_0': {'חלק ממילה': true},
        },
        'alternativeWords': {
          '1': ['רעך'],
        },
        'customSpacing': {'0-1': '2'},
      });

      expect(request.validateAgainstQuery, returnsNormally);
    }, skip: engineReady ? false : searchEngineSkipReason);
  });

  group('PluginSearchApi.resolveFacets', () {
    Book? noBook(Map<String, dynamic> identity) => null;

    test('היקף ריק = כל הספרייה', () {
      expect(PluginSearchApi.resolveFacets({}, findBook: noBook), ['/']);
    });

    test('קטגוריות מנורמלות לנתיב facet', () {
      expect(
        PluginSearchApi.resolveFacets({
          'categories': ['תנך/תורה', '/הלכה'],
        }, findBook: noBook),
        ['/תנך/תורה', '/הלכה'],
      );
    });

    test('ספר מתורגם ל-facet של הספר', () {
      final book = TextBook(id: 7, title: 'בראשית', topics: 'תנך, תורה');

      final facets = PluginSearchApi.resolveFacets({
        'books': [
          {'id': 7},
        ],
      }, findBook: (_) => book);

      expect(facets.single, startsWith('/תנך/תורה/'));
    });

    test('ספר שלא נמצא מחזיר not_found', () {
      expect(
        () => PluginSearchApi.resolveFacets({
          'books': [
            {'bookId': 'לא קיים'},
          ],
        }, findBook: noBook),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('error.not_found'),
          ),
        ),
      );
    });

    test('תקופה לא מוכרת נדחית, ומוכרת מתווספת לצד שורש הקטגוריות', () {
      expect(
        () => PluginSearchApi.resolveFacets({
          'eras': ['תקופה מומצאת'],
        }, findBook: noBook),
        throwsA(isA<Exception>()),
      );

      // היקף ממדי בלבד חייב לכלול גם את שורש הקטגוריות, אחרת קבוצת
      // הקטגוריות ריקה והמנוע לא מחזיר דבר.
      expect(
        PluginSearchApi.resolveFacets({
          'eras': ['ראשונים'],
          'baseBooksOnly': true,
        }, findBook: noBook),
        [
          FacetHelper.buildEraFacet('ראשונים'),
          FacetHelper.baseDimensionFacet,
          '/',
        ],
      );
    });

    test('facet גולמי חייב להתחיל ב-"/"', () {
      expect(
        () => PluginSearchApi.resolveFacets({
          'facets': ['תנך'],
        }, findBook: noBook),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('PluginSearchApi.resultToJson', () {
    engine.SearchResult buildResult() => engine.SearchResult(
      title: 'בראשית',
      reference: 'בראשית, פרק א',
      text: 'בראשית ברא',
      id: BigInt.one,
      segment: BigInt.from(12),
      isPdf: false,
      filePath: 'id:7',
      mergedCount: 1,
      merged: const [],
      textStatus: engine.TextStatus.ok,
    );

    test('תוצאה עם ספר מזוהה נושאת זהות מלאה', () {
      final json = PluginSearchApi.resultToJson(
        buildResult(),
        TextBook(id: 7, title: 'בראשית', categoryPath: '/תנך/תורה'),
      );

      expect(json['id'], 7);
      expect(json['type'], 'text');
      expect(json['source'], 'library');
      expect(json['index'], 12);
      expect(json['reference'], 'בראשית, פרק א');
      expect(json['categoryPath'], '/תנך/תורה');
      expect(json.containsKey('merged'), isFalse);
    });

    test('ספר שלא זוהה נופל ל-type לפי isPdf ו-id ריק', () {
      final json = PluginSearchApi.resultToJson(buildResult(), null);

      expect(json['id'], isNull);
      expect(json['type'], 'text');
      expect(json['bookId'], 'בראשית');
    });

    test('תוצאה מאוחדת נושאת זהות מלאה של הספר האח', () {
      final result = engine.SearchResult(
        title: 'בראשית',
        reference: 'בראשית, פרק א',
        text: 'בראשית ברא',
        id: BigInt.one,
        segment: BigInt.from(12),
        isPdf: false,
        filePath: 'id:7',
        mergedCount: 2,
        merged: [
          engine.MergedSibling(
            title: 'מהדורה אחרת',
            reference: 'פרק א',
            id: BigInt.two,
            segment: BigInt.from(4),
            isPdf: true,
            filePath: 'id:8',
          ),
        ],
        textStatus: engine.TextStatus.ok,
      );

      final json = PluginSearchApi.resultToJson(
        result,
        TextBook(id: 7, title: 'בראשית'),
        booksByPath: {
          'id:8': PdfBook(
            id: 8,
            title: 'מהדורה אחרת',
            path: '/tmp/other.pdf',
          ),
        },
      );
      final sibling = (json['merged'] as List).single as Map;
      expect(sibling['id'], 8);
      expect(sibling['type'], 'pdf');
      expect(sibling['bookId'], 'מהדורה אחרת');
      expect(sibling['source'], 'library');
    });

    test('רגרסיה #774/#712: מפתח שהוסב לספר אחר אינו נושא זהות', () {
      // אינדקס לא מסונכרן: id:7 שייך כעת לספר אחר, והתוסף היה מקבל את
      // הכותרת הישנה יחד עם ה-id של הספר הזר.
      final json = PluginSearchApi.resultToJson(
        buildResult(),
        TextBook(id: 7, title: 'רבינו חננאל על מועד קטן'),
      );

      expect(json['id'], isNull);
      expect(json['source'], isNull);
      expect(json['bookId'], 'בראשית');
      expect(json['book'], 'בראשית');
      expect(json.containsKey('categoryPath'), isFalse);
    });

    test('רגרסיה: ספר אח שהוסב לספר אחר אינו נושא זהות', () {
      final result = engine.SearchResult(
        title: 'בראשית',
        reference: 'בראשית, פרק א',
        text: 'בראשית ברא',
        id: BigInt.one,
        segment: BigInt.from(12),
        isPdf: false,
        filePath: 'id:7',
        mergedCount: 2,
        merged: [
          engine.MergedSibling(
            title: 'מהדורה אחרת',
            reference: 'פרק א',
            id: BigInt.two,
            segment: BigInt.from(4),
            isPdf: true,
            filePath: 'id:8',
          ),
        ],
        textStatus: engine.TextStatus.ok,
      );

      final json = PluginSearchApi.resultToJson(
        result,
        TextBook(id: 7, title: 'בראשית'),
        booksByPath: {'id:8': PdfBook(id: 8, title: 'ספר זר', path: '/tmp/x')},
      );

      final sibling = (json['merged'] as List).single as Map;
      expect(sibling['id'], isNull);
      expect(sibling['source'], isNull);
      expect(sibling['bookId'], 'מהדורה אחרת');
      expect(sibling['book'], 'מהדורה אחרת');
      expect(sibling.containsKey('categoryPath'), isFalse);
    });

    test('מצב הטקסט מוחזר כמחרוזת', () {
      for (final status in engine.TextStatus.values) {
        final result = engine.SearchResult(
          title: 'בראשית',
          reference: 'בראשית, פרק א',
          text: status == engine.TextStatus.unavailable ? '' : 'בראשית ברא',
          id: BigInt.one,
          segment: BigInt.from(12),
          isPdf: false,
          filePath: 'id:7',
          mergedCount: 1,
          merged: const [],
          textStatus: status,
        );
        final json = PluginSearchApi.resultToJson(result, null);
        expect(json['textStatus'], status.name);
      }
      expect(engine.TextStatus.values.map((status) => status.name), [
        'ok',
        'stale',
        'unavailable',
      ]);
    });

    test('שדות התוצאה עצמם נשמרים גם כשהזהות נדחתה', () {
      final json = PluginSearchApi.resultToJson(
        buildResult(),
        TextBook(id: 7, title: 'ספר זר'),
      );

      expect(json['id'], isNull, reason: 'הזהות נדחתה');
      expect(json['bookId'], 'בראשית');
      expect(json['reference'], 'בראשית, פרק א');
      expect(json['text'], 'בראשית ברא');
      expect(json['index'], 12);
    });
  });

  test('describeOptions מכסה את כל הערכים החוקיים', () {
    final options = PluginSearchApi.describeOptions();

    expect(options['modes'], PluginSearchApi.searchModes.keys.toList());
    expect(options['orders'], contains('generation'));
    expect(options['eras'], contains('ראשונים'));
    expect(options['maxLimit'], PluginSearchApi.maxLimit);
    expect(options['maxResultWindow'], PluginSearchApi.maxResultWindow);
    expect(options['fuzzyMaxDistance'], PluginSearchApi.fuzzyMaxDistance);
  });
}
