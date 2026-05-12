import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/models/search_results.dart';
import 'package:otzaria/text_book/utils/section_search_utils.dart';
import 'package:otzaria/text_book/view/text_book_search_screen.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  testWidgets('חיפוש ישן לא דורס תוצאות של חיפוש חדש יותר', (tester) async {
    final textBookBloc = _TestTextBookBloc(_loadedState());
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());
    final focusNode = FocusNode();

    addTearDown(textBookBloc.close);
    addTearDown(settingsBloc.close);
    addTearDown(focusNode.dispose);
    addTearDown(resetSectionSearchWorkerForTesting);

    Future<List<TextSearchResult>> simpleSearchRunner(
      List<String> content,
      String query,
    ) async {
      if (query == 'אב') {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      } else if (query == 'אברהם') {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      return [
        TextSearchResult(
          snippet: 'תוצאה עבור $query',
          index: 0,
          query: query,
          address: query == 'אב' ? 'ישן' : 'חדש',
        ),
      ];
    }

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: textBookBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: Scaffold(
            body: TextBookSearchView(
              data: 'אב אברהם',
              scrollControler: ItemScrollController(),
              focusNode: focusNode,
              closeLeftPaneCallback: () {},
              initialQuery: '',
              simpleSearchRunner: simpleSearchRunner,
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    final textField = find.byType(TextField);

    await tester.enterText(textField, 'אב');
    await tester.pump(const Duration(milliseconds: 250));

    await tester.enterText(textField, 'אברהם');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('חדש'), findsOneWidget);
    expect(find.text('ישן'), findsNothing);

    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('חדש'), findsOneWidget);
    expect(find.text('ישן'), findsNothing);
  });
}

TextBookLoaded _loadedState() {
  return TextBookLoaded(
    book: TextBook(title: 'ספר בדיקה'),
    showLeftPane: false,
    content: const ['שורה א'],
    fontSize: 18,
    showSplitView: false,
    activeCommentators: const [],
    commentatorGroups: const [],
    availableCommentators: const [],
    links: const [],
    visibleLinks: const [],
    linksByLine: const {},
    tableOfContents: const [],
    removeNikud: false,
    visibleIndices: const [0],
    selectedIndex: 0,
    pinLeftPane: false,
    searchText: '',
    scrollController: ItemScrollController(),
    positionsListener: ItemPositionsListener.create(),
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

class _TestSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _TestSettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
