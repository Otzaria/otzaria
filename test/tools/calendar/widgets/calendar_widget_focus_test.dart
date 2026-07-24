import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/tools/calendar/services/google_calendar_service.dart';
import 'package:otzaria/tools/calendar/services/notification_service.dart';
import 'package:otzaria/tools/calendar/calendar_screen.dart';
import '../../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Jerusalem'));
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  group('CalendarWidget focus refresh', () {
    late CalendarCubit calendarCubit;
    late SettingsBloc settingsBloc;
    late FocusNode outsideFocusNode;

    setUp(() {
      settingsBloc = SettingsBloc(repository: SettingsRepository())
        ..add(LoadSettings());
      calendarCubit = CalendarCubit(
        notificationService: _FakeNotificationService(),
        googleCalendarService: _FakeGoogleCalendarService(),
      );
      outsideFocusNode = FocusNode(debugLabel: 'outside-focus');
    });

    tearDown(() {
      outsideFocusNode.dispose();
      settingsBloc.close();
      calendarCubit.close();
    });

    testWidgets('arrow navigation resumes after requesting focus again', (
      tester,
    ) async {
      final calendarKey = GlobalKey<CalendarWidgetState>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MultiBlocProvider(
              providers: [
                BlocProvider.value(value: settingsBloc),
                BlocProvider.value(value: calendarCubit),
              ],
              child: Column(
                children: [
                  Expanded(
                    child: CalendarWidget(key: calendarKey),
                  ),
                  Focus(
                    focusNode: outsideFocusNode,
                    child: const SizedBox(width: 1, height: 1),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final initialDate = calendarCubit.state.selectedGregorianDate;

      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();

      final dateAfterFirstArrow = calendarCubit.state.selectedGregorianDate;
      expect(dateAfterFirstArrow, isNot(initialDate));

      outsideFocusNode.requestFocus();
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();

      final dateWithoutCalendarFocus =
          calendarCubit.state.selectedGregorianDate;
      expect(dateWithoutCalendarFocus, dateAfterFirstArrow);

      calendarKey.currentState!.requestKeyboardFocus();
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();

      final dateAfterRefocus = calendarCubit.state.selectedGregorianDate;
      expect(dateAfterRefocus, isNot(dateWithoutCalendarFocus));
    });

    testWidgets('invalid shortcut does not bind to key A', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MultiBlocProvider(
              providers: [
                BlocProvider.value(value: settingsBloc),
                BlocProvider.value(value: calendarCubit),
              ],
              child: const CalendarWidget(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final shiftedDate = calendarCubit.state.selectedGregorianDate.add(
        const Duration(days: 5),
      );
      calendarCubit.jumpToDate(shiftedDate);
      await tester.pumpAndSettle();

      await Settings.setValue<String>(
        'key-shortcut-calendar-today',
        'not-a-shortcut',
      );
      settingsBloc.add(LoadSettings());
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      await tester.pump();

      expect(calendarCubit.state.selectedGregorianDate, shiftedDate);
    });
  });
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
