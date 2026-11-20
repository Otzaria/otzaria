import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/tools/calendar/calendar_screen.dart';
import 'package:otzaria/tools/calendar/services/google_calendar_service.dart';
import 'package:otzaria/tools/calendar/services/notification_service.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../../../test_helpers/memory_cache_provider.dart';

/// מקשי ניווט חודש/שנה בלוח השנה: Ctrl+חצים (המקורי) ו-PageUp/PageDown
/// (חלופה לכל הפלטפורמות; ב-macOS Ctrl+חצים הם קיצורי המערכת).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Jerusalem'));
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  late CalendarCubit cubit;
  late SettingsBloc settingsBloc;

  setUp(() {
    settingsBloc = SettingsBloc(repository: SettingsRepository())
      ..add(LoadSettings());
    cubit = CalendarCubit(
      notificationService: _FakeNotificationService(),
      googleCalendarService: _FakeGoogleCalendarService(),
    );
  });

  tearDown(() async {
    await settingsBloc.close();
    await cubit.close();
  });

  Widget host({Widget? above}) => MaterialApp(
    home: Scaffold(
      body: MultiBlocProvider(
        providers: [
          BlocProvider.value(value: settingsBloc),
          BlocProvider.value(value: cubit),
        ],
        child: above == null
            ? const CalendarWidget()
            : Column(
                children: [
                  above,
                  const Expanded(child: CalendarWidget()),
                ],
              ),
      ),
    ),
  );

  Future<void> pumpAt(WidgetTester tester, DateTime date) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    cubit.jumpToDate(date);
    await tester.pumpAndSettle();
  }

  Future<void> press(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    List<LogicalKeyboardKey> modifiers = const [],
  }) async {
    for (final m in modifiers) {
      await tester.sendKeyDownEvent(m);
    }
    await tester.sendKeyDownEvent(key);
    await tester.pump();
    await tester.sendKeyUpEvent(key);
    for (final m in modifiers.reversed) {
      await tester.sendKeyUpEvent(m);
    }
    await tester.pump();
  }

  final start = DateTime(2026, 6, 15);

  group('calendar month/year keys', () {
    testWidgets('PageDown moves one month forward, PageUp one back', (
      tester,
    ) async {
      await pumpAt(tester, start);
      await press(tester, LogicalKeyboardKey.pageDown);
      expect(cubit.state.selectedGregorianDate, DateTime(2026, 7, 15));
      await press(tester, LogicalKeyboardKey.pageUp);
      await press(tester, LogicalKeyboardKey.pageUp);
      expect(cubit.state.selectedGregorianDate, DateTime(2026, 5, 15));
    });

    testWidgets('Shift+PageDown moves one year forward, Shift+PageUp back', (
      tester,
    ) async {
      await pumpAt(tester, start);
      await press(
        tester,
        LogicalKeyboardKey.pageDown,
        modifiers: [LogicalKeyboardKey.shiftLeft],
      );
      expect(cubit.state.selectedGregorianDate, DateTime(2027, 6, 15));
      await press(
        tester,
        LogicalKeyboardKey.pageUp,
        modifiers: [LogicalKeyboardKey.shiftLeft],
      );
      await press(
        tester,
        LogicalKeyboardKey.pageUp,
        modifiers: [LogicalKeyboardKey.shiftLeft],
      );
      expect(cubit.state.selectedGregorianDate, DateTime(2025, 6, 15));
    });

    testWidgets('Ctrl+arrows still navigate month and year', (tester) async {
      await pumpAt(tester, start);
      await press(
        tester,
        LogicalKeyboardKey.arrowLeft,
        modifiers: [LogicalKeyboardKey.controlLeft],
      );
      expect(cubit.state.selectedGregorianDate, DateTime(2026, 7, 15));
      await press(
        tester,
        LogicalKeyboardKey.arrowRight,
        modifiers: [LogicalKeyboardKey.controlLeft],
      );
      expect(cubit.state.selectedGregorianDate, DateTime(2026, 6, 15));
      await press(
        tester,
        LogicalKeyboardKey.arrowUp,
        modifiers: [LogicalKeyboardKey.controlLeft],
      );
      expect(cubit.state.selectedGregorianDate, DateTime(2027, 6, 15));
    });

    testWidgets('page keys do nothing while a text field has focus', (
      tester,
    ) async {
      final fieldFocus = FocusNode();
      addTearDown(fieldFocus.dispose);
      await tester.pumpWidget(host(above: TextField(focusNode: fieldFocus)));
      await tester.pumpAndSettle();
      cubit.jumpToDate(start);
      fieldFocus.requestFocus();
      await tester.pumpAndSettle();
      expect(fieldFocus.hasPrimaryFocus, isTrue);
      await press(tester, LogicalKeyboardKey.pageDown);
      expect(cubit.state.selectedGregorianDate, start);
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
  Future<void> cancelNotifications(Iterable<int> ids) async {}

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
