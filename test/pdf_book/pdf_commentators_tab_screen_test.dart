import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_common/view/commentary_search_pane.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/models/pdf_headings.dart';
import 'package:otzaria/pdf_book/view/pdf_commentary_panel.dart';
import 'package:otzaria/pdf_book/view/pdf_commentators_tab_screen.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/tabs/models/pdf_commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/widgets/lists/nav_tree_tile.dart';
import 'package:otzaria/widgets/feedback/scrollable_positioned_list_scrollbar.dart';
import 'package:otzaria/widgets/navigation/nav_side_panel.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../helpers/memory_settings_cache.dart';

class _FakeSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _FakeSettingsBloc([SettingsState? initial])
    : super(initial ?? SettingsState.initial()) {
    on<SettingsEvent>((event, _) => events.add(event));
  }

  final events = <SettingsEvent>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePersonalNotesBloc
    extends Bloc<PersonalNotesEvent, PersonalNotesState>
    implements PersonalNotesBloc {
  _FakePersonalNotesBloc()
    : super(
        const PersonalNotesState(
          isLoading: false,
          bookId: '',
          locatedNotes: [],
          missingNotes: [],
          errorMessage: null,
          filteredLocatedNotes: [],
          filteredMissingNotes: [],
        ),
      ) {
    on<PersonalNotesEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _wrap(
  Widget child, {
  SettingsState? settings,
  _FakeSettingsBloc? settingsBloc,
}) => MaterialApp(
  home: MultiBlocProvider(
    providers: [
      BlocProvider<SettingsBloc>.value(
        value: settingsBloc ?? _FakeSettingsBloc(settings),
      ),
      BlocProvider<PersonalNotesBloc>.value(
        value: _FakePersonalNotesBloc(),
      ),
    ],
    child: Scaffold(body: child),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  testWidgets('זום בכרטיסיית מפרשי PDF שולח צעדים לשני הכיוונים', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final sourceTab = PdfBookTab(
      book: PdfBook(title: 'PDF בדיקה', path: '/tmp/book.pdf'),
      pageNumber: 1,
    );
    addTearDown(sourceTab.dispose);
    final settingsBloc = _FakeSettingsBloc();
    addTearDown(settingsBloc.close);
    final tab = PdfCommentatorsTab(sourceTab: sourceTab);

    await tester.pumpWidget(
      _wrap(PdfCommentatorsTabScreen(tab: tab), settingsBloc: settingsBloc),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('הגדל את גודל הטקסט').first);
    await tester.pump();
    await tester.tap(find.byTooltip('הקטן את גודל הטקסט').first);
    await tester.pump();

    expect(
      settingsBloc.events.whereType<AdjustCommentatorsFontSize>().map(
        (event) => event.delta,
      ),
      [2.0, -2.0],
    );
  });

  testWidgets('כרטסיית מפרשי PDF מסתנכרנת עם currentTitle של sourceTab', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final sourceTab = PdfBookTab(
      book: PdfBook(title: 'PDF בדיקה', path: '/tmp/book.pdf'),
      pageNumber: 1,
    );
    addTearDown(sourceTab.dispose);

    sourceTab.pdfHeadings = PdfHeadings(
      bookTitle: 'PDF בדיקה',
      headingsMap: {
        'פרק א': 1,
        'פרק ב': 10,
      },
    );
    sourceTab.currentTitle.value = 'פרק א';
    sourceTab.currentTextLineNumber = 1;
    sourceTab.currentTextLineNumberEnd = 9;

    final tab = PdfCommentatorsTab(sourceTab: sourceTab);

    await tester.pumpWidget(
      _wrap(PdfCommentatorsTabScreen(tab: tab)),
    );
    await tester.pump();

    // הסנכרון משתקף בטווח השורות שמועבר ל-PdfCommentaryPanel:
    // 'פרק א' מתחיל בשורה 1.
    PdfCommentaryPanel panel() =>
        tester.widget<PdfCommentaryPanel>(find.byType(PdfCommentaryPanel));
    expect(panel().lineStartOverride, 1);

    sourceTab.currentTitle.value = 'פרק ב';
    sourceTab.currentTextLineNumber = 10;
    sourceTab.currentTextLineNumberEnd = 19;
    await tester.pump();

    // הבחירה התעדכנה ל'פרק ב' (מתחיל בשורה 10)
    expect(panel().lineStartOverride, 10);
  });

  testWidgets(
    'תצוגת ספר: כותרת משולבת נפתחת על העמוד הראשון ומציגה גם את העמוד השני',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final sourceTab = PdfBookTab(
        book: PdfBook(title: 'PDF בדיקה', path: '/tmp/book.pdf'),
        pageNumber: 2,
      );
      addTearDown(sourceTab.dispose);

      sourceTab.pdfHeadings = PdfHeadings(
        bookTitle: 'PDF בדיקה',
        headingsMap: {
          'פרק א': 1,
          'פרק ב': 10,
          'פרק ג': 20,
        },
      );
      // כותרת ספירייד משולבת (כפי שנוצרת בתצוגת ספר)
      sourceTab.currentTitle.value = 'פרק ב — פרק ג';

      final tab = PdfCommentatorsTab(sourceTab: sourceTab);

      await tester.pumpWidget(
        _wrap(PdfCommentatorsTabScreen(tab: tab)),
      );
      await tester.pump();

      PdfCommentaryPanel panel() =>
          tester.widget<PdfCommentaryPanel>(find.byType(PdfCommentaryPanel));

      // לא נופל ל'פרק א' (שורה 1) — נבחר העמוד הראשון בספירייד, 'פרק ב' (שורה 10)
      expect(panel().lineStartOverride, 10);
      // העמוד השני בספירייד ('פרק ג', שורה 20) נכלל דרך extraLineIndices
      expect(panel().extraLineIndices, contains(20));
    },
  );

  testWidgets('כותרת חוקית עם מקף ארוך אינה מפוצלת בטעות לספירייד', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final sourceTab = PdfBookTab(
      book: PdfBook(title: 'PDF בדיקה', path: '/tmp/book.pdf'),
      pageNumber: 3,
    );
    addTearDown(sourceTab.dispose);

    sourceTab.pdfHeadings = PdfHeadings(
      bookTitle: 'PDF בדיקה',
      headingsMap: {
        'שער': 1,
        'שער — מבוא': 30,
        'פרק א': 40,
      },
    );
    // כותרת בודדת חוקית שמכילה מקף ארוך — אינה ספירייד
    sourceTab.currentTitle.value = 'שער — מבוא';

    final tab = PdfCommentatorsTab(sourceTab: sourceTab);

    await tester.pumpWidget(
      _wrap(PdfCommentatorsTabScreen(tab: tab)),
    );
    await tester.pump();

    PdfCommentaryPanel panel() =>
        tester.widget<PdfCommentaryPanel>(find.byType(PdfCommentaryPanel));

    // נבחרה הכותרת המלאה (שורה 30), לא 'שער' (שורה 1)
    expect(panel().lineStartOverride, 30);
    // אין הוספת עמוד שני — זו כותרת בודדת
    expect(panel().extraLineIndices, isNull);
  });

  testWidgets('ספירייד שכותרתו הראשונה מכילה מקף — מתפצל במקום הנכון', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final sourceTab = PdfBookTab(
      book: PdfBook(title: 'PDF בדיקה', path: '/tmp/book.pdf'),
      pageNumber: 2,
    );
    addTearDown(sourceTab.dispose);

    sourceTab.pdfHeadings = PdfHeadings(
      bookTitle: 'PDF בדיקה',
      headingsMap: {
        'שער — מבוא': 10,
        'פרק א': 20,
        'פרק ב': 30,
      },
    );
    // העמוד הראשון בספירייד הוא הכותרת 'שער — מבוא' (מכילה מקף בעצמה)
    sourceTab.currentTitle.value = 'שער — מבוא — פרק א';

    final tab = PdfCommentatorsTab(sourceTab: sourceTab);

    await tester.pumpWidget(
      _wrap(PdfCommentatorsTabScreen(tab: tab)),
    );
    await tester.pump();

    PdfCommentaryPanel panel() =>
        tester.widget<PdfCommentaryPanel>(find.byType(PdfCommentaryPanel));

    // העמוד הראשון נבחר נכון ('שער — מבוא', שורה 10) ולא פוצל ל'שער'
    expect(panel().lineStartOverride, 10);
    // העמוד השני ('פרק א', שורה 20) נכלל
    expect(panel().extraLineIndices, contains(20));
  });

  testWidgets(
    'כרטסיית מפרשי PDF מציגה "טוען מפרשים..." בזמן טעינת links של sourceTab',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final sourceTab = PdfBookTab(
        book: PdfBook(title: 'PDF בדיקה', path: '/tmp/book.pdf'),
        pageNumber: 1,
      );
      addTearDown(sourceTab.dispose);

      sourceTab.pdfHeadings = PdfHeadings(
        bookTitle: 'PDF בדיקה',
        headingsMap: {
          'פרק א': 1,
        },
      );
      sourceTab.currentTitle.value = 'פרק א';
      sourceTab.currentTextLineNumber = 1;
      sourceTab.currentTextLineNumberEnd = 9;
      sourceTab.linksLoadingNotifier.value = true;

      final tab = PdfCommentatorsTab(sourceTab: sourceTab);

      await tester.pumpWidget(
        _wrap(PdfCommentatorsTabScreen(tab: tab)),
      );
      await tester.pump();

      expect(find.text('טוען מפרשים...'), findsOneWidget);
      expect(find.text('לא נמצאו מפרשים לקטע הנבחר'), findsNothing);

      sourceTab.linksLoadingNotifier.value = false;
      await tester.pump();

      expect(find.text('לא נמצאו מפרשים לקטע הנבחר'), findsOneWidget);
    },
  );

  for (final isMac in [false, true]) {
    testWidgets(
      '${isMac ? 'Command' : 'Ctrl'}+F פותח את לשונית החיפוש וממקד את השדה',
      (tester) async {
        final previousMacOverride = ShortcutHelper.isMacForTesting;
        ShortcutHelper.isMacForTesting = isMac;
        addTearDown(() => ShortcutHelper.isMacForTesting = previousMacOverride);
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final sourceTab = PdfBookTab(
          book: PdfBook(title: 'PDF בדיקה', path: '/tmp/book.pdf'),
          pageNumber: 1,
        );
        addTearDown(sourceTab.dispose);
        final tab = PdfCommentatorsTab(sourceTab: sourceTab);
        await tester.pumpWidget(_wrap(PdfCommentatorsTabScreen(tab: tab)));
        await tester.pump();
        expect(find.byType(NavPanelTabHeader), findsNothing);

        final modifier = ShortcutHelper.usesMacModifiers
            ? LogicalKeyboardKey.metaLeft
            : LogicalKeyboardKey.controlLeft;
        await tester.sendKeyDownEvent(modifier);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
        await tester.sendKeyUpEvent(modifier);
        await tester.pumpAndSettle();

        expect(
          tester
              .widget<NavPanelTabHeader>(find.byType(NavPanelTabHeader))
              .controller
              .index,
          2,
        );
        expect(
          tester
              .widget<CommentarySearchPane>(find.byType(CommentarySearchPane))
              .focusNode
              .hasFocus,
          isTrue,
        );
      },
    );
  }

  testWidgets('חלונית הניווט בעיצוב האחיד: NavSidePanel, כותרת ועץ כרטיסים', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final sourceTab = PdfBookTab(
      book: PdfBook(title: 'PDF בדיקה', path: '/tmp/book.pdf'),
      pageNumber: 1,
    );
    addTearDown(sourceTab.dispose);
    sourceTab.pdfHeadings = PdfHeadings(
      bookTitle: 'PDF בדיקה',
      headingsMap: {'פרק א': 1, 'פרק ב': 10},
    );
    sourceTab.currentTitle.value = 'פרק א';

    final tab = PdfCommentatorsTab(sourceTab: sourceTab);
    await tester.pumpWidget(_wrap(PdfCommentatorsTabScreen(tab: tab)));
    await tester.pump();

    expect(find.byType(NavSidePanel), findsOneWidget);
    // פתיחת החלונית דרך הכפתור האחיד של כל המסכים.
    await tester.tap(find.byType(NavPanelToggleButton));
    await tester.pumpAndSettle();

    expect(find.byType(NavPanelTabHeader), findsOneWidget);
    expect(find.byType(NavPanelPinButton), findsOneWidget);
    // שורות העץ בעיצוב הספרייה: כרטיס מקובץ + שורת ניווט.
    expect(find.byType(NavTreeGroupCard), findsWidgets);
    expect(find.widgetWithText(NavTreeTile, 'פרק א'), findsOneWidget);
  });

  testWidgets('בחירת כותרת בעץ הניווט שומרת את החיפוש במפרשים', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final sourceTab = PdfBookTab(
      book: PdfBook(title: 'PDF בדיקה', path: '/tmp/book.pdf'),
      pageNumber: 1,
    );
    addTearDown(sourceTab.dispose);
    sourceTab.pdfHeadings = PdfHeadings(
      bookTitle: 'PDF בדיקה',
      headingsMap: {'פרק א': 1, 'פרק ב': 10},
    );
    sourceTab.currentTitle.value = 'פרק א';
    final tab = PdfCommentatorsTab(sourceTab: sourceTab);
    await tester.pumpWidget(_wrap(PdfCommentatorsTabScreen(tab: tab)));
    await tester.pump();

    await tester.tap(find.byTooltip('חיפוש').first);
    await tester.pumpAndSettle();
    final searchField = find.widgetWithText(TextField, 'חיפוש במפרשים...');
    await tester.enterText(searchField, 'אמר');
    await tester.pumpAndSettle();

    await tester.tap(find.text('ניווט'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(NavTreeTile, 'פרק ב'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widgetList<EditableText>(
            find.byType(EditableText, skipOffstage: false),
          )
          .map((field) => field.controller.text),
      contains('אמר'),
    );
  });

  // issue #1112 — פערים מול כרטיסיית המפרשים של ספר טקסט.
  group('התאמה לכרטיסיית המפרשים של טקסט (issue #1112)', () {
    PdfBookTab sourceTab() {
      final tab = PdfBookTab(
        book: PdfBook(title: 'PDF בדיקה', path: '/tmp/book.pdf'),
        pageNumber: 1,
      );
      tab.pdfHeadings = PdfHeadings(
        bookTitle: 'PDF בדיקה',
        headingsMap: {'פרק א': 1, 'פרק ב': 10},
      );
      tab.currentTitle.value = 'פרק א';
      return tab;
    }

    testWidgets('חלונית לא נעוצה: גלילה אינה סוגרת, לחיצה על התוכן סוגרת', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final source = sourceTab();
      addTearDown(source.dispose);

      await tester.pumpWidget(
        _wrap(
          PdfCommentatorsTabScreen(tab: PdfCommentatorsTab(sourceTab: source)),
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(NavPanelToggleButton));
      await tester.pumpAndSettle();
      NavSidePanel panel() =>
          tester.widget<NavSidePanel>(find.byType(NavSidePanel));
      expect(panel().isOpen, isTrue);

      // גלילת המשתמש ברשימת המפרשים, כפי שהיא עולה מהרשימה אל המסך.
      final context = tester.element(find.byType(PdfCommentaryPanel));
      UserScrollNotification(
        metrics: FixedScrollMetrics(
          minScrollExtent: 0,
          maxScrollExtent: 1000,
          pixels: 100,
          viewportDimension: 500,
          axisDirection: AxisDirection.down,
          devicePixelRatio: 1,
        ),
        context: context,
        direction: ScrollDirection.forward,
      ).dispatch(context);
      await tester.pumpAndSettle();

      expect(panel().isOpen, isTrue, reason: 'גלילה אינה סגירה מפורשת');

      // ההצללה מכסה את המפרשים; לחיצה עליה סוגרת את החלונית.
      await tester.tapAt(const Offset(100, 450));
      await tester.pumpAndSettle();

      expect(panel().isOpen, isFalse);
    });

    testWidgets('הגדרת רוחב הטקסט חלה על רשימת המפרשים', (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final source = sourceTab();
      source.links = [
        Link(
          heRef: 'מפרש בדיקה',
          index1: 1,
          path2: '/tmp/commentary.txt',
          index2: 0,
          connectionType: 'COMMENTARY',
        ),
      ];
      addTearDown(source.dispose);

      await tester.pumpWidget(
        _wrap(
          PdfCommentatorsTabScreen(tab: PdfCommentatorsTab(sourceTab: source)),
          settings: SettingsState.initial().copyWith(textMaxWidth: 600),
        ),
      );
      await tester.pumpAndSettle();

      final list = find.descendant(
        of: find.byType(PdfCommentaryPanel),
        matching: find.byType(ScrollablePositionedList),
      );
      expect(
        list,
        findsOneWidget,
      );
      expect(tester.getSize(list).width, lessThanOrEqualTo(600.0));

      final panelRect = tester.getRect(find.byType(PdfCommentaryPanel));
      final scrollbarRect = tester.getRect(
        find.byType(ScrollablePositionedListScrollbar),
      );
      expect(scrollbarRect.right, panelRect.right);
    });
  });
}
