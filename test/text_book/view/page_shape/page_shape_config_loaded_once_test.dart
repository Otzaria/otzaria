// הגדרות צורת הדף והקישורים נטענים פעם אחת, לא בכל שינוי MediaQuery.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/shared_preferences_cache.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/page_shape/page_shape_screen.dart';
import 'package:otzaria/text_book/view/page_shape/simple_text_viewer.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_settings_manager.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:otzaria/workspaces/bloc/workspace_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../test_helpers/stub_navigation_bloc.dart';
import '../../../test_helpers/stub_personal_notes_bloc.dart';
import '../../../test_helpers/stub_settings_bloc.dart';
import '../../../test_helpers/stub_tabs_bloc.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    final root = Directory.systemTemp.createTempSync('page-shape-once-');
    AppPaths.debugOverrideDataRootPath(root.path);
    addTearDown(() async {
      AppPaths.debugOverrideDataRootPath(null);
      await root.delete(recursive: true);
    });
    SharedPreferences.setMockInitialValues({});
    await Settings.init(cacheProvider: SharePreferenceCache());
  });

  testWidgets('רק שינוי הגדרות מפרשים שחל על הדף מרענן קישורים', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final book = TextBook(title: 'ספר בדיקה');
    final bloc = _RecordingBloc(
      TextBookLoaded(
        book: book,
        showLeftPane: false,
        content: const ['שורה א', 'שורה ב'],
        fontSize: 18,
        showSplitView: false,
        showPageShapeView: true,
        activeCommentators: const [],
        commentatorGroups: const [],
        availableCommentators: const [],
        commentatorsLoaded: true,
        links: const [],
        visibleLinks: const [],
        linksByLine: const {},
        tableOfContents: const [],
        visibleIndices: const [0],
        selectedIndex: 0,
        searchText: '',
      ),
    );
    final settings = StubSettingsBloc(
      SettingsState.initial().copyWith(textMaxWidth: 600),
    );
    final notes = StubPersonalNotesBloc(const PersonalNotesState.initial());
    final tab = TextBookTab(book: book, index: 0, blocOverride: bloc);
    final tabs = StubTabsBloc(TabsState(tabs: [tab], currentTabIndex: 0));
    final navigation = StubNavigationBloc(
      const NavigationState(currentScreen: Screen.reading),
    );
    final workspace = _WorkspaceBloc();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await bloc.close();
      await settings.close();
      await notes.close();
      await tabs.close();
      await navigation.close();
      await workspace.close();
      tab.dispose();
    });

    var defaultsCalls = 0;
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<TextBookBloc>.value(value: bloc),
          BlocProvider<SettingsBloc>.value(value: settings),
          BlocProvider<PersonalNotesBloc>.value(value: notes),
          BlocProvider<TabsBloc>.value(value: tabs),
          BlocProvider<NavigationBloc>.value(value: navigation),
          BlocProvider<WorkspaceBloc>.value(value: workspace),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: PageShapeScreen(
              openBookCallback: (_) {},
              tab: tab,
              defaultsLoader: (book, available) async {
                defaultsCalls++;
                return (
                  commentators: <String, String?>{},
                  visibility: <String, bool>{},
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(defaultsCalls, 1);
    final refreshesAfterLoad = bloc.refreshCount;
    expect(refreshesAfterLoad, 1);

    for (var i = 0; i < 15; i++) {
      tester.view.physicalSize = Size(2400 - i * 40.0, 1200);
      await tester.pump();
      await tester.pump();
    }

    expect(defaultsCalls, 1);
    expect(bloc.refreshCount, refreshesAfterLoad);

    final mainText = find.byType(SimpleTextViewer);
    expect(tester.getSize(mainText).width, greaterThan(600));
    await PageShapeSettingsManager.saveApplyTextMaxWidth(true);
    await tester.pumpAndSettle();
    expect(tester.getSize(mainText).width, lessThanOrEqualTo(600));
    expect(defaultsCalls, 1);
    expect(bloc.refreshCount, refreshesAfterLoad);

    await PageShapeSettingsManager.saveConfiguration('ספר אחר', {});
    await tester.pumpAndSettle();
    expect(defaultsCalls, 1);
    expect(bloc.refreshCount, refreshesAfterLoad);

    expect(find.text('בחר מפרש'), findsNWidgets(2));
    await PageShapeSettingsManager.saveConfiguration(
      book.title,
      {},
      columnVisibility: {'left': false},
    );
    await tester.pumpAndSettle();
    expect(find.text('בחר מפרש'), findsOneWidget);
    expect(bloc.refreshCount, refreshesAfterLoad + 1);

    await PageShapeSettingsManager.resetBookCommentatorConfig(book.title);
    await tester.pumpAndSettle();
    expect(find.text('בחר מפרש'), findsNWidgets(2));
    expect(defaultsCalls, 2);
    expect(bloc.refreshCount, refreshesAfterLoad + 2);

    await PageShapeSettingsManager.saveConfiguration(
      book.title,
      {},
      saveToWorkspaceId: 'ws-2',
      columnVisibility: {'right': false},
    );
    await tester.pumpAndSettle();
    expect(find.text('בחר מפרש'), findsNWidgets(2));
    expect(bloc.refreshCount, refreshesAfterLoad + 2);

    workspace.activate('ws-2');
    await tester.pumpAndSettle();
    expect(find.text('בחר מפרש'), findsOneWidget);
    expect(bloc.refreshCount, refreshesAfterLoad + 3);
  });
}

class _WorkspaceBloc extends Cubit<WorkspaceState> implements WorkspaceBloc {
  _WorkspaceBloc() : super(const WorkspaceState(workspaces: []));

  void activate(String id) => emit(state.copyWith(activeWorkspaceId: id));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  int refreshCount = 0;

  _RecordingBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {
      if (event is RefreshLinksForCurrentWindow) refreshCount++;
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
