import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/view/pane_drop_geometry.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/layout/split_pane_content_inset.dart';

/// עובי רצועת המפריד בעכבר.
const double kPaneDividerThickness = 12;

/// עובי רצועת המפריד במגע — אצבע אינה מדייקת ל-12 פיקסלים.
const double kPaneDividerThicknessTouch = 24;

/// עובי ידית המפריד כשהיא מוצגת. במנוחה אין ידית כלל — הרווח שבין כרטיסי
/// החלוניות הוא ההפרדה.
const double _kDividerHandleThickness = 4;

/// אורך ידית המפריד לאורך הרצועה.
const double _kDividerHandleLength = 40;

/// עיגול פינות כרטיס החלונית.
const double kPaneCardRadius = 10;

/// שוליים סביב כרטיס החלונית, מעבר לרצועת המפריד.
const double kPaneCardMargin = 3;

/// סכום ה-flex בין שתי החלוניות — קובע את דיוק היחס (0.1%).
const int _kFlexResolution = 1000;

/// כמה זז המפריד בכל הקשה על חץ.
const double _kKeyboardNudge = 24;

/// השהיית השמירה אחרי הקשות מקלדת, כדי שהקשה ממושכת תישמר פעם אחת.
const Duration _kKeyboardCommitDelay = Duration(milliseconds: 250);

/// עובי רצועת המפריד לפי אמצעי הקלט של הפלטפורמה.
double paneDividerThicknessFor(TargetPlatform platform) {
  return platform == TargetPlatform.android || platform == TargetPlatform.iOS
      ? kPaneDividerThicknessTouch
      : kPaneDividerThickness;
}

/// מציג טאב: חלונית אחת, או שתיים זו לצד זו עם מפריד ניתן לגרירה.
///
/// [paneBuilder] נקרא לכל חלונית. כל חלונית נעטפת ב-[GlobalObjectKey] לפי
/// זהות האובייקט שלה, כך שפיצול הטאב ופירוקו מעבירים את ה-Element שלה
/// (reparenting) במקום להרוס ולבנות אותו מחדש — בלי זה כל פיצול היה טוען
/// מחדש את הספר ומאבד את מיקום הקריאה.
class SplitPaneView extends StatelessWidget {
  /// הטאב המוצג — מפוצל או יחיד.
  final OpenedTab root;

  /// בונה את תוכן החלונית.
  final Widget Function(OpenedTab pane) paneBuilder;

  /// נקרא בתום גרירת המפריד, עם היחס החדש.
  final ValueChanged<double> onRatioChanged;

  const SplitPaneView({
    super.key,
    required this.root,
    required this.paneBuilder,
    required this.onRatioChanged,
  });

  @override
  Widget build(BuildContext context) {
    final node = root;
    if (node is! CombinedTab) {
      return buildPane(node, EdgeInsets.zero, paneBuilder);
    }

    // הרווח שסביב הכרטיסים ובין שניהם הוא ההפרדה — אין קו מפריד במנוחה.
    return ColoredBox(
      color: AppSurfaces.paneGutter(context),
      child: Padding(
        padding: const EdgeInsets.all(kPaneCardMargin),
        child: _SplitNode(
          // מפתח לפי זהות הצומת: החלפת צדדים מחליפה את הטאב ומאפסת נכון את
          // היחס המקומי, בעוד גרירת מפריד משנה אותו במקום ולא נוגעת במפתח.
          key: ObjectKey(node),
          node: node,
          thickness: paneDividerThicknessFor(Theme.of(context).platform),
          paneBuilder: paneBuilder,
          onRatioChanged: onRatioChanged,
        ),
      ),
    );
  }

  /// עוטפת חלונית במפתח היציב שלה ובשוליים המפצים על עובי המפריד.
  @visibleForTesting
  static Widget buildPane(
    OpenedTab pane,
    EdgeInsetsGeometry contentInset,
    Widget Function(OpenedTab pane) paneBuilder,
  ) {
    return ClipRect(
      child: SplitPaneContentInset(
        contentInset: contentInset,
        child: KeyedSubtree(
          key: GlobalObjectKey(pane),
          child: paneBuilder(pane),
        ),
      ),
    );
  }
}

/// המסגור של חלונית בטאב מפוצל: משטח מעוגל שצף מעל הרווח שבין החלוניות.
/// החלונית הפעילה מסומנת בקו דק — זה החיווי היחיד ל"במה אני עובד".
///
/// בטאב שאינו מפוצל ([isSplit] כבוי) אין מסגרת והחלונית ממלאת את המסך כמו
/// קודם. הווידג'ט עצמו נשאר בעץ בשני המצבים: החלפתו בילד עצמו הייתה משנה את
/// סוג הווידג'ט בפיצול ובפירוק, ובונה מחדש את הספר.
class PaneCard extends StatelessWidget {
  final bool isActive;
  final bool isSplit;
  final Widget child;

  const PaneCard({
    super.key,
    required this.isActive,
    required this.isSplit,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(isSplit ? kPaneCardRadius : 0);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: isSplit ? AppSurfaces.paneCard(context) : Colors.transparent,
        borderRadius: radius,
        border: isSplit
            ? Border.all(
                color: AppSurfaces.paneCardBorder(cs, isActive: isActive),
              )
            : null,
        boxShadow: isSplit
            ? [
                BoxShadow(
                  color: AppSurfaces.paneCardShadow(cs, isActive: isActive),
                  blurRadius: isActive ? 10 : 6,
                  offset: const Offset(0, 1),
                ),
              ]
            : null,
      ),
      // חיתוך לפי אותו רדיוס: בלעדיו תוכן הספר יוצא מעבר לפינות המעוגלות.
      child: ClipRRect(borderRadius: radius, child: child),
    );
  }
}

/// שתי חלוניות ומפריד ביניהן.
class _SplitNode extends StatefulWidget {
  final CombinedTab node;
  final double thickness;
  final Widget Function(OpenedTab pane) paneBuilder;
  final ValueChanged<double> onRatioChanged;

  const _SplitNode({
    super.key,
    required this.node,
    required this.thickness,
    required this.paneBuilder,
    required this.onRatioChanged,
  });

  @override
  State<_SplitNode> createState() => _SplitNodeState();
}

class _SplitNodeState extends State<_SplitNode> {
  /// היחס מוחזק ב-notifier ולא ב-state: גרירת מפריד מעדכנת רק את ה-Flex,
  /// בעוד `setState` היה בונה מחדש את שתי תצוגות הספרים בכל פריים.
  late final ValueNotifier<double> _ratioNotifier;
  bool _dragging = false;
  Timer? _commitDebounce;

  double get _ratio => _ratioNotifier.value;

  @override
  void initState() {
    super.initState();
    _ratioNotifier = ValueNotifier<double>(widget.node.splitRatio);
  }

  @override
  void dispose() {
    _commitDebounce?.cancel();
    _ratioNotifier.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_SplitNode oldWidget) {
    super.didUpdateWidget(oldWidget);
    // מסתנכרן עם יחס שהגיע מבחוץ (איפוס מתפריט, טעינה מדיסק). ההשוואה לערך
    // ולא לזהות: המפתח מבטיח שאותו State מקבל תמיד את אותו טאב.
    //
    // הזזה שטרם נשמרה מוגנת: בגרירה דרך `_dragging`, ובהקשת חצים דרך שעון
    // ה-debounce. בלי השני, בנייה מחדש של ההורה בתוך רבע שנייה הייתה מוחקת
    // את ההקשה — וגם משמרת את המחיקה, כי השמירה המושהית משדרת את הישן.
    if (!_dragging &&
        _commitDebounce == null &&
        widget.node.splitRatio != _ratio) {
      _ratioNotifier.value = widget.node.splitRatio;
    }
  }

  /// המקום שנותר לשתי החלוניות אחרי ניכוי המפריד, לפי הרוחב בפועל.
  double? get _availableExtent {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final available = box.size.width - widget.thickness;
    return available > 0 ? available : null;
  }

  /// מזיז את המפריד ב-[delta] פיקסלים; חיובי מגדיל את החלונית הראשונה.
  void _applyAxisDelta(double delta) {
    final availableExtent = _availableExtent;
    if (availableExtent == null) return;

    // ההגבלה בפיקסלים ולא באחוזים — במסך צר יחס קבוע היה מאפשר לכווץ
    // חלונית עד לרוחב בלתי שמיש.
    final minRatio = (kMinPaneExtent / availableExtent).clamp(0.0, 0.5);
    // אין מקום לשתי חלוניות קריאות: כל הזזה הייתה נצמדת ל-50% ודורסת בשקט
    // את היחס השמור, שלא היה חוזר גם אחרי הרחבת החלון.
    if (minRatio >= 0.5) return;
    _ratioNotifier.value = (_ratio + delta / availableExtent).clamp(
      minRatio,
      1 - minRatio,
    );
  }

  void _onDragUpdate(DragUpdateDetails details) {
    // ב-RTL הציר הפוך: גרירה שמאלה מגדילה את החלונית הראשונה (הימנית).
    _applyAxisDelta(
      Directionality.of(context) == TextDirection.rtl
          ? -details.delta.dx
          : details.delta.dx,
    );
  }

  /// הזזה בהקשה על חץ; [towardFirst] = כיווץ החלונית הראשונה.
  void _nudge({required bool towardFirst}) {
    final before = _ratio;
    _applyAxisDelta(towardFirst ? -_kKeyboardNudge : _kKeyboardNudge);
    // בקצה ה-clamp ההקשה אינה מזיזה דבר, ואין מה לשמור.
    if (_ratio == before) return;
    // הקשה ממושכת מייצרת עשרות אירועים; שמירה בכל אחד מהם הייתה מסרלת את כל
    // עץ הטאבים לדיסק שוב ושוב. הגרירה בעכבר שומרת פעם אחת בסוף — כאן זה
    // מושג בהשהיה קצרה.
    _commitDebounce?.cancel();
    _commitDebounce = Timer(_kKeyboardCommitDelay, _commit);
  }

  /// היחס שיושג בהזזה אחת, לדיווח לקורא מסך. חסום באותם גבולות כמו ההזזה
  /// עצמה, אחרת מוכרז ערך שלא יושג לעולם.
  double _ratioAfterNudge({required bool towardFirst}) {
    final extent = _availableExtent;
    if (extent == null) return _ratio;
    final minRatio = (kMinPaneExtent / extent).clamp(0.0, 0.5);
    if (minRatio >= 0.5) return _ratio;
    final delta = (towardFirst ? -_kKeyboardNudge : _kKeyboardNudge) / extent;
    return (_ratio + delta).clamp(minRatio, 1 - minRatio);
  }

  void _commit() {
    _commitDebounce?.cancel();
    _commitDebounce = null;
    _dragging = false;
    widget.node.splitRatio = _ratio;
    widget.onRatioChanged(_ratio);
  }

  void _resetRatio() {
    _ratioNotifier.value = 0.5;
    _commit();
  }

  @override
  Widget build(BuildContext context) {
    // שתי החלוניות נבנות פעם אחת לכל בנייה של הצומת, ונלכדות ב-closure שלהלן.
    // עדכון היחס מפעיל רק את ה-builder, ו-Flutter מדלג על תת-עץ שהווידג'ט שלו
    // זהה — כך גרירת מפריד אינה בונה מחדש את תצוגות הספרים.
    final firstChild = SplitPaneView.buildPane(
      widget.node.rightTab,
      EdgeInsetsDirectional.only(start: widget.thickness),
      widget.paneBuilder,
    );
    final secondChild = SplitPaneView.buildPane(
      widget.node.leftTab,
      EdgeInsetsDirectional.only(end: widget.thickness),
      widget.paneBuilder,
    );

    return ValueListenableBuilder<double>(
      valueListenable: _ratioNotifier,
      builder: (context, ratio, _) {
        // חלוקה ב-flex ולא ב-LayoutBuilder: בנייה בזמן layout בונה מחדש את כל
        // תת-העץ בכל שינוי גודל, והופכת מפתח כפול ל-assertion חסר פשר.
        final firstFlex = (ratio * _kFlexResolution).round().clamp(
          1,
          _kFlexResolution - 1,
        );

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: firstFlex, child: firstChild),
            _PaneDivider(
              thickness: widget.thickness,
              isTouch: widget.thickness == kPaneDividerThicknessTouch,
              ratio: ratio,
              increasedRatio: _ratioAfterNudge(towardFirst: false),
              decreasedRatio: _ratioAfterNudge(towardFirst: true),
              onDragStart: () => _dragging = true,
              onDragUpdate: _onDragUpdate,
              onDragEnd: _commit,
              onReset: _resetRatio,
              onNudge: (towardFirst) => _nudge(towardFirst: towardFirst),
            ),
            Expanded(flex: _kFlexResolution - firstFlex, child: secondChild),
          ],
        );
      },
    );
  }
}

/// רצועת המפריד: אזור התפיסה רחב מהקו הנראה, כדי שתפיסה בעכבר תהיה נוחה
/// בלי לעבות את החזות.
///
/// מצב ההדגשה נשמר כאן ולא בצומת: `setState` בצומת בונה מחדש את שתי חלוניות
/// הקריאה, וריחוף עכבר על המפריד היה מרנדר מחדש שני ספרים.
class _PaneDivider extends StatefulWidget {
  /// עובי רצועת התפיסה — רחבה יותר במגע.
  final double thickness;

  /// במגע בלבד: לחיצה ארוכה מאפסת. בעכבר היא הייתה חוטפת את הגרירה — מזהה
  /// הלחיצה הארוכה זוכה בזירה ודוחה את מזהי הגרירה.
  final bool isTouch;

  /// היחס הנוכחי, לדיווח לקורא מסך בלבד.
  final double ratio;

  /// היחסים שיושגו בהזזה אחת לכל כיוון — הערכים שקורא מסך יכריז.
  final double increasedRatio;
  final double decreasedRatio;

  final VoidCallback onDragStart;
  final ValueChanged<DragUpdateDetails> onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onReset;

  /// הזזה בהקשה על חץ; `true` = כיווץ החלונית הראשונה.
  final ValueChanged<bool> onNudge;

  const _PaneDivider({
    required this.thickness,
    required this.isTouch,
    required this.ratio,
    required this.increasedRatio,
    required this.decreasedRatio,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onReset,
    required this.onNudge,
  });

  @override
  State<_PaneDivider> createState() => _PaneDividerState();
}

class _PaneDividerState extends State<_PaneDivider> {
  bool _hovering = false;
  bool _dragging = false;
  bool _focused = false;

  /// node מפורש כדי שההדגשה תשקף פוקוס מקלדת, ושהמפריד יהיה יעד ל-Tab.
  final FocusNode _focusNode = FocusNode(debugLabel: 'מפריד חלוניות');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _setDragging(bool value) {
    if (_dragging != value) setState(() => _dragging = value);
  }

  static String _percent(double ratio) =>
      '${(ratio.clamp(0.0, 1.0) * 100).round()}%';

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final active = _hovering || _dragging || _focused;

    void handleDragStart(DragStartDetails _) {
      _setDragging(true);
      // אחרי גרירה בעכבר החצים ממשיכים לכוון את אותו מפריד, בלי לחפש אותו
      // מחדש ב-Tab.
      _focusNode.requestFocus();
      widget.onDragStart();
    }

    void handleDragEnd(DragEndDetails _) {
      _setDragging(false);
      widget.onDragEnd();
    }

    // ב-RTL חץ שמאלה מזיז את המפריד שמאלה, כלומר מגדיל את החלונית הראשונה
    // (הימנית) — בדיוק כמו גרירה.
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Focus(
        focusNode: _focusNode,
        // הסמנטיקה מוגדרת במלואה למטה; בלי זה ה-Focus היה מוסיף צומת עוטף
        // ודגלי הפוקוס היו נדבקים לו במקום למחוון עצמו.
        includeSemantics: false,
        onFocusChange: (value) => setState(() => _focused = value),
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
            return KeyEventResult.ignored;
          }
          // קיצור עם מקש הצירוף שייך למסך ולא למפריד (למשל Alt+חץ = הקטע הבא).
          final keyboard = HardwareKeyboard.instance;
          if (keyboard.isAltPressed ||
              keyboard.isControlPressed ||
              keyboard.isMetaPressed) {
            return KeyEventResult.ignored;
          }
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowLeft) {
            widget.onNudge(!isRtl);
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowRight) {
            widget.onNudge(isRtl);
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.home) {
            widget.onReset();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTap: widget.onReset,
          // רק במגע: בעכבר מזהה הלחיצה הארוכה זוכה בזירה ודוחה את הגרירה, כך
          // שהיסוס של חצי שנייה על הרצועה היה מאפס את היחס והורג את הגרירה.
          onLongPress: widget.isTouch ? widget.onReset : null,
          onHorizontalDragStart: handleDragStart,
          onHorizontalDragUpdate: widget.onDragUpdate,
          onHorizontalDragEnd: handleDragEnd,
          child: Semantics(
            container: true,
            slider: true,
            focusable: true,
            focused: _focused,
            value: _percent(widget.ratio),
            increasedValue: _percent(widget.increasedRatio),
            decreasedValue: _percent(widget.decreasedRatio),
            label: 'מפריד בין חלוניות — גרירה או חצים לצדדים, Home לאיפוס',
            onIncrease: () => widget.onNudge(false),
            onDecrease: () => widget.onNudge(true),
            child: SizedBox(
              width: widget.thickness,
              child: Center(
                // ידית קצרה במרכז ולא קו לכל האורך: במנוחה הרווח שבין
                // הכרטיסים הוא ההפרדה, והידית מופיעה רק כשמכוונים אליה.
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOut,
                  opacity: active ? 1 : 0,
                  child: SizedBox(
                    width: _kDividerHandleThickness,
                    height: _kDividerHandleLength,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppSurfaces.paneDividerHandle(
                          colorScheme,
                          isActive: active,
                        ),
                        borderRadius: BorderRadius.circular(
                          _kDividerHandleThickness / 2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
