import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'package:otzaria/tools/calendar/services/google_calendar_service.dart';
import 'package:otzaria/tools/calendar/services/notification_service.dart';
import 'package:otzaria/tools/calendar/utils/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/widgets/calendar_main_panel.dart';

import '../../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Jerusalem'));
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  late _RecordingCalendarCubit cubit;

  setUp(() {
    cubit = _RecordingCalendarCubit();
  });

  tearDown(() async {
    await cubit.close();
  });

  Future<void> pumpPanel(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider<CalendarCubit>.value(
            value: cubit,
            child: BlocBuilder<CalendarCubit, CalendarState>(
              bloc: cubit,
              builder: (context, state) => CalendarMainPanel(
                state: state,
                onCreateEvent: ({existingEvent, specificDate}) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('החלקה מעלה קוראת ל-next()', (tester) async {
    await pumpPanel(tester);

    await tester.fling(
      find.byType(CalendarMainPanel),
      const Offset(0, -300),
      1000,
    );
    await tester.pumpAndSettle();

    expect(cubit.nextCount, 1);
    expect(cubit.previousCount, 0);
  });

  testWidgets('החלקה מטה קוראת ל-previous()', (tester) async {
    await pumpPanel(tester);

    await tester.fling(
      find.byType(CalendarMainPanel),
      const Offset(0, 300),
      1000,
    );
    await tester.pumpAndSettle();

    expect(cubit.previousCount, 1);
    expect(cubit.nextCount, 0);
  });

  testWidgets('גרירה איטית מתחת לסף המהירות לא מנווטת', (tester) async {
    await pumpPanel(tester);

    await tester.drag(find.byType(CalendarMainPanel), const Offset(0, -300));
    await tester.pumpAndSettle();

    expect(cubit.nextCount, 0);
    expect(cubit.previousCount, 0);
  });
}

/// Cubit שמונה קריאות next()/previous() לאימות המחווה.
class _RecordingCalendarCubit extends CalendarCubit {
  int nextCount = 0;
  int previousCount = 0;

  _RecordingCalendarCubit()
    : super(
        notificationService: _FakeNotificationService(),
        googleCalendarService: _FakeGoogleCalendarService(),
      );

  @override
  void next() => nextCount++;

  @override
  void previous() => previousCount++;
}

class _FakeNotificationService implements NotificationService {
  bool _initialized = false;

  @override
  bool get isInitialized => _initialized;

  @override
  bool get hasPermissions => true;

  @override
  Future<void> init() async {
    _initialized = true;
  }

  @override
  Future<bool> checkPermissions() async => true;

  @override
  Future<bool> requestPermissions() async => true;

  @override
  Future<bool> forceRequestPermissions() async => true;

  @override
  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime eventDate,
    required int reminderMinutes,
    bool soundEnabled = true,
  }) async {}

  @override
  Future<void> cancelNotification(int id) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }
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
