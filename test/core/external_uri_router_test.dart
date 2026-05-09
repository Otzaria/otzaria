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
      });

      test('מפענח index ו-q בפתיחת ספר', () {
        final action = ExternalUriRouter.parseUri(
          Uri.parse('otzaria://open/book/1234?index=42&q=%D7%91%D7%A8%D7%90%D7%A9%D7%99%D7%AA'),
        ) as OpenBookAction;

        expect(action.bookId, 1234);
        expect(action.index, 42);
        expect(action.searchQuery, 'בראשית');
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
