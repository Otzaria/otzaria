// "מעבר לתאריך" בסרגל העליון: הפופאפ הוא משטח צף מהקטלוג (FloatingPanel),
// ומקשי החיצים בו עוקבים אחרי כיוון הכתיבה, כמו רשת הלוח הראשית.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/widgets/calendar_date_picker_panel.dart';
import 'package:otzaria/tools/calendar/widgets/calendar_side_panel.dart';
import 'package:otzaria/tools/calendar/widgets/calendar_top_bar.dart';
import 'package:otzaria/widgets/layout/floating_panel.dart';
import 'package:timezone/data/latest.dart' as tz_data;

import '../../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    tz_data.initializeTimeZones();
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  late SettingsBloc settingsBloc;
  setUp(() {
    settingsBloc = SettingsBloc(repository: SettingsRepository())
      ..add(LoadSettings());
  });
  tearDown(() async => settingsBloc.close());

  final start = DateTime(2026, 11, 17);
  int closes = 0;
  final jumped = <DateTime>[];

  Future<void> pumpBar(
    WidgetTester tester, {
    required bool open,
    TextDirection direction = TextDirection.rtl,
  }) async {
    tester.view.physicalSize = const Size(1100, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            Directionality(textDirection: direction, child: child!),
        home: BlocProvider.value(
          value: settingsBloc,
          child: Scaffold(
            body: CalendarTopBar(
              state: CalendarState.initial().copyWith(
                selectedGregorianDate: start,
                calendarType: CalendarType.gregorian,
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
              isJumpToDateSearchOpen: open,
              onToggleJumpToDateSearch: () {},
              onCloseJumpToDateSearch: () => closes++,
              parseInputDate: (_) => null,
              onJumpToDateSelected: jumped.add,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> openAndFocusPopup(
    WidgetTester tester, {
    TextDirection direction = TextDirection.rtl,
  }) async {
    closes = 0;
    jumped.clear();
    await pumpBar(tester, open: false, direction: direction);
    await pumpBar(tester, open: true, direction: direction);
    await tester.pump(const Duration(milliseconds: 300));
    // חץ למטה בשדה מעביר את הפוקוס לפופאפ.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
  }

  DateTime pickerDate(WidgetTester tester) => tester
      .widget<CalendarDatePickerPanel>(
        find.byType(CalendarDatePickerPanel),
      )
      .selectedDate;

  testWidgets('הפופאפ מצויר על FloatingPanel של הקטלוג', (tester) async {
    await openAndFocusPopup(tester);
    expect(
      find.descendant(
        of: find.byType(FloatingPanel),
        matching: find.byType(CalendarDatePickerPanel),
      ),
      findsOneWidget,
    );
  });

  testWidgets('הפופאפ קטן: לא רחב מ-340 ולא גבוה מ-410', (tester) async {
    await openAndFocusPopup(tester);
    final size = tester.getSize(find.byType(FloatingPanel));
    expect(size.width, lessThanOrEqualTo(340));
    expect(size.height, lessThanOrEqualTo(410));
  });

  testWidgets('RTL: חץ שמאלה מקדם יום וחץ ימינה מחזיר, כמו רשת הלוח', (
    tester,
  ) async {
    await openAndFocusPopup(tester);
    expect(pickerDate(tester), start);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(pickerDate(tester), start.add(const Duration(days: 1)));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(pickerDate(tester), start.subtract(const Duration(days: 1)));
  });

  testWidgets('LTR: חץ ימינה מקדם יום', (tester) async {
    await openAndFocusPopup(tester, direction: TextDirection.ltr);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(pickerDate(tester), start.add(const Duration(days: 1)));
  });

  testWidgets('חץ למעלה ולמטה זזים שבוע', (tester) async {
    await openAndFocusPopup(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(pickerDate(tester), start.add(const Duration(days: 7)));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(pickerDate(tester), start);
  });

  testWidgets('Escape סוגר ו-Enter מאשר את התאריך הנבחר', (tester) async {
    await openAndFocusPopup(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(jumped, [start]);
    expect(closes, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(closes, 2);
  });
}
