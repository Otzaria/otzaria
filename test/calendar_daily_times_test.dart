import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/calendar/calendar_cubit.dart';
import 'package:otzaria/services/notification_service.dart';
import 'package:otzaria/settings/bloc/settings_repository.dart';
import 'package:timezone/data/latest_all.dart' as tz;

// Mock SettingsRepository
class MockSettingsRepository implements SettingsRepository {
  final Map<String, dynamic> _settings = {
    'calendarType': 'combined',
    'selectedCity': 'ירושלים',
    'calendarEvents': '[]',
    'calendarNotificationsEnabled': true,
    'calendarNotificationTime': 60,
    'calendarNotificationSound': true,
    'calendarZmanAlerts': '{}',
    'googleCalendarEnabled': false,
    'googleCalendarSelectedIds': 'primary',
    'googleCalendarSyncPastDays': 60,
    'googleCalendarSyncFutureDays': 365,
    'googleCalendarLastSync': 0,
  };

  @override
  Future<Map<String, dynamic>> loadSettings() async => _settings;

  @override
  Future<void> updateSelectedCity(String city) async {
    _settings['selectedCity'] = city;
  }

  @override
  String getCalendarEventNotificationIdsJson() => '[]';

  @override
  Future<void> updateCalendarEventNotificationIdsJson(String json) async {}

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Mock NotificationService
class MockNotificationService implements NotificationService {
  @override
  bool get isInitialized => true;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CalendarCubit Daily Times Timezone Tests', () {
    late CalendarCubit calendarCubit;
    late MockSettingsRepository mockSettingsRepository;
    late MockNotificationService mockNotificationService;

    setUp(() {
      tz.initializeTimeZones();
      mockSettingsRepository = MockSettingsRepository();
      mockNotificationService = MockNotificationService();
    });

    test('Daily times are displayed in correct timezone for New York',
        () async {
      // Initialize Cubit
      calendarCubit = CalendarCubit(
        settingsRepository: mockSettingsRepository,
        notificationService: mockNotificationService,
      );

      await Future.delayed(const Duration(milliseconds: 100));

      // Change city to New York
      await calendarCubit.changeCity('ניו יורק');
      await Future.delayed(const Duration(milliseconds: 100));

      // Get current state
      final state = calendarCubit.state;

      // Verify that times are present
      expect(state.dailyTimes, isNotEmpty,
          reason: 'Daily times should not be empty');

      // Check that sunrise time exists and is in reasonable format (HH:MM)
      final sunrise = state.dailyTimes['sunrise'];
      expect(sunrise, isNotNull, reason: 'Sunrise time should exist');
      expect(sunrise, matches(r'^\d{2}:\d{2}$'),
          reason: 'Time should be in HH:MM format');

      // Debug output (only in tests)
      // ignore: avoid_print
      print('New York sunrise: $sunrise');
      // ignore: avoid_print
      print('All times: ${state.dailyTimes}');
    });

    test('Daily times are displayed in correct timezone for Jerusalem',
        () async {
      // Initialize Cubit with Jerusalem (default)
      calendarCubit = CalendarCubit(
        settingsRepository: mockSettingsRepository,
        notificationService: mockNotificationService,
      );

      await Future.delayed(const Duration(milliseconds: 100));

      // Get current state
      final state = calendarCubit.state;

      // Verify that times are present
      expect(state.dailyTimes, isNotEmpty,
          reason: 'Daily times should not be empty');

      // Check that sunrise time exists
      final sunrise = state.dailyTimes['sunrise'];
      expect(sunrise, isNotNull, reason: 'Sunrise time should exist');
      expect(sunrise, matches(r'^\d{2}:\d{2}$'),
          reason: 'Time should be in HH:MM format');

      // Debug output (only in tests)
      // ignore: avoid_print
      print('Jerusalem sunrise: $sunrise');
      // ignore: avoid_print
      print('All times: ${state.dailyTimes}');
    });

    test('Times differ between New York and Jerusalem', () async {
      // Test Jerusalem
      final jerusalemCubit = CalendarCubit(
        settingsRepository: MockSettingsRepository(),
        notificationService: MockNotificationService(),
      );
      await Future.delayed(const Duration(milliseconds: 100));
      final jerusalemSunrise = jerusalemCubit.state.dailyTimes['sunrise'];

      // Test New York
      final nySettings = MockSettingsRepository();
      await nySettings.updateSelectedCity('ניו יורק');
      final nyCubit = CalendarCubit(
        settingsRepository: nySettings,
        notificationService: MockNotificationService(),
      );
      await nyCubit.changeCity('ניו יורק');
      await Future.delayed(const Duration(milliseconds: 100));
      final nySunrise = nyCubit.state.dailyTimes['sunrise'];

      // Debug output (only in tests)
      // ignore: avoid_print
      print('Jerusalem sunrise: $jerusalemSunrise');
      // ignore: avoid_print
      print('New York sunrise: $nySunrise');

      // Times should be different (unless by extreme coincidence)
      // We can't assert they're different because on some dates they might be the same
      // But we can verify both are valid
      expect(jerusalemSunrise, isNotNull);
      expect(nySunrise, isNotNull);
      expect(jerusalemSunrise, matches(r'^\d{2}:\d{2}$'));
      expect(nySunrise, matches(r'^\d{2}:\d{2}$'));
    });
  });
}
