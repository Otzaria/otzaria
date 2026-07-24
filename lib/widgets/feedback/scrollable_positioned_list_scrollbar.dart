import 'dart:math';
import 'package:otzaria/theme/app_tokens.dart';
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

  // גובהי הפריטים שנמדדו (אינדקס → גובה ביחידות מסך). ממוצע גלובלי עליהם נותן
  // אומדן תוכן יציב, במקום ממוצע מקומי מתנודד על הגלויים כרגע.
  final Map<int, double> _itemHeights = {};
  double _itemHeightSum = 0.0;

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
    widget.itemPositionsListener.itemPositions.addListener(
      _updateScrollPosition,
    );
  }

  @override
  void didUpdateWidget(covariant ScrollablePositionedListScrollbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // החלפת ספר (itemCount/listener/scrollController) מייתרת את הגבהים הישנים.
    // שני ספרים עלולים לחלוק itemCount, ולכן בודקים גם את ה-scrollController.
    if (oldWidget.itemCount != widget.itemCount ||
        oldWidget.itemPositionsListener != widget.itemPositionsListener ||
        oldWidget.scrollController != widget.scrollController) {
      _itemHeights.clear();
      _itemHeightSum = 0.0;
    }
    if (oldWidget.itemPositionsListener != widget.itemPositionsListener) {
      oldWidget.itemPositionsListener.itemPositions.removeListener(
        _updateScrollPosition,
      );
      widget.itemPositionsListener.itemPositions.addListener(
        _updateScrollPosition,
      );
    }
  }

  @override
  void dispose() {
    widget.itemPositionsListener.itemPositions.removeListener(
      _updateScrollPosition,
    );
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
    final thumbPos = (clickPosition - (_thumbHeight / 2)).clamp(
      0.0,
      1.0 - _thumbHeight,
    );
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
    double trailingAtMin = positions.first.itemTrailingEdge;
    double trailingAtMax = positions.first.itemTrailingEdge;

    for (var position in positions) {
      if (position.index < minIndex) {
        minIndex = position.index;
        leadingAtMin = position.itemLeadingEdge;
        trailingAtMin = position.itemTrailingEdge;
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

    // גובה פריט קבוע תחת גלילה; אם פריט שכבר נמדד מופיע בגובה שונה, ה-layout
    // השתנה (גופן/גודל viewport/מפרשים/split) וכל היחסים השמורים אינם תקפים.
    final layoutChanged = positions.any((position) {
      final cached = _itemHeights[position.index];
      if (cached == null) return false;
      final height = position.itemTrailingEdge - position.itemLeadingEdge;
      return height > 0 && (cached - height).abs() > cached * 0.02;
    });
    if (layoutChanged) {
      _itemHeights.clear();
      _itemHeightSum = 0.0;
    }

    // צבירת גבהים לממוצע גלובלי. max(0) מגן מפני סחיפת נקודה-צפה לשלילי זעיר.
    for (final position in positions) {
      final height = position.itemTrailingEdge - position.itemLeadingEdge;
      if (height > 0) {
        _itemHeightSum = max(
          0.0,
          _itemHeightSum + height - (_itemHeights[position.index] ?? 0.0),
        );
        _itemHeights[position.index] = height;
      }
    }

    final visibleItems = maxIndex - minIndex + 1;

    // גובה האגודל = יחס התוכן הנראה לכלל, לפי ממוצע גלובלי יציב. ה-fallback
    // מגן רק מפני 0/0 במקרה המנוון שאף פריט לא נמדד (כל הגבהים ≤ 0).
    final visibleSpan = trailingAtMax - leadingAtMin;
    final avgItemHeight = _itemHeights.isNotEmpty
        ? _itemHeightSum / _itemHeights.length
        : (visibleItems > 0 ? visibleSpan / visibleItems : 0.0);
    final totalContent = avgItemHeight * widget.itemCount;
    final newHeight = totalContent > 0
        ? (1.0 / totalContent).clamp(0.05, 1.0)
        : 1.0;

    // minIndex לבדו זז בקפיצות של פריט שלם והאגודל "לא מחליק". מוסיפים את
    // החלק של הפריט העליון שכבר נגלל מעבר לקצה (-leadingAtMin חלקי גובהו)
    // כדי שהאגודל יחליק חלק בין אינדקסים סמוכים.
    final topItemHeight = trailingAtMin - leadingAtMin;
    final fractionIntoTop = topItemHeight > 0
        ? (-leadingAtMin / topItemHeight).clamp(0.0, 1.0)
        : 0.0;
    final continuousIndex = minIndex + fractionIntoTop;

    final maxScrollableIndex = max(widget.itemCount - visibleItems, 1);
    // הכפלה ב-(1 - newHeight) שומרת עקביות עם המיפוי ההפוך
    // ב-_indexFromThumbPosition (שמחלק ב-(1 - _thumbHeight)); בלעדיה האגודל
    // "ירד" אחרי קפיצה ליעד, בעוצמה שגדלה ככל שמתקדמים בספר.
    final newPosition =
        ((continuousIndex / maxScrollableIndex) * (1.0 - newHeight)).clamp(
          0.0,
          1.0 - newHeight,
        );

    // כל התוכן נראה אם הפריט הראשון מתחיל בתוך המסך, האחרון מסתיים בתוכו,
    // וכל הפריטים בטווח הזה מיוצגים — במצב כזה אין מה לגלול ואין טעם
    // להציג את הפס.
    final allVisible =
        minIndex == 0 &&
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
  void _jumpToTrackPosition(
    double localDy,
    double trackHeight, [
    Offset? globalPosition,
  ]) {
    if (trackHeight <= 0) return;
    final clickPosition = localDy / trackHeight;
    final newThumbPos = (clickPosition - (_thumbHeight / 2)).clamp(
      0.0,
      1.0 - _thumbHeight,
    );
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

  void _onDragUpdate(
    double delta,
    double trackHeight, [
    Offset? globalPosition,
  ]) {
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
    // עדכון סופי דחוי לframe הבא: itemPositions.value מתעדכן רק אחרי שה-list
    // מרנדר את מיקום הקפיצה; קריאה סינכרונית מחזירה ערך ישן וגורמת לחזרת האגודל.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateScrollPosition();
    });
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
                            event.localPosition.dy,
                            trackHeight,
                          );
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
                          dy,
                          trackHeight,
                          details.globalPosition,
                        );
                      }
                    },
                    onVerticalDragUpdate: (details) {
                      _onDragUpdate(
                        details.delta.dy / trackHeight,
                        trackHeight,
                        details.globalPosition,
                      );
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
                              color: AppSurfaces.scrollbarThumb(
                                colorScheme,
                                isDragging: _isDragging,
                              ),
                              borderRadius: AppTokens.borderRadiusAll,
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
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),
            child: widget.child,
          ),
        ),
      ],
    );
  }
}
