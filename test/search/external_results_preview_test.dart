import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/library/view/book_preview_panel.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/models/search_preview_target.dart';
import 'package:otzaria/search/view/external_search_results_section.dart';
import 'package:otzaria/search/view/tantivy_search_results.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';

import '../test_helpers/memory_cache_provider.dart';

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _StaticSearchBloc extends SearchBloc {
  _StaticSearchBloc(SearchState initialState) {
    emit(initialState);
  }

  void updateState(SearchState state) => emit(state);

  @override
  void add(SearchEvent event) {}
}

/// תצוגה מקדימה לתוצאות ממקור חיצוני (היברובוקס): המדור החיצוני מקבל את
/// מצב החלונית מהמסך, והפתיחה בעיון מתוכה עוברת במסלול של המקור — ולא
/// באימות מול אינדקס המנוע, שאין בו רשומה לספר חיצוני.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _StaticSearchBloc searchBloc;
  late _MockSettingsBloc settingsBloc;
  late SearchingTab tab;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() {
    DataRepository.instance.library = Future.value(
      Library(categories: const []),
    );
    searchBloc = _StaticSearchBloc(
      const SearchState(searchQuery: 'בדיקה', totalResults: 0, results: []),
    );
    settingsBloc = _MockSettingsBloc();
    whenListen(
      settingsBloc,
      const Stream<SettingsState>.empty(),
      initialState: SettingsState.initial().copyWith(searchShowPreview: true),
    );
    tab = SearchingTab('חיפוש', 'בדיקה', searchBloc: searchBloc);
  });

  tearDown(() async {
    tab.dispose();
    await searchBloc.close();
    await settingsBloc.close();
  });

  Future<void> pumpResults(
    WidgetTester tester, {
    required bool showPreviewPane,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<SearchBloc>.value(value: searchBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: Scaffold(
            body: SizedBox(
              width: 1200,
              height: 600,
              child: TantivySearchResults(
                tab: tab,
                showPreviewPane: showPreviewPane,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  ExternalSearchResultsSection externalSection(WidgetTester tester) {
    final scrollView = tester.widget<CustomScrollView>(
      find.byType(CustomScrollView),
    );
    return scrollView.slivers.whereType<ExternalSearchResultsSection>().single;
  }

  testWidgets('המדור החיצוני מקבל את מצב חלונית התצוגה המקדימה', (
    tester,
  ) async {
    await pumpResults(tester, showPreviewPane: true);
    expect(externalSection(tester).showPreviewPane, isTrue);
  });

  testWidgets('במסך צר המדור החיצוני יודע שאין חלונית', (tester) async {
    await pumpResults(tester, showPreviewPane: false);
    expect(externalSection(tester).showPreviewPane, isFalse);
  });

  testWidgets('פתיחה בעיון מהחלונית משתמשת במסלול של התוצאה החיצונית', (
    tester,
  ) async {
    await pumpResults(tester, showPreviewPane: true);

    var openedExternally = false;
    tab.previewTarget.value = SearchPreviewTarget(
      book: TextBook(title: 'ספר חיצוני'),
      title: 'ספר חיצוני',
      reference: 'ספר חיצוני',
      segment: 4,
      isPdf: false,
      filePath: 'hb:1234',
      openInReader: () => openedExternally = true,
    );
    await tester.pump();

    final panel = tester.widget<BookPreviewPanel>(
      find.byType(BookPreviewPanel),
    );
    panel.onOpenInReader!(4);

    expect(openedExternally, isTrue);
  });

  testWidgets(
    'סינון בעץ משאיר תצוגה של תוצאה חיצונית, שאינה ברשימה הראשית (issue #3257)',
    (tester) async {
      await pumpResults(tester, showPreviewPane: true);
      tab.previewTarget.value = SearchPreviewTarget(
        book: TextBook(title: 'ספר חיצוני'),
        title: 'ספר חיצוני',
        reference: 'ספר חיצוני',
        segment: 4,
        isPdf: false,
        filePath: 'hb:1234',
        openInReader: () {},
      );
      await tester.pump();

      searchBloc.updateState(
        SearchState(
          searchQuery: 'בדיקה',
          totalResults: 0,
          results: const [],
          configuration: SearchConfiguration(currentFacets: const ['/תנ"ך']),
        ),
      );
      await tester.pump();

      final panel = tester.widget<BookPreviewPanel>(
        find.byType(BookPreviewPanel),
      );
      expect(panel.book?.title, 'ספר חיצוני');
    },
  );
}
