import '../ast_helpers.dart';
import '../ui_lint.dart';

/// UIL-013: `CircularProgressIndicator(` (גם `.adaptive`) מחוץ לרכיבי המשוב
/// המשותפים. ‏`ActionButton(isLoading:)` מחריג את עצמו ב־config.
class RawProgressIndicatorRule extends UiLintRule {
  const RawProgressIndicatorRule();

  @override
  String get id => 'UIL-013';

  @override
  int get stage => 2;

  @override
  String get title => 'CircularProgressIndicator גולמי';

  @override
  String get hint =>
      'LoadingIndicator (מסך או אזור, גם עם message:), LoadingIndicator.inline '
      '(בשורה או בכפתור), או ActionButton(isLoading:) (DESIGN_SYSTEM.md §3.5)';

  @override
  void check(UiLintFile file) {
    for (final call in ctorCallsNamed(file.unit, {
      'CircularProgressIndicator',
    })) {
      if (call.importPrefix == null) {
        file.report(this, call.node, identity: call.head);
      }
    }
  }
}
