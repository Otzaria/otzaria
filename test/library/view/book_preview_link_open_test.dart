import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/library/view/book_preview_panel.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/combined_view/combined_book_screen.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../helpers/memory_settings_cache.dart';

class _Recorder<E, S> extends Bloc<E, S> {
  final events = <E>[];
  _Recorder(super.initialState) {
    on<E>((event, _) => events.add(event));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TabsBloc extends _Recorder<TabsEvent, TabsState> implements TabsBloc {
  _TabsBloc() : super(const TabsState(tabs: [], currentTabIndex: 0));
}

class _NavigationBloc extends _Recorder<NavigationEvent, NavigationState>
    implements NavigationBloc {
  _NavigationBloc() : super(NavigationState.initial(false));
}

class _HistoryBloc extends _Recorder<HistoryEvent, HistoryState>
    implements HistoryBloc {
  _HistoryBloc() : super(HistoryInitial());
}

class _SettingsBloc extends _Recorder<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _SettingsBloc() : super(SettingsState.initial());
}

class _NotesBloc extends _Recorder<PersonalNotesEvent, PersonalNotesState>
    implements PersonalNotesBloc {
  _NotesBloc() : super(const PersonalNotesState.initial());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  testWidgets('קישור בתצוגה המקדימה פותח את הספר המקושר (issue #2020)', (
    tester,
  ) async {
    final book = TextBook(title: 'ספר בדיקה');
    final tabs = _TabsBloc();
    final navigation = _NavigationBloc();
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<SettingsBloc>(create: (_) => _SettingsBloc()),
          BlocProvider<PersonalNotesBloc>(create: (_) => _NotesBloc()),
          BlocProvider<TabsBloc>.value(value: tabs),
          BlocProvider<NavigationBloc>.value(value: navigation),
          BlocProvider<HistoryBloc>(create: (_) => _HistoryBloc()),
        ],
        child: MaterialApp(
          home: Scaffold(body: BookPreviewPanel(book: book)),
        ),
      ),
    );
    await tester.pump();

    final previewBloc = BlocProvider.of<TextBookBloc>(
      tester.element(
        find
            .descendant(
              of: find.byWidgetPredicate(
                (w) => w is BlocProvider<TextBookBloc>,
              ),
              matching: find.byWidgetPredicate((_) => true),
            )
            .last,
      ),
    );
    // הטעינה האמיתית נכשלת בלי ספרייה; ממתינים לה לפני הזרקת מצב טעון.
    for (var i = 0; i < 100; i++) {
      final state = previewBloc.state;
      if (state is! TextBookInitial && state is! TextBookLoading) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    // ignore: invalid_use_of_visible_for_testing_member
    previewBloc.emit(
      TextBookLoaded(
        book: book,
        showLeftPane: false,
        content: const ['שורה'],
        fontSize: 18,
        showSplitView: false,
        showPageShapeView: false,
        activeCommentators: const [],
        commentatorGroups: const [],
        availableCommentators: const [],
        links: const [],
        visibleLinks: const [],
        linksByLine: const {},
        tableOfContents: const [],
        removeNikud: false,
        visibleIndices: const [0],
        selectedIndex: null,
        pinLeftPane: false,
        searchText: '',
        scrollController: ItemScrollController(),
        positionsListener: ItemPositionsListener.create(),
      ),
    );
    await tester.pump();

    final target = TextBookTab(book: TextBook(title: 'יעד'), index: 3);
    addTearDown(target.dispose);
    tester
        .widget<CombinedView>(find.byType(CombinedView))
        .openBookCallback(
          target,
        );
    await tester.pump();

    expect(
      tabs.events.whereType<OpenOrFocusTab>().map((e) => e.tab),
      [same(target)],
    );
    expect(
      navigation.events.whereType<NavigateToScreen>().map((e) => e.screen),
      [Screen.reading],
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });
}
