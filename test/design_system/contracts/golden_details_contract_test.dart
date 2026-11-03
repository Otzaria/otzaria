import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_frame.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

import 'contract_harness.dart';

/// פרטים שקטנים מסף ה-golden (0.05%, DD-22): הסרה של X או של תג עוברת בהשוואת
/// התמונות, ולכן הם נבדקים כאן.
void main() {
  const wide = Size(1200, 800);
  const compact = Size(400, 800);

  Future<void> showFrame(
    WidgetTester tester,
    AppDialogSize size, {
    Size window = wide,
  }) => showInApp<void>(
    tester,
    AppDialogFrame(
      title: 'מסגרת',
      icon: FluentIcons.folder_24_regular,
      size: size,
      child: const Text('גוף'),
    ),
    size: window,
  );

  group('X ותג אייקון לפי גודל הדיאלוג (DD-07)', () {
    for (final (size, window, hasClose) in [
      (AppDialogSize.small, wide, false),
      (AppDialogSize.medium, wide, true),
      (AppDialogSize.large, wide, true),
      (AppDialogSize.full, wide, true),
      (AppDialogSize.small, compact, false),
      (AppDialogSize.medium, compact, true),
      (AppDialogSize.large, compact, true),
    ]) {
      final where = window == wide ? 'חלון רחב' : 'חלון צר';
      testWidgets('${size.name}, $where: ${hasClose ? 'עם' : 'בלי'} X, ותג', (
        tester,
      ) async {
        await showFrame(tester, size, window: window);
        expect(
          find.byTooltip('סגור'),
          hasClose ? findsOneWidget : findsNothing,
        );
        final badge = tester.widget<AppDialogIconBadge>(
          find.byType(AppDialogIconBadge),
        );
        expect(badge.icon, FluentIcons.folder_24_regular);
      });
    }
  });

  group('הדיאלוגים של ה-golden', () {
    Iterable<String> actionTexts(WidgetTester tester) => tester
        .widgetList<ActionButton>(find.byType(ActionButton))
        .map((b) => b.text);

    testWidgets('AppDialog.twoActions: בלי X, תג אישור, ביטול ואז אישור', (
      tester,
    ) async {
      await showInApp<bool>(
        tester,
        const AppDialog.twoActions(
          title: 'מחיקת קבוצה',
          content: 'הקבוצה "ספרי יסוד" וכל הספרים שבה יוסרו מהרשימה. להמשיך?',
          confirmText: 'מחיקה',
        ),
      );
      expect(find.byTooltip('סגור'), findsNothing);
      final badge = tester.widget<AppDialogIconBadge>(
        find.byType(AppDialogIconBadge),
      );
      expect(badge.icon, AppDialogIcons.confirm);
      expect(badge.tone, AppDialogHeaderTone.primary);
      expect(actionTexts(tester), [
        'ביטול',
        'מחיקה',
      ]);
      expect(
        find.descendant(
          of: find.widgetWithText(ActionButton, 'ביטול'),
          matching: find.byType(FilledButton),
        ),
        findsOneWidget,
      );
    });

    testWidgets('AppDialog.warning: בלי X, תג אזהרה בטון שגיאה, אישור מלא', (
      tester,
    ) async {
      await showInApp<bool>(
        tester,
        const AppDialog.warning(
          title: 'שינויים שלא נשמרו',
          content: 'יש בטופס שינויים שלא נשמרו. לצאת בלי לשמור?',
          confirmText: 'צא בלי לשמור',
        ),
      );
      expect(find.byTooltip('סגור'), findsNothing);
      final badge = tester.widget<AppDialogIconBadge>(
        find.byType(AppDialogIconBadge),
      );
      expect(badge.icon, AppDialogIcons.warning);
      expect(badge.tone, AppDialogHeaderTone.error);
      expect(
        find.descendant(
          of: find.widgetWithText(ActionButton, 'צא בלי לשמור'),
          matching: find.byType(FilledButton),
        ),
        findsOneWidget,
      );
    });

    testWidgets('ActionButton עם icon מציג את האייקון', (tester) async {
      await pumpInApp(
        tester,
        ActionButton.recommended(
          text: 'הוספה',
          icon: FluentIcons.add_24_regular,
          onPressed: () {},
        ),
      );
      expect(
        find.descendant(
          of: find.byType(ActionButton),
          matching: find.byIcon(FluentIcons.add_24_regular),
        ),
        findsOneWidget,
      );
    });
  });
}
