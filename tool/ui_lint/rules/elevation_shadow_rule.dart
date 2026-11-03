import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../ast_helpers.dart';
import '../ui_lint.dart';

/// UIL-030: הגבהה וצל מהטוקנים (DD-12).
///
/// - `elevation:` עם ליטרל שאינו 0, גם כ־fallback (`theme.elevation ?? 3`) או
///   בענף של תנאי. ההגבהה רק 0 או `AppTokens.elevation*`. ביטוי מחושב בלי
///   ליטרל (גובה גאוגרפי, ערך מ־API של תוסף) לא נתפס.
/// - `BoxShadow(...)` מחוץ לשכבת הטוקנים: צל רק דרך `AppShadows`.
///   `pw.BoxShadow` (נייר) ו־CustomPainter מוחרגים.
class ElevationShadowRule extends UiLintRule {
  const ElevationShadowRule();

  @override
  String get id => 'UIL-030';

  @override
  int get stage => 3;

  @override
  String get title => 'elevation ליטרלי או BoxShadow מקומי';

  @override
  String get hint =>
      '0, או AppTokens.elevation1 (סרגל, חלונית מוצמדת) / AppTokens.elevation2 '
      '(תפריט, tooltip, חלונית צפה); צל: AppShadows (DESIGN_SYSTEM.md §2.5.4, '
      'DD-12)';

  @override
  void check(UiLintFile file) => file.unit.accept(_Visitor(this, file));
}

class _Visitor extends RecursiveAstVisitor<void> {
  _Visitor(this.rule, this.file);

  final ElevationShadowRule rule;
  final UiLintFile file;

  @override
  void visitNamedArgument(NamedArgument node) {
    if (node.name.lexeme == 'elevation' &&
        !isInsideClassExtending(node, const {'CustomPainter'})) {
      final literals = _NonZeroLiterals();
      node.argumentExpression.accept(literals);
      if (literals.found) file.report(rule, node);
    }
    super.visitNamedArgument(node);
  }

  void _checkShadow(Expression node) {
    final call = asCtorCall(node);
    if (call != null &&
        call.typeName == 'BoxShadow' &&
        call.importPrefix == null &&
        !isInsideClassExtending(node, const {'CustomPainter'})) {
      file.report(rule, node, identity: call.head);
    }
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    _checkShadow(node);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    _checkShadow(node);
    super.visitMethodInvocation(node);
  }
}

class _NonZeroLiterals extends RecursiveAstVisitor<void> {
  bool found = false;

  @override
  void visitIntegerLiteral(IntegerLiteral node) {
    if (node.value != 0) found = true;
  }

  @override
  void visitDoubleLiteral(DoubleLiteral node) {
    if (node.value != 0) found = true;
  }

  /// `args['elevation']` וכדומה: הליטרל הוא מפתח, לא ערך.
  @override
  void visitIndexExpression(IndexExpression node) => node.target?.accept(this);

  /// ארגומנט של קריאה (`math.max(x, 2)`) הוא חישוב, לא ערך קבוע.
  @override
  void visitArgumentList(ArgumentList node) {}
}
