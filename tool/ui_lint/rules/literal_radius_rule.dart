import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../ast_helpers.dart';
import '../ui_lint.dart';

/// UIL-019: רדיוס רק מהטוקן היחיד (DD-04).
///
/// - `BorderRadius.circular(n)`/`BorderRadiusDirectional.circular(n)`/
///   `Radius.circular(n)` ליטרלי;
/// - `StadiumBorder(...)`: הגלולה מאושרת רק ל־BarSplitButton (q8 שאלה 7),
///   והחריג נרשם ב־config;
/// - `CircleBorder(...)`: מותר רק לכפתור אייקון בלבד (DD-04, q9 שאלה 3) —
///   בתוך `IconButton(...)`/`IconButton.styleFrom(...)`, או בקבצים שב־config.
///   רכיב עגול מטבעו (נקודה, עיגול צבע) מסומן ב־allow.
class LiteralRadiusRule extends UiLintRule {
  const LiteralRadiusRule();

  static const _types = {'BorderRadius', 'BorderRadiusDirectional', 'Radius'};
  static const _iconButtons = {'IconButton', 'AppIconButton'};

  @override
  String get id => 'UIL-019';

  @override
  int get stage => 3;

  @override
  String get title =>
      'רדיוס ליטרלי, StadiumBorder, או CircleBorder שאינו כפתור אייקון';

  @override
  String get hint =>
      'AppTokens.borderRadiusAll / AppTokens.roundedShape; עיגול רק לכפתור '
      'אייקון בלבד (DESIGN_SYSTEM.md §2.3, DD-04)';

  @override
  void check(UiLintFile file) => file.unit.accept(_Visitor(this, file));
}

class _Visitor extends RecursiveAstVisitor<void> {
  _Visitor(this.rule, this.file);

  final LiteralRadiusRule rule;
  final UiLintFile file;

  bool _inIconButton(AstNode node) =>
      enclosingCtorCall(
        node,
        (c) => LiteralRadiusRule._iconButtons.contains(c.typeName),
      ) !=
      null;

  void _check(Expression node) {
    final call = asCtorCall(node);
    if (call == null ||
        call.importPrefix != null ||
        isInsideClassExtending(node, const {'CustomPainter'})) {
      return;
    }
    if (call.typeName == 'StadiumBorder' ||
        (call.typeName == 'CircleBorder' && !_inIconButton(node))) {
      file.report(rule, node, identity: call.head);
      return;
    }
    if (LiteralRadiusRule._types.contains(call.typeName) &&
        call.constructor == 'circular' &&
        call.importPrefix == null &&
        call.positional.length == 1 &&
        isNumericLiteral(call.positional.single) &&
        !isInsideClassExtending(node, const {'CustomPainter'})) {
      file.report(rule, node);
    }
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
}
