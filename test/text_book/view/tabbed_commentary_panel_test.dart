import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/commentators_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/tabbed_commentary_panel.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  Widget buildPanel({
    int? initialTabIndex,
    Function(int)? onTabChanged,
    bool showSplitView = true,
    TextBookTab? tab,
    _RecordingTabsBloc? tabsBloc,
    List<String> activeCommentators = const [],
  }) {
    final textBookBloc = _TestTextBookBloc(
      _loadedState(activeCommentators: activeCommentators),
    );
    final personalNotesBloc = _TestPersonalNotesBloc(
      const PersonalNotesState.initial(),
    );
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());

    return MaterialApp(
      home: MultiBlocProvider(
        providers: [
          BlocProvider<TextBookBloc>.value(value: textBookBloc),
          BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
          if (tabsBloc != null) BlocProvider<TabsBloc>.value(value: tabsBloc),
        ],
        child: Scaffold(
          body: TabbedCommentaryPanel(
            openBookCallback: (_) {},
            fontSize: 18,
            showSearch: true,
            initialTabIndex: initialTabIndex,
            onTabChanged: onTabChanged,
            showSplitView: showSplitView,
            tab: tab,
          ),
        ),
      ),
    );
  }

  testWidgets('מציג את שלושת הכרטיסיות', (tester) async {
    await tester.pumpWidget(buildPanel());
    await tester.pump();

    expect(find.text('מפרשים'), findsOneWidget);
    expect(find.text('קישורים'), findsOneWidget);
    expect(find.text('הערות'), findsOneWidget);
  });

  testWidgets('onTabChanged נקרא עם האינדקס הנכון כשהמשתמש מחליף טאב', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var reportedIndex = -1;

    await tester.pumpWidget(
      buildPanel(
        initialTabIndex: 0,
        onTabChanged: (index) => reportedIndex = index,
      ),
    );
    await tester.pump();

    // לחיצה על "קישורים" (טאב 1)
    await tester.tap(find.text('קישורים'));
    await tester.pumpAndSettle();

    expect(reportedIndex, 1);
  });

  testWidgets('onTabChanged נקרא עם אינדקס 2 כשלוחצים על הערות', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var reportedIndex = -1;

    await tester.pumpWidget(
      buildPanel(
        initialTabIndex: 0,
        onTabChanged: (index) => reportedIndex = index,
      ),
    );
    await tester.pump();

    await tester.tap(find.text('הערות'));
    await tester.pumpAndSettle();

    expect(reportedIndex, 2);
  });

  testWidgets('שינוי initialTabIndex גורם למעבר לטאב החדש', (tester) async {
    // בדיקה ש-didUpdateWidget מחליף טאב כשהאינדקס משתנה
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var reportedIndex = -1;

    await tester.pumpWidget(
      _TabSwitcherWrapper(
        initialTabIndex: 0,
        onTabChanged: (index) => reportedIndex = index,
      ),
    );
    await tester.pump();

    // מעבר פרוגרמטי לטאב 2 (הערות)
    final state = tester.state<_TabSwitcherWrapperState>(
      find.byType(_TabSwitcherWrapper),
    );
    state.switchTo(2);
    await tester.pumpAndSettle();

    expect(reportedIndex, 2);
  });

  testWidgets('initialTabIndex זהה לא מאפס טאב שנשתנה ידנית (P1 regression)', (
    tester,
  ) async {
    // תרחיש: פתיחה על מפרשים (0), משתמש עובר לקישורים (1),
    // הורה שולח שוב initialTabIndex: 0 — הטאב צריך להישאר על 1 (בחירת המשתמש)
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var reportedIndex = -1;

    await tester.pumpWidget(
      _TabSwitcherWrapper(
        initialTabIndex: 0,
        onTabChanged: (index) => reportedIndex = index,
      ),
    );
    await tester.pump();

    // משתמש עובר לקישורים
    await tester.tap(find.text('קישורים'));
    await tester.pumpAndSettle();
    expect(reportedIndex, 1);

    // הורה שולח שוב אותו initialTabIndex: 0 (לא השתנה)
    final state = tester.state<_TabSwitcherWrapperState>(
      find.byType(_TabSwitcherWrapper),
    );
    state.switchTo(0); // לא שינוי — אותו ערך
    await tester.pumpAndSettle();

    // הטאב צריך להישאר על 1 (בחירת המשתמש) ולא לחזור ל-0
    expect(reportedIndex, 1);
  });

  testWidgets('כפתור ההרחבה מוסיף CommentatorsTab ל-TabsBloc', (tester) async {
    // הגדרת רוחב מסוים כדי שכל הלחצנים ייכנסו בלי תפריט גלישה
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final sourceTab = TextBookTab(
      book: TextBook(title: 'ספר בדיקה'),
      index: 0,
      blocOverride: _TestTextBookBloc(
        _loadedState(activeCommentators: const ['רש"י']),
      ),
    );
    addTearDown(sourceTab.dispose);

    final tabsBloc = _RecordingTabsBloc();
    addTearDown(tabsBloc.close);

    await tester.pumpWidget(
      buildPanel(
        tab: sourceTab,
        tabsBloc: tabsBloc,
        activeCommentators: const ['רש"י'],
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('פתח כרטסיית מפרשים'));
    await tester.pump();

    expect(tabsBloc.recordedEvents, hasLength(1));
    final event = tabsBloc.recordedEvents.single;
    expect(event, isA<AddTab>());
    expect((event as AddTab).tab, isA<CommentatorsTab>());
    expect((event.tab as CommentatorsTab).sourceTab, same(sourceTab));
  });
}

// ===== Wrapper widget לבדיקת דינמיקת initialTabIndex =====

class _TabSwitcherWrapper extends StatefulWidget {
  const _TabSwitcherWrapper({
    required this.initialTabIndex,
    this.onTabChanged,
  });

  final int initialTabIndex;
  final Function(int)? onTabChanged;

  @override
  State<_TabSwitcherWrapper> createState() => _TabSwitcherWrapperState();
}

class _TabSwitcherWrapperState extends State<_TabSwitcherWrapper> {
  late int _currentTabIndex;

  @override
  void initState() {
    super.initState();
    _currentTabIndex = widget.initialTabIndex;
  }

  void switchTo(int index) {
    setState(() => _currentTabIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final textBookBloc = _TestTextBookBloc(_loadedState());
    final personalNotesBloc = _TestPersonalNotesBloc(
      const PersonalNotesState.initial(),
    );
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());

    return MaterialApp(
      home: MultiBlocProvider(
        providers: [
          BlocProvider<TextBookBloc>.value(value: textBookBloc),
          BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
        ],
        child: Scaffold(
          body: TabbedCommentaryPanel(
            openBookCallback: (_) {},
            fontSize: 18,
            showSearch: true,
            initialTabIndex: _currentTabIndex,
            onTabChanged: widget.onTabChanged,
            showSplitView: true,
          ),
        ),
      ),
    );
  }
}

// ===== Helpers =====

TextBookLoaded _loadedState({
  List<String> activeCommentators = const [],
}) => TextBookLoaded(
  book: TextBook(title: 'ספר בדיקה'),
  showLeftPane: false,
  content: const ['שורה א', 'שורה ב'],
  fontSize: 18,
  showSplitView: true,
  showPageShapeView: false,
  activeCommentators: activeCommentators,
  commentatorGroups: const [],
  availableCommentators: activeCommentators,
  links: const <Link>[],
  visibleLinks: const <Link>[],
  linksByLine: const {},
  tableOfContents: const [],
  removeNikud: false,
  visibleIndices: const [0],
  selectedIndex: null,
  pinLeftPane: false,
  searchText: '',
  scrollController: ItemScrollController(),
  positionsListener: ItemPositionsListener.create(),
);

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestPersonalNotesBloc
    extends Bloc<PersonalNotesEvent, PersonalNotesState>
    implements PersonalNotesBloc {
  _TestPersonalNotesBloc(super.initialState) {
    on<PersonalNotesEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _TestSettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
