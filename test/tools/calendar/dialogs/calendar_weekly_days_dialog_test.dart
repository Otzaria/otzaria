import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/theme/app_seed_colors.dart';
import 'package:otzaria/theme/app_theme_data.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/dialogs/calendar_event_dialog.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';

import '../../../support/golden_fonts.dart';

void main() {
  setUpAll(loadGoldenFonts);

  for (final (name, brightness, seed) in [
    ('light', Brightness.light, AppSeedColors.defaultLight),
    ('dark', Brightness.dark, AppSeedColors.defaultDark),
    ('white', Brightness.light, AppSeedColors.white),
  ]) {
    for (final width in [360.0, 1200.0]) {
      for (final scale in [1.0, 1.3]) {
        testWidgets(
          '$name RTL width=$width scale=$scale saves selected weekdays',
          (
            tester,
          ) async {
            tester.view.physicalSize = Size(width, 900);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            final scheme = AppThemeData.createColorScheme(seed, brightness);
            final variant = AppThemeVariant.ofSeed(seed);
            final theme = brightness == Brightness.dark
                ? AppThemeData.dark(
                    scheme,
                    compactMenuMode: false,
                    variant: variant,
                  )
                : AppThemeData.light(
                    scheme,
                    compactMenuMode: false,
                    variant: variant,
                  );
            CalendarEventDialogResult? result;
            await tester.pumpWidget(
              MaterialApp(
                theme: theme,
                locale: const Locale('he', 'IL'),
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                supportedLocales: const [Locale('he', 'IL')],
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(scale),
                  ),
                  child: child!,
                ),
                home: Builder(
                  builder: (context) => Scaffold(
                    body: ActionButton.neutral(
                      text: 'פתח',
                      onPressed: () async {
                        result = await showCalendarEventDialog(
                          context: context,
                          state: CalendarState.initial(),
                          existingEvent: CustomEvent(
                            id: 'lesson',
                            title: 'שיעור שבועי',
                            description: '',
                            createdAt: DateTime(2026, 11, 1),
                            baseGregorianDate: DateTime(2026, 11, 2),
                            baseJewishYear: 5787,
                            baseJewishMonth: 8,
                            baseJewishDay: 22,
                            recurrenceType: RecurrenceType.weekly,
                            weeklyDays: const [
                              DateTime.monday,
                              DateTime.wednesday,
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            );
            await tester.tap(find.text('פתח'));
            await tester.pumpAndSettle();
            final monday = find.widgetWithText(FilterChip, 'ב׳');
            final tuesday = find.widgetWithText(FilterChip, 'ג׳');
            final wednesday = find.widgetWithText(FilterChip, 'ד׳');
            expect(find.byType(FilterChip), findsNWidgets(7));
            await tester.ensureVisible(monday);
            await tester.pumpAndSettle();
            expect(tester.widget<FilterChip>(monday).selected, isTrue);
            expect(tester.widget<FilterChip>(wednesday).selected, isTrue);
            expect(
              Directionality.of(tester.element(monday)),
              TextDirection.rtl,
            );
            await tester.tap(monday);
            await tester.pumpAndSettle();
            await tester.tap(wednesday);
            await tester.pumpAndSettle();
            expect(tester.widget<FilterChip>(wednesday).selected, isTrue);
            await tester.tap(tuesday);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tester.tap(find.text('שמור שינויים'));
            await tester.pumpAndSettle();
            expect(result?.weeklyDays, [DateTime.tuesday, DateTime.wednesday]);
            expect(tester.takeException(), isNull);
          },
          variant: TargetPlatformVariant.only(goldenPlatform),
        );
      }
    }
  }
}
