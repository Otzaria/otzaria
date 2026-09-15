// רגרסיה ל-issue #877: פתיחת ספר (למשל מהאיתור) בזמן שמסך הקריאה מנותק
// מעץ הרינדור (keepAlive מחוץ למסך) — במובייל קפיצת הסנכרון נצמדה ל-extent
// מיושן ו-onPageChanged החזיר SetCurrentTab עם אינדקס הטאב הקודם.
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  setUp(() => ReadingScreen.debugForceTouchTabs = true);
  tearDown(() => ReadingScreen.debugForceTouchTabs = null);

  testWidgets(
    'טאב שנפתח כשמסך הקריאה אינו מוצג — התצוגה עוברת אליו עם החזרה למסך',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final bloc = TabsBloc(repository: _FakeTabsRepository());
      addTearDown(bloc.close);
      final tabs = [_tab('א'), _tab('ב')];
      addTearDown(() {
        for (final t in tabs) {
          t.dispose();
        }
      });
      bloc.emit(TabsState(tabs: List.of(tabs), currentTabIndex: 0));

      final outer = PageController(initialPage: 1);
      addTearDown(outer.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: MultiBlocProvider(
            providers: [
              BlocProvider<SettingsBloc>.value(value: _FakeSettingsBloc()),
              BlocProvider<PersonalNotesBloc>.value(
                value: _FakePersonalNotesBloc(),
              ),
              BlocProvider<TabsBloc>.value(value: bloc),
              BlocProvider<HistoryBloc>.value(value: _FakeHistoryBloc()),
              Provider<FocusRepository>.value(value: FocusRepository()),
            ],
            child: PageView(
              controller: outer,
              physics: const NeverScrollableScrollPhysics(),
              children: const [
                SizedBox.expand(), // "ספרייה"
                ReadingScreen(),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // המשתמש עובר לספרייה — מסך הקריאה נשמר חי (keepAlive מילדיו) אך מנותק.
      outer.jumpToPage(0);
      await tester.pumpAndSettle();

      // פתיחת ספר מהאיתור: הטאב נוסף וממוקד בזמן שמסך הקריאה אינו בעץ.
      final newTab = _tab('ג');
      tabs.add(newTab);
      bloc.add(AddTab(newTab));
      await tester.pump();
      expect(bloc.state.currentTabIndex, 2);

      // ניווט חזרה למסך הקריאה (openBook → NavigateToScreen(reading)).
      outer.jumpToPage(1);
      await tester.pumpAndSettle();

      final inner = tester.widget<PageView>(
        find.descendant(
          of: find.byType(ReadingScreen),
          matching: find.byType(PageView),
        ),
      );
      expect(
        bloc.state.currentTabIndex,
        2,
        reason: 'האינדקס בבלוק לא אמור להשתנות מהצגת המסך',
      );
      expect(
        inner.controller!.page!.round(),
        2,
        reason: 'התצוגה חייבת להציג את הטאב החדש, לא את הקודם',
      );
    },
  );

  testWidgets(
    'טאב שנפתח באמצע אנימציית המעבר למסך הקריאה — התצוגה מסתנכרנת אליו',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final bloc = TabsBloc(repository: _FakeTabsRepository());
      addTearDown(bloc.close);
      final tabs = [_tab('א'), _tab('ב')];
      addTearDown(() {
        for (final t in tabs) {
          t.dispose();
        }
      });
      bloc.emit(TabsState(tabs: List.of(tabs), currentTabIndex: 0));

      final outer = PageController(initialPage: 0);
      addTearDown(outer.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: MultiBlocProvider(
            providers: [
              BlocProvider<SettingsBloc>.value(value: _FakeSettingsBloc()),
              BlocProvider<PersonalNotesBloc>.value(
                value: _FakePersonalNotesBloc(),
              ),
              BlocProvider<TabsBloc>.value(value: bloc),
              BlocProvider<HistoryBloc>.value(value: _FakeHistoryBloc()),
              Provider<FocusRepository>.value(value: FocusRepository()),
            ],
            child: PageView(
              controller: outer,
              physics: const NeverScrollableScrollPhysics(),
              children: const [
                SizedBox.expand(),
                ReadingScreen(),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // כמו המסלול האמיתי: הניווט מתחיל, וה-emit של הטאבים מגיע פריים אחד
      // אחרי שמסך הקריאה כבר נכנס לעץ (עבודת ה-DB האסינכרונית של OpenOrFocusTab).
      outer.animateToPage(
        1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      await tester.pump(const Duration(milliseconds: 50));

      final newTab = _tab('ג');
      tabs.add(newTab);
      bloc.add(AddTab(newTab));
      await tester.pumpAndSettle();

      final inner = tester.widget<PageView>(
        find.descendant(
          of: find.byType(ReadingScreen),
          matching: find.byType(PageView),
        ),
      );
      expect(bloc.state.currentTabIndex, 2);
      expect(
        inner.controller!.page!.round(),
        2,
        reason: 'התצוגה חייבת להציג את הטאב החדש, לא את הקודם',
      );
    },
  );
}

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
      if (name.contains('save') ||
          name.contains('remap') ||
          name.contains('flush')) {
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
