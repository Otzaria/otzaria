import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../ast_helpers.dart';
import '../ui_lint.dart';

/// UIL-007: `hoverColor:`/`splashColor:`/`overlayColor:` מקומי מחוץ ל־lib/theme.
///
/// צבעי המצב באים מערכת הנושא (`_hoverButtonStyle`, DD-06). מותר:
/// - ערך מ־`AppSurfaces.*` (הבעלים של צבעי המצב, למשל `hoverRow`), גם בענף
///   של תנאי שהענף השני שלו `null` (ברירת המחדל של ערכת הנושא), למשל ריחוף
///   רק במצב בחירה;
/// - `Colors.transparent` (גם בענף של תנאי) ב־`ListTile` שיש לו `onTap:` וגם
///   `trailing:`, כדי שהריחוף של השורה לא יתחרה בכפתורים שבתוכה (החריג
///   המתועד ב־DESIGN_SYSTEM §2.1 ו־CI_ENFORCEMENT §3.3). ב־`ListTile` בלי
///   `onTap` אין ריחוף, ולכן `Colors.transparent` שם הוא קוד מת ונתפס.
class StateColorOverrideRule extends UiLintRule {
  const StateColorOverrideRule();

  static const _names = {'hoverColor', 'splashColor', 'overlayColor'};

  @override
  String get id => 'UIL-007';

  @override
  int get stage => 1;

  @override
  String get title => 'hoverColor/splashColor/overlayColor מקומי';

  @override
  String get hint =>
      'צבע המצב מערכת הנושא, או AppSurfaces.hoverRow וכדומה '
      '(DESIGN_SYSTEM.md §2.1, DD-06)';

  @override
  void check(UiLintFile file) => file.unit.accept(_Visitor(this, file));
}

class _Visitor extends RecursiveAstVisitor<void> {
  _Visitor(this.rule, this.file);

  final StateColorOverrideRule rule;
  final UiLintFile file;

  static bool _isSurfaceToken(Expression e) {
    final x = e.unParenthesized;
    if (x is ConditionalExpression) {
      bool tokenOrNull(Expression b) =>
          b.unParenthesized is NullLiteral || _isSurfaceToken(b);
      return tokenOrNull(x.thenExpression) &&
          tokenOrNull(x.elseExpression) &&
          (_isSurfaceToken(x.thenExpression) ||
              _isSurfaceToken(x.elseExpression));
    }
    if (x is MethodInvocation) {
      final target = x.target;
      return target is SimpleIdentifier && target.name == 'AppSurfaces';
    }
    return x is PrefixedIdentifier && x.prefix.name == 'AppSurfaces';
  }

  static bool _isTransparentOrNull(Expression e) {
    final x = e.unParenthesized;
    if (x is NullLiteral) return true;
    if (x is PrefixedIdentifier) {
      return x.prefix.name == 'Colors' && x.identifier.name == 'transparent';
    }
    if (x is ConditionalExpression) {
      return _isTransparentOrNull(x.thenExpression) &&
          _isTransparentOrNull(x.elseExpression);
    }
    return false;
  }

  bool _inActionListTile(NamedArgument node) {
    final call = asCtorCall(node.parent!.parent!);
    if (call == null || call.typeName != 'ListTile') return false;
    final names = {
      for (final arg in call.arguments.arguments)
        if (arg is NamedArgument) arg.name.lexeme,
    };
    return names.contains('onTap') && names.contains('trailing');
  }

  @override
  void visitNamedArgument(NamedArgument node) {
    if (StateColorOverrideRule._names.contains(node.name.lexeme)) {
      final value = node.argumentExpression;
      final allowed =
          _isSurfaceToken(value) ||
          (node.name.lexeme == 'hoverColor' &&
              _isTransparentOrNull(value) &&
              _inActionListTile(node));
      if (!allowed) file.report(rule, node);
    }
    super.visitNamedArgument(node);
  }
}
