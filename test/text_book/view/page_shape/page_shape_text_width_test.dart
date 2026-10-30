import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
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
import 'package:otzaria/text_book/view/page_shape/simple_text_viewer.dart';

import '../../../test_helpers/memory_cache_provider.dart';

/// הגדרת "רוחב הטקסט" חלה בצורת הדף רק כשהמתג בהגדרות צורת הדף דלוק —
/// ואז על כל תוכן הדף, ממורכז עם שוליים (issue #889, מתג מ-issue #1005).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const bookTitle = 'ספר בדיקה';
  const screenWidth = 2000.0;

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

  Future<void> pumpScreen(
    WidgetTester tester, {
    required double textMaxWidth,
    bool applyTextMaxWidth = true,
  }) async {
    await Settings.setValue<bool>(
      'page_shape_apply_text_max_width',
      applyTextMaxWidth,
    );
    tester.view.physicalSize = const Size(screenWidth, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final book = TextBook(title: bookTitle);
    final textBookBloc = _TestTextBookBloc(_loadedState(book));
    final personalNotesBloc = _TestPersonalNotesBloc(
      const PersonalNotesState.initial(),
    );
    final settingsBloc = _TestSettingsBloc(
      SettingsState.initial().copyWith(textMaxWidth: textMaxWidth),
    );
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
  }

  testWidgets('ללא הגבלה (0) — תוכן הדף מתפרס על כל הרוחב', (tester) async {
    await pumpScreen(tester, textMaxWidth: 0);

    final size = tester.getSize(find.byType(SimpleTextViewer));
    expect(size.width, greaterThan(screenWidth * 0.9));
  });

  testWidgets('רוחב יעד — תוכן הדף מוגבל וממורכז עם שוליים', (tester) async {
    await pumpScreen(tester, textMaxWidth: 900);

    final rect = tester.getRect(find.byType(SimpleTextViewer));
    expect(rect.width, lessThanOrEqualTo(900 + 1));
    // ממורכז: שוליים דומים משני הצדדים.
    expect((rect.left - (screenWidth - rect.right)).abs(), lessThan(40));
  });

  testWidgets('המתג כבוי (ברירת המחדל) — ההגדרה אינה חלה על הדף', (
    tester,
  ) async {
    await pumpScreen(tester, textMaxWidth: 900, applyTextMaxWidth: false);

    final size = tester.getSize(find.byType(SimpleTextViewer));
    expect(size.width, greaterThan(screenWidth * 0.9));
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
