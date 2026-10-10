// הסרגל העליון של לוח השנה עטוף כולו ב-OverlayPortal (דיאלוג "מעבר לתאריך").
// tooltip של כפתור בסרגל שאין לו צומת סמנטיקה משלו מתמזג לצומת של עוגן
// ה-OverlayPortal, עוגן הבלון נשמט, ובריחוף הבלון נשלח למערכת ההפעלה בלי אב —
// Windows דוחה את עדכון עץ הנגישות והעץ קופא.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/widgets/calendar_side_panel.dart';
import 'package:otzaria/tools/calendar/widgets/calendar_top_bar.dart';
import 'package:timezone/data/latest.dart' as tz_data;

import '../../../helpers/semantics_update_recorder.dart';
import '../../../test_helpers/memory_cache_provider.dart';

void main() {
  // ה-binding המקליט חייב להיווצר לפני כל binding אחר בקובץ.
  SemanticsRecordingBinding.ensure();
  final recorder = SemanticsRecordingBinding.recorder;

  setUpAll(() async {
    tz_data.initializeTimeZones();
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  late SettingsBloc settingsBloc;

  setUp(() {
    recorder.reset();
    settingsBloc = SettingsBloc(repository: SettingsRepository())
      ..add(LoadSettings());
  });

  tearDown(() async {
    await settingsBloc.close();
  });

  Future<void> pumpTopBar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: settingsBloc,
          child: Scaffold(
            body: CalendarTopBar(
              state: CalendarState.initial().copyWith(
                googleCalendarEnabled: true,
                googleCalendarConnected: true,
              ),
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
              isJumpToDateSearchOpen: false,
              onToggleJumpToDateSearch: () {},
              onCloseJumpToDateSearch: () {},
              parseInputDate: (_) => null,
              onJumpToDateSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  const tooltips = [
    'קודם',
    'הבא',
    'מעבר לתאריך',
    'הדפסה',
    'זמנים',
    'אירועים',
    'הגדרות לוח שנה',
    'Google Calendar מחובר',
  ];

  for (final tooltip in tooltips) {
    testWidgets(
      'ריחוף על "$tooltip" בסרגל לוח השנה אינו שולח צומת נגישות יתום '
      '(issue #1915)',
      (tester) async {
        final handle = tester.ensureSemantics();
        await pumpTopBar(tester);

        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        await mouse.moveTo(tester.getCenter(find.byTooltip(tooltip)));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.text(tooltip), findsOneWidget, reason: 'הבלון נפתח');

        // גם סגירת הבלון (יציאת העכבר) עוברת בלי עדכון פגום.
        await mouse.moveTo(Offset.zero);
        await tester.pumpAndSettle();

        expect(
          recorder.violations,
          isEmpty,
          reason: 'הבלון "$tooltip" חייב להישלח למנוע עם אב בסדר המעבר',
        );
        expect(
          tester.getSemantics(find.byTooltip(tooltip)),
          isSemantics(tooltip: tooltip),
          reason: 'ה-tooltip מוכרז על צומת הכפתור עצמו',
        );
        handle.dispose();
      },
    );
  }
}
