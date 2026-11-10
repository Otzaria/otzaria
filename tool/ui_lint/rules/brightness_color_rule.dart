import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../ast_helpers.dart';
import '../ui_lint.dart';

/// UIL-027: החלטת צבע לפי בהירות בקוד פיצ'ר (הכרעת בעל הפרויקט, 10.11.2026):
/// תנאי על `isDark`/`Brightness.dark` שהענפים שלו צבעים. ערכת הנושא כבר נבנית
/// לכל בהירות, ולכן הצבע בא מתפקיד ב־`colorScheme` או ב־`AppSurfaces`, בלי תנאי.
///
/// נתפסים: `isDark ? X : Y`, ‏`if (isDark) … else …` שכל ענף בו מחזיר או מציב
/// צבע, ו־`switch` שאחד המקרים בו `Brightness.dark` והגופים צבעים. "צבע":
/// `Color(...)`, ‏`Colors.*`, תפקיד של `cs`/`colorScheme`/`scheme`,
/// `AppSurfaces.*`/`AppColors.*` (גם `AppSurfaces.card(context)`),
/// `Color.lerp`/`alphaBlend`, ו־`.withValues(...)` ודומיו על אחד מאלה. תנאי בהירות שאינו בוחר צבע (סרגל המערכת, שם קובץ,
/// זרע הערכה) לא נתפס.
class BrightnessColorRule extends UiLintRule {
  const BrightnessColorRule();

  @override
  String get id => 'UIL-027';

  @override
  int get stage => 3;

  @override
  String get title => 'החלטת צבע לפי isDark/Brightness.dark';

  @override
  String get hint =>
      'תפקיד מ־colorScheme או AppSurfaces, שכבר שונה בין בהיר לכהה '
      '(DESIGN_SYSTEM.md §2.1)';

  @override
  void check(UiLintFile file) => file.unit.accept(_Visitor(this, file));
}

final _darkName = RegExp(r'^_?(is)?[dD]ark(Mode|Theme)?$');
const _schemeNames = {'cs', 'colorScheme', 'scheme', 'colors'};
const _palettes = {'Colors', 'CupertinoColors', 'AppSurfaces', 'AppColors'};
const _alphaMethods = {'withValues', 'withAlpha', 'withOpacity'};

/// האם [condition] בודק בהירות כהה.
bool _isDarkCondition(Expression condition) {
  var found = false;
  condition.accept(_DarkFinder(() => found = true));
  return found;
}

class _DarkFinder extends RecursiveAstVisitor<void> {
  _DarkFinder(this.onFound);

  final void Function() onFound;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (_darkName.hasMatch(node.name)) onFound();
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (node.prefix.name == 'Brightness' && node.identifier.name == 'dark') {
      onFound();
    }
    super.visitPrefixedIdentifier(node);
  }
}

/// ביטוי שערכו צבע, לפי הצורה בלבד (AST לא מפוענח).
bool _isColor(Expression? expression) {
  final e = expression?.unParenthesized;
  if (e == null) return false;
  if (e is ConditionalExpression) {
    return _isColor(e.thenExpression) && _isColor(e.elseExpression);
  }
  if (e is PrefixedIdentifier) {
    return _palettes.contains(e.prefix.name) ||
        _schemeNames.contains(e.prefix.name);
  }
  if (e is PropertyAccess) {
    final target = e.realTarget;
    final name = switch (target) {
      SimpleIdentifier(:final name) => name,
      PropertyAccess(:final propertyName) => propertyName.name,
      PrefixedIdentifier(:final identifier) => identifier.name,
      _ => null,
    };
    return _schemeNames.contains(name) ||
        (target is SimpleIdentifier && _palettes.contains(target.name));
  }
  if (e is MethodInvocation) {
    if (_alphaMethods.contains(e.methodName.name)) return _isColor(e.target);
    final target = e.target;
    // AppSurfaces.card(context)
    if (target is SimpleIdentifier && _palettes.contains(target.name)) {
      return true;
    }
    if (target is SimpleIdentifier &&
        target.name == 'Color' &&
        {'lerp', 'alphaBlend'}.contains(e.methodName.name)) {
      return true;
    }
  }
  final call = asCtorCall(e);
  return call != null &&
      call.typeName == 'Color' &&
      call.importPrefix == null &&
      {null, 'fromARGB', 'fromRGBO', 'from'}.contains(call.constructor);
}

/// הצבע שענף של if מחזיר או מציב, אם הענף הוא רק זה.
bool _branchIsColor(Statement? statement) {
  var s = statement;
  if (s is Block) {
    if (s.statements.length != 1) return false;
    s = s.statements.single;
  }
  if (s is ReturnStatement) return _isColor(s.expression);
  if (s is ExpressionStatement) {
    final e = s.expression;
    return e is AssignmentExpression && _isColor(e.rightHandSide);
  }
  if (s is IfStatement) return _ifIsColor(s);
  return false;
}

bool _ifIsColor(IfStatement node) =>
    node.elseStatement != null &&
    _branchIsColor(node.thenStatement) &&
    _branchIsColor(node.elseStatement);

class _Visitor extends RecursiveAstVisitor<void> {
  _Visitor(this.rule, this.file);

  final BrightnessColorRule rule;
  final UiLintFile file;

  bool _excluded(AstNode node) =>
      isInsideClassExtending(node, const {'CustomPainter'});

  @override
  void visitConditionalExpression(ConditionalExpression node) {
    if (_isDarkCondition(node.condition) &&
        _isColor(node.thenExpression) &&
        _isColor(node.elseExpression) &&
        !_excluded(node)) {
      file.report(rule, node);
      // ענפים מקוננים כבר נספרו בצומת הזה.
      return;
    }
    super.visitConditionalExpression(node);
  }

  @override
  void visitIfStatement(IfStatement node) {
    if (_isDarkCondition(node.expression) &&
        _ifIsColor(node) &&
        !_excluded(node)) {
      file.report(rule, node, identity: 'if (${node.expression.toSource()})');
      return;
    }
    super.visitIfStatement(node);
  }

  @override
  void visitSwitchExpression(SwitchExpression node) {
    final darkCase =
        _isDarkCondition(node.expression) ||
        node.cases.any((c) {
          final pattern = c.guardedPattern.pattern;
          return pattern is ConstantPattern &&
              _isDarkCondition(pattern.expression);
        });
    if (darkCase &&
        node.cases.every((c) => _isColor(c.expression)) &&
        !_excluded(node)) {
      file.report(rule, node, identity: 'switch (${node.expression})');
      return;
    }
    super.visitSwitchExpression(node);
  }
}
