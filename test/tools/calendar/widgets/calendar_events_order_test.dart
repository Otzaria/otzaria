// סדר התצוגה של אירועי המשתמש — בפאנל האירועים ובתא היום שבלוח.
// האירועים חייבים להופיע לפי שעה, לא לפי סדר א-ב של הכותרת.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/theme/app_seed_colors.dart';
import 'package:otzaria/theme/app_theme_data.dart';
import 'package:otzaria/tools/calendar/services/google_calendar_service.dart';
import 'package:otzaria/tools/calendar/services/notification_service.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/widgets/calendar_day_cell.dart';
import 'package:otzaria/tools/calendar/widgets/calendar_events_panel.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../../test_helpers/memory_cache_provider.dart';

final _date = DateTime(2026, 8, 3);

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

class _InMemorySettingsRepository implements SettingsRepository {
  @override
  Future<void> updateCalendarEvents(String json) async {}

  @override
  Future<Map<String, dynamic>> loadSettings() async {
    return {
      'calendarType': 'combined',
      'selectedCity': 'ירושלים',
      'calendarEvents': '[]',
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
    };
  }

  @override
  String getCalendarEventNotificationIdsJson() => '[]';

  @override
  Future<void> updateCalendarEventNotificationIdsJson(String json) async {}

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// סדר ההופעה האנכי של כותרות נתונות במסך — לפי מיקום ה-Text בפועל.
List<String> _verticalOrder(WidgetTester tester, List<String> titles) {
  final located =
      titles
          .map((t) => (title: t, dy: tester.getTopLeft(find.text(t)).dy))
          .toList()
        ..sort((a, b) => a.dy.compareTo(b.dy));
  return located.map((e) => e.title).toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Jerusalem'));
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  late CalendarCubit cubit;

  setUp(() async {
    cubit = CalendarCubit(
      settingsRepository: _InMemorySettingsRepository(),
      notificationService: _FakeNotificationService(),
      googleCalendarService: _FakeGoogleCalendarService(),
    );
    await Future.delayed(const Duration(milliseconds: 100));
  });

  tearDown(() => cubit.close());

  Future<void> pumpEventsPanel(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: cubit,
          child: Scaffold(
            body: SizedBox(
              width: 600,
              height: 900,
              child: BlocBuilder<CalendarCubit, CalendarState>(
                builder: (context, state) => CalendarEventsPanel(
                  state: state,
                  onCreateEvent: ({existingEvent, specificDate}) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('CalendarEventsPanel — תצוגת יום נבחר', () {
    testWidgets('אירועים מוצגים לפי שעה ולא לפי א-ב', (tester) async {
      cubit.selectDate(JewishDate.fromDateTime(_date), _date);
      await cubit.addEvent(
        title: 'אירוע ערב',
        baseGregorianDate: _date,
        recurrenceType: RecurrenceType.none,
        eventTime: const TimeOfDay(hour: 21, minute: 0),
      );
      await cubit.addEvent(
        title: 'שיעור צהריים',
        baseGregorianDate: _date,
        recurrenceType: RecurrenceType.none,
        eventTime: const TimeOfDay(hour: 14, minute: 0),
      );

      await pumpEventsPanel(tester);

      expect(_verticalOrder(tester, ['אירוע ערב', 'שיעור צהריים']), [
        'שיעור צהריים',
        'אירוע ערב',
      ]);
      expect(find.text('14:00'), findsOneWidget);
      expect(find.text('21:00'), findsOneWidget);
    });

    testWidgets('אירוע ללא שעה מוצג ראשון, עם תווית "כל היום"', (tester) async {
      cubit.selectDate(JewishDate.fromDateTime(_date), _date);
      await cubit.addEvent(
        title: 'תענית',
        baseGregorianDate: _date,
        recurrenceType: RecurrenceType.none,
      );
      await cubit.addEvent(
        title: 'אאא בבוקר',
        baseGregorianDate: _date,
        recurrenceType: RecurrenceType.none,
        eventTime: const TimeOfDay(hour: 7, minute: 30),
      );

      await pumpEventsPanel(tester);

      expect(_verticalOrder(tester, ['תענית', 'אאא בבוקר']), [
        'תענית',
        'אאא בבוקר',
      ]);
      expect(find.text('כל היום'), findsOneWidget);
      expect(find.text('07:30'), findsOneWidget);
    });

    testWidgets('אין אירועים ביום זה — הודעה מתאימה', (tester) async {
      cubit.selectDate(JewishDate.fromDateTime(_date), _date);
      await pumpEventsPanel(tester);
      expect(find.text('אין אירועים ביום זה'), findsOneWidget);
    });
  });

  group('CalendarEventsPanel — תצוגת "הצג הכל"', () {
    testWidgets('כל האירועים מוצגים לפי תאריך ואז לפי שעה', (tester) async {
      await cubit.addEvent(
        title: 'מחר בבוקר',
        baseGregorianDate: DateTime(2026, 8, 4),
        recurrenceType: RecurrenceType.none,
        eventTime: const TimeOfDay(hour: 6, minute: 0),
      );
      await cubit.addEvent(
        title: 'היום בערב',
        baseGregorianDate: _date,
        recurrenceType: RecurrenceType.none,
        eventTime: const TimeOfDay(hour: 22, minute: 0),
      );
      await cubit.addEvent(
        title: 'היום בבוקר',
        baseGregorianDate: _date,
        recurrenceType: RecurrenceType.none,
        eventTime: const TimeOfDay(hour: 8, minute: 0),
      );
      cubit.setEventsView(CalendarEventsView.all);

      await pumpEventsPanel(tester);

      expect(_verticalOrder(tester, ['מחר בבוקר', 'היום בערב', 'היום בבוקר']), [
        'היום בבוקר',
        'היום בערב',
        'מחר בבוקר',
      ]);
    });
  });

  group('CalendarEventsPanel — חיפוש', () {
    testWidgets('תוצאות החיפוש מוצגות כרונולוגית', (tester) async {
      await cubit.addEvent(
        title: 'שיעור ב',
        baseGregorianDate: _date,
        recurrenceType: RecurrenceType.none,
        eventTime: const TimeOfDay(hour: 20, minute: 0),
      );
      await cubit.addEvent(
        title: 'שיעור א',
        baseGregorianDate: _date,
        recurrenceType: RecurrenceType.none,
        eventTime: const TimeOfDay(hour: 9, minute: 0),
      );
      cubit.setEventSearchQuery('שיעור');

      await pumpEventsPanel(tester);

      expect(_verticalOrder(tester, ['שיעור ב', 'שיעור א']), [
        'שיעור א',
        'שיעור ב',
      ]);
    });

    testWidgets('חיפוש בלי התאמות — הודעה מתאימה', (tester) async {
      await cubit.addEvent(
        title: 'שיעור',
        baseGregorianDate: _date,
        recurrenceType: RecurrenceType.none,
      );
      cubit.setEventSearchQuery('לא קיים');

      await pumpEventsPanel(tester);
      expect(find.text('לא נמצאו אירועים מתאימים'), findsOneWidget);
    });
  });

  group('CalendarEventsPanel — לחיצה על אירוע (issue #2494)', () {
    testWidgets('קופצת למופע הקרוב; עריכה ומחיקה לא קופצות', (tester) async {
      cubit.jumpToDate(_date);
      await cubit.addEvent(
        title: 'אירוע מסונכרן',
        baseGregorianDate: DateTime(2026, 10, 20),
        recurrenceType: RecurrenceType.none,
      );
      await cubit.updateEvent(
        cubit.state.events.single.copyWith(googleEventId: 'google-1'),
      );
      await cubit.addEvent(
        title: 'יום הולדת',
        baseGregorianDate: DateTime(2024, 9, 10),
        recurrenceType: RecurrenceType.annualGregorian,
      );
      await pumpEventsPanel(tester);
      await tester.tap(find.text('הכל'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('ערוך אירוע').first);
      await tester.tap(find.text('מחק').first);
      await tester.pumpAndSettle();
      expect(find.text('אישור מחיקה'), findsOneWidget);
      await tester.tap(find.text('ביטול'));
      await tester.pumpAndSettle();
      expect(cubit.state.selectedGregorianDate, _date);

      await tester.tap(find.text('יום הולדת'));
      await tester.pumpAndSettle();
      expect(cubit.state.selectedGregorianDate, DateTime(2026, 9, 10));

      await tester.tap(find.text('אירוע מסונכרן'));
      await tester.pumpAndSettle();
      expect(cubit.state.selectedGregorianDate, DateTime(2026, 10, 20));
      expect(cubit.state.currentGregorianDate, DateTime(2026, 10, 20));

      // שנתי עברי: בתשפ"ט ובתש"ץ אין ל' חשוון, והתא בלוח מציג אותו בתשצ"א.
      await cubit.addEvent(
        title: 'ל׳ חשוון',
        baseGregorianDate: DateTime(2024, 12, 1),
        recurrenceType: RecurrenceType.annualHebrew,
      );
      cubit.jumpToDate(DateTime(2028, 10, 1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ל׳ חשוון'));
      await tester.pumpAndSettle();
      final target = DateTime(2030, 11, 26);
      expect(cubit.state.selectedGregorianDate, target);
      expect(cubit.eventsForDate(target).map((e) => e.title), ['ל׳ חשוון']);
    });
  });

  group('DayExtras — אירועי תא היום', () {
    testWidgets('בתא נבחר נקודת אירוע נשארת קריאה', (tester) async {
      await cubit.addEvent(
        title: 'אירוע צבעוני',
        baseGregorianDate: _date,
        recurrenceType: RecurrenceType.none,
        colorIndex: 2,
      );

      final colorScheme = AppThemeData.createColorScheme(
        AppSeedColors.white,
        Brightness.dark,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppThemeData.dark(colorScheme, compactMenuMode: false),
          home: BlocProvider.value(
            value: cubit,
            child: Scaffold(
              body: DayExtras(
                jewishCalendar: JewishCalendar.fromDateTime(_date)
                  ..inIsrael = true,
                date: _date,
                maxVisibleItems: 1,
                isSelected: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final eventSpan = tester
          .widgetList<RichText>(find.byType(RichText))
          .map((richText) => richText.text as TextSpan)
          .singleWhere((span) => span.toPlainText().contains('אירוע צבעוני'));
      final contentSpan = eventSpan.children!.single as TextSpan;
      final dot = contentSpan.children!.whereType<TextSpan>().singleWhere(
        (span) => span.text == '• ',
      );
      expect(dot.style?.color, colorScheme.onPrimaryContainer);
    });

    testWidgets('כשיש יותר אירועים מהמקום — מוצגים המוקדמים בזמן', (
      tester,
    ) async {
      await cubit.addEvent(
        title: 'אאא בערב',
        baseGregorianDate: _date,
        recurrenceType: RecurrenceType.none,
        eventTime: const TimeOfDay(hour: 22, minute: 0),
      );
      await cubit.addEvent(
        title: 'ששש בבוקר',
        baseGregorianDate: _date,
        recurrenceType: RecurrenceType.none,
        eventTime: const TimeOfDay(hour: 8, minute: 0),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider.value(
            value: cubit,
            child: Scaffold(
              body: SizedBox(
                width: 200,
                child: DayExtras(
                  jewishCalendar: JewishCalendar.fromDateTime(_date)
                    ..inIsrael = true,
                  date: _date,
                  maxVisibleItems: 1,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('ששש בבוקר', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('אאא בערב', findRichText: true), findsNothing);
    });

    Widget extrasApp(int maxVisibleItems) => MaterialApp(
      home: BlocProvider.value(
        value: cubit,
        child: Scaffold(
          body: SizedBox(
            width: 200,
            child: DayExtras(
              jewishCalendar: JewishCalendar.fromDateTime(_date)
                ..inIsrael = true,
              date: _date,
              maxVisibleItems: maxVisibleItems,
            ),
          ),
        ),
      ),
    );

    Future<void> addEvents(int count) async {
      for (var i = 1; i <= count; i++) {
        await cubit.addEvent(
          title: 'אירוע $i',
          baseGregorianDate: _date,
          recurrenceType: RecurrenceType.none,
          eventTime: TimeOfDay(hour: 8 + i, minute: 0),
        );
      }
    }

    testWidgets('פריטים שלא נכנסו מסומנים ב-+N, ולחיצה מציגה את כולם', (
      tester,
    ) async {
      await addEvents(4);
      await tester.pumpWidget(extrasApp(2));
      await tester.pumpAndSettle();

      expect(find.textContaining('אירוע 2', findRichText: true), findsOne);
      expect(find.textContaining('אירוע 3', findRichText: true), findsNothing);
      expect(find.text('+2'), findsOneWidget);

      await tester.tap(find.text('+2'));
      await tester.pumpAndSettle();

      expect(find.text('כל הפריטים ביום'), findsOneWidget);
      for (var i = 1; i <= 4; i++) {
        expect(
          find.textContaining('אירוע $i', findRichText: true),
          findsAtLeast(1),
        );
      }
    });

    testWidgets('כשכל הפריטים נכנסים אין סימון +N', (tester) async {
      await addEvents(2);
      await tester.pumpWidget(extrasApp(2));
      await tester.pumpAndSettle();

      expect(find.textContaining('אירוע 2', findRichText: true), findsOne);
      expect(find.textContaining('+'), findsNothing);
    });

    testWidgets('+N מזוהה ככפתור ונפתח ב-Enter וב-Space', (tester) async {
      await addEvents(4);
      await tester.pumpWidget(extrasApp(2));
      await tester.pumpAndSettle();
      final semantics = tester.ensureSemantics();
      await tester.pump();
      try {
        expect(
          tester.getSemantics(find.text('+2')),
          matchesSemantics(
            label: '+2',
            tooltip: 'עוד 2 — הצגת כל הפריטים',
            isButton: true,
            isFocusable: true,
            hasFocusAction: true,
            hasTapAction: true,
          ),
        );
      } finally {
        semantics.dispose();
      }
      for (final key in [LogicalKeyboardKey.enter, LogicalKeyboardKey.space]) {
        Focus.of(tester.element(find.text('+2'))).requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
        expect(find.text('כל הפריטים ביום'), findsOneWidget);
        for (var i = 1; i <= 4; i++) {
          expect(
            find.textContaining('אירוע $i', findRichText: true),
            findsAtLeast(1),
          );
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.text('כל הפריטים ביום'), findsNothing);
      }
    });

    testWidgets('linesThatFit: תא גבוה מכיל יותר שורות, הגדלת טקסט פחות', (
      tester,
    ) async {
      late int small, tall, tallScaled;
      Widget probe(double scale) => MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Builder(
            builder: (context) {
              if (scale == 1) {
                small = DayExtras.linesThatFit(context, 30, compact: false);
                tall = DayExtras.linesThatFit(context, 120, compact: false);
              } else {
                tallScaled = DayExtras.linesThatFit(
                  context,
                  120,
                  compact: false,
                );
              }
              return const SizedBox();
            },
          ),
        ),
      );

      await tester.pumpWidget(probe(1));
      await tester.pumpWidget(probe(2));

      expect(small, greaterThanOrEqualTo(1));
      expect(tall, greaterThan(2), reason: 'תא גבוה לא מוגבל לשני פריטים');
      expect(tallScaled, lessThan(tall));
    });
  });

  group('buildDayCell — פריטים בתא לפי המקום', () {
    Widget cellApp({
      required double width,
      required double height,
      double textScale = 1,
      List<String> info = const [],
      VoidCallback? onTap,
      ThemeData? theme,
      TextDirection direction = TextDirection.ltr,
    }) => MaterialApp(
      theme: theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: Directionality(textDirection: direction, child: child!),
      ),
      home: BlocProvider.value(
        value: cubit,
        child: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => SizedBox(
                width: width,
                height: height,
                child: buildDayCell(
                  context,
                  cubit.state,
                  _date,
                  JewishDate.fromDateTime(_date),
                  false,
                  onTap ?? () {},
                  () {},
                  additionalInfoLines: info,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    Future<void> addLongEvents(int count) async {
      for (var i = 1; i <= count; i++) {
        await cubit.addEvent(
          title: 'אירוע $i עם כותרת ארוכה מאוד 2026 gjpqy',
          baseGregorianDate: _date,
          recurrenceType: RecurrenceType.none,
          eventTime: TimeOfDay(hour: 8 + i, minute: 0),
        );
      }
    }

    testWidgets('+N סופר את הפריטים שאינם מוצגים גם כשהוא מחליף שורה', (
      tester,
    ) async {
      await addLongEvents(6);
      final themes = [
        AppThemeData.light(
          AppThemeData.createColorScheme(
            AppSeedColors.defaultLight,
            Brightness.light,
          ),
          compactMenuMode: false,
        ),
        AppThemeData.dark(
          AppThemeData.createColorScheme(
            AppSeedColors.defaultDark,
            Brightness.dark,
          ),
          compactMenuMode: false,
        ),
        AppThemeData.light(
          AppThemeData.createColorScheme(AppSeedColors.white, Brightness.light),
          compactMenuMode: false,
          variant: AppThemeVariant.white,
        ),
      ];
      for (final theme in themes) {
        for (final scale in [1.0, 1.3]) {
          for (final width in [56.0, 68.0, 150.0]) {
            for (final height in [70.0, 110.0, 200.0]) {
              for (final info in [
                const <String>[],
                const ['זריחה 06:12', 'שקיעה 19:45'],
              ]) {
                await tester.pumpWidget(
                  cellApp(
                    width: width,
                    height: height,
                    textScale: scale,
                    info: info,
                    theme: theme,
                    direction: TextDirection.rtl,
                  ),
                );
                await tester.pumpAndSettle();
                final visible = find
                    .byWidgetPredicate(
                      (widget) =>
                          widget is Text &&
                          ((widget.textSpan?.toPlainText().contains('אירוע ') ??
                                  false) ||
                              info.contains(widget.data)),
                    )
                    .evaluate()
                    .length;
                final hidden = 6 + info.length - visible;
                final more = find.textContaining(RegExp(r'^\+\d+$'));
                final scenario =
                    'width=$width height=$height scale=$scale info=${info.length}';
                if (hidden == 0) {
                  expect(more, findsNothing, reason: scenario);
                } else {
                  expect(more, findsOneWidget, reason: scenario);
                  expect(
                    tester.widget<Text>(more).data,
                    '+$hidden',
                    reason: scenario,
                  );
                  expect(
                    find.byTooltip('עוד $hidden — הצגת כל הפריטים'),
                    findsOneWidget,
                  );
                }
                expect(tester.takeException(), isNull, reason: scenario);
              }
            }
          }
        }
      }
    });

    testWidgets('אין גלישה בגדלים ובהגדלות טקסט שונים', (tester) async {
      await addLongEvents(8);
      final overflows = <String>[];
      for (final textScale in [1.0, 1.3, 2.0]) {
        // בהגדלה 2.0 כותרת התאריך עצמה גולשת ברוחב צר מ-80, בלי קשר לפריטים.
        for (final width in [if (textScale < 2) 56.0, 80.0, 150.0]) {
          for (var height = 70.0; height <= 200; height += 3.5) {
            for (final info in [
              const <String>[],
              const ['זריחה 06:12', 'שקיעה 19:45'],
            ]) {
              await tester.pumpWidget(
                cellApp(
                  width: width,
                  height: height,
                  textScale: textScale,
                  info: info,
                ),
              );
              final error = tester.takeException();
              if (error != null) {
                overflows.add('scale=$textScale w=$width h=$height: $error');
              }
            }
          }
        }
      }
      expect(overflows, isEmpty);
    });

    testWidgets('לחיצה על +N פותחת את החלונית בלי לבחור את היום', (
      tester,
    ) async {
      await addLongEvents(6);
      var cellTaps = 0;
      await tester.pumpWidget(
        cellApp(width: 150, height: 110, onTap: () => cellTaps++),
      );
      await tester.pumpAndSettle();

      final more = find.textContaining(RegExp(r'^\+\d+$'));
      expect(more, findsOneWidget);
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(find.text('כל הפריטים ביום'), findsOneWidget);
      expect(cellTaps, 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('כל הפריטים ביום'), findsNothing);

      await tester.tap(
        find.textContaining('אירוע 1', findRichText: true).first,
      );
      expect(cellTaps, 1);
    });
  });
}
