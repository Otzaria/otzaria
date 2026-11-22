import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/view/reading_tabs_side_panel.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:otzaria/workspaces/bloc/workspace_state.dart';

import '../helpers/memory_settings_cache.dart';
import '../test_helpers/stub_settings_bloc.dart';
import '../test_helpers/stub_tabs_bloc.dart';

class _HistoryBloc extends Cubit<HistoryState> implements HistoryBloc {
  _HistoryBloc() : super(HistoryInitial());

  @override
  void add(HistoryEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _WorkspaceBloc extends Cubit<WorkspaceState> implements WorkspaceBloc {
  _WorkspaceBloc() : super(WorkspaceState.initial());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  // רוחב שמור שמתחת למזערי (קובץ הגדרות ישן או פגום) אינו מצמצם את העמודה
  // מתחת למזערי: במגע (ערכת הנושא ברירת המחדל של flutter test) ידית שינוי
  // הרוחב תופסת 32, ושורת הכפתורים של הכותרת צריכה את היתר.
  testWidgets('רוחב שמור מתחת למזערי: העמודה לא צרה מהמזערי ואין overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final tab = PdfBookTab(
      book: PdfBook(title: 'ספר א', path: '/tmp/a.pdf'),
      pageNumber: 1,
    );
    addTearDown(tab.dispose);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<TabsBloc>.value(
            value: StubTabsBloc(TabsState(tabs: [tab], currentTabIndex: 0)),
          ),
          BlocProvider<SettingsBloc>.value(
            value: StubSettingsBloc(
              SettingsState.initial().copyWith(
                readingTabsPlacement:
                    SettingsRepository.readingTabsPlacementSide,
                readingTabsColumnWidth: 120,
              ),
            ),
          ),
          BlocProvider<HistoryBloc>.value(value: _HistoryBloc()),
          BlocProvider<WorkspaceBloc>.value(value: _WorkspaceBloc()),
        ],
        child: MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: ReadingTabsSidePanel(
                show: true,
                child: const SizedBox.expand(key: ValueKey('content')),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final content = tester.getSize(find.byKey(const ValueKey('content'))).width;
    expect(
      900 - content,
      SettingsRepository.minReadingTabsColumnWidth,
      reason: 'העמודה לפחות ברוחב המזערי',
    );
  });
}
