import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../ast_helpers.dart';
import '../ui_lint.dart';

/// UIL-016: שקיפות מקומית על צבע (`.withValues(alpha:)`, `.withAlpha(`,
/// `.withOpacity(`) מחוץ לשכבת הטוקנים.
///
/// שקיפות של צבע ממשק היא תפקיד: מצב (`AppSurfaces.hoverRow`), משטח
/// (`AppSurfaces.panelSection`) או מפריד (`AppSurfaces.subtleDivider`).
/// מוחרגים: ציור תוכן ב־`CustomPainter`, ייצוא (`pw.*` ונתיבי הייצוא ב־config),
/// וצבע הצל בתוך `BoxShadow(...)`, שנספר פעם אחת ב־UIL-030.
class LocalAlphaRule extends UiLintRule {
  const LocalAlphaRule();

  static const _methods = {'withValues', 'withAlpha', 'withOpacity'};

  @override
  String get id => 'UIL-016';

  @override
  int get stage => 3;

  @override
  String get title => 'שקיפות מקומית על צבע';

  @override
  String get hint =>
      'תפקיד מ־AppSurfaces (מצב, משטח, מפריד), או פונקציה חדשה שם '
      '(DESIGN_SYSTEM.md §2.1, ‏2.1.1)';

  @override
  void check(UiLintFile file) => file.unit.accept(_Visitor(this, file));
}

class _Visitor extends RecursiveAstVisitor<void> {
  _Visitor(this.rule, this.file);

  final LocalAlphaRule rule;
  final UiLintFile file;

  bool _setsAlpha(MethodInvocation node) {
    final name = node.methodName.name;
    if (!LocalAlphaRule._methods.contains(name)) return false;
    if (name != 'withValues') return true;
    return node.argumentList.arguments.any(
      (a) => a is NamedArgument && a.name.lexeme == 'alpha',
    );
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.target != null &&
        _setsAlpha(node) &&
        !isInsideClassExtending(node, const {'CustomPainter'}) &&
        enclosingCtorCall(
              node,
              (c) => c.typeName == 'BoxShadow' || c.importPrefix == 'pw',
            ) ==
            null) {
      file.report(rule, node);
    }
    super.visitMethodInvocation(node);
  }
}
