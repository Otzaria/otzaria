import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../ast_helpers.dart';
import '../ui_lint.dart';

/// UIL-029: גודל אייקון שאינו טוקן (DD-03): `size:` ליטרלי ב־`Icon`/`RtlIcon`/
/// `ImageIcon`, `iconSize:` ליטרלי בכל מקום, ו־`AppTokens.font*` כגודל אייקון.
///
/// ביטוי מחושב (`size * 0.8`) לא נתפס. CustomPainter ו־`pw.*` מוחרגים.
class IconSizeRule extends UiLintRule {
  const IconSizeRule();

  static const _icons = {'Icon', 'RtlIcon', 'ImageIcon'};

  @override
  String get id => 'UIL-029';

  @override
  int get stage => 3;

  @override
  String get title => 'גודל אייקון שאינו טוקן';

  @override
  String get hint =>
      'AppTokens.iconXS/SM/MD/LG/XL (14/16/20/24/48), או גודל ברירת המחדל '
      'מ־IconTheme (DESIGN_SYSTEM.md §2.5.1, DD-03)';

  @override
  void check(UiLintFile file) => file.unit.accept(_Visitor(this, file));
}

class _Visitor extends RecursiveAstVisitor<void> {
  _Visitor(this.rule, this.file);

  final IconSizeRule rule;
  final UiLintFile file;

  static bool _notToken(Expression e) {
    if (isNumericLiteral(e)) return true;
    final x = e.unParenthesized;
    return x is PrefixedIdentifier &&
        x.prefix.name == 'AppTokens' &&
        x.identifier.name.startsWith('font');
  }

  @override
  void visitNamedArgument(NamedArgument node) {
    final name = node.name.lexeme;
    if ((name == 'size' || name == 'iconSize') &&
        _notToken(node.argumentExpression) &&
        !isInsideClassExtending(node, const {'CustomPainter'})) {
      final owner = node.parent?.parent;
      final call = owner == null ? null : asCtorCall(owner);
      final ownerOk = call?.importPrefix != 'pw';
      final isIcon =
          name == 'iconSize' ||
          (call != null &&
              call.importPrefix == null &&
              IconSizeRule._icons.contains(call.typeName));
      if (isIcon && ownerOk) file.report(rule, node);
    }
    super.visitNamedArgument(node);
  }
}
