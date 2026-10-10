import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/library/view/book_preview_panel.dart';
import 'package:otzaria/library/view/category_preview_panel.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/theme/app_theme_data.dart';
import 'package:otzaria/widgets/lists/nav_tree_tile.dart';

import '../../helpers/memory_settings_cache.dart';

Category _category(String title, {String description = ''}) => Category(
  title: title,
  description: description,
  shortDescription: '',
  order: 0,
  subCategories: [],
  books: [],
  parent: null,
);

Future<void> _pump(
  WidgetTester tester, {
  required Category category,
  List<Category> subCategories = const [],
  List<Book> books = const [],
  VoidCallback? onOpen,
  bool alreadyOpen = false,
  double width = 400,
  double height = 600,
  double textScale = 1,
  Brightness brightness = Brightness.light,
  String parentPath = 'תנ״ך, ראשונים',
}) async {
  final cs = ColorScheme.fromSeed(
    seedColor: Colors.blue,
    brightness: brightness,
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: brightness == Brightness.light
          ? AppThemeData.light(cs, compactMenuMode: false)
          : AppThemeData.dark(cs, compactMenuMode: false),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: SizedBox(
              width: width,
              height: height,
              child: CategoryPreviewPanel(
                category: category,
                parentPath: parentPath,
                subCategories: subCategories,
                books: books,
                onOpen: alreadyOpen ? null : (onOpen ?? () {}),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    final loader = FontLoader('Roboto')
      ..addFont(rootBundle.load('fonts/Rubik-VariableFont_wght.ttf'));
    await loader.load();
  });

  group('categoryContentCountsText', () {
    test('יחיד, רבים והשמטת אפס', () {
      expect(
        categoryContentCountsText(subCategories: 1, books: 1),
        'תיקייה אחת · ספר אחד',
      );
      expect(categoryContentCountsText(subCategories: 0, books: 5), '5 ספרים');
      expect(categoryContentCountsText(subCategories: 3, books: 0), '3 תיקיות');
      expect(categoryContentCountsText(subCategories: 0, books: 0), isNull);
    });
  });

  testWidgets('מציג שם, נתיב, מונים ותוכן — בלי תיאור כשאין', (tester) async {
    await _pump(
      tester,
      category: _category('רש״י'),
      subCategories: [_category('תורה')],
      books: [TextBook(title: 'רש״י על בראשית')],
    );

    expect(find.text('רש״י'), findsOneWidget);
    expect(find.text('תנ״ך, ראשונים'), findsOneWidget);
    expect(find.text('תיקייה אחת · ספר אחד'), findsOneWidget);
    expect(find.text('תורה'), findsOneWidget);
    expect(find.textContaining('רש״י על בראשית'), findsOneWidget);
  });

  testWidgets('מציג את התיאור כשקיים ב-DB', (tester) async {
    await _pump(
      tester,
      category: _category('חסידות', description: 'ספרי תורת החסידות'),
    );

    expect(find.text('ספרי תורת החסידות'), findsOneWidget);
  });

  testWidgets('שורות התוכן אינן מנווטות; רק "פתח תיקייה" פותח', (
    tester,
  ) async {
    var opened = 0;
    await _pump(
      tester,
      category: _category('חסידות'),
      subCategories: [_category('חב״ד')],
      books: [TextBook(title: 'תניא')],
      onOpen: () => opened++,
    );

    for (final title in ['חב״ד', 'תניא']) {
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
      expect(opened, 0);
      await tester.pump(const Duration(milliseconds: 500));
    }

    await tester.tap(find.text('פתח תיקייה'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(opened, 1);
  });

  testWidgets('הכותרת, התיאור והמונים מיושרים לגבול הכרטיס', (tester) async {
    await _pump(
      tester,
      category: _category('תורה', description: 'ספרי התורה'),
      books: [TextBook(title: 'בראשית')],
    );
    final header = find.ancestor(
      of: find.text('תורה'),
      matching: find.byType(Row),
    );
    final card = find
        .descendant(
          of: find.byType(NavTreeGroupCard),
          matching: find.byType(Material),
        )
        .first;
    final cardRect = tester.getRect(card);
    final headerRect = tester.getRect(header);
    expect(headerRect.left, cardRect.left);
    expect(headerRect.right, cardRect.right);
    expect(tester.getRect(find.text('ספרי התורה')).right, cardRect.right);
    expect(tester.getRect(find.text('ספר אחד')).right, cardRect.right);
  });

  testWidgets('לחיצה כפולה על שורת תוכן פותחת את תיקיית האב בלבד', (
    tester,
  ) async {
    var opened = 0;
    await _pump(
      tester,
      category: _category('תורה'),
      subCategories: [_category('מפרשים')],
      books: [TextBook(title: 'בראשית')],
      onOpen: () => opened++,
    );
    for (final title in ['מפרשים', 'בראשית']) {
      await tester.tap(find.text(title));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
    }
    expect(opened, 2);
    for (final tile in tester.widgetList<NavTreeTile>(
      find.byType(NavTreeTile),
    )) {
      expect(tile.onTap, isNull);
      expect(tile.onToggleExpand, isNull);
      expect(tile.onFilter, isNull);
      expect(tile.hasChildren, isFalse);
    }
  });

  testWidgets('תיקייה שכבר פתוחה אינה מגיבה ללחיצה כפולה', (tester) async {
    var opened = 0;
    await _pump(
      tester,
      category: _category('תורה'),
      books: [TextBook(title: 'בראשית')],
      alreadyOpen: true,
      onOpen: () => opened++,
    );
    await tester.tap(find.text('בראשית'));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(find.text('בראשית'));
    await tester.pumpAndSettle();
    expect(opened, 0);
  });

  testWidgets('מחברים נחתכים ומושמטים כשהם ריקים או חסרים', (tester) async {
    await _pump(
      tester,
      category: _category('תורה'),
      subCategories: [_category('מפרשים')],
      books: [
        TextBook(title: 'בראשית', author: '  רבי משה  '),
        TextBook(title: 'שמות', author: '  '),
        TextBook(title: 'ויקרא'),
      ],
    );
    final rows = tester
        .widgetList<NavTreeTile>(find.byType(NavTreeTile))
        .toList();
    expect(rows.map((row) => row.title), ['מפרשים', 'בראשית', 'שמות', 'ויקרא']);
    expect(rows.map((row) => row.subtitle), [null, 'רבי משה', '', null]);
    final cards = tester.widgetList<NavTreeGroupCard>(
      find.byType(NavTreeGroupCard),
    );
    expect(cards.map((card) => card.isGroupStart), [true, false, false, false]);
    expect(cards.map((card) => card.isGroupEnd), [false, false, false, true]);
    expect(find.text('רבי משה'), findsOneWidget);
    expect(find.text(''), findsNothing);
    expect(rows.first.useFolderIcon, isTrue);
    expect(rows.skip(1).every((row) => !row.useFolderIcon), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('טקסט שנקטע שומר על tooltip מלא', (tester) async {
    const title =
        'פירוש התורה עם ביאורים והרחבות על כל פרשות השבוע ומועדי ישראל';
    const author = 'רבי משה בן רבי יהודה מחבר הפירוש והביאורים המלאים';
    await _pump(
      tester,
      width: 280,
      category: _category('תורה'),
      books: [TextBook(title: title, author: author)],
    );
    expect(find.byTooltip(title), findsOneWidget);
    expect(find.byTooltip(author), findsOneWidget);
    tester.state<RawTooltipState>(find.byTooltip(title)).ensureTooltipVisible();
    await tester.pumpAndSettle();
    expect(find.text(title), findsNWidgets(2));
  });

  testWidgets('רשימה של 10,000 ספרים בונה רק את אזור התצוגה גם בגלילה ובחזרה', (
    tester,
  ) async {
    final books = _CountingBooks(10000);
    await _pump(tester, category: _category('תורה'), books: books, height: 400);
    final initialReads = books.reads;
    expect(initialReads, lessThan(25));
    expect(find.byType(NavTreeTile).evaluate().length, lessThan(25));
    final initialIndices = Set<int>.of(books.indices);
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    final scrollReads = books.reads;
    expect(books.indices.difference(initialIndices), isNotEmpty);
    expect(books.reads, lessThan(100));
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    scrollable.position.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.text('ספר 0'), findsOneWidget);
    expect(find.byType(NavTreeTile).evaluate().length, lessThan(25));
    expect(books.reads, lessThan(150));
    expect(books.indices.length, lessThan(100));
    debugPrint(
      '10,000 books: initial=$initialReads, scrolled=$scrollReads, '
      'returned=${books.reads}, distinct=${books.indices.length}',
    );
    expect(books.indices, isNot(contains(9999)));
    expect(tester.takeException(), isNull);
  });

  for (final width in [280.0, 320.0, 400.0, 600.0]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      for (final brightness in Brightness.values) {
        testWidgets('RTL ברוחב $width, גודל $scale, ${brightness.name}', (
          tester,
        ) async {
          await _pump(
            tester,
            width: width,
            textScale: scale,
            brightness: brightness,
            category: _category('תורה', description: 'ספרי התורה ומפרשיהם'),
            subCategories: [_category('מפרשים')],
            books: [TextBook(title: 'בראשית', author: 'רבי משה')],
          );
          expect(tester.takeException(), isNull);
          expect(find.text('תורה'), findsOneWidget);
          final titleContext = tester.element(find.text('בראשית'));
          expect(Directionality.of(titleContext), TextDirection.rtl);
          expect(Theme.of(titleContext).brightness, brightness);
        });
      }
    }
  }

  testWidgets('כפתור הפתיחה יורד מתחת לנתיב ארוך בחלונית צרה עם טקסט מוגדל', (
    tester,
  ) async {
    const path = 'תנ״ך, מפרשים, ראשונים, פירושי התורה';
    await _pump(
      tester,
      width: 280,
      textScale: 2,
      parentPath: path,
      category: _category('פירושי התורה'),
      books: [TextBook(title: 'בראשית')],
    );
    expect(tester.takeException(), isNull);
    final button = tester.getRect(find.text('פתח תיקייה'));
    expect(button.top, greaterThan(tester.getRect(find.text(path)).bottom));

    await _pump(
      tester,
      width: 600,
      parentPath: path,
      category: _category('פירושי התורה'),
      books: [TextBook(title: 'בראשית')],
    );
    expect(tester.takeException(), isNull);
    final header = tester.getRect(find.text('פירושי התורה'));
    final wideButton = tester.getRect(find.text('פתח תיקייה'));
    expect(wideButton.top, lessThan(tester.getRect(find.text(path)).bottom));
    expect(wideButton.right, lessThan(header.left));
  });

  testWidgets('כיתוב החלונית הריקה ניתן להחלפה (ספרייה: ספר או תיקייה)', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BookPreviewPanel(emptyMessage: 'בחר ספר או תיקייה'),
        ),
      ),
    );
    expect(find.text('בחר ספר או תיקייה'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: BookPreviewPanel())),
    );
    expect(find.text('בחר ספר לתצוגה מקדימה'), findsOneWidget);
  });

  testWidgets('התיקייה הפתוחה כבר — בלי כפתור "פתח תיקייה"', (tester) async {
    await _pump(tester, category: _category('חסידות'), alreadyOpen: true);

    expect(find.text('חסידות'), findsOneWidget);
    expect(find.text('פתח תיקייה'), findsNothing);
  });
}

class _CountingBooks extends ListBase<Book> {
  final List<Book> _books;
  int reads = 0;
  final indices = <int>{};

  _CountingBooks(int count)
    : _books = List.generate(count, (index) => TextBook(title: 'ספר $index'));

  @override
  int get length => _books.length;

  @override
  set length(int value) => throw UnsupportedError('read only');

  @override
  Book operator [](int index) {
    reads++;
    indices.add(index);
    return _books[index];
  }

  @override
  void operator []=(int index, Book value) =>
      throw UnsupportedError('read only');
}
