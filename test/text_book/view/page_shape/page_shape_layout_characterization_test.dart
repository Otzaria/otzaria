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
import 'package:otzaria/widgets/layout/resizable_drag_handle.dart';

import '../../../test_helpers/memory_cache_provider.dart';

/// Characterization of the page-shape layout before splitting its build
/// (DD-30): the rects of the main text, the empty side columns and
/// their drag handles must not move.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const bookTitle = 'ספר בדיקה';
  const windowWidth = 1366.0;

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    await Settings.setValue<String>(
      'page_shape_book_$bookTitle',
      'left|null||right|null||bottom|null||bottomRight|null',
    );
    await Settings.setValue<bool>('page_shape_global_visibility_left', true);
    await Settings.setValue<bool>('page_shape_global_visibility_right', true);
    await Settings.setValue<bool>('page_shape_global_visibility_bottom', false);
    // רוחב שנגרר כשהחלון היה פנוי — בתוך מגבלת 40% מרוחב החלון.
    await Settings.setValue<double>('page_shape_left_width', 300);
    await Settings.setValue<double>('page_shape_right_width', 300);
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    required double sidePanesWidth,
    double textMaxWidth = 0,
    double width = windowWidth,
  }) async {
    await Settings.setValue<bool>(
      'page_shape_apply_text_max_width',
      textMaxWidth != 0,
    );
    tester.view.physicalSize = Size(width, 736);
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
          body: Row(
            children: [
              SizedBox(width: sidePanesWidth),
              Expanded(
                child: MultiBlocProvider(
                  providers: [
                    BlocProvider<TextBookBloc>.value(value: textBookBloc),
                    BlocProvider<PersonalNotesBloc>.value(
                      value: personalNotesBloc,
                    ),
                    BlocProvider<SettingsBloc>.value(value: settingsBloc),
                    BlocProvider<NavigationBloc>.value(value: navigationBloc),
                    BlocProvider<TabsBloc>.value(value: tabsBloc),
                  ],
                  child: PageShapeScreen(openBookCallback: (_) {}, tab: tab),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  String rects(WidgetTester tester) {
    String r(Rect rect) => [
      rect.left,
      rect.top,
      rect.width,
      rect.height,
    ].map((v) => v.toStringAsFixed(1)).join(',');
    return [
      'main ${r(tester.getRect(find.byType(SimpleTextViewer)))}',
      for (final e in find.text('בחר מפרש').evaluate())
        'empty ${r(tester.getRect(find.byWidget(e.widget)))}',
      for (final e in find.byType(ResizableDragHandle).evaluate())
        'handle ${r(tester.getRect(find.byWidget(e.widget)))}',
    ].join(' | ');
  }

  for (final (width, side) in [(1366.0, 0.0), (1366.0, 400.0), (900.0, 0.0)]) {
    testWidgets('page-shape layout is stable at $width with $side side panes', (
      tester,
    ) async {
      await pumpScreen(tester, sidePanesWidth: side, width: width);
      expect(tester.takeException(), isNull);
      expect(rects(tester), _expected['$width/$side'], reason: rects(tester));
    });
  }
}

const _expected = <String, String>{
  '1366.0/0.0':
      'main 293.9,0.0,778.1,736.0 | empty 95.6,328.0,112.8,20.0 | '
      'empty 1175.6,328.0,112.8,20.0 | handle 285.9,0.0,24.0,736.0 | '
      'handle 1072.1,0.0,24.0,736.0',
  '1366.0/400.0':
      'main 606.1,0.0,553.8,736.0 | empty 451.6,328.0,112.8,20.0 | '
      'empty 1219.6,328.0,112.8,20.0 | handle 598.1,0.0,24.0,736.0 | '
      'handle 1159.9,0.0,24.0,736.0',
  '900.0/0.0':
      'main 286.7,0.0,326.7,736.0 | empty 91.9,328.0,112.8,20.0 | '
      'empty 713.3,328.0,112.8,20.0 | handle 278.7,0.0,24.0,736.0 | '
      'handle 613.3,0.0,24.0,736.0',
};

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
