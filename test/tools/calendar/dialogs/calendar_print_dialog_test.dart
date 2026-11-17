import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_frame.dart';
import 'package:otzaria/tools/calendar/helpers/calendar_print_options.dart';
import 'package:otzaria/tools/calendar/helpers/zmanim_helpers.dart';
import 'package:otzaria/tools/calendar/dialogs/calendar_print_dialog.dart';
import 'package:otzaria/tools/calendar/dialogs/calendar_print_zmanim_picker.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';

import '../../../test_helpers/memory_cache_provider.dart';

void main() {
  Future<void> pumpDialog(
    WidgetTester tester,
    CalendarView view, {
    Set<String> enabledZmanim = const {},
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: CalendarPrintDialog(
            calendarView: view,
            enabledZmanim: enabledZmanim,
          ),
        ),
      ),
    );
  }

  double sliderMax(WidgetTester tester) =>
      tester.widget<Slider>(find.byType(Slider)).max;

  group('CalendarPrintDialog — תקרות טווח ההדפסה (issue #961)', () {
    testWidgets('חודשים: עד 24 — מכסה שנה מעוברת (13) וטווח כולל (14)', (
      tester,
    ) async {
      await pumpDialog(tester, CalendarView.month);
      expect(sliderMax(tester), 24);
    });

    testWidgets('שבועות: עד 55 — מכסה שנה מעוברת ארוכה (385 ימים)', (
      tester,
    ) async {
      await pumpDialog(tester, CalendarView.week);
      expect(sliderMax(tester), 55);
    });

    testWidgets('ימים: עד 62 — שני חודשים מלאים', (tester) async {
      await pumpDialog(tester, CalendarView.day);
      expect(sliderMax(tester), 62);
    });

    testWidgets('גרירת המחוון למקסימום ואישור מחזירים את הכמות שנבחרה', (
      tester,
    ) async {
      int? returned;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    returned = await showCalendarPrintDialog(
                      context: context,
                      calendarView: CalendarView.month,
                    );
                  },
                  child: const Text('פתח'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('פתח'));
      await tester.pumpAndSettle();

      final slider = find.byType(Slider);
      await tester.drag(slider, const Offset(500, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('הדפס'));
      await tester.pumpAndSettle();

      expect(returned, 24);
    });
  });

  group('CalendarPrintDialog — זמני היום להדפסה', () {
    setUpAll(() async {
      await Settings.init(cacheProvider: MemoryCacheProvider());
    });
    setUp(() => CalendarPrintZmanimStore.save(null));

    Future<void> pumpTall(
      WidgetTester tester,
      CalendarView view, {
      Set<String> enabledZmanim = const {},
    }) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpDialog(tester, view, enabledZmanim: enabledZmanim);
      await tester.pumpAndSettle();
    }

    /// כמה תיבות מסומנות ברשימה.
    int checkedCount(WidgetTester tester) => tester
        .widgetList<Checkbox>(find.byType(Checkbox))
        .where((c) => c.value == true)
        .length;

    Finder zmanimSwitch() => find.descendant(
      of: find.byType(CalendarPrintZmanimPicker),
      matching: find.byType(Switch),
    );

    Future<void> turnOn(WidgetTester tester) async {
      await tester.tap(zmanimSwitch());
      await tester.pumpAndSettle();
    }

    testWidgets(
      'כבוי כברירת מחדל: רק המתג, בלי רשימה וכפתורים, ולא נשמר דבר',
      (
        tester,
      ) async {
        await pumpTall(tester, CalendarView.month);
        expect(tester.widget<Switch>(zmanimSwitch()).value, isFalse);
        expect(find.byType(Checkbox), findsNothing);
        expect(find.text('נקה בחירה'), findsNothing);
        await tester.tap(find.text('הדפס'));
        await tester.pumpAndSettle();
        expect(CalendarPrintZmanimStore.load(), isNull);
      },
    );

    for (final view in CalendarView.values) {
      testWidgets('כבוי: בלי טקסט הסבר מתחת למתג (${view.name})', (
        tester,
      ) async {
        await pumpTall(tester, view);
        expect(find.text('זריחה ושקיעה בכל יום'), findsNothing);
        expect(
          find.text('בלי זמנים בתאי החודש: חגים ואירועים בלבד'),
          findsNothing,
        );
        expect(find.text('הזמנים שמוצגים בלוח'), findsNothing);
        expect(find.byType(Checkbox), findsNothing);
      });
    }

    testWidgets('הדלקה בשבוע: זריחה ושקיעה מסומנות, והרשימה גוללת אליהן', (
      tester,
    ) async {
      await pumpTall(tester, CalendarView.week);
      await turnOn(tester);
      expect(find.text('זריחה ושקיעה בכל יום'), findsNothing);
      expect(find.text('נבחרו 2 מתוך 14'), findsOneWidget);
      expect(find.text('נקה בחירה'), findsOneWidget);
      expect(checkedCount(tester), 2);
      final list = find.descendant(
        of: find.byType(CalendarPrintZmanimPicker),
        matching: find.byType(SingleChildScrollView),
      );
      final sunrise = kZmanimRegistry.firstWhere((d) => d.id == 'sunrise');
      final row = find.widgetWithText(InkWell, sunrise.fullName).first;
      expect(
        tester.getRect(list).contains(tester.getRect(row).center),
        isTrue,
        reason: 'השורה המסומנת בתוך חלון הרשימה',
      );
      // הדיאלוג עצמו לא נגלל: כותרת ההדפסה עדיין גלויה.
      expect(find.text('הגדרות הדפסה').hitTestable(), findsOneWidget);
    });

    testWidgets('הדלקה ביום: מסומנים הזמנים שמופעלים בלוח', (tester) async {
      await pumpTall(
        tester,
        CalendarView.day,
        enabledZmanim: {kZmanimRegistry[0].id, kZmanimRegistry[1].id},
      );
      await turnOn(tester);
      expect(find.text('נבחרו 2'), findsOneWidget);
      expect(checkedCount(tester), 2);
    });

    testWidgets('אישור שומר את מה שסומן, ומתחיל מברירת המחדל', (tester) async {
      await pumpTall(tester, CalendarView.month);
      await turnOn(tester);
      expect(find.text('נבחרו 0 מתוך 3'), findsOneWidget);
      await tester.tap(find.byType(Checkbox).at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pumpAndSettle();
      expect(find.text('נבחרו 2 מתוך 3'), findsOneWidget);
      await tester.tap(find.text('הדפס'));
      await tester.pumpAndSettle();
      expect(CalendarPrintZmanimStore.load(), {
        kZmanimRegistry[0].id,
        kZmanimRegistry[1].id,
      });
    });

    testWidgets('הבחירה השמורה נטענת בפתיחה הבאה, והמתג דלוק', (tester) async {
      await CalendarPrintZmanimStore.save({kZmanimRegistry[0].id});
      await pumpTall(tester, CalendarView.week);
      expect(tester.widget<Switch>(zmanimSwitch()).value, isTrue);
      expect(find.text('נבחרו 1 מתוך 14'), findsOneWidget);
      expect(tester.widget<Checkbox>(find.byType(Checkbox).first).value, true);
    });

    testWidgets('כיבוי המתג מסתיר את הרשימה ומוחק את הבחירה השמורה', (
      tester,
    ) async {
      await CalendarPrintZmanimStore.save({kZmanimRegistry[0].id});
      await pumpTall(tester, CalendarView.day);
      await tester.tap(zmanimSwitch());
      await tester.pumpAndSettle();
      expect(find.byType(Checkbox), findsNothing);
      expect(find.text('נקה בחירה'), findsNothing);
      await tester.tap(find.text('הדפס'));
      await tester.pumpAndSettle();
      expect(CalendarPrintZmanimStore.load(), isNull);
    });

    testWidgets('בחודש אי אפשר לסמן יותר מ-3 זמנים', (tester) async {
      await pumpTall(tester, CalendarView.month);
      await turnOn(tester);
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byType(Checkbox).at(i));
        await tester.pumpAndSettle();
      }
      expect(find.text('נבחרו 3 מתוך 3'), findsOneWidget);
      expect(
        tester.widget<Checkbox>(find.byType(Checkbox).at(3)).onChanged,
        isNull,
      );
      // אלה שסומנו נשארים פעילים, כדי שאפשר יהיה להחליף.
      expect(
        tester.widget<Checkbox>(find.byType(Checkbox).at(0)).onChanged,
        isNotNull,
      );
    });

    testWidgets('ביום אין תקרה', (tester) async {
      await pumpTall(tester, CalendarView.day);
      await turnOn(tester);
      await tester.tap(find.byType(Checkbox).at(0));
      await tester.pumpAndSettle();
      expect(find.text('נבחרו 1'), findsOneWidget);
    });

    for (final (view, selectedCount) in [
      (CalendarView.week, 98),
      (CalendarView.month, 14),
    ]) {
      testWidgets('בחירה שמורה חורגת מחייבת תיקון לפני הדפסת $view', (
        tester,
      ) async {
        await CalendarPrintZmanimStore.save({
          for (final def in kZmanimRegistry.take(selectedCount)) def.id,
        });
        await pumpTall(tester, view);
        final printButton = find.widgetWithText(ActionButton, 'הדפס');
        expect(tester.widget<ActionButton>(printButton).onPressed, isNull);
        expect(
          tester.widget<AppDialogFrame>(find.byType(AppDialogFrame)).onConfirm,
          isNull,
        );
        expect(
          find.text(
            'יש לצמצם את הבחירה לכל היותר ל־${maxPrintedZmanim(view)} זמנים לפני ההדפסה.',
          ),
          findsOneWidget,
        );
        expect(checkedCount(tester), selectedCount);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.byType(CalendarPrintDialog), findsOneWidget);
        if (view == CalendarView.month) {
          for (var i = 3; i < selectedCount; i++) {
            final checkbox = find.byType(Checkbox).at(i);
            await tester.ensureVisible(checkbox);
            await tester.tap(checkbox);
            await tester.pumpAndSettle();
          }
          expect(checkedCount(tester), 3);
        } else {
          await tester.tap(find.text('נקה בחירה'));
          await tester.pumpAndSettle();
        }
        expect(tester.widget<ActionButton>(printButton).onPressed, isNotNull);
        await tester.tap(find.text('הדפס'));
        await tester.pumpAndSettle();
        expect(
          CalendarPrintZmanimStore.load(),
          view == CalendarView.month
              ? {for (final def in kZmanimRegistry.take(3)) def.id}
              : <String>{},
        );
      });
    }

    testWidgets('"נקה בחירה" מאפס את הסימונים ומשאיר את המתג דלוק', (
      tester,
    ) async {
      await CalendarPrintZmanimStore.save({kZmanimRegistry[0].id});
      await pumpTall(tester, CalendarView.week);
      await tester.tap(find.text('נקה בחירה'));
      await tester.pumpAndSettle();
      expect(find.text('נבחרו 0 מתוך 14'), findsOneWidget);
      expect(tester.widget<Switch>(zmanimSwitch()).value, isTrue);
      await tester.tap(find.text('הדפס'));
      await tester.pumpAndSettle();
      expect(CalendarPrintZmanimStore.load(), isEmpty);
    });
  });
}
