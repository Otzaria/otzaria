import '../ast_helpers.dart';
import '../ui_lint.dart';

/// UIL-003: לכל IconButton יש tooltip, שהוא גם התווית לקורא מסך.
class IconButtonTooltipRule extends UiLintRule {
  const IconButtonTooltipRule();

  static const _constructors = {null, 'filled', 'filledTonal', 'outlined'};

  @override
  String get id => 'UIL-003';

  @override
  int get stage => 1;

  @override
  String get title => 'IconButton בלי tooltip';

  @override
  String get hint => "להוסיף tooltip: '...' (DESIGN_SYSTEM.md §6.3)";

  @override
  void check(UiLintFile file) {
    for (final call in ctorCallsNamed(file.unit, {'IconButton'})) {
      if (call.importPrefix == null &&
          _constructors.contains(call.constructor) &&
          call.named('tooltip') == null) {
        file.report(this, call.node, identity: call.head);
      }
    }
  }
}
