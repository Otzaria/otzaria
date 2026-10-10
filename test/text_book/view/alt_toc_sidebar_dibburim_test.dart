import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/alt_toc_sidebar_view.dart';
import 'package:otzaria/text_book/utils/dibburim_structure.dart';
import 'package:otzaria/widgets/lists/nav_tree_tile.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

/// דיבורי-המתחיל בלשונית 'כותרות': מבנה מסונתז "דיבורי המתחיל" שבו הדיבורים
/// הם עלים תחת כותרות ה-TOC, בלי מסד (המבנים האמיתיים חוזרים ריקים).
class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

TextBookLoaded _loadedState({
  required List<TocEntry> toc,
  required List<int> visibleIndices,
}) {
  return TextBookLoaded(
    book: TextBook(title: 'ספר בדיקה'),
    showLeftPane: true,
    content: List.generate(30, (i) => 'שורה $i'),
    fontSize: 18,
    showSplitView: false,
    activeCommentators: const [],
    commentatorGroups: const [],
    availableCommentators: const [],
    links: const [],
    visibleLinks: const [],
    linksByLine: const {},
    tableOfContents: toc,
    removeNikud: false,
    visibleIndices: visibleIndices,
    selectedIndex: null,
    pinLeftPane: false,
    searchText: '',
    scrollController: ItemScrollController(),
    positionsListener: ItemPositionsListener.create(),
  );
}

Future<void> _pumpSidebar(
  WidgetTester tester, {
  required List<TocEntry> toc,
  required Map<int, String> dibburim,
  required List<int> visibleIndices,
}) async {
  final bloc = _TestTextBookBloc(
    _loadedState(toc: toc, visibleIndices: visibleIndices),
  );
  addTearDown(bloc.close);

  await tester.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: BlocProvider<TextBookBloc>.value(
            value: bloc,
            child: SizedBox(
              width: 400,
              height: 800,
              child: AltTocSidebarView(
                book: TextBook(title: 'ספר בדיקה'),
                closeLeftPaneCallback: () {},
                scrollController: ItemScrollController(),
                dibburim: dibburim,
                tableOfContents: toc,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

NavTreeTile _tile(WidgetTester tester, String title) =>
    tester.widget<NavTreeTile>(
      find.byWidgetPredicate((w) => w is NavTreeTile && w.title == title),
    );

/// לוחץ על חץ ההרחבה של השורה [title].
Future<void> _expand(WidgetTester tester, String title) async {
  await tester.tap(
    find.descendant(
      of: find.byWidgetPredicate((w) => w is NavTreeTile && w.title == title),
      matching: find.byType(IconButton),
    ),
  );
  await tester.pumpAndSettle();
}

List<TocEntry> _toc() => [
  TocEntry(text: 'דף ב.', index: 1, level: 1),
  TocEntry(text: 'דף ב:', index: 6, level: 1),
  TocEntry(text: 'דף ג.', index: 12, level: 1),
];

void main() {
  testWidgets('שורשי דיבורים מהמסד נשארים מכווצים עד לחיצה', (tester) async {
    final fixture =
        jsonDecode(
              File(
                'test/fixtures/toc/maadanei_yom_tov_berakhot_dibburim.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final toc = (fixture['toc'] as List)
        .map(
          (row) => TocEntry(
            text: row[4] as String,
            index: row[3] as int,
            level: row[2] as int,
          ),
        )
        .toList();
    final dibburim = {
      for (final row in fixture['dh'] as List) row[0] as int: row[1] as String,
    };
    final entries = buildDibburimEntries(toc, dibburim);
    expect(entries, hasLength(983));
    expect(
      entries.every((entry) => entry.parentId == null && !entry.hasChildren),
      isTrue,
    );

    await _pumpSidebar(
      tester,
      toc: toc,
      dibburim: dibburim,
      visibleIndices: [dibburim.keys.first],
    );

    expect(_tile(tester, 'דיבורי המתחיל').isExpanded, isFalse);
    expect(find.byType(NavTreeTile), findsOneWidget);

    await _expand(tester, 'דיבורי המתחיל');

    expect(find.byType(NavTreeTile), findsNWidgets(984));
    expect(
      tester
          .widgetList<NavTreeTile>(find.byType(NavTreeTile))
          .where((tile) => tile.isSelected)
          .single
          .title,
      entries.first.text,
    );
  });

  testWidgets('שורשי כותרות לצד דיבור ישיר אינם חושפים דיבורים אוטומטית', (
    tester,
  ) async {
    final bookHeading = TocEntry(text: 'שם הספר', index: 0, level: 0);
    bookHeading.children.add(
      TocEntry(text: 'פרק ראשון', index: 5, level: 1, parent: bookHeading),
    );
    await _pumpSidebar(
      tester,
      toc: [bookHeading],
      dibburim: {2: 'דיבור לפני הפרק', 6: 'דיבור בפרק'},
      visibleIndices: const [6],
    );

    expect(_tile(tester, 'דיבורי המתחיל').isExpanded, isFalse);
    expect(find.byType(NavTreeTile), findsOneWidget);

    await _expand(tester, 'דיבורי המתחיל');

    expect(find.text('דיבור לפני הפרק'), findsOneWidget);
    expect(find.text('פרק ראשון'), findsOneWidget);
    expect(find.text('דיבור בפרק'), findsNothing);
    expect(_tile(tester, 'פרק ראשון').isSelected, isTrue);
    await _expand(tester, 'פרק ראשון');
    expect(_tile(tester, 'דיבור בפרק').isSelected, isTrue);
  });

  testWidgets('מבנה "דיבורי המתחיל" נפתח לבדו ומציג את הדיבורים תחת הדפים', (
    tester,
  ) async {
    await _pumpSidebar(
      tester,
      toc: _toc(),
      dibburim: {2: 'אמר רבא', 3: 'ואם יש לו צורת פתח אפילו רחב', 8: 'תנן'},
      visibleIndices: const [0],
    );

    expect(find.text('דיבורי המתחיל'), findsOneWidget);
    // מבנה יחיד נפתח מעצמו, והדפים שבו גלויים ומכווצים.
    expect(find.text('דף ב.'), findsOneWidget);
    expect(find.text('דף ב:'), findsOneWidget);
    // "דף ג." אין תחתיו דיבור ולכן אינו במבנה.
    expect(find.text('דף ג.'), findsNothing);
    expect(find.text('אמר רבא'), findsNothing);

    await _expand(tester, 'דף ב.');

    expect(find.text('אמר רבא'), findsOneWidget);
    // דיבור ארוך מקוצר.
    expect(find.text('ואם יש לו צורת…'), findsOneWidget);
    expect(find.textContaining('רחב'), findsNothing);
  });

  testWidgets('בלי דיבורים — הלשונית ריקה כמו קודם', (tester) async {
    await _pumpSidebar(
      tester,
      toc: _toc(),
      dibburim: const {},
      visibleIndices: const [0],
    );

    expect(find.text('אין כותרות חלופיות זמינות'), findsOneWidget);
    expect(find.text('דיבורי המתחיל'), findsNothing);
  });

  testWidgets('המיקום הנוכחי מסומן רק ברמה הגלויה, בלי לפתוח דיבורים מעצמו', (
    tester,
  ) async {
    await _pumpSidebar(
      tester,
      toc: _toc(),
      dibburim: {2: 'אמר רבא', 8: 'תנן', 9: 'אמר ליה'},
      visibleIndices: const [10],
    );

    // הדף של המיקום מסומן; הדיבור שבו קוראים עדיין מוסתר.
    expect(_tile(tester, 'דף ב:').isSelected, isTrue);
    expect(find.text('אמר ליה'), findsNothing);

    await _expand(tester, 'דף ב:');
    expect(_tile(tester, 'אמר ליה').isSelected, isTrue);
    expect(_tile(tester, 'תנן').isSelected, isFalse);
    expect(_tile(tester, 'דף ב:').isSelected, isFalse);
    expect(find.text('אמר רבא'), findsNothing);
  });
}
