import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/view/full_text_facet_filtering.dart';
import 'package:otzaria/search/view/search_results_layout.dart';
import 'package:otzaria/semantic_search/view/widgets/semantic_facet_filtering.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/widgets/navigation/nav_panel_search.dart';
import 'package:otzaria/widgets/navigation/nav_side_panel.dart';

import '../helpers/memory_settings_cache.dart';

class _LibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {}

class _SettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _TabsBloc extends MockBloc<TabsEvent, TabsState> implements TabsBloc {}

void main() {
  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  Future<
    ({SearchingTab tab, FocusNode resultsFocus, ValueNotifier<int> revision})
  >
  pumpLayout(
    WidgetTester tester, {
    required bool semantic,
    required double width,
    bool initiallyOpen = false,
    SearchingTab? activePane,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 700);
    final tab = SearchingTab('חיפוש', null);
    tab.isLeftPaneOpen.value = initiallyOpen;
    final resultsFocus = FocusNode();
    final revision = ValueNotifier<int>(0);
    final settingsBloc = _SettingsBloc();
    final libraryBloc = _LibraryBloc();
    final tabsBloc = _TabsBloc();
    final library = Library(
      categories: [
        Category(
          title: 'קבוצה',
          description: '',
          shortDescription: '',
          order: 1,
          subCategories: const [],
          books: [TextBook(id: 1, title: 'ספר בדיקה', categoryPath: '/קבוצה')],
          parent: null,
        ),
      ],
    );
    library.subCategories.single.parent = library;
    whenListen(
      settingsBloc,
      const Stream<SettingsState>.empty(),
      initialState: SettingsState.initial(),
    );
    whenListen(
      libraryBloc,
      const Stream<LibraryState>.empty(),
      initialState: LibraryState(library: library, isLoading: false),
    );
    whenListen(
      tabsBloc,
      const Stream<TabsState>.empty(),
      initialState: TabsState(
        tabs: [tab, ?activePane],
        currentTabIndex: activePane == null ? 0 : 1,
        rawActivePane: activePane ?? tab,
      ),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      tab.dispose();
      resultsFocus.dispose();
      revision.dispose();
      await settingsBloc.close();
      await libraryBloc.close();
      await tabsBloc.close();
      tester.view.reset();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<SearchBloc>.value(value: tab.searchBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
            BlocProvider<LibraryBloc>.value(value: libraryBloc),
            BlocProvider<TabsBloc>.value(value: tabsBloc),
          ],
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: ValueListenableBuilder<int>(
                valueListenable: revision,
                builder: (context, value, _) => SearchResultsLayout(
                  tab: tab,
                  hasQuery: false,
                  onEditSearch: () {},
                  countsBuilder: (_, _) => const SizedBox.shrink(),
                  resultsBuilder: (_) => Focus(
                    focusNode: resultsFocus,
                    autofocus: true,
                    child: Center(child: Text('תוצאות $value')),
                  ),
                  facetPane: semantic
                      ? SemanticFacetFiltering(
                          facetCounts: {'/': value + 1, '/קבוצה': value + 1},
                          selectedFacets: const ['/'],
                          isLoading: false,
                          hasResults: true,
                          onSetFacet: (_) {},
                          onToggleFacet: (_) {},
                          onClearAll: () {},
                          onToggleDimension: (_) {},
                        )
                      : SearchFacetFiltering(tab: tab),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (tab: tab, resultsFocus: resultsFocus, revision: revision);
  }

  for (final semantic in [false, true]) {
    for (final width in [1100.0, 700.0, 360.0]) {
      testWidgets(
        'עץ ${semantic ? 'סמנטי' : 'רגיל'} ממקד רק בפתיחה ידנית ($width)',
        (tester) async {
          final harness = await pumpLayout(
            tester,
            semantic: semantic,
            width: width,
            initiallyOpen: width >= 800,
          );
          expect(harness.resultsFocus.hasPrimaryFocus, isTrue);

          if (harness.tab.isLeftPaneOpen.value) {
            await tester.tap(find.byType(NavPanelToggleButton));
            await tester.pumpAndSettle();
          }
          await tester.tap(find.byType(NavPanelToggleButton));
          await tester.pumpAndSettle();

          final fieldFinder = find.byType(EditableText);
          expect(fieldFinder, findsOneWidget);
          final field = tester.widget<EditableText>(fieldFinder);
          expect(field.focusNode.hasFocus, width >= kNavPanelWideMinWidth);
          await tester.enterText(fieldFinder, 'בדיקה');
          await tester.pumpAndSettle();

          // עדכון תוצאות אינו פתיחה חדשה של העץ ואינו גונב את הפוקוס.
          harness.resultsFocus.requestFocus();
          await tester.pump();
          harness.revision.value++;
          await tester.pumpAndSettle();
          expect(harness.resultsFocus.hasPrimaryFocus, isTrue);
          expect(
            tester.widget<EditableText>(fieldFinder).controller.text,
            'בדיקה',
          );

          await tester.tap(find.byType(NavPanelToggleButton));
          await tester.pumpAndSettle();
          expect(field.focusNode.hasFocus, isFalse);
          if (width < 800) {
            expect(field.focusNode.canRequestFocus, isFalse);
          }
          await tester.tap(find.byType(NavPanelToggleButton));
          await tester.pumpAndSettle();
          expect(
            tester.widget<EditableText>(fieldFinder).focusNode.hasFocus,
            width >= kNavPanelWideMinWidth,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('סגירה לפני הפריים מבטלת את מיקוד עץ התוצאות', (tester) async {
    final harness = await pumpLayout(tester, semantic: false, width: 1100);
    tester
        .widget<NavPanelToggleButton>(find.byType(NavPanelToggleButton))
        .onToggle();
    harness.tab.isLeftPaneOpen.value = false;
    await tester.pumpAndSettle();
    expect(harness.resultsFocus.hasPrimaryFocus, isTrue);
  });

  testWidgets('דיאלוג שנפתח לפני הפריים שומר על המיקוד', (tester) async {
    await pumpLayout(tester, semantic: true, width: 1100);
    tester
        .widget<NavPanelToggleButton>(find.byType(NavPanelToggleButton))
        .onToggle();
    final dialogFocus = FocusNode();
    addTearDown(dialogFocus.dispose);
    showDialog<void>(
      context: tester.element(find.byType(SearchResultsLayout)),
      builder: (_) => AlertDialog(
        content: TextField(focusNode: dialogFocus, autofocus: true),
      ),
    );
    await tester.pumpAndSettle();
    expect(dialogFocus.hasPrimaryFocus, isTrue);
    expect(tester.takeException(), isNull);
    Navigator.of(tester.element(find.byType(AlertDialog))).pop();
    await tester.pumpAndSettle();
  });

  testWidgets('עץ בחלונית שאינה פעילה אינו גונב את המיקוד', (tester) async {
    final otherTab = SearchingTab('חלונית אחרת', null);
    addTearDown(otherTab.dispose);
    final harness = await pumpLayout(
      tester,
      semantic: false,
      width: 1100,
      activePane: otherTab,
    );
    tester
        .widget<NavPanelToggleButton>(find.byType(NavPanelToggleButton))
        .onToggle();
    await tester.pumpAndSettle();
    expect(harness.resultsFocus.hasPrimaryFocus, isTrue);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isFalse,
    );
  });
}
