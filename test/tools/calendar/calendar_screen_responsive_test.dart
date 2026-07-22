// טסטים לפריסה הרספונסיבית של CalendarWidget:
// - מסך רחב (≥840): פריסה זה-לצד-זה (AdaptiveSidePane).
// - מסך צר (<600): פריסה מוערמת — לוח למעלה, חלונית זמנים/אירועים למטה.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/tools/calendar/calendar_screen.dart';
import 'package:otzaria/tools/calendar/services/google_calendar_service.dart';
import 'package:otzaria/tools/calendar/services/notification_service.dart';
import 'package:otzaria/tools/calendar/widgets/calendar_main_panel.dart';
import 'package:otzaria/tools/calendar/widgets/calendar_side_panel.dart';

import '../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Jerusalem'));
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  late CalendarCubit calendarCubit;
  late SettingsBloc settingsBloc;

  setUp(() {
    settingsBloc = SettingsBloc(repository: SettingsRepository())
      ..add(LoadSettings());
    calendarCubit = CalendarCubit(
      notificationService: _FakeNotificationService(),
      googleCalendarService: _FakeGoogleCalendarService(),
    );
  });

  tearDown(() async {
    await calendarCubit.close();
    await settingsBloc.close();
  });

  Future<void> pumpCalendar(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

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
  }

  group('CalendarWidget — פריסה רספונסיבית', () {
    testWidgets('מסך צר (<600): הלוח למעלה והחלונית למטה (מוערם)', (
      tester,
    ) async {
      await pumpCalendar(tester, const Size(580, 1000));

      // שני הרכיבים מוצגים גם יחד במסך צר.
      expect(find.byType(CalendarMainPanel), findsOneWidget);
      expect(find.byType(CalendarSidePanel), findsOneWidget);

      final mainBottom = tester
          .getBottomLeft(find.byType(CalendarMainPanel))
          .dy;
      final sideTop = tester.getTopLeft(find.byType(CalendarSidePanel)).dy;

      // החלונית מתחת ללוח (פריסה מוערמת).
      expect(
        sideTop,
        greaterThanOrEqualTo(mainBottom - 1),
        reason:
            'CalendarSidePanel צריך להופיע מתחת ל-CalendarMainPanel '
            'במסך צר (פריסה מוערמת בעמודה).',
      );
    });

    testWidgets('מסך צר: שני הפאנלים חולקים את אותו הציר האופקי', (
      tester,
    ) async {
      // וידוא שהם אחד מעל השני, לא זה-לצד-זה.
      await pumpCalendar(tester, const Size(580, 1000));

      final mainLeft = tester.getTopLeft(find.byType(CalendarMainPanel)).dx;
      final sideLeft = tester.getTopLeft(find.byType(CalendarSidePanel)).dx;

      // ב-stacked layout שני הפאנלים מתחילים מאותו x (בלי הזחה).
      // ב-side-by-side הם היו מופרדים אופקית.
      expect(
        (mainLeft - sideLeft).abs(),
        lessThan(20),
        reason:
            'במסך צר שני הפאנלים אמורים להתחיל מאותו x (מוערמים '
            'אנכית), לא זה לצד זה.',
      );
    });

    testWidgets('מסך רחב (≥840): שני הפאנלים זה-לצד-זה', (tester) async {
      await pumpCalendar(tester, const Size(1200, 800));

      expect(find.byType(CalendarMainPanel), findsOneWidget);
      expect(find.byType(CalendarSidePanel), findsOneWidget);

      final mainRect = tester.getRect(find.byType(CalendarMainPanel));
      final sideRect = tester.getRect(find.byType(CalendarSidePanel));

      expect(
        mainRect.right <= sideRect.left || sideRect.right <= mainRect.left,
        isTrue,
        reason: 'במסך רחב הפאנלים צריכים לתפוס אזורים אופקיים נפרדים.',
      );
    });

    testWidgets('מסך רחב: הפאנלים מופרדים אופקית', (tester) async {
      await pumpCalendar(tester, const Size(1200, 800));

      final mainLeft = tester.getTopLeft(find.byType(CalendarMainPanel)).dx;
      final sideLeft = tester.getTopLeft(find.byType(CalendarSidePanel)).dx;

      expect(
        (mainLeft - sideLeft).abs(),
        greaterThan(100),
        reason: 'במסך רחב הפאנלים אמורים להיות מופרדים אופקית.',
      );
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
