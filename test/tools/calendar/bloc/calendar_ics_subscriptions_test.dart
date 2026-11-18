import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/tools/calendar/services/ics_calendar_service.dart';
import 'package:otzaria/tools/calendar/services/notification_service.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;

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

class _InMemorySettingsRepository implements SettingsRepository {
  String savedEventsJson = '[]';
  String savedIcsSubscriptionsJson = '[]';

  @override
  Future<Map<String, dynamic>> loadSettings() async {
    return {
      'calendarType': 'combined',
      'selectedCity': 'ירושלים',
      'calendarEvents': savedEventsJson,
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
      'calendarIcsSubscriptions': savedIcsSubscriptionsJson,
    };
  }

  @override
  Future<void> updateCalendarEvents(String json) async {
    savedEventsJson = json;
  }

  @override
  Future<void> updateCalendarIcsSubscriptions(String value) async {
    savedIcsSubscriptionsJson = value;
  }

  @override
  String getCalendarEventNotificationIdsJson() => '[]';

  @override
  Future<void> updateCalendarEventNotificationIdsJson(String json) async {}

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

String _icsWithEvents(List<String> uids) {
  final buffer = StringBuffer('BEGIN:VCALENDAR\n');
  for (final uid in uids) {
    buffer
      ..writeln('BEGIN:VEVENT')
      ..writeln('UID:$uid')
      ..writeln('DTSTART;VALUE=DATE:20260601')
      ..writeln('SUMMARY:אירוע $uid')
      ..writeln('END:VEVENT');
  }
  buffer.writeln('END:VCALENDAR');
  return buffer.toString();
}

void main() {
  setUpAll(() {
    tz_data.initializeTimeZones();
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  late _InMemorySettingsRepository settings;
  late String fetchedBody;
  late List<Uri> fetchedUris;
  Object? fetchError;
  Completer<String>? pendingFetch;

  CalendarCubit buildCubit() {
    return CalendarCubit(
      settingsRepository: settings,
      notificationService: _FakeNotificationService(),
      icsCalendarService: IcsCalendarService(
        httpFetcher: (uri) async {
          fetchedUris.add(uri);
          final error = fetchError;
          if (error != null) throw error;
          final fetch = pendingFetch;
          return fetch == null ? fetchedBody : await fetch.future;
        },
      ),
    );
  }

  setUp(() {
    settings = _InMemorySettingsRepository();
    fetchedBody = _icsWithEvents(['a1']);
    fetchedUris = [];
    fetchError = null;
    pendingFetch = null;
  });

  test('importIcsContent מוסיף אירועים, וייבוא חוזר לא משכפל', () async {
    final cubit = buildCubit();
    await cubit.initialized;

    final count = await cubit.importIcsContent(_icsWithEvents(['x1', 'x2']));
    expect(count, 2);
    expect(cubit.state.events, hasLength(2));

    final again = await cubit.importIcsContent(_icsWithEvents(['x1', 'x2']));
    expect(again, 2);
    expect(cubit.state.events, hasLength(2));

    final saved = jsonDecode(settings.savedEventsJson) as List;
    expect(saved, hasLength(2));
    await cubit.close();
  });

  test('סגירת הלוח בזמן פענוח קובץ גדול מונעת שמירת אירועים', () async {
    final cubit = buildCubit();
    await cubit.initialized;

    final importing = cubit.importIcsContent(
      _icsWithEvents(['large-file-${'x' * 200000}']),
    );
    await cubit.close();

    expect(await importing, 0);
    expect(settings.savedEventsJson, '[]');
  });

  test('addIcsSubscription מוסיף מנוי ואירועים ושומר את שניהם', () async {
    final cubit = buildCubit();
    await cubit.initialized;

    fetchedBody = _icsWithEvents(['a1', 'a2']);
    final count = await cubit.addIcsSubscription(
      name: 'יומן עבודה',
      url: 'https://example.com/cal.ics',
    );

    expect(count, 2);
    expect(cubit.state.icsSubscriptions, hasLength(1));
    expect(cubit.state.events, hasLength(2));
    expect(
      cubit.state.events.every(
        (e) => e.icsSourceId == cubit.state.icsSubscriptions.single.id,
      ),
      isTrue,
    );
    expect(settings.savedIcsSubscriptionsJson, contains('יומן עבודה'));
    await cubit.close();
  });

  test('webcal:// מומר ל-https בהורדה', () async {
    final cubit = buildCubit();
    await cubit.initialized;

    await cubit.addIcsSubscription(
      name: 'יומן',
      url: 'webcal://example.com/cal.ics',
    );
    expect(fetchedUris.single.scheme, 'https');
    await cubit.close();
  });

  test('רענון מחליף את אירועי המנוי ומשאיר אירועי משתמש', () async {
    final cubit = buildCubit();
    await cubit.initialized;

    await cubit.addEvent(
      title: 'אירוע שלי',
      baseGregorianDate: DateTime(2026, 6, 1),
      recurrenceType: RecurrenceType.none,
    );
    await cubit.addIcsSubscription(
      name: 'יומן',
      url: 'https://example.com/cal.ics',
    );
    expect(cubit.state.events, hasLength(2));

    fetchedBody = _icsWithEvents(['b1', 'b2']);
    await cubit.refreshIcsSubscriptions();

    expect(cubit.state.events, hasLength(3));
    expect(
      cubit.state.events.map((e) => e.title),
      containsAll(['אירוע שלי', 'אירוע b1', 'אירוע b2']),
    );
    expect(cubit.state.events.any((e) => e.title == 'אירוע a1'), isFalse);
    await cubit.close();
  });

  test('כשל בהורדה בזמן רענון שומר את האירועים הקיימים ורושם שגיאה', () async {
    final cubit = buildCubit();
    await cubit.initialized;

    await cubit.addIcsSubscription(
      name: 'יומן',
      url: 'https://example.com/cal.ics',
    );
    expect(cubit.state.events, hasLength(1));

    fetchError = Exception('network down');
    await cubit.refreshIcsSubscriptions();

    expect(cubit.state.events, hasLength(1));
    expect(cubit.state.icsSyncError, isNotNull);
    expect(cubit.state.icsRefreshInProgress, isFalse);
    await cubit.close();
  });

  test('הסרת מנוי מוחקת את האירועים שלו בלבד', () async {
    final cubit = buildCubit();
    await cubit.initialized;

    await cubit.addEvent(
      title: 'אירוע שלי',
      baseGregorianDate: DateTime(2026, 6, 1),
      recurrenceType: RecurrenceType.none,
    );
    await cubit.addIcsSubscription(
      name: 'יומן',
      url: 'https://example.com/cal.ics',
    );
    final subscriptionId = cubit.state.icsSubscriptions.single.id;

    await cubit.removeIcsSubscription(subscriptionId);

    expect(cubit.state.icsSubscriptions, isEmpty);
    expect(cubit.state.events, hasLength(1));
    expect(cubit.state.events.single.title, 'אירוע שלי');
    expect(settings.savedIcsSubscriptionsJson, '[]');
    await cubit.close();
  });

  test('רענון לא משחזר אירועים של מנוי שהוסר בזמן הטעינה', () async {
    final cubit = buildCubit();
    await cubit.initialized;
    await cubit.addIcsSubscription(
      name: 'יומן',
      url: 'https://example.com/cal.ics',
    );
    final subscriptionId = cubit.state.icsSubscriptions.single.id;
    final fetch = Completer<String>();
    pendingFetch = fetch;

    final refreshing = cubit.refreshIcsSubscriptions();
    await cubit.removeIcsSubscription(subscriptionId);
    fetch.complete(_icsWithEvents(['b1']));
    await refreshing;

    expect(cubit.state.events, isEmpty);
    expect(cubit.state.icsSubscriptions, isEmpty);
    expect(cubit.state.icsRefreshInProgress, isFalse);
    await cubit.close();
  });

  test('מנויים שמורים נטענים ומתרעננים באתחול', () async {
    settings.savedIcsSubscriptionsJson = jsonEncode([
      {
        'id': 'icssub_stored',
        'name': 'יומן שמור',
        'url': 'https://example.com/stored.ics',
      },
    ]);
    fetchedBody = _icsWithEvents(['s1']);

    final cubit = buildCubit();
    await cubit.initialized;
    // הרענון רץ אחרי ש-initialized הושלם — ממתינים לסיומו
    await Future.delayed(const Duration(milliseconds: 50));

    expect(cubit.state.icsSubscriptions, hasLength(1));
    expect(fetchedUris, isNotEmpty);
    expect(cubit.state.events.any((e) => e.title == 'אירוע s1'), isTrue);
    await cubit.close();
  });

  test('addIcsSubscription מחזיר null על תוכן שאינו ICS', () async {
    final cubit = buildCubit();
    await cubit.initialized;

    fetchedBody = '<html>not a calendar</html>';
    final count = await cubit.addIcsSubscription(
      name: 'יומן',
      url: 'https://example.com/notcal',
    );

    expect(count, isNull);
    expect(cubit.state.icsSubscriptions, isEmpty);
    expect(cubit.state.icsSyncError, isNotNull);
    await cubit.close();
  });
}
