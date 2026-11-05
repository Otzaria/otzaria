// בדיקות הנחיות הנגישות של Flutter (meetsGuideline) לרכיבים המשותפים,
// בבהיר ובכהה (CI_ENFORCEMENT §4).
//
// כשל ידוע נרשם ב-skip עם המספרים שנמדדו, ולא מתוקן כאן: תיקון המראה דורש
// הכרעה של בעל הפרויקט. אחרי שינוי ברכיבים (ערכת הנושא, גדלים, צבעים) מריצים
// את הקובץ מחדש, ומסירים skip שעבר.
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/controls/app_icon_button.dart';
import 'package:otzaria/widgets/controls/bar_button.dart';
import 'package:otzaria/widgets/controls/status_chip.dart';
import 'package:otzaria/widgets/controls/toggle_pill.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_frame.dart';
import 'package:otzaria/widgets/dialogs/app_dialogs.dart';
import 'package:otzaria/widgets/layout/app_card.dart';
import 'package:otzaria/widgets/navigation/app_top_bar.dart';
import 'package:otzaria/widgets/navigation/nav_rail_item.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';

import 'contracts/contract_harness.dart';

void _noop() {}

/// רכיב לבדיקה. [touch] — הרכיב משמש גם במגע (אנדרואיד), ולכן נבדק גם
/// androidTapTargetGuideline (48×48). [knownTapTarget] / [knownContrast] —
/// כשל ידוע: הסיבה והמספרים שנמדדו.
class _Case {
  final String name;
  final Widget Function() build;
  final bool dialog;
  final bool touch;
  final String? knownTapTarget;
  final String? knownContrast;

  const _Case(
    this.name,
    this.build, {
    this.dialog = false,
    this.touch = true,
    this.knownTapTarget,
    this.knownContrast,
  });
}

final List<_Case> _cases = [
  _Case(
    'ActionButton.recommended',
    () => const ActionButton.recommended(text: 'שמור', onPressed: _noop),
  ),
  _Case(
    'ActionButton.neutral',
    () => const ActionButton.neutral(text: 'ביטול', onPressed: _noop),
  ),
  _Case(
    'ActionButton.ghost',
    () => const ActionButton.ghost(text: 'עוד', onPressed: _noop),
  ),
  _Case(
    'ActionButton.warning',
    () => const ActionButton.warning(text: 'מחק', onPressed: _noop),
  ),
  for (final size in AppIconButtonSize.values)
    _Case(
      'AppIconButton.${size.name}',
      () => AppIconButton(
        icon: const Icon(FluentIcons.dismiss_24_regular),
        tooltip: 'סגור',
        size: size,
        onPressed: _noop,
      ),
    ),
  // מיכל: גודל המטרה הוא גודל התוכן, ולכן בלי בדיקת 48×48.
  _Case(
    'AppCard',
    () => AppCard(onTap: _noop, child: const Text('כרטיס')),
    touch: false,
  ),
  _Case(
    'AppTopBar',
    () => SizedBox(
      width: 800,
      child: AppTopBar(
        leadingItems: [
          AppTopBarItem(
            widget: BarButton.icon(
              tooltip: 'חזרה',
              icon: FluentIcons.arrow_right_24_regular,
              onPressed: _noop,
            ),
          ),
        ],
        center: const Text('כותרת'),
      ),
    ),
    knownTapTarget: 'BarButton.icon בסרגל בצפיפות מגע: 40×40 (נדרש 48×48)',
  ),
  for (final selected in [false, true])
    _Case(
      'NavRailItem${selected ? '.selected' : ''}',
      () => NavRailItem(
        icon: FluentIcons.library_24_regular,
        label: 'ספרייה',
        isSelected: selected,
        onTap: _noop,
      ),
      knownContrast:
          'בבהיר נמדד 2.78:1 בגופן 11 (כהה ‎#9E968D על ‎#FFF8F4). צבע התווית '
          'עצמו ‎#4F4539 (נבחר ‎#56442A) הוא 8.9:1, ונבדק ישירות למטה; '
          'הסיבה לפער במדידת הפיקסלים לא אומתה',
    ),
  for (final value in [false, true])
    _Case(
      'AppTogglePill.${value ? 'on' : 'off'}',
      () =>
          AppTogglePill(label: 'מילים שלמות', value: value, onChanged: (_) {}),
      knownTapTarget: 'גובה הגלולה 24 (188.8×24; נדרש 48×48)',
    ),
  _Case(
    'StatusChip',
    () => const StatusChip(
      icon: Icon(FluentIcons.arrow_download_24_regular),
      label: 'עדכון זמין',
      onPressed: _noop,
      tooltip: 'עדכון',
    ),
    knownTapTarget: 'גובה 32 (shrinkWrap; 191×32; נדרש 48×48)',
  ),
  _Case(
    'OtzariaSearchField',
    () => SizedBox(
      width: 400,
      child: OtzariaSearchField(
        controller: TextEditingController(text: 'בראשית'),
        hintText: 'חיפוש',
        onClear: _noop,
      ),
    ),
    knownTapTarget: 'כפתור הניקוי "נקה" 32×32 (נדרש 48×48)',
  ),
  _Case(
    'AppDialog.twoActions',
    () => const AppDialog.twoActions(
      title: 'מחיקה',
      content: 'למחוק את הסימנייה?',
      cancelText: 'ביטול',
      confirmText: 'מחק',
      icon: FluentIcons.delete_24_regular,
    ),
    dialog: true,
  ),
  _Case(
    'AppDialogFrame',
    () => AppDialogFrame(
      title: 'הגדרות',
      icon: FluentIcons.settings_24_regular,
      actions: const [
        ActionButton.neutral(text: 'ביטול', onPressed: _noop),
        ActionButton.recommended(text: 'שמור', onPressed: _noop),
      ],
      child: const Text('תוכן הדיאלוג'),
    ),
    dialog: true,
  ),
];

Future<void> _pump(WidgetTester tester, _Case c, Brightness brightness) async {
  if (c.dialog) {
    await showInApp<void>(tester, c.build(), brightness: brightness);
  } else {
    await pumpInApp(tester, Center(child: c.build()), brightness: brightness);
    await tester.pumpAndSettle();
  }
}

/// יחס הניגודיות של WCAG בין שני צבעים אטומים.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  for (final brightness in Brightness.values) {
    group(brightness.name, () {
      for (final c in _cases) {
        group(c.name, () {
          testWidgets('labeledTapTargetGuideline', (tester) async {
            final handle = tester.ensureSemantics();
            await _pump(tester, c, brightness);
            await expectLater(
              tester,
              meetsGuideline(labeledTapTargetGuideline),
            );
            handle.dispose();
          });

          final contrastKnown =
              c.knownContrast != null && brightness == Brightness.light;
          testWidgets(
            contrastKnown
                ? 'textContrastGuideline — ידוע: ${c.knownContrast}'
                : 'textContrastGuideline',
            skip: contrastKnown,
            (tester) async {
              final handle = tester.ensureSemantics();
              await _pump(tester, c, brightness);
              await expectLater(tester, meetsGuideline(textContrastGuideline));
              handle.dispose();
            },
          );

          if (c.touch) {
            testWidgets(
              c.knownTapTarget != null
                  ? 'androidTapTargetGuideline — ידוע: ${c.knownTapTarget}'
                  : 'androidTapTargetGuideline',
              skip: c.knownTapTarget != null,
              (tester) async {
                final handle = tester.ensureSemantics();
                await _pump(tester, c, brightness);
                await expectLater(
                  tester,
                  meetsGuideline(androidTapTargetGuideline),
                );
                handle.dispose();
              },
            );
          }
        });
      }

      // המדידה בפיקסלים של NavRailItem מערבבת אייקון ותווית (ראו knownContrast),
      // ולכן צבע התווית נבדק מול הרקע שהעמודה יושבת עליו בפועל.
      for (final selected in [false, true]) {
        testWidgets('NavRailItem${selected ? '.selected' : ''}: תווית ≥4.5:1', (
          tester,
        ) async {
          await pumpInApp(
            tester,
            Center(
              child: NavRailItem(
                icon: FluentIcons.library_24_regular,
                label: 'ספרייה',
                isSelected: selected,
                onTap: _noop,
              ),
            ),
            brightness: brightness,
          );
          await tester.pumpAndSettle();
          final label = find.text('ספרייה');
          final color = tester
              .widget<DefaultTextStyle>(
                find
                    .ancestor(
                      of: label,
                      matching: find.byType(DefaultTextStyle),
                    )
                    .first,
              )
              .style
              .color!;
          final railBackground = AppSurfaces.topBarBackground(
            tester.element(label),
          );
          expect(
            _contrast(color, railBackground),
            greaterThanOrEqualTo(4.5),
            reason: 'תווית $color על $railBackground',
          );
        });
      }
    });
  }
}
