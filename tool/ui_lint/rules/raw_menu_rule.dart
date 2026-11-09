import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../ast_helpers.dart';
import '../ui_lint.dart';

/// UIL-014: תפריט גולמי (`PopupMenuButton`, `MenuAnchor`, `showMenu`) מחוץ
/// למערכת התפריטים המשותפת.
class RawMenuRule extends UiLintRule {
  const RawMenuRule();

  static const _types = {'PopupMenuButton', 'MenuAnchor'};

  @override
  String get id => 'UIL-014';

  @override
  int get stage => 2;

  @override
  String get title => 'PopupMenuButton/MenuAnchor/showMenu גולמי';

  @override
  String get hint =>
      'AppPopupMenuButton / showAnchoredAppMenu / showAnchoredAppSearchMenu '
      '(app_popup_menu.dart)';

  @override
  void check(UiLintFile file) {
    for (final call in ctorCallsNamed(file.unit, _types)) {
      if (call.importPrefix == null) {
        file.report(this, call.node, identity: call.head);
      }
    }
    file.unit.accept(_ShowMenuVisitor(this, file));
  }
}

class _ShowMenuVisitor extends RecursiveAstVisitor<void> {
  _ShowMenuVisitor(this.rule, this.file);

  final RawMenuRule rule;
  final UiLintFile file;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.target == null && node.methodName.name == 'showMenu') {
      file.report(rule, node, identity: 'showMenu');
    }
    super.visitMethodInvocation(node);
  }
}
