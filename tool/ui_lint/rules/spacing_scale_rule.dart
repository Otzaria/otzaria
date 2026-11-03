import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../ast_helpers.dart';
import '../ui_lint.dart';

/// UIL-020: ריווח מחוץ לסולם (DD-03): ליטרל ב־`EdgeInsets*` או ב־`SizedBox`
/// מרווח שאינו 0/2/4/8/12/16/24/32.
///
/// - `EdgeInsets.*`/`EdgeInsetsDirectional.*`: כל ארגומנט ליטרלי.
/// - `SizedBox(width:/height:)` בלי `child`, עם ערך קטן מ־32: זה מרווח. קופסה
///   עם ילד, או גודל של 32 ומעלה, היא מידה של רכיב ולא ריווח.
/// ביטוי מחושב, טוקן ו־`double.infinity` לא נתפסים. ציור תוכן ו־`pw.*` מוחרגים.
class SpacingScaleRule extends UiLintRule {
  const SpacingScaleRule();

  static const scale = {0, 2, 4, 8, 12, 16, 24, 32};
  static const _insets = {'EdgeInsets', 'EdgeInsetsDirectional'};
  static const _maxGap = 32;

  @override
  String get id => 'UIL-020';

  @override
  int get stage => 3;

  @override
  String get title => 'ריווח מחוץ לסולם';

  @override
  String get hint =>
      'AppTokens.space* (2/4/8/12/16/24/32) או טוקן סמנטי; ערך מחוץ לסולם '
      'עולה לערך הבא: 6→8, 10→12, 14→16 (DESIGN_SYSTEM.md §2.2, DD-03)';

  @override
  void check(UiLintFile file) => file.unit.accept(_Visitor(this, file));
}

class _Visitor extends RecursiveAstVisitor<void> {
  _Visitor(this.rule, this.file);

  final SpacingScaleRule rule;
  final UiLintFile file;

  static double? _literal(Expression e) {
    final x = e.unParenthesized;
    if (x is IntegerLiteral) return x.value?.toDouble();
    if (x is DoubleLiteral) return x.value;
    return null;
  }

  static bool _offScale(double v) =>
      v != v.roundToDouble() || !SpacingScaleRule.scale.contains(v.toInt());

  void _check(Expression node) {
    final call = asCtorCall(node);
    if (call == null || call.importPrefix != null) return;
    final Iterable<Expression> values;
    if (SpacingScaleRule._insets.contains(call.typeName)) {
      values = [
        for (final a in call.arguments.arguments)
          if (a is NamedArgument)
            a.argumentExpression
          else if (a is Expression)
            a,
      ];
    } else if (call.typeName == 'SizedBox' &&
        call.constructor == null &&
        call.named('child') == null) {
      values = [?call.named('width'), ?call.named('height')].where((e) {
        final v = _literal(e);
        return v != null && v < SpacingScaleRule._maxGap;
      });
    } else {
      return;
    }
    final offScale = values.any((e) {
      final v = _literal(e);
      return v != null && _offScale(v);
    });
    if (offScale && !isInsideClassExtending(node, const {'CustomPainter'})) {
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
