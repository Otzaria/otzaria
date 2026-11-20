// פריסת תא יום בלוח השנה: אזור האירועים מקבל את כל הגובה שנשאר מתחת לשורת
// המספרים (לא חצי ממנו), והמספר הראשי נשאר בקצה גם כשאין מספר לועזי לצדו.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
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

  Future<void> pumpCell(WidgetTester tester, CalendarType type) async {
    final jewish = JewishDate.fromDateTime(date);
    final state = CalendarState.initial().copyWith(
      calendarType: type,
      selectedJewishDate: JewishDate.fromDateTime(DateTime(2020)),
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
                    () {},
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

  testWidgets('אזור האירועים ממלא את כל הגובה שמתחת לשורת המספרים', (
    tester,
  ) async {
    await pumpCell(tester, CalendarType.combined);

    final column = tester.getRect(find.byType(Column).first);
    final numbers = tester.getRect(find.byType(FittedBox).first);
    final extras = tester.getRect(find.byType(Expanded).first);

    expect(
      extras.bottom,
      closeTo(column.bottom, 0.5),
      reason: 'האירועים מגיעים עד תחתית התא ולא נעצרים באמצע',
    );
    expect(extras.top, closeTo(numbers.bottom + 6, 0.5));
  });

  testWidgets('בלוח עברי בלבד המספר הראשי נשאר בקצה הסופי של השורה', (
    tester,
  ) async {
    await pumpCell(tester, CalendarType.hebrew);

    final numbers = tester.getRect(find.byType(FittedBox).first);
    final day = tester.getRect(
      find.descendant(
        of: find.byType(FittedBox).first,
        matching: find.byType(Text),
      ),
    );

    // שורת המספרים כפויה LTR (העברי תמיד בימין התא), ולכן הקצה הסופי הוא
    // הימני, כמו Spacer לפני המספר בגרסה הקודמת.
    expect(day.right, closeTo(numbers.right, 0.5));
  });
}
