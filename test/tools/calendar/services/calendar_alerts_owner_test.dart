import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/adapters/plugin_calendar_adapter.dart';
import 'package:otzaria/tools/calendar/models/calendar_event.dart';
import 'package:otzaria/tools/calendar/models/zman_alert_preference.dart';
import 'package:otzaria/tools/calendar/services/calendar_alert_planner.dart';
import 'package:otzaria/tools/calendar/services/calendar_alerts_client.dart';
import 'package:otzaria/tools/calendar/services/calendar_alerts_owner.dart';
import 'package:otzaria/tools/calendar/services/calendar_alerts_store.dart';
import 'package:otzaria/tools/calendar/services/notification_service.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;

import '../support/calendar_alerts_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();

  var now = DateTime(2026, 10, 20, 9);
  late MemoryAlertsStore store;
  late WindowsLikeNotifications notifications;
  late List<CustomEvent> pluginEvents;
  late List<CalendarScheduleStatus> statuses;
  late MemoryPluginIds pluginIds;

  CalendarAlertsOwner owner({
    WindowsLikeNotifications? using,
    bool dedupe = false,
    bool crashes = false,
    ZmanAlertPlanner? zmanPlanner,
  }) {
    final created = CalendarAlertsOwner(
      store: store,
      notifications: using ?? notifications,
      pluginIds: pluginIds,
      pluginEvents: () async => pluginEvents,
      now: () => now,
      zmanPlanner: zmanPlanner,
      dedupeDuplicates: dedupe,
      pluginEventsDelay: const Duration(milliseconds: 200),
    );
    created.scheduleStatuses.listen(statuses.add);
    addTearDown(() async {
      // בעלים ש"קרס" נשאר באמצע ריצה לתמיד.
      if (!crashes) await created.idle;
      created.dispose();
    });
    return created;
  }

  Map<String, Object?> eventArgs(CustomEvent event) => {
    'event': jsonDecode(jsonEncode(event.toJson())),
  };

  /// מה שהתוכנית דורשת לפי המצב השמור עכשיו.
  Set<int> expectedPlan() {
    final events = [
      for (final item
          in jsonDecode(store.values[CalendarAlertsKeys.events] as String)
              as List)
        CustomEvent.fromJson(item as Map<String, dynamic>),
      ...pluginEvents,
    ];
    return {
      for (final alert in CalendarAlertPlanner.planEventReminders(
        events: events,
        enabled: store.values[CalendarAlertsKeys.enabled] == true,
        defaultMinutes: store.values[CalendarAlertsKeys.time] as int,
        soundEnabled: true,
        now: now,
      ))
        alert.id,
    };
  }

  setUp(() {
    now = DateTime(2026, 10, 20, 9);
    store = MemoryAlertsStore();
    notifications = WindowsLikeNotifications();
    pluginEvents = [];
    statuses = [];
    pluginIds = MemoryPluginIds();
  });

  test('תזכורת לאירוע חדש מתוזמנת, ומחיקה מבטלת אותה', () async {
    final o = owner();

    final ack = await o.execute('upsertEvent', eventArgs(futureEvent('a')));
    await o.idle;
    expect(ack['ok'], isTrue);
    expect(notifications.present, {reminderId('a')});
    expect(store.ledger, [reminderId('a')]);

    await o.execute('deleteEvent', {'id': 'a'});
    await o.idle;
    expect(notifications.present, isEmpty);
    expect(store.ledger, isEmpty);
    expect(statuses.last.ok, isTrue);
  });

  test('חישוב זמני יום נשמר עד שינוי עיר, יום או העדפות', () async {
    var calculations = 0;
    bool? plannedTwelveHourClock;
    final o = owner(
      zmanPlanner:
          ({
            required alerts,
            required city,
            required now,
            required twelveHourClock,
          }) {
            calculations++;
            plannedTwelveHourClock = twelveHourClock;
            return CalendarAlertPlanner.planZmanAlerts(
              alerts: alerts,
              city: city,
              now: now,
              twelveHourClock: twelveHourClock,
            );
          },
    );
    await o.execute('setZmanAlert', {
      'timeId': 'sunset',
      'pref': const ZmanAlertPreference(
        minutesBefore: 10,
        displayName: 'שקיעה',
      ).toJson(),
    });
    await o.idle;
    expect(calculations, 1);
    await o.execute('upsertEvent', eventArgs(futureEvent('a')));
    await o.idle;
    await o.execute('setNotificationPrefs', {'sound': false});
    await o.idle;
    expect(calculations, 1);
    await o.execute('setCity', {'city': 'חיפה'});
    await o.idle;
    expect(calculations, 2);
    await o.execute('setZmanAlert', {
      'timeId': 'sunset',
      'pref': const ZmanAlertPreference(
        minutesBefore: 15,
        displayName: 'שקיעה',
      ).toJson(),
    });
    await o.idle;
    expect(calculations, 3);
    now = now.add(const Duration(days: 1));
    await o.restoreIfNeeded();
    expect(calculations, 4);
    expect(plannedTwelveHourClock, isFalse);
    await o.execute('setTwelveHourClock', {'enabled': true});
    await o.idle;
    expect(calculations, 5);
    expect(plannedTwelveHourClock, isTrue);
    expect(store.values[CalendarAlertsKeys.twelveHourClock], isTrue);
    final rejected = await o.execute('setTwelveHourClock', {'enabled': 'yes'});
    expect(rejected['ok'], isFalse);
    expect(store.values[CalendarAlertsKeys.twelveHourClock], isTrue);
    expect(notifications.everyIdAtMostOnce, isTrue);
  });

  test('תוכנית שמורה מסננת זמנים שחלפו ומאפשרת חזרה בשעון', () async {
    final o = owner();
    store.values[CalendarAlertsKeys.zmanAlerts] = jsonEncode({
      'sunrise': const ZmanAlertPreference(
        minutesBefore: 10,
        displayName: 'הנץ',
      ).toJson(),
    });
    final today = CalendarAlertPlanner.zmanNotificationId('sunrise', now);
    await o.restoreIfNeeded();
    expect(notifications.present, isNot(contains(today)));
    now = DateTime(2026, 10, 20, 0, 1);
    await o.restoreIfNeeded();
    expect(notifications.present, contains(today));
    notifications.scheduled.clear();
    now = DateTime(2026, 10, 20, 9);
    await o.restoreIfNeeded();
    expect(notifications.present, isNot(contains(today)));
    expect(notifications.scheduled, isEmpty);
  });

  test('רענון יומי נשאר פעיל לאירוע חוזר שעדיין מחוץ לחלון', () {
    fakeAsync((async) {
      final event = futureEvent('future').copyWith(
        baseGregorianDate: DateTime(2027, 2, 1),
        recurrenceType: RecurrenceType.weekly,
      );
      store.values[CalendarAlertsKeys.events] = jsonEncode([event.toJson()]);
      final o = CalendarAlertsOwner(
        store: store,
        notifications: notifications,
        pluginEvents: () async => [],
        now: () => now,
        dedupeDuplicates: false,
      );
      unawaited(o.restoreIfNeeded());
      async.elapse(Duration.zero);
      expect(notifications.initCalls, 0);
      expect(store.ledger, isEmpty);
      now = DateTime(2027, 1, 31, 9);
      async.elapse(const Duration(days: 1));
      expect(notifications.scheduled, isNotEmpty);
      expect(notifications.everyIdAtMostOnce, isTrue);
      o.dispose();
      async.flushMicrotasks();
    });
  });

  test('עריכת אירוע אינה מתזמנת מחדש זמני יום שלא השתנו', () async {
    store.values[CalendarAlertsKeys.zmanAlerts] = jsonEncode({
      'sunset': const ZmanAlertPreference(
        minutesBefore: 10,
        displayName: 'שקיעה',
      ).toJson(),
    });
    final o = owner();
    await o.restoreIfNeeded();
    final original = notifications.present;
    expect(original, hasLength(46));
    notifications.scheduled.clear();
    notifications.cancelled.clear();

    await o.execute('upsertEvent', eventArgs(futureEvent('new')));
    await o.idle;

    expect(notifications.scheduled.map((a) => a.id), [reminderId('new')]);
    expect(notifications.cancelled, [reminderId('new')]);
    expect(notifications.present, {...original, reminderId('new')});
  });

  test('שינוי צליל מתזמן רק אירועים, ושינוי עיר רק זמני יום', () async {
    store.values[CalendarAlertsKeys.zmanAlerts] = jsonEncode({
      'sunset': const ZmanAlertPreference(
        minutesBefore: 10,
        displayName: 'שקיעה',
      ).toJson(),
    });
    final o = owner();
    await o.execute('upsertEvent', eventArgs(futureEvent('a')));
    await o.idle;
    notifications.scheduled.clear();
    notifications.cancelled.clear();

    await o.execute('setNotificationPrefs', {'sound': false});
    await o.idle;
    expect(notifications.scheduled.map((a) => a.id), [reminderId('a')]);
    expect(notifications.scheduled.single.sound, isFalse);
    notifications.scheduled.clear();
    notifications.cancelled.clear();

    await o.execute('setCity', {'city': 'חיפה'});
    await o.idle;
    expect(notifications.scheduled, isNotEmpty);
    expect(
      notifications.scheduled.map((a) => a.id),
      isNot(contains(reminderId('a'))),
    );
    expect(notifications.cancelled, isNot(contains(reminderId('a'))));
    expect(notifications.everyIdAtMostOnce, isTrue);
  });

  test('כשל ביטול וכשל תזמון נשארים ניתנים לניסיון חוזר', () async {
    final o = owner();
    await o.execute('upsertEvent', eventArgs(futureEvent('a')));
    await o.idle;
    notifications.onCancel = () => throw StateError('cancel failed');
    await o.execute('deleteEvent', {'id': 'a'});
    await o.idle;
    expect(store.ledger, [reminderId('a')]);
    expect(statuses.last.ok, isFalse);
    notifications.onCancel = null;
    await o.restoreIfNeeded();
    expect(notifications.present, isEmpty);
    expect(store.ledger, isEmpty);

    notifications.failingIds.add(reminderId('a'));
    await o.execute('upsertEvent', eventArgs(futureEvent('a')));
    await o.idle;
    expect(store.ledger, isEmpty);
    notifications.failingIds.clear();
    await o.restoreIfNeeded();
    expect(notifications.present, {reminderId('a')});
    expect(notifications.everyIdAtMostOnce, isTrue);
  });

  test('אובדן הרשאה ושחזורה אינם משאירים cache של תזמון שבוטל', () async {
    final o = owner();
    await o.execute('upsertEvent', eventArgs(futureEvent('a')));
    await o.idle;
    notifications.permissions = false;
    await o.restoreIfNeeded();
    expect(store.ledger, isEmpty);
    expect(notifications.present, isEmpty);
    expect(statuses.last.ok, isFalse);
    notifications.permissions = true;
    await o.restoreIfNeeded();
    expect(notifications.present, {reminderId('a')});
    expect(notifications.everyIdAtMostOnce, isTrue);
  });

  test('חלון זמני היום מתארך כשהבעלים מתזמן ביום הבא', () async {
    store.values[CalendarAlertsKeys.zmanAlerts] = jsonEncode({
      'sunrise': const ZmanAlertPreference(
        minutesBefore: 15,
        displayName: 'הנץ',
      ).toJson(),
    });
    now = DateTime(2026, 10, 20, 0, 1);
    final o = owner();
    await o.restoreIfNeeded();
    final firstDay = CalendarAlertPlanner.zmanNotificationId(
      'sunrise',
      DateTime(2026, 10, 20),
    );
    expect(notifications.present, hasLength(46));
    expect(notifications.present, contains(firstDay));

    now = DateTime(2026, 10, 21, 0, 1);
    await o.restoreIfNeeded();

    expect(notifications.everyIdAtMostOnce, isTrue);
    expect(notifications.present, hasLength(46));
    expect(notifications.present, isNot(contains(firstDay)));
    expect(
      notifications.present,
      contains(
        CalendarAlertPlanner.zmanNotificationId(
          'sunrise',
          DateTime(2026, 12, 5),
        ),
      ),
    );
  });

  test('תזמון שנכשל אינו נרשם, והכשל מדווח בנפרד מהאישור', () async {
    notifications.failingIds.add(reminderId('a'));
    final o = owner();

    final ack = await o.execute('upsertEvent', eventArgs(futureEvent('a')));
    await o.execute('upsertEvent', eventArgs(futureEvent('b')));
    await o.idle;

    expect(ack['ok'], isTrue);
    expect(store.ledger, [reminderId('b')]);
    expect(statuses.last.ok, isFalse);
  });

  test('אירוע תוסף אינו נשמר באירועי המשתמש', () async {
    store.values[CalendarAlertsKeys.events] = jsonEncode([
      futureEvent('u').toJson(),
      futureEvent('plugin:k').toJson(),
    ]);
    final o = owner();

    final rejected = await o.execute(
      'upsertEvent',
      eventArgs(futureEvent('plugin:x')),
    );
    await o.execute('snapshot', const {});

    expect(rejected['ok'], isFalse);
    final stored =
        jsonDecode(store.values[CalendarAlertsKeys.events] as String) as List;
    expect(stored.map((e) => (e as Map)['id']), ['u']);
  });

  test('אירועי תוספים מתוזמנים כולם, בלי תלות ב-scope', () async {
    final adapter = PluginCalendarAdapter(
      recordsLoader: (_) async => [
        for (final scope in ['global', 'workspace:w', 'book:b'])
          {
            'plugin_id': 'p',
            'key': scope,
            'scope': scope,
            'payload_json': jsonEncode({
              'title': scope,
              'startsAt': '2026-10-25T18:00:00',
            }),
          },
      ],
    );
    pluginEvents = await adapter.loadAllPluginEvents();
    final shown = await adapter.loadAndMergePluginEvents(const []);
    final o = owner();

    await o.restoreIfNeeded();

    expect(shown.map((e) => e.id), ['p:global']);
    expect(notifications.present, {
      for (final scope in ['global', 'workspace:w', 'book:b'])
        reminderId('p:$scope'),
    });
  });

  test('כשל קריאת תוספים שומר התראות, וקריאה ריקה מוצלחת מבטלת', () async {
    var fails = false;
    var title = 'original';
    var empty = false;
    final adapter = PluginCalendarAdapter(
      recordsLoader: (_) async {
        if (fails) throw StateError('database unavailable');
        return [
          if (!empty)
            {
              'plugin_id': 'p',
              'key': 'future',
              'scope': 'global',
              'payload_json': jsonEncode({
                'title': title,
                'startsAt': '2026-10-25T18:00:00',
              }),
            },
        ];
      },
    );
    final o = CalendarAlertsOwner(
      store: store,
      notifications: notifications,
      pluginEvents: adapter.loadAllPluginEvents,
      now: () => now,
      dedupeDuplicates: false,
    );
    o.scheduleStatuses.listen(statuses.add);
    addTearDown(o.dispose);
    await o.restoreIfNeeded();
    final initial = notifications.present;
    final ledger = List<int>.of(store.ledger);
    expect(initial, hasLength(1));
    notifications.scheduled.clear();
    notifications.cancelled.clear();

    fails = true;
    await o.restoreIfNeeded();
    expect(notifications.present, initial);
    expect(store.ledger, ledger);
    expect(notifications.cancelled, isEmpty);
    expect(statuses.last.ok, isFalse);

    fails = false;
    title = 'updated';
    await o.restoreIfNeeded();
    expect(notifications.scheduled.single.title, 'updated');
    expect(notifications.everyIdAtMostOnce, isTrue);
    expect(statuses.last.ok, isTrue);

    empty = true;
    await o.restoreIfNeeded();
    expect(notifications.present, isEmpty);
    expect(store.ledger, isEmpty);
  });

  test('ב-Windows כפילויות של מזהים שלנו נמחקות פעם אחת', () async {
    store.values[CalendarAlertsKeys.events] = jsonEncode([
      futureEvent('a').toJson(),
    ]);
    store.ledger = [reminderId('a'), 77];
    notifications.counts.addAll({reminderId('a'): 2, 77: 3, 99: 2});
    final o = owner(dedupe: true);

    await o.restoreIfNeeded();

    expect(notifications.counts[reminderId('a')], 1);
    expect(notifications.counts[77], 0);
    // מזהה שאינו שלנו (למשל של תוסף) אינו נוגע.
    expect(notifications.counts[99], 2);
    expect(store.ledger, [reminderId('a')]);
  });

  test('קריסה באמצע ריצה אינה משאירה התראה שאין לבטל', () async {
    store.values[CalendarAlertsKeys.events] = jsonEncode([
      futureEvent('a').toJson(),
      futureEvent('b').toJson(),
    ]);
    store.ledger = [5];
    notifications.counts[5] = 1;
    final crashed = Completer<void>();
    notifications.onSchedule = (call) {
      if (call == 2) {
        notifications.scheduleGate = Completer<void>();
        crashed.complete();
      }
    };
    unawaited(owner(crashes: true).restoreIfNeeded());
    await crashed.future;
    await pumpEventQueue();

    // הרישום נכתב לפני כל פעולה במערכת, ולכן מכסה את כל מה שקיים בה.
    expect(store.ledgerWrites.first.toSet(), {
      5,
      reminderId('a'),
      reminderId('b'),
    });
    expect(store.ledger.toSet().containsAll(notifications.present), isTrue);

    // הפעלה חדשה: האירוע b נמחק בינתיים.
    store.values[CalendarAlertsKeys.events] = jsonEncode([
      futureEvent('a').toJson(),
    ]);
    final restarted = WindowsLikeNotifications()
      ..counts.addAll(notifications.counts);
    await owner(using: restarted).restoreIfNeeded();

    expect(restarted.everyIdAtMostOnce, isTrue);
    expect(restarted.present, {reminderId('a')});
    expect(store.ledger, [reminderId('a')]);
  });

  test('בלי מה לתזמן או לבטל — אין אתחול נייטיבי', () async {
    final o = owner();

    await o.restoreIfNeeded();
    await o.execute('snapshot', const {});
    await o.execute('setNotificationPrefs', {'time': 15});
    await o.execute('setCity', {'city': 'חיפה'});
    await o.idle;

    expect(notifications.initCalls, 0);
  });

  test('שער עלייה תקוע: האישור חוזר מיד, והתזמון קורה פעם אחת אחריו', () async {
    notifications.initGate = Completer<void>();
    final o = owner();

    final ack = await o
        .execute('upsertEvent', eventArgs(futureEvent('a')))
        .timeout(const Duration(seconds: 2));
    await o.execute('upsertEvent', eventArgs(futureEvent('a')));
    await pumpEventQueue();
    expect(ack['ok'], isTrue);
    expect(notifications.scheduled, isEmpty);

    notifications.initGate!.complete();
    await o.idle;

    expect(
      notifications.scheduled.where((s) => s.id == reminderId('a')),
      hasLength(1),
    );
  });

  test(
    'בכל שזירה של פקודות כל מזהה קיים פעם אחת והרישום שווה לתוכנית',
    () async {
      for (var seed = 0; seed < 25; seed++) {
        store = MemoryAlertsStore({
          CalendarAlertsKeys.events: jsonEncode([
            for (final id in ['a', 'b', 'c']) futureEvent(id).toJson(),
          ]),
        });
        notifications = WindowsLikeNotifications();
        final random = Random(seed);
        final o = owner();
        // העלייה כבר תזמנה את המצב השמור.
        await o.restoreIfNeeded();
        final pending = <Future<Object?>>[];

        Future<Object?> randomCommand() {
          final id = ['a', 'b', 'c', 'd', 'e'][random.nextInt(5)];
          return switch (random.nextInt(4)) {
            0 => o.execute('deleteEvent', {'id': id}),
            1 => o.execute('setNotificationPrefs', {
              'enabled': random.nextInt(4) != 0,
            }),
            2 => o.execute('setNotificationPrefs', {
              'time': 10 + random.nextInt(50),
            }),
            _ => o.execute(
              'upsertEvent',
              eventArgs(futureEvent(id, day: 22 + random.nextInt(6))),
            ),
          };
        }

        // פקודות מגיעות גם באמצע ביטול ותזמון.
        notifications.onSchedule = (_) {
          if (random.nextInt(3) == 0) pending.add(randomCommand());
        };
        for (var i = 0; i < 6; i++) {
          pending.add(randomCommand());
        }
        while (pending.isNotEmpty) {
          await pending.removeLast();
        }
        await o.idle;
        notifications.onSchedule = null;
        // פקודות שנוספו בריצת התזמון האחרונה.
        while (pending.isNotEmpty) {
          await pending.removeLast();
        }
        await o.idle;

        expect(notifications.everyIdAtMostOnce, isTrue, reason: 'seed $seed');
        expect(notifications.present, expectedPlan(), reason: 'seed $seed');
        expect(store.ledger.toSet(), expectedPlan(), reason: 'seed $seed');
      }
    },
  );

  group('התראות של תוספים', () {
    Map<String, Object?> scheduleArgs(String pluginId, int id) => {
      'pluginId': pluginId,
      'id': id,
      'title': 't',
      'body': 'b',
      'at': now.add(const Duration(hours: 2)).toIso8601String(),
    };

    test('ביטול של תוסף בלי מזהים אינו מאתחל את השירות', () async {
      final o = owner();

      final acks = [
        await o.execute('pluginCancelAll', {'pluginId': 'p'}),
        await o.execute('pluginCancel', {'pluginId': 'p', 'id': 3}),
      ];

      expect(acks.map((a) => a['ok']), [true, true]);
      expect(notifications.initCalls, 0);
    });

    test('שני תזמונים מקבילים של אותו מזהה משאירים מופע אחד', () async {
      final o = owner();

      final acks = await Future.wait([
        o.execute('pluginSchedule', scheduleArgs('p', 5)),
        o.execute('pluginSchedule', scheduleArgs('p', 5)),
      ]);

      expect(acks.map((a) => a['ok']), [true, true]);
      expect(notifications.counts[5], 1);
      expect(pluginIds.ids['p'], [5]);
    });

    test('בכל שזירה כל מזהה קיים פעם אחת ושווה לרישום', () async {
      for (var seed = 0; seed < 25; seed++) {
        notifications = WindowsLikeNotifications();
        pluginIds = MemoryPluginIds();
        final random = Random(seed);
        final o = owner();

        Future<Object?> randomCommand() {
          final plugin = ['p', 'q'][random.nextInt(2)];
          // לכל תוסף מזהים משלו; מזהה משותף לשני תוספים הוא התנגשות אחרת.
          final id = (plugin == 'p' ? 1 : 11) + random.nextInt(3);
          return switch (random.nextInt(4)) {
            0 => o.execute('pluginCancel', {'pluginId': plugin, 'id': id}),
            1 => o.execute('pluginCancelAll', {'pluginId': plugin}),
            _ => o.execute('pluginSchedule', scheduleArgs(plugin, id)),
          };
        }

        final pending = [for (var i = 0; i < 8; i++) randomCommand()];
        notifications.onSchedule = (_) {
          if (random.nextInt(3) == 0) pending.add(randomCommand());
        };
        while (pending.isNotEmpty) {
          await pending.removeLast();
        }
        notifications.onSchedule = null;

        expect(notifications.everyIdAtMostOnce, isTrue, reason: 'seed $seed');
        expect(notifications.present, {
          for (final ids in pluginIds.ids.values) ...ids,
        }, reason: 'seed $seed');
      }
    });

    test('ביטול של מזהה שאינו ברישום התוסף אינו נוגע בו', () async {
      store.values[CalendarAlertsKeys.events] = jsonEncode([
        futureEvent('a').toJson(),
      ]);
      final o = owner();
      await o.restoreIfNeeded();
      await o.execute('pluginSchedule', scheduleArgs('q', 9));

      final acks = [
        await o.execute('pluginCancel', {
          'pluginId': 'p',
          'id': reminderId('a'),
        }),
        await o.execute('pluginCancel', {'pluginId': 'p', 'id': 9}),
        await o.execute('pluginCancelAll', {'pluginId': 'p'}),
      ];

      expect(acks.map((a) => a['ok']), [true, true, true]);
      expect(notifications.present, {reminderId('a'), 9});
      expect(pluginIds.ids['q'], [9]);
    });

    test('ביטול של מזהה שברישום מבטל אותו ומסיר אותו', () async {
      final o = owner();
      await o.execute('pluginSchedule', scheduleArgs('p', 4));
      await o.execute('pluginSchedule', scheduleArgs('p', 6));

      await o.execute('pluginCancel', {'pluginId': 'p', 'id': 4});

      expect(notifications.present, {6});
      expect(pluginIds.ids['p'], [6]);
    });

    test('ביטול שממתין לאתחול מבטל גם מזהה שנרשם בינתיים', () async {
      pluginIds.ids['p'] = [1];
      notifications.counts[1] = 1;
      notifications.initGate = Completer<void>();
      final o = owner();

      final scheduled = o.execute('pluginSchedule', scheduleArgs('p', 2));
      final cancelled = o.execute('pluginCancelAll', {'pluginId': 'p'});
      await Future<void>.delayed(Duration.zero);
      notifications.initGate!.complete();
      await Future.wait([scheduled, cancelled]);

      expect(notifications.present, isEmpty);
      expect(pluginIds.ids['p'], isEmpty);
    });

    test('הצגה נרשמת לתוסף, ולכן ביטול שלה מגיע להתראה', () async {
      final o = owner();
      await o.execute('pluginShow', {
        'pluginId': 'p',
        'id': 7,
        'title': 't',
        'body': 'b',
      });

      await o.execute('pluginCancel', {'pluginId': 'p', 'id': 7});

      expect(notifications.shown, [7]);
      expect(notifications.cancelled, contains(7));
      expect(pluginIds.ids['p'], isEmpty);
    });

    for (final initialized in [true, false]) {
      test('ביטול שנשלח אחרי תזמון בלי המתנה אינו עוקף אותו '
          '(${initialized ? 'מאותחל' : 'ממתין לאתחול'})', () async {
        if (initialized) {
          await notifications.ensureInitialized();
        } else {
          notifications.initGate = Completer<void>();
        }
        final o = owner();

        final scheduled = o.execute('pluginSchedule', scheduleArgs('p', 5));
        final cancelled = o.execute('pluginCancel', {'pluginId': 'p', 'id': 5});
        notifications.initGate?.complete();
        final acks = await Future.wait([scheduled, cancelled]);

        expect(acks.map((a) => a['ok']), [true, true]);
        expect(notifications.present, isEmpty);
        expect(pluginIds.ids['p'], isEmpty);
      });
    }

    test('מזהה של התראת לוח השנה נדחה ואינו מבוטל', () async {
      store.values[CalendarAlertsKeys.events] = jsonEncode([
        futureEvent('a').toJson(),
      ]);
      final o = owner();
      await o.restoreIfNeeded();
      notifications.cancelled.clear();

      final acks = [
        await o.execute('pluginSchedule', scheduleArgs('p', reminderId('a'))),
        await o.execute('pluginShow', {
          'pluginId': 'p',
          'id': reminderId('a'),
          'title': 't',
          'body': 'b',
        }),
      ];

      for (final ack in acks) {
        expect(ack['ok'], isFalse);
        expect('${ack['error']}', startsWith('error.invalid_params'));
      }
      expect(notifications.counts[reminderId('a')], 1);
      expect(notifications.cancelled, isNot(contains(reminderId('a'))));
      expect(notifications.shown, isEmpty);
      expect(pluginIds.ids['p'], isNull);
    });

    test('תזמון עם מזהה של תוסף אחר אינו מבטל את ההתראה שלו', () async {
      final o = owner();
      await o.execute('pluginSchedule', scheduleArgs('q', 9));

      await o.execute('pluginSchedule', scheduleArgs('p', 9));

      expect(notifications.cancelled, isNot(contains(9)));
      expect(pluginIds.ids['q'], [9]);
    });

    test('בלי הרשאה תוסף אינו מתזמן ואינו נרשם', () async {
      notifications.permissions = false;
      final o = owner();

      final ack = await o.execute('pluginSchedule', scheduleArgs('p', 3));

      expect(ack['ok'], isFalse);
      expect('${ack['error']}', startsWith('error.forbidden'));
      expect(notifications.scheduled, isEmpty);
      expect(pluginIds.ids['p'], isNull);
    });
  });

  test('לולאת פרסום של אירועי תוספים מייצרת שידור אחד', () async {
    final o = owner();
    await o.restoreIfNeeded();
    final updates = <CalendarAlertsUpdate>[];
    o.updates.listen(updates.add);

    for (var i = 0; i < 20; i++) {
      pluginEvents = [...pluginEvents, futureEvent('p:$i')];
      await o.execute('pluginEventsChanged', const {});
      await Future<void>.delayed(Duration.zero);
    }
    await o.idle;

    expect(updates, hasLength(1));
    expect(updates.single.pluginEventsChanged, isTrue);
    expect(notifications.present, {
      for (var i = 0; i < 20; i++) reminderId('p:$i'),
    });
  });

  test('שינוי באירועי תוספים אחרי השידור משודר שוב', () async {
    final o = owner();
    final updates = <CalendarAlertsUpdate>[];
    o.updates.listen(updates.add);

    await o.execute('pluginEventsChanged', const {});
    await o.idle;
    await o.execute('pluginEventsChanged', const {});
    await o.idle;

    expect(updates.where((u) => u.pluginEventsChanged), hasLength(2));
  });

  test(
    'איפוס הגדרות: הבעלים משדר את הערכים השמורים ומבטל מול הרישום',
    () async {
      store.values[CalendarAlertsKeys.events] = jsonEncode([
        futureEvent('a').toJson(),
      ]);
      final o = owner();
      await o.restoreIfNeeded();
      expect(notifications.present, {reminderId('a')});
      final updates = <CalendarAlertsUpdate>[];
      o.updates.listen(updates.add);
      final revision = o.revision;

      // האיפוס מוחק גם את הרישום השמור; הבעלים מבטל לפי מה שבזיכרון.
      store.values
        ..clear()
        ..addAll(CalendarAlertsKeys.defaults);
      store.ledger = [];
      await o.handleSettingsReset();
      await o.idle;

      final changed = updates.single;
      expect(changed.revision, revision + 1);
      expect(
        changed.values[CalendarAlertsKeys.events],
        CalendarAlertsKeys.defaults[CalendarAlertsKeys.events],
      );
      expect(notifications.present, isEmpty);
    },
  );

  group('לקוח בחלון הבעלים', () {
    test('עדכון ישן נזרק', () async {
      final client = LocalCalendarAlertsClient(owner());
      final seen = <int>[];
      client.updates.listen((u) => seen.add(u.revision));
      const epoch = 'e';

      expect(
        await client.accept(
          const CalendarAlertsUpdate(epoch: epoch, revision: 5, values: {}),
        ),
        isTrue,
      );
      expect(
        await client.accept(
          const CalendarAlertsUpdate(epoch: epoch, revision: 3, values: {}),
        ),
        isFalse,
      );
      expect(seen, [5]);
      expect(client.appliedRevision, 5);
    });

    test('אחרי forgetAppliedRevision אותו revision מוחל שוב', () async {
      final client = LocalCalendarAlertsClient(owner());
      const update = CalendarAlertsUpdate(epoch: 'e', revision: 5, values: {});
      expect(await client.accept(update), isTrue);
      expect(await client.accept(update), isFalse);

      client.forgetAppliedRevision();

      expect(await client.accept(update), isTrue);
    });
  });

  group('NotificationService אמיתי', () {
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    final calls = <MethodCall>[];
    final service = NotificationService();

    setUpAll(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      FlutterLocalNotificationsPlatform.instance =
          MacOSFlutterLocalNotificationsPlugin();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return true;
          });
    });

    tearDownAll(() {
      debugDefaultTargetPlatformOverride = null;
      NotificationService.startupGate = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    setUp(() {
      service.resetForTesting();
      calls.clear();
    });

    test('אין initialize לפני שער החשיפה, ואחריו בדיוק אחד', () async {
      // השירות האמיתי בודק את שעון המערכת, ולכן גם האירועים יחסיים אליו.
      now = DateTime.now();
      CustomEvent event(String id) => futureEvent(id).copyWith(
        baseGregorianDate: now.add(const Duration(days: 5)),
      );
      final reveal = Completer<void>();
      NotificationService.startupGate = () => reveal.future;
      final o = CalendarAlertsOwner(
        store: store,
        notifications: service,
        pluginEvents: () async => const [],
        now: () => now,
        dedupeDuplicates: false,
      );
      addTearDown(o.dispose);

      final ack = await o.execute('upsertEvent', eventArgs(event('a')));
      await o.execute('upsertEvent', eventArgs(event('b')));
      await pumpEventQueue();
      expect(ack['ok'], isTrue);
      expect(calls, isEmpty);

      reveal.complete();
      await o.idle;
      final methods = calls.map((c) => c.method).toList();
      expect(methods.where((m) => m == 'initialize'), hasLength(1));
      expect(methods.where((m) => m == 'zonedSchedule'), hasLength(2));
      expect(store.ledger.toSet(), {reminderId('a'), reminderId('b')});
    });
  });
}
