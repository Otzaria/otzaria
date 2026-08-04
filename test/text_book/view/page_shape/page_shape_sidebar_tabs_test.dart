import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/page_shape/page_shape_screen.dart';
import 'package:otzaria/text_book/view/tabbed_commentary_panel.dart';
import 'package:otzaria/widgets/navigation/panel_tab_header.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../test_helpers/memory_cache_provider.dart';

/// חלונית הצד של צורת הדף מציגה את אותן שלוש לשוניות כמו "מפרשים בצד".
/// לפני כן היו בה "קישורים" ו"הערות" בלבד, בלי מפרשים.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const bookTitle = 'ספר בדיקה';

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    // קונפיגורציה ריקה + טורים מוסתרים → אין _CommentaryPane ואין גישה ל-DB.
    await Settings.setValue<String>(
      'page_shape_book_$bookTitle',
      'left|null||right|null||bottom|null||bottomRight|null',
    );
    await Settings.setValue<bool>('page_shape_global_visibility_left', false);
    await Settings.setValue<bool>('page_shape_global_visibility_right', false);
    await Settings.setValue<bool>('page_shape_global_visibility_bottom', false);
  });

  Future<TextBookTab> pumpScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(2000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final book = TextBook(title: bookTitle);
    final textBookBloc = _TestTextBookBloc(_loadedState(book));
    final personalNotesBloc = _TestPersonalNotesBloc(
      const PersonalNotesState.initial(),
    );
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());
    final tab = TextBookTab(book: book, index: 0, blocOverride: textBookBloc);
    final navigationBloc = _TestNavigationBloc(
      const NavigationState(currentScreen: Screen.reading),
    );
    final tabsBloc = _TestTabsBloc(
      const TabsState(tabs: [], currentTabIndex: 0).copyWith(tabs: [tab]),
    );

    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await textBookBloc.close();
      await personalNotesBloc.close();
      await settingsBloc.close();
      await navigationBloc.close();
      await tabsBloc.close();
      tab.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider<TextBookBloc>.value(value: textBookBloc),
              BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
              BlocProvider<SettingsBloc>.value(value: settingsBloc),
              BlocProvider<NavigationBloc>.value(value: navigationBloc),
              BlocProvider<TabsBloc>.value(value: tabsBloc),
            ],
            child: PageShapeScreen(openBookCallback: (_) {}, tab: tab),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tab;
  }

  /// לשוניות הכותרת, לפי הסדר. הכיתוב מוסתר בחלונית צרה, ולכן הזיהוי לפי אייקון.
  Finder tabWithIcon(IconData icon) => find.descendant(
    of: find.byType(PanelTabHeader),
    matching: find.byIcon(icon),
  );

  testWidgets('הידית הצדדית פותחת את חלונית הצד על שלוש הלשוניות', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(find.byType(TabbedCommentaryPanel), findsNothing);

    await tester.tap(find.byType(PanelOpenHandle));
    await tester.pumpAndSettle();

    expect(find.byType(TabbedCommentaryPanel), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(PanelTabHeader),
        matching: find.byType(Tab),
      ),
      findsNWidgets(3),
    );
    expect(tabWithIcon(FluentIcons.book_24_regular), findsOneWidget);
    expect(tabWithIcon(FluentIcons.link_24_regular), findsOneWidget);
    expect(tabWithIcon(FluentIcons.note_24_regular), findsOneWidget);

    // הלשונית הפעילה היא "מפרשים" — בלי מפרשים נבחרים מוצג מסך הבחירה,
    // ולא רשימת הקישורים.
    expect(find.text('בחירת מפרשים'), findsOneWidget);
    expect(find.text('לא נמצאו קישורים לקטע הנבחר'), findsNothing);
  });

  testWidgets('מעבר ללשונית הקישורים מציג את תוכנה', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byType(PanelOpenHandle));
    await tester.pumpAndSettle();

    await tester.tap(tabWithIcon(FluentIcons.link_24_regular));
    await tester.pumpAndSettle();

    expect(find.text('לא נמצאו קישורים לקטע הנבחר'), findsOneWidget);
  });

  testWidgets('הקיצור Ctrl+Shift+C פותח את לשונית המפרשים וסוגר בשנייה', (
    tester,
  ) async {
    final tab = await pumpScreen(tester);

    tab.toggleCommentatorsPaneNotifier.value++;
    await tester.pumpAndSettle();
    expect(find.byType(PanelOpenHandle), findsNothing);
    expect(find.text('בחירת מפרשים'), findsOneWidget);

    tab.toggleCommentatorsPaneNotifier.value++;
    await tester.pumpAndSettle();
    expect(find.byType(PanelOpenHandle), findsOneWidget);
  });
}

TextBookLoaded _loadedState(TextBook book) => TextBookLoaded(
  book: book,
  showLeftPane: false,
  content: const ['שורה א'],
  fontSize: 18,
  showSplitView: false,
  showPageShapeView: true,
  activeCommentators: const [],
  commentatorGroups: const [],
  availableCommentators: const [],
  links: const <Link>[],
  visibleLinks: const <Link>[],
  linksByLine: const {},
  tableOfContents: const [],
  removeNikud: false,
  removePunctuation: false,
  visibleIndices: const [0],
  selectedIndex: 0,
  pinLeftPane: false,
  searchText: '',
  scrollController: ItemScrollController(),
  positionsListener: ItemPositionsListener.create(),
  searchMode: SearchMode.exact,
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

class _TestNavigationBloc extends Bloc<NavigationEvent, NavigationState>
    implements NavigationBloc {
  _TestNavigationBloc(super.initialState) {
    on<NavigationEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestTabsBloc extends Bloc<TabsEvent, TabsState> implements TabsBloc {
  _TestTabsBloc(super.initialState) {
    on<TabsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
