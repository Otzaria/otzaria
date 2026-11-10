import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/widgets/commentary/links_list_view.dart';
import 'package:otzaria/widgets/commentary/panel_anchor_links.dart';
import 'package:otzaria/text_display/models/text_display_profile.dart';
import 'package:otzaria/widgets/feedback/scrollable_positioned_list_scrollbar.dart';
import 'package:otzaria/widgets/lists/filter_chips_widget.dart';
import 'package:positioned_sliver_list/positioned_list.dart';

import '../../helpers/memory_settings_cache.dart';
import '../../test_helpers/stub_settings_bloc.dart';

/// [LinksListView] חולץ מ-`SelectedLineLinksView` כדי שכרטיסיית הטקסט וחלונית
/// ה-PDF יציגו את אותה רשימת קישורים. הטסטים כאן נועלים את התכונה שמאפשרת
/// זאת: הווידג'ט חייב להישאר חסר-תלות ב-`TextBookBloc`.

Link _link({
  required String path2,
  required String connectionType,
  int index1 = 5,
  int index2 = 1,
}) => Link(
  heRef: 'הפניה $path2',
  index1: index1,
  path2: path2,
  index2: index2,
  connectionType: connectionType,
);

class _LongContentLink extends Link {
  _LongContentLink({
    required super.heRef,
    required super.index1,
    required super.path2,
    required super.index2,
    required super.connectionType,
    required this._content,
    super.targetSource,
    super.targetBookId,
    super.targetCategoryId,
  });

  final String _content;

  @override
  Future<String> get content => Future.value(_content);

  @override
  Future<String> get displayReference => Future.value(fallbackDisplayReference);
}

/// בונה את הרשימה המשותפת **בלי** `BlocProvider<TextBookBloc>` — כך שכל
/// קריאה ל-`read<TextBookBloc>()` בתוכה תיכשל ותיתפס כאן.
Future<Set<String>?> _pumpWithoutTextBookBloc(
  WidgetTester tester, {
  required List<Link> links,
  Set<String> selectedTypes = const {},
}) async {
  Set<String>? lastEmitted;
  await tester.pumpWidget(
    MaterialApp(
      home: BlocProvider<SettingsBloc>.value(
        value: StubSettingsBloc(),
        child: Scaffold(
          body: LinksListView(
            displayProfile: TextDisplayProfile.defaults,
            links: links,
            chipSourceLinks: links,
            openBookTitle: 'שבת',
            selectedLinkTypes: selectedTypes,
            onSelectedLinkTypesChanged: (types) => lastEmitted = types,
            openBookCallback: (_) {},
            fontSize: 16,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return lastEmitted;
}

void main() {
  setUpAll(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  group('LinksListView — חסר תלות ב-TextBookBloc', () {
    testWidgets('נבנה ללא BlocProvider<TextBookBloc> ולא זורק', (tester) async {
      await _pumpWithoutTextBookBloc(
        tester,
        links: [
          _link(path2: 'מסורת הש"ס', connectionType: LinkTypes.mesoratHashas),
        ],
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(LinksListView), findsOneWidget);
    });

    testWidgets('מציג שדה חיפוש', (tester) async {
      await _pumpWithoutTextBookBloc(
        tester,
        links: [_link(path2: 'עין משפט', connectionType: LinkTypes.einMishpat)],
      );
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('רשימה ריקה מציגה את הודעת ברירת המחדל', (tester) async {
      await _pumpWithoutTextBookBloc(tester, links: const []);
      expect(find.text('לא נמצאו קישורים לקטע הנבחר'), findsOneWidget);
    });

    testWidgets('emptyMessage מותאם נכבד', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<SettingsBloc>.value(
            value: StubSettingsBloc(),
            child: Scaffold(
              body: LinksListView(
                displayProfile: TextDisplayProfile.defaults,
                links: const [],
                chipSourceLinks: const [],
                openBookTitle: 'מכות',
                selectedLinkTypes: const {},
                onSelectedLinkTypesChanged: (_) {},
                openBookCallback: (_) {},
                fontSize: 16,
                emptyMessage: 'לא נמצאו קישורים לדף זה',
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('לא נמצאו קישורים לדף זה'), findsOneWidget);
    });

    testWidgets('שני סוגי קישורים שונים מציגים שורת צ׳יפים', (tester) async {
      await _pumpWithoutTextBookBloc(
        tester,
        links: [
          _link(path2: 'מסורת הש"ס', connectionType: LinkTypes.mesoratHashas),
          _link(path2: 'עין משפט', connectionType: LinkTypes.einMishpat),
        ],
      );
      expect(find.byType(FilterChipsSelector<String>), findsWidgets);
    });

    testWidgets('סוג יחיד אינו מציג צ׳יפים', (tester) async {
      await _pumpWithoutTextBookBloc(
        tester,
        links: [
          _link(path2: 'מסורת הש"ס', connectionType: LinkTypes.mesoratHashas),
        ],
      );
      expect(find.byType(FilterChipsSelector<String>), findsNothing);
    });
  });

  group('LinksListView — סינון הסוגים יוצא בקולבק ולא ב-BLoC', () {
    testWidgets('בחירת צ׳יפ מדווחת דרך onSelectedLinkTypesChanged', (
      tester,
    ) async {
      Set<String>? emitted;
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<SettingsBloc>.value(
            value: StubSettingsBloc(),
            child: Scaffold(
              body: LinksListView(
                displayProfile: TextDisplayProfile.defaults,
                links: [
                  _link(
                    path2: 'מסורת הש"ס',
                    connectionType: LinkTypes.mesoratHashas,
                  ),
                  _link(
                    path2: 'עין משפט',
                    connectionType: LinkTypes.einMishpat,
                  ),
                ],
                chipSourceLinks: [
                  _link(
                    path2: 'מסורת הש"ס',
                    connectionType: LinkTypes.mesoratHashas,
                  ),
                  _link(
                    path2: 'עין משפט',
                    connectionType: LinkTypes.einMishpat,
                  ),
                ],
                openBookTitle: 'שבת',
                selectedLinkTypes: const {},
                onSelectedLinkTypesChanged: (types) => emitted = types,
                openBookCallback: (_) {},
                fontSize: 16,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final chip = find.byType(Chip).first;
      expect(chip, findsOneWidget);
      await tester.tap(chip, warnIfMissed: false);
      await tester.pump();

      expect(
        emitted,
        isNotNull,
        reason: 'הבחירה חייבת לצאת בקולבק — בלעדיו ה-PDF לא יכול לסנן',
      );
    });

    testWidgets('סינון לסוג שאין לו קישור מציג הודעת "מהסוגים שנבחרו"', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<SettingsBloc>.value(
            value: StubSettingsBloc(),
            child: Scaffold(
              body: LinksListView(
                displayProfile: TextDisplayProfile.defaults,
                links: [
                  _link(
                    path2: 'מסורת הש"ס',
                    connectionType: LinkTypes.mesoratHashas,
                  ),
                ],
                chipSourceLinks: [
                  _link(
                    path2: 'מסורת הש"ס',
                    connectionType: LinkTypes.mesoratHashas,
                  ),
                  _link(
                    path2: 'עין משפט',
                    connectionType: LinkTypes.einMishpat,
                  ),
                ],
                openBookTitle: 'שבת',
                selectedLinkTypes: const {LinkTypes.einMishpat},
                onSelectedLinkTypesChanged: (_) {},
                openBookCallback: (_) {},
                fontSize: 16,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('לא נמצאו קישורים מהסוגים שנבחרו'), findsOneWidget);
    });
  });

  testWidgets('שני מסדי יעד שומרים תוכן והרחבה נפרדים באותה כותרת', (
    tester,
  ) async {
    final links = [
      for (final slug in ['library-a', 'library-b'])
        _LongContentLink(
          heRef: 'אותה הפניה',
          index1: 1,
          path2: 'ספר משותף',
          index2: 1,
          connectionType: LinkTypes.mesoratHashas,
          targetSource: BookSource.attached(slug),
          targetBookId: 2,
          targetCategoryId: 2,
          content: 'תוכן של $slug',
        ),
    ];
    CommentaryService.seedEraCache({
      for (final link in links)
        '${link.targetSource.wireKey}\u0000ספר משותף': CommentaryEra.other,
    });
    addTearDown(CommentaryService.clearEraCache);
    await _pumpWithoutTextBookBloc(tester, links: links);
    await tester.pumpAndSettle();

    List<String> contents() => tester
        .widgetList<PanelAnchoredText>(find.byType(PanelAnchoredText))
        .map((widget) => widget.html)
        .toList();
    final tiles = find.byType(ExpansionTile);
    Finder header(int index) => find.descendant(
      of: tiles.at(index),
      matching: find.text('ספר משותף'),
    );
    expect(tiles, findsNWidgets(2));
    await tester.tap(header(0));
    await tester.pumpAndSettle();
    expect(contents(), ['תוכן של library-a']);

    await tester.tap(header(1));
    await tester.pumpAndSettle();
    expect(contents(), ['תוכן של library-a', 'תוכן של library-b']);

    await tester.tap(header(0));
    await tester.pumpAndSettle();
    expect(contents(), ['תוכן של library-b']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('שינוי contentScopeKey מאפס גלילה בלי לפרק את ה-State', (
    tester,
  ) async {
    final links = List.generate(
      30,
      (index) =>
          _link(path2: 'ספר-$index', connectionType: LinkTypes.mesoratHashas),
    );
    CommentaryService.seedEraCache({
      for (var index = 0; index < 30; index++)
        'ספר-$index': CommentaryEra.other,
    });

    Widget view(String scopeKey) => MaterialApp(
      home: BlocProvider<SettingsBloc>.value(
        value: StubSettingsBloc(),
        child: Scaffold(
          body: LinksListView(
            displayProfile: TextDisplayProfile.defaults,
            links: links,
            chipSourceLinks: links,
            openBookTitle: 'שבת',
            selectedLinkTypes: const {},
            onSelectedLinkTypesChanged: (_) {},
            openBookCallback: (_) {},
            fontSize: 16,
            contentScopeKey: scopeKey,
          ),
        ),
      ),
    );

    final list = find.byType(ScrollablePositionedList);
    await tester.pumpWidget(view('עמוד-א'));
    for (var i = 0; i < 20 && list.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(list, findsOneWidget);
    final stateBefore = tester.state(find.byType(LinksListView));

    await tester.drag(list, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(
      find.text('ספר-0'),
      findsNothing,
      reason: 'גללנו למטה — ראש הרשימה יצא מהמסך',
    );

    await tester.pumpWidget(view('עמוד-ב'));
    await tester.pumpAndSettle();

    expect(tester.state(find.byType(LinksListView)), same(stateBefore));
    expect(
      find.text('ספר-0'),
      findsOneWidget,
      reason: 'החלפת הקטע חייבת להחזיר את הרשימה לראשה',
    );
  });

  testWidgets('המסילה בקצה ימין של הרשימה, לא בשמאל', (tester) async {
    final links = List.generate(
      30,
      (index) =>
          _link(path2: 'ספר-$index', connectionType: LinkTypes.mesoratHashas),
    );
    CommentaryService.seedEraCache({
      for (var index = 0; index < 30; index++)
        'ספר-$index': CommentaryEra.other,
    });
    addTearDown(CommentaryService.clearEraCache);

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          // האפליקציה כולה RTL (locale he_IL); בלי זה הצד נמדד הפוך.
          textDirection: TextDirection.rtl,
          child: BlocProvider<SettingsBloc>.value(
            value: StubSettingsBloc(),
            child: Scaffold(
              body: LinksListView(
                displayProfile: TextDisplayProfile.defaults,
                links: links,
                chipSourceLinks: links,
                openBookTitle: 'שבת',
                selectedLinkTypes: const {},
                onSelectedLinkTypesChanged: (_) {},
                openBookCallback: (_) {},
                fontSize: 16,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final barRect = tester.getRect(
      find.byType(ScrollablePositionedListScrollbar),
    );
    final listRect = tester.getRect(find.byType(ScrollablePositionedList));

    expect(
      listRect.right,
      lessThan(barRect.right),
      reason: 'המסילה חייבת לתפוס את הקצה הימני והרשימה להצטמצם לפניה',
    );
    expect(
      listRect.left,
      barRect.left,
      reason: 'אין מסילה בקצה השמאלי — הרשימה מגיעה עד לשם',
    );
  });

  testWidgets('גרירת המסילה גוללת בתוך קישור יחיד ומורחב', (tester) async {
    final longContent = List.filled(200, 'תוכן ארוך לבדיקה').join('\n');
    final link = _LongContentLink(
      heRef: 'קישור ארוך, א',
      index1: 1,
      path2: 'קישור ארוך',
      index2: 1,
      connectionType: LinkTypes.mesoratHashas,
      content: longContent,
    );
    CommentaryService.seedEraCache({'קישור ארוך': CommentaryEra.other});
    addTearDown(CommentaryService.clearEraCache);

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: BlocProvider<SettingsBloc>.value(
            value: StubSettingsBloc(),
            child: Scaffold(
              body: LinksListView(
                displayProfile: TextDisplayProfile.defaults,
                links: [link],
                chipSourceLinks: [link],
                openBookTitle: 'שבת',
                selectedLinkTypes: const {},
                onSelectedLinkTypesChanged: (_) {},
                openBookCallback: (_) {},
                fontSize: 16,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();

    final scrollbar = find.byType(ScrollablePositionedListScrollbar);
    final scrollbarRect = tester.getRect(scrollbar);
    final listFinder = find.byType(ScrollablePositionedList);
    final list = tester.widget<ScrollablePositionedList>(listFinder);
    final position = list.itemScrollController!.scrollController!.position;
    expect(
      tester.getRect(listFinder).right,
      lessThan(scrollbarRect.right),
      reason: 'קישור מורחב וגבוה מציג מסילה',
    );
    expect(
      position.pixels,
      closeTo(0, 0.01),
    );

    await tester.dragFrom(
      Offset(scrollbarRect.right - 6, scrollbarRect.top + 20),
      Offset(0, scrollbarRect.height - 40),
    );
    await tester.pumpAndSettle();

    expect(
      position.pixels,
      greaterThan(position.viewportDimension * 0.1),
      reason: 'המסילה גוללת בתוך אותו קישור',
    );
  });

  testWidgets(
    'בנייה חוזרת עם אותה רשימה אינה גוזרת מחדש את מפתחות כל הקישורים (perf)',
    (tester) async {
      const count = 300;
      final links = [
        for (var i = 1; i <= count; i++)
          _CountingLink(
            heRef: 'הפניה $i',
            index1: 5,
            path2: 'ספר $i',
            index2: i,
            connectionType: LinkTypes.quotation,
          ),
      ];
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<SettingsBloc>.value(
            value: StubSettingsBloc(),
            child: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  rebuild = setState;
                  return LinksListView(
                    displayProfile: TextDisplayProfile.defaults,
                    links: links,
                    chipSourceLinks: links,
                    openBookTitle: 'שבת',
                    selectedLinkTypes: const {},
                    onSelectedLinkTypesChanged: (_) {},
                    openBookCallback: (_) {},
                    fontSize: 16,
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      _CountingLink.index2EndReads = 0;
      rebuild(() {});
      await tester.pump();

      // רק הפריטים הבנויים גוזרים את מפתחם, ולא כל קישורי הקטע.
      expect(_CountingLink.index2EndReads, lessThan(count));
    },
  );
}

/// סופר קריאות של [index2End], שמפתחות הקישור נגזרים ממנו.
class _CountingLink extends Link {
  _CountingLink({
    required super.heRef,
    required super.index1,
    required super.path2,
    required super.index2,
    required super.connectionType,
  });

  static int index2EndReads = 0;

  @override
  int? get index2End {
    index2EndReads++;
    return super.index2End;
  }
}
