import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../ast_helpers.dart';
import '../ui_lint.dart';

/// UIL-015: צבע קשיח (`Color(0x…)`, `Color.fromARGB(…)` מליטרלים,
/// `Colors.<גוון>`, `CupertinoColors.<גוון>`) מחוץ לשכבת הטוקנים.
class HardcodedColorRule extends UiLintRule {
  const HardcodedColorRule();

  static const _colorConstructors = {null, 'fromARGB', 'fromRGBO', 'from'};

  @override
  String get id => 'UIL-015';

  @override
  int get stage => 3;

  @override
  String get title => 'צבע קשיח';

  @override
  String get hint =>
      'תפקיד מ-colorScheme או AppSurfaces (DESIGN_SYSTEM.md §2.1, חריגים §2.1.3)';

  @override
  void check(UiLintFile file) => file.unit.accept(_Visitor(this, file));
}

class _Visitor extends RecursiveAstVisitor<void> {
  _Visitor(this.rule, this.file);

  final HardcodedColorRule rule;
  final UiLintFile file;

  static const _palettes = {'Colors', 'CupertinoColors'};

  bool _inPainter(AstNode node) =>
      isInsideClassExtending(node, const {'CustomPainter'});

  bool _inBoxShadow(AstNode node) =>
      enclosingCtorCall(node, (c) => c.typeName == 'BoxShadow') != null;

  void _checkCall(Expression node) {
    final call = asCtorCall(node);
    if (call == null ||
        call.typeName != 'Color' ||
        call.importPrefix != null ||
        !HardcodedColorRule._colorConstructors.contains(call.constructor) ||
        // Color(value) שממיר ערך מחושב אינו צבע קשיח.
        !call.positional.every(isNumericLiteral) ||
        _inPainter(node)) {
      return;
    }
    file.report(rule, node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    _checkCall(node);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    _checkCall(node);
    super.visitMethodInvocation(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    final name = node.identifier.name;
    if (_palettes.contains(node.prefix.name) &&
        name != 'transparent' &&
        !_inPainter(node) &&
        !((name.startsWith('white') || name.startsWith('black')) &&
            _inBoxShadow(node))) {
      file.report(rule, node);
    }
    super.visitPrefixedIdentifier(node);
  }
}
