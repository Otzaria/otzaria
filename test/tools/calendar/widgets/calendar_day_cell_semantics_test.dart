// תא יום בלוח השנה חשוף לקורא מסך ככפתור עם תאריך מלא
// ועם מצב "נבחר", ולא כאזור ללא שם.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/helpers/calendar_date_helpers.dart';
import 'package:otzaria/tools/calendar/widgets/calendar_day_cell.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../../../test_helpers/memory_cache_provider.dart';
import '../support/calendar_cubit_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Jerusalem'));
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  final date = DateTime(2026, 3, 12);
  late CalendarCubit cubit;

  setUp(() {
    cubit = CalendarCubit(
      notificationService: FakeNotificationService(),
      googleCalendarService: FakeGoogleCalendarService(),
    );
  });

  tearDown(() => cubit.close());

  Future<void> pumpCell(
    WidgetTester tester, {
    required bool selected,
    required VoidCallback onTap,
  }) async {
    final jewish = JewishDate.fromDateTime(date);
    final state = CalendarState.initial().copyWith(
      selectedJewishDate: selected
          ? jewish
          : JewishDate.fromDateTime(DateTime(2020)),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: cubit,
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SizedBox(
                width: 120,
                height: 100,
                child: Builder(
                  builder: (context) => buildDayCell(
                    context,
                    state,
                    date,
                    jewish,
                    false,
                    onTap,
                    () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder cell() => find.bySemanticsLabel(formatEventDate(date));

  testWidgets('תא יום: כפתור עם תאריך עברי ולועזי, לא נבחר', (tester) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await pumpCell(tester, selected: false, onTap: () => taps++);

    final node = tester.getSemantics(cell());
    expect(node, isSemantics(isButton: true, isSelected: false));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    tester.semantics.tap(find.semantics.byLabel(formatEventDate(date)));
    expect(taps, 1);
    handle.dispose();
  });

  testWidgets('תא היום הנבחר מוכרז כנבחר', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpCell(tester, selected: true, onTap: () {});

    expect(
      tester.getSemantics(cell()),
      isSemantics(isButton: true, isSelected: true),
    );
    handle.dispose();
  });
}
