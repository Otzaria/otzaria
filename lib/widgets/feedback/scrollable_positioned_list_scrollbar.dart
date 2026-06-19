import 'dart:math';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/widgets/feedback/scrollbar_target_label.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

class ScrollablePositionedListScrollbar extends StatefulWidget {
  final ItemScrollController scrollController;
  final ItemPositionsListener itemPositionsListener;
  final int itemCount;
  final Widget child;

  /// מחזירה את כתובת היעד עבור אינדקס פריט נתון (אותו אינדקס שאליו הסרגל
  /// קופץ). כשהיא מסופקת, ריחוף/גרירה על הסרגל מציגים תווית צפה עם הכתובת
  /// שמוחזרת; כשהיא null התווית מושבתת והסרגל מתנהג כמקודם. הקריאה מתבצעת
  /// רק כשהאינדקס שמתחת לסמן משתנה, ולכן מותר שתבצע חישוב קל (כמו מיפוי
  /// אינדקס→תוכן עניינים).
  final String Function(int index)? labelForIndex;

  const ScrollablePositionedListScrollbar({
    super.key,
    required this.scrollController,
    required this.itemPositionsListener,
    required this.itemCount,
    required this.child,
    this.labelForIndex,
  });

  @override
  State<ScrollablePositionedListScrollbar> createState() =>
      _ScrollablePositionedListScrollbarState();
}

class _ScrollablePositionedListScrollbarState
    extends State<ScrollablePositionedListScrollbar> {
  static const double _trackWidth = 12.0;

  double _thumbPosition = 0.0;
  double _thumbHeight = 0.1; // יחס גובה ברירת מחדל
  bool _isDragging = false;
  // ברירת מחדל false כדי שלא נציג את ה-track בספרים קטנים שכל תוכנם נכנס במסך.
  // יתעדכן ל-true ברגע שה-positions מראים שיש פריט מחוץ למסך.
  bool _canScroll = false;
  // האינדקס המקסימלי שאפשר לקפוץ אליו (itemCount - visibleItems) — נשמר כדי
  // שמיפוי הגרירה לאינדקס יישאר עקבי גם כש-_thumbHeight מקובל למינימום
  // 0.05. בלי זה, כשמפרש פתוח מתחת ומעט סגמנטים גלויים, הגרירה לתחתית לא
  // הגיעה לסוף הספר.
  int _maxScrollableIndex = 1;

  // להחלקת הקפיצות במיקום
  int _lastFirstIndex = 0;

  // תווית היעד הצפה (כתובת המקום שאליו נקפוץ בלחיצה). מבודדת מעץ הסרגל דרך
  // Overlay כדי שלא תגרום ל-rebuild של הרשימה. _labelIndex/_labelText
  // ממזערים חישוב: refFromTocList רץ רק כשהאינדקס שמתחתיו העכבר משתנה.
  final ScrollbarTargetLabelController _labelController =
      ScrollbarTargetLabelController();
  int? _labelIndex;
  String? _labelText;

  @override
  void initState() {
    super.initState();
    widget.itemPositionsListener.itemPositions
        .addListener(_updateScrollPosition);
  }

  @override
  void didUpdateWidget(covariant ScrollablePositionedListScrollbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemPositionsListener != widget.itemPositionsListener) {
      oldWidget.itemPositionsListener.itemPositions
          .removeListener(_updateScrollPosition);
      widget.itemPositionsListener.itemPositions
          .addListener(_updateScrollPosition);
    }
  }

  @override
  void dispose() {
    widget.itemPositionsListener.itemPositions
        .removeListener(_updateScrollPosition);
    _labelController.dispose();
    super.dispose();
  }

  /// האם להציג בכלל את תווית היעד (סופקה פונקציית מיפוי).
  bool get _labelEnabled => widget.labelForIndex != null;

  /// בעברית הסרגל יושב בקצה ימין של אזור הקריאה, ולכן התווית נפתחת שמאלה
  /// (לתוך התוכן); ב-LTR להפך.
  ScrollbarLabelSide get _labelSide =>
      Directionality.of(context) == TextDirection.rtl
          ? ScrollbarLabelSide.left
          : ScrollbarLabelSide.right;

  /// מציג/מעדכן את תווית היעד עבור [index]. מחשב את הכתובת רק כשהאינדקס
  /// השתנה, ותמיד מעדכן את מיקום העוגן ([globalPosition]) כדי שהתווית תעקוב
  /// אחרי הסמן בצורה חלקה.
  void _showLabelForIndex(int index, Offset globalPosition) {
    if (!_labelEnabled) return;
    if (index != _labelIndex) {
      _labelIndex = index;
      _labelText = widget.labelForIndex!(index);
    }
    _labelController.show(
      context,
      anchor: globalPosition,
      text: _labelText ?? '',
      side: _labelSide,
    );
  }

  void _hideLabel() {
    _labelIndex = null;
    _labelText = null;
    _labelController.hide();
  }

  /// ממפה מיקום אנכי על המסילה לאינדקס היעד — בדיוק כמו חישוב הקפיצה
  /// ב-[_jumpToTrackPosition], כדי שהתווית תציג את היעד האמיתי של לחיצה.
  int _indexFromTrackDy(double localDy, double trackHeight) {
    if (trackHeight <= 0) return 0;
    final clickPosition = localDy / trackHeight;
    final thumbPos =
        (clickPosition - (_thumbHeight / 2)).clamp(0.0, 1.0 - _thumbHeight);
    return _indexFromThumbPosition(thumbPos);
  }

  void _updateScrollPosition() {
    if (!mounted) return;

    final positions = widget.itemPositionsListener.itemPositions.value;
    if (positions.isEmpty || widget.itemCount == 0) return;

    // מציאת האינדקסים הראשונים והאחרונים הנראים, יחד עם הקצוות שלהם —
    // הקצוות נחוצים כדי להחליט אם באמת יש מה לגלול (ראה חישוב _canScroll
    // בהמשך הפונקציה).
    int minIndex = positions.first.index;
    int maxIndex = positions.first.index;
    double leadingAtMin = positions.first.itemLeadingEdge;
    double trailingAtMax = positions.first.itemTrailingEdge;

    for (var position in positions) {
      if (position.index < minIndex) {
        minIndex = position.index;
        leadingAtMin = position.itemLeadingEdge;
      }
      if (position.index > maxIndex) {
        maxIndex = position.index;
        trailingAtMax = position.itemTrailingEdge;
      }
    }

    // בזמן גרירה, _lastFirstIndex מנוהל בתוך _onDragUpdate על פי היעד שאליו
    // קפצנו. אסור לדרוס אותו פה לפי הפוזיציה הנוכחית של הרשימה אחרת קפיצות
    // הביניים יפסיקו כי "השינוי קטן מדי".
    if (!_isDragging) {
      _lastFirstIndex = minIndex;
    }

    // חישוב גובה הפס ביחס לכמות הפריטים
    // מוסיפים 1 כדי למנוע חילוק ב-0
    final visibleItems = (maxIndex - minIndex + 1);
    final proportion = visibleItems / max(widget.itemCount, 1);

    // גובה מינימלי בפיקסלים ל"אגודל" הגלילה הוא בדרך כלל סביב 40-50 פיקסלים במסכים רגילים
    // אבל כאן אנחנו עובדים באחוזים (0.0 עד 1.0)
    // נניח שגובה המסך הוא H, גובה מינימלי h_min. אחוז מינימלי הוא h_min/H
    // נניח באופן שמרני שרצוי לפחות 5%
    final newHeight = proportion.clamp(0.05, 1.0);

    // חישוב המיקום היחסי (0.0 למעלה, 1.0 למטה)
    // האינדקסים הם 0-based.
    // אם minIndex הוא 0 -> top 0.
    // אם maxIndex הוא itemCount-1 -> bottom 1.0 (בערך)

    final maxScrollableIndex = max(widget.itemCount - visibleItems, 1);
    // המיפוי ההפוך (אינדקס → מיקום אגודל) חייב להכפיל ב-(1 - newHeight) כדי
    // להיות עקבי עם המיפוי הקדים ב-_indexFromThumbPosition (שמחלק ב-
    // (1 - _thumbHeight)). בלי ההכפלה, אחרי לחיצה/גרירה שקפצה ליעד, העדכון
    // הזה דרס את מיקום האגודל לערך גבוה ב-1/(1-thumbHeight) — והאגודל "ירד"
    // ביחס למקום שנלחץ, בעוצמה שגדלה ככל שמתקדמים בספר.
    final newPosition = ((minIndex / maxScrollableIndex) * (1.0 - newHeight))
        .clamp(0.0, 1.0 - newHeight);

    // כל התוכן נראה אם הפריט הראשון מתחיל בתוך המסך, האחרון מסתיים בתוכו,
    // וכל הפריטים בטווח הזה מיוצגים — במצב כזה אין מה לגלול ואין טעם
    // להציג את הפס.
    final allVisible = minIndex == 0 &&
        maxIndex == widget.itemCount - 1 &&
        leadingAtMin >= 0 &&
        trailingAtMax <= 1.0;

    setState(() {
      _canScroll = !allVisible;
      // _maxScrollableIndex חייב להתעדכן גם תוך כדי גרירה: כשהמשתמש גורר
      // לתוך אזור עם פריטים גדולים יותר (לדוגמה — אזור שבו מפרש פתוח, או
      // כותרות עם הרבה תוכן) מספר הפריטים הגלויים יורד והאינדקס המקסימלי
      // שאליו אפשר לקפוץ עולה. בלי עדכון, שלב הגרירה הבא יחזיר אינדקס
      // יעד מבוסס על ערך ישן ולא יגיע לסוף הספר.
      _maxScrollableIndex = maxScrollableIndex;
      if (!_isDragging) {
        _thumbHeight = newHeight;
        _thumbPosition = newPosition;
      }
    });
  }

  // הופך את מיקום האגודל (0.0–(1.0 - _thumbHeight)) לאינדקס יעד בטווח
  // [0, _maxScrollableIndex]. שימוש ב-_maxScrollableIndex ולא ב-itemCount
  // מבטיח שגרירה לתחתית באמת מגיעה לסוף הספר גם כש-_thumbHeight מקובל
  // למינימום (לדוגמה כשמפרש פתוח מתחת ומעט סגמנטים גלויים).
  int _indexFromThumbPosition(double position) {
    final maxPosition = 1.0 - _thumbHeight;
    if (maxPosition <= 0) return 0;
    final ratio = (position / maxPosition).clamp(0.0, 1.0);
    return (ratio * _maxScrollableIndex).round();
  }

  /// בודק אם נקודה אנכית על המסילה נמצאת מחוץ לאגודל. רק נקודה כזו מצדיקה
  /// קפיצה מוחלטת; לחיצה/גרירה שמתחילה על האגודל עצמו נועדה לגרירה יחסית
  /// ואסור למרכז את האגודל מחדש סביב הסמן (זה היה מקפיץ את הרשימה).
  bool _isOutsideThumb(double localDy, double trackHeight) {
    final thumbTop = trackHeight * _thumbPosition;
    final thumbBottom = thumbTop + trackHeight * _thumbHeight;
    return localDy < thumbTop || localDy > thumbBottom;
  }

  /// קופץ למיקום מוחלט שנלחץ/נגרר על המסילה: ממרכז את האגודל סביב הנקודה
  /// ומבצע קפיצה של הרשימה ליעד המתאים. משותף ללחיצה (`onTapDown`) ולתחילת
  /// גרירה על המסילה (`onVerticalDragStart`), כדי שלחיצה שזוהתה כגרירה (כל
  /// מיקרו-תזוזה הופכת tap ל-drag) עדיין תקפוץ ליעד ולא רק תזוז מעט.
  void _jumpToTrackPosition(double localDy, double trackHeight,
      [Offset? globalPosition]) {
    if (trackHeight <= 0) return;
    final clickPosition = localDy / trackHeight;
    final newThumbPos =
        (clickPosition - (_thumbHeight / 2)).clamp(0.0, 1.0 - _thumbHeight);
    setState(() {
      _thumbPosition = newThumbPos;
    });
    final int targetIndex = _indexFromThumbPosition(_thumbPosition);
    _lastFirstIndex = targetIndex;
    widget.scrollController.jumpTo(index: targetIndex);
    if (globalPosition != null) {
      _showLabelForIndex(targetIndex, globalPosition);
    }
  }

  void _onDragUpdate(double delta, double trackHeight,
      [Offset? globalPosition]) {
    setState(() {
      _isDragging = true;
      _thumbPosition += delta;
      _thumbPosition = _thumbPosition.clamp(0.0, 1.0 - _thumbHeight);
    });

    final int targetIndex = _indexFromThumbPosition(_thumbPosition);

    // אופטימיזציה: לא לקפוץ אם השינוי קטן מדי כדי למנוע ריצוד
    if ((targetIndex - _lastFirstIndex).abs() > widget.itemCount * 0.001) {
      widget.scrollController.jumpTo(index: targetIndex);
      _lastFirstIndex = targetIndex;
    }

    if (globalPosition != null) {
      _showLabelForIndex(targetIndex, globalPosition);
    }
  }

  void _onDragEnd() {
    setState(() {
      _isDragging = false;
    });
    // התווית מוסתרת בתום הגרירה; ריחוף נוסף יחזיר אותה דרך ה-MouseRegion.
    _hideLabel();
    // עדכון סופי ליתר ביטחון
    _updateScrollPosition();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (widget.itemCount > 0 && _canScroll)
          SizedBox(
            width: _trackWidth,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final trackHeight = constraints.maxHeight;
                final thumbPixelHeight = trackHeight * _thumbHeight;
                final thumbPixelTop = trackHeight * _thumbPosition;
                final colorScheme = Theme.of(context).colorScheme;

                return MouseRegion(
                  // ריחוף סתמי מעל המסילה — תצוגה מקדימה של יעד הקפיצה. מחושב
                  // רק כשהעכבר זז, וה-show מחשב כתובת רק כשהאינדקס משתנה.
                  onHover: _labelEnabled
                      ? (event) {
                          final index = _indexFromTrackDy(
                              event.localPosition.dy, trackHeight);
                          _showLabelForIndex(index, event.position);
                        }
                      : null,
                  onExit: (_) {
                    // בזמן גרירה העכבר עלול לצאת מרוחב המסילה — אסור להסתיר אז.
                    if (_isDragging) return;
                    _hideLabel();
                  },
                  child: GestureDetector(
                    // opaque: מבטיח שהגרירה והלחיצה יתקבלו בכל שטח ה-track,
                    // לא רק מעל ה-thumb עצמו — ללא צורך ברקע צבעוני.
                    behavior: HitTestBehavior.opaque,
                    // down ולא start: מבטיח ש-onVerticalDragStart מקבל את נקודת
                    // המגע המקורית, כך שההבחנה בין גרירת אגודל לגרירת מסילה
                    // והקפיצה אליה מדויקות.
                    dragStartBehavior: DragStartBehavior.down,
                    onVerticalDragStart: (details) {
                      final dy = details.localPosition.dy;
                      setState(() {
                        _isDragging = true;
                      });
                      // גרירה שמתחילה מחוץ לאגודל (על המסילה) — קפיצה מיידית
                      // ליעד הנלחץ. כך גם לחיצה שזוהתה כגרירה זעירה מגיעה ליעד
                      // במקום רק להזיז את האגודל מעט. גרירת האגודל עצמו נשארת
                      // יחסית (onVerticalDragUpdate) כמקודם.
                      if (_isOutsideThumb(dy, trackHeight)) {
                        _jumpToTrackPosition(
                            dy, trackHeight, details.globalPosition);
                      }
                    },
                    onVerticalDragUpdate: (details) {
                      _onDragUpdate(details.delta.dy / trackHeight, trackHeight,
                          details.globalPosition);
                    },
                    onVerticalDragEnd: (_) => _onDragEnd(),
                    // גרירה שנקטעה (הרשימה ניצחה ב-gesture arena וגללה את
                    // התוכן) חייבת להסתיר את התווית — אחרת היא נשארת תקועה.
                    onVerticalDragCancel: _onDragEnd,
                    // קפיצה רק כשהלחיצה על המסילה. לחיצה על האגודל עצמו נורית גם
                    // כשהמחווה הופכת מיד לגרירה — קפיצה כאן הייתה ממקמת אותו מחדש
                    // סביב הסמן ומקפיצה את הרשימה לפני שהגרירה התחילה.
                    onTapDown: (details) {
                      final dy = details.localPosition.dy;
                      // לחיצה בודדת קופצת אך לא מציגה תווית: במסך מגע אין
                      // onExit שיסתיר אותה, והיא הייתה נשארת תקועה.
                      if (_isOutsideThumb(dy, trackHeight)) {
                        _jumpToTrackPosition(dy, trackHeight);
                      }
                    },
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // ה"אגודל" (Thumb) עצמו
                        Positioned(
                          top: thumbPixelTop,
                          left: 2, // רווח קטן מהקצה
                          right: 2,
                          height: thumbPixelHeight,
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppSurfaces.scrollbarThumb(colorScheme,
                                  isDragging: _isDragging),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        Expanded(
          child: ScrollConfiguration(
            behavior:
                ScrollConfiguration.of(context).copyWith(scrollbars: false),
            child: widget.child,
          ),
        ),
      ],
    );
  }
}
