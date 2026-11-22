import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../ast_helpers.dart';
import '../ui_lint.dart';

/// UIL-020: ריווח מחוץ לסולם (DD-03): ליטרל ב־`EdgeInsets*` או ב־`SizedBox`
/// מרווח שאינו 0/2/4/8/12/16/24/32.
///
/// - `EdgeInsets.*`/`EdgeInsetsDirectional.*`: כל ארגומנט ליטרלי.
/// - `SizedBox(width:/height:)` ו־`SizedBox.square(dimension:)` בלי `child`, עם
///   ערך קטן מ־32: זה מרווח. קופסה עם ילד, או גודל של 32 ומעלה, היא מידה של
///   רכיב ולא ריווח.
/// - `spacing:`/`runSpacing:` של `Wrap`/`Row`/`Column`/`Flex`, ו־
///   `mainAxisSpacing:`/`crossAxisSpacing:` של `GridView` ושל
///   `SliverGridDelegateWith*`. רכיב גאומטריה בעל פרמטר `spacing:` משלו
///   (`SkeletonLines`) לא נתפס, כי רק הבעלים שברשימה נבדקים.
/// - ביטוי מחושב על טוקן ריווח או גודל אייקון: `AppTokens.spaceSM + 1`,
///   `AppTokens.spaceMD - 4`. הערך המחושב יוצא מהסולם ועוקף את בדיקת הליטרל.
///   כפל (`spaceSM * 2`) הוא מכפלה של הטוקן ולא היסט, ולכן לא נתפס; גופן
///   מחושב נתפס ב־UIL-017.
/// ביטוי אחר, טוקן ו־`double.infinity` לא נתפסים. ציור תוכן ו־`pw.*` מוחרגים.
class SpacingScaleRule extends UiLintRule {
  const SpacingScaleRule();

  static const scale = {0, 2, 4, 8, 12, 16, 24, 32};
  static const _insets = {'EdgeInsets', 'EdgeInsetsDirectional'};
  static const _maxGap = 32;
  static const _spacingOwners = {
    'Wrap',
    'Row',
    'Column',
    'Flex',
    'GridView',
    'SliverGridDelegateWithFixedCrossAxisCount',
    'SliverGridDelegateWithMaxCrossAxisExtent',
  };
  static const _spacingNames = {
    'spacing',
    'runSpacing',
    'mainAxisSpacing',
    'crossAxisSpacing',
  };

  @override
  String get id => 'UIL-020';

  @override
  int get stage => 3;

  @override
  String get title => 'ריווח מחוץ לסולם';

  @override
  String get hint =>
      'AppTokens.space* (2/4/8/12/16/24/32) או טוקן סמנטי; ערך מחוץ לסולם '
      'עולה לערך הבא: 6→8, 10→12, 14→16, וגם בלי חישוב על טוקן '
      '(space + 1) (DESIGN_SYSTEM.md §2.2, DD-03)';

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
        (call.constructor == null || call.constructor == 'square') &&
        call.named('child') == null) {
      values =
          [
            ?call.named('width'),
            ?call.named('height'),
            ?call.named('dimension'),
          ].where((e) {
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

  static bool _isScaleToken(Expression e) {
    final x = e.unParenthesized;
    return x is PrefixedIdentifier &&
        x.prefix.name == 'AppTokens' &&
        (x.identifier.name.startsWith('space') ||
            x.identifier.name.startsWith('icon'));
  }

  @override
  void visitNamedArgument(NamedArgument node) {
    final v = _literal(node.argumentExpression);
    if (v != null &&
        SpacingScaleRule._spacingNames.contains(node.name.lexeme) &&
        _offScale(v)) {
      final owner = node.parent?.parent;
      final call = owner == null ? null : asCtorCall(owner);
      if (call != null &&
          call.importPrefix == null &&
          SpacingScaleRule._spacingOwners.contains(call.typeName) &&
          !isInsideClassExtending(node, const {'CustomPainter'})) {
        file.report(rule, node);
      }
    }
    super.visitNamedArgument(node);
  }

  @override
  void visitBinaryExpression(BinaryExpression node) {
    final op = node.operator.lexeme;
    if ((op == '+' || op == '-') &&
        ((_isScaleToken(node.leftOperand) &&
                isNumericLiteral(node.rightOperand)) ||
            (_isScaleToken(node.rightOperand) &&
                isNumericLiteral(node.leftOperand))) &&
        !isInsideClassExtending(node, const {'CustomPainter'})) {
      file.report(rule, node);
    }
    super.visitBinaryExpression(node);
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
