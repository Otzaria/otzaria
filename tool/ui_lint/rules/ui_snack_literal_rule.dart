import 'package:analyzer/dart/ast/ast.dart';

import '../ast_helpers.dart';
import '../ui_lint.dart';

/// UIL-009: מחרוזת קשיחה בקריאה ל-UiSnack (issue #1473), גם בארגומנט בשם.
class UiSnackLiteralRule extends UiLintRule {
  const UiSnackLiteralRule();

  @override
  String get id => 'UIL-009';

  @override
  int get stage => 1;

  @override
  String get title => 'מחרוזת קשיחה ב-UiSnack';

  @override
  String get hint =>
      'הודעה מקטלוג ב-lib/core/messages/ (DESIGN_SYSTEM.md §3.5)';

  @override
  void check(UiLintFile file) {
    for (final call in ctorCallsNamed(file.unit, {'UiSnack'})) {
      if (call.importPrefix != null || call.constructor == null) continue;
      for (final argument in call.arguments.arguments) {
        final value = switch (argument) {
          NamedArgument(:final argumentExpression) => argumentExpression,
          Expression() => argument,
          _ => null,
        };
        if (value != null && value.unParenthesized is StringLiteral) {
          file.report(this, value);
        }
      }
    }
  }
}
