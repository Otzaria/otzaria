import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../ast_helpers.dart';
import '../ui_lint.dart';

/// UIL-008: `ScaffoldMessenger` או `SnackBar(` במקום `UiSnack`.
///
/// כל שימוש בשם `ScaffoldMessenger` נתפס (`.of`, `.maybeOf`, בנאי), וכן כל בנאי
/// `SnackBar`. ‏`ScaffoldMessengerState` (טיפוס של מפתח) אינו שם אחר ולא נתפס.
class SnackBarRule extends UiLintRule {
  const SnackBarRule();

  @override
  String get id => 'UIL-008';

  @override
  int get stage => 1;

  @override
  String get title => 'ScaffoldMessenger/SnackBar';

  @override
  String get hint =>
      'UiSnack.show / showError / showSuccess, עם הודעה מקטלוג '
      '(DESIGN_SYSTEM.md §3.5)';

  @override
  void check(UiLintFile file) {
    for (final call in ctorCallsNamed(file.unit, {'SnackBar'})) {
      if (call.importPrefix == null) {
        file.report(this, call.node, identity: call.head);
      }
    }
    file.unit.accept(_Visitor(this, file));
  }
}

class _Visitor extends RecursiveAstVisitor<void> {
  _Visitor(this.rule, this.file);

  final SnackBarRule rule;
  final UiLintFile file;

  static const _name = 'ScaffoldMessenger';

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.name == _name) file.report(rule, node);
    super.visitSimpleIdentifier(node);
  }

  /// `const ScaffoldMessenger(...)` ו־`new ScaffoldMessenger(...)`: שם הטיפוס
  /// בבנאי הוא NamedType ולא SimpleIdentifier.
  @override
  void visitNamedType(NamedType node) {
    if (node.importPrefix == null && node.name.lexeme == _name) {
      file.report(rule, node);
    }
    super.visitNamedType(node);
  }
}
