import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../ui_lint.dart';

/// UIL-005: אייקוני Material/Cupertino.
class MaterialIconsRule extends UiLintRule {
  const MaterialIconsRule();

  static const _sets = {'Icons', 'CupertinoIcons'};

  @override
  String get id => 'UIL-005';

  @override
  String get title => 'אייקון Material/Cupertino';

  @override
  String get hint => 'OtzariaIcons או FluentIcons (DESIGN_SYSTEM.md §2.5.1)';

  @override
  void check(UiLintFile file) => file.unit.accept(_Visitor(this, file));
}

class _Visitor extends RecursiveAstVisitor<void> {
  _Visitor(this.rule, this.file);

  final MaterialIconsRule rule;
  final UiLintFile file;

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (MaterialIconsRule._sets.contains(node.prefix.name)) {
      file.report(rule, node);
    }
    super.visitPrefixedIdentifier(node);
  }
}
