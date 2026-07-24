import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/misc/app_dropdown_field.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';

void main() {
  Future<void> pumpDropdown<T>(
    WidgetTester tester, {
    required List<AppMenuEntry<T>> entries,
    required T? value,
    required ValueChanged<T?>? onSelected,
    bool enableSearch = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 240,
              child: AppDropdownField<T>(
                value: value,
                entries: entries,
                onSelected: onSelected,
                enableSearch: enableSearch,
              ),
            ),
          ),
        ),
      ),
    );
  }

  group('AppDropdownField - טריגר אחיד', () {
    testWidgets('לא משתמש ב-DropdownMenu של Material 3 (enableSearch=false)', (
      tester,
    ) async {
      await pumpDropdown<String>(
        tester,
        value: 'a',
        entries: const [
          AppMenuEntry<String>(value: 'a', label: 'אבא'),
          AppMenuEntry<String>(value: 'b', label: 'בית'),
        ],
        onSelected: (_) {},
        enableSearch: false,
      );

      expect(find.byType(AppDropdownField<String>), findsOneWidget);
      expect(
        find.byType(DropdownMenu<String>),
        findsNothing,
        reason: 'הטריגר לא צריך להיות DropdownMenu של Material 3',
      );
    });

    testWidgets('לא משתמש ב-DropdownMenu של Material 3 (enableSearch=true)', (
      tester,
    ) async {
      await pumpDropdown<String>(
        tester,
        value: 'a',
        entries: const [
          AppMenuEntry<String>(value: 'a', label: 'אבא'),
          AppMenuEntry<String>(value: 'b', label: 'בית'),
        ],
        onSelected: (_) {},
        enableSearch: true,
      );

      expect(find.byType(AppDropdownField<String>), findsOneWidget);
      expect(
        find.byType(DropdownMenu<String>),
        findsNothing,
        reason: 'גם עם enableSearch הטריגר לא צריך להיות DropdownMenu',
      );
    });
  });

  group('AppDropdownField - תווית הערך הנבחר', () {
    testWidgets('מציג את label של ה-entry הנבחר', (tester) async {
      await pumpDropdown<String>(
        tester,
        value: 'b',
        entries: const [
          AppMenuEntry<String>(value: 'a', label: 'אבא'),
          AppMenuEntry<String>(value: 'b', label: 'בית'),
        ],
        onSelected: (_) {},
      );

      expect(find.text('בית'), findsOneWidget);
    });

    testWidgets('כש-value הוא null מציג טקסט ריק', (tester) async {
      await pumpDropdown<String>(
        tester,
        value: null,
        entries: const [
          AppMenuEntry<String>(value: 'a', label: 'אבא'),
        ],
        onSelected: (_) {},
      );

      expect(find.byType(AppDropdownField<String>), findsOneWidget);
      expect(find.text('אבא'), findsNothing);
    });
  });

  group('AppDropdownField - פתיחת תפריט', () {
    testWidgets('לחיצה פותחת תפריט עם הפריטים', (tester) async {
      await pumpDropdown<String>(
        tester,
        value: 'a',
        entries: const [
          AppMenuEntry<String>(value: 'a', label: 'אבא'),
          AppMenuEntry<String>(value: 'b', label: 'בית'),
          AppMenuEntry<String>(value: 'c', label: 'גמל'),
        ],
        onSelected: (_) {},
      );

      await tester.tap(find.byType(AppDropdownField<String>));
      await tester.pumpAndSettle();

      expect(find.text('בית'), findsOneWidget);
      expect(find.text('גמל'), findsOneWidget);
    });

    testWidgets('בחירת פריט קוראת ל-onSelected עם הערך', (tester) async {
      String? selected;
      await pumpDropdown<String>(
        tester,
        value: 'a',
        entries: const [
          AppMenuEntry<String>(value: 'a', label: 'אבא'),
          AppMenuEntry<String>(value: 'b', label: 'בית'),
        ],
        onSelected: (v) => selected = v,
      );

      await tester.tap(find.byType(AppDropdownField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('בית').last);
      await tester.pumpAndSettle();

      expect(selected, 'b');
    });
  });

  group('AppDropdownField - מצב מושבת', () {
    testWidgets('רשימה ריקה לא פותחת תפריט', (tester) async {
      bool selected = false;
      await pumpDropdown<String>(
        tester,
        value: null,
        entries: const [],
        onSelected: (_) => selected = true,
      );

      await tester.tap(find.byType(AppDropdownField<String>));
      await tester.pumpAndSettle();

      expect(
        selected,
        isFalse,
        reason: 'אין פריטים לבחור, ולכן onSelected לא נקרא',
      );
    });

    testWidgets('onSelected=null משאיר את השדה כמושבת', (tester) async {
      await pumpDropdown<String>(
        tester,
        value: 'a',
        entries: const [
          AppMenuEntry<String>(value: 'a', label: 'אבא'),
        ],
        onSelected: null,
      );

      await tester.tap(find.byType(AppDropdownField<String>));
      await tester.pumpAndSettle();

      expect(find.byType(AppDropdownField<String>), findsOneWidget);
    });
  });

  group('AppDropdownField - עיצוב הכפתור', () {
    testWidgets('החץ צמוד לקצה הכפתור (isExpanded=true)', (tester) async {
      await pumpDropdown<String>(
        tester,
        value: 'a',
        entries: const [AppMenuEntry<String>(value: 'a', label: 'קצר')],
        onSelected: (_) {},
      );

      final buttonRect = tester.getRect(find.byType(FilledButton));
      final iconRect = tester.getRect(
        find.byIcon(FluentIcons.chevron_down_24_regular),
      );

      final edgeGap = buttonRect.right - iconRect.right;
      expect(
        edgeGap,
        lessThan(12),
        reason: 'החץ אמור להיות צמוד לקצה הכפתור, לא לצוף עם רווח גדול',
      );
    });

    testWidgets('הטקסט ממורכז בשטח התוכן של הכפתור, לא צמוד לצד אחד', (
      tester,
    ) async {
      await pumpDropdown<String>(
        tester,
        value: 'a',
        entries: const [AppMenuEntry<String>(value: 'a', label: 'קצר')],
        onSelected: (_) {},
      );

      final buttonRect = tester.getRect(find.byType(FilledButton));
      final iconRect = tester.getRect(
        find.byIcon(FluentIcons.chevron_down_24_regular),
      );
      final textRect = tester.getRect(find.text('קצר'));

      // שטח התוכן הוא בין תחילת הכפתור לתחילת אזור החץ.
      final contentCenter = (buttonRect.left + iconRect.left) / 2;
      final textCenter = (textRect.left + textRect.right) / 2;

      expect(
        (textCenter - contentCenter).abs(),
        lessThan(6),
        reason: 'הטקסט אמור להיות ממורכז בשטח התוכן, לא צמוד לקצה אחד',
      );
    });

    testWidgets(
      'isExpanded=false: רוחב הכפתור נגזר מהתפריט, לא מהערך הנבחר כרגע',
      (tester) async {
        const entries = [
          AppMenuEntry<String>(value: 's', label: 'קצר'),
          AppMenuEntry<String>(
            value: 'l',
            label: 'זוהי תווית ארוכה משמעותית לבדיקת רוחב',
          ),
        ];

        Future<double> widthFor(String value) async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 400,
                    child: AppDropdownField<String>(
                      value: value,
                      entries: entries,
                      onSelected: (_) {},
                      isExpanded: false,
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          return tester.getRect(find.byType(FilledButton)).width;
        }

        final shortSelectedWidth = await widthFor('s');
        final longSelectedWidth = await widthFor('l');

        expect(
          shortSelectedWidth,
          closeTo(longSelectedWidth, 0.5),
          reason:
              'הרוחב נגזר מרוחב התפריט (הפריט הארוך ביותר), '
              'ולא אמור לקפוץ לפי אורך הערך הנבחר כרגע',
        );
      },
    );

    testWidgets('isExpanded=false: הרוחב לא חורג מהמקום שההורה מקצה לכפתור', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 120,
                child: AppDropdownField<String>(
                  value: 'l',
                  entries: const [
                    AppMenuEntry<String>(
                      value: 'l',
                      label: 'תווית ארוכה מאוד שבוודאי לא נכנסת ל-120 פיקסלים',
                    ),
                  ],
                  onSelected: (_) {},
                  isExpanded: false,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final buttonRect = tester.getRect(find.byType(FilledButton));
      expect(
        buttonRect.width,
        lessThanOrEqualTo(120.5),
        reason: 'הכפתור לא אמור להתרחב מעבר למקום שההורה נתן לו',
      );
    });
  });
}
