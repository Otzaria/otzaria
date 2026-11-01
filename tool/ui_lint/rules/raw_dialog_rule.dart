import '../ast_helpers.dart';
import '../ui_lint.dart';

/// UIL-001: דיאלוג גולמי מחוץ לרכיבי הדיאלוג המשותפים.
class RawDialogRule extends UiLintRule {
  const RawDialogRule();

  static const _types = {'AlertDialog', 'Dialog', 'SimpleDialog'};

  @override
  String get id => 'UIL-001';

  @override
  String get title => 'AlertDialog/Dialog/SimpleDialog גולמי';

  @override
  String get hint =>
      'AppDialog / AppDialogFrame / AppCustomContentDialog (DESIGN_SYSTEM.md §3.1)';

  @override
  void check(UiLintFile file) {
    for (final call in ctorCallsNamed(file.unit, _types)) {
      if (call.importPrefix == null) file.report(this, call.node);
    }
  }
}
