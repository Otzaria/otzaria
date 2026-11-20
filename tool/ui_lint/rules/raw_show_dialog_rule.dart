import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../ast_helpers.dart';
import '../ui_lint.dart';

/// UIL-028: פתיחת דיאלוג גולמי (`showDialog` ושלוש הצורות העוקפות שלו:
/// `showAdaptiveDialog`, ‏`showCupertinoDialog`, ‏`showGeneralDialog`) רק דרך
/// `showDialogUntilTornDown`/`settingsDialogBuilder` והעזרים שעוטפים אותם
/// (`showAppDialog`, ‏`showWarningDialog` ודומיהם ב־lib/widgets/dialogs).
///
/// נתפסת קריאה שה־`builder:` שלה אינו `settingsDialogBuilder(...)`, גם עם
/// prefix של ייבוא Flutter (`m.showDialog`). דיאלוג כזה לא מקבל את השפה
/// והכיוון של מסך ההגדרות, ואם ה־Navigator מתפרק לפני שהוא נבנה ה־Future שלו
/// לא מסתיים.
class RawShowDialogRule extends UiLintRule {
  const RawShowDialogRule();

  @override
  String get id => 'UIL-028';

  @override
  int get stage => 3;

  @override
  String get title =>
      'showDialog/showAdaptiveDialog/showCupertinoDialog/showGeneralDialog גולמי';

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

  static const _openers = {
    'showDialog',
    'showAdaptiveDialog',
    'showCupertinoDialog',
    'showGeneralDialog',
  };

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
    final target = node.target;
    final plain =
        target == null ||
        (target is SimpleIdentifier &&
            flutterImportPrefixes(node.root).contains(target.name));
    final name = node.methodName.name;
    if (plain && _openers.contains(name) && !_scopedBuilder(node)) {
      file.report(rule, node, identity: name);
    }
    super.visitMethodInvocation(node);
  }
}
