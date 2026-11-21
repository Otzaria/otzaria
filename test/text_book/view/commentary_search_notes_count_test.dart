import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_common/models/commentator_group.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/commentary_list_base.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/widgets/commentary/commentary_content.dart';

import '../../support/search_engine_test_init.dart';
import '../../test_helpers/fake_commentary_library_provider.dart';
import '../../test_helpers/memory_cache_provider.dart';
import '../../test_helpers/stub_settings_bloc.dart';
import '../../test_helpers/stub_text_book_bloc.dart';

/// issue #5715: חיפוש בכרטיסיית המפרשים מדגיש התאמות בהערות הספר אך לא
/// סופר אותן — החלונית מציגה "אין תוצאות" כשההתאמות רק בהערות.
Future<void> main() async {
  final engineReady = await tryInitSearchEngine();
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  late StubTextBookBloc textBookBloc;
  late StubSettingsBloc settingsBloc;

  setUp(() {
    LibraryProviderManager.instance.resetForTesting();
    LibraryProviderManager.instance.seedMappingsForTesting(
      mapping: {
        BookCompositeKey.create(
          title: 'מפרש בדיקה',
          categoryId: 1,
          fileType: 'txt',
        ): FakeCommentaryLibraryProvider(),
      },
      providers: [FakeCommentaryLibraryProvider()],
    );
    settingsBloc = StubSettingsBloc(SettingsState.initial());
  });

  tearDown(() async {
    await textBookBloc.close();
    await settingsBloc.close();
    LibraryProviderManager.instance.resetForTesting();
  });

  Future<CommentaryListBaseState> search(
    WidgetTester tester,
    String query,
    ValueNotifier<List<CommentarySearchSnippet>> snippets,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: textBookBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: Scaffold(
            body: SizedBox(
              height: 600,
              width: 500,
              child: CommentaryListBase(
                openBookCallback: (_) {},
                fontSize: 18,
                showSearch: true,
                shrinkWrap: false,
                externalSearchSnippetsNotifier: snippets,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(FluentIcons.search_24_regular).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), query);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    return tester.state<CommentaryListBaseState>(
      find.byType(CommentaryListBase),
    );
  }

  testWidgets('חיפוש בכרטיסיית מפרשים סופר גם את ההערות (issue #5715)', (
    tester,
  ) async {
    textBookBloc = StubTextBookBloc(
      _state(
        content: '<i class="footnote">הלכות שבת ושבת</i>גוף הקטע',
        withCommentary: false,
      ),
    );
    final snippets = ValueNotifier<List<CommentarySearchSnippet>>(const []);
    addTearDown(snippets.dispose);

    final list = await search(tester, 'שבת', snippets);

    expect(list.totalSearchResultsNotifier.value, 2);
    expect(snippets.value.map((s) => s.path), [kNotesCommentatorTitle]);
    expect(snippets.value.single.globalIndex, 0);
  }, skip: !engineReady);

  testWidgets('הערות ומפרשים: ההערות נספרות ראשונות והמפרש אחריהן', (
    tester,
  ) async {
    textBookBloc = StubTextBookBloc(
      _state(
        content: '<i class="footnote">הערה לבדיקה</i>גוף הקטע',
        withCommentary: true,
      ),
    );
    final snippets = ValueNotifier<List<CommentarySearchSnippet>>(const []);
    addTearDown(snippets.dispose);

    final list = await search(tester, 'בדיקה', snippets);

    expect(list.totalSearchResultsNotifier.value, 2);
    expect(snippets.value.map((s) => s.path), [
      kNotesCommentatorTitle,
      'מפרש בדיקה.txt',
    ]);
    expect(snippets.value.map((s) => s.globalIndex), [0, 1]);

    list.navigateToGlobalIndex(0);
    await tester.pumpAndSettle();
    final content = tester.widget<CommentaryContent>(
      find.byType(CommentaryContent),
    );
    expect(content.currentSearchIndex, -1);

    list.navigateSearchNext();
    await tester.pumpAndSettle();
    expect(list.currentSearchIndexNotifier.value, 1);
    expect(
      tester
          .widget<CommentaryContent>(find.byType(CommentaryContent))
          .currentSearchIndex,
      0,
    );
  }, skip: !engineReady);
}

TextBookLoaded _state({required String content, required bool withCommentary}) {
  final link = Link(
    heRef: 'בדיקה א',
    index1: 1,
    path2: 'מפרש בדיקה.txt',
    index2: 1,
    connectionType: 'COMMENTARY',
    targetCategoryId: 1,
    targetFileType: 'txt',
  );
  final commentators = [
    if (withCommentary) 'מפרש בדיקה',
    kNotesCommentatorTitle,
  ];
  return TextBookLoaded(
    book: TextBook(title: 'ספר בדיקה'),
    showLeftPane: false,
    content: [content],
    fontSize: 18,
    showSplitView: false,
    activeCommentators: commentators,
    commentatorGroups: const [],
    availableCommentators: commentators,
    links: [if (withCommentary) link],
    visibleLinks: const [],
    linksByLine: {
      if (withCommentary) 1: [link],
    },
    tableOfContents: const [],
    removeNikud: false,
    visibleIndices: const [0],
    selectedIndex: 0,
    pinLeftPane: false,
    searchText: '',
  );
}
