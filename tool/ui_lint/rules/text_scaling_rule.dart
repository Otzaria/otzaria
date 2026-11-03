import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../ast_helpers.dart';
import '../ui_lint.dart';

/// UIL-026: טקסט שמתעלם מהגדלת הטקסט של מערכת ההפעלה:
/// - `MediaQuery.withNoTextScaling(...)`;
/// - `TextScaler.noScaling`, בכל מקום;
/// - `RichText(` גולמי, כלומר בלי `textScaler:`. ‏RichText לא קורא את ה־
///   TextScaler מה־MediaQuery בעצמו; עם `textScaler: MediaQuery.textScalerOf(…)`
///   הוא מכבד את ההגדלה ואינו גולמי.
///
/// פריסה קבועה בכוונה (JX-10, למשל טור הסת"ם בתיקון קוראים) מסומנת ב־allow.
class TextScalingRule extends UiLintRule {
  const TextScalingRule();

  @override
  String get id => 'UIL-026';

  @override
  int get stage => 2;

  @override
  String get title => 'טקסט בלי הגדלת הטקסט של המערכת';

  @override
  String get hint =>
      'Text.rich, או RichText עם textScaler: MediaQuery.textScalerOf(context); '
      'בלי withNoTextScaling/TextScaler.noScaling (DESIGN_SYSTEM.md §6.3)';

  @override
  void check(UiLintFile file) {
    for (final call in ctorCallsNamed(file.unit, {'MediaQuery', 'RichText'})) {
      if (call.importPrefix != null) continue;
      if (call.typeName == 'MediaQuery' &&
          call.constructor == 'withNoTextScaling') {
        file.report(this, call.node, identity: call.head);
      } else if (call.typeName == 'RichText' &&
          call.constructor == null &&
          call.named('textScaler') == null) {
        file.report(this, call.node, identity: call.head);
      }
    }
    file.unit.accept(_Visitor(this, file));
  }
}

class _Visitor extends RecursiveAstVisitor<void> {
  _Visitor(this.rule, this.file);

  final TextScalingRule rule;
  final UiLintFile file;

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (node.prefix.name == 'TextScaler' &&
        node.identifier.name == 'noScaling') {
      file.report(rule, node);
    }
    super.visitPrefixedIdentifier(node);
  }
}
