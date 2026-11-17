import '../ast_helpers.dart';
import '../ui_lint.dart';

/// UIL-033: רכיב שיוצא משימוש בקוד פיצ'ר (DESIGN_SYSTEM.md §3.3). הרשימה היא
/// [replacements]: רכיב → התחליף. הרכיבים המשותפים שעוד בונים אותו מוחרגים
/// ב־config.yaml עד שהוא יוסר.
class DeprecatedComponentRule extends UiLintRule {
  const DeprecatedComponentRule();

  static const replacements = {
    'CustomSwitch':
        'SettingsSwitchTile בהגדרות, AppTogglePill בשורה, ו־Switch מחוץ להן',
  };

  @override
  String get id => 'UIL-033';

  @override
  int get stage => 2;

  @override
  String get title => 'רכיב שיוצא משימוש';

  @override
  String get hint =>
      '${replacements.entries.map((e) => '${e.key} → ${e.value}').join('; ')} '
      '(DESIGN_SYSTEM.md §3.3)';

  @override
  void check(UiLintFile file) {
    for (final call in ctorCallsNamed(file.unit, replacements.keys.toSet())) {
      if (call.importPrefix == null) {
        file.report(this, call.node, identity: call.head);
      }
    }
  }
}
