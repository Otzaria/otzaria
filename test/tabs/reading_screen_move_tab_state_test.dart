import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/pdf_headings.dart';
import 'package:otzaria/pdf_book/view/pdf_commentators_tab_screen.dart';
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
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/reading_screen.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:provider/provider.dart';

import '../helpers/memory_settings_cache.dart';

/// אימות התנהגותי של התיקון "העברת כרטיסייה שומרת State", על ה-`ReadingScreen`
/// האמיתי עם `TabsBloc` אמיתי ואירועי `MoveTab` אמיתיים (לא PageView מדומה).
///
/// הקריטריון: אחרי `MoveTab`, אובייקט ה-`State` של מסך הטאב חייב להיות *אותו
/// מופע* (`identical`). ב-PDF זה בדיוק ההבדל בין "המסמך נשאר פתוח" לבין
/// "dispose סוגר אותו ו-initState טוען אותו מחדש מהדיסק".
///
/// למה `PdfCommentatorsTab` ולא `PdfBookTab`: `PdfBookScreen` דורש pdfrx נייטיב,
/// גישה לדיסק, `BookmarkBloc` ו-`TourCubit` — לא ניתן להרכיב אותו ב-widget test.
/// `PdfCommentatorsTabScreen` הוא טאב אמיתי העובר באותו `_buildTabView`, עם
/// `AutomaticKeepAliveClientMixin` ו-State מקומי — אותו פרופיל בדיוק.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  /// מרכיב את ה-ReadingScreen האמיתי מעל TabsBloc אמיתי.
  Future<TabsBloc> pumpReadingScreen(
    WidgetTester tester,
    List<OpenedTab> tabs, {
    int currentTabIndex = 0,
    SideBySideMode? sideBySideMode,
  }) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bloc = TabsBloc(repository: _FakeTabsRepository());
    addTearDown(bloc.close);
    bloc.emit(
      TabsState(
        tabs: tabs,
        currentTabIndex: currentTabIndex,
        sideBySideMode: sideBySideMode,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: MultiBlocProvider(
            providers: [
              BlocProvider<SettingsBloc>.value(value: _FakeSettingsBloc()),
              BlocProvider<PersonalNotesBloc>.value(
                value: _FakePersonalNotesBloc(),
              ),
              BlocProvider<TabsBloc>.value(value: bloc),
              BlocProvider<HistoryBloc>.value(value: _FakeHistoryBloc()),
              Provider<FocusRepository>.value(value: FocusRepository()),
            ],
            child: const ReadingScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return bloc;
  }

  /// ה-State החי של מסך הטאב בעל הכותרת [title], או null אם אינו בעץ.
  State? tabScreenState(WidgetTester tester, String title) {
    final finder = find.byWidgetPredicate(
      (w) => w is PdfCommentatorsTabScreen && w.tab.title.contains(title),
      skipOffstage: false,
    );
    if (finder.evaluate().isEmpty) return null;
    return tester.state(finder);
  }

  /// מבקר בכל טאב לפי הסדר כדי שכל ה-Stateים ייבנו וישמרו חיים (keepAlive),
  /// ואז חוזר ל-[backTo]. בלי זה, טאב שמעולם לא הוצג פשוט אינו בעץ.
  Future<void> visitAllTabs(
    WidgetTester tester,
    TabsBloc bloc,
    int backTo,
  ) async {
    for (var i = 0; i < bloc.state.tabs.length; i++) {
      bloc.add(SetCurrentTab(i));
      await tester.pumpAndSettle();
    }
    bloc.add(SetCurrentTab(backTo));
    await tester.pumpAndSettle();
  }

  group('ReadingScreen אמיתי + MoveTab — שימור State', () {
    testWidgets('הזזה קדימה: כל הטאבים שומרים את אותו מופע State', (
      tester,
    ) async {
      final tabs = [_tab('א'), _tab('ב'), _tab('ג')];
      addTearDown(() {
        for (final t in tabs) {
          t.dispose();
        }
      });
      final bloc = await pumpReadingScreen(tester, tabs);
      await visitAllTabs(tester, bloc, 0);

      final before = {
        for (final t in ['א', 'ב', 'ג']) t: tabScreenState(tester, t),
      };
      expect(before.values, everyElement(isNotNull));

      // גרירת הטאב הראשון לסוף — התרחיש המדויק של הבאג.
      bloc.add(MoveTab(tabs[0], 2));
      await tester.pumpAndSettle();

      expect(_titles(bloc), [
        'ב',
        'ג',
        'א',
      ]);
      for (final t in ['א', 'ב', 'ג']) {
        expect(
          identical(tabScreenState(tester, t), before[t]),
          isTrue,
          reason: 'ה-State של "$t" הוחלף בהזזה — ב-PDF זה dispose+טעינה מחדש',
        );
      }
    });

    testWidgets('הזזה אחורה: הטאב האחרון לראש, כל ה-Stateים נשמרים', (
      tester,
    ) async {
      final tabs = [_tab('א'), _tab('ב'), _tab('ג')];
      addTearDown(() {
        for (final t in tabs) {
          t.dispose();
        }
      });
      final bloc = await pumpReadingScreen(tester, tabs);
      await visitAllTabs(tester, bloc, 2);

      final before = {
        for (final t in ['א', 'ב', 'ג']) t: tabScreenState(tester, t),
      };

      bloc.add(MoveTab(tabs[2], 0));
      await tester.pumpAndSettle();

      expect(_titles(bloc), ['ג', 'א', 'ב']);
      for (final t in ['א', 'ב', 'ג']) {
        expect(identical(tabScreenState(tester, t), before[t]), isTrue);
      }
    });

    testWidgets('הזזת הטאב הפעיל: הוא נשאר הפעיל ושומר State', (tester) async {
      final tabs = [_tab('א'), _tab('ב'), _tab('ג')];
      addTearDown(() {
        for (final t in tabs) {
          t.dispose();
        }
      });
      final bloc = await pumpReadingScreen(tester, tabs);
      await visitAllTabs(tester, bloc, 0);
      final activeBefore = tabScreenState(tester, 'א');

      bloc.add(MoveTab(tabs[0], 2));
      await tester.pumpAndSettle();

      expect(
        bloc.state.currentTabIndex,
        2,
        reason: 'הטאב שנגרר היה הפעיל — ההדגשה חייבת לעקוב אחריו למיקום החדש',
      );
      expect(_short(bloc.state.currentTab!.title), 'א');
      expect(identical(tabScreenState(tester, 'א'), activeBefore), isTrue);
    });

    testWidgets('הזזת טאב רקע: הטאב הפעיל נשאר פעיל וה-State שלו נשמר', (
      tester,
    ) async {
      final tabs = [_tab('א'), _tab('ב'), _tab('ג')];
      addTearDown(() {
        for (final t in tabs) {
          t.dispose();
        }
      });
      final bloc = await pumpReadingScreen(tester, tabs);
      await visitAllTabs(tester, bloc, 1); // "ב" פעיל
      final activeBefore = tabScreenState(tester, 'ב');

      // מזיז את "ג" (רקע) לראש — "ב" זז מ-1 ל-2 בלי שהמשתמש נגע בו.
      bloc.add(MoveTab(tabs[2], 0));
      await tester.pumpAndSettle();

      expect(_titles(bloc), ['ג', 'א', 'ב']);
      expect(
        bloc.state.currentTabIndex,
        2,
        reason: 'הטאב הפעיל "ב" נדחף קדימה ולכן האינדקס שלו התעדכן',
      );
      expect(_short(bloc.state.currentTab!.title), 'ב');
      expect(identical(tabScreenState(tester, 'ב'), activeBefore), isTrue);
    });

    testWidgets('הזזה עם טאב מוצמד ברשימה — State נשמר וההדגשה נכונה', (
      tester,
    ) async {
      final tabs = [_tab('א')..isPinned = true, _tab('ב'), _tab('ג')];
      addTearDown(() {
        for (final t in tabs) {
          t.dispose();
        }
      });
      final bloc = await pumpReadingScreen(tester, tabs);
      await visitAllTabs(tester, bloc, 2);
      final before = {
        for (final t in ['א', 'ב', 'ג']) t: tabScreenState(tester, t),
      };

      bloc.add(MoveTab(tabs[1], 2)); // "ב" אחרי "ג"
      await tester.pumpAndSettle();

      expect(_titles(bloc), ['א', 'ג', 'ב']);
      expect(bloc.state.tabs[0].isPinned, isTrue);
      expect(_short(bloc.state.currentTab!.title), 'ג');
      for (final t in ['א', 'ב', 'ג']) {
        expect(identical(tabScreenState(tester, t), before[t]), isTrue);
      }
    });

    testWidgets('הזזה ואז סגירה: הטאבים הנותרים שומרים State', (tester) async {
      final tabs = [_tab('א'), _tab('ב'), _tab('ג')];
      addTearDown(() {
        for (final t in tabs) {
          t.dispose();
        }
      });
      final bloc = await pumpReadingScreen(tester, tabs);
      await visitAllTabs(tester, bloc, 0);
      final before = {
        for (final t in ['ב', 'ג']) t: tabScreenState(tester, t),
      };

      bloc.add(MoveTab(tabs[0], 2));
      await tester.pumpAndSettle();
      bloc.add(RemoveTab(tabs[0]));
      await tester.pumpAndSettle();

      expect(_titles(bloc), ['ב', 'ג']);
      for (final t in ['ב', 'ג']) {
        expect(
          identical(tabScreenState(tester, t), before[t]),
          isTrue,
          reason: 'סגירה אחרי הזזה לא תקפיץ Stateים של טאבים אחרים',
        );
      }
      // _disposeTabLater מתזמן טיימר של 350ms — מרוקנים אותו לפני סוף הטסט.
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('הזזה, סגירה ופתיחה מחדש — אין דליפת מפתחות ואין קריסה', (
      tester,
    ) async {
      final tabs = [_tab('א'), _tab('ב')];
      final extra = _tab('ד');
      addTearDown(() {
        for (final t in [...tabs, extra]) {
          t.dispose();
        }
      });
      final bloc = await pumpReadingScreen(tester, tabs);
      await visitAllTabs(tester, bloc, 0);

      bloc.add(MoveTab(tabs[0], 1));
      await tester.pumpAndSettle();
      bloc.add(RemoveTab(tabs[1]));
      await tester.pumpAndSettle();
      bloc.add(AddTab(extra));
      await tester.pumpAndSettle();

      expect(_titles(bloc), ['א', 'ד']);
      expect(_short(bloc.state.currentTab!.title), 'ד');
      expect(tester.takeException(), isNull);
    });
  });

  group('ReadingScreen — אינדקסי side-by-side אחרי MoveTab', () {
    testWidgets('MoveTab מעדכן leftTabIndex/rightTabIndex לטאבים הנכונים', (
      tester,
    ) async {
      final tabs = [_tab('א'), _tab('ב'), _tab('ג')];
      addTearDown(() {
        for (final t in tabs) {
          t.dispose();
        }
      });
      // right=0 ("א"), left=2 ("ג")
      final bloc = await pumpReadingScreen(
        tester,
        tabs,
        sideBySideMode: const SideBySideMode(leftTabIndex: 2, rightTabIndex: 0),
      );

      // מזיז את "ב" (שאינו חלק מהמצב) לראש → שני האינדקסים זזים ב-1.
      bloc.add(MoveTab(tabs[1], 0));
      await tester.pumpAndSettle();

      final mode = bloc.state.sideBySideMode!;
      expect(
        _short(bloc.state.tabs[mode.rightTabIndex].title),
        'א',
        reason: 'rightTabIndex חייב להצביע על אותו טאב גם אחרי ההזזה',
      );
      expect(_short(bloc.state.tabs[mode.leftTabIndex].title), 'ג');
    });

    testWidgets('הזזת טאב שהוא עצמו צד ב-side-by-side מעדכנת את האינדקס שלו', (
      tester,
    ) async {
      final tabs = [_tab('א'), _tab('ב'), _tab('ג')];
      addTearDown(() {
        for (final t in tabs) {
          t.dispose();
        }
      });
      final bloc = await pumpReadingScreen(
        tester,
        tabs,
        sideBySideMode: const SideBySideMode(leftTabIndex: 1, rightTabIndex: 0),
      );

      bloc.add(MoveTab(tabs[0], 2)); // "א" (right) לסוף
      await tester.pumpAndSettle();

      final mode = bloc.state.sideBySideMode!;
      expect(_titles(bloc), ['ב', 'ג', 'א']);
      expect(
        _short(bloc.state.tabs[mode.rightTabIndex].title),
        'א',
        reason: 'הצד הימני חייב להישאר "א" גם אחרי שהוא נגרר',
      );
      expect(_short(bloc.state.tabs[mode.leftTabIndex].title), 'ב');
    });
  });

  group('ReadingScreen — ה-PageView עוקב אחרי הטאב הפעיל אחרי MoveTab', () {
    /// אינדקס העמוד שה-PageView באמת מציג.
    double displayedPage(WidgetTester tester) {
      final pageView = tester.widget<PageView>(find.byType(PageView));
      return pageView.controller!.page!;
    }

    testWidgets('הזזת הטאב הפעיל — התצוגה קופצת למיקום החדש', (tester) async {
      final tabs = [_tab('א'), _tab('ב'), _tab('ג')];
      addTearDown(() {
        for (final t in tabs) {
          t.dispose();
        }
      });
      final bloc = await pumpReadingScreen(tester, tabs);
      await visitAllTabs(tester, bloc, 0);
      expect(displayedPage(tester), 0);

      bloc.add(MoveTab(tabs[0], 2));
      await tester.pumpAndSettle();

      expect(bloc.state.currentTabIndex, 2);
      expect(
        displayedPage(tester),
        2,
        reason:
            'currentTabIndex השתנה → ה-listener נדלק → jumpToPage. אם נכשל, '
            'המשתמש רואה טאב אחר מזה שמודגש בשורת הטאבים',
      );
    });

    testWidgets('הזזת טאב רקע שדוחפת את הפעיל — התצוגה עוקבת', (tester) async {
      final tabs = [_tab('א'), _tab('ב'), _tab('ג')];
      addTearDown(() {
        for (final t in tabs) {
          t.dispose();
        }
      });
      final bloc = await pumpReadingScreen(tester, tabs);
      await visitAllTabs(tester, bloc, 1);
      expect(displayedPage(tester), 1);

      bloc.add(MoveTab(tabs[2], 0)); // ['ג','א','ב'] — "ב" הפעיל עובר ל-2
      await tester.pumpAndSettle();

      expect(bloc.state.currentTabIndex, 2);
      expect(displayedPage(tester), 2);
    });

    testWidgets(
      'הזזה שלא משנה את אינדקס הפעיל — התצוגה נשארת על הטאב הפעיל',
      (tester) async {
        // תרחיש הגבול של ה-listenWhen: currentTabIndex ו-tabs.length שניהם
        // לא משתנים, ולכן ה-listener *לא* נדלק. חייבים לוודא שזה תקין.
        final tabs = [_tab('א'), _tab('ב'), _tab('ג'), _tab('ד')];
        addTearDown(() {
          for (final t in tabs) {
            t.dispose();
          }
        });
        final bloc = await pumpReadingScreen(tester, tabs);
        await visitAllTabs(tester, bloc, 0); // "א" פעיל באינדקס 0
        expect(displayedPage(tester), 0);

        // מחליף את "ג" ו-"ד" אחרי הטאב הפעיל — אינדקס 0 לא זז.
        bloc.add(MoveTab(tabs[3], 1));
        await tester.pumpAndSettle();

        expect(_titles(bloc), [
          'א',
          'ד',
          'ב',
          'ג',
        ]);
        expect(bloc.state.currentTabIndex, 0);
        expect(
          displayedPage(tester),
          0,
          reason: 'הטאב הפעיל לא זז — התצוגה חייבת להישאר עליו',
        );
        expect(
          find.byWidgetPredicate(
            (w) => w is PdfCommentatorsTabScreen && w.tab.title.contains('א'),
          ),
          findsOneWidget,
        );
      },
    );
  });
}

/// כותרות הטאבים ללא הקידומת "מפרשים | " שמוסיף [PdfCommentatorsTab].
List<String> _titles(TabsBloc bloc) =>
    bloc.state.tabs.map((t) => _short(t.title)).toList();

String _short(String title) => title.replaceFirst('מפרשים | ', '');

/// כרטסיית מפרשים קלה שנטענת סינכרונית — טאב אמיתי לכל דבר.
PdfCommentatorsTab _tab(String title) {
  final sourceTab = PdfBookTab(
    book: PdfBook(title: title, path: '/tmp/$title.pdf'),
    pageNumber: 1,
  );
  sourceTab.pdfHeadings = PdfHeadings(
    bookTitle: title,
    headingsMap: {'פרק א': 1},
  );
  sourceTab.currentTitle.value = 'פרק א';
  sourceTab.currentTextLineNumber = 1;
  sourceTab.currentTextLineNumberEnd = 9;
  return PdfCommentatorsTab(sourceTab: sourceTab);
}

class _FakeTabsRepository implements TabsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isMethod) {
      final name = invocation.memberName.toString();
      if (name.contains('save') || name.contains('remap')) {
        return Future<void>.value();
      }
      if (name.contains('loadTabs')) return <OpenedTab>[];
      if (name.contains('loadCurrentTabIndex')) return 0;
    }
    return null;
  }
}

class _FakeHistoryBloc extends Bloc<HistoryEvent, HistoryState>
    implements HistoryBloc {
  _FakeHistoryBloc() : super(HistoryInitial()) {
    on<HistoryEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _FakeSettingsBloc() : super(SettingsState.initial()) {
    on<SettingsEvent>((_, _) {});
  }

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
