import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../ast_helpers.dart';
import '../ui_lint.dart';

/// UIL-017: `fontSize:` ליטרלי בסגנון טקסט של ממשק.
class LiteralFontSizeRule extends UiLintRule {
  const LiteralFontSizeRule();

  @override
  String get id => 'UIL-017';

  @override
  int get stage => 3;

  @override
  String get title => 'fontSize ליטרלי';

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

  @override
  void visitNamedArgument(NamedArgument node) {
    if (node.name.lexeme == 'fontSize' &&
        isNumericLiteral(node.argumentExpression) &&
        _isTextStyle(node.parent?.parent)) {
      file.report(rule, node);
    }
    super.visitNamedArgument(node);
  }
}
