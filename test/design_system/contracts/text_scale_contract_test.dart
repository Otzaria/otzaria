// חוזה הגדלת גופן (B-31): ברכיבים המשותפים, בהגדלה 1.0, 1.3 ו-2.0, אין
// גלישה, והתווית מוצגת בשלמותה ובגודל שמכבד את ההגדלה.
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/widgets/settings_card.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/controls/bar_button.dart';
import 'package:otzaria/widgets/controls/status_chip.dart';
import 'package:otzaria/widgets/controls/toggle_pill.dart';
import 'package:otzaria/widgets/feedback/app_info_banner.dart';
import 'package:otzaria/widgets/feedback/loading_indicator.dart';
import 'package:otzaria/widgets/feedback/otzaria_empty_state.dart';
import 'package:otzaria/widgets/layout/app_card.dart';
import 'package:otzaria/widgets/layout/meta_chip.dart';
import 'package:otzaria/widgets/navigation/nav_rail_item.dart';

import 'contract_harness.dart';

void _noop() {}

const _scales = [1.0, 1.3, 2.0];

/// רכיב ותוויות שצריכות להיראות בשלמותן. [width] — רוחב המקום שהרכיב מקבל,
/// כמו במקום טיפוסי באפליקציה.
class _Case {
  final String name;
  final double width;
  final List<String> labels;
  final Widget Function() build;

  const _Case(this.name, this.width, this.labels, this.build);
}

final _cases = <_Case>[
  _Case(
    'ActionButton.recommended',
    320,
    ['שמור שינויים'],
    () => const ActionButton.recommended(
      text: 'שמור שינויים',
      icon: FluentIcons.save_24_regular,
      onPressed: _noop,
    ),
  ),
  _Case(
    'ActionButton.neutral',
    320,
    ['ביטול'],
    () => const ActionButton.neutral(text: 'ביטול', onPressed: _noop),
  ),
  _Case(
    'ActionButton.ghost',
    320,
    ['הצג עוד'],
    () => const ActionButton.ghost(text: 'הצג עוד', onPressed: _noop),
  ),
  _Case(
    'ActionButton.warning',
    320,
    ['מחק הכל'],
    () => const ActionButton.warning(text: 'מחק הכל', onPressed: _noop),
  ),
  _Case(
    'BarButton.text',
    320,
    ['כניסה'],
    () => BarButton.text(text: 'כניסה', onPressed: _noop),
  ),
  _Case(
    'MetaChip',
    320,
    ['ראשונים'],
    () => const MetaChip(label: 'ראשונים', icon: FluentIcons.clock_24_regular),
  ),
  _Case(
    'StatusChip',
    320,
    ['עדכון זמין'],
    () => const StatusChip(
      icon: Icon(FluentIcons.arrow_download_24_regular),
      label: 'עדכון זמין',
      onPressed: _noop,
      tooltip: 'עדכון',
    ),
  ),
  _Case(
    'AppTogglePill',
    320,
    ['מילים שלמות'],
    () => AppTogglePill(label: 'מילים שלמות', value: true, onChanged: (_) {}),
  ),
  _Case(
    'AppCard',
    320,
    ['בראשית'],
    () => AppCard(
      onTap: _noop,
      padding: const EdgeInsets.all(12),
      child: const Text('בראשית'),
    ),
  ),
  _Case(
    'NavRailItem',
    120,
    ['ספרייה'],
    () => NavRailItem(
      icon: FluentIcons.library_24_regular,
      label: 'ספרייה',
      isSelected: true,
      onTap: _noop,
    ),
  ),
  _Case(
    'AppInfoBanner',
    360,
    ['שים לב', 'הספרייה תתעדכן בהפעלה הבאה'],
    () => const AppInfoBanner(
      icon: FluentIcons.info_24_regular,
      title: 'שים לב',
      message: 'הספרייה תתעדכן בהפעלה הבאה',
    ),
  ),
  _Case(
    'OtzariaEmptyState',
    360,
    ['אין תוצאות', 'נסה מילה אחרת'],
    () => const OtzariaEmptyState(
      icon: FluentIcons.search_24_regular,
      title: 'אין תוצאות',
      message: 'נסה מילה אחרת',
    ),
  ),
  _Case(
    'LoadingIndicator',
    360,
    ['טוען ספרים'],
    () => const LoadingIndicator(message: 'טוען ספרים'),
  ),
  _Case(
    'SettingsSwitchTile',
    360,
    ['סינכרון אוטומטי', 'מתעדכן בטעינת הספרייה'],
    () => SettingsSwitchTile(
      title: 'סינכרון אוטומטי',
      subtitle: 'מתעדכן בטעינת הספרייה',
      value: true,
      onChanged: (_) {},
    ),
  ),
];

void main() {
  // בלי גופן אמיתי כל אות בגופן הבדיקה ברוחב em, ומילה עברית נראית כפולה
  // מרוחבה. Rubik מחליף את גופן הממשק (Roboto בבדיקות) במידות של גופן אמיתי.
  setUpAll(() async {
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('fonts/Rubik-VariableFont_wght.ttf'))).load();
  });

  for (final c in _cases) {
    group(c.name, () {
      for (final scale in _scales) {
        testWidgets('הגדלה $scale: בלי גלישה, התווית שלמה ומוגדלת', (
          tester,
        ) async {
          await pumpInApp(
            tester,
            Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: Center(
                  child: SizedBox(
                    width: c.width,
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: c.build(),
                    ),
                  ),
                ),
              ),
            ),
          );
          // pump ולא pumpAndSettle: במחוון הטעינה האנימציה אינסופית.
          await tester.pump(const Duration(milliseconds: 500));
          // שגיאת RenderFlex overflow נזרקת כחריגה בזמן הפריסה.
          expect(tester.takeException(), isNull);

          for (final label in c.labels) {
            final finder = find.text(label);
            expect(finder, findsOneWidget, reason: label);
            final paragraph = tester.renderObject<RenderParagraph>(finder);
            final style = paragraph.text.style;
            if (style?.fontFamily == null) {
              // סגנון בלי משפחה (AnimatedDefaultTextStyle לא יורש את ערכת
              // הנושא) מצויר בבדיקה בגופן הבדיקה. המדידה בגופן אמיתי.
              final painter = TextPainter(
                text: TextSpan(
                  text: label,
                  style: style?.copyWith(fontFamily: 'Roboto'),
                ),
                textDirection: TextDirection.rtl,
                textScaler: TextScaler.linear(scale),
              )..layout();
              expect(
                painter.width,
                lessThanOrEqualTo(paragraph.constraints.maxWidth),
                reason: '"$label" רחב מהמקום בהגדלה $scale',
              );
              painter.dispose();
            } else {
              expect(
                paragraph.didExceedMaxLines,
                isFalse,
                reason: '"$label" נחתך בהגדלה $scale',
              );
            }
            final fontSize =
                style?.fontSize ??
                DefaultTextStyle.of(tester.element(finder)).style.fontSize!;
            expect(paragraph.textScaler.scale(fontSize), fontSize * scale);
            // לפחות שורה אחת בגובה הגופן המוגדל.
            expect(
              paragraph.size.height,
              greaterThanOrEqualTo(fontSize * scale * 0.95),
              reason: '"$label" מכווץ בהגדלה $scale',
            );
          }
        });
      }
    });
  }
}
