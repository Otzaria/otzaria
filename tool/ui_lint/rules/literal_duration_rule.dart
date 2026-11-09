import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../ast_helpers.dart';
import '../ui_lint.dart';

/// UIL-023: משך אנימציה ליטרלי (`Duration(milliseconds: 200)`) בפרמטר
/// `duration:`/`reverseDuration:` של אנימציית ממשק:
/// - רכיב `Animated*` או `TweenAnimationBuilder`;
/// - `AnimationController(...)`;
/// - גלילה מונפשת: `animateTo`, `scrollTo`, `animateToPage`, `nextPage`,
///   `previousPage`, `ensureVisible`.
///
/// משך של אנימציית ממשק עובר דרך `AppMotion.duration(context, AppTokens.anim*)`,
/// שמכבד הפחתת תנועה (DD-21). גם `AppMotion.duration(context, const
/// Duration(...))` תקין: הוא עובר דרך AppMotion, ולכן מתאפס בהפחתת תנועה.
/// timeout, debounce, `Future.delayed` ו־`waitDuration` של Tooltip אינם
/// אנימציה ולא נתפסים. `Duration.zero` ו־0 מותרים.
class LiteralDurationRule extends UiLintRule {
  const LiteralDurationRule();

  @override
  String get id => 'UIL-023';

  @override
  int get stage => 3;

  @override
  String get title => 'משך אנימציה ליטרלי';

  @override
  String get hint =>
      'AppMotion.duration(context, AppTokens.anim*) (DESIGN_SYSTEM.md §2.5.5, '
      'DD-21)';

  @override
  void check(UiLintFile file) => file.unit.accept(_Visitor(this, file));
}

class _Visitor extends RecursiveAstVisitor<void> {
  _Visitor(this.rule, this.file);

  final LiteralDurationRule rule;
  final UiLintFile file;

  static const _names = {'duration', 'reverseDuration'};
  static const _scrollMethods = {
    'animateTo',
    'scrollTo',
    'animateToPage',
    'nextPage',
    'previousPage',
    'ensureVisible',
  };

  static bool _isAnimation(AstNode owner) {
    if (owner is MethodInvocation &&
        owner.target != null &&
        _scrollMethods.contains(owner.methodName.name)) {
      return true;
    }
    final call = asCtorCall(owner);
    return call != null &&
        call.importPrefix == null &&
        (call.typeName.startsWith('Animated') ||
            call.typeName == 'TweenAnimationBuilder' ||
            (call.typeName == 'AnimationController' &&
                call.constructor == null));
  }

  static bool _isLiteralDuration(Expression e) {
    final call = asCtorCall(e.unParenthesized);
    if (call == null || call.typeName != 'Duration') return false;
    return call.arguments.arguments.any((a) {
      final Expression? x = a is NamedArgument
          ? a.argumentExpression
          : (a is Expression ? a : null);
      final v = x?.unParenthesized;
      return (v is IntegerLiteral && v.value != 0) ||
          (v is DoubleLiteral && v.value != 0);
    });
  }

  @override
  void visitNamedArgument(NamedArgument node) {
    if (_names.contains(node.name.lexeme) &&
        _isLiteralDuration(node.argumentExpression)) {
      final owner = node.parent?.parent;
      if (owner != null && _isAnimation(owner)) file.report(rule, node);
    }
    super.visitNamedArgument(node);
  }
}
