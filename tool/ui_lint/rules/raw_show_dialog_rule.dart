import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../ui_lint.dart';

/// UIL-028: `showDialog(` רק דרך `showDialogUntilTornDown`/`settingsDialogBuilder`
/// והעזרים שעוטפים אותם (`showAppDialog`, ‏`showWarningDialog` ודומיהם ב־
/// lib/widgets/dialogs).
///
/// נתפסת קריאה ל־`showDialog` שה־`builder:` שלה אינו `settingsDialogBuilder(...)`.
/// דיאלוג כזה לא מקבל את השפה והכיוון של מסך ההגדרות, ואם ה־Navigator מתפרק
/// לפני שהוא נבנה ה־Future שלו לא מסתיים.
class RawShowDialogRule extends UiLintRule {
  const RawShowDialogRule();

  @override
  String get id => 'UIL-028';

  @override
  int get stage => 4;

  @override
  String get title => 'showDialog גולמי';

  @override
  String get hint =>
      'showAppDialog/showWarningDialog ודומיהם, showDialogUntilTornDown, או '
      'builder: settingsDialogBuilder(context, …) (DESIGN_SYSTEM.md §3.1)';

  @override
  void check(UiLintFile file) => file.unit.accept(_Visitor(this, file));
}

class _Visitor extends RecursiveAstVisitor<void> {
  _Visitor(this.rule, this.file);

  final RawShowDialogRule rule;
  final UiLintFile file;

  static bool _scopedBuilder(MethodInvocation node) {
    for (final argument in node.argumentList.arguments) {
      if (argument is NamedArgument && argument.name.lexeme == 'builder') {
        final value = argument.argumentExpression.unParenthesized;
        return value is MethodInvocation &&
            value.target == null &&
            value.methodName.name == 'settingsDialogBuilder';
      }
    }
    return false;
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.target == null &&
        node.methodName.name == 'showDialog' &&
        !_scopedBuilder(node)) {
      file.report(rule, node, identity: 'showDialog');
    }
    super.visitMethodInvocation(node);
  }
}
