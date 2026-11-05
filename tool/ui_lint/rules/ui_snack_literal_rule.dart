import 'package:analyzer/dart/ast/ast.dart';

import '../ast_helpers.dart';
import '../ui_lint.dart';

/// UIL-009: מחרוזת קשיחה בקריאה ל-UiSnack (issue #1473), גם בארגומנט בשם וגם
/// בענף של תנאי.
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
        if (value != null) {
          for (final literal in _literals(value)) {
            file.report(this, literal);
          }
        }
      }
    }
  }

  /// הליטרל עצמו, או הענפים הליטרליים של תנאי (`ok ? 'נשמר' : 'נכשל'`).
  static Iterable<Expression> _literals(Expression value) sync* {
    final e = value.unParenthesized;
    if (e is StringLiteral) {
      yield e;
    } else if (e is ConditionalExpression) {
      yield* _literals(e.thenExpression);
      yield* _literals(e.elseExpression);
    }
  }
}
