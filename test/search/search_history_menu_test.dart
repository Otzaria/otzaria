import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/view/search_history_menu.dart';
import 'package:otzaria/widgets/controls/app_icon_button.dart';

import '../support/search_engine_test_init.dart';

Bookmark _entry(String q) => Bookmark(
  ref: q,
  book: TextBook(title: q),
  index: 0,
  isSearch: true,
);

Future<void> _pump(
  WidgetTester tester,
  List<Bookmark> entries, {
  ValueChanged<Bookmark>? onSelect,
  ValueChanged<Bookmark>? onRemove,
  Size size = const Size(800, 600),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 360,
            child: SearchHistoryMenu(
              entries: entries,
              onSelect: onSelect ?? (_) {},
              onRemove: onRemove ?? (_) {},
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> main() async {
  // כותרת עם אפשרויות מפצלת מילים דרך המנוע; מדולג כשאין build.
  final engineReady = await tryInitSearchEngine();

  testWidgets('כל חיפוש הוא שורה, ובחירה ומחיקה מועברות החוצה', (tester) async {
    final selected = <String>[];
    final removed = <String>[];
    final entries = [_entry('משה'), _entry('אברהם')];
    await _pump(
      tester,
      entries,
      onSelect: (b) => selected.add(b.ref),
      onRemove: (b) => removed.add(b.ref),
    );
    expect(find.byKey(searchHistoryMenuKey), findsOneWidget);
    expect(find.text('היסטוריית חיפושים'), findsOneWidget);
    expect(find.text('משה'), findsOneWidget);
    expect(find.text('אברהם'), findsOneWidget);

    await tester.tap(find.text('אברהם'));
    expect(selected, ['אברהם']);

    await tester.tap(find.byTooltip('מחק מההיסטוריה').first);
    expect(removed, ['משה']);
    expect(selected, ['אברהם'], reason: 'מחיקה אינה בוחרת');
  });

  testWidgets('מחיקה היא AppIconButton עם tooltip', (tester) async {
    await _pump(tester, [_entry('משה')]);
    expect(
      find.ancestor(
        of: find.byTooltip('מחק מההיסטוריה'),
        matching: find.byType(AppIconButton),
      ),
      findsOneWidget,
    );
  });

  testWidgets('בלי היסטוריה מוצג מצב ריק במקום תפריט ריק', (tester) async {
    await _pump(tester, const []);
    expect(find.text('אין עדיין חיפושים בהיסטוריה'), findsOneWidget);
    expect(find.byTooltip('מחק מההיסטוריה'), findsNothing);
  });

  testWidgets('חיפוש ארוך נחתך בשורה אחת ואינו מגדיל את השורה', (tester) async {
    final long = 'מילה ארוכה ' * 20;
    await _pump(tester, [_entry('קצר'), _entry(long)]);
    final shortRow = tester.getSize(find.text('קצר'));
    final longText = tester.widget<Text>(find.text(long));
    expect(longText.maxLines, 1);
    expect(longText.overflow, TextOverflow.ellipsis);
    expect(tester.getSize(find.text(long)).height, shortRow.height);
    expect(tester.takeException(), isNull);
  });

  testWidgets('50 חיפושים גוללים בתוך התפריט ואינם חורגים מחצי החלון', (
    tester,
  ) async {
    await _pump(tester, [for (var i = 0; i < 50; i++) _entry('חיפוש $i')]);
    final menu = tester.getSize(find.byKey(searchHistoryMenuKey));
    expect(menu.height, lessThanOrEqualTo(600 / 2 + 60));
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'אפשרויות המילה מובחנות מהמילים, כמו בחלון ההיסטוריה (issue #5537)',
    (tester) async {
      await _pump(tester, [
        Bookmark(
          ref: '(קד)שלום + עולם',
          book: TextBook(title: 'שלום עולם'),
          index: 0,
          isSearch: true,
          searchOptions: {
            'שלום_0': {'קידומות דקדוקיות': true},
          },
        ),
      ]);

      final title = tester.widget<Text>(find.text('(קד)שלום + עולם'));
      final spans = <String, TextStyle?>{};
      title.textSpan?.visitChildren((span) {
        if (span is TextSpan && span.text != null) {
          spans[span.text!] = span.style;
        }
        return true;
      });
      final theme = Theme.of(tester.element(find.byKey(searchHistoryMenuKey)));
      expect(spans.keys, ['(קד)', 'שלום', ' + ', 'עולם']);
      expect(spans['(קד)']?.fontSize, theme.textTheme.bodySmall?.fontSize);
      expect(spans['(קד)']?.color, theme.colorScheme.primary);
      expect(spans['שלום'], isNull, reason: 'המילה בסגנון השורה הרגיל');
      expect(find.byTooltip('(קד)שלום + עולם'), findsOneWidget);
    },
    skip: !engineReady,
  );

  testWidgets('רשומה ותיקה מציגה את הנוסח השמור כשהפיצול הנוכחי שונה', (
    tester,
  ) async {
    const storedRef = 'רמב"ם תורה';
    await _pump(tester, [
      Bookmark(
        ref: storedRef,
        book: TextBook(title: storedRef),
        index: 0,
        isSearch: true,
        searchOptions: {
          'רמב_0': {'קידומות דקדוקיות': true},
          'תורה_2': {'סיומות': true},
        },
      ),
    ]);

    expect(find.text(storedRef), findsOneWidget);
    expect(find.byTooltip(storedRef), findsOneWidget);
  }, skip: !engineReady);
}
