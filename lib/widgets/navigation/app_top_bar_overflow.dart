// lib/widgets/navigation/app_top_bar_overflow.dart
//
// מעבר פריטי AppTopBar לתפריט "עוד ⋮" לפי עדיפות, כשאין להם מקום.

import 'dart:math' as math;

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';

/// עד כמה פריט בסרגל חיוני. כשהפריטים לא נכנסים ברוחב הסרגל, [low] עוברים
/// ראשונים ל"עוד ⋮", אחריהם [normal]; [critical] לעולם לא עוברים.
enum AppTopBarPriority { critical, normal, low }

/// השורה שמייצגת פריט שעבר ל"עוד ⋮": כיתוב, אייקון ופעולה.
class AppTopBarMenuAction {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  const AppTopBarMenuAction({
    required this.label,
    required this.icon,
    required this.onPressed,
  });
}

/// פריט בשורה מתקפלת: הווידג'ט, מפריד אופציונלי לפניו, ועדיפותו.
class AppTopBarFoldEntry {
  final Widget widget;
  final Widget? divider;
  final bool flexible;
  final AppTopBarPriority priority;
  final AppTopBarMenuAction? menuAction;

  const AppTopBarFoldEntry({
    required this.widget,
    required this.divider,
    required this.flexible,
    required this.priority,
    required this.menuAction,
  });
}

/// שורת פריטים של [AppTopBar] (התחלה או סיום) שמקפלת פריטים ל"עוד ⋮" כשהם לא
/// נכנסים ברוחב שקיבלה.
///
/// ההחלטה נעשית בזמן הפריסה, אחרי מדידת הפריטים בפועל, ולכן עובדת גם עם
/// פריטים שמסתגלים לרוחב בעצמם (`LayoutBuilder`, `flexible`): הם מקבלים רוחב
/// חסום, בניגוד לגלילה אופקית שנתנה להם רוחב לא חסום. פריט שעבר ל"עוד" נשאר
/// בעץ (כך שמצבו נשמר) אבל לא מצויר, לא נלחץ, לא מקבל פוקוס ולא נקרא.
class AppTopBarFoldingRow extends StatefulWidget {
  final List<AppTopBarFoldEntry> entries;
  final double spacing;

  /// false: השורה מקפלת בלי כפתור "עוד ⋮" משלה (ולא שומרת לו מקום); מי שקורא
  /// לה מציג את הפריטים המקופלים בתפריט אחר, ראו [AppTopBarFoldedActions].
  final bool showOverflowButton;

  /// נקרא (אחרי ה-frame) כשקבוצת הפריטים המקופלים משתנה.
  final ValueChanged<Set<int>>? onFoldedChanged;

  const AppTopBarFoldingRow({
    super.key,
    required this.entries,
    required this.spacing,
    this.showOverflowButton = true,
    this.onFoldedChanged,
  });

  @override
  State<AppTopBarFoldingRow> createState() => _AppTopBarFoldingRowState();
}

class _AppTopBarFoldingRowState extends State<AppTopBarFoldingRow> {
  /// האינדקסים שהפריסה האחרונה קיפלה. מגיע אחרי ה-frame: הפריסה לא יכולה
  /// לבנות מחדש בזמן שהיא רצה.
  Set<int> _folded = const {};

  void _onFolded(Set<int> folded) {
    if (!mounted || setEquals(folded, _folded)) return;
    setState(() => _folded = folded);
    widget.onFoldedChanged?.call(folded);
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.entries;
    final folded = {
      for (final i in _folded)
        if (i < entries.length) i,
    };
    final slots = <_Slot>[];
    final children = <Widget>[];
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      if (entry.divider != null) {
        slots.add((
          kind: _SlotKind.divider,
          item: i,
          priority: entry.priority,
          flexible: false,
        ));
        children.add(
          ExcludeFocus(
            excluding: folded.contains(i),
            child: entry.divider!,
          ),
        );
      }
      slots.add((
        kind: _SlotKind.item,
        item: i,
        priority: entry.priority,
        flexible: entry.flexible,
      ));
      children.add(
        ExcludeFocus(
          excluding: folded.contains(i),
          child: entry.widget,
        ),
      );
    }
    if (widget.showOverflowButton) {
      slots.add((
        kind: _SlotKind.overflow,
        item: -1,
        priority: AppTopBarPriority.critical,
        flexible: false,
      ));
      children.add(
        ExcludeFocus(
          excluding: folded.isEmpty,
          child: _OverflowButton(entries: entries, folded: folded),
        ),
      );
    }
    return _FoldingRowRenderWidget(
      slots: slots,
      spacing: widget.spacing,
      textDirection: Directionality.of(context),
      onFoldedChanged: _onFolded,
      children: children,
    );
  }
}

/// הפריטים שהשורה המתקפלת של [AppTopBar] קיפלה, כשהסרגל הוגדר להציג אותם
/// בתפריט "עוד ⋮" של פריטי הסיום ולא בכפתור משלהם
/// (`AppTopBar.mergeFoldedIntoTrailingMenu`). `ResponsiveActionBar` עם
/// `absorbTopBarFolds` קורא אותם ומוסיף אותם בראש התפריט שלו.
class AppTopBarFoldedActions extends InheritedWidget {
  final List<AppTopBarMenuAction> actions;

  const AppTopBarFoldedActions({
    super.key,
    required this.actions,
    required super.child,
  });

  /// השורות שיש להוסיף לתפריט; ריק מחוץ לסרגל ממוזג.
  static List<AppTopBarMenuAction> of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<AppTopBarFoldedActions>()
          ?.actions ??
      const [];

  @override
  bool updateShouldNotify(AppTopBarFoldedActions oldWidget) =>
      !listEquals(actions, oldWidget.actions);
}

class _OverflowButton extends StatelessWidget {
  final List<AppTopBarFoldEntry> entries;
  final Set<int> folded;

  const _OverflowButton({required this.entries, required this.folded});

  @override
  Widget build(BuildContext context) {
    final indexes = folded.toList()..sort();
    return AppPopupMenuButton<int>(
      iconData: FluentIcons.more_vertical_24_regular,
      tooltip: context.settingsText('עוד פעולות'),
      position: PopupMenuPosition.under,
      entries: [
        for (final i in indexes)
          if (entries[i].menuAction case final action?)
            AppMenuEntry<int>(
              value: i,
              label: action.label,
              icon: action.icon,
              enabled: action.onPressed != null,
            ),
      ],
      onSelected: (i) => entries[i].menuAction?.onPressed?.call(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  פריסה
// ─────────────────────────────────────────────────────────────────────────────

enum _SlotKind { item, divider, overflow }

typedef _Slot = ({
  _SlotKind kind,
  int item,
  AppTopBarPriority priority,
  bool flexible,
});

class _FoldingRowRenderWidget extends MultiChildRenderObjectWidget {
  final List<_Slot> slots;
  final double spacing;
  final TextDirection textDirection;
  final ValueChanged<Set<int>> onFoldedChanged;

  const _FoldingRowRenderWidget({
    required this.slots,
    required this.spacing,
    required this.textDirection,
    required this.onFoldedChanged,
    required super.children,
  });

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderFoldingRow(
    slots: slots,
    spacing: spacing,
    textDirection: textDirection,
    onFoldedChanged: onFoldedChanged,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderFoldingRow renderObject,
  ) {
    renderObject
      ..slots = slots
      ..spacing = spacing
      ..textDirection = textDirection
      ..onFoldedChanged = onFoldedChanged;
  }
}

/// כמו `Row(mainAxisSize: min)` עם `Flexible` לפריטים הגמישים, ובנוסף: כשסכום
/// הרוחבים עולה על הרוחב המרבי, מקפל פריטים לפי עדיפות (נמוך לפני רגיל, ובאותה
/// עדיפות המאוחר לפני המוקדם) עד שהכל נכנס עם כפתור "עוד ⋮".
class _FoldParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderFoldingRow extends RenderBox
    with
        ContainerRenderObjectMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        >,
        RenderBoxContainerDefaultsMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        > {
  _RenderFoldingRow({
    required List<_Slot> slots,
    required double spacing,
    required TextDirection textDirection,
    required this.onFoldedChanged,
  }) {
    _slots = slots;
    _spacing = spacing;
    _textDirection = textDirection;
  }

  late List<_Slot> _slots;
  set slots(List<_Slot> value) {
    if (listEquals(_slots, value)) return;
    _slots = value;
    markNeedsLayout();
  }

  late double _spacing;
  set spacing(double value) {
    if (_spacing == value) return;
    _spacing = value;
    markNeedsLayout();
  }

  late TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (_textDirection == value) return;
    _textDirection = value;
    markNeedsLayout();
  }

  ValueChanged<Set<int>> onFoldedChanged;

  Set<int> _reported = const {};

  /// לכל ילד (לפי סדרו): האם הוא מצויר ונלחץ. ילד מקופל לא.
  List<bool> _shown = const [];

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! ContainerBoxParentData<RenderBox>) {
      child.parentData = _FoldParentData();
    }
  }

  List<RenderBox> get _kids {
    final kids = <RenderBox>[];
    for (var c = firstChild; c != null; c = childAfter(c)) {
      kids.add(c);
    }
    return kids;
  }

  @override
  void performLayout() {
    final kids = _kids;
    assert(kids.length == _slots.length);
    final maxWidth = constraints.maxWidth;
    final bounded = maxWidth.isFinite;
    final loose = BoxConstraints(maxHeight: constraints.maxHeight);

    final itemCount = _slots.where((s) => s.kind == _SlotKind.item).length;
    final itemKid = List<RenderBox?>.filled(itemCount, null);
    final itemSlot = List<_Slot?>.filled(itemCount, null);
    final dividerKid = List<RenderBox?>.filled(itemCount, null);
    RenderBox? overflowKid;
    for (var k = 0; k < kids.length; k++) {
      final slot = _slots[k];
      switch (slot.kind) {
        case _SlotKind.item:
          itemKid[slot.item] = kids[k];
          itemSlot[slot.item] = slot;
        case _SlotKind.divider:
          dividerKid[slot.item] = kids[k];
        case _SlotKind.overflow:
          overflowKid = kids[k];
      }
    }

    // מדידה טבעית. הגמישים נמדדים אחרי שנקבע כמה מקום נשאר להם.
    final widths = List<double>.filled(itemCount, 0);
    final dividerWidths = List<double>.filled(itemCount, 0);
    for (var i = 0; i < itemCount; i++) {
      if (!itemSlot[i]!.flexible) {
        itemKid[i]!.layout(loose, parentUsesSize: true);
        widths[i] = itemKid[i]!.size.width;
      }
      final divider = dividerKid[i];
      if (divider != null) {
        divider.layout(loose, parentUsesSize: true);
        dividerWidths[i] = divider.size.width;
      }
    }
    // בלי כפתור משלה (מצב ממוזג) אין מה לשמור לו מקום.
    overflowKid?.layout(loose, parentUsesSize: true);
    final overflowWidth = overflowKid?.size.width ?? 0.0;

    final folded = <int>{};

    double needed() {
      var total = 0.0;
      var first = true;
      for (var i = 0; i < itemCount; i++) {
        if (folded.contains(i)) continue;
        if (!first) total += dividerWidths[i] + _spacing;
        total += widths[i];
        first = false;
      }
      if (folded.isNotEmpty && overflowKid != null) {
        total += (first ? 0.0 : _spacing) + overflowWidth;
      }
      return total;
    }

    if (bounded) {
      final candidates =
          [
            for (var i = 0; i < itemCount; i++)
              if (itemSlot[i]!.priority != AppTopBarPriority.critical) i,
          ]..sort((a, b) {
            final byPriority = itemSlot[b]!.priority.index.compareTo(
              itemSlot[a]!.priority.index,
            );
            return byPriority != 0 ? byPriority : b.compareTo(a);
          });
      var next = 0;
      while (needed() > maxWidth && next < candidates.length) {
        folded.add(candidates[next++]);
      }
    }

    var used = needed();
    for (var i = 0; i < itemCount; i++) {
      if (folded.contains(i) || !itemSlot[i]!.flexible) continue;
      final room = bounded ? math.max(0.0, maxWidth - used) : double.infinity;
      itemKid[i]!.layout(
        BoxConstraints(maxWidth: room, maxHeight: constraints.maxHeight),
        parentUsesSize: true,
      );
      widths[i] = itemKid[i]!.size.width;
      used += widths[i];
    }

    // מיקום לוגי משמאל לימין (ובעברית מראים אותו הפוך בסוף).
    final shown = List<bool>.filled(kids.length, false);
    final logicalX = List<double>.filled(kids.length, 0);
    final indexOf = {for (var k = 0; k < kids.length; k++) kids[k]: k};
    var x = 0.0;
    var height = 0.0;
    var first = true;
    void place(RenderBox kid) {
      final k = indexOf[kid]!;
      shown[k] = true;
      logicalX[k] = x;
      x += kid.size.width;
      height = math.max(height, kid.size.height);
    }

    for (var i = 0; i < itemCount; i++) {
      final kid = itemKid[i]!;
      if (folded.contains(i)) {
        kid.layout(BoxConstraints.tight(Size.zero), parentUsesSize: true);
        dividerKid[i]?.layout(
          BoxConstraints.tight(Size.zero),
          parentUsesSize: true,
        );
        continue;
      }
      if (!first) {
        final divider = dividerKid[i];
        if (divider != null) {
          place(divider);
        }
        x += _spacing;
      } else {
        dividerKid[i]?.layout(
          BoxConstraints.tight(Size.zero),
          parentUsesSize: true,
        );
      }
      place(kid);
      first = false;
    }
    if (folded.isNotEmpty && overflowKid != null) {
      if (!first) x += _spacing;
      place(overflowKid);
    } else {
      overflowKid?.layout(
        BoxConstraints.tight(Size.zero),
        parentUsesSize: true,
      );
    }

    size = constraints.constrain(Size(x, height));
    final rtl = _textDirection == TextDirection.rtl;
    for (var k = 0; k < kids.length; k++) {
      final kid = kids[k];
      final dx = rtl ? size.width - logicalX[k] - kid.size.width : logicalX[k];
      (kid.parentData! as ContainerBoxParentData<RenderBox>).offset = Offset(
        dx,
        (size.height - kid.size.height) / 2,
      );
    }
    _shown = shown;

    if (!setEquals(folded, _reported)) {
      _reported = folded;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (attached) onFoldedChanged(_reported);
      });
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final kids = _kids;
    for (var k = 0; k < kids.length; k++) {
      if (k >= _shown.length || !_shown[k]) continue;
      final parentData =
          kids[k].parentData! as ContainerBoxParentData<RenderBox>;
      context.paintChild(kids[k], parentData.offset + offset);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final kids = _kids;
    for (var k = kids.length - 1; k >= 0; k--) {
      if (k >= _shown.length || !_shown[k]) continue;
      final kid = kids[k];
      final parentData = kid.parentData! as ContainerBoxParentData<RenderBox>;
      final hit = result.addWithPaintOffset(
        offset: parentData.offset,
        position: position,
        hitTest: (result, transformed) =>
            kid.hitTest(result, position: transformed),
      );
      if (hit) return true;
    }
    return false;
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    final kids = _kids;
    for (var k = 0; k < kids.length; k++) {
      if (k >= _shown.length || !_shown[k]) continue;
      visitor(kids[k]);
    }
  }
}
