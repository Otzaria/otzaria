import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/core/windowing/external_tab_drag.dart';
import 'package:otzaria/core/windowing/tab_drag_preview.dart';
import 'package:otzaria/navigation/view/tab_visuals.dart';
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

/// עומק אזור הקצה שגרירה בתוכו גוללת את הרצועה.
const double _kAutoScrollEdge = 40;

/// קצב הגלילה האוטומטית — פיקסלים לכל פעימה (פעימה לכל פריים בקירוב).
const double _kAutoScrollStep = 8;

const Duration _kAutoScrollTick = Duration(milliseconds: 16);

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

  /// מידת כל כרטיסיה לאורך ציר הרצועה — רוחב באופקית, גובה באנכית.
  final List<double> widths;

  /// ציר הרצועה. באנכית אין היפוך RTL: הכרטיסיה הראשונה תמיד למעלה.
  final Axis axis;

  /// רוחב הכרטיסיה הצפה בגרירה כשהציר אנכי; באופקית הרוחב נלקח מ-[widths].
  final double? crossExtent;

  /// האם הרצועה עצמה נגללת. ברצועה האופקית הרוחבים מחושבים כך שהכל נכנס.
  final bool scrollable;

  /// לחיצה ארוכה לגרירה גם בעכבר; בלעדיה היא נדרשת רק במגע ובעט.
  final bool requireLongPressToDrag;

  /// רקע הרצועה — הרקע שמאחורי הכרטיסיה במוק החלון שנגרר.
  ///
  /// ⚠️ מגיע מבחוץ ולא נלקח מ-`Theme`: ה-`feedback` חי ב-`Overlay`, והמוק
  /// הנייטיבי מצויר בכלל ב-GDI. שניהם צריכים את הצבע שהרצועה **באמת**
  /// צבועה בו, ולא ניחוש ממשטח דומה.
  final Color stripColor;

  /// בונה את תוכן הכרטיסיה. התוצאה נעטפת ב-[Draggable] ולכן חייבת לכלול את
  /// סמן ה-hit-test שהרצועה החיצונית מסתמכת עליו.
  final Widget Function(OpenedTab tab, int index, double width) tabBuilder;

  /// נקרא עם היעד בקונבנציית הסרה-ואז-הכנסה, כמצופה ב-`MoveTab`.
  final void Function(OpenedTab tab, int newIndex) onReorder;

  /// האם לקבל כרטיסיה נגררת שאינה ברצועה — חלונית של טאב מפוצל שנגררת
  /// חזרה לשורת הכרטיסיות.
  final bool Function(OpenedTab tab)? acceptsExternal;

  /// נקרא בשחרור כרטיסיה חיצונית, עם מיקום הכנסה בטווח `0..tabs.length`.
  final void Function(OpenedTab tab, int insertIndex)? onExternalDrop;

  /// נקרא כשמתחילה גרירת כרטיסיה, עם הכרטיסיה הנגררת.
  ///
  /// `cancelDrag` מבטל את הגרירה של Flutter בלי שהמשתמש שחרר את
  /// הכפתור — נדרש כשהגרירה נמסרת ל-Windows. ראו
  /// `_DraggableTabState._cancelDrag`.
  final void Function(OpenedTab tab, VoidCallback cancelDrag)? onDragStarted;

  /// נקרא כשמוק החלון מוכן — **אחרי** [onDragStarted].
  ///
  /// ⚠️ שני קולבקים ולא אחד: הצילום אסינכרוני, ותצוגת הגרירה חייבת
  /// להתחיל מיד. הבעלות על התמונה עוברת למי שמקבל אותה.
  final void Function(OpenedTab tab, TabWindowPreview preview, int generation)?
  onTabSnapshot;

  /// נקרא בסיום הגרירה בכל מסלול — הצלחה, ביטול, או שחרור בחוץ.
  ///
  /// ⚠️ נפרד מ-[onDroppedOutside]: תצוגת הגרירה הנייטיבית חייבת להיסגר
  /// **תמיד**, אחרת היא נשארת תלויה על המסך אחרי גרירה שהסתיימה בתוך
  /// החלון.
  final VoidCallback? onDragFinishedAnywhere;

  /// נקרא כשגרירה משתהה מעל כרטיסיה — היא נפתחת, וכך אפשר להמשיך ולשחרר
  /// את הנגררת לצדה באזור הקריאה בלי לוותר על הגרירה.
  final void Function(OpenedTab tab)? onSpringOpen;

  /// נקרא ביציאה מהרצועה, להבחנה בין סידור מקומי להוצאת כרטיסיה.
  final VoidCallback? onDragLeftStrip;

  /// נקרא כשכרטיסיה שוחררה מחוץ לכל יעד הפלה.
  ///
  /// ⚠️ זה כולל שחרור **מחוץ לחלון** — Flutter תופס את הסמן לכל אורך
  /// הגרירה, ולכן האירוע מגיע גם כשהמשתמש שחרר מעל חלון אחר או מעל שולחן
  /// העבודה. מי שמממש אחראי לברר לאן, כי Flutter אינו יודע דבר מחוץ
  /// לחלון שלו.
  final void Function(OpenedTab tab)? onDroppedOutside;

  const ReadingTabStrip({
    super.key,
    required this.tabs,
    required this.widths,
    required this.tabBuilder,
    required this.onReorder,
    required this.stripColor,
    this.acceptsExternal,
    this.onExternalDrop,
    this.onDragStarted,
    this.onTabSnapshot,
    this.onDragFinishedAnywhere,
    this.onSpringOpen,
    this.onDragLeftStrip,
    this.onDroppedOutside,
    this.requireLongPressToDrag = false,
    this.axis = Axis.horizontal,
    this.crossExtent,
    this.scrollable = false,
  });

  bool get isVertical => axis == Axis.vertical;

  @override
  State<ReadingTabStrip> createState() => _ReadingTabStripState();
}

class _ReadingTabStripState extends State<ReadingTabStrip> {
  late _TabStripGeometry _geometry;

  /// מיקום ההכנסה הנוכחי בטווח `0..tabs.length`, או `null` כשאין גרירה מעל.
  int? _insertIndex;

  /// הכרטיסיה שהגרירה משתהה מעליה, והשעון שיפתח אותה.
  OpenedTab? _springTarget;
  Timer? _springTimer;

  final ScrollController _scrollController = ScrollController();

  /// גלילת הקצה: הכיוון (1- למעלה/להתחלה, 1 למטה/לסוף), השעון שמניע אותה,
  /// והגרירה האחרונה שנמדדה — כדי לעדכן את מיקום ההכנסה גם כשהסמן עומד.
  double _autoScrollDirection = 0;
  Timer? _autoScrollTimer;
  OpenedTab? _autoScrollTab;
  Offset? _autoScrollOffset;

  @override
  void initState() {
    super.initState();
    _geometry = _TabStripGeometry.fromWidths(widget.widths);
    externalTabDrag.addListener(_onExternalDrag);
  }

  /// כרטיסיה מחלון אחר נגררת מעל החלון הזה.
  ///
  /// ⚠️ המיקום מגיע בקואורדינטות **מסך**, כי הוא נמדד בחלון אחר. רק כאן
  /// אפשר לתרגם אותו למיקום הכנסה, ולכן התוצאה נכתבת ל-
  /// [externalTabDropIndex] שה-host מחזיר לשולח.
  void _onExternalDrag() {
    final drag = externalTabDrag.value;
    if (drag == null) {
      externalTabDropIndex.value = null;
      if (_insertIndex != null) setState(() => _insertIndex = null);
      return;
    }
    final box = _contentKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    // המיקום כבר בקואורדינטות החלון (הומר ב-runner), ונשאר להמיר לרצועה.
    final local = box.globalToLocal(drag.local);

    // מחוץ לגובה הרצועה — הכרטיסיה תתקבל, אבל לא למקום מדויק.
    final cross = widget.isVertical ? local.dx : local.dy;
    final crossExtent = widget.isVertical ? box.size.width : box.size.height;
    if (cross < -12 || cross > crossExtent + 12) {
      externalTabDropIndex.value = null;
      if (_insertIndex != null) setState(() => _insertIndex = null);
      return;
    }

    final next = _insertIndexFor(widget.isVertical ? local.dy : local.dx);
    externalTabDropIndex.value = next;
    if (next != _insertIndex) setState(() => _insertIndex = next);
  }

  @override
  void didUpdateWidget(covariant ReadingTabStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(_geometry.widths, widget.widths)) {
      _geometry = _TabStripGeometry.fromWidths(widget.widths);
    }
  }

  @override
  void dispose() {
    externalTabDrag.removeListener(_onExternalDrag);
    _springTimer?.cancel();
    _autoScrollTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  /// מזניק או עוצר את גלילת הקצה לפי מיקום הסמן ברצועה.
  void _updateAutoScroll(OpenedTab dragged, Offset globalOffset) {
    if (!widget.scrollable) return;

    final box = _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return _stopAutoScroll();

    final local = box.globalToLocal(globalOffset);
    final main = widget.isVertical ? local.dy : local.dx;
    final extent = widget.isVertical ? box.size.height : box.size.width;

    // רחוק מחוץ לרצועה הגרירה כבר מכוונת לאזור הקריאה, ולא לסידור מחדש.
    if (main < -_kAutoScrollEdge || main > extent + _kAutoScrollEdge) {
      return _stopAutoScroll();
    }

    var direction = 0.0;
    if (main < _kAutoScrollEdge) {
      direction = -1;
    } else if (main > extent - _kAutoScrollEdge) {
      direction = 1;
    }
    // ב-RTL אופקי הגלילה מתקדמת שמאלה, ולכן קצה המסך ההפוך מגליל קדימה.
    if (_flipsForRtl) direction = -direction;

    if (direction == 0) return _stopAutoScroll();

    _autoScrollDirection = direction;
    _autoScrollTab = dragged;
    _autoScrollOffset = globalOffset;
    _autoScrollTimer ??= Timer.periodic(_kAutoScrollTick, _onAutoScrollTick);
  }

  void _onAutoScrollTick(Timer timer) {
    if (!_scrollController.hasClients) return _stopAutoScroll();

    final position = _scrollController.position;
    final target = (position.pixels + _autoScrollDirection * _kAutoScrollStep)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if (target == position.pixels) return _stopAutoScroll();

    position.jumpTo(target);
    // הרצועה זזה תחת סמן שעומד במקומו, ולכן מיקום ההכנסה נמדד מחדש.
    final tab = _autoScrollTab;
    final offset = _autoScrollOffset;
    if (tab != null && offset != null) _updateDragPosition(tab, offset);
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    _autoScrollDirection = 0;
    _autoScrollTab = null;
    _autoScrollOffset = null;
  }

  /// שורת הכרטיסיות עצמה. הרצועה נמתחת על כל הרוחב הפנוי, ולכן מדידה מול
  /// גבולותיה הייתה מוסיפה את השטח הריק — וב-RTL, שבו הכרטיסיות צמודות
  /// לימין, כל ההפרש נכנס לחישוב ומיקום ההכנסה יצא תמיד 0.
  final GlobalKey _contentKey = GlobalKey();

  /// מכל הגלילה עצמו — גבולותיו הם אזורי הקצה שגלילה אוטומטית נמדדת מולם,
  /// בשונה מ-[_contentKey] שגדל עם הכרטיסיות וזז עם הגלילה.
  final GlobalKey _viewportKey = GlobalKey();

  /// ב-RTL הכרטיסיה הראשונה יושבת בימין, ולכן המרחק נמדד מהקצה הימני. בציר
  /// אנכי אין היפוך: הכרטיסיה הראשונה למעלה בשתי הכיווניות.
  bool get _flipsForRtl =>
      !widget.isVertical && Directionality.of(context) == TextDirection.rtl;

  /// מיקום ההכנסה שאליו מצביע [localMain] (מיקום מקומי לאורך ציר הרצועה).
  ///
  /// ההשוואה היא לאמצע כל כרטיסיה — כך היעד מתחלף בדיוק כשחוצים אותה,
  /// והמידות אינן חייבות להיות אחידות.
  int _insertIndexFor(double localMain) {
    final total = _geometry.totalWidth;
    final flow = _flipsForRtl ? total - localMain : localMain;
    return _geometry.insertIndexAt(flow);
  }

  /// קצה ההתחלה של קו החיווי בתוך רצועת הכרטיסיות, מוגבל לגבולותיה — קו
  /// שחורג מהן מפעיל חיתוך ב-Stack וקוצץ את קצות הכרטיסיה הנבחרת.
  double _insertLineOffset(int index) {
    final edge = _geometry.edgeAt(index);
    final total = _geometry.totalWidth;
    final visualEdge = _flipsForRtl ? total - edge : edge;
    final maxOffset = total - _kInsertLineWidth;
    if (maxOffset <= 0) return 0;
    return (visualEdge - _kInsertLineWidth / 2).clamp(0.0, maxOffset);
  }

  /// הכרטיסיה שמתחת ל-[localMain], או `null` מחוץ לרצועה.
  ///
  /// שונה מ-[_insertIndexFor], שמחזיר גבול בין כרטיסיות ולא כרטיסיה.
  OpenedTab? _tabAt(double localMain) {
    final total = _geometry.totalWidth;
    final flow = _flipsForRtl ? total - localMain : localMain;
    final index = _geometry.tabIndexAt(flow);
    return index == null ? null : widget.tabs[index];
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
    _updateAutoScroll(dragged, globalOffset);

    final box = _contentKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    final local = box.globalToLocal(globalOffset);
    final localMain = widget.isVertical ? local.dy : local.dx;
    // פתיחת כרטיסיה בהשתהות הייתה מחליפה את הטאב המוצג — ובגרירה חיצונית
    // (מחלונית מפוצלת) מפרקת את מקור הגרירה עצמו באמצע המחווה.
    if (_acceptsReorder(dragged)) {
      _updateSpringTarget(dragged, _tabAt(localMain));
    }

    // setState רק כשהיעד באמת זז: onMove יורה בכל תזוזת מצביע.
    final next = _insertIndexFor(localMain);
    if (next != _insertIndex) setState(() => _insertIndex = next);
  }

  /// כרטיסיה שנמצאת ברצועה — לסידור מחדש.
  bool _acceptsReorder(OpenedTab tab) => widget.tabs.contains(tab);

  bool _accepts(OpenedTab tab) =>
      _acceptsReorder(tab) ||
      (widget.onExternalDrop != null &&
          (widget.acceptsExternal?.call(tab) ?? false));

  void _completeReorder(OpenedTab tab) {
    final insertIndex = _insertIndex;
    _cancelSpring();
    _stopAutoScroll();
    setState(() => _insertIndex = null);
    if (insertIndex == null) return;

    final oldIndex = widget.tabs.indexOf(tab);
    if (oldIndex == -1) {
      // כרטיסיה חיצונית נכנסת במיקום ההכנסה כמות שהוא — אין מה להסיר.
      widget.onExternalDrop?.call(tab, insertIndex);
      return;
    }

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
        _stopAutoScroll();
        if (_insertIndex != null) setState(() => _insertIndex = null);
        // יציאה מהרצועה מאפשרת מסירה מוקדמת ל-Windows.
        widget.onDragLeftStrip?.call();
      },
      onAcceptWithDetails: (details) => _completeReorder(details.data),
      builder: (context, candidate, rejected) {
        // הרצועה נמתחת על כל הרוחב הפנוי ולא מתכווצת לרוחב הכרטיסיות: השטח
        // שנותר הוא "האזור הריק" שגרירת חלון ולחיצה כפולה למסך מלא מסתמכות
        // על קיומו.
        final isVertical = widget.isVertical;
        return SizedBox(
          width: isVertical ? null : double.infinity,
          height: isVertical ? double.infinity : null,
          // ברצועה האופקית הגלילה מנוטרלת: הרוחבים מחושבים כך שכל הכרטיסיות
          // ייכנסו, אבל בפריים הראשון — לפני שאזור הכרטיסיות נמדד — הם לפי
          // רוחב המסך. בלי מכל שגולש בשקט אותו פריים היה זורק overflow.
          child: SingleChildScrollView(
            key: _viewportKey,
            controller: _scrollController,
            scrollDirection: widget.axis,
            physics: widget.scrollable
                ? null
                : const NeverScrollableScrollPhysics(),
            // קו החיווי יושב באותו Stack עם הרצועה, ולכן באותה מערכת
            // קואורדינטות שבה נמדד מיקום ההכנסה.
            child: Stack(
              children: [
                Flex(
                  key: _contentKey,
                  direction: widget.axis,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < widget.tabs.length; i++)
                      _DraggableTab(
                        key: ObjectKey(widget.tabs[i]),
                        tab: widget.tabs[i],
                        axis: widget.axis,
                        extent: widget.widths[i],
                        crossExtent: widget.crossExtent,
                        requireLongPress: widget.requireLongPressToDrag,
                        stripColor: widget.stripColor,
                        onDragStarted: widget.onDragStarted == null
                            ? null
                            : (cancelDrag) => widget.onDragStarted!(
                                widget.tabs[i],
                                cancelDrag,
                              ),
                        onTabSnapshot: widget.onTabSnapshot == null
                            ? null
                            : (preview, generation) => widget.onTabSnapshot!(
                                widget.tabs[i],
                                preview,
                                generation,
                              ),
                        onDroppedOutside: widget.onDroppedOutside == null
                            ? null
                            : () => widget.onDroppedOutside!(widget.tabs[i]),
                        // גרירה שהסתיימה מחוץ לרצועה אינה מפעילה onLeave,
                        // ולכן קו החיווי מנוקה גם כאן.
                        onDragFinished: () {
                          _cancelSpring();
                          _stopAutoScroll();
                          if (_insertIndex != null) {
                            setState(() => _insertIndex = null);
                          }
                          widget.onDragFinishedAnywhere?.call();
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
                  _InsertIndicator(
                    axis: widget.axis,
                    offset: _insertLineOffset(_insertIndex!),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// גבולות מצטברים של הכרטיסיות: נבנים רק כשמערך הרוחבים מתעדכן, וכל
/// תזוזת מצביע מחפשת בהם במקום לסרוק את הכרטיסיות שוב.
class _TabStripGeometry {
  final List<double> widths;
  final List<double> _edges;
  final List<double> _midpoints;

  const _TabStripGeometry._(this.widths, this._edges, this._midpoints);

  factory _TabStripGeometry.fromWidths(List<double> widths) {
    final edges = <double>[0];
    final midpoints = <double>[];
    var total = 0.0;
    for (final width in widths) {
      midpoints.add(total + width / 2);
      total += width;
      edges.add(total);
    }
    return _TabStripGeometry._(List.unmodifiable(widths), edges, midpoints);
  }

  double get totalWidth => _edges.last;

  double edgeAt(int index) => _edges[index.clamp(0, _edges.length - 1)];

  int insertIndexAt(double flowX) {
    var lower = 0;
    var upper = _midpoints.length;
    while (lower < upper) {
      final middle = (lower + upper) ~/ 2;
      if (flowX < _midpoints[middle]) {
        upper = middle;
      } else {
        lower = middle + 1;
      }
    }
    return lower;
  }

  int? tabIndexAt(double flowX) {
    if (flowX < 0 || flowX >= totalWidth) return null;

    var lower = 0;
    var upper = _edges.length - 1;
    while (lower < upper) {
      final middle = (lower + upper) ~/ 2;
      if (flowX < _edges[middle + 1]) {
        upper = middle;
      } else {
        lower = middle + 1;
      }
    }
    return lower;
  }
}

/// כרטיסיה בודדת ברצועה, ניתנת לגרירה.
class _DraggableTab extends StatefulWidget {
  final OpenedTab tab;
  final Axis axis;
  final double extent;
  final double? crossExtent;
  final bool requireLongPress;

  /// רקע הרצועה — ראו [ReadingTabStrip.stripColor].
  final Color stripColor;

  /// נקרא כשמתחילה גרירה מהכרטיסיה הזו, עם דרך לבטל אותה.
  final void Function(VoidCallback cancelDrag)? onDragStarted;

  /// נקרא כשמוק החלון מוכן — **אחרי** [onDragStarted].
  ///
  /// ⚠️ שני קולבקים ולא אחד: הצילום אסינכרוני, ותצוגת הגרירה חייבת להתחיל
  /// מיד. הבעלות על התמונה עוברת למי שמקבל אותה.
  final void Function(TabWindowPreview preview, int generation)? onTabSnapshot;
  final VoidCallback onDragFinished;

  /// נקרא כשהכרטיסיה שוחררה מחוץ לכל יעד הפלה — ייתכן מחוץ לחלון כולו.
  final VoidCallback? onDroppedOutside;
  final Widget child;

  const _DraggableTab({
    super.key,
    required this.tab,
    required this.axis,
    required this.extent,
    required this.crossExtent,
    required this.requireLongPress,
    required this.stripColor,
    required this.onDragStarted,
    required this.onTabSnapshot,
    required this.onDragFinished,
    required this.onDroppedOutside,
    required this.child,
  });

  @override
  State<_DraggableTab> createState() => _DraggableTabState();
}

class _DraggableTabState extends State<_DraggableTab> {
  /// ⚠️ `RepaintBoundary` פר-כרטיסיה, וזה המחיר של נאמנות.
  ///
  /// שרטוט מחדש של הכרטיסיה בנייטיב אינו יכול להיות זהה — גופן, אייקון
  /// סוג, כפתור X, סימון בחירה — ולכן התצוגה שמחוץ לחלון מקבלת **צילום**
  /// של הכרטיסיה האמיתית. צילום מחייב גבול ציור.
  ///
  /// המחיר מוגבל: הכרטיסיה הנגררת מקבלת שכבה נפרדת ממילא בזמן הגרירה
  /// (`Draggable.feedback`), והרצועה מחזיקה עשרות כרטיסיות לכל היותר.
  final GlobalKey _boundaryKey = GlobalKey();

  /// ⚠️ `toImage` (אסינכרוני) ולא `toImageSync`.
  ///
  /// `toImageSync` היה הבחירה הראשונה, כי `onDragStarted` סינכרוני — והוא
  /// החזיר תמונה **ריקה**: המשתמש ראה כרטיסיה שקופה במקום כרטיסיה. עם
  /// Impeller, ברירת המחדל ב-Flutter 3.47, המסלול הסינכרוני אינו אמין
  /// לקריאה מיידית של הפיקסלים.
  ///
  /// ההמתנה אינה עולה כלום כאן: התצוגה הנייטיבית מופיעה מיד עם שרטוט GDI,
  /// והתמונה מחליפה אותו כשהיא מוכנה.
  Future<ui.Image?> _captureTab(double pixelRatio) async {
    return captureBoundary(_boundaryKey, pixelRatio);
  }

  /// צילום אזור התוכן, לתצוגה המוקטנת שבתוך החלון.
  ///
  /// ⚠️ שדה ולא משתנה מקומי: ה-`feedback` נבנה שוב ושוב בזמן הגרירה,
  /// והוא צריך לקרוא את התמונה כשהיא מגיעה. `ValueNotifier` ולא `setState`
  /// כי ה-feedback חי ב-`Overlay` ואינו תת-עץ של הכרטיסיה.
  final ValueNotifier<ui.Image?> _contentImage = ValueNotifier(null);

  /// מחליף את הצילום ומשחרר את קודמו.
  ///
  /// ⚠️ `ui.Image` מחזיקה זיכרון GPU שאינו נאסף לבד. השמה ישירה
  /// ל-`_contentImage.value` הייתה מדליפה צילום של חלון מלא (~5MB) בכל
  /// גרירה שנייה של אותה כרטיסיה, ועוד אחד בכל גרירה שהסתיימה.
  void _setContentImage(ui.Image? image) {
    final previous = _contentImage.value;
    if (identical(previous, image)) return;
    _contentImage.value = image;
    previous?.dispose();
  }

  @override
  void dispose() {
    _setContentImage(null);
    _contentImage.dispose();
    super.dispose();
  }

  /// המצביע שבו מתבצעת הגרירה, לביטולה מבחוץ. ראו [_cancelDrag].
  int? _pointer;

  /// מבטל את הגרירה של Flutter מבלי שהמשתמש שחרר את הכפתור.
  ///
  /// ⚠️ נדרש כשהגרירה נמסרת ל-Windows (Snap Layouts): מאותו רגע לולאת
  /// ההזזה של המערכת לוכדת את העכבר, ו-Flutter **לא יראה את השחרור** —
  /// כלומר ה-[Draggable] היה נשאר תקוע לנצח, עם הכרטיסיה מעומעמת במקומה.
  ///
  /// ה-cancel מגיע לזירת המחוות ולכן מסתיים דרך `onDraggableCanceled`,
  /// כמו כל גרירה שהתפספסה — אותו מסלול סיום בדיוק.
  void _cancelDrag() {
    final pointer = _pointer;
    if (pointer == null) return;
    GestureBinding.instance.cancelPointer(pointer);
  }

  /// האם גרירה פעילה, והאם [_buildPreview] עוד רץ.
  ///
  /// ⚠️ שני דגלים, ולא אחד. הצילום נדרש רק כל עוד ה-`feedback` מוצג, אבל
  /// **שחרורו בסיום הגרירה בזמן שההרכבה עוד קוראת אותו הוא
  /// use-after-dispose**. וזה לא תרחיש תיאורטי: הגרירה מבוטלת מיד כשהיא
  /// נמסרת ל-Windows, וההרכבה אסינכרונית — כלומר הסיום מגיע דווקא באמצע.
  ///
  /// מי שמסיים אחרון משחרר: אם ההרכבה עוד רצה, הסיום מדלג והיא תשחרר.
  bool _dragging = false;
  bool _previewPending = false;
  int _dragGeneration = 0;

  void _handleDragFinished() {
    _dragging = false;
    if (!_previewPending) _setContentImage(null);
    widget.onDragFinished();
  }

  void _handleDragStarted() {
    _dragging = true;
    _setContentImage(null);
    // ⚠️ מודיעים **מיד**, ובלי להמתין לצילום: התצוגה הנייטיבית מתחילה עם
    // שרטוט GDI כדי שלא יהיה רגע ריק, והתמונה מגיעה בקריאה שנייה.
    widget.onDragStarted?.call(_cancelDrag);
    _previewPending = true;
    final generation = ++_dragGeneration;
    unawaited(_finishPreview(generation));
  }

  /// עוטף את [_buildPreview] ומשחרר את הצילום אם הגרירה הסתיימה בינתיים.
  Future<void> _finishPreview(int generation) async {
    try {
      await _buildPreview(generation);
    } finally {
      if (generation == _dragGeneration) {
        _previewPending = false;
        if (!_dragging) _setContentImage(null);
      }
    }
  }

  /// מצלם את הכרטיסיה הנגררת, או מצייר מוק אם אין לה גבול ציור זמין.
  /// אזור התוכן אינו מקור צילום: הוא מציג תמיד את הכרטיסיה הפעילה.
  Future<ui.Image?> _captureContent(double ratio) async {
    final key = TabContentBoundaries.instance.maybeKeyFor(widget.tab);
    final captured = key == null ? null : await captureBoundary(key, ratio);
    if (captured != null) return captured;
    if (!mounted) return null;

    // המוק נמדד לפי אזור התוכן, ולא לפי החלון הרחב ממנו.
    final contentBox =
        windowContentBoundaryKey.currentContext?.findRenderObject()
            as RenderBox?;
    final size = contentBox != null && contentBox.hasSize
        ? contentBox.size
        : null;
    if (size == null || size.isEmpty) return null;

    return composeTabContentPlaceholder(
      title: widget.tab.title,
      icon: tabTypeIconData(widget.tab),
      background: widget.stripColor,
      foreground: Theme.of(context).colorScheme.onSurface,
      logicalSize: size,
      captureRatio: ratio,
      rtl: Directionality.of(context) == TextDirection.rtl,
    );
  }

  /// מצלם את הכרטיסיה ואת התוכן שלה, ומרכיב מהם מוק של החלון.
  ///
  /// ## למה שני צילומים ולא צילום של החלון
  ///
  /// צילום החלון היה מראה את **כל** הכרטיסיות הפתוחות, בעוד שהחלון שייפתח
  /// יכיל אחת. ההרכבה מציגה את מה שיהיה שם.
  ///
  /// שתי תוצאות משני הצילומים:
  /// * המוק המלא — לתצוגה הנייטיבית שמחוץ לחלון, בגודל החלון שייפתח.
  /// * צילום התוכן לבדו — לתצוגה המוקטנת שבתוך החלון, שם ראש הכרטיסיה
  ///   מוצג כווידג'ט אמיתי ולא כתמונה.
  Future<void> _buildPreview(int generation) async {
    final view = View.of(context);
    final dpr = view.devicePixelRatio;
    final logical = view.physicalSize / dpr;
    final ratio = previewCaptureRatio(logical, dpr);

    final content = await _captureContent(ratio);
    if (!mounted || generation != _dragGeneration) {
      content?.dispose();
      return;
    }
    if (content != null) _setContentImage(content);

    final onSnapshot = widget.onTabSnapshot;
    if (onSnapshot == null) return;
    // ⚠️ הגרירה כבר הסתיימה — אין למי להציג את המוק. ההרכבה היא צילום
    // שני, מיזוג ותמונה של ~4.8MB, וגרירה קצרה שילמה את כולם על לא כלום.
    if (!_dragging || generation != _dragGeneration) return;

    final tabHead = await _captureTab(ratio);
    if (tabHead == null) return;
    if (!mounted || content == null || generation != _dragGeneration) {
      tabHead.dispose();
      return;
    }

    final preview = await composeTabWindowPreview(
      tabHead: tabHead,
      content: content,
      stripColor: widget.stripColor,
      devicePixelRatio: dpr,
      captureRatio: ratio,
      rtl: Directionality.of(context) == TextDirection.rtl,
    );
    tabHead.dispose();
    if (preview == null) return;
    // מונע ממוק מאוחר להישלח לגרירה שכבר הסתיימה או הוחלפה.
    if (!mounted || !_dragging || generation != _dragGeneration) {
      preview.image.dispose();
      return;
    }
    onSnapshot(preview, generation);
  }

  @override
  Widget build(BuildContext context) {
    // ⚠️ הגבול עוטף את הכרטיסיה שברצועה, ולא את ה-feedback: ה-feedback
    // קיים רק בזמן הגרירה, והצילום נדרש **ברגע** שהיא מתחילה.
    final child = RepaintBoundary(key: _boundaryKey, child: widget.child);

    // הכרטיסיה נשארת במקומה מעומעמת ולא נעלמת: היעלמותה הייתה משנה את חלוקת
    // המידות באמצע הגרירה ומזיזה את שאר הכרטיסיות תחת הסמן.
    final placeholder = Opacity(opacity: _kDraggingTabOpacity, child: child);
    final isVertical = widget.axis == Axis.vertical;
    final feedback = _TabDragFeedback(
      width: isVertical ? widget.crossExtent : widget.extent,
      height: isVertical ? widget.extent : null,
      stripColor: widget.stripColor,
      contentImage: _contentImage,
      child: widget.child,
    );

    // ⚠️ ה-Listener רק **מתעד** את המצביע, ואינו צורך את האירוע:
    // `deferToChild` מעביר אותו ל-Draggable כרגיל. המצביע נדרש כדי
    // שנוכל לבטל את הגרירה מבחוץ — ראו [_cancelDrag].
    final draggable = widget.requireLongPress
        ? LongPressDraggable<OpenedTab>(
            data: widget.tab,
            dragAnchorStrategy: pointerDragAnchorStrategy,
            feedback: feedback,
            childWhenDragging: placeholder,
            onDragStarted: _handleDragStarted,
            onDragEnd: (_) => _handleDragFinished(),
            onDraggableCanceled: (_, _) {
              _handleDragFinished();
              widget.onDroppedOutside?.call();
            },
            child: child,
          )
        : _TouchLongPressDraggable(
            data: widget.tab,
            // חובה: ה-offset שמקבלים יעדי ההפלה הוא פינת ה-feedback, ולכן עוגן
            // ברירת המחדל מסיט את אזור ההפלה בכחצי רוחב כרטיסיה.
            dragAnchorStrategy: pointerDragAnchorStrategy,
            feedback: feedback,
            childWhenDragging: placeholder,
            onDragStarted: _handleDragStarted,
            onDragEnd: (_) => _handleDragFinished(),
            onDraggableCanceled: (_, _) {
              _handleDragFinished();
              widget.onDroppedOutside?.call();
            },
            child: child,
          );

    return Listener(
      onPointerDown: (event) => _pointer = event.pointer,
      child: draggable,
    );
  }
}

/// גרירה מיידית בעכבר, ובמגע ובעט (שגוללים ברשימות) רק אחרי לחיצה ארוכה.
class _TouchLongPressDraggable extends Draggable<OpenedTab> {
  const _TouchLongPressDraggable({
    required super.child,
    required super.feedback,
    super.data,
    super.childWhenDragging,
    super.dragAnchorStrategy,
    super.onDragStarted,
    super.onDragEnd,
    super.onDraggableCanceled,
  });

  @override
  MultiDragGestureRecognizer createRecognizer(
    GestureMultiDragStartCallback onStart,
  ) => _TouchDelayedDragRecognizer()..onStart = onStart;
}

class _TouchDelayedDragRecognizer extends ImmediateMultiDragGestureRecognizer {
  final _touch = DelayedMultiDragGestureRecognizer();

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.mouse) {
      return super.addAllowedPointer(event);
    }
    _touch
      ..onStart = onStart
      ..gestureSettings = gestureSettings
      ..addPointer(event);
  }

  @override
  void dispose() {
    _touch.dispose();
    super.dispose();
  }
}

/// הכרטיסיה הצפה תחת הסמן בזמן גרירה — **עם התוכן שלה**.
///
/// ## למה לא רק ראש הכרטיסיה
///
/// עד כה נגרר ראש הכרטיסיה לבדו, וזה הפער שהמשתמש תיאר: "נגרר רק ראש
/// הכרטיסייה, ואני מעוניין שיגרר כל תוכן הכרטיסייה". מה שנגרר עכשיו הוא
/// מוק מוקטן של החלון — הכרטיסיה בראש, והתוכן שלה מתחתיה.
///
/// ⚠️ **מוקטן ולא בגודל אמיתי**, ורק כאן. סידור כרטיסיות בתוך הרצועה הוא
/// מחווה מקומית, ותצוגה בגודל חלון הייתה מכסה את התוכנה בזמן שהמשתמש
/// מנסה לראות לאן הכרטיסיה נכנסת. בגרירה **החוצה** התצוגה הנייטיבית כן
/// בגודל אמיתי — שם היא מוק של החלון שעומד להיפתח.
///
/// ⚠️ התוכן מגיע **אחרי** תחילת הגרירה, כי הצילום אסינכרוני. עד שהוא
/// מגיע מוצג ראש הכרטיסיה לבדו — כלומר ההתנהגות הקודמת, ולא רגע ריק.
///
/// מוצגת ב-[Overlay] ולכן אינה יורשת את ערכת הנושא ואת שכבת ה-[Material]
/// של הרצועה — בלי העטיפה המפורשת הצבעים נופלים לברירות מחדל.
class _TabDragFeedback extends StatelessWidget {
  final double? width;
  final double? height;

  /// רקע רצועת הכרטיסיות — הרקע שמאחורי הכרטיסיה במוק.
  final Color stripColor;

  /// צילום אזור התוכן, כשהוא מוכן.
  final ValueListenable<ui.Image?> contentImage;

  final Widget child;

  const _TabDragFeedback({
    required this.width,
    this.height,
    required this.stripColor,
    required this.contentImage,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // ⚠️ ה-`feedback` מצויר ב-Overlay ולכן אינו יורש את ה-`Theme` של הרצועה.
    // הכיווניות **כן** נורשת, ולכן אין צורך לעטוף בה.
    return Theme(
      data: theme,
      // העוגן הוא נקודת המצביע, ולכן התצוגה מוזזת כדי לרחף סביבו.
      child: ValueListenableBuilder<ui.Image?>(
        valueListenable: contentImage,
        builder: (context, content, _) => FractionalTranslation(
          // ⚠️ המוק יורד **מתחת** לסמן, ורק הוא. ראש הכרטיסיה לבדו
          // ממורכז על הסמן כמו קודם, אבל מוק בגובה 170 שממורכז עליו
          // מכסה את הכרטיסיות שמימין ומשמאל — בדיוק אותן כרטיסיות
          // שהמשתמש צריך לראות זזות כדי לדעת לאן הנגררת נכנסת.
          translation: content == null
              ? const Offset(-0.5, -0.5)
              : const Offset(-0.5, 0),
          child: Material(
            color: content == null
                ? theme.colorScheme.surfaceContainerHigh
                : stripColor,
            elevation: 8,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: content == null
                ? SizedBox(width: width, height: height, child: child)
                : _MiniWindow(
                    content: content,
                    tabWidth: width,
                    stripColor: stripColor,
                    tab: child,
                  ),
          ),
        ),
      ),
    );
  }
}

/// מוק מוקטן של החלון: הכרטיסיה בראש, וצילום התוכן מתחתיה.
class _MiniWindow extends StatelessWidget {
  const _MiniWindow({
    required this.content,
    required this.tabWidth,
    required this.stripColor,
    required this.tab,
  });

  final ui.Image content;
  final double? tabWidth;
  final Color stripColor;
  final Widget tab;

  @override
  Widget build(BuildContext context) {
    // ⚠️ הגובה נגזר מיחס אזור התוכן, כדי שהמוק ייראה כמו החלון ולא כמו
    // מלבן שרירותי. תקרה נפרדת מונעת מוק ארוך במסך גבוה-וצר.
    final aspect = content.height / content.width;
    final contentHeight = math.min(
      kMiniPreviewWidth * aspect,
      kMiniPreviewMaxHeight,
    );
    return SizedBox(
      width: kMiniPreviewWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ⚠️ הכרטיסיה כווידג'ט אמיתי ולא כתמונה: כאן היא מוצגת בגודלה
          // הלוגי, וצילום שהוקטן לצורך הערוץ היה נראה מטושטש דווקא
          // במקום שבו המשתמש מסתכל.
          SizedBox(
            width: tabWidth == null
                ? null
                : math.min(tabWidth!, kMiniPreviewWidth),
            child: tab,
          ),
          SizedBox(
            width: kMiniPreviewWidth,
            height: contentHeight,
            child: RawImage(
              image: content,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
            ),
          ),
        ],
      ),
    );
  }
}

/// קו המסמן היכן הכרטיסיה הנגררת תיכנס — אנכי ברצועה אופקית ולהפך.
class _InsertIndicator extends StatelessWidget {
  final Axis axis;

  /// קצה ההתחלה של הקו, כבר ממורכז על נקודת ההכנסה ומוגבל לגבולות הרצועה.
  final double offset;

  const _InsertIndicator({required this.axis, required this.offset});

  @override
  Widget build(BuildContext context) {
    final isVertical = axis == Axis.vertical;
    return Positioned(
      top: isVertical ? offset : 4,
      bottom: isVertical ? null : 4,
      left: isVertical ? 4 : offset,
      right: isVertical ? 4 : null,
      width: isVertical ? null : _kInsertLineWidth,
      height: isVertical ? _kInsertLineWidth : null,
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
