import 'dart:math';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

class ScrollablePositionedListScrollbar extends StatefulWidget {
  final ItemScrollController scrollController;
  final ItemPositionsListener itemPositionsListener;
  final int itemCount;
  final Widget child;

  const ScrollablePositionedListScrollbar({
    super.key,
    required this.scrollController,
    required this.itemPositionsListener,
    required this.itemCount,
    required this.child,
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
    super.dispose();
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
    final newPosition =
        (minIndex / maxScrollableIndex).clamp(0.0, 1.0 - newHeight);

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
  void _jumpToTrackPosition(double localDy, double trackHeight) {
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
  }

  void _onDragUpdate(double delta, double trackHeight) {
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
  }

  void _onDragEnd() {
    setState(() {
      _isDragging = false;
    });
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

                return GestureDetector(
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
                      _jumpToTrackPosition(dy, trackHeight);
                    }
                  },
                  onVerticalDragUpdate: (details) {
                    _onDragUpdate(details.delta.dy / trackHeight, trackHeight);
                  },
                  onVerticalDragEnd: (_) => _onDragEnd(),
                  // קפיצה רק כשהלחיצה על המסילה. לחיצה על האגודל עצמו נורית גם
                  // כשהמחווה הופכת מיד לגרירה — קפיצה כאן הייתה ממקמת אותו מחדש
                  // סביב הסמן ומקפיצה את הרשימה לפני שהגרירה התחילה.
                  onTapDown: (details) {
                    final dy = details.localPosition.dy;
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
                            color: _isDragging
                                ? colorScheme.primary.withValues(alpha: 0.8)
                                : colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ],
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
