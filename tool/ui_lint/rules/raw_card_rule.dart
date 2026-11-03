import '../ast_helpers.dart';
import '../ui_lint.dart';

/// UIL-012: `Card(` גולמי (גם `Card.filled`/`Card.outlined`) מחוץ לרכיבי
/// הפריסה המשותפים.
class RawCardRule extends UiLintRule {
  const RawCardRule();

  @override
  String get id => 'UIL-012';

  @override
  int get stage => 2;

  @override
  String get title => 'Card גולמי';

  @override
  String get hint =>
      'AppCard / AppCard(tone:), או ResultCardFrame לכרטיס תוצאה '
      '(DESIGN_SYSTEM.md §3.4, DD-11)';

  @override
  void check(UiLintFile file) {
    for (final call in ctorCallsNamed(file.unit, {'Card'})) {
      if (call.importPrefix == null) {
        file.report(this, call.node, identity: call.head);
      }
    }
  }
}
