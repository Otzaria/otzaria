import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../ast_helpers.dart';
import '../ui_lint.dart';

/// UIL-005: אייקוני Material/Cupertino.
class MaterialIconsRule extends UiLintRule {
  const MaterialIconsRule();

  static const _sets = {'Icons', 'CupertinoIcons'};

  @override
  String get id => 'UIL-005';

  @override
  int get stage => 1;

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

  /// `m.Icons.close`, כש־m הוא prefix של ייבוא Flutter.
  @override
  void visitPropertyAccess(PropertyAccess node) {
    final target = node.target;
    if (target is PrefixedIdentifier &&
        MaterialIconsRule._sets.contains(target.identifier.name) &&
        flutterImportPrefixes(node.root).contains(target.prefix.name)) {
      file.report(rule, node);
    }
    super.visitPropertyAccess(node);
  }
}
