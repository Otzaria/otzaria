import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/pdf_book/view/pdf_commentary_panel.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/pdf_commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as text_utils;
import 'package:otzaria/widgets/lists/commentators_selection_panel.dart';
import '../helpers/memory_settings_cache.dart';

// ─── fakes ───────────────────────────────────────────────────────────────────

class _FakeSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _FakeSettingsBloc() : super(SettingsState.initial()) {
    on<SettingsEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
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
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

// ─── helpers ─────────────────────────────────────────────────────────────────

PdfBook _book() => PdfBook(title: 'מכות', path: '/books/מכות.pdf');

PdfBookTab _tab({
  int? currentLine,
  int? currentLineEnd,
  List<Link> links = const [],
}) {
  final tab = PdfBookTab(book: _book(), pageNumber: 1);
  tab.currentTextLineNumber = currentLine;
  tab.currentTextLineNumberEnd = currentLineEnd;
  tab.links = List.of(links);
  return tab;
}

Link _commentaryLink({
  required int index1,
  String path2 = '/books/rashi.txt',
}) => Link(
  heRef: 'רש"י',
  index1: index1,
  path2: path2,
  index2: 0,
  connectionType: 'COMMENTARY',
);

Link _regularLink({required int index1}) => Link(
  heRef: 'פרשה א',
  index1: index1,
  path2: '/books/other.txt',
  index2: 0,
  connectionType: 'NONE',
);

Widget _wrap(Widget child, {_RecordingTabsBloc? tabsBloc}) => MaterialApp(
  home: MultiBlocProvider(
    providers: [
      BlocProvider<SettingsBloc>.value(value: _FakeSettingsBloc()),
      BlocProvider<PersonalNotesBloc>.value(value: _FakePersonalNotesBloc()),
      if (tabsBloc != null) BlocProvider<TabsBloc>.value(value: tabsBloc),
    ],
    child: Scaffold(body: child),
  ),
);

PdfCommentaryPanel _panel(
  PdfBookTab tab, {
  bool linksLoading = false,
  int? initialTabIndex,
}) => PdfCommentaryPanel(
  tab: tab,
  linksCount: tab.links.length,
  linksLoading: linksLoading,
  openBookCallback: (_) {},
  fontSize: 16.0,
  initialTabIndex: initialTabIndex,
);

// ─── tests ───────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await Settings.init(cacheProvider: MemorySettingsCache());
    await text_utils.splitByEra(const []);
  });

  // ── לשונית קישורים ──────────────────────────────────────────────────────

  group('PdfCommentaryPanel - לשונית קישורים', () {
    testWidgets(
      'linksLoading=true עם currentTextLineNumber מוגדר → מציג "טוען קישורים..."',
      (tester) async {
        final tab = _tab(currentLine: 10, links: []);

        await tester.pumpWidget(
          _wrap(_panel(tab, linksLoading: true, initialTabIndex: 1)),
        );
        await tester.pump();

        expect(find.text('טוען קישורים...'), findsOneWidget);
        expect(find.text('לא נמצאו קישורים לדף זה'), findsNothing);
      },
    );

    testWidgets(
      'linksLoading=false עם links ריקות → מציג "לא נמצאו קישורים לדף זה"',
      (tester) async {
        final tab = _tab(currentLine: 10, links: []);

        await tester.pumpWidget(
          _wrap(_panel(tab, linksLoading: false, initialTabIndex: 1)),
        );
        await tester.pump();

        expect(find.text('לא נמצאו קישורים לדף זה'), findsOneWidget);
        expect(find.text('טוען קישורים...'), findsNothing);
      },
    );

    testWidgets(
      'linksLoading=true ו-currentTextLineNumber=null → מציג "טוען קישורים..."',
      (tester) async {
        final tab = _tab(links: []); // currentLine=null

        await tester.pumpWidget(
          _wrap(_panel(tab, linksLoading: true, initialTabIndex: 1)),
        );
        await tester.pump();

        expect(find.text('טוען קישורים...'), findsOneWidget);
      },
    );

    testWidgets(
      'קישור מחוץ לטווח (index1 > currentTextLineNumberEnd) לא מוצג',
      (tester) async {
        final tab = _tab(
          currentLine: 10,
          currentLineEnd: 15,
          links: [_regularLink(index1: 16)], // מחוץ לטווח
        );

        await tester.pumpWidget(
          _wrap(_panel(tab, linksLoading: false, initialTabIndex: 1)),
        );
        await tester.pump();

        // אין קישורים בטווח → "לא נמצאו"
        expect(find.text('לא נמצאו קישורים לדף זה'), findsOneWidget);
      },
    );

    testWidgets(
      'currentTextLineNumberEnd=null → fallback לטווח +50, קישור ב-index1=59 נכלל',
      (tester) async {
        final tab = _tab(
          currentLine: 10,
          // currentLineEnd=null → endLine = 10+50 = 60
          links: [_regularLink(index1: 59)],
        );

        await tester.pumpWidget(
          _wrap(_panel(tab, linksLoading: false, initialTabIndex: 1)),
        );
        await tester.pump();

        // קישור בטווח → לא מוצגת הודעת "לא נמצאו"
        expect(find.text('לא נמצאו קישורים לדף זה'), findsNothing);
      },
    );

    testWidgets(
      'currentTextLineNumberEnd=null → fallback לטווח +50, קישור ב-index1=61 מחוץ לטווח',
      (tester) async {
        final tab = _tab(
          currentLine: 10,
          // currentLineEnd=null → endLine = 10+50 = 60
          links: [_regularLink(index1: 61)],
        );

        await tester.pumpWidget(
          _wrap(_panel(tab, linksLoading: false, initialTabIndex: 1)),
        );
        await tester.pump();

        expect(find.text('לא נמצאו קישורים לדף זה'), findsOneWidget);
      },
    );
  });

  // ── לשונית מפרשים ─────────────────────────────────────────────────────────

  group('PdfCommentaryPanel - לשונית מפרשים', () {
    testWidgets(
      'linksLoading=true עם currentTextLineNumber מוגדר → מציג "טוען מפרשים..."',
      (tester) async {
        final tab = _tab(currentLine: 10, links: []);

        await tester.pumpWidget(
          _wrap(_panel(tab, linksLoading: true, initialTabIndex: 0)),
        );
        await tester.pump();

        expect(find.text('טוען מפרשים...'), findsOneWidget);
        expect(find.textContaining('לא נמצאו מפרשים'), findsNothing);
      },
    );

    testWidgets(
      'linksLoading=false ללא links → מציג "לא נמצאו מפרשים לקטע הנבחר"',
      (tester) async {
        final tab = _tab(currentLine: 10, links: []);

        await tester.pumpWidget(
          _wrap(_panel(tab, linksLoading: false, initialTabIndex: 0)),
        );
        await tester.pump();

        expect(find.text('לא נמצאו מפרשים לקטע הנבחר'), findsOneWidget);
        expect(find.text('טוען מפרשים...'), findsNothing);
      },
    );

    testWidgets(
      'מפרש מחוץ לטווח (index1 > currentTextLineNumberEnd) → לא נמצאו מפרשים',
      (tester) async {
        final tab = _tab(
          currentLine: 10,
          currentLineEnd: 15,
          links: [_commentaryLink(index1: 16)], // מחוץ לטווח
        );

        await tester.pumpWidget(
          _wrap(_panel(tab, linksLoading: false, initialTabIndex: 0)),
        );
        await tester.pump();

        expect(find.textContaining('לא נמצאו מפרשים'), findsOneWidget);
      },
    );

    testWidgets(
      'enableInternalFilter=false ובחירה ריקה → מציג את כל המפרשים הזמינים (לא "לא נמצאו")',
      (tester) async {
        final tab = _tab(
          currentLine: 10,
          currentLineEnd: 15,
          links: [_commentaryLink(index1: 12)], // מפרש בטווח, ללא בחירה
        );
        addTearDown(tab.dispose);

        await tester.pumpWidget(
          _wrap(
            PdfCommentaryPanel(
              tab: tab,
              linksCount: tab.links.length,
              linksLoading: false,
              openBookCallback: (_) {},
              fontSize: 16.0,
              initialTabIndex: 0,
              isFullScreen: true,
              enableInternalFilter: false,
            ),
          ),
        );
        await tester.pump();

        // בחירה ריקה אך יש מפרש זמין לקטע → אין הודעת "לא נמצאו"
        expect(tab.activeCommentators, isEmpty);
        expect(find.textContaining('לא נמצאו מפרשים'), findsNothing);
      },
    );
  });

  // ── openFilterRequest: התנהגות baseline + counter ─────────────────────────

  group('PdfCommentaryPanel - openFilterRequest', () {
    PdfCommentaryPanel buildPanel(
      PdfBookTab tab,
      ValueNotifier<int> notifier,
    ) => PdfCommentaryPanel(
      tab: tab,
      linksCount: tab.links.length,
      linksLoading: false,
      openBookCallback: (_) {},
      fontSize: 16.0,
      initialTabIndex: 0,
      openFilterRequest: notifier,
    );

    testWidgets('עליה ב-counter פותחת את חלונית בחירת המפרשים', (tester) async {
      final tab = _tab(currentLine: 10, links: [_commentaryLink(index1: 10)]);
      // מסמן מפרש פעיל כדי למנוע auto-open של ה-filter בעת build
      // (כשאין מפרשים נבחרים והם זמינים, ה-build פותח אותו אוטומטית).
      tab.activeCommentators.add('rashi');
      final notifier = ValueNotifier<int>(0);
      addTearDown(notifier.dispose);

      await tester.pumpWidget(_wrap(buildPanel(tab, notifier)));
      await tester.pumpAndSettle();

      expect(find.text('בחירת מפרשים'), findsNothing);

      notifier.value++;
      await tester.pumpAndSettle();

      expect(find.text('בחירת מפרשים'), findsOneWidget);
    });

    testWidgets(
      'בחירת מפרשים מציגה גם מפרש כלל־ספרי שאין לו קישור בטווח הנוכחי',
      (tester) async {
        final tab = _tab(
          currentLine: 10,
          currentLineEnd: 15,
          links: [
            _commentaryLink(index1: 12),
            _commentaryLink(
              index1: 1000,
              path2: '/books/tosafot.txt',
            ),
          ],
        );
        tab.linksAreComplete = true;
        tab.activeCommentators.add('rashi');
        final notifier = ValueNotifier<int>(0);
        addTearDown(tab.dispose);
        addTearDown(notifier.dispose);

        await tester.pumpWidget(_wrap(buildPanel(tab, notifier)));
        await tester.pumpAndSettle();

        notifier.value++;
        await tester.pumpAndSettle();

        expect(find.text('בחירת מפרשים'), findsOneWidget);
        final selection = tester.widget<CommentatorsSelectionPanel>(
          find.byType(CommentatorsSelectionPanel),
        );
        expect(
          selection.groups.expand((group) => group.commentators).toSet(),
          containsAll({'rashi', 'tosafot'}),
          reason: 'מפרש מחוץ לטווח 10–15 חייב להישאר זמין לבחירה',
        );
        expect(
          selection.rareCommentators,
          isEmpty,
          reason: 'מסך PDF אינו רשאי להסתיר מפרש לפי הקטע הנוכחי',
        );
      },
    );

    testWidgets(
      'counter ישן (value>0 בעת init) לא פותח אוטומטית — רק עליה חדשה כן',
      (tester) async {
        // מדמה תרחיש שבו ה-counter כבר עלה בעבר (state נוצר מחדש בעקבות
        // re-creation של הפאנל / החלפת טאב). אם ה-baseline מתאפס כראוי,
        // הערך הקיים לא צריך לפתוח את הסינון אוטומטית.
        final tab = _tab(currentLine: 10, links: [_commentaryLink(index1: 10)]);
        tab.activeCommentators.add('rashi');
        final notifier = ValueNotifier<int>(5);
        addTearDown(notifier.dispose);

        await tester.pumpWidget(_wrap(buildPanel(tab, notifier)));
        await tester.pumpAndSettle();

        expect(find.text('בחירת מפרשים'), findsNothing);

        // עליה חדשה מעבר ל-baseline אכן פותחת.
        notifier.value = 6;
        await tester.pumpAndSettle();

        expect(find.text('בחירת מפרשים'), findsOneWidget);
      },
    );

    testWidgets(
      'החלפת notifier מאפסת את ה-baseline (counter ישן לא חוסם פתיחות עתידיות)',
      (tester) async {
        final tab = _tab(currentLine: 10, links: [_commentaryLink(index1: 10)]);
        tab.activeCommentators.add('rashi');
        final notifierA = ValueNotifier<int>(7);
        final notifierB = ValueNotifier<int>(0);
        addTearDown(notifierA.dispose);
        addTearDown(notifierB.dispose);

        await tester.pumpWidget(_wrap(buildPanel(tab, notifierA)));
        await tester.pumpAndSettle();

        // החלפה ל-notifier חדש עם value=0. בלי איפוס baseline, _lastSeen היה
        // נשאר על 7 ופתיחות חדשות עד value=7 היו נחסמות.
        await tester.pumpWidget(_wrap(buildPanel(tab, notifierB)));
        await tester.pumpAndSettle();

        expect(find.text('בחירת מפרשים'), findsNothing);

        // עליה אחת קטנה ב-notifier החדש אמורה לפתוח — מוכיח שה-baseline אופס.
        notifierB.value = 1;
        await tester.pumpAndSettle();

        expect(find.text('בחירת מפרשים'), findsOneWidget);
      },
    );
  });

  testWidgets('כפתור ההרחבה מוסיף PdfCommentatorsTab ל-TabsBloc', (
    tester,
  ) async {
    final tab = _tab(currentLine: 10, links: []);
    final tabsBloc = _RecordingTabsBloc();
    addTearDown(tab.dispose);
    addTearDown(tabsBloc.close);

    await tester.pumpWidget(
      _wrap(
        _panel(tab, linksLoading: false, initialTabIndex: 0),
        tabsBloc: tabsBloc,
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('פתח כרטסיית מפרשים'));
    await tester.pump();

    expect(tabsBloc.recordedEvents, hasLength(1));
    final event = tabsBloc.recordedEvents.single as AddTab;
    expect(event.tab, isA<PdfCommentatorsTab>());
    expect((event.tab as PdfCommentatorsTab).sourceTab, same(tab));
  });
}

class _RecordingTabsBloc extends Bloc<TabsEvent, TabsState>
    implements TabsBloc {
  _RecordingTabsBloc() : super(TabsState.initial()) {
    on<TabsEvent>((event, emit) {
      recordedEvents.add(event);
    });
  }

  final List<TabsEvent> recordedEvents = [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
