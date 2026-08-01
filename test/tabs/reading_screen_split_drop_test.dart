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
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/pdf_commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/reading_screen.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:provider/provider.dart';

import '../helpers/memory_settings_cache.dart';

/// החיווט שב-`reading_screen`: הפלת כרטיסייה על אזור הקריאה של המסך האמיתי
/// מפצלת אותו, והצד שבו שוחררה קובע את סדר החלוניות.
///
/// המסך המוקטן שבטסט האינטגרציה משכפל את החיווט הזה; כאן נבדק המקור עצמו,
/// כי שני הצדדים יכולים להתפצל זה מזה בלי שאיש ישים לב.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  const handleKey = Key('drag-handle');

  Future<TabsBloc> pumpScreen(
    WidgetTester tester,
    List<OpenedTab> tabs, {
    required OpenedTab dragged,
  }) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bloc = TabsBloc(repository: _FakeTabsRepository());
    addTearDown(bloc.close);
    bloc.emit(TabsState(tabs: tabs, currentTabIndex: 0));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
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
            // הידית מרחפת מעל אזור הקריאה במקום שורת הכרטיסיות האמיתית,
            // שאינה חלק מ-ReadingScreen.
            child: Stack(
              children: [
                const Positioned.fill(child: ReadingScreen()),
                Positioned(
                  top: 0,
                  right: 0,
                  child: Draggable<OpenedTab>(
                    data: dragged,
                    feedback: const SizedBox(
                      width: 40,
                      height: 20,
                      child: ColoredBox(color: Color(0xFF000000)),
                    ),
                    child: const SizedBox(
                      key: handleKey,
                      width: 40,
                      height: 20,
                      child: ColoredBox(color: Color(0xFF888888)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return bloc;
  }

  Future<void> dragTo(WidgetTester tester, Offset target) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(handleKey)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveTo(target);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  List<String> titles(OpenedTab tab) =>
      leafPanes(tab).map((p) => p.title).toList();

  testWidgets('שחרור בחצי הימני מכניס את הנגררת לחלונית הראשונה', (
    tester,
  ) async {
    final shown = _commentaryTab('מוצג');
    final dragged = _commentaryTab('נגרר');
    addTearDown(shown.dispose);
    final bloc = await pumpScreen(tester, [shown, dragged], dragged: dragged);

    await dragTo(tester, const Offset(1400, 500));

    expect(bloc.state.tabs, hasLength(1));
    final combined = bloc.state.tabs.single as CombinedTab;
    expect(titles(combined), ['מפרשים | נגרר', 'מפרשים | מוצג']);
    expect(combined.rightTab, same(dragged));
  });

  testWidgets('שחרור בחצי השמאלי מכניס את הנגררת לחלונית השנייה', (
    tester,
  ) async {
    final shown = _commentaryTab('מוצג');
    final dragged = _commentaryTab('נגרר');
    addTearDown(shown.dispose);
    final bloc = await pumpScreen(tester, [shown, dragged], dragged: dragged);

    await dragTo(tester, const Offset(200, 500));

    final combined = bloc.state.tabs.single as CombinedTab;
    expect(titles(combined), ['מפרשים | מוצג', 'מפרשים | נגרר']);
    expect(combined.leftTab, same(dragged));
  });

  testWidgets('טאב שכבר מפוצל אינו מקבל כרטיסייה נוספת', (tester) async {
    final split = CombinedTab(
      rightTab: _commentaryTab('א'),
      leftTab: _commentaryTab('ב'),
    );
    final dragged = _commentaryTab('נגרר');
    final bloc = await pumpScreen(tester, [split, dragged], dragged: dragged);

    await dragTo(tester, const Offset(1400, 500));

    expect(bloc.state.tabs, hasLength(2));
    expect(leafPanes(bloc.state.tabs.first), hasLength(2));
    expect(bloc.state.tabs[1], same(dragged));
  });

  /// המבחן האמיתי של `GlobalObjectKey`: הוא מעביר את תת-העץ רק כל עוד *מבנה*
  /// הווידג'טים שמתחתיו זהה לפני הפיצול ואחריו. עטיפה שנוספת רק במצב מפוצל
  /// מחליפה את סוג הווידג'ט, ואז הספר נבנה מחדש ומיקום הקריאה אובד — בדיוק
  /// מה שהמפתח נועד למנוע. נבדק על המסך האמיתי ולא על `paneBuilder` חשוף.
  testWidgets('פיצול ופירוק אינם בונים מחדש את תוכן החלונית', (tester) async {
    final shown = _commentaryTab('מוצג');
    final dragged = _commentaryTab('נגרר');
    final bloc = await pumpScreen(tester, [shown, dragged], dragged: dragged);

    State<StatefulWidget> paneStateOf(OpenedTab pane) => tester.state(
      find.byWidgetPredicate(
        (w) => w is PdfCommentatorsTabScreen && identical(w.tab, pane),
      ),
    );

    final shownBefore = paneStateOf(shown);

    await dragTo(tester, const Offset(1400, 500));
    expect(bloc.state.tabs.single, isA<CombinedTab>());
    expect(
      paneStateOf(shown),
      same(shownBefore),
      reason: 'הפיצול בנה מחדש את החלונית שכבר הוצגה',
    );

    // הנגררת נכנסה מימין, ולכן היא שנשארת מוצגת אחרי הפירוק — `PageView`
    // בונה רק את הכרטיסייה הפעילה, ואין מה לבדוק על השנייה.
    final draggedInSplit = paneStateOf(dragged);

    bloc.add(const DisableSideBySideMode(0));
    await tester.pumpAndSettle();
    expect(bloc.state.tabs, hasLength(2));
    expect(
      paneStateOf(dragged),
      same(draggedInSplit),
      reason: 'הפירוק בנה מחדש את החלונית שנשארה מוצגת',
    );
  });
}

PdfCommentatorsTab _commentaryTab(String title) {
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
