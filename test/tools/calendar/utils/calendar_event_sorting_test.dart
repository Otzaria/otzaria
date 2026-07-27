import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/tools/calendar/services/notification_service.dart';
import 'package:otzaria/tools/calendar/utils/calendar_cubit.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;

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

class _InMemorySettingsRepository implements SettingsRepository {
  String savedEventsJson = '[]';

  @override
  Future<void> updateCalendarEvents(String json) async {
    savedEventsJson = json;
  }

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

CustomEvent _event({
  required String id,
  required String title,
  DateTime? date,
  TimeOfDay? time,
  RecurrenceType recurrenceType = RecurrenceType.none,
}) {
  final base = date ?? DateTime(2026, 8, 3);
  final jewish = JewishDate.fromDateTime(base);
  return CustomEvent(
    id: id,
    title: title,
    description: '',
    createdAt: DateTime(2026, 8, 1),
    baseGregorianDate: base,
    baseJewishYear: jewish.getJewishYear(),
    baseJewishMonth: jewish.getJewishMonth(),
    baseJewishDay: jewish.getJewishDayOfMonth(),
    recurrenceType: recurrenceType,
    eventTime: time,
  );
}

Future<CalendarCubit> _readyCubit([
  _InMemorySettingsRepository? settings,
]) async {
  final cubit = CalendarCubit(
    settingsRepository: settings ?? _InMemorySettingsRepository(),
    notificationService: _FakeNotificationService(),
  );
  await Future.delayed(const Duration(milliseconds: 100));
  return cubit;
}

void main() {
  setUpAll(() {
    tz_data.initializeTimeZones();
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('compareCalendarEventsByTime', () {
    test('שעה מוקדמת קודמת לשעה מאוחרת, ללא תלות בכותרת', () {
      final late_ = _event(
        id: '1',
        title: 'אאא',
        time: const TimeOfDay(hour: 21, minute: 0),
      );
      final early = _event(
        id: '2',
        title: 'תתת',
        time: const TimeOfDay(hour: 14, minute: 0),
      );

      final sorted = [late_, early]..sort(compareCalendarEventsByTime);
      expect(sorted.map((e) => e.id), ['2', '1']);
    });

    test('דקות נלקחות בחשבון ולא רק שעות', () {
      final a = _event(
        id: 'a',
        title: 'א',
        time: const TimeOfDay(hour: 9, minute: 45),
      );
      final b = _event(
        id: 'b',
        title: 'ב',
        time: const TimeOfDay(hour: 9, minute: 5),
      );

      final sorted = [a, b]..sort(compareCalendarEventsByTime);
      expect(sorted.map((e) => e.id), ['b', 'a']);
    });

    test('חצות (00:00) קודם לכל שעה אחרת', () {
      final midnight = _event(
        id: 'midnight',
        title: 'תתת',
        time: const TimeOfDay(hour: 0, minute: 0),
      );
      final noon = _event(
        id: 'noon',
        title: 'אאא',
        time: const TimeOfDay(hour: 12, minute: 0),
      );

      final sorted = [noon, midnight]..sort(compareCalendarEventsByTime);
      expect(sorted.map((e) => e.id), ['midnight', 'noon']);
    });

    test('אירוע ללא שעה מופיע לפני אירוע עם שעה', () {
      final timed = _event(
        id: 'timed',
        title: 'אאא',
        time: const TimeOfDay(hour: 8, minute: 0),
      );
      final allDay = _event(id: 'allDay', title: 'תתת');

      final sorted = [timed, allDay]..sort(compareCalendarEventsByTime);
      expect(sorted.map((e) => e.id), ['allDay', 'timed']);
    });

    test('שני אירועים ללא שעה ממוינים לפי כותרת', () {
      final bet = _event(id: 'bet', title: 'בבב');
      final alef = _event(id: 'alef', title: 'אאא');

      final sorted = [bet, alef]..sort(compareCalendarEventsByTime);
      expect(sorted.map((e) => e.id), ['alef', 'bet']);
    });

    test('שני אירועים באותה שעה ממוינים לפי כותרת', () {
      const time = TimeOfDay(hour: 10, minute: 30);
      final bet = _event(id: 'bet', title: 'בבב', time: time);
      final alef = _event(id: 'alef', title: 'אאא', time: time);

      final sorted = [bet, alef]..sort(compareCalendarEventsByTime);
      expect(sorted.map((e) => e.id), ['alef', 'bet']);
    });

    test('המשווה סימטרי ומחזיר 0 רק לאירועים שווי-סדר', () {
      const time = TimeOfDay(hour: 7, minute: 15);
      final a = _event(id: 'a', title: 'שווה', time: time);
      final b = _event(id: 'b', title: 'שווה', time: time);

      expect(compareCalendarEventsByTime(a, b), 0);
      final earlier = _event(
        id: 'c',
        title: 'שווה',
        time: const TimeOfDay(hour: 6, minute: 0),
      );
      expect(compareCalendarEventsByTime(earlier, a), lessThan(0));
      expect(compareCalendarEventsByTime(a, earlier), greaterThan(0));
    });
  });

  group('compareCalendarEventsChronologically', () {
    test('תאריך קודם לשעה', () {
      final laterDayEarlyHour = _event(
        id: 'later',
        title: 'א',
        date: DateTime(2026, 8, 4),
        time: const TimeOfDay(hour: 6, minute: 0),
      );
      final earlierDayLateHour = _event(
        id: 'earlier',
        title: 'ת',
        date: DateTime(2026, 8, 3),
        time: const TimeOfDay(hour: 23, minute: 0),
      );

      final sorted = [laterDayEarlyHour, earlierDayLateHour]
        ..sort(compareCalendarEventsChronologically);
      expect(sorted.map((e) => e.id), ['earlier', 'later']);
    });

    test('באותו תאריך — מיון לפי שעה', () {
      final late_ = _event(
        id: 'late',
        title: 'אאא',
        time: const TimeOfDay(hour: 21, minute: 0),
      );
      final early = _event(
        id: 'early',
        title: 'תתת',
        time: const TimeOfDay(hour: 14, minute: 0),
      );

      final sorted = [late_, early]..sort(compareCalendarEventsChronologically);
      expect(sorted.map((e) => e.id), ['early', 'late']);
    });

    test('שעה בתוך baseGregorianDate אינה משפיעה על השוואת התאריך', () {
      final a = _event(
        id: 'a',
        title: 'א',
        date: DateTime(2026, 8, 3, 23, 30),
        time: const TimeOfDay(hour: 20, minute: 0),
      );
      final b = _event(
        id: 'b',
        title: 'ב',
        date: DateTime(2026, 8, 3, 1, 0),
        time: const TimeOfDay(hour: 8, minute: 0),
      );

      final sorted = [a, b]..sort(compareCalendarEventsChronologically);
      expect(sorted.map((e) => e.id), ['b', 'a']);
    });
  });

  group('eventsForDate — סדר התצוגה', () {
    test('שני אירועים באותו יום מוצגים לפי שעה ולא לפי א-ב', () async {
      final cubit = await _readyCubit();
      final date = DateTime(2026, 8, 3);

      await cubit.addEvent(
        title: 'אירוע ערב',
        baseGregorianDate: date,
        recurrenceType: RecurrenceType.none,
        eventTime: const TimeOfDay(hour: 21, minute: 0),
      );
      await cubit.addEvent(
        title: 'שיעור צהריים',
        baseGregorianDate: date,
        recurrenceType: RecurrenceType.none,
        eventTime: const TimeOfDay(hour: 14, minute: 0),
      );

      final events = cubit.eventsForDate(date);
      expect(events.map((e) => e.title), ['שיעור צהריים', 'אירוע ערב']);

      await cubit.close();
    });

    test('אירוע חוזר ואירוע חד-פעמי באותו יום ממוינים יחד לפי שעה', () async {
      final cubit = await _readyCubit();
      final date = DateTime(2026, 8, 3);

      await cubit.addEvent(
        title: 'יום שנה',
        baseGregorianDate: DateTime(2020, 8, 3),
        recurrenceType: RecurrenceType.annualGregorian,
        eventTime: const TimeOfDay(hour: 18, minute: 0),
      );
      await cubit.addEvent(
        title: 'פגישה',
        baseGregorianDate: date,
        recurrenceType: RecurrenceType.none,
        eventTime: const TimeOfDay(hour: 9, minute: 0),
      );

      expect(cubit.eventsForDate(date).map((e) => e.title), [
        'פגישה',
        'יום שנה',
      ]);

      await cubit.close();
    });

    test('אירוע ללא שעה מוצג לפני אירועים עם שעה', () async {
      final cubit = await _readyCubit();
      final date = DateTime(2026, 8, 3);

      await cubit.addEvent(
        title: 'תענית',
        baseGregorianDate: date,
        recurrenceType: RecurrenceType.none,
      );
      await cubit.addEvent(
        title: 'אאא עם שעה',
        baseGregorianDate: date,
        recurrenceType: RecurrenceType.none,
        eventTime: const TimeOfDay(hour: 7, minute: 0),
      );

      expect(cubit.eventsForDate(date).map((e) => e.title), [
        'תענית',
        'אאא עם שעה',
      ]);

      await cubit.close();
    });

    test('אירוע מרובה-ימים ממוין לפי שעתו גם ביום שאינו יום ההתחלה', () async {
      final cubit = await _readyCubit();

      await cubit.addEvent(
        title: 'כינוס',
        baseGregorianDate: DateTime(2026, 8, 2),
        endGregorianDate: DateTime(2026, 8, 5),
        recurrenceType: RecurrenceType.none,
        eventTime: const TimeOfDay(hour: 8, minute: 0),
      );
      await cubit.addEvent(
        title: 'אאא',
        baseGregorianDate: DateTime(2026, 8, 3),
        recurrenceType: RecurrenceType.none,
        eventTime: const TimeOfDay(hour: 20, minute: 0),
      );

      expect(cubit.eventsForDate(DateTime(2026, 8, 3)).map((e) => e.title), [
        'כינוס',
        'אאא',
      ]);

      await cubit.close();
    });
  });

  group('getFilteredEvents — סדר תוצאות החיפוש', () {
    test('תוצאות מסודרות כרונולוגית לפי תאריך ואז שעה', () async {
      final cubit = await _readyCubit();

      await cubit.addEvent(
        title: 'שיעור ב',
        baseGregorianDate: DateTime(2026, 8, 5),
        recurrenceType: RecurrenceType.none,
        eventTime: const TimeOfDay(hour: 9, minute: 0),
      );
      await cubit.addEvent(
        title: 'שיעור א',
        baseGregorianDate: DateTime(2026, 8, 3),
        recurrenceType: RecurrenceType.none,
        eventTime: const TimeOfDay(hour: 22, minute: 0),
      );
      await cubit.addEvent(
        title: 'שיעור ג',
        baseGregorianDate: DateTime(2026, 8, 3),
        recurrenceType: RecurrenceType.none,
        eventTime: const TimeOfDay(hour: 7, minute: 0),
      );

      expect(cubit.getFilteredEvents('שיעור').map((e) => e.title), [
        'שיעור ג',
        'שיעור א',
        'שיעור ב',
      ]);

      await cubit.close();
    });

    test('חיפוש ריק מחזיר רשימה ריקה', () async {
      final cubit = await _readyCubit();
      await cubit.addEvent(
        title: 'משהו',
        baseGregorianDate: DateTime(2026, 8, 3),
        recurrenceType: RecurrenceType.none,
      );

      expect(cubit.getFilteredEvents(''), isEmpty);

      await cubit.close();
    });

    test('חיפוש בתיאור פועל רק כשהאפשרות מופעלת', () async {
      final cubit = await _readyCubit();
      await cubit.addEvent(
        title: 'כותרת',
        description: 'מילה בתיאור',
        baseGregorianDate: DateTime(2026, 8, 3),
        recurrenceType: RecurrenceType.none,
      );

      expect(cubit.getFilteredEvents('בתיאור'), isEmpty);
      cubit.toggleSearchInDescriptions(true);
      expect(cubit.getFilteredEvents('בתיאור'), hasLength(1));

      await cubit.close();
    });
  });
}
