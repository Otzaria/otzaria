import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../ast_helpers.dart';
import '../ui_lint.dart';

/// UIL-017: `fontSize:` ליטרלי בסגנון טקסט של ממשק, וגם `AppTokens.font*` או
/// חשבון עליו (`AppTokens.fontSM - 1`): הטוקנים האלה שייכים לשכבת ה־Theme (DD-02).
/// גם שינוי גודל ליטרלי ב־`.apply(fontSizeDelta:/fontSizeFactor:)` של
/// `TextStyle`/`TextTheme` הוא גודל מספרי בקוד פיצ'ר.
class LiteralFontSizeRule extends UiLintRule {
  const LiteralFontSizeRule();

  @override
  String get id => 'UIL-017';

  @override
  int get stage => 3;

  @override
  String get title => 'fontSize ליטרלי או מ־AppTokens.font*';

  @override
  String get hint => 'Theme.of(context).textTheme.* (DESIGN_SYSTEM.md §2.4.1)';

  @override
  void check(UiLintFile file) => file.unit.accept(_Visitor(this, file));
}

class _Visitor extends RecursiveAstVisitor<void> {
  _Visitor(this.rule, this.file);

  final LiteralFontSizeRule rule;
  final UiLintFile file;

  bool _isTextStyle(AstNode? invocation) {
    if (invocation is MethodInvocation &&
        invocation.methodName.name == 'copyWith') {
      return true;
    }
    final call = invocation == null ? null : asCtorCall(invocation);
    return call != null &&
        call.typeName == 'TextStyle' &&
        call.constructor == null &&
        call.importPrefix == null;
  }

  static bool _isApply(AstNode? invocation) =>
      invocation is MethodInvocation &&
      invocation.target != null &&
      invocation.methodName.name == 'apply';

  @override
  void visitNamedArgument(NamedArgument node) {
    final value = node.argumentExpression;
    final name = node.name.lexeme;
    final owner = node.parent?.parent;
    if ((isNumericLiteral(value) || _usesFontToken(value)) &&
        ((name == 'fontSize' && _isTextStyle(owner)) ||
            ((name == 'fontSizeDelta' || name == 'fontSizeFactor') &&
                _isApply(owner)))) {
      file.report(rule, node);
    }
    super.visitNamedArgument(node);
  }
}

/// `AppTokens.font*` בתוך הביטוי, גם בחשבון (`AppTokens.fontSM - 1`).
bool _usesFontToken(Expression expression) {
  final finder = _FontTokenFinder();
  expression.accept(finder);
  return finder.found;
}

class _FontTokenFinder extends RecursiveAstVisitor<void> {
  bool found = false;

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (node.prefix.name == 'AppTokens' &&
        node.identifier.name.startsWith('font')) {
      found = true;
    }
  }
}
