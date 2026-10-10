import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/tabs/models/commentators_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/commentators_tab_screen.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../helpers/memory_settings_cache.dart';
import '../../unit/mocks/mock_settings_repository.mocks.dart';

class _LoadingTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _LoadingTextBookBloc(super.initialState, TextBookLoaded loaded) {
    on<TextBookEvent>((event, emit) {
      if (event is LoadContent) emit(loaded);
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestPersonalNotesBloc
    extends Bloc<PersonalNotesEvent, PersonalNotesState>
    implements PersonalNotesBloc {
  _TestPersonalNotesBloc() : super(const PersonalNotesState.initial()) {
    on<PersonalNotesEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

TextBookLoaded _loaded(TextBook book, List<TocEntry> toc, int index) =>
    TextBookLoaded(
      book: book,
      showLeftPane: false,
      content: List.generate(20, (i) => 'שורה $i'),
      fontSize: 25,
      showSplitView: false,
      activeCommentators: const [],
      commentatorGroups: const [],
      availableCommentators: const [],
      links: const [],
      visibleLinks: const [],
      linksByLine: const {},
      tableOfContents: toc,
      removeNikud: false,
      visibleIndices: [index],
      pinLeftPane: false,
      searchText: '',
      scrollController: ItemScrollController(),
      positionsListener: ItemPositionsListener.create(),
    );

void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  testWidgets('המיקום שנשמר הוא הדף שאליו נווט בכרטיסיה ולא דף הפתיחה', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final book = TextBook(title: 'כתובות');
    final toc = [
      TocEntry(text: 'דף ב', index: 0),
      TocEntry(text: 'דף כ', index: 10),
    ];
    final sourceTab = TextBookTab(book: book, index: 10);
    final tabBloc = _LoadingTextBookBloc(
      TextBookInitial.named(book, 10, false, const []),
      _loaded(book, toc, 10),
    );
    final tab = CommentatorsTab(
      sourceTab: sourceTab,
      startIndex: 10,
      blocOverride: tabBloc,
    );
    final settings = SettingsBloc(repository: MockSettingsRepository());
    final notes = _TestPersonalNotesBloc();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await settings.close();
      await notes.close();
      await tabBloc.close();
      sourceTab.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<SettingsBloc>.value(value: settings),
            BlocProvider<PersonalNotesBloc>.value(value: notes),
          ],
          child: Scaffold(
            body: CommentatorsTabScreen(tab: tab, openBookCallback: (_) {}),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(tab.toJson()['initialIndex'], 10);

    await tester.tap(find.byTooltip('הפרק הקודם').first);
    await tester.pump();

    expect(tab.toJson()['initialIndex'], 0);
  });
}
