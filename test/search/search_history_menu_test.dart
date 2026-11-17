import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/view/search_history_menu.dart';
import 'package:otzaria/widgets/controls/app_icon_button.dart';

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

void main() {
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
}
