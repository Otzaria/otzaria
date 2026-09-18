import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/external_uri_router.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/utils/text/html_link_handler.dart';
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/link.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class _RecordingUrlLauncher extends UrlLauncherPlatform
    with MockPlatformInterfaceMixin {
  final List<String> launched = [];

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return true;
  }

  @override
  LinkDelegate? get linkDelegate => null;
}

Library _libraryWith(List<Book> books) => Library(
  categories: [
    Category(
      title: 'קטגוריה',
      description: '',
      shortDescription: '',
      order: 1,
      subCategories: [],
      books: books,
      parent: null,
    ),
  ],
);

void main() {
  group('יעד של קישור book://', () {
    test('ספר טקסט רגיל נמצא', () {
      final library = _libraryWith([
        TextBook(title: 'ברכות', filePath: 'C:/ספרים/ברכות.txt'),
      ]);
      expect(
        HtmlLinkHandler.resolveBookLinkTarget(library, 'ברכות')?.title,
        'ברכות',
      );
    });

    // ‏`findBookByTitle` משווה `runtimeType` ולא `is`, ולכן בלי העטיפה
    // ב-`toTextBook()` כל קישור `book://` אל ספר-מסמך היה מת — וב-HTML זו
    // הדרך המתועדת לקשר בין ספרים.
    for (final entry in const {
      'html': 'ספר.html',
      'htm': 'ספר.htm',
      'docx': 'ספר.docx',
      'epub': 'ספר.epub',
      'odt': 'ספר.odt',
    }.entries) {
      test('ספר-מסמך מסוג ${entry.key} נפתר לספר טקסט', () {
        final book = buildBookForFileType(
          fileType: entry.key,
          title: 'ספר',
          path: 'C:/ספרים/${entry.value}',
          filePath: 'C:/ספרים/${entry.value}',
          categoryId: 7,
        );
        expect(book, isA<ConvertibleDocumentBook>(), reason: entry.key);

        final resolved = HtmlLinkHandler.resolveBookLinkTarget(
          _libraryWith([book]),
          'ספר',
        );
        expect(resolved, isNotNull, reason: entry.key);
        // שדות הזהות נשמרים — בלעדיהם `getBookText` אינו מאתר את הספר.
        expect(resolved!.fileType, entry.key);
        expect(resolved.filePath, 'C:/ספרים/${entry.value}');
        expect(resolved.categoryId, 7);
      });
    }

    test('ספר PDF אינו יעד לקישור טקסט', () {
      final library = _libraryWith([
        PdfBook(title: 'ספר', path: 'C:/ספרים/ספר.pdf'),
      ]);
      expect(HtmlLinkHandler.resolveBookLinkTarget(library, 'ספר'), isNull);
    });

    test('ספר שאינו קיים מחזיר null', () {
      expect(
        HtmlLinkHandler.resolveBookLinkTarget(_libraryWith([]), 'אין'),
        isNull,
      );
    });
  });

  group('HtmlLinkHandler Markdown anchors', () {
    test('משווה slug של Markdown לכותרת עם פיסוק ורווחים', () {
      expect(
        HtmlLinkHandler.isHeaderMatch('0. מפה מהירה', '0-מפה-מהירה'),
        isTrue,
      );
      expect(
        HtmlLinkHandler.isHeaderMatch('פרק: מבוא כללי', 'פרק-מבוא-כללי'),
        isTrue,
      );
    });

    test('מוצא עוגן בכותרת מקוננת', () {
      final root = TocEntry(text: 'ראשי', index: 0, level: 1);
      root.children.add(
        TocEntry(
          text: '0. מפה מהירה',
          index: 7,
          level: 2,
          parent: root,
        ),
      );

      expect(
        HtmlLinkHandler.findHeaderIndexInToc([root], '0-מפה-מהירה'),
        7,
      );
    });

    test('אינו מחזיר התאמת substring לכותרת קצרה', () {
      expect(HtmlLinkHandler.isHeaderMatch('פרק ב', 'ב'), isFalse);
    });

    test('מוצא עוגן יעד מפורש שהוגדר ב-<a name>', () {
      expect(
        HtmlLinkHandler.findAnchorIndex(
          const [
            '<p>פתיחה</p>',
            '<a name="3a-סוגי-קשר"></a>',
            '<h2 id="3א-סוגי-קשר-connection-type">3א. סוגי קשר</h2>',
          ],
          '3a-סוגי-קשר',
        ),
        1,
      );
    });

    test('עוגן יעד שאינו קיים אינו מוחזר', () {
      expect(
        HtmlLinkHandler.findAnchorIndex(
          const ['<a name="אחר"></a>'],
          'לא-קיים',
        ),
        isNull,
      );
    });

    test('מעדיף id מפורש של כותרת גם כשהטקסט שונה', () {
      expect(
        HtmlLinkHandler.findAnchorIndex(
          const ['<p>פתיחה</p>', '<h2 id="2-ספירת-db">נוסח אחר</h2>'],
          '2-ספירת-db',
        ),
        1,
      );
    });
  });

  group('קישורים חיצוניים ממסמך', () {
    test('מתיר רק http, https ו-mailto תקינים', () {
      expect(
        HtmlLinkHandler.externalUriFor('https://example.test/דף')?.scheme,
        'https',
      );
      expect(
        HtmlLinkHandler.externalUriFor('mailto:test@example.test')?.scheme,
        'mailto',
      );
      expect(HtmlLinkHandler.externalUriFor('javascript:alert(1)'), isNull);
      expect(HtmlLinkHandler.externalUriFor('file:///secret'), isNull);
      expect(HtmlLinkHandler.externalUriFor('//example.test'), isNull);
      expect(HtmlLinkHandler.externalUriFor('https:בלי-מארח'), isNull);
    });

    testWidgets('פותח יעד מאומת באפליקציה חיצונית', (tester) async {
      final launcher = _RecordingUrlLauncher();
      final previousLauncher = UrlLauncherPlatform.instance;
      UrlLauncherPlatform.instance = launcher;
      addTearDown(() => UrlLauncherPlatform.instance = previousLauncher);

      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (builderContext) {
              context = builderContext;
              return const SizedBox();
            },
          ),
        ),
      );

      final handled = await HtmlLinkHandler.handleLink(
        context,
        'https://example.test/word-link',
        (_) {},
      );

      expect(handled, isTrue);
      expect(launcher.launched, ['https://example.test/word-link']);
    });
  });

  // תוכן ספר — כולל ספר ממסד מצורף — יכול רק לנווט: פעולות otzaria:// אינן מופעלות ממנו.
  group('otzaria:// actions inside book content', () {
    const actionLinks = [
      'otzaria://plugin/install?url=https%3A%2F%2Fexample.com%2Fp.otzplugin',
      'otzaria://plugin/install-local?path=C%3A%2Fp.otzplugin',
      'otzaria://library/reindex',
      'otzaria://open/book/7?source=db%3Alib-a',
    ];

    test('are real app actions, yet never external or book links', () {
      for (final url in actionLinks) {
        expect(
          ExternalUriRouter.parseUri(Uri.parse(url)),
          isNotNull,
          reason: url,
        );
        expect(HtmlLinkHandler.externalUriFor(url), isNull, reason: url);
        expect(HtmlLinkHandler.opensAnotherBook(url), isFalse, reason: url);
      }
    });

    testWidgets('handleLink ignores them without launching anything', (
      tester,
    ) async {
      final launcher = _RecordingUrlLauncher();
      final previousLauncher = UrlLauncherPlatform.instance;
      UrlLauncherPlatform.instance = launcher;
      addTearDown(() => UrlLauncherPlatform.instance = previousLauncher);

      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (builderContext) {
              context = builderContext;
              return const SizedBox();
            },
          ),
        ),
      );

      for (final url in actionLinks) {
        final opened = <Object>[];
        final handled = await HtmlLinkHandler.handleLink(
          context,
          url,
          opened.add,
        );
        expect(handled, isFalse, reason: url);
        expect(opened, isEmpty, reason: url);
      }
      expect(launcher.launched, isEmpty);
    });
  });
}
