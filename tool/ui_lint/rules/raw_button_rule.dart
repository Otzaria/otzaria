import '../ast_helpers.dart';
import '../ui_lint.dart';

/// UIL-002: כפתור Material גולמי (`TextButton`, `FilledButton`,
/// `OutlinedButton`, `ElevatedButton`, כולל `.icon`/`.tonal`) מחוץ לרכיבי
/// הכפתור המשותפים. `X.styleFrom(...)` אינו בנאי, ומותר.
class RawButtonRule extends UiLintRule {
  const RawButtonRule();

  static const _buttons = {
    'TextButton',
    'FilledButton',
    'OutlinedButton',
    'ElevatedButton',
  };

  @override
  String get id => 'UIL-002';

  @override
  int get stage => 1;

  @override
  String get title => 'כפתור Material גולמי';

  @override
  String get hint =>
      'ActionButton.recommended/neutral/ghost/inline/warning, או BarButton '
      'בסרגל (DESIGN_SYSTEM.md §3.2)';

  @override
  void check(UiLintFile file) {
    for (final call in ctorCallsNamed(file.unit, _buttons)) {
      if (call.importPrefix == null && call.constructor != 'styleFrom') {
        file.report(this, call.node, identity: call.head);
      }
    }
  }
}
