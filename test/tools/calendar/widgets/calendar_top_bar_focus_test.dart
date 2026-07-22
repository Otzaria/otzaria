// טסטים לפוקוס של דיאלוג "מעבר לתאריך" בסרגל העליון:
// הוא צריך להיסגר רק במעבר אמיתי לרקע (paused), ולא כשהחלון מאבד פוקוס
// ל-OS (inactive/hidden) — כמו כל דיאלוג.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/tools/calendar/utils/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/widgets/calendar_side_panel.dart';
import 'package:otzaria/tools/calendar/widgets/calendar_top_bar.dart';

import '../../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  late SettingsBloc settingsBloc;

  setUp(() {
    settingsBloc = SettingsBloc(repository: SettingsRepository())
      ..add(LoadSettings());
  });

  tearDown(() async {
    await settingsBloc.close();
  });

  Future<int> pumpAndDispatch(
    WidgetTester tester, {
    required List<AppLifecycleState> states,
  }) async {
    int closeCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: settingsBloc,
          child: Scaffold(
            body: CalendarTopBar(
              state: CalendarState.initial(),
              onJumpToToday: () {},
              onPreviousPeriod: () {},
              onNextPeriod: () {},
              onViewChanged: (_) {},
              activeSidePanelView: CalendarSidePanelView.events,
              isSidePanelVisible: false,
              isSettingsPanelOpen: false,
              onToggleTimesPanel: () {},
              onToggleEventsPanel: () {},
              onToggleSettingsPanel: () {},
              onPrint: () {},
              onToggleSidebar: () {},
              isJumpToDateSearchOpen: true,
              onToggleJumpToDateSearch: () {},
              onCloseJumpToDateSearch: () => closeCount++,
              parseInputDate: (_) => null,
              onJumpToDateSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    for (final state in states) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
    }
    return closeCount;
  }

  testWidgets('נשאר פתוח כשהאפליקציה מאבדת פוקוס OS (inactive/hidden)',
      (tester) async {
    final closeCount = await pumpAndDispatch(
      tester,
      states: [AppLifecycleState.inactive, AppLifecycleState.hidden],
    );
    expect(closeCount, 0);
  });

  testWidgets('נסגר רק במעבר אמיתי לרקע (paused)', (tester) async {
    // מעבר תקין דורש שרשור: resumed → inactive → hidden → paused.
    final closeCount = await pumpAndDispatch(
      tester,
      states: [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ],
    );
    // רק paused סוגר — inactive/hidden שקדמו לו לא.
    expect(closeCount, 1);
  });
}
