import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../ast_helpers.dart';
import '../ui_lint.dart';

/// UIL-040: יישור טקסט פיזי (`TextAlign.left`/`TextAlign.right`) מחוץ לתוכן
/// הספרים (הכרעת בעל הפרויקט 18.11). בעברית "ימין" ו"שמאל" הפוכים מהשפות
/// האחרות, ובמצב אנגלית הכרום מתהפך, ולכן בכרום משתמשים ב־`TextAlign.start`/
/// `TextAlign.end`.
///
/// תוכן הספרים (קורא הטקסט, `smart_text`, פסקת תיקון הקוראים) מוחרג ב־
/// `config.yaml`: הוא נשלט בכיוון התוכן ולא בכיוון הכרום. ערך LTR מטבעו (שדה
/// כתובת אינטרנט) נכתב עם `// ui-lint: allow UIL-040 — נימוק` (JX-09).
class TextAlignPhysicalRule extends UiLintRule {
  const TextAlignPhysicalRule();

  @override
  String get id => 'UIL-040';

  @override
  int get stage => 3;

  @override
  String get title => 'יישור טקסט פיזי (TextAlign.left/right) בכרום';

  @override
  String get hint =>
      'TextAlign.start / TextAlign.end (DESIGN_SYSTEM.md §2.2, §6.1)';

  @override
  void check(UiLintFile file) => file.unit.accept(_Visitor(this, file));
}

class _Visitor extends RecursiveAstVisitor<void> {
  _Visitor(this.rule, this.file);

  final TextAlignPhysicalRule rule;
  final UiLintFile file;

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (node.prefix.name == 'TextAlign' &&
        (node.identifier.name == 'left' || node.identifier.name == 'right') &&
        !isInsideClassExtending(node, const {'CustomPainter'})) {
      file.report(rule, node);
    }
    super.visitPrefixedIdentifier(node);
  }
}
