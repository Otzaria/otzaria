import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../ast_helpers.dart';
import '../ui_lint.dart';

/// UIL-019: רדיוס פינה ליטרלי.
class LiteralRadiusRule extends UiLintRule {
  const LiteralRadiusRule();

  static const _types = {'BorderRadius', 'Radius'};

  @override
  String get id => 'UIL-019';

  @override
  int get stage => 3;

  @override
  String get title => 'BorderRadius.circular/Radius.circular ליטרלי';

  @override
  String get hint =>
      'AppTokens.borderRadiusAll / AppTokens.roundedShape (DESIGN_SYSTEM.md §2.3)';

  @override
  void check(UiLintFile file) => file.unit.accept(_Visitor(this, file));
}

class _Visitor extends RecursiveAstVisitor<void> {
  _Visitor(this.rule, this.file);

  final LiteralRadiusRule rule;
  final UiLintFile file;

  void _check(Expression node) {
    final call = asCtorCall(node);
    if (call != null &&
        LiteralRadiusRule._types.contains(call.typeName) &&
        call.constructor == 'circular' &&
        call.importPrefix == null &&
        call.positional.length == 1 &&
        isNumericLiteral(call.positional.single) &&
        !isInsideClassExtending(node, const {'CustomPainter'})) {
      file.report(rule, node);
    }
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    _check(node);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    _check(node);
    super.visitMethodInvocation(node);
  }
}
