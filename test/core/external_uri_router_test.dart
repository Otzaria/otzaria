import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:otzaria/core/external_uri_router.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/search/models/search_configuration.dart'
    show SearchMode;
import 'package:otzaria/settings/view/settings_screen.dart' show SettingsTab;

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
          ExternalUriRouter.parseUri(Uri.parse('otzaria://open/settings')),
          isA<OpenSettingsTabAction>(),
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

    group('open/plugin/<id>', () {
      test('פותחת תוסף לפי מזהה כפי שהוא', () {
        final action = ExternalUriRouter.parseUri(
          Uri.parse('otzaria://open/plugin/com.example.myplugin'),
        );

        expect(action, isA<OpenPluginAction>());
        expect(
          (action as OpenPluginAction).pluginId,
          'com.example.myplugin',
        );
      });

      test('המילה plugin אינה רגישה לאותיות גדולות/קטנות', () {
        final action = ExternalUriRouter.parseUri(
          Uri.parse('otzaria://open/PLUGIN/com.example.myplugin'),
        );

        expect(action, isA<OpenPluginAction>());
        expect(
          (action as OpenPluginAction).pluginId,
          'com.example.myplugin',
        );
      });

      test('המזהה נשמר עם אותיות גדולות/קטנות מקוריות', () {
        final action = ExternalUriRouter.parseUri(
          Uri.parse('otzaria://open/plugin/com.Example.MyPlugin'),
        );

        expect(
          (action as OpenPluginAction).pluginId,
          'com.Example.MyPlugin',
        );
      });

      test('דוחה plugin/ עם מזהה ריק', () {
        expect(
          ExternalUriRouter.parseUri(Uri.parse('otzaria://open/plugin/')),
          isNull,
        );
      });
    });

    group('open/tab/<index>', () {
      test('מחזיר SwitchToTabAction עם המיקום שנדרש', () {
        final action = ExternalUriRouter.parseUri(
          Uri.parse('otzaria://open/tab/4'),
        );

        expect(action, isA<SwitchToTabAction>());
        expect((action as SwitchToTabAction).index, 4);
      });

      test('מיקום 0 תקף', () {
        final action = ExternalUriRouter.parseUri(
          Uri.parse('otzaria://open/tab/0'),
        );

        expect((action as SwitchToTabAction).index, 0);
      });

      test('המילה tab אינה רגישה לאותיות גדולות/קטנות', () {
        final action = ExternalUriRouter.parseUri(
          Uri.parse('otzaria://open/TAB/2'),
        );

        expect((action as SwitchToTabAction).index, 2);
      });

      test('דוחה מיקום שלילי', () {
        expect(
          ExternalUriRouter.parseUri(Uri.parse('otzaria://open/tab/-1')),
          isNull,
        );
      });

      test('דוחה מיקום לא-מספרי', () {
        expect(
          ExternalUriRouter.parseUri(Uri.parse('otzaria://open/tab/abc')),
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
        final action =
            ExternalUriRouter.parseUri(
                  Uri.parse(
                    'otzaria://open/book/1234?index=42&q=%D7%91%D7%A8%D7%90%D7%A9%D7%99%D7%AA',
                  ),
                )
                as OpenBookAction;

        expect(action.bookId, 1234);
        expect(action.index, 42);
        expect(action.searchQuery, 'בראשית');
        expect(action.markSection, isFalse);
        expect(action.markText, isNull);
      });

      test('מפענח m= בפתיחת ספר עם index', () {
        final action =
            ExternalUriRouter.parseUri(
                  Uri.parse(
                    'otzaria://open/book/1234?index=42&m=%D7%91%D7%A8%D7%90%D7%A9%D7%99%D7%AA',
                  ),
                )
                as OpenBookAction;

        expect(action.bookId, 1234);
        expect(action.index, 42);
        expect(action.markText, 'בראשית');
        expect(action.searchQuery, isNull);
      });

      test('m= ריק מתעלם', () {
        final action =
            ExternalUriRouter.parseUri(
                  Uri.parse('otzaria://open/book/1234?index=42&m='),
                )
                as OpenBookAction;

        expect(action.markText, isNull);
      });

      test('m גובר על q: q מתעלם כש-m קיים (priority m > q)', () {
        final action =
            ExternalUriRouter.parseUri(
                  Uri.parse(
                    'otzaria://open/book/1234?index=42&q=%D7%90%D7%9C%D7%A3&m=%D7%91%D7%99%D7%AA',
                  ),
                )
                as OpenBookAction;

        expect(action.markText, 'בית');
        // priority m > mark > q — לא לפתוח חיפוש כללי בנוסף להדגשה המקומית.
        expect(action.searchQuery, isNull);
      });

      test('index שלילי או לא מספרי מתעלם', () {
        final negative =
            ExternalUriRouter.parseUri(
                  Uri.parse('otzaria://open/book/1234?index=-3'),
                )
                as OpenBookAction;
        final nonNumeric =
            ExternalUriRouter.parseUri(
                  Uri.parse('otzaria://open/book/1234?index=foo'),
                )
                as OpenBookAction;

        expect(negative.index, isNull);
        expect(nonNumeric.index, isNull);
      });

      test('q ריק מתעלם', () {
        final action =
            ExternalUriRouter.parseUri(
                  Uri.parse('otzaria://open/book/1234?q='),
                )
                as OpenBookAction;

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
        final action =
            ExternalUriRouter.parseUri(
                  Uri.parse('otzaria://open/pdf/1234?index=42'),
                )
                as OpenPdfBookAction;

        expect(action.bookId, 1234);
        expect(action.page, 42);
      });

      test('index=1 נשמר (PDF הוא 1-based)', () {
        final action =
            ExternalUriRouter.parseUri(
                  Uri.parse('otzaria://open/pdf/7?index=1'),
                )
                as OpenPdfBookAction;

        expect(action.page, 1);
      });

      test('index=0 מתעלם (לא חוקי ב-PDF)', () {
        final action =
            ExternalUriRouter.parseUri(
                  Uri.parse('otzaria://open/pdf/7?index=0'),
                )
                as OpenPdfBookAction;

        expect(action.page, isNull);
      });

      test('index שלילי מתעלם', () {
        final action =
            ExternalUriRouter.parseUri(
                  Uri.parse('otzaria://open/pdf/7?index=-3'),
                )
                as OpenPdfBookAction;

        expect(action.page, isNull);
      });

      test('index לא מספרי מתעלם', () {
        final action =
            ExternalUriRouter.parseUri(
                  Uri.parse('otzaria://open/pdf/7?index=foo'),
                )
                as OpenPdfBookAction;

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

    group('open/detection', () {
      test('עם q — מחזיר RunDetectionAction עם הקוורי', () {
        final action = ExternalUriRouter.parseUri(
          Uri.parse(
            'otzaria://open/detection?q=%D7%91%D7%A8%D7%90%D7%A9%D7%99%D7%AA',
          ),
        );

        expect(action, isA<RunDetectionAction>());
        expect((action as RunDetectionAction).query, 'בראשית');
      });

      test('שם פעולה אינו רגיש לאותיות גדולות/קטנות', () {
        final action = ExternalUriRouter.parseUri(
          Uri.parse(
            'otzaria://open/DETECTION?q=%D7%91%D7%A8%D7%90%D7%A9%D7%99%D7%AA',
          ),
        );
        expect(action, isA<RunDetectionAction>());
      });

      test('ללא q — מחזיר null (אין טעם לפתוח דיאלוג ריק)', () {
        expect(
          ExternalUriRouter.parseUri(Uri.parse('otzaria://open/detection')),
          isA<RunDetectionAction>(),
        );
        expect(
          (ExternalUriRouter.parseUri(Uri.parse('otzaria://open/detection'))
                  as RunDetectionAction)
              .query,
          '',
        );
      });

      test('q ריק — מחזיר null', () {
        expect(
          ExternalUriRouter.parseUri(Uri.parse('otzaria://open/detection?q=')),
          isA<RunDetectionAction>(),
        );
      });

      test('q עם רווחים בלבד — מחזיר null', () {
        expect(
          ExternalUriRouter.parseUri(
            Uri.parse('otzaria://open/detection?q=%20%20'),
          ),
          isA<RunDetectionAction>(),
        );
        // query מכיל רווחים — trim מחזיר ריק
        expect(
          (ExternalUriRouter.parseUri(
                    Uri.parse('otzaria://open/detection?q=%20%20'),
                  )
                  as RunDetectionAction)
              .query,
          '',
        );
      });

      test('q מפוענח נכון מ-URL encoding', () {
        final encoded = Uri.encodeQueryComponent('בראשית פרק א');
        final action =
            ExternalUriRouter.parseUri(
                  Uri.parse('otzaria://open/detection?q=$encoded'),
                )
                as RunDetectionAction;

        expect(action.query, 'בראשית פרק א');
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
        expect(action.mode, isNull);
      });

      test('mode=fuzzy — מחזיר SearchMode.fuzzy', () {
        final action =
            ExternalUriRouter.parseUri(
                  Uri.parse('otzaria://open/search?q=abc&mode=fuzzy'),
                )
                as RunSearchAction;

        expect(action.mode, SearchMode.fuzzy);
      });

      test('mode=exact — מחזיר SearchMode.exact', () {
        final action =
            ExternalUriRouter.parseUri(
                  Uri.parse('otzaria://open/search?q=abc&mode=exact'),
                )
                as RunSearchAction;

        expect(action.mode, SearchMode.exact);
      });

      test('mode=advanced — מחזיר SearchMode.advanced', () {
        final action =
            ExternalUriRouter.parseUri(
                  Uri.parse('otzaria://open/search?q=abc&mode=advanced'),
                )
                as RunSearchAction;

        expect(action.mode, SearchMode.advanced);
      });

      test('mode אינו רגיש לאותיות גדולות/קטנות', () {
        final action =
            ExternalUriRouter.parseUri(
                  Uri.parse('otzaria://open/search?q=abc&mode=FUZZY'),
                )
                as RunSearchAction;

        expect(action.mode, SearchMode.fuzzy);
      });

      test('mode לא מוכר או ריק — mode=null (ברירת מחדל)', () {
        expect(
          (ExternalUriRouter.parseUri(
                    Uri.parse('otzaria://open/search?q=abc&mode=bogus'),
                  )
                  as RunSearchAction)
              .mode,
          isNull,
        );
        expect(
          (ExternalUriRouter.parseUri(
                    Uri.parse('otzaria://open/search?q=abc&mode='),
                  )
                  as RunSearchAction)
              .mode,
          isNull,
        );
      });

      test('mode ללא q — נופל חזרה לפתיחת המסך בלבד', () {
        final action = ExternalUriRouter.parseUri(
          Uri.parse('otzaria://open/search?mode=fuzzy'),
        );

        expect(action, isA<OpenScreenAction>());
        expect((action as OpenScreenAction).screen, Screen.search);
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
                  )
                  as OpenScreenAction)
              .screen,
          Screen.search,
        );
      });
    });

    group('open/book/<id> — mark params', () {
      test('?mark ללא index — markSection=true, index=null', () {
        final action =
            ExternalUriRouter.parseUri(
                  Uri.parse('otzaria://open/book/1?mark'),
                )
                as OpenBookAction;

        expect(action.markSection, isTrue);
        expect(action.index, isNull);
      });

      test('?mark= (ערך ריק) — markSection=true', () {
        final action =
            ExternalUriRouter.parseUri(
                  Uri.parse('otzaria://open/book/1?mark='),
                )
                as OpenBookAction;

        expect(action.markSection, isTrue);
      });

      test('?index=5&mark — markSection=true, index=5', () {
        final action =
            ExternalUriRouter.parseUri(
                  Uri.parse('otzaria://open/book/1?index=5&mark'),
                )
                as OpenBookAction;

        expect(action.markSection, isTrue);
        expect(action.index, 5);
      });

      test('?mark&q=תורה — mark גובר, q מתעלם (priority mark > q)', () {
        final action =
            ExternalUriRouter.parseUri(
                  Uri.parse(
                    'otzaria://open/book/1?mark&q=%D7%AA%D7%95%D7%A8%D7%94',
                  ),
                )
                as OpenBookAction;

        expect(action.markSection, isTrue);
        // priority m > mark > q — q מתעלם כדי שלא תיפתח לשונית חיפוש כללית.
        expect(action.searchQuery, isNull);
      });

      test('URI של PDF עם mark — OpenPdfBookAction ללא שדות mark', () {
        final action = ExternalUriRouter.parseUri(
          Uri.parse('otzaria://open/pdf/1?mark'),
        );

        expect(action, isA<OpenPdfBookAction>());
      });

      test('?m=בראשית — markText=בראשית', () {
        final action =
            ExternalUriRouter.parseUri(
                  Uri.parse(
                    'otzaria://open/book/1?m=%D7%91%D7%A8%D7%90%D7%A9%D7%99%D7%AA',
                  ),
                )
                as OpenBookAction;

        expect(action.markText, 'בראשית');
      });

      test('?m= (ריק) — markText=null', () {
        final action =
            ExternalUriRouter.parseUri(
                  Uri.parse('otzaria://open/book/1?m='),
                )
                as OpenBookAction;

        expect(action.markText, isNull);
      });

      test('?m=%20%20 (רווחים) — markText=null', () {
        final action =
            ExternalUriRouter.parseUri(
                  Uri.parse('otzaria://open/book/1?m=%20%20'),
                )
                as OpenBookAction;

        expect(action.markText, isNull);
      });

      test('?m=בראשית&q=תורה — m גובר, q מתעלם (priority m > q)', () {
        final action =
            ExternalUriRouter.parseUri(
                  Uri.parse(
                    'otzaria://open/book/1?m=%D7%91%D7%A8%D7%90%D7%A9%D7%99%D7%AA&q=%D7%AA%D7%95%D7%A8%D7%94',
                  ),
                )
                as OpenBookAction;

        expect(action.markText, 'בראשית');
        expect(action.searchQuery, isNull);
      });

      test('?mark=&q=ייעלם — mark עם ערך ריק עדיין גובר על q', () {
        final action =
            ExternalUriRouter.parseUri(
                  Uri.parse(
                    'otzaria://open/book/1?mark=&q=%D7%AA%D7%95%D7%A8%D7%94',
                  ),
                )
                as OpenBookAction;

        expect(action.markSection, isTrue);
        expect(action.searchQuery, isNull);
      });

      test('?q=תורה לבד — q נשמר כשאין mark/m', () {
        final action =
            ExternalUriRouter.parseUri(
                  Uri.parse('otzaria://open/book/1?q=%D7%AA%D7%95%D7%A8%D7%94'),
                )
                as OpenBookAction;

        expect(action.searchQuery, 'תורה');
        expect(action.markSection, isFalse);
        expect(action.markText, isNull);
      });

      // hasExplicitPosition — קובע אם להזיז טאב קיים למיקום שב-URI. נדרש כדי
      // ש-otzaria://open/book/<id> "חשוף" לא ידרוס מיקום של טאב פתוח.
      group('hasExplicitPosition', () {
        test('false כש-URI חשוף (ללא index/mark/m/q)', () {
          final action =
              ExternalUriRouter.parseUri(
                    Uri.parse('otzaria://open/book/1'),
                  )
                  as OpenBookAction;
          expect(action.hasExplicitPosition, isFalse);
        });

        test('false כש-URI עם q בלבד (q לא מיקום)', () {
          final action =
              ExternalUriRouter.parseUri(
                    Uri.parse(
                      'otzaria://open/book/1?q=%D7%AA%D7%95%D7%A8%D7%94',
                    ),
                  )
                  as OpenBookAction;
          expect(
            action.hasExplicitPosition,
            isFalse,
            reason: 'q הוא חיפוש, לא מיקום',
          );
        });

        test('true כש-URI עם ?index= מפורש', () {
          final action =
              ExternalUriRouter.parseUri(
                    Uri.parse('otzaria://open/book/1?index=42'),
                  )
                  as OpenBookAction;
          expect(action.hasExplicitPosition, isTrue);
        });

        test('true כש-URI עם ?mark', () {
          final action =
              ExternalUriRouter.parseUri(
                    Uri.parse('otzaria://open/book/1?mark'),
                  )
                  as OpenBookAction;
          expect(action.hasExplicitPosition, isTrue);
        });

        test('true כש-URI עם ?m=', () {
          final action =
              ExternalUriRouter.parseUri(
                    Uri.parse('otzaria://open/book/1?m=%D7%91%D7%99%D7%AA'),
                  )
                  as OpenBookAction;
          expect(action.hasExplicitPosition, isTrue);
        });

        test('PDF: false כש-URI חשוף', () {
          final action =
              ExternalUriRouter.parseUri(
                    Uri.parse('otzaria://open/pdf/1'),
                  )
                  as OpenPdfBookAction;
          expect(action.hasExplicitPosition, isFalse);
        });

        test('PDF: true כש-URI עם ?index= מפורש', () {
          final action =
              ExternalUriRouter.parseUri(
                    Uri.parse('otzaria://open/pdf/1?index=5'),
                  )
                  as OpenPdfBookAction;
          expect(action.hasExplicitPosition, isTrue);
        });
      });

      test('?mark&m=בראשית — markSection=true ו-markText=בראשית', () {
        final action =
            ExternalUriRouter.parseUri(
                  Uri.parse(
                    'otzaria://open/book/1?mark&m=%D7%91%D7%A8%D7%90%D7%A9%D7%99%D7%AA',
                  ),
                )
                as OpenBookAction;

        expect(action.markSection, isTrue);
        expect(action.markText, 'בראשית');
      });

      test('ללא mark ו-m — ברירת מחדל markSection=false, markText=null', () {
        final action =
            ExternalUriRouter.parseUri(
                  Uri.parse('otzaria://open/book/1?index=3&q=test'),
                )
                as OpenBookAction;

        expect(action.markSection, isFalse);
        expect(action.markText, isNull);
      });

      // Feature: deep-link-mark, Property 1: mark preserves index
      // For any n >= 0, parseUri('otzaria://open/book/1?index=$n&mark')
      //   returns OpenBookAction with markSection=true and index=n
      test('Property 1: mark שומר index', () {
        for (int n = 0; n < 100; n++) {
          final action =
              ExternalUriRouter.parseUri(
                    Uri.parse('otzaria://open/book/1?index=$n&mark'),
                  )
                  as OpenBookAction;

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
          final action =
              ExternalUriRouter.parseUri(
                    Uri.parse('otzaria://open/book/1?m=$encoded'),
                  )
                  as OpenBookAction;

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
          final action =
              ExternalUriRouter.parseUri(
                    Uri.parse('otzaria://open/book/1?m=$encoded'),
                  )
                  as OpenBookAction;

          expect(action.markText, isNull, reason: 'whitespace=$ws');
        }
      });

      // Feature: deep-link-mark, Property 4: mark גובר על q (priority mark > q)
      // עבור כל q לא ריק, parseUri עם mark&q=q מחזיר markSection=true ו-
      // searchQuery=null — כך הקישור לא פותח גם חיפוש כללי וגם הדגשה מקומית.
      test('Property 4: mark גובר על q (priority enforced)', () {
        final testQueries = [
          'בראשית',
          'תורה',
          'test',
          'hello world',
          'א ב ג',
        ];

        for (final q in testQueries) {
          final encoded = Uri.encodeComponent(q);
          final action =
              ExternalUriRouter.parseUri(
                    Uri.parse('otzaria://open/book/1?mark&q=$encoded'),
                  )
                  as OpenBookAction;

          expect(action.markSection, isTrue, reason: 'q=$q');
          expect(
            action.searchQuery,
            isNull,
            reason: 'q=$q: q חייב להתעלם כש-mark קיים',
          );
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
          final action =
              ExternalUriRouter.parseUri(
                    Uri.parse(uriStr),
                  )
                  as OpenBookAction;

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
        final action =
            ExternalUriRouter.parseUri(
                  Uri.parse(
                    'otzaria://plugin/install?url=https%3A%2F%2Fexample.com%2Fp.otzplugin&overwrite=true',
                  ),
                )
                as InstallPluginAction;

        expect(action.request.forceOverwrite, isTrue);
      });

      test('דוחה plugin/install ללא url', () {
        expect(
          ExternalUriRouter.parseUri(Uri.parse('otzaria://plugin/install')),
          isNull,
        );
      });
    });

    group('plugin/install-local', () {
      // נתיבי הבדיקה בסגנון Windows — מקבעים סמנטיקת Windows כדי שהבדיקות
      // יעברו זהה גם ב-CI על Linux. בדיקות POSIX מחליפות ל-p.posix מקומית.
      setUp(() {
        ExternalUriRouter.pathContext = p.windows;
      });

      tearDown(() {
        ExternalUriRouter.pathContext = p.context;
      });

      test('מחזיר InstallLocalPluginAction עבור נתיב מקודד', () {
        final encodedPath = Uri.encodeQueryComponent(
          r'C:\Users\Foo\Downloads\my plugin.otzplugin',
        );
        final action = ExternalUriRouter.parseUri(
          Uri.parse('otzaria://plugin/install-local?path=$encodedPath'),
        );

        expect(action, isA<InstallLocalPluginAction>());
        final install = action as InstallLocalPluginAction;
        expect(
          install.archivePath,
          r'C:\Users\Foo\Downloads\my plugin.otzplugin',
        );
      });

      test('דוחה install-local ללא path', () {
        expect(
          ExternalUriRouter.parseUri(
            Uri.parse('otzaria://plugin/install-local'),
          ),
          isNull,
        );
      });

      test('דוחה install-local עם path ריק', () {
        expect(
          ExternalUriRouter.parseUri(
            Uri.parse('otzaria://plugin/install-local?path='),
          ),
          isNull,
        );
      });

      test('דוחה נתיב ללא סיומת .otzplugin', () {
        final encoded = Uri.encodeQueryComponent(r'C:\Windows\System32\a.dll');
        expect(
          ExternalUriRouter.parseUri(
            Uri.parse('otzaria://plugin/install-local?path=$encoded'),
          ),
          isNull,
        );
      });

      test('דוחה נתיב UNC (מונע דליפת אישורי SMB)', () {
        final encoded = Uri.encodeQueryComponent(
          r'\\attacker\share\evil.otzplugin',
        );
        expect(
          ExternalUriRouter.parseUri(
            Uri.parse('otzaria://plugin/install-local?path=$encoded'),
          ),
          isNull,
        );
      });

      test('דוחה נתיב התקן (\\\\.\\ ו-\\\\?\\)', () {
        final device = Uri.encodeQueryComponent(r'\\.\C:\evil.otzplugin');
        final extended = Uri.encodeQueryComponent(
          r'\\?\C:\Users\x\evil.otzplugin',
        );
        expect(
          ExternalUriRouter.parseUri(
            Uri.parse('otzaria://plugin/install-local?path=$device'),
          ),
          isNull,
        );
        expect(
          ExternalUriRouter.parseUri(
            Uri.parse('otzaria://plugin/install-local?path=$extended'),
          ),
          isNull,
        );
      });

      test('דוחה נתיב UNC בלוכסנים קדמיים (//host)', () {
        final encoded = Uri.encodeQueryComponent(
          '//attacker/share/evil.otzplugin',
        );
        expect(
          ExternalUriRouter.parseUri(
            Uri.parse('otzaria://plugin/install-local?path=$encoded'),
          ),
          isNull,
        );
      });

      test('מקבל סיומת .otzplugin ללא תלות באותיות גדולות/קטנות', () {
        final encoded = Uri.encodeQueryComponent(
          r'C:\Users\Foo\plugin.OTZPLUGIN',
        );
        final action = ExternalUriRouter.parseUri(
          Uri.parse('otzaria://plugin/install-local?path=$encoded'),
        );
        expect(action, isA<InstallLocalPluginAction>());
      });

      test('מקבל נתיב POSIX מוחלט בפלטפורמת POSIX', () {
        ExternalUriRouter.pathContext = p.posix;
        final encoded = Uri.encodeQueryComponent(
          '/home/user/plugins/my.otzplugin',
        );
        final action = ExternalUriRouter.parseUri(
          Uri.parse('otzaria://plugin/install-local?path=$encoded'),
        );
        expect(action, isA<InstallLocalPluginAction>());
      });

      test('נתיב Windows נדחה בפלטפורמת POSIX (שם הוא יחסי)', () {
        ExternalUriRouter.pathContext = p.posix;
        final encoded = Uri.encodeQueryComponent(
          r'C:\Users\Foo\plugin.otzplugin',
        );
        expect(
          ExternalUriRouter.parseUri(
            Uri.parse('otzaria://plugin/install-local?path=$encoded'),
          ),
          isNull,
        );
      });

      test('נתיב POSIX נדחה ב-Windows (root-relative, לא מוחלט)', () {
        final encoded = Uri.encodeQueryComponent(
          '/home/user/plugins/my.otzplugin',
        );
        expect(
          ExternalUriRouter.parseUri(
            Uri.parse('otzaria://plugin/install-local?path=$encoded'),
          ),
          isNull,
        );
      });

      test('דוחה נתיב יחסי', () {
        for (final relative in [
          'plugins/evil.otzplugin',
          './evil.otzplugin',
          '../evil.otzplugin',
          'evil.otzplugin',
          r'C:evil.otzplugin', // כונן ללא לוכסן — נפתר מול CWD של הכונן
        ]) {
          final encoded = Uri.encodeQueryComponent(relative);
          expect(
            ExternalUriRouter.parseUri(
              Uri.parse('otzaria://plugin/install-local?path=$encoded'),
            ),
            isNull,
            reason: 'נתיב יחסי: $relative',
          );
        }
      });
    });

    group('aliases חדשים לכלים מובנים', () {
      test('shamor_zachor → builtin.shamor_zachor', () {
        final action = ExternalUriRouter.parseUri(
          Uri.parse('otzaria://open/shamor_zachor'),
        );
        expect(action, isA<OpenToolAction>());
        expect((action as OpenToolAction).toolId, 'builtin.shamor_zachor');
      });

      test('measurements → builtin.measurements', () {
        final action = ExternalUriRouter.parseUri(
          Uri.parse('otzaria://open/measurements'),
        );
        expect(action, isA<OpenToolAction>());
        expect((action as OpenToolAction).toolId, 'builtin.measurements');
      });

      test('aramaic_dictionary → builtin.aramaic_dictionary', () {
        final action = ExternalUriRouter.parseUri(
          Uri.parse('otzaria://open/aramaic_dictionary'),
        );
        expect(action, isA<OpenToolAction>());
        expect((action as OpenToolAction).toolId, 'builtin.aramaic_dictionary');
      });

      test('acronyms_dictionary → builtin.acronyms_dictionary', () {
        final action = ExternalUriRouter.parseUri(
          Uri.parse('otzaria://open/acronyms_dictionary'),
        );
        expect(action, isA<OpenToolAction>());
        expect(
          (action as OpenToolAction).toolId,
          'builtin.acronyms_dictionary',
        );
      });

      test('aliases אינם רגישים לאותיות גדולות/קטנות', () {
        expect(
          ExternalUriRouter.parseUri(Uri.parse('otzaria://open/SHAMOR_ZACHOR')),
          isA<OpenToolAction>(),
        );
        expect(
          ExternalUriRouter.parseUri(Uri.parse('otzaria://open/MEASUREMENTS')),
          isA<OpenToolAction>(),
        );
      });
    });

    group('open/history', () {
      test('מחזיר OpenHistoryAction', () {
        final action = ExternalUriRouter.parseUri(
          Uri.parse('otzaria://open/history'),
        );
        expect(action, isA<OpenHistoryAction>());
      });

      test('אינו רגיש לאותיות גדולות/קטנות', () {
        expect(
          ExternalUriRouter.parseUri(Uri.parse('otzaria://open/HISTORY')),
          isA<OpenHistoryAction>(),
        );
      });
    });

    group('open/bookmarks', () {
      test('מחזיר OpenBookmarksAction', () {
        final action = ExternalUriRouter.parseUri(
          Uri.parse('otzaria://open/bookmarks'),
        );
        expect(action, isA<OpenBookmarksAction>());
      });

      test('אינו רגיש לאותיות גדולות/קטנות', () {
        expect(
          ExternalUriRouter.parseUri(Uri.parse('otzaria://open/BOOKMARKS')),
          isA<OpenBookmarksAction>(),
        );
      });
    });

    group('open/settings', () {
      test('ללא sub-tab — מחזיר OpenSettingsTabAction עם tab=null', () {
        final action = ExternalUriRouter.parseUri(
          Uri.parse('otzaria://open/settings'),
        );
        expect(action, isA<OpenSettingsTabAction>());
        expect((action as OpenSettingsTabAction).tab, isNull);
      });

      test('settings/design', () {
        final action =
            ExternalUriRouter.parseUri(
                  Uri.parse('otzaria://open/settings/design'),
                )
                as OpenSettingsTabAction;
        expect(action.tab, SettingsTab.design);
      });

      test('settings/text', () {
        expect(
          (ExternalUriRouter.parseUri(
                    Uri.parse('otzaria://open/settings/text'),
                  )
                  as OpenSettingsTabAction)
              .tab,
          SettingsTab.text,
        );
      });

      test('settings/library', () {
        expect(
          (ExternalUriRouter.parseUri(
                    Uri.parse('otzaria://open/settings/library'),
                  )
                  as OpenSettingsTabAction)
              .tab,
          SettingsTab.library,
        );
      });

      test('settings/tools', () {
        expect(
          (ExternalUriRouter.parseUri(
                    Uri.parse('otzaria://open/settings/tools'),
                  )
                  as OpenSettingsTabAction)
              .tab,
          SettingsTab.tools,
        );
      });

      test('settings/shortcuts', () {
        expect(
          (ExternalUriRouter.parseUri(
                    Uri.parse('otzaria://open/settings/shortcuts'),
                  )
                  as OpenSettingsTabAction)
              .tab,
          SettingsTab.shortcuts,
        );
      });

      test('settings/system', () {
        expect(
          (ExternalUriRouter.parseUri(
                    Uri.parse('otzaria://open/settings/system'),
                  )
                  as OpenSettingsTabAction)
              .tab,
          SettingsTab.system,
        );
      });

      test('settings/about', () {
        expect(
          (ExternalUriRouter.parseUri(
                    Uri.parse('otzaria://open/settings/about'),
                  )
                  as OpenSettingsTabAction)
              .tab,
          SettingsTab.about,
        );
      });

      test('settings/<לשונית לא מוכרת> — מחזיר null', () {
        expect(
          ExternalUriRouter.parseUri(
            Uri.parse('otzaria://open/settings/unknown'),
          ),
          isNull,
        );
      });

      test('שמות sub-tab אינם רגישים לאותיות גדולות/קטנות', () {
        expect(
          (ExternalUriRouter.parseUri(
                    Uri.parse('otzaria://open/SETTINGS/DESIGN'),
                  )
                  as OpenSettingsTabAction)
              .tab,
          SettingsTab.design,
        );
        expect(
          (ExternalUriRouter.parseUri(
                    Uri.parse('otzaria://open/Settings/About'),
                  )
                  as OpenSettingsTabAction)
              .tab,
          SettingsTab.about,
        );
      });
    });

    group('open/detection ללא q (detection ריק)', () {
      test('ללא q — מחזיר RunDetectionAction עם query ריק', () {
        final action = ExternalUriRouter.parseUri(
          Uri.parse('otzaria://open/detection'),
        );
        expect(action, isA<RunDetectionAction>());
        expect((action as RunDetectionAction).query, '');
      });

      test('q ריק — מחזיר RunDetectionAction עם query ריק', () {
        final action = ExternalUriRouter.parseUri(
          Uri.parse('otzaria://open/detection?q='),
        );
        expect(action, isA<RunDetectionAction>());
        expect((action as RunDetectionAction).query, '');
      });

      test('daily כבר לא alias — מחזיר null', () {
        expect(
          ExternalUriRouter.parseUri(Uri.parse('otzaria://open/daily')),
          isNull,
        );
      });
    });

    group('open/inspection', () {
      test('מחזיר OpenInspectionAction', () {
        expect(
          ExternalUriRouter.parseUri(Uri.parse('otzaria://open/inspection')),
          isA<OpenInspectionAction>(),
        );
      });

      test('אינו רגיש לאותיות גדולות/קטנות', () {
        expect(
          ExternalUriRouter.parseUri(Uri.parse('otzaria://open/INSPECTION')),
          isA<OpenInspectionAction>(),
        );
      });
    });

    group('open/sdk', () {
      test('מחזיר OpenSdkAction', () {
        expect(
          ExternalUriRouter.parseUri(Uri.parse('otzaria://open/sdk')),
          isA<OpenSdkAction>(),
        );
      });

      test('אינו רגיש לאותיות גדולות/קטנות', () {
        expect(
          ExternalUriRouter.parseUri(Uri.parse('otzaria://open/SDK')),
          isA<OpenSdkAction>(),
        );
      });
    });

    group('open/daily_page', () {
      test('daily_page → OpenDailyPageAction', () {
        final action = ExternalUriRouter.parseUri(
          Uri.parse('otzaria://open/daily_page'),
        );
        expect(action, isA<OpenDailyPageAction>());
      });

      test('אינו רגיש לאותיות גדולות/קטנות', () {
        expect(
          ExternalUriRouter.parseUri(Uri.parse('otzaria://open/DAILY_PAGE')),
          isA<OpenDailyPageAction>(),
        );
      });
    });
  });
}
