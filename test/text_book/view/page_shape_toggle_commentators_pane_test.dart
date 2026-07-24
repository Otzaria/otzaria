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
import 'package:otzaria/text_book/view/page_shape/links_notes_sidebar.dart';
import 'package:otzaria/text_book/view/page_shape/page_shape_screen.dart';
import 'package:otzaria/widgets/navigation/panel_tab_header.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../test_helpers/memory_cache_provider.dart';

/// טסט רגרסיה למאזין על `tab.toggleCommentatorsPaneNotifier` ב-PageShapeScreen.
///
/// הבאג המקורי: הקיצור Ctrl+Shift+C מעלה את ה-notifier, אך ב-PageShapeScreen
/// לא היה מאזין כלל — אז ב-split-view וב-PDF הקיצור פעל, ובצורת הדף הוא היה
/// no-op שקט. הטסט הזה מרכיב את המסך ויורה ב-notifier מבחוץ; אם מחר מישהו
/// יפרק את initState/didUpdateWidget ויאבד את `addListener`, הטסט ייפול.
///
/// השימוש ב-[PanelOpenHandle] כאינדיקטור לסגירה: AdaptiveSidePane שומר את
/// תוכן הפאנל ב-tree אחרי הפתיחה הראשונה (רק opacity/width=0), ולכן
/// `find.byType(LinksNotesSidebar)` אינו מבחין בין פתוח לסגור. הידית הצדדית
/// לעומת זאת מוצגת ב-build רק כש-`!_isLeftSidebarOpen`, ולכן היא אינדיקטור
/// אמין למצב הסגור.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const bookTitle = 'ספר בדיקה';

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    // קונפיגורציה ריקה לספר → `_loadConfiguration` חוזרת בלי לקרוא ל-
    // `DefaultCommentators.getDefaults` (שניגש ל-DB ולא יעבוד בטסט).
    await Settings.setValue<String>(
      'page_shape_book_$bookTitle',
      'left|null||right|null||bottom|null||bottomRight|null',
    );
    // הסתרת כל עמודות המפרשים → לא בונים `_CommentaryPane` ולא צורכים נכסים
    // נוספים בעץ הוידג'טים.
    await Settings.setValue<bool>('page_shape_global_visibility_left', false);
    await Settings.setValue<bool>('page_shape_global_visibility_right', false);
    await Settings.setValue<bool>('page_shape_global_visibility_bottom', false);
  });

  Future<TextBookTab> pumpScreen(WidgetTester tester) async {
    final book = TextBook(title: bookTitle);
    final textBookBloc = _TestTextBookBloc(_loadedState(book));
    final personalNotesBloc = _TestPersonalNotesBloc(
      const PersonalNotesState.initial(),
    );
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());
    final tab = TextBookTab(
      book: book,
      index: 0,
      blocOverride: textBookBloc,
    );
    // צורת-הדף קוראת ב-build את NavigationBloc ו-TabsBloc כדי לבדוק אם הטאב
    // בחזית (issue #472); הטאב מסומן כפעיל ומסך הקריאה גלוי כדי לדמות חזית.
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
            child: PageShapeScreen(
              openBookCallback: (_) {},
              tab: tab,
            ),
          ),
        ),
      ),
    );

    // `_loadConfiguration` עובד אסינכרונית; ממתינים עד שהמסך מסיים לבנות.
    await tester.pumpAndSettle();

    return tab;
  }

  testWidgets('רגרסיה: יריית ה-notifier פותחת את הסיידבר '
      '(נכשל אם המאזין לא חובר ב-initState)', (tester) async {
    final tab = await pumpScreen(tester);

    // מצב התחלתי: הסיידבר סגור, ולכן ידית הפתיחה הצדדית גלויה והפאנל
    // אינו ב-tree (לא נפתח אפילו פעם אחת).
    expect(find.byType(PanelOpenHandle), findsOneWidget);
    expect(find.byType(LinksNotesSidebar), findsNothing);

    tab.toggleCommentatorsPaneNotifier.value++;
    await tester.pumpAndSettle();

    // היה צריך לפתוח את הסיידבר.
    expect(
      find.byType(LinksNotesSidebar),
      findsOneWidget,
      reason:
          'יריית ה-notifier הייתה צריכה לפתוח את חלונית הצד — '
          'נכשל אם addListener נמחק מ-PageShapeScreen.initState',
    );
    expect(find.byType(PanelOpenHandle), findsNothing);
  });

  testWidgets('יריית ה-notifier בפעם השנייה סוגרת את הסיידבר שפתחה', (
    tester,
  ) async {
    final tab = await pumpScreen(tester);

    // פתיחה: יריית notifier ראשונה.
    tab.toggleCommentatorsPaneNotifier.value++;
    await tester.pumpAndSettle();
    expect(
      find.byType(PanelOpenHandle),
      findsNothing,
      reason: 'אחרי פתיחה ידית הפתיחה הצדדית אמורה להיעלם',
    );

    // סגירה: יריית notifier שנייה.
    tab.toggleCommentatorsPaneNotifier.value++;
    await tester.pumpAndSettle();

    expect(
      find.byType(PanelOpenHandle),
      findsOneWidget,
      reason:
          'יריית ה-notifier על סיידבר פתוח ("קישורים") אמורה לסגור — '
          'ידית הפתיחה הצדדית חזרה לסימן שהסיידבר סגור',
    );
  });
}

TextBookLoaded _loadedState(TextBook book) {
  return TextBookLoaded(
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
}

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
