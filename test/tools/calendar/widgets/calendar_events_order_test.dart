// סדר התצוגה של אירועי המשתמש — בפאנל האירועים ובתא היום שבלוח.
// האירועים חייבים להופיע לפי שעה, לא לפי סדר א-ב של הכותרת.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/tools/calendar/services/google_calendar_service.dart';
import 'package:otzaria/tools/calendar/services/notification_service.dart';
import 'package:otzaria/tools/calendar/utils/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/widgets/calendar_day_cell.dart';
import 'package:otzaria/tools/calendar/widgets/calendar_events_panel.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../../test_helpers/memory_cache_provider.dart';

final _date = DateTime(2026, 8, 3);

class _FakeNotificationService implements NotificationService {
  @override
  bool get isInitialized => true;

  @override
  Future<void> cancelNotification(int id) async {}

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

/// סדר ההופעה האנכי של כותרות נתונות במסך — לפי מיקום ה-Text בפועל.
List<String> _verticalOrder(WidgetTester tester, List<String> titles) {
  final located =
      titles
          .map((t) => (title: t, dy: tester.getTopLeft(find.text(t)).dy))
          .toList()
        ..sort((a, b) => a.dy.compareTo(b.dy));
  return located.map((e) => e.title).toList();
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

  group('CalendarEventsPanel — תצוגת יום נבחר', () {
    testWidgets('אירועים מוצגים לפי שעה ולא לפי א-ב', (tester) async {
      cubit.selectDate(JewishDate.fromDateTime(_date), _date);
      await cubit.addEvent(
        title: 'אירוע ערב',
        baseGregorianDate: _date,
        recurrenceType: RecurrenceType.none,
        eventTime: const TimeOfDay(hour: 21, minute: 0),
      );
      await cubit.addEvent(
        title: 'שיעור צהריים',
        baseGregorianDate: _date,
        recurrenceType: RecurrenceType.none,
        eventTime: const TimeOfDay(hour: 14, minute: 0),
      );

      await pumpEventsPanel(tester);

      expect(_verticalOrder(tester, ['אירוע ערב', 'שיעור צהריים']), [
        'שיעור צהריים',
        'אירוע ערב',
      ]);
      expect(find.text('14:00'), findsOneWidget);
      expect(find.text('21:00'), findsOneWidget);
    });

    testWidgets('אירוע ללא שעה מוצג ראשון, עם תווית "כל היום"', (tester) async {
      cubit.selectDate(JewishDate.fromDateTime(_date), _date);
      await cubit.addEvent(
        title: 'תענית',
        baseGregorianDate: _date,
        recurrenceType: RecurrenceType.none,
      );
      await cubit.addEvent(
        title: 'אאא בבוקר',
        baseGregorianDate: _date,
        recurrenceType: RecurrenceType.none,
        eventTime: const TimeOfDay(hour: 7, minute: 30),
      );

      await pumpEventsPanel(tester);

      expect(_verticalOrder(tester, ['תענית', 'אאא בבוקר']), [
        'תענית',
        'אאא בבוקר',
      ]);
      expect(find.text('כל היום'), findsOneWidget);
      expect(find.text('07:30'), findsOneWidget);
    });

    testWidgets('אין אירועים ביום זה — הודעה מתאימה', (tester) async {
      cubit.selectDate(JewishDate.fromDateTime(_date), _date);
      await pumpEventsPanel(tester);
      expect(find.text('אין אירועים ביום זה'), findsOneWidget);
    });
  });

  group('CalendarEventsPanel — תצוגת "הצג הכל"', () {
    testWidgets('כל האירועים מוצגים לפי תאריך ואז לפי שעה', (tester) async {
      await cubit.addEvent(
        title: 'מחר בבוקר',
        baseGregorianDate: DateTime(2026, 8, 4),
        recurrenceType: RecurrenceType.none,
        eventTime: const TimeOfDay(hour: 6, minute: 0),
      );
      await cubit.addEvent(
        title: 'היום בערב',
        baseGregorianDate: _date,
        recurrenceType: RecurrenceType.none,
        eventTime: const TimeOfDay(hour: 22, minute: 0),
      );
      await cubit.addEvent(
        title: 'היום בבוקר',
        baseGregorianDate: _date,
        recurrenceType: RecurrenceType.none,
        eventTime: const TimeOfDay(hour: 8, minute: 0),
      );
      cubit.toggleShowAllEvents(true);

      await pumpEventsPanel(tester);

      expect(
        _verticalOrder(tester, ['מחר בבוקר', 'היום בערב', 'היום בבוקר']),
        ['היום בבוקר', 'היום בערב', 'מחר בבוקר'],
      );
    });
  });

  group('CalendarEventsPanel — חיפוש', () {
    testWidgets('תוצאות החיפוש מוצגות כרונולוגית', (tester) async {
      await cubit.addEvent(
        title: 'שיעור ב',
        baseGregorianDate: _date,
        recurrenceType: RecurrenceType.none,
        eventTime: const TimeOfDay(hour: 20, minute: 0),
      );
      await cubit.addEvent(
        title: 'שיעור א',
        baseGregorianDate: _date,
        recurrenceType: RecurrenceType.none,
        eventTime: const TimeOfDay(hour: 9, minute: 0),
      );
      cubit.setEventSearchQuery('שיעור');

      await pumpEventsPanel(tester);

      expect(_verticalOrder(tester, ['שיעור ב', 'שיעור א']), [
        'שיעור א',
        'שיעור ב',
      ]);
    });

    testWidgets('חיפוש בלי התאמות — הודעה מתאימה', (tester) async {
      await cubit.addEvent(
        title: 'שיעור',
        baseGregorianDate: _date,
        recurrenceType: RecurrenceType.none,
      );
      cubit.setEventSearchQuery('לא קיים');

      await pumpEventsPanel(tester);
      expect(find.text('לא נמצאו אירועים מתאימים'), findsOneWidget);
    });
  });

  group('DayExtras — אירועי תא היום', () {
    testWidgets('כשיש יותר אירועים מהמקום — מוצגים המוקדמים בזמן', (
      tester,
    ) async {
      await cubit.addEvent(
        title: 'אאא בערב',
        baseGregorianDate: _date,
        recurrenceType: RecurrenceType.none,
        eventTime: const TimeOfDay(hour: 22, minute: 0),
      );
      await cubit.addEvent(
        title: 'ששש בבוקר',
        baseGregorianDate: _date,
        recurrenceType: RecurrenceType.none,
        eventTime: const TimeOfDay(hour: 8, minute: 0),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider.value(
            value: cubit,
            child: Scaffold(
              body: SizedBox(
                width: 200,
                child: DayExtras(
                  jewishCalendar: JewishCalendar.fromDateTime(_date)
                    ..inIsrael = true,
                  date: _date,
                  maxVisibleItems: 1,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('ששש בבוקר', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('אאא בערב', findRichText: true), findsNothing);
    });
  });
}
