import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/widgets/commentary/links_list_view.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';
import 'package:otzaria/text_display/models/text_display_profile.dart';
import 'package:otzaria/widgets/feedback/scrollable_positioned_list_scrollbar.dart';
import 'package:otzaria/widgets/lists/filter_chips_widget.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../helpers/memory_settings_cache.dart';

/// [LinksListView] חולץ מ-`SelectedLineLinksView` כדי שכרטיסיית הטקסט וחלונית
/// ה-PDF יציגו את אותה רשימת קישורים. הטסטים כאן נועלים את התכונה שמאפשרת
/// זאת: הווידג'ט חייב להישאר חסר-תלות ב-`TextBookBloc`.
class _FakeSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _FakeSettingsBloc() : super(SettingsState.initial()) {
    on<SettingsEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// קישור נפתח מורחב ותוכנו נטען מיד; בלי תוכן מוכן הטעינה הייתה ממתינה
/// לספרייה שאינה קיימת בבדיקה.
Link _link({
  required String path2,
  required String connectionType,
  int index1 = 5,
  int index2 = 1,
}) => _LongContentLink(
  heRef: 'הפניה $path2',
  index1: index1,
  path2: path2,
  index2: index2,
  connectionType: connectionType,
  content: 'תוכן $path2',
);

class _LongContentLink extends Link {
  _LongContentLink({
    required super.heRef,
    required super.index1,
    required super.path2,
    required super.index2,
    required super.connectionType,
    required this._content,
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
        value: _FakeSettingsBloc(),
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
            value: _FakeSettingsBloc(),
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
            value: _FakeSettingsBloc(),
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
            value: _FakeSettingsBloc(),
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
        value: _FakeSettingsBloc(),
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
            value: _FakeSettingsBloc(),
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

    final bar = tester.widget<ScrollablePositionedListScrollbar>(
      find.byType(ScrollablePositionedListScrollbar),
    );
    final list = tester.widget<ScrollablePositionedList>(
      find.byType(ScrollablePositionedList),
    );
    expect(bar.offsetController, isNotNull);
    expect(bar.offsetController, same(list.scrollOffsetController));
  });

  testWidgets('קישור נפתח מורחב כברירת מחדל ותוכנו נטען בלי הקשה', (
    tester,
  ) async {
    final link = _LongContentLink(
      heRef: 'שבת, כ., א',
      index1: 1,
      path2: 'שבת',
      index2: 1,
      connectionType: LinkTypes.quotation,
      content: 'תוכן המקור המצוטט',
    );
    CommentaryService.seedEraCache({'שבת': CommentaryEra.other});
    addTearDown(CommentaryService.clearEraCache);

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<SettingsBloc>.value(
          value: _FakeSettingsBloc(),
          child: Scaffold(
            body: LinksListView(
              displayProfile: TextDisplayProfile.defaults,
              links: [link],
              chipSourceLinks: [link],
              openBookTitle: 'ברכות',
              selectedLinkTypes: const {},
              onSelectedLinkTypesChanged: (_) {},
              openBookCallback: (_) {},
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tile = tester.widget<ExpansionTile>(find.byType(ExpansionTile));
    expect(tile.initiallyExpanded, isTrue, reason: 'issue #1924');
    final rendered = tester.widget<SmartTextWidget>(
      find.byType(SmartTextWidget),
    );
    expect(rendered.text, contains('תוכן המקור המצוטט'));
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
            value: _FakeSettingsBloc(),
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

    final scrollbar = find.byType(ScrollablePositionedListScrollbar);
    final scrollbarRect = tester.getRect(scrollbar);
    final listFinder = find.byType(ScrollablePositionedList);
    final list = tester.widget<ScrollablePositionedList>(listFinder);
    expect(
      tester.getRect(listFinder).right,
      lessThan(scrollbarRect.right),
      reason: 'קישור מורחב וגבוה מציג מסילה',
    );
    expect(
      list.itemPositionsNotifier!.itemPositions.value.single.itemLeadingEdge,
      closeTo(0, 0.01),
    );

    await tester.dragFrom(
      Offset(scrollbarRect.right - 6, scrollbarRect.top + 20),
      Offset(0, scrollbarRect.height - 40),
    );
    await tester.pumpAndSettle();

    expect(
      list.itemPositionsNotifier!.itemPositions.value.single.itemLeadingEdge,
      lessThan(-0.1),
      reason: 'ה־offsetController מאפשר למסילה לגלול בתוך אותו קישור',
    );
  });

  group('מבנה — שני הצדדים צורכים את אותה רשימה', () {
    String read(String path) => File(path).readAsStringSync();

    test('כרטיסיית הטקסט וחלונית ה-PDF מייבאות את LinksListView', () {
      const importRef = 'widgets/commentary/links_list_view.dart';
      expect(
        read('lib/text_book/view/selected_line_links_view.dart'),
        contains(importRef),
      );
      expect(
        read('lib/pdf_book/view/pdf_commentary_panel.dart'),
        contains(importRef),
      );
    });

    test('הווידג\'ט המשותף אינו תלוי ב-TextBookBloc', () {
      final source = read('lib/widgets/commentary/links_list_view.dart');
      // ההערה התיעודית מזכירה את השם; מה שאסור הוא ייבוא או שימוש בקוד.
      expect(source, isNot(contains('text_book_bloc.dart')));
      expect(source, isNot(contains('text_book_state.dart')));
      expect(source, isNot(contains('text_book_event.dart')));
      expect(source, isNot(contains('read<TextBookBloc')));
      expect(source, isNot(contains('TextBookStateBuilder')));
      expect(source, isNot(contains('TextBookLoaded')));
    });

    test('חלונית ה-PDF אינה מחזיקה עוד tile קישורים משלה', () {
      expect(
        read('lib/pdf_book/view/pdf_commentary_panel.dart'),
        isNot(contains('_buildLinkTile')),
      );
    });

    test('המתאם ממשיך לייצא את העזרים הטהורים לצרכני הטקסט', () {
      expect(
        read('lib/text_book/view/selected_line_links_view.dart'),
        contains(
          "export 'package:otzaria/widgets/commentary/"
          "links_list_view.dart';",
        ),
      );
    });
  });
}
