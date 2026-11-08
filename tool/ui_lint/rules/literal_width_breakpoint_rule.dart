import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../ast_helpers.dart';
import '../ui_lint.dart';

/// UIL-022: השוואת רוחב לליטרל (`constraints.maxWidth < 520`), גם כשהרוחב
/// במשתנה מקומי (`final width = constraints.maxWidth; width < 520`).
class LiteralWidthBreakpointRule extends UiLintRule {
  const LiteralWidthBreakpointRule();

  static const _operators = {'<', '<=', '>', '>='};
  static const _widthNames = {'width', 'maxWidth', 'minWidth'};

  /// שמות של משתנה מקומי שמחזיק רוחב. שם אחר (`tabWidth`, `rangeWidth`) הוא
  /// מידה של רכיב או נתון, לא רוחב המסך או הפריסה.
  static const _localWidthNames = {
    ..._widthNames,
    'screenWidth',
    'availableWidth',
    'windowWidth',
  };

  /// מתחת לזה זה מידה של רכיב (אייקון, ריווח), לא סף פריסה.
  static const _minBreakpoint = 100;

  @override
  String get id => 'UIL-022';

  @override
  int get stage => 3;

  @override
  String get title => 'השוואת רוחב לליטרל';

  @override
  String get hint =>
      'WindowClass / LayoutBreakpoints, או קבוע static const עם שם ברכיב '
      '(DESIGN_SYSTEM.md §5.2, DD-15)';

  @override
  void check(UiLintFile file) => file.unit.accept(_Visitor(this, file));
}

class _Visitor extends RecursiveAstVisitor<void> {
  _Visitor(this.rule, this.file);

  final LiteralWidthBreakpointRule rule;
  final UiLintFile file;

  static bool _isWidth(Expression e) {
    final x = e.unParenthesized;
    return switch (x) {
      PropertyAccess() => LiteralWidthBreakpointRule._widthNames.contains(
        x.propertyName.name,
      ),
      PrefixedIdentifier() => LiteralWidthBreakpointRule._widthNames.contains(
        x.identifier.name,
      ),
      SimpleIdentifier() =>
        LiteralWidthBreakpointRule._localWidthNames.contains(x.name),
      _ => false,
    };
  }

  static bool _isBreakpointLiteral(Expression e) {
    final x = e.unParenthesized;
    if (!isNumericLiteral(x)) return false;
    final value = switch (x) {
      IntegerLiteral() => x.value ?? 0,
      DoubleLiteral() => x.value,
      _ => 0,
    };
    return value >= LiteralWidthBreakpointRule._minBreakpoint;
  }

  @override
  void visitBinaryExpression(BinaryExpression node) {
    if (LiteralWidthBreakpointRule._operators.contains(node.operator.lexeme) &&
        ((_isWidth(node.leftOperand) &&
                _isBreakpointLiteral(node.rightOperand)) ||
            (_isWidth(node.rightOperand) &&
                _isBreakpointLiteral(node.leftOperand))) &&
        !isInsideClassExtending(node, const {'CustomPainter'})) {
      file.report(rule, node);
    }
    super.visitBinaryExpression(node);
  }
}
