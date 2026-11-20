// לוח שנה ברוחב צר ובגובה נמוך (סעיף 19, החלטת הבעלים ב): מתחת ל-600 בגובה
// החלונית שלצד הלוח מוסתרת כברירת מחדל והלוח מקבל את כל הגובה; הכפתורים
// בסרגל מציגים אותה.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/tools/calendar/calendar_screen.dart';
import 'package:otzaria/tools/calendar/widgets/calendar_main_panel.dart';
import 'package:otzaria/tools/calendar/widgets/calendar_side_panel.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../../test_helpers/memory_cache_provider.dart';
import 'support/calendar_cubit_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Jerusalem'));
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  late CalendarCubit cubit;
  late SettingsBloc settings;

  setUp(() {
    settings = SettingsBloc(repository: SettingsRepository())
      ..add(LoadSettings());
    cubit = CalendarCubit(
      notificationService: FakeNotificationService(),
      googleCalendarService: FakeGoogleCalendarService(),
    );
  });

  tearDown(() async {
    await cubit.close();
    await settings.close();
  });

  Future<void> pump(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider.value(value: settings),
              BlocProvider.value(value: cubit),
            ],
            child: const CalendarWidget(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> resize(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
  }

  testWidgets('320×400: החלונית מוסתרת והלוח תופס את כל הגובה', (tester) async {
    await pump(tester, const Size(320, 400));

    expect(find.byType(CalendarSidePanel), findsNothing);
    final main = tester.getSize(find.byType(CalendarMainPanel));
    // מתחת לסרגל העליון; לפני כן הלוח קיבל 3/5 מהגובה הזה בלבד.
    expect(main.height, greaterThan(400 * 0.6));
    await unmount(tester);
  });

  testWidgets('הסף: מתחת ל-600 מוסתרת, מ-600 מוצגת, ובלי גלישה בשני המצבים', (
    tester,
  ) async {
    await pump(tester, const Size(320, 599));
    expect(find.byType(CalendarSidePanel), findsNothing);

    // הסף 600 (במקום 450): מתחתיו הפריסה המוערמת גולשת בתאי היום גם
    // כשהחלונית מוצגת (נמדד: אין גלישה מ-600 ומעלה). בלי takeException,
    // כך שגלישה כאן היא כשל.
    await resize(tester, const Size(320, 600));
    expect(find.byType(CalendarSidePanel), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('גובה נמוך: כפתור האירועים מציג את החלונית ושוב מסתיר', (
    tester,
  ) async {
    await pump(tester, const Size(320, 400));

    await tester.tap(find.byTooltip('אירועים').first);
    await tester.pumpAndSettle();
    expect(find.byType(CalendarSidePanel), findsOneWidget);

    await tester.tap(find.byTooltip('אירועים').first);
    await tester.pumpAndSettle();
    expect(find.byType(CalendarSidePanel), findsNothing);
    await unmount(tester);
  });

  testWidgets('הגדלת הגובה מציגה את החלונית, והקטנה מסתירה אותה שוב', (
    tester,
  ) async {
    await pump(tester, const Size(320, 400));
    expect(find.byType(CalendarSidePanel), findsNothing);

    await resize(tester, const Size(320, 700));
    expect(find.byType(CalendarSidePanel), findsOneWidget);

    await resize(tester, const Size(320, 400));
    expect(find.byType(CalendarSidePanel), findsNothing);
    await unmount(tester);
  });

  testWidgets('גובה נמוך אך רוחב מספיק: הפריסה לא משתנה', (tester) async {
    await pump(tester, const Size(1100, 400));

    expect(find.byType(CalendarSidePanel), findsOneWidget);
    await unmount(tester);
  });
}
