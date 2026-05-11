import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/external_uri_router.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';

void main() {
  group('ExternalUriRouter', () {
    group('open/<target>', () {
      test('פותחת לוח שנה דרך alias', () {
        final action = ExternalUriRouter.parseUri(
          Uri.parse('otzaria://open/calendar'),
        );

        expect(action, isA<OpenToolAction>());
        expect((action as OpenToolAction).toolId, 'builtin.calendar');
      });

      test('aliases של כלים מובנים נוספים', () {
        expect(
          (ExternalUriRouter.parseUri(Uri.parse('otzaria://open/gematria'))
                  as OpenToolAction)
              .toolId,
          'builtin.gematria',
        );
        expect(
          (ExternalUriRouter.parseUri(Uri.parse('otzaria://open/notes'))
                  as OpenToolAction)
              .toolId,
          'builtin.notes',
        );
      });

      test('aliases של מסכים עליונים', () {
        expect(
          (ExternalUriRouter.parseUri(Uri.parse('otzaria://open/library'))
                  as OpenScreenAction)
              .screen,
          Screen.library,
        );
        expect(
          (ExternalUriRouter.parseUri(Uri.parse('otzaria://open/settings'))
                  as OpenScreenAction)
              .screen,
          Screen.settings,
        );
        expect(
          (ExternalUriRouter.parseUri(Uri.parse('otzaria://open/search'))
                  as OpenScreenAction)
              .screen,
          Screen.search,
        );
        expect(
          (ExternalUriRouter.parseUri(Uri.parse('otzaria://open/tools'))
                  as OpenScreenAction)
              .screen,
          Screen.more,
        );
      });

      test('escape hatch של tool/<id> עובר את המזהה כפי שהוא', () {
        final action = ExternalUriRouter.parseUri(
          Uri.parse('otzaria://open/tool/com.example.myplugin'),
        );

        expect(action, isA<OpenToolAction>());
        expect(
          (action as OpenToolAction).toolId,
          'com.example.myplugin',
        );
      });

      test('שמות פעולה אינם רגישים לאותיות גדולות/קטנות', () {
        expect(
          ExternalUriRouter.parseUri(Uri.parse('OTZARIA://OPEN/calendar')),
          isA<OpenToolAction>(),
        );
        expect(
          ExternalUriRouter.parseUri(Uri.parse('otzaria://open/CALENDAR')),
          isA<OpenToolAction>(),
        );
        expect(
          ExternalUriRouter.parseUri(Uri.parse('otzaria://open/Library')),
          isA<OpenScreenAction>(),
        );
        expect(
          (ExternalUriRouter.parseUri(Uri.parse('otzaria://open/BOOK/1234'))
                  as OpenBookAction)
              .bookId,
          1234,
        );
      });

      test('דוחה סכמה שאינה otzaria', () {
        expect(
          ExternalUriRouter.parseUri(Uri.parse('https://open/calendar')),
          isNull,
        );
      });

      test('דוחה host לא נתמך', () {
        expect(
          ExternalUriRouter.parseUri(Uri.parse('otzaria://unknown/x')),
          isNull,
        );
      });

      test('דוחה target לא מוכר', () {
        expect(
          ExternalUriRouter.parseUri(Uri.parse('otzaria://open/banana')),
          isNull,
        );
      });

      test('דוחה otzaria://open ללא target', () {
        expect(
          ExternalUriRouter.parseUri(Uri.parse('otzaria://open')),
          isNull,
        );
        expect(
          ExternalUriRouter.parseUri(Uri.parse('otzaria://open/')),
          isNull,
        );
      });

      test('דוחה tool/ עם מזהה ריק', () {
        expect(
          ExternalUriRouter.parseUri(Uri.parse('otzaria://open/tool/')),
          isNull,
        );
      });
    });

    group('open/book/<id>', () {
      test('פותחת ספר לפי מזהה DB', () {
        final action = ExternalUriRouter.parseUri(
          Uri.parse('otzaria://open/book/1234'),
        );

        expect(action, isA<OpenBookAction>());
        final book = action as OpenBookAction;
        expect(book.bookId, 1234);
        expect(book.index, isNull);
        expect(book.searchQuery, isNull);
        expect(book.markSection, isFalse);
        expect(book.markText, isNull);
      });

      test('מפענח index ו-q בפתיחת ספר', () {
        final action = ExternalUriRouter.parseUri(
          Uri.parse(
              'otzaria://open/book/1234?index=42&q=%D7%91%D7%A8%D7%90%D7%A9%D7%99%D7%AA'),
        ) as OpenBookAction;

        expect(action.bookId, 1234);
        expect(action.index, 42);
        expect(action.searchQuery, 'בראשית');
        expect(action.markSection, isFalse);
        expect(action.markText, isNull);
      });

      test('מפענח m= בפתיחת ספר עם index', () {
        final action = ExternalUriRouter.parseUri(
          Uri.parse(
            'otzaria://open/book/1234?index=42&m=%D7%91%D7%A8%D7%90%D7%A9%D7%99%D7%AA',
          ),
        ) as OpenBookAction;

        expect(action.bookId, 1234);
        expect(action.index, 42);
        expect(action.markText, 'בראשית');
        expect(action.searchQuery, isNull);
      });

      test('m= ריק מתעלם', () {
        final action = ExternalUriRouter.parseUri(
          Uri.parse('otzaria://open/book/1234?index=42&m='),
        ) as OpenBookAction;

        expect(action.markText, isNull);
      });

      test('m= ו-q= יכולים להתקיים יחד', () {
        final action = ExternalUriRouter.parseUri(
          Uri.parse(
            'otzaria://open/book/1234?index=42&q=%D7%90%D7%9C%D7%A3&m=%D7%91%D7%99%D7%AA',
          ),
        ) as OpenBookAction;

        expect(action.markText, 'בית');
        expect(action.searchQuery, 'אלף');
      });

      test('index שלילי או לא מספרי מתעלם', () {
        final negative = ExternalUriRouter.parseUri(
          Uri.parse('otzaria://open/book/1234?index=-3'),
        ) as OpenBookAction;
        final nonNumeric = ExternalUriRouter.parseUri(
          Uri.parse('otzaria://open/book/1234?index=foo'),
        ) as OpenBookAction;

        expect(negative.index, isNull);
        expect(nonNumeric.index, isNull);
      });

      test('q ריק מתעלם', () {
        final action = ExternalUriRouter.parseUri(
          Uri.parse('otzaria://open/book/1234?q='),
        ) as OpenBookAction;

        expect(action.searchQuery, isNull);
      });

      test('דוחה book/ עם מזהה לא מספרי', () {
        expect(
          ExternalUriRouter.parseUri(Uri.parse('otzaria://open/book/abc')),
          isNull,
        );
      });

      test('דוחה book/ עם מזהה ריק', () {
        expect(
          ExternalUriRouter.parseUri(Uri.parse('otzaria://open/book/')),
          isNull,
        );
      });

      test('דוחה book/ עם מזהה אפס או שלילי', () {
        expect(
          ExternalUriRouter.parseUri(Uri.parse('otzaria://open/book/0')),
          isNull,
        );
        expect(
          ExternalUriRouter.parseUri(Uri.parse('otzaria://open/book/-5')),
          isNull,
        );
      });
    });

    group('open/pdf/<id>', () {
      test('פותחת ספר PDF לפי מזהה DB', () {
        final action = ExternalUriRouter.parseUri(
          Uri.parse('otzaria://open/pdf/1234'),
        );

        expect(action, isA<OpenPdfBookAction>());
        final pdf = action as OpenPdfBookAction;
        expect(pdf.bookId, 1234);
        expect(pdf.page, isNull);
      });

      test('מפענח index כעמוד התחלתי (1-based)', () {
        final action = ExternalUriRouter.parseUri(
          Uri.parse('otzaria://open/pdf/1234?index=42'),
        ) as OpenPdfBookAction;

        expect(action.bookId, 1234);
        expect(action.page, 42);
      });

      test('index=1 נשמר (PDF הוא 1-based)', () {
        final action = ExternalUriRouter.parseUri(
          Uri.parse('otzaria://open/pdf/7?index=1'),
        ) as OpenPdfBookAction;

        expect(action.page, 1);
      });

      test('index=0 מתעלם (לא חוקי ב-PDF)', () {
        final action = ExternalUriRouter.parseUri(
          Uri.parse('otzaria://open/pdf/7?index=0'),
        ) as OpenPdfBookAction;

        expect(action.page, isNull);
      });

      test('index שלילי מתעלם', () {
        final action = ExternalUriRouter.parseUri(
          Uri.parse('otzaria://open/pdf/7?index=-3'),
        ) as OpenPdfBookAction;

        expect(action.page, isNull);
      });

      test('index לא מספרי מתעלם', () {
        final action = ExternalUriRouter.parseUri(
          Uri.parse('otzaria://open/pdf/7?index=foo'),
        ) as OpenPdfBookAction;

        expect(action.page, isNull);
      });

      test('שם פעולה אינו רגיש לאותיות גדולות/קטנות', () {
        final action = ExternalUriRouter.parseUri(
          Uri.parse('otzaria://open/PDF/1234'),
        );
        expect(action, isA<OpenPdfBookAction>());
        expect((action as OpenPdfBookAction).bookId, 1234);
      });

      test('דוחה pdf/ עם מזהה לא מספרי', () {
        expect(
          ExternalUriRouter.parseUri(Uri.parse('otzaria://open/pdf/abc')),
          isNull,
        );
      });

      test('דוחה pdf/ עם מזהה ריק', () {
        expect(
          ExternalUriRouter.parseUri(Uri.parse('otzaria://open/pdf/')),
          isNull,
        );
      });

      test('דוחה pdf/ עם מזהה אפס או שלילי', () {
        expect(
          ExternalUriRouter.parseUri(Uri.parse('otzaria://open/pdf/0')),
          isNull,
        );
        expect(
          ExternalUriRouter.parseUri(Uri.parse('otzaria://open/pdf/-5')),
          isNull,
        );
      });
    });

    group('open/search', () {
      test('ללא q — פתיחת המסך בלבד', () {
        final action = ExternalUriRouter.parseUri(
          Uri.parse('otzaria://open/search'),
        );

        expect(action, isA<OpenScreenAction>());
        expect((action as OpenScreenAction).screen, Screen.search);
      });

      test('עם q — מחזיר RunSearchAction עם הקוורי', () {
        final action = ExternalUriRouter.parseUri(
          Uri.parse(
            'otzaria://open/search?q=%D7%91%D7%A8%D7%90%D7%A9%D7%99%D7%AA',
          ),
        );

        expect(action, isA<RunSearchAction>());
        expect((action as RunSearchAction).query, 'בראשית');
      });

      test('q ריק/רווחים — נופל חזרה לפתיחת המסך בלבד', () {
        expect(
          (ExternalUriRouter.parseUri(Uri.parse('otzaria://open/search?q='))
                  as OpenScreenAction)
              .screen,
          Screen.search,
        );
        expect(
          (ExternalUriRouter.parseUri(
            Uri.parse('otzaria://open/search?q=%20%20'),
          ) as OpenScreenAction)
              .screen,
          Screen.search,
        );
      });
    });

    group('open/book/<id> — mark params', () {
      test('?mark ללא index — markSection=true, index=null', () {
        final action = ExternalUriRouter.parseUri(
          Uri.parse('otzaria://open/book/1?mark'),
        ) as OpenBookAction;

        expect(action.markSection, isTrue);
        expect(action.index, isNull);
      });

      test('?mark= (ערך ריק) — markSection=true', () {
        final action = ExternalUriRouter.parseUri(
          Uri.parse('otzaria://open/book/1?mark='),
        ) as OpenBookAction;

        expect(action.markSection, isTrue);
      });

      test('?index=5&mark — markSection=true, index=5', () {
        final action = ExternalUriRouter.parseUri(
          Uri.parse('otzaria://open/book/1?index=5&mark'),
        ) as OpenBookAction;

        expect(action.markSection, isTrue);
        expect(action.index, 5);
      });

      test('?mark&q=תורה — markSection=true, searchQuery=תורה', () {
        final action = ExternalUriRouter.parseUri(
          Uri.parse('otzaria://open/book/1?mark&q=%D7%AA%D7%95%D7%A8%D7%94'),
        ) as OpenBookAction;

        expect(action.markSection, isTrue);
        expect(action.searchQuery, 'תורה');
      });

      test('URI של PDF עם mark — OpenPdfBookAction ללא שדות mark', () {
        final action = ExternalUriRouter.parseUri(
          Uri.parse('otzaria://open/pdf/1?mark'),
        );

        expect(action, isA<OpenPdfBookAction>());
      });

      test('?m=בראשית — markText=בראשית', () {
        final action = ExternalUriRouter.parseUri(
          Uri.parse(
            'otzaria://open/book/1?m=%D7%91%D7%A8%D7%90%D7%A9%D7%99%D7%AA',
          ),
        ) as OpenBookAction;

        expect(action.markText, 'בראשית');
      });

      test('?m= (ריק) — markText=null', () {
        final action = ExternalUriRouter.parseUri(
          Uri.parse('otzaria://open/book/1?m='),
        ) as OpenBookAction;

        expect(action.markText, isNull);
      });

      test('?m=%20%20 (רווחים) — markText=null', () {
        final action = ExternalUriRouter.parseUri(
          Uri.parse('otzaria://open/book/1?m=%20%20'),
        ) as OpenBookAction;

        expect(action.markText, isNull);
      });

      test('?m=בראשית&q=תורה — markText ו-searchQuery שניהם', () {
        final action = ExternalUriRouter.parseUri(
          Uri.parse(
            'otzaria://open/book/1?m=%D7%91%D7%A8%D7%90%D7%A9%D7%99%D7%AA&q=%D7%AA%D7%95%D7%A8%D7%94',
          ),
        ) as OpenBookAction;

        expect(action.markText, 'בראשית');
        expect(action.searchQuery, 'תורה');
      });

      test('?mark&m=בראשית — markSection=true ו-markText=בראשית', () {
        final action = ExternalUriRouter.parseUri(
          Uri.parse(
            'otzaria://open/book/1?mark&m=%D7%91%D7%A8%D7%90%D7%A9%D7%99%D7%AA',
          ),
        ) as OpenBookAction;

        expect(action.markSection, isTrue);
        expect(action.markText, 'בראשית');
      });

      test('ללא mark ו-m — ברירת מחדל markSection=false, markText=null', () {
        final action = ExternalUriRouter.parseUri(
          Uri.parse('otzaria://open/book/1?index=3&q=test'),
        ) as OpenBookAction;

        expect(action.markSection, isFalse);
        expect(action.markText, isNull);
      });

      // Feature: deep-link-mark, Property 1: mark preserves index
      // For any n >= 0, parseUri('otzaria://open/book/1?index=$n&mark')
      //   returns OpenBookAction with markSection=true and index=n
      test('Property 1: mark שומר index', () {
        for (int n = 0; n < 100; n++) {
          final action = ExternalUriRouter.parseUri(
            Uri.parse('otzaria://open/book/1?index=$n&mark'),
          ) as OpenBookAction;

          expect(action.markSection, isTrue, reason: 'n=$n');
          expect(action.index, n, reason: 'n=$n');
        }
      });

      // Feature: deep-link-mark, Property 2: m param decoded correctly
      // For any non-empty string t, parseUri with m=Uri.encodeComponent(t)
      //   returns OpenBookAction with markText=t
      test('Property 2: m param decoded correctly', () {
        final testStrings = [
          'בראשית',
          'תורה',
          'hello world',
          'test123',
          'א ב ג',
          'special!@#',
          '日本語',
          'עברית עם רווחים',
        ];

        for (final text in testStrings) {
          final encoded = Uri.encodeComponent(text);
          final action = ExternalUriRouter.parseUri(
            Uri.parse('otzaria://open/book/1?m=$encoded'),
          ) as OpenBookAction;

          expect(action.markText, text, reason: 'text=$text');
        }
      });

      // Feature: deep-link-mark, Property 3: blank m is ignored
      // For any string of only whitespace s, parseUri with m=s
      //   returns OpenBookAction with markText=null
      test('Property 3: blank m is ignored', () {
        final whitespaceStrings = [
          '',
          ' ',
          '  ',
          '   ',
          '\t',
          '\n',
          ' \t\n ',
        ];

        for (final ws in whitespaceStrings) {
          final encoded = Uri.encodeComponent(ws);
          final action = ExternalUriRouter.parseUri(
            Uri.parse('otzaria://open/book/1?m=$encoded'),
          ) as OpenBookAction;

          expect(action.markText, isNull, reason: 'whitespace=$ws');
        }
      });

      // Feature: deep-link-mark, Property 4: mark and q coexist
      // For any non-empty q, parseUri with mark&q=q
      //   returns OpenBookAction with markSection=true AND searchQuery=q
      test('Property 4: mark and q coexist', () {
        final testQueries = [
          'בראשית',
          'תורה',
          'test',
          'hello world',
          'א ב ג',
        ];

        for (final q in testQueries) {
          final encoded = Uri.encodeComponent(q);
          final action = ExternalUriRouter.parseUri(
            Uri.parse('otzaria://open/book/1?mark&q=$encoded'),
          ) as OpenBookAction;

          expect(action.markSection, isTrue, reason: 'q=$q');
          expect(action.searchQuery, q, reason: 'q=$q');
        }
      });

      // Feature: deep-link-mark, Property 5: default behavior unchanged
      // For any URI without mark/m, parseUri returns markSection=false, markText=null
      test('Property 5: default behavior unchanged', () {
        final testUris = [
          'otzaria://open/book/1',
          'otzaria://open/book/1?index=5',
          'otzaria://open/book/1?q=test',
          'otzaria://open/book/1?index=10&q=search',
        ];

        for (final uriStr in testUris) {
          final action = ExternalUriRouter.parseUri(
            Uri.parse(uriStr),
          ) as OpenBookAction;

          expect(action.markSection, isFalse, reason: 'uri=$uriStr');
          expect(action.markText, isNull, reason: 'uri=$uriStr');
        }
      });
    });

    group('plugin/install', () {
      test('מחזיר InstallPluginAction עבור קישור תקין', () {
        final action = ExternalUriRouter.parseUri(
          Uri.parse(
            'otzaria://plugin/install?url=https%3A%2F%2Fexample.com%2Fplugin.otzplugin',
          ),
        );

        expect(action, isA<InstallPluginAction>());
        final install = action as InstallPluginAction;
        expect(
          install.request.downloadUri.toString(),
          'https://example.com/plugin.otzplugin',
        );
        expect(install.request.forceOverwrite, isFalse);
      });

      test('מעביר flag overwrite', () {
        final action = ExternalUriRouter.parseUri(
          Uri.parse(
            'otzaria://plugin/install?url=https%3A%2F%2Fexample.com%2Fp.otzplugin&overwrite=true',
          ),
        ) as InstallPluginAction;

        expect(action.request.forceOverwrite, isTrue);
      });

      test('דוחה plugin/install ללא url', () {
        expect(
          ExternalUriRouter.parseUri(Uri.parse('otzaria://plugin/install')),
          isNull,
        );
      });
    });
  });
}
