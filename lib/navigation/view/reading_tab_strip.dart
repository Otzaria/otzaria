import 'dart:async';

import 'package:flutter/material.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/view/pane_drop_target.dart';

/// עובי קו החיווי שמסמן היכן הכרטיסיה הנגררת תיכנס.
const double _kInsertLineWidth = 3;

/// כמה זמן להתעכב מעל כרטיסיה בזמן גרירה עד שהיא נפתחת.
///
/// קצר מדי — כל מעבר מעל כרטיסיה בדרך לאזור הקריאה היה מחליף ספר; ארוך מדי
/// והמחווה מרגישה תקועה.
const Duration kTabSpringOpenDelay = Duration(milliseconds: 400);

/// שקיפות הכרטיסיה במקומה המקורי בזמן שגוררים אותה.
const double _kDraggingTabOpacity = 0.35;

/// רצועת כרטיסיות העיון.
///
/// כל כרטיסיה היא [Draggable] של הטאב עצמו, ולכן אותה מחווה משרתת שני
/// יעדים: שחרור בתוך הרצועה מסדר מחדש, ושחרור מעל אזור הקריאה מפצל אותו
/// לשתיים — כי אותו מטען מתקבל גם ב-[PaneDropTarget] שבמסך הקריאה.
///
/// זו הסיבה שהרצועה אינה [ReorderableListView]: הוא בולע את המחווה ואין לו
/// דרך לדעת שהמצביע יצא מגבולותיו.
class ReadingTabStrip extends StatefulWidget {
  /// הכרטיסיות בסדר התצוגה.
  final List<OpenedTab> tabs;

  /// רוחב כל כרטיסיה, מקביל באורכו ל-[tabs].
  final List<double> widths;

  /// במגע נדרשת לחיצה ארוכה, כדי שהחלקה או גלילה לא יגררו כרטיסיה בטעות.
  final bool requireLongPressToDrag;

  /// בונה את תוכן הכרטיסיה. התוצאה נעטפת ב-[Draggable] ולכן חייבת לכלול את
  /// סמן ה-hit-test שהרצועה החיצונית מסתמכת עליו.
  final Widget Function(OpenedTab tab, int index, double width) tabBuilder;

  /// נקרא עם היעד בקונבנציית הסרה-ואז-הכנסה, כמצופה ב-`MoveTab`.
  final void Function(OpenedTab tab, int newIndex) onReorder;

  /// נקרא כשמתחילה גרירת כרטיסיה.
  final VoidCallback? onDragStarted;

  /// נקרא כשגרירה משתהה מעל כרטיסיה — היא נפתחת, וכך אפשר להמשיך ולשחרר
  /// את הנגררת לצדה באזור הקריאה בלי לוותר על הגרירה.
  final void Function(OpenedTab tab)? onSpringOpen;

  const ReadingTabStrip({
    super.key,
    required this.tabs,
    required this.widths,
    required this.tabBuilder,
    required this.onReorder,
    this.onDragStarted,
    this.onSpringOpen,
    this.requireLongPressToDrag = false,
  });

  @override
  State<ReadingTabStrip> createState() => _ReadingTabStripState();
}

class _ReadingTabStripState extends State<ReadingTabStrip> {
  /// מיקום ההכנסה הנוכחי בטווח `0..tabs.length`, או `null` כשאין גרירה מעל.
  int? _insertIndex;

  /// הכרטיסיה שהגרירה משתהה מעליה, והשעון שיפתח אותה.
  OpenedTab? _springTarget;
  Timer? _springTimer;

  @override
  void dispose() {
    _springTimer?.cancel();
    super.dispose();
  }

  /// שורת הכרטיסיות עצמה. הרצועה נמתחת על כל הרוחב הפנוי, ולכן מדידה מול
  /// גבולותיה הייתה מוסיפה את השטח הריק — וב-RTL, שבו הכרטיסיות צמודות
  /// לימין, כל ההפרש נכנס לחישוב ומיקום ההכנסה יצא תמיד 0.
  final GlobalKey _contentKey = GlobalKey();

  bool get _isRtl => Directionality.of(context) == TextDirection.rtl;

  double get _stripWidth =>
      widget.widths.fold<double>(0, (sum, width) => sum + width);

  /// מיקום ההכנסה שאליו מצביע [localDx].
  ///
  /// ב-RTL הכרטיסיה הראשונה יושבת בימין, ולכן המרחק נמדד מהקצה הימני.
  /// ההשוואה היא לאמצע כל כרטיסיה — כך היעד מתחלף בדיוק כשחוצים אותה,
  /// והרוחבים אינם חייבים להיות אחידים.
  int _insertIndexFor(double localDx) {
    final total = _stripWidth;
    final flowX = _isRtl ? total - localDx : localDx;

    var accumulated = 0.0;
    for (var i = 0; i < widget.widths.length; i++) {
      if (flowX < accumulated + widget.widths[i] / 2) return i;
      accumulated += widget.widths[i];
    }
    return widget.widths.length;
  }

  /// הקצה השמאלי של קו החיווי בתוך שורת הכרטיסיות, מוגבל לגבולותיה — קו
  /// שחורג מהן מפעיל חיתוך ב-Stack וקוצץ את קצות הכרטיסיה הנבחרת.
  double _insertLineLeft(int index) {
    var accumulated = 0.0;
    for (var i = 0; i < index && i < widget.widths.length; i++) {
      accumulated += widget.widths[i];
    }
    final total = _stripWidth;
    final edge = _isRtl ? total - accumulated : accumulated;
    final maxLeft = total - _kInsertLineWidth;
    if (maxLeft <= 0) return 0;
    return (edge - _kInsertLineWidth / 2).clamp(0.0, maxLeft);
  }

  /// הכרטיסיה שמתחת ל-[localDx], או `null` מחוץ לשורה.
  ///
  /// שונה מ-[_insertIndexFor], שמחזיר גבול בין כרטיסיות ולא כרטיסיה.
  OpenedTab? _tabAt(double localDx) {
    final total = _stripWidth;
    final flowX = _isRtl ? total - localDx : localDx;
    if (flowX < 0 || flowX >= total) return null;

    var accumulated = 0.0;
    for (var i = 0; i < widget.widths.length; i++) {
      accumulated += widget.widths[i];
      if (flowX < accumulated) return widget.tabs[i];
    }
    return null;
  }

  /// מזניק את שעון הפתיחה כשהגרירה עברה לכרטיסיה אחרת, ומאפס אותו כשהיא
  /// יצאה מהשורה. השהייה על אותה כרטיסיה ממשיכה את השעון הקיים.
  void _updateSpringTarget(OpenedTab dragged, OpenedTab? hovered) {
    if (hovered == null || identical(hovered, dragged)) {
      _cancelSpring();
      return;
    }
    if (identical(hovered, _springTarget)) return;

    _cancelSpring();
    _springTarget = hovered;
    _springTimer = Timer(kTabSpringOpenDelay, () {
      _springTimer = null;
      widget.onSpringOpen?.call(hovered);
    });
  }

  void _cancelSpring() {
    _springTimer?.cancel();
    _springTimer = null;
    _springTarget = null;
  }

  void _updateDragPosition(OpenedTab dragged, Offset globalOffset) {
    final box = _contentKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    final localDx = box.globalToLocal(globalOffset).dx;
    _updateSpringTarget(dragged, _tabAt(localDx));

    // setState רק כשהיעד באמת זז: onMove יורה בכל תזוזת מצביע.
    final next = _insertIndexFor(localDx);
    if (next != _insertIndex) setState(() => _insertIndex = next);
  }

  /// רק כרטיסיה שנמצאת ברצועה הזו מסדרת אותה מחדש.
  bool _accepts(OpenedTab tab) => widget.tabs.contains(tab);

  void _completeReorder(OpenedTab tab) {
    final insertIndex = _insertIndex;
    _cancelSpring();
    setState(() => _insertIndex = null);
    if (insertIndex == null) return;

    final oldIndex = widget.tabs.indexOf(tab);
    if (oldIndex == -1) return;

    // תיאום לקונבנציית הסרה-ואז-הכנסה: אחרי הסרת הכרטיסיה כל מיקום שאחריה
    // נסוג באחד. בלי זה גרירה ימינה הייתה נוחתת כרטיסיה אחת רחוק מדי.
    final target = insertIndex > oldIndex ? insertIndex - 1 : insertIndex;
    if (target == oldIndex) return;

    widget.onReorder(tab, target);
  }

  @override
  Widget build(BuildContext context) {
    return DragTarget<OpenedTab>(
      onWillAcceptWithDetails: (details) {
        if (!_accepts(details.data)) return false;
        _updateDragPosition(details.data, details.offset);
        return true;
      },
      onMove: (details) {
        if (_accepts(details.data)) {
          _updateDragPosition(details.data, details.offset);
        }
      },
      onLeave: (_) {
        _cancelSpring();
        if (_insertIndex != null) setState(() => _insertIndex = null);
      },
      onAcceptWithDetails: (details) => _completeReorder(details.data),
      builder: (context, candidate, rejected) {
        // הרצועה נמתחת על כל הרוחב הפנוי ולא מתכווצת לרוחב הכרטיסיות: השטח
        // שנותר הוא "האזור הריק" שגרירת חלון ולחיצה כפולה למסך מלא מסתמכות
        // על קיומו.
        return SizedBox(
          width: double.infinity,
          // גלילה מנוטרלת: הרוחבים מחושבים כך שכל הכרטיסיות ייכנסו, אבל
          // בפריים הראשון — לפני שאזור הכרטיסיות נמדד — הם לפי רוחב המסך.
          // בלי מכל שגולש בשקט אותו פריים היה זורק overflow.
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            // קו החיווי יושב באותו Stack עם השורה, ולכן באותה מערכת
            // קואורדינטות שבה נמדד מיקום ההכנסה.
            child: Stack(
              children: [
                Row(
                  key: _contentKey,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < widget.tabs.length; i++)
                      _DraggableTab(
                        key: ObjectKey(widget.tabs[i]),
                        tab: widget.tabs[i],
                        width: widget.widths[i],
                        requireLongPress: widget.requireLongPressToDrag,
                        onDragStarted: widget.onDragStarted,
                        // גרירה שהסתיימה מחוץ לרצועה אינה מפעילה onLeave,
                        // ולכן קו החיווי מנוקה גם כאן.
                        onDragFinished: () {
                          _cancelSpring();
                          if (_insertIndex != null) {
                            setState(() => _insertIndex = null);
                          }
                        },
                        child: widget.tabBuilder(
                          widget.tabs[i],
                          i,
                          widget.widths[i],
                        ),
                      ),
                  ],
                ),
                if (_insertIndex != null)
                  _InsertIndicator(left: _insertLineLeft(_insertIndex!)),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// כרטיסיה בודדת ברצועה, ניתנת לגרירה.
class _DraggableTab extends StatelessWidget {
  final OpenedTab tab;
  final double width;
  final bool requireLongPress;
  final VoidCallback? onDragStarted;
  final VoidCallback onDragFinished;
  final Widget child;

  const _DraggableTab({
    super.key,
    required this.tab,
    required this.width,
    required this.requireLongPress,
    required this.onDragStarted,
    required this.onDragFinished,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    // הכרטיסיה נשארת במקומה מעומעמת ולא נעלמת: היעלמותה הייתה משנה את חלוקת
    // הרוחבים באמצע הגרירה ומזיזה את שאר הכרטיסיות תחת הסמן.
    final placeholder = Opacity(opacity: _kDraggingTabOpacity, child: child);
    final feedback = _TabDragFeedback(width: width, child: child);

    if (requireLongPress) {
      return LongPressDraggable<OpenedTab>(
        data: tab,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: feedback,
        childWhenDragging: placeholder,
        onDragStarted: onDragStarted,
        onDragEnd: (_) => onDragFinished(),
        onDraggableCanceled: (_, _) => onDragFinished(),
        child: child,
      );
    }

    return Draggable<OpenedTab>(
      data: tab,
      // חובה: ה-offset שמקבלים יעדי ההפלה הוא פינת ה-feedback, ולכן עוגן
      // ברירת המחדל מסיט את אזור ההפלה בכחצי רוחב כרטיסיה.
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: feedback,
      childWhenDragging: placeholder,
      onDragStarted: onDragStarted,
      onDragEnd: (_) => onDragFinished(),
      onDraggableCanceled: (_, _) => onDragFinished(),
      child: child,
    );
  }
}

/// הכרטיסיה הצפה תחת הסמן בזמן גרירה.
///
/// מוצגת ב-[Overlay] ולכן אינה יורשת את ערכת הנושא ואת שכבת ה-[Material]
/// של הרצועה — בלי העטיפה המפורשת הצבעים נופלים לברירות מחדל.
class _TabDragFeedback extends StatelessWidget {
  final double width;
  final Widget child;

  const _TabDragFeedback({required this.width, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Directionality(
      textDirection: Directionality.of(context),
      child: Theme(
        data: theme,
        // העוגן הוא נקודת המצביע, ולכן הכרטיסיה מוזזת כדי לרחף סביבה.
        child: FractionalTranslation(
          translation: const Offset(-0.5, -0.5),
          child: Material(
            color: theme.colorScheme.surfaceContainerHigh,
            elevation: 8,
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    );
  }
}

/// קו אנכי המסמן היכן הכרטיסיה הנגררת תיכנס.
class _InsertIndicator extends StatelessWidget {
  /// הקצה השמאלי של הקו, כבר ממורכז על נקודת ההכנסה ומוגבל לגבולות השורה.
  final double left;

  const _InsertIndicator({required this.left});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 4,
      bottom: 4,
      left: left,
      width: _kInsertLineWidth,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(_kInsertLineWidth / 2),
          ),
        ),
      ),
    );
  }
}
