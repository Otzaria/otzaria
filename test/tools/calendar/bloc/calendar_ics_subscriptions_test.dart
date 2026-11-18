import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/tools/calendar/services/calendar_alerts_client.dart';
import 'package:otzaria/tools/calendar/services/calendar_alerts_owner.dart';
import 'package:otzaria/tools/calendar/services/calendar_alerts_store.dart';
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

String _largeIcsWithEvent(String uid) => _icsWithEvents([uid]).replaceFirst(
  'END:VCALENDAR\n',
  '${'X-PADDING:1234567890\n' * 125000}END:VCALENDAR\n',
);

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

  CalendarCubit buildCubit({CalendarAlertsClient? alertsClient}) {
    return CalendarCubit(
      settingsRepository: settings,
      notificationService: _FakeNotificationService(),
      alertsClient: alertsClient,
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

  Future<(CalendarCubit, CalendarCubit)> buildTwoWindows() async {
    final owner = CalendarAlertsOwner(
      store: RepositoryCalendarAlertsStore(settings),
      notifications: _FakeNotificationService(),
    );
    addTearDown(() async {
      await owner.idle;
      owner.dispose();
    });
    final alerts = LocalCalendarAlertsClient(owner);
    final firstWindow = buildCubit(alertsClient: alerts);
    final secondWindow = buildCubit(alertsClient: alerts);
    addTearDown(firstWindow.close);
    addTearDown(secondWindow.close);
    await Future.wait([firstWindow.initialized, secondWindow.initialized]);
    return (firstWindow, secondWindow);
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

  test('ייבוא מאוחר מחליף אירוע מייבוא גדול שהתחיל בחלון אחר', () async {
    final (firstWindow, secondWindow) = await buildTwoWindows();

    final original = _icsWithEvents(['shared']);
    final large = original.replaceFirst(
      'END:VCALENDAR\n',
      '${'X-PADDING:1234567890\n' * 10000}END:VCALENDAR\n',
    );
    final updated = original.replaceFirst('אירוע shared', 'עדכון חדש');
    expect(
      await Future.wait([
        firstWindow.importIcsContent(large),
        secondWindow.importIcsContent(updated),
      ]),
      [1, 1],
    );

    expect(secondWindow.state.events.single.title, 'עדכון חדש');
    final saved = jsonDecode(settings.savedEventsJson) as List;
    expect(saved.single, containsPair('title', 'עדכון חדש'));
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

  test('הוספת מנויים במקביל שומרת את כל המנויים ואירועיהם', () async {
    final (firstWindow, secondWindow) = await buildTwoWindows();
    final largeResponse = Completer<String>();
    pendingFetch = largeResponse;
    final first = firstWindow.addIcsSubscription(
      name: 'יומן ראשון',
      url: 'https://example.com/first.ics',
    );
    final smallResponse = Completer<String>();
    pendingFetch = smallResponse;
    final smallImports = [
      for (var i = 1; i <= 6; i++)
        secondWindow.addIcsSubscription(
          name: 'יומן $i',
          url: 'https://example.com/$i.ics',
        ),
    ];
    largeResponse.complete(_largeIcsWithEvent('ראשון'));
    smallResponse.complete(_icsWithEvents(['שני']));
    expect(await Future.wait([first, ...smallImports]), everyElement(1));

    final subscriptions =
        jsonDecode(settings.savedIcsSubscriptionsJson) as List;
    expect(subscriptions, hasLength(7));
    final events = jsonDecode(settings.savedEventsJson) as List;
    expect(
      events.map((item) => item['icsSourceId']),
      unorderedEquals(subscriptions.map((item) => item['id'])),
    );
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

  test('רענון גדול שומר על סדר הגעת התשובות בין חלונות', () async {
    final (firstWindow, secondWindow) = await buildTwoWindows();
    await firstWindow.addIcsSubscription(
      name: 'יומן',
      url: 'https://example.com/cal.ics',
    );
    final subscriptionId = firstWindow.state.icsSubscriptions.single.id;

    final oldResponse = Completer<String>();
    pendingFetch = oldResponse;
    final firstRefresh = firstWindow.refreshIcsSubscriptions(
      onlyId: subscriptionId,
    );
    final newResponse = Completer<String>();
    pendingFetch = newResponse;
    final secondRefresh = secondWindow.refreshIcsSubscriptions(
      onlyId: subscriptionId,
    );
    oldResponse.complete(_largeIcsWithEvent('ישן'));
    newResponse.complete(_icsWithEvents(['חדש']));
    await Future.wait([firstRefresh, secondRefresh]);

    final saved = jsonDecode(settings.savedEventsJson) as List;
    expect(saved.single, containsPair('title', 'אירוע חדש'));
    expect(firstWindow.state.events.single.title, 'אירוע חדש');
    expect(secondWindow.state.events.single.title, 'אירוע חדש');
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
