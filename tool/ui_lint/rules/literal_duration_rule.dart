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
/// גם קבוע מקומי שמאותחל ב־`Duration(<מספר>)` ועובר כ־`duration:` של אנימציית
/// ממשק (`duration: _kAnimDuration`) הוא משך ליטרלי שהוסתר מאחורי שם.
///
/// גלילה לשורה (`scrollToLine(duration:)`) היא ניווט ולא אנימציית ממשק
/// (הכרעת בעל הפרויקט 18.11): הכלל לא מסתכל עליה. מי שרוצה קפיצה בלי אנימציה
/// כותב `Duration.zero` במפורש.
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
  void check(UiLintFile file) {
    final constants = <String>{};
    file.unit.accept(_ConstantCollector(constants));
    file.unit.accept(_Visitor(this, file, constants));
  }
}

/// שמות של משתנים/שדות בקובץ שמאותחלים ב־`Duration(<מספר>)`.
class _ConstantCollector extends RecursiveAstVisitor<void> {
  _ConstantCollector(this.names);

  final Set<String> names;

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    final init = node.initializer;
    if (init != null && _Visitor._isLiteralDuration(init)) {
      names.add(node.name.lexeme);
    }
    super.visitVariableDeclaration(node);
  }
}

class _Visitor extends RecursiveAstVisitor<void> {
  _Visitor(this.rule, this.file, this.constants);

  final LiteralDurationRule rule;
  final UiLintFile file;
  final Set<String> constants;

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
    final value = node.argumentExpression.unParenthesized;
    if (_names.contains(node.name.lexeme) &&
        (_isLiteralDuration(value) ||
            (value is SimpleIdentifier && constants.contains(value.name)))) {
      final owner = node.parent?.parent;
      if (owner != null && _isAnimation(owner)) file.report(rule, node);
    }
    super.visitNamedArgument(node);
  }
}
