import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/services/google_calendar_service.dart';
import 'package:otzaria/tools/calendar/services/notification_service.dart';
import 'package:otzaria/tools/calendar/widgets/calendar_main_panel.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../../test_helpers/memory_cache_provider.dart';

class _FakeNotifications implements NotificationService {
  @override
  bool get isInitialized => false;
  @override
  Future<void> init() async {}
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeGoogle extends GoogleCalendarService {
  @override
  Future<bool> isSignedIn() async => false;
  @override
  Future<void> signOut() async {}
  @override
  Future<GoogleCalendarApiClient?> getApiClient({
    bool interactive = false,
  }) async => null;
}

/// Records the dates the week view renders.
class _RecordingCubit extends CalendarCubit {
  _RecordingCubit()
    : super(
        notificationService: _FakeNotifications(),
        googleCalendarService: _FakeGoogle(),
      );
  final shown = <DateTime>[];
  @override
  Map<String, String> shortTimesFor(DateTime date) {
    shown.add(date);
    return const {};
  }
}

/// The first day in 2026–2027 whose local length is [hours] (23 or 25),
/// or null when the machine's time zone has no DST.
DateTime? _localDayLasting(int hours) {
  for (var d = DateTime(2026); d.year < 2028; d = _plusDays(d, 1)) {
    if (_plusDays(d, 1).difference(d).inHours == hours) return d;
  }
  return null;
}

DateTime _plusDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();

  // הבאג תלוי באזור הזמן של המחשב; ב-UTC אין ימי מעבר שעון.
  final longDay = _localDayLasting(25);
  final shortDay = _localDayLasting(23);
  final noDst = longDay == null || shortDay == null
      ? 'local time zone has no DST (run with e.g. TZ=Asia/Jerusalem)'
      : null;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  group('Calendar navigation across a DST change', skip: noDst, () {
    late CalendarCubit cubit;
    setUp(() {
      cubit = CalendarCubit(
        notificationService: _FakeNotifications(),
        googleCalendarService: _FakeGoogle(),
      );
    });
    tearDown(() => cubit.close());

    test('next day leaves the 25-hour day', () {
      cubit.jumpToDate(longDay!);
      cubit.navigateToNextDay();
      expect(cubit.state.selectedGregorianDate, _plusDays(longDay, 1));
    });

    test('next week from the 25-hour day lands seven days later', () {
      cubit.jumpToDate(longDay!);
      cubit.changeCalendarView(CalendarView.week);
      cubit.next();
      expect(cubit.state.selectedGregorianDate, _plusDays(longDay, 7));
    });

    test('previous day does not skip the 23-hour day', () {
      cubit.jumpToDate(_plusDays(shortDay!, 1));
      cubit.changeCalendarView(CalendarView.day);
      cubit.previous();
      expect(cubit.state.selectedGregorianDate, shortDay);
    });
  });

  test('"today" advances after sunset on the 25-hour day', skip: noDst, () {
    final jerusalem = tz.getLocation('Asia/Jerusalem');
    final today = resolveCalendarDayForTransition(
      now: tz.TZDateTime(
        jerusalem,
        longDay!.year,
        longDay.month,
        longDay.day,
        21,
      ),
      city: 'ירושלים',
      transition: CalendarDayTransition.sunset,
    );
    expect(today, _plusDays(longDay, 1));
  });

  group('Week view across a DST change', skip: noDst, () {
    Future<List<DateTime>> shownWeek(WidgetTester tester, DateTime day) async {
      final cubit = _RecordingCubit()
        ..jumpToDate(day)
        ..changeCalendarView(CalendarView.week);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlocProvider<CalendarCubit>.value(
              value: cubit,
              child: CalendarMainPanel(
                state: cubit.state,
                onCreateEvent: ({existingEvent, specificDate}) {},
              ),
            ),
          ),
        ),
      );
      await cubit.close();
      return cubit.shown;
    }

    List<DateTime> weekOf(DateTime d) =>
        List.generate(7, (i) => _plusDays(d, i - d.weekday % 7));

    testWidgets('week with the 25-hour day shows seven distinct days', (
      tester,
    ) async {
      expect(await shownWeek(tester, longDay!), weekOf(longDay));
    });

    testWidgets('day after the 23-hour day shows its own week', (
      tester,
    ) async {
      final day = _plusDays(shortDay!, 1);
      expect(await shownWeek(tester, day), weekOf(day));
    });
  });
}
