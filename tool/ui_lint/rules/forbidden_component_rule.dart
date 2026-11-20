import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../ast_helpers.dart';
import '../ui_lint.dart';

/// UIL-039: רכיבים סטנדרטיים של Flutter שהתקן אוסר (DESIGN_SYSTEM.md §3.3):
/// - `SliderTheme` מקומי (מחוון: `SettingsSliderTile`);
/// - `AppBar`/`SliverAppBar` (סרגל עליון: `AppTopBar`);
/// - `DropdownButton`/`DropdownButtonFormField` (תפריט נפתח:
///   `AppDropdownField`);
/// - `SegmentedButton`/`ToggleButtons` (מתג מקטעים: `AppSegmentedControl`);
/// - `FloatingActionButton` (כפתור צף: אין);
/// - גיליון תחתון (הכרעת בעל הפרויקט 18.11: אסור): `showModalBottomSheet`,
///   `showBottomSheet`, `BottomSheet`, `DraggableScrollableSheet`;
/// - רכיבי `Cupertino*` (הכרום של iOS מגיע מערכת הנושא של האפליקציה). מה שיש
///   לו כלל משלו לא נספר פעמיים: `CupertinoAlertDialog` ב־UIL-001,
///   `CupertinoScrollbar` ב־UIL-031.
///
/// הכלל נעול ללא חריגות: הרכיב המשותף שבונה `SegmentedButton` מוחרג ב־
/// `config.yaml`.
class ForbiddenComponentRule extends UiLintRule {
  const ForbiddenComponentRule();

  static const _components = {
    'SliderTheme',
    'AppBar',
    'SliverAppBar',
    'DropdownButton',
    'DropdownButtonFormField',
    'SegmentedButton',
    'ToggleButtons',
    'FloatingActionButton',
    'BottomSheet',
    'DraggableScrollableSheet',
  };
  static const _functions = {'showModalBottomSheet', 'showBottomSheet'};
  static const _coveredElsewhere = {
    'CupertinoAlertDialog',
    'CupertinoScrollbar',
  };

  @override
  String get id => 'UIL-039';

  @override
  int get stage => 2;

  @override
  String get title =>
      'רכיב אסור (מחוון מקומי, AppBar, גיליון תחתון, Cupertino…)';

  @override
  String get hint =>
      'SettingsSliderTile, AppTopBar, AppDropdownField, AppSegmentedControl; '
      'אין כפתור צף וגיליון תחתון (DESIGN_SYSTEM.md §3.3)';

  @override
  void check(UiLintFile file) => file.unit.accept(_Visitor(this, file));
}

class _Visitor extends RecursiveAstVisitor<void> {
  _Visitor(this.rule, this.file);

  final ForbiddenComponentRule rule;
  final UiLintFile file;

  void _check(Expression node) {
    final call = asCtorCall(node);
    if (call == null || call.importPrefix != null) return;
    final name = call.typeName;
    if (ForbiddenComponentRule._components.contains(name) ||
        (name.startsWith('Cupertino') &&
            !ForbiddenComponentRule._coveredElsewhere.contains(name))) {
      file.report(rule, node, identity: call.head);
    }
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    _check(node);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final target = node.target;
    final plain =
        target == null ||
        (target is SimpleIdentifier &&
            flutterImportPrefixes(node.root).contains(target.name));
    if (plain &&
        ForbiddenComponentRule._functions.contains(node.methodName.name)) {
      file.report(rule, node, identity: node.methodName.name);
    } else {
      _check(node);
    }
    super.visitMethodInvocation(node);
  }
}
