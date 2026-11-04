import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis_auth/googleapis_auth.dart' as auth;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/repository/google_calendar_repository.dart';
import 'package:otzaria/tools/calendar/services/google_calendar_service.dart';
import 'package:otzaria/tools/calendar/services/notification_service.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;

class _Settings implements SettingsRepository {
  int? lastSync;
  String savedEventsJson = '[]';

  @override
  Future<Map<String, dynamic>> loadSettings() async => {
    'calendarType': 'combined',
    'selectedCity': 'ירושלים',
    'calendarEvents': '[]',
    'calendarNotificationsEnabled': false,
    'calendarNotificationTime': 60,
    'calendarNotificationSound': false,
    'calendarZmanAlerts': '{}',
    'calendarEnabledZmanim': '',
    'calendarDayTransition': 'sunset',
    'googleCalendarEnabled': true,
    'googleCalendarSelectedIds': 'primary',
    'googleCalendarSyncPastDays': 60,
    'googleCalendarSyncFutureDays': 365,
    'googleCalendarLastSync': 0,
  };

  @override
  Future<void> updateCalendarEvents(String json) async {
    savedEventsJson = json;
  }

  @override
  Future<void> updateGoogleCalendarSelectedIds(List<String> ids) async {}

  @override
  Future<void> updateGoogleCalendarLastSync(int value) async =>
      lastSync = value;

  @override
  String getCalendarEventNotificationIdsJson() => '[]';

  @override
  Future<void> updateCalendarEventNotificationIdsJson(String json) async {}

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Notifications implements NotificationService {
  @override
  bool get isInitialized => true;

  @override
  Future<void> cancelNotifications(Iterable<int> ids) async {}

  @override
  Future<bool> checkPermissions() async => false;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Hands out a client over [handler], or fails the way the test asks.
class _Google extends GoogleCalendarService {
  _Google({this.handler, this.error});

  final MockClientHandler? handler;
  final Object? error;

  @override
  Future<bool> isSignedIn() async => handler != null;

  @override
  Future<GoogleCalendarApiClient?> getApiClient({
    bool interactive = false,
  }) async {
    if (error != null) throw error!;
    if (handler == null) return null;
    final credentials = auth.AccessCredentials(
      auth.AccessToken(
        'Bearer',
        'token',
        DateTime.now().toUtc().add(const Duration(hours: 1)),
      ),
      null,
      const [],
    );
    return GoogleCalendarApiClient(
      client: auth.authenticatedClient(MockClient(handler!), credentials),
    );
  }
}

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();

  Future<(CalendarCubit, _Settings)> build(_Google google) async {
    final settings = _Settings();
    final cubit = CalendarCubit(
      settingsRepository: settings,
      notificationService: _Notifications(),
      googleCalendarService: google,
    );
    addTearDown(cubit.close);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return (cubit, settings);
  }

  test('without an authorized client the sync reports it', () async {
    final (cubit, _) = await build(_Google());

    await cubit.syncGoogleCalendar(interactive: false);

    expect(
      cubit.state.googleCalendarSyncError,
      'לא הצלחנו להתחבר לחשבון Google.',
    );
    expect(cubit.state.googleCalendarConnected, isFalse);
    expect(cubit.state.googleCalendarSyncInProgress, isFalse);
  });

  test('an error while getting the client is shown as is', () async {
    final (cubit, _) = await build(_Google(error: Exception('ההרשאה נדחתה')));

    await cubit.syncGoogleCalendar(interactive: false);

    expect(cubit.state.googleCalendarSyncError, 'ההרשאה נדחתה');
    expect(cubit.state.googleCalendarConnected, isFalse);
  });

  test('a successful sync merges the events', () async {
    final (cubit, settings) = await build(
      _Google(
        handler: (request) async {
          if (request.url.path.contains('calendarList')) {
            return _json({'items': []});
          }
          return _json({
            'items': [
              {
                'id': 'g1',
                'summary': 'פגישה',
                'start': {'date': '2026-10-05'},
                'end': {'date': '2026-10-06'},
              },
            ],
          });
        },
      ),
    );

    await cubit.syncGoogleCalendar(interactive: false);

    expect(cubit.state.events.map((e) => e.title), contains('פגישה'));
    expect(cubit.state.googleCalendarConnected, isTrue);
    expect(cubit.state.googleCalendarSyncError, isNull);
    expect(settings.lastSync, isNotNull);
  });

  test(
    'selection changes during a sync do not restore deselected events',
    () async {
      final colorsStarted = Completer<void>();
      final releaseColors = Completer<void>();
      final requestedCalendars = <String>[];
      var holdColors = false;
      var colorRequests = 0;
      final (cubit, settings) = await build(
        _Google(
          handler: (request) async {
            if (request.url.path.contains('calendarList')) {
              if (holdColors && ++colorRequests == 1) {
                colorsStarted.complete();
                await releaseColors.future;
              }
              return _json({'items': []});
            }
            if (!holdColors) return _json({'items': []});
            final calendarId = request.url.pathSegments[3];
            requestedCalendars.add(calendarId);
            return _json({
              'items': [
                {
                  'id': 'event-$calendarId',
                  'summary': 'אירוע מ-$calendarId',
                  'start': {'date': '2026-10-05'},
                  'end': {'date': '2026-10-06'},
                },
              ],
            });
          },
        ),
      );
      // הסנכרון הראשון בעלייה מסתיים בשמירת זמן הסנכרון.
      while (settings.lastSync == null) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      holdColors = true;
      final olderSync = cubit.syncGoogleCalendar(interactive: false);
      await colorsStarted.future;
      await cubit.updateGoogleCalendarSelectedIds(['new-calendar']);
      await cubit.syncGoogleCalendar(interactive: false);
      final eventsAfterNewerSync = List<CustomEvent>.of(cubit.state.events);
      releaseColors.complete();
      await olderSync;

      expect(eventsAfterNewerSync.map((e) => e.title), [
        'אירוע מ-new-calendar',
      ]);
      expect(requestedCalendars, ['new-calendar', 'new-calendar']);
      expect(cubit.state.googleCalendarSelectedIds, ['new-calendar']);
      expect(cubit.state.events.map((e) => e.title), ['אירוע מ-new-calendar']);
      expect(
        (jsonDecode(settings.savedEventsJson) as List).map((e) => e['title']),
        ['אירוע מ-new-calendar'],
      );
    },
  );

  test('a calendar that fails to load is skipped', () async {
    final (cubit, _) = await build(
      _Google(handler: (request) async => _json({'error': 'boom'}, 500)),
    );

    await cubit.syncGoogleCalendar(interactive: false);

    expect(cubit.state.googleCalendarConnected, isTrue);
    expect(cubit.state.googleCalendarSyncError, isNull);
    expect(cubit.state.events, isEmpty);
  });

  test(
    'an event deleted in Google is removed by the sync (issue #3288)',
    () async {
      var deletedInGoogle = false;
      var listFails = false;
      final (cubit, settings) = await build(
        _Google(
          handler: (request) async {
            if (request.url.path.contains('calendarList')) {
              return _json({'items': []});
            }
            if (request.method == 'POST') return _json({'id': 'google-event'});
            if (listFails) return _json({'error': 'boom'}, 500);
            // כמו גוגל: אירוע שנמחק חוזר רק כשמבקשים את המחוקים.
            final showDeleted =
                request.url.queryParameters['showDeleted'] == 'true';
            return _json({
              'items': [
                if (deletedInGoogle && showDeleted)
                  {'id': 'google-event', 'status': 'cancelled'},
              ],
            });
          },
        ),
      );
      while (settings.lastSync == null) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await cubit.addEvent(
        title: 'פגישה',
        baseGregorianDate: DateTime.now(),
        recurrenceType: RecurrenceType.none,
      );
      expect(cubit.state.events.single.googleEventId, 'google-event');

      deletedInGoogle = true;
      listFails = true;
      await cubit.syncGoogleCalendar(interactive: false);
      expect(cubit.state.events, hasLength(1));

      listFails = false;
      await cubit.syncGoogleCalendar(interactive: false);

      expect(cubit.state.googleCalendarSyncError, isNull);
      expect(cubit.state.events, isEmpty);
      expect(jsonDecode(settings.savedEventsJson), isEmpty);
    },
  );

  test(
    'a recurring event is removed only when its whole series was deleted '
    'in Google (issue #3288)',
    () async {
      // מופע מבוטל נראה אותו דבר כשנמחק מופע אחד וכשנמחקה הסדרה.
      for (final (master, removed) in [
        (_json({'id': 'series', 'status': 'cancelled'}), true),
        (_json({'id': 'series', 'status': 'confirmed'}), false),
        (_json({'error': 'boom'}, 500), false),
      ]) {
        var deletedInGoogle = false;
        final (cubit, settings) = await build(
          _Google(
            handler: (request) async {
              if (request.url.path.contains('calendarList')) {
                return _json({'items': []});
              }
              if (request.method == 'POST') return _json({'id': 'series'});
              if (request.url.path.endsWith('/events/series')) return master;
              return _json({
                'items': [
                  if (deletedInGoogle)
                    {
                      'id': 'series_20271103',
                      'recurringEventId': 'series',
                      'status': 'cancelled',
                    },
                ],
              });
            },
          ),
        );
        while (settings.lastSync == null) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        await cubit.addEvent(
          title: 'יום הולדת',
          baseGregorianDate: DateTime.now(),
          recurrenceType: RecurrenceType.annualGregorian,
        );
        expect(cubit.state.events.single.googleEventId, 'series');

        deletedInGoogle = true;
        await cubit.syncGoogleCalendar(interactive: false);

        expect(cubit.state.events, hasLength(removed ? 0 : 1));
        expect(
          jsonDecode(settings.savedEventsJson),
          hasLength(removed ? 0 : 1),
        );
      }
    },
  );

  for (final recurring in [false, true]) {
    for (final failedPage in [1, 2]) {
      for (final activeFirst in [true, false]) {
        test(
          'partial sync preserves shared ${recurring ? 'series' : 'event'} '
          'and reminder (page $failedPage, active first: $activeFirst)',
          () async {
            var failActiveCalendar = false;
            var deletedInGoogle = false;
            var colorsFail = false;
            var revision = 0;
            var masterRequests = 0;
            String? localId;
            final date = DateTime.now().toIso8601String().split('T').first;
            final endDate = DateTime.now()
                .add(const Duration(days: 1))
                .toIso8601String()
                .split('T')
                .first;
            final googleId = recurring ? 'shared_instance' : 'shared';
            final (cubit, settings) = await build(
              _Google(
                handler: (request) async {
                  if (request.url.path.contains('calendarList')) {
                    return colorsFail
                        ? _json({'error': 'colors unavailable'}, 503)
                        : _json({'items': []});
                  }
                  if (request.method == 'POST') return _json({'id': 'shared'});
                  if (request.url.path.endsWith('/events/shared')) {
                    masterRequests++;
                    return _json({'id': 'shared', 'status': 'cancelled'});
                  }
                  final calendar = request.url.pathSegments[3];
                  if (calendar == 'primary') return _json({'items': []});
                  if (calendar == 'active') {
                    if (failedPage == 2 &&
                        request.url.queryParameters['pageToken'] == null) {
                      return _json({'items': [], 'nextPageToken': 'second'});
                    }
                    if (failActiveCalendar) {
                      return _json({'error': 'temporarily unavailable'}, 503);
                    }
                  }
                  return _json({
                    'items': [
                      {
                        'id': googleId,
                        if (recurring) 'recurringEventId': 'shared',
                        if (calendar != 'active' || deletedInGoogle)
                          'status': 'cancelled'
                        else ...{
                          'summary': 'Shared appointment',
                          'start': {'date': date},
                          'end': {'date': endDate},
                          'extendedProperties': {
                            'private': {'otzaria_event_id': localId},
                          },
                        },
                      },
                      if (calendar == 'removed-copy')
                        {
                          'id': 'other',
                          'summary': 'Other appointment $revision',
                          'start': {'date': date},
                          'end': {'date': endDate},
                        },
                    ],
                  });
                },
              ),
            );
            while (settings.lastSync == null) {
              await Future<void>.delayed(const Duration(milliseconds: 10));
            }
            await cubit.addEvent(
              title: 'Shared appointment',
              baseGregorianDate: DateTime.now(),
              recurrenceType: recurring
                  ? RecurrenceType.annualGregorian
                  : RecurrenceType.none,
              notificationMinutes: 17,
            );
            localId = cubit.state.events.single.id;
            await cubit.updateGoogleCalendarSelectedIds(
              activeFirst
                  ? ['active', 'removed-copy']
                  : ['removed-copy', 'active'],
            );
            await cubit.syncGoogleCalendar(interactive: false);
            expect(cubit.state.events, hasLength(2));

            failActiveCalendar = true;
            revision++;
            await cubit.syncGoogleCalendar(interactive: false);

            expect(cubit.state.events, hasLength(2));
            expect(
              cubit.state.events
                  .singleWhere((e) => e.id == localId)
                  .notificationMinutes,
              17,
            );
            expect(
              cubit.state.events.map((e) => e.title),
              contains('Other appointment 1'),
            );
            final saved = jsonDecode(settings.savedEventsJson) as List;
            expect(saved, hasLength(2));
            expect(
              saved.singleWhere(
                (e) => e['id'] == localId,
              )['notificationMinutes'],
              17,
            );
            expect(masterRequests, 0);

            failActiveCalendar = false;
            await cubit.syncGoogleCalendar(interactive: false);
            expect(
              cubit.state.events
                  .singleWhere((e) => e.id == localId)
                  .notificationMinutes,
              17,
            );

            deletedInGoogle = true;
            colorsFail = true;
            await cubit.syncGoogleCalendar(interactive: false);
            expect(cubit.state.events.map((e) => e.id), ['other']);
            expect(jsonDecode(settings.savedEventsJson), hasLength(1));
            expect(masterRequests, recurring ? 1 : 0);
          },
        );
      }
    }
  }

  test('a late insert response preserves its id for the next edit', () {
    fakeAsync((async) {
      final firstResponse = Completer<http.Response>();
      final methods = <String>[];
      final repository = GoogleCalendarRepository(
        _Google(
          handler: (request) async {
            methods.add(request.method);
            if (methods.length == 1) return firstResponse.future;
            return _json({'id': 'google-event'});
          },
        ),
      );
      final event = CustomEvent(
        id: 'local-event',
        title: 'פגישה',
        description: '',
        createdAt: DateTime(2026, 10, 18),
        baseGregorianDate: DateTime(2026, 10, 18),
        baseJewishYear: 5787,
        baseJewishMonth: 7,
        baseJewishDay: 7,
        recurrenceType: RecurrenceType.none,
      );
      String? googleId;
      var completed = false;
      repository.upsertEvent(event, 'Asia/Jerusalem').then((id) {
        googleId = id;
        completed = true;
      });
      async.flushMicrotasks();
      expect(methods, ['POST']);
      async.elapse(const Duration(seconds: 21));
      final completedBeforeResponse = completed;
      firstResponse.complete(_json({'id': 'google-event'}));
      async.flushMicrotasks();

      expect(completedBeforeResponse, isFalse);
      expect(completed, isTrue);
      expect(googleId, 'google-event');
      repository.upsertEvent(
        event.copyWith(title: 'פגישה מעודכנת', googleEventId: googleId),
        'Asia/Jerusalem',
      );
      async.flushMicrotasks();
      expect(methods, ['POST', 'PUT']);
    });
  });

  test('a stalled calendar list still times out', () {
    fakeAsync((async) {
      final response = Completer<http.Response>();
      final repository = GoogleCalendarRepository(
        _Google(handler: (_) => response.future),
      );
      List<GoogleCalendarInfo>? calendars;
      repository.listCalendars().then((result) => calendars = result);
      async.flushMicrotasks();
      expect(calendars, isNull);
      async.elapse(const Duration(seconds: 21));
      expect(calendars, isEmpty);
      response.complete(_json({'items': []}));
      async.flushMicrotasks();
    });
  });
}
