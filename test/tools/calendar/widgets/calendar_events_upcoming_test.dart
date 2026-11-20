// תצוגת "אירועים קרובים" בפאנל האירועים, נפרדת מ"הצג הכל" (issue #4713).

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/tools/calendar/services/google_calendar_service.dart';
import 'package:otzaria/tools/calendar/services/notification_service.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/helpers/calendar_date_helpers.dart';
import 'package:otzaria/tools/calendar/widgets/calendar_events_panel.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../../test_helpers/memory_cache_provider.dart';

class _FakeNotificationService implements NotificationService {
  @override
  bool get isInitialized => true;

  @override
  Future<void> cancelNotifications(Iterable<int> ids) async {}

  @override
  Future<bool> checkPermissions() async => false;

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeGoogleCalendarService extends GoogleCalendarService {
  @override
  Future<bool> isSignedIn() async => false;

  @override
  Future<void> signOut() async {}

  @override
  Future<GoogleCalendarApiClient?> getApiClient({
    bool interactive = false,
  }) async => null;
}

class _InMemorySettingsRepository implements SettingsRepository {
  @override
  Future<void> updateCalendarEvents(String json) async {}

  @override
  Future<Map<String, dynamic>> loadSettings() async {
    return {
      'calendarType': 'combined',
      'selectedCity': 'ירושלים',
      'calendarEvents': '[]',
      'calendarNotificationsEnabled': false,
      'calendarNotificationTime': 60,
      'calendarNotificationSound': false,
      'calendarZmanAlerts': '{}',
      'calendarEnabledZmanim': '',
      'calendarDayTransition': 'sunset',
      'googleCalendarEnabled': false,
      'googleCalendarSelectedIds': 'primary',
      'googleCalendarSyncPastDays': 60,
      'googleCalendarSyncFutureDays': 365,
      'googleCalendarLastSync': 0,
    };
  }

  @override
  String getCalendarEventNotificationIdsJson() => '[]';

  @override
  Future<void> updateCalendarEventNotificationIdsJson(String json) async {}

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

DateTime _dayOffset(int days) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day + days);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Jerusalem'));
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  late CalendarCubit cubit;

  setUp(() async {
    cubit = CalendarCubit(
      settingsRepository: _InMemorySettingsRepository(),
      notificationService: _FakeNotificationService(),
      googleCalendarService: _FakeGoogleCalendarService(),
    );
    await Future.delayed(const Duration(milliseconds: 100));
  });

  tearDown(() => cubit.close());

  Future<void> pumpEventsPanel(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: cubit,
          child: Scaffold(
            body: SizedBox(
              width: 600,
              height: 900,
              child: BlocBuilder<CalendarCubit, CalendarState>(
                builder: (context, state) => CalendarEventsPanel(
                  state: state,
                  onCreateEvent: ({existingEvent, specificDate}) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('upcoming events view separate from show-all (issue #4713)', () {
    testWidgets('אירוע חד-פעמי שעבר מוסתר בקרובים ומוצג בהכל', (tester) async {
      await cubit.addEvent(
        title: 'אירוע ישן',
        baseGregorianDate: _dayOffset(-400),
        recurrenceType: RecurrenceType.none,
      );
      await cubit.addEvent(
        title: 'אירוע עתידי',
        baseGregorianDate: _dayOffset(10),
        recurrenceType: RecurrenceType.none,
      );
      await pumpEventsPanel(tester);

      await tester.tap(find.text('קרובים'));
      await tester.pumpAndSettle();
      expect(cubit.state.eventsView, CalendarEventsView.upcoming);
      expect(find.text('אירוע ישן'), findsNothing);
      expect(find.text('אירוע עתידי'), findsOneWidget);

      await tester.tap(find.text('הכל'));
      await tester.pumpAndSettle();
      expect(find.text('אירוע ישן'), findsOneWidget);
      expect(find.text('אירוע עתידי'), findsOneWidget);
    });

    testWidgets('אין אירועים קרובים — הודעה מתאימה', (tester) async {
      await cubit.addEvent(
        title: 'אירוע ישן',
        baseGregorianDate: _dayOffset(-400),
        recurrenceType: RecurrenceType.none,
      );
      cubit.setEventsView(CalendarEventsView.upcoming);
      await pumpEventsPanel(tester);
      expect(find.text('אין אירועים קרובים'), findsOneWidget);
    });

    testWidgets('אירוע שנתי עברי מלפני 5 שנים מופיע פעם אחת במועדו הבא', (
      tester,
    ) async {
      // תאריך עברי שקיים בכל שנה (לא ל' בחודש ולא אדר ב').
      var base = _dayOffset(-5 * 365 + 20);
      while (JewishDate.fromDateTime(base).getJewishDayOfMonth() > 28 ||
          JewishDate.fromDateTime(base).getJewishMonth() >= 12) {
        base = DateTime(base.year, base.month, base.day + 1);
      }
      await cubit.addEvent(
        title: 'יארצייט',
        baseGregorianDate: base,
        recurrenceType: RecurrenceType.annualHebrew,
      );
      final today = cubit.state.todayGregorianDate;
      final event = cubit.state.events.single;
      final next = event.nextOccurrenceFrom(today);
      expect(next.isBefore(today), isFalse);

      cubit.setEventsView(CalendarEventsView.upcoming);
      await pumpEventsPanel(tester);

      expect(find.text('יארצייט'), findsOneWidget);
      // השורה מציגה את תאריך המופע הקרוב, לא את תאריך הבסיס.
      expect(find.text(formatEventDate(next)), findsOneWidget);
      expect(find.text(formatEventDate(base)), findsNothing);
    });

    testWidgets('אירוע חוזר שחזרתו הסתיימה בשנה שעברה מוסתר', (tester) async {
      await cubit.addEvent(
        title: 'שבועי שהסתיים',
        baseGregorianDate: _dayOffset(-700),
        recurrenceType: RecurrenceType.weekly,
        recurrenceEndDate: _dayOffset(-300),
      );
      await cubit.addEvent(
        title: 'שנתי שהסתיים',
        baseGregorianDate: _dayOffset(-4 * 365 - 30),
        recurrenceType: RecurrenceType.annualGregorian,
        recurringYears: 2,
      );
      cubit.setEventsView(CalendarEventsView.upcoming);
      await pumpEventsPanel(tester);

      expect(find.text('שבועי שהסתיים'), findsNothing);
      expect(find.text('שנתי שהסתיים'), findsNothing);
      expect(find.text('אין אירועים קרובים'), findsOneWidget);
    });

    testWidgets('אירוע רב-יומי שמתקיים היום נכלל', (tester) async {
      await cubit.addEvent(
        title: 'כנס',
        baseGregorianDate: _dayOffset(-2),
        endGregorianDate: _dayOffset(2),
        recurrenceType: RecurrenceType.none,
      );
      cubit.setEventsView(CalendarEventsView.upcoming);
      await pumpEventsPanel(tester);
      expect(find.text('כנס'), findsOneWidget);
    });

    testWidgets('לחיצה על שורה בקרובים עוברת לתאריך שמוצג בה', (tester) async {
      final next = _dayOffset(5);
      await cubit.addEvent(
        title: 'שנתי',
        baseGregorianDate: DateTime(next.year - 2, next.month, next.day),
        recurrenceType: RecurrenceType.annualGregorian,
      );
      // היום הנבחר רחוק מהיום: המופע הבא ממנו אינו המופע שבשורה.
      cubit.jumpToDate(DateTime(next.year + 3, next.month, next.day - 10));
      cubit.setEventsView(CalendarEventsView.upcoming);
      await pumpEventsPanel(tester);

      await tester.tap(find.text('שנתי'));
      await tester.pumpAndSettle();
      expect(cubit.state.selectedGregorianDate, next);
    });

    test('סדר לפי המופע הקרוב ואז לפי שעה', () async {
      await cubit.addEvent(
        title: 'בעוד חודש',
        baseGregorianDate: _dayOffset(30),
        recurrenceType: RecurrenceType.none,
      );
      // אירוע שנתי שהתחיל לפני שנתיים ומועדו הבא בעוד 5 ימים.
      final annualBase = _dayOffset(5);
      await cubit.addEvent(
        title: 'שנתי',
        baseGregorianDate: DateTime(
          annualBase.year - 2,
          annualBase.month,
          annualBase.day,
        ),
        recurrenceType: RecurrenceType.annualGregorian,
      );
      await cubit.addEvent(
        title: 'מחר בערב',
        baseGregorianDate: _dayOffset(1),
        recurrenceType: RecurrenceType.none,
        eventTime: const TimeOfDay(hour: 20, minute: 0),
      );
      await cubit.addEvent(
        title: 'מחר בבוקר',
        baseGregorianDate: _dayOffset(1),
        recurrenceType: RecurrenceType.none,
        eventTime: const TimeOfDay(hour: 8, minute: 0),
      );

      final upcoming = cubit.upcomingEvents();
      expect(upcoming.map((e) => e.event.title), [
        'מחר בבוקר',
        'מחר בערב',
        'שנתי',
        'בעוד חודש',
      ]);
      expect(upcoming[2].date, annualBase);
    });
  });
}
