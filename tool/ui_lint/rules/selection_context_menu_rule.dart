import '../ast_helpers.dart';
import '../ui_lint.dart';

/// UIL-032: בחירת טקסט מציגה את תפריט אוצריא ולא את תפריט Flutter (issue
/// #1590). אין `SelectableText` (הוא פותח את תפריט Flutter גם בתוך
/// `AppSelectionArea`), ואין `SelectionArea`/`SelectableRegion` בלי
/// `contextMenuBuilder:`.
class SelectionContextMenuRule extends UiLintRule {
  const SelectionContextMenuRule();

  static const _regions = {'SelectionArea', 'SelectableRegion'};

  @override
  String get id => 'UIL-032';

  @override
  int get stage => 1;

  @override
  String get title => 'SelectableText, או SelectionArea בלי contextMenuBuilder';

  @override
  String get hint =>
      'Text בתוך AppSelectionArea (lib/widgets/misc/app_selection_area.dart), '
      'שמציג את תפריט אוצריא';

  @override
  void check(UiLintFile file) {
    for (final call in ctorCallsNamed(file.unit, {
      'SelectableText',
      ..._regions,
    })) {
      if (call.importPrefix != null) continue;
      if (_regions.contains(call.typeName) &&
          call.named('contextMenuBuilder') != null) {
        continue;
      }
      file.report(this, call.node, identity: call.head);
    }
  }
}
