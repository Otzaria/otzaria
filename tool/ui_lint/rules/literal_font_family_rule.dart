import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../ui_lint.dart';

/// UIL-018: `fontFamily:` ליטרלי (כולל 'Roboto') מחוץ לשכבת הטוקנים.
///
/// גופן הממשק ורשימת ה־fallback של DD-01 חיים רק ב־`AppThemeData`, גופני
/// התוכן ב־`AppFonts`, ומשפחת המונוספייס ב־`AppTextStyles.monospaceFamily`.
class LiteralFontFamilyRule extends UiLintRule {
  const LiteralFontFamilyRule();

  @override
  String get id => 'UIL-018';

  @override
  int get stage => 2;

  @override
  String get title => 'fontFamily ליטרלי';

  @override
  String get hint =>
      'בלי fontFamily (גופן הממשק מה־Theme), AppFonts.* לגופן תוכן, '
      'AppTextStyles.monospaceFamily למונוספייס (DESIGN_SYSTEM.md §2.4.1)';

  @override
  void check(UiLintFile file) => file.unit.accept(_Visitor(this, file));
}

class _Visitor extends RecursiveAstVisitor<void> {
  _Visitor(this.rule, this.file);

  final LiteralFontFamilyRule rule;
  final UiLintFile file;

  @override
  void visitNamedArgument(NamedArgument node) {
    if (node.name.lexeme == 'fontFamily' &&
        node.argumentExpression.unParenthesized is StringLiteral) {
      file.report(rule, node);
    }
    super.visitNamedArgument(node);
  }
}
