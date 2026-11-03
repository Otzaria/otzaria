import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../ast_helpers.dart';
import '../ui_lint.dart';

/// UIL-021: כיוון פיזי (שמאל/ימין) בפריסה, במקום כיוון לפי הטקסט.
///
/// - `EdgeInsets.only(left:/right:)` ו־`EdgeInsets.fromLTRB(...)`;
/// - `Alignment.centerLeft`/`topRight` וכו';
/// - `Positioned(left:/right:)`.
///
/// ערך סימטרי לא תלוי כיוון ולכן מותר (JX-20): `fromLTRB(a, b, a, c)`,
/// `only(left: x, right: x)`, `Positioned(left: x, right: x)`.
/// ציור ב־CustomPainter ו־`pw.*` מוחרגים; גאומטריה אחרת — allow עם נימוק.
class PhysicalDirectionRule extends UiLintRule {
  const PhysicalDirectionRule();

  static const _alignments = {
    'centerLeft',
    'centerRight',
    'topLeft',
    'topRight',
    'bottomLeft',
    'bottomRight',
  };

  @override
  String get id => 'UIL-021';

  @override
  int get stage => 3;

  @override
  String get title => 'כיוון פיזי (left/right) בפריסה';

  @override
  String get hint =>
      'EdgeInsetsDirectional (start/end), AlignmentDirectional, '
      'Positioned.directional (DESIGN_SYSTEM.md §2.2, §6.1)';

  @override
  void check(UiLintFile file) => file.unit.accept(_Visitor(this, file));
}

class _Visitor extends RecursiveAstVisitor<void> {
  _Visitor(this.rule, this.file);

  final PhysicalDirectionRule rule;
  final UiLintFile file;

  bool _excluded(AstNode node) =>
      isInsideClassExtending(node, const {'CustomPainter'});

  /// left/right שנמסרו, ושאינם אותו ביטוי בשני הצדדים.
  static bool _asymmetric(CtorCall call) {
    final left = call.named('left');
    final right = call.named('right');
    if (left == null && right == null) return false;
    return left?.toSource() != right?.toSource();
  }

  bool _violates(CtorCall call) {
    if (call.importPrefix != null) return false;
    switch ((call.typeName, call.constructor)) {
      case ('EdgeInsets', 'only'):
      case ('Positioned', null):
      case ('Positioned', 'fill'):
        return _asymmetric(call);
      case ('EdgeInsets', 'fromLTRB'):
        final args = call.positional.toList();
        return args.length == 4 && args[0].toSource() != args[2].toSource();
      default:
        return false;
    }
  }

  void _check(Expression node) {
    final call = asCtorCall(node);
    if (call != null && _violates(call) && !_excluded(node)) {
      file.report(rule, node, identity: _identity(call));
    }
  }

  /// הטביעה של `Positioned` נגזרת מ־left/right בלבד: הילד שלו יכול להיות עץ
  /// שלם, ושינוי בו לא נוגע בכיוון. ל־`EdgeInsets` הצומת עצמו קטן.
  static String? _identity(CtorCall call) {
    if (call.typeName != 'Positioned') return null;
    final left = call.named('left')?.toSource();
    final right = call.named('right')?.toSource();
    return '${call.head}(left: $left, right: $right)';
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    _check(node);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    _check(node);
    super.visitMethodInvocation(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (node.prefix.name == 'Alignment' &&
        PhysicalDirectionRule._alignments.contains(node.identifier.name) &&
        !_excluded(node)) {
      file.report(rule, node);
    }
    super.visitPrefixedIdentifier(node);
  }
}
