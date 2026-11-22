// Responsive: הדיאלוגים המשותפים בכל המטריצה. הכותרת, התוכן וכפתורי האישור
// נשארים בתוך החלון ונגישים גם בחלון צר, נמוך או בהגדלת טקסט, ובטקסט ארוך.
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_frame.dart';
import 'package:otzaria/widgets/dialogs/app_dialogs.dart';
import 'package:otzaria/widgets/dialogs/input_dialog.dart';
import 'package:otzaria/widgets/dialogs/selection_dialog.dart';

import 'responsive_harness.dart';

const _longTitle =
    'ספר ארוך מאוד בשם משני וחמש מילים נוספות כדי לבדוק שהכותרת אינה דוחפת החוצה את הכפתורים';
const _longBody =
    'זהו טקסט הסבר ארוך שחוזר על עצמו כדי לבדוק התנהגות בחלון צר ובגובה נמוך. '
    'הוא נמשך על פני כמה שורות, כולל נתיב קובץ C:\\Users\\Someone\\Documents\\Otzaria\\ספרים\\ספר ארוך.pdf '
    'ושם באנגלית: SomeVeryLongEnglishIdentifierThatHasNoBreakOpportunitiesAtAll. ';
final _veryLongBody = List.filled(8, _longBody).join();

/// כפתור שפותח דיאלוג, כמו במסך אמיתי.
Widget _opener(Future<Object?> Function(BuildContext context) open) => Builder(
  builder: (context) => Center(
    child: TextButton(
      onPressed: () => open(context),
      child: const Text('פתח'),
    ),
  ),
);

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('פתח'));
  await tester.pumpAndSettle();
}

/// דיאלוג פתוח: מוצג בתוך החלון, וכל הכפתורים [buttons] גלויים ונגישים.
ResponsiveAct _dialogChecks(List<String> buttons) => (tester, run) async {
  expectInsideViewport(tester, run, find.byType(Dialog), name: 'הדיאלוג');
  for (final label in buttons) {
    expectVisible(tester, run, find.text(label), name: 'כפתור "$label"');
  }
};

void main() {
  testResponsive(
    'showSingleActionDialog, טקסט ארוך',
    build: (_) => _opener(
      (context) => showSingleActionDialog(
        context: context,
        title: _longTitle,
        content: _veryLongBody,
        confirmText: 'הבנתי',
        scrollable: true,
      ),
    ),
    act: (tester, run) => _open(tester),
    verify: _dialogChecks(['הבנתי']),
  );

  testResponsive(
    'showTwoActionsDialog, טקסט ארוך',
    build: (_) => _opener(
      (context) => showTwoActionsDialog(
        context: context,
        title: _longTitle,
        content: _veryLongBody,
        cancelText: 'ביטול',
        confirmText: 'אישור והמשך',
        scrollable: true,
      ),
    ),
    act: (tester, run) => _open(tester),
    verify: _dialogChecks(['ביטול', 'אישור והמשך']),
  );

  testResponsive(
    'showWarningDialog',
    build: (_) => _opener(
      (context) => showWarningDialog(
        context: context,
        title: 'מחיקת כל ההערות',
        content: _longBody,
        subtitle: _longTitle,
        cancelText: 'ביטול',
        confirmText: 'מחק הכל',
      ),
    ),
    act: (tester, run) => _open(tester),
    verify: _dialogChecks(['ביטול', 'מחק הכל']),
  );

  testResponsive(
    'showChoiceDialog, שלוש בחירות ארוכות',
    build: (_) => _opener(
      (context) => showChoiceDialog<int>(
        context: context,
        title: 'ייצוא',
        content: _longBody,
        cancelText: 'ביטול',
        choices: const [
          AppDialogChoice(
            value: 1,
            label: 'שמירה כקובץ טקסט',
            recommended: true,
          ),
          AppDialogChoice(value: 2, label: 'שמירה כמסמך Word'),
          AppDialogChoice(value: 3, label: 'העתקה ללוח בלי עיצוב מיוחד'),
        ],
      ),
    ),
    act: (tester, run) => _open(tester),
    verify: _dialogChecks([
      'ביטול',
      'שמירה כקובץ טקסט',
      'שמירה כמסמך Word',
      'העתקה ללוח בלי עיצוב מיוחד',
    ]),
  );

  testResponsive(
    'showInputDialog',
    build: (_) => _opener(
      (context) => showInputDialog(
        context: context,
        title: _longTitle,
        subtitle: _longBody,
        labelText: 'שם התיקייה',
        cancelText: 'ביטול',
        confirmText: 'צור',
      ),
    ),
    act: (tester, run) => _open(tester),
    verify: (tester, run) async {
      expectInsideViewport(tester, run, find.byType(Dialog), name: 'הדיאלוג');
      expectVisible(tester, run, find.text('צור'), name: 'כפתור "צור"');
      expectVisible(tester, run, find.text('ביטול'), name: 'כפתור "ביטול"');
      expectVisible(
        tester,
        run,
        find.byType(TextField),
        name: 'שדה ההקלדה',
      );
    },
  );

  testResponsive(
    'showSelectionDialog, רשימה ארוכה',
    build: (_) => _opener(
      (context) => showSelectionDialog<int>(
        context: context,
        title: 'בחירת פונט',
        searchHint: 'חיפוש',
        items: [
          for (var i = 0; i < 80; i++)
            SelectionItem(
              label: 'גופן מספר $i בשם ארוך במיוחד $_longTitle',
              value: i,
            ),
        ],
      ),
    ),
    act: (tester, run) => _open(tester),
    verify: (tester, run) async {
      expectInsideViewport(tester, run, find.byType(Dialog), name: 'הדיאלוג');
      expectVisible(tester, run, find.byType(TextField), name: 'שדה החיפוש');
    },
  );

  for (final size in AppDialogSize.values) {
    testResponsive(
      'AppDialogFrame.${size.name} עם טופס ארוך ופעולות',
      build: (_) => _opener(
        (context) => showDialog<void>(
          context: context,
          builder: (_) => AppDialogFrame(
            title: _longTitle,
            subtitle: _longBody,
            subtitleMaxLines: 2,
            icon: FluentIcons.settings_24_regular,
            size: size,
            scrollable: true,
            actions: [
              ActionButton.neutral(text: 'ביטול', onPressed: () {}),
              ActionButton.recommended(text: 'שמור שינויים', onPressed: () {}),
            ],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < 14; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      decoration: InputDecoration(
                        labelText: 'שדה $i $_longTitle',
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      act: (tester, run) => _open(tester),
      verify: _dialogChecks(['ביטול', 'שמור שינויים']),
    );
  }
}
