import 'package:analyzer/dart/ast/ast.dart';

import '../ast_helpers.dart';
import '../ui_lint.dart';

/// UIL-010: `textDirection: TextDirection.rtl` על `Text`/`Text.rich`/
/// `SelectableText`/`SelectableText.rich`.
///
/// כיוון הטקסט בא מה־`Directionality` שמעליו: RTL בממשק העברי, ו־LTR במצב
/// האנגלית של ההגדרות (`ChromeDirectionality`). כיוון קבוע על Text שובר את מצב
/// האנגלית. ציטוט עברי שנשאר RTL גם באנגלית (חלון `ContentDirectionality`)
/// מסומן בהערת allow עם נימוק.
class TextRtlDirectionRule extends UiLintRule {
  const TextRtlDirectionRule();

  static const _types = {'Text', 'SelectableText'};
  static const _constructors = {null, 'rich'};

  @override
  String get id => 'UIL-010';

  @override
  int get stage => 1;

  @override
  String get title => 'textDirection: TextDirection.rtl על Text';

  @override
  String get hint =>
      'בלי textDirection: הכיוון מה־Directionality; תוכן עברי במצב אנגלית '
      'בתוך ContentDirectionality (DESIGN_SYSTEM.md §6.1)';

  @override
  void check(UiLintFile file) {
    for (final call in ctorCallsNamed(file.unit, _types)) {
      if (call.importPrefix != null ||
          !_constructors.contains(call.constructor)) {
        continue;
      }
      for (final argument in call.arguments.arguments) {
        if (argument is! NamedArgument ||
            argument.name.lexeme != 'textDirection') {
          continue;
        }
        final value = argument.argumentExpression.unParenthesized;
        if (value is PrefixedIdentifier &&
            value.prefix.name == 'TextDirection' &&
            value.identifier.name == 'rtl') {
          file.report(this, argument);
        }
      }
    }
  }
}
