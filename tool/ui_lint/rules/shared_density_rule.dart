import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../ui_lint.dart';
import 'shared_feature_import_rule.dart';

/// UIL-025: רכיב משותף (lib/widgets) לא קורא את `compactMenuMode` של
/// ההגדרות. הצפיפות מגיעה מ־`AppDensity.of(context)`.
///
/// נתפסת קריאה של המאפיין (`state.compactMenuMode`,
/// `bloc.state.compactMenuMode`), וגם `widget.compactMenuMode`: פרמטר כזה מעביר
/// את ההגדרה לרכיב ועוקף את AppDensity. ההצהרה עצמה אינה קריאה ולא נתפסת.
class SharedDensityRule extends UiLintRule {
  const SharedDensityRule();

  @override
  String get id => 'UIL-025';

  @override
  int get stage => 4;

  @override
  String get title => 'compactMenuMode ברכיב משותף';

  @override
  String get hint =>
      'AppDensity.of(context).isCompact (DESIGN_SYSTEM.md §2.5.8, DD-10)';

  @override
  void check(UiLintFile file) {
    if (!file.path.startsWith(SharedFeatureImportRule.sharedRoot)) return;
    file.unit.accept(_Visitor(this, file));
  }
}

class _Visitor extends RecursiveAstVisitor<void> {
  _Visitor(this.rule, this.file);

  final SharedDensityRule rule;
  final UiLintFile file;

  static const _name = 'compactMenuMode';

  @override
  void visitPropertyAccess(PropertyAccess node) {
    if (node.propertyName.name == _name) file.report(rule, node);
    super.visitPropertyAccess(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (node.identifier.name == _name) file.report(rule, node);
    super.visitPrefixedIdentifier(node);
  }
}
