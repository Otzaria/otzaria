import '../ast_helpers.dart';
import '../ui_lint.dart';

/// UIL-031: `Scrollbar(`/`RawScrollbar(`/`CupertinoScrollbar(` גולמי מחוץ
/// ל־`app_scrollbar.dart`. פס גולמי קובע את הצד לפי כיוון הטקסט (שמאל
/// בעברית) ומצויר מעל התוכן.
class RawScrollbarRule extends UiLintRule {
  const RawScrollbarRule();

  @override
  String get id => 'UIL-031';

  @override
  int get stage => 2;

  @override
  String get title => 'Scrollbar גולמי';

  @override
  String get hint =>
      'AppScrollbar (פס בימין הפיזי, ברצועה משלו); צד שמאל רק בחריג מתועד '
      'דרך side: (DESIGN_SYSTEM.md "פס גלילה")';

  @override
  void check(UiLintFile file) {
    for (final call in ctorCallsNamed(file.unit, {
      'Scrollbar',
      'RawScrollbar',
      'CupertinoScrollbar',
    })) {
      if (call.importPrefix == null) {
        file.report(this, call.node, identity: call.head);
      }
    }
  }
}
