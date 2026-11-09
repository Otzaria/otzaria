import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../ast_helpers.dart';
import '../ui_lint.dart';

/// UIL-004: `Theme.of(context).primaryColor` הוא surface במצב כהה, לא primary.
class PrimaryColorRule extends UiLintRule {
  const PrimaryColorRule();

  @override
  String get id => 'UIL-004';

  @override
  int get stage => 1;

  @override
  String get title => 'Theme.primaryColor';

  @override
  String get hint => 'colorScheme.primary (DESIGN_SYSTEM.md §2.1.1)';

  @override
  void check(UiLintFile file) => file.unit.accept(_Visitor(this, file));
}

final _themeVariable = RegExp('theme', caseSensitive: false);

class _Visitor extends RecursiveAstVisitor<void> {
  _Visitor(this.rule, this.file);

  final PrimaryColorRule rule;
  final UiLintFile file;

  @override
  void visitPropertyAccess(PropertyAccess node) {
    final target = node.realTarget;
    if (node.propertyName.name == 'primaryColor' &&
        target is MethodInvocation &&
        target.methodName.name == 'of' &&
        asCtorCall(target)?.typeName == 'Theme') {
      file.report(rule, node);
    }
    super.visitPropertyAccess(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (node.identifier.name == 'primaryColor' &&
        _themeVariable.hasMatch(node.prefix.name)) {
      file.report(rule, node);
    }
    super.visitPrefixedIdentifier(node);
  }
}
