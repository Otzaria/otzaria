// תא היום בונה JewishCalendar אחד ומשתף אותו בין getDayBackgroundColor
// ל-DayExtras, ומשתמש ב-HebrewDateFormatter סטטי משותף. הטסטים כאן נועלים
// את שתי הנקודות הרגישות: ש-inIsrael של ה-JewishCalendar המועבר הוא שקובע,
// ושה-formatter המשותף אינו מזליג מועד מתא אחד לאחר.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/tools/calendar/services/google_calendar_service.dart';
import 'package:otzaria/tools/calendar/services/notification_service.dart';
import 'package:otzaria/tools/calendar/utils/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/widgets/calendar_day_cell.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../../../test_helpers/memory_cache_provider.dart';

/// כ"ג תשרי תשפ"ה — שמחת תורה בחו"ל בלבד (בארץ היא נחוגה בכ"ב).
final _simchasTorahChutz = DateTime(2024, 10, 25);

/// ז' טבת תשפ"ה — יום חול רגיל, ללא מועד.
final _plainWeekday = DateTime(2025, 1, 7);

/// שבת רגילה.
final _shabbat = DateTime(2025, 1, 4);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Jerusalem'));
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  late CalendarCubit cubit;

  setUp(() {
    cubit = CalendarCubit(
      notificationService: _FakeNotificationService(),
      googleCalendarService: _FakeGoogleCalendarService(),
    );
  });

  tearDown(() => cubit.close());

  Widget wrapExtras(List<Widget> children) => MaterialApp(
    home: BlocProvider.value(
      value: cubit,
      child: Scaffold(body: Column(children: children)),
    ),
  );

  DayExtras extrasFor(DateTime date, {required bool inIsrael}) => DayExtras(
    jewishCalendar: JewishCalendar.fromDateTime(date)..inIsrael = inIsrael,
    date: date,
    maxVisibleItems: 4,
  );

  group('getDayBackgroundColor — צובע לפי ה-JewishCalendar שהועבר', () {
    testWidgets('שבת מקבלת רקע, יום חול לא', (tester) async {
      Color? shabbatColor;
      Color? weekdayColor;
      Color? selectedColor;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              final shabbat = JewishCalendar.fromDateTime(_shabbat)
                ..inIsrael = true;
              final weekday = JewishCalendar.fromDateTime(_plainWeekday)
                ..inIsrael = true;
              shabbatColor = getDayBackgroundColor(
                context,
                shabbat,
                false,
                false,
              );
              weekdayColor = getDayBackgroundColor(
                context,
                weekday,
                false,
                false,
              );
              selectedColor = getDayBackgroundColor(
                context,
                shabbat,
                true,
                false,
              );
              return const SizedBox();
            },
          ),
        ),
      );

      expect(shabbatColor, isNotNull);
      expect(weekdayColor, isNull);
      expect(
        selectedColor,
        isNull,
        reason: 'תא נבחר מקבל את צבע הבחירה, לא את רקע המועד',
      );
    });
  });

  group('DayExtras — inIsrael מגיע מה-JewishCalendar המשותף', () {
    testWidgets('כ"ג תשרי: שמחת תורה בחו"ל בלבד', (tester) async {
      await tester.pumpWidget(
        wrapExtras([extrasFor(_simchasTorahChutz, inIsrael: false)]),
      );
      expect(find.text('שמחת תורה'), findsOneWidget);

      await tester.pumpWidget(
        wrapExtras([extrasFor(_simchasTorahChutz, inIsrael: true)]),
      );
      expect(
        find.text('שמחת תורה'),
        findsNothing,
        reason: 'בארץ שמחת תורה אינה בכ"ג תשרי',
      );
    });
  });

  group('buildDayCell — בונה את ה-JewishCalendar המשותף מ-state', () {
    Widget cellFor(bool inIsrael) => MaterialApp(
      home: BlocProvider.value(
        value: cubit,
        child: Scaffold(
          body: Builder(
            builder: (context) => SizedBox(
              width: 200,
              height: 200,
              child: buildDayCell(
                context,
                cubit.state.copyWith(inIsrael: inIsrael),
                _simchasTorahChutz,
                JewishDate.fromDateTime(_simchasTorahChutz),
                false,
                () {},
                () {},
              ),
            ),
          ),
        ),
      ),
    );

    testWidgets('state.inIsrael מגיע אל המועדים המוצגים בתא', (tester) async {
      await tester.pumpWidget(cellFor(false));
      expect(find.text('שמחת תורה'), findsOneWidget);

      await tester.pumpWidget(cellFor(true));
      expect(
        find.text('שמחת תורה'),
        findsNothing,
        reason: 'התא חייב לבנות את ה-JewishCalendar לפי state.inIsrael',
      );
    });
  });

  group('DayExtras — formatter סטטי משותף בין תאים', () {
    testWidgets('כל תא מציג את המועד שלו בלבד', (tester) async {
      await tester.pumpWidget(
        wrapExtras([
          extrasFor(_simchasTorahChutz, inIsrael: false),
          extrasFor(_plainWeekday, inIsrael: false),
        ]),
      );

      expect(
        find.text('שמחת תורה'),
        findsOneWidget,
        reason: 'המועד לא מוזלג לתא של יום החול',
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
