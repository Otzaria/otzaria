import '../ast_helpers.dart';
import '../ui_lint.dart';

/// כללים מועמדים (דוח בלבד), `uiLintPendingRules`.
///
/// כל כלל כאן מוצא חוב אמיתי ב־`lib/` שעדיין לא תוקן, ולכן אי־אפשר להפעיל
/// אותו כחוסם בלי להגדיל את ה־baseline (שדורש את התווית `ui-baseline`).
/// הכלי מדווח את מספר ההתאמות שלהם ולא משווה ל־baseline ולא מכשיל:
/// `ui_lint_cli --check` ו־`ui_lint_test` מתעלמים מהם. כשהחוב של כלל מתאפס
/// (0 התאמות), מעבירים אותו ל־`uiLintRules` ב־`rules.dart`, ואם הוא נוגע
/// בכלל קיים, מאחדים אותו עם הכלל הזה.
///
/// אין הערת allow לכללים האלה.
abstract class PendingUiLintRule extends UiLintRule {
  const PendingUiLintRule();

  @override
  int get stage => 4;

  /// הכלל הקיים שהכלל הזה יתאחד איתו כשהחוב יתאפס, אם יש.
  String? get extendsRule => null;
}

/// UIL-034: `IconButton` גולמי (כולל `.filled`/`.filledTonal`/`.outlined`)
/// מחוץ ל־`lib/widgets`. ב־`lib/widgets` הרכיבים המשותפים בונים אותו.
///
/// UIL-003 מכסה רק `tooltip:`, ו־UIL-002 רק כפתורי טקסט, ולכן IconButton
/// בקוד פיצ'ר לא נאכף, בניגוד ל־`AppIconButton` (DESIGN_SYSTEM.md §3.2).
class RawIconButtonOutsideSharedRule extends PendingUiLintRule {
  const RawIconButtonOutsideSharedRule();

  @override
  String get id => 'UIL-034';

  @override
  String get title => 'IconButton גולמי בקוד פיצ\'ר';

  @override
  String get hint => 'AppIconButton (DESIGN_SYSTEM.md §3.2)';

  @override
  void check(UiLintFile file) {
    if (file.path.startsWith('lib/widgets/')) return;
    for (final call in ctorCallsNamed(file.unit, const {'IconButton'})) {
      // `IconButton.styleFrom(...)` בונה ButtonStyle ואינו כפתור.
      if (call.importPrefix == null && call.constructor != 'styleFrom') {
        file.report(this, call.node, identity: call.head);
      }
    }
  }
}
