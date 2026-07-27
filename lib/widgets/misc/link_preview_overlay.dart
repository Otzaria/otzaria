import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/misc/app_selection_area.dart';
import 'package:otzaria/widgets/misc/link_context_menu_entry.dart';
import 'package:otzaria/widgets/misc/overlay_scroll_anchor.dart';
import 'package:otzaria/widgets/smart_text/smart_text.dart';

/// חלונית צפה עם תצוגה מקדימה של מפרש, שנפתחת בריחוף או בלחיצה על עוגן-מילה,
/// או לצד פריט בתפריט הקשר ([showBesideMenuItem]).
///
/// ממוקמת ליד נקודת הריחוף/הלחיצה, מוגבלת ברוחב ובגובה (4 שורות), נסגרת כשהסמן
/// עוזב אותה או בהקשה מחוצה לה — ונשארת פתוחה כשהסמן נכנס לתוכה (לסימון
/// והעתקה). לחיצה בתוך החלונית מקבעת אותה: היא נשארת פתוחה גם כשהסמן יוצא,
/// עד הקשה במקום אחר בדף, וזזה יחד עם גלילת התוכן שעליו נפתחה.
/// לחיצה על הכותרת פותחת את היעד. מוצגת חלונית אחת בכל רגע.
class LinkPreviewOverlay {
  LinkPreviewOverlay._();

  static OverlayEntry? _entry;
  static Object? _token;
  static VoidCallback? _onDismissed;
  static _LinkPreviewPanelState? _activePanel;

  /// מקפיצה תצוגה מקדימה של [link] ליד [globalPosition]. סוגרת חלונית קודמת.
  /// [onDismissed] נקרא כשהחלונית נסגרת (גם בהחלפה בחלונית אחרת).
  /// [onOpen] — לחיצה על כותרת החלונית (פתיחת היעד); הסגירה באחריות הקורא.
  /// [hoverMode] — חלונית שנפתחה מריחוף: בלי מחסום-הקשות מאחוריה (שלא תחסום
  /// את הלחיצה הבאה), והסגירה מתוזמנת דרך [scheduleHide] כשהסמן עוזב את העוגן.
  static void show(
    BuildContext context, {
    required Link link,
    required Offset globalPosition,
    VoidCallback? onDismissed,
    VoidCallback? onOpen,
    bool hoverMode = false,
    bool? removeNikud,
    bool? removePunctuation,
  }) {
    _show(
      context,
      contentBuilder: (context) => LinkHoverPreviewContent(
        link: link,
        maxContentLines: 4,
        compact: true,
        onOpen: onOpen,
        removeNikud: removeNikud,
        removePunctuation: removePunctuation,
      ),
      anchorPosition: globalPosition,
      onDismissed: onDismissed,
      hoverMode: hoverMode,
    );
  }

  /// מציגה תוכן כללי באותה חלונית המשמשת תצוגות מקדימות של קישורים.
  static void showContent(
    BuildContext context, {
    required WidgetBuilder contentBuilder,
    required Offset globalPosition,
    VoidCallback? onDismissed,
    bool hoverMode = false,
  }) {
    _show(
      context,
      contentBuilder: contentBuilder,
      anchorPosition: globalPosition,
      onDismissed: onDismissed,
      hoverMode: hoverMode,
    );
  }

  /// מציגה תצוגה מקדימה צמודה לפריט תפריט שמלבנו הגלובלי [itemGlobalRect].
  ///
  /// לחיצה בתוך החלונית מקבעת אותה במקום — אותו עץ widgets, בלי בנייה מחדש —
  /// ומפעילה את [onPinned] (סגירת התפריט שמתחת). כך גרירה לסימון טקסט אינה
  /// נקטעת. [touchTriggered] — נפתחה בלחיצה ארוכה במגע: מחסום סוגר מאחוריה,
  /// שגם חוסם את התפריט שמתחת כדי שיישאר פתוח. [scrollAnchor] — עוגן בדף
  /// שהחלונית המקובעת תזוז איתו בגלילה. מחזירה מזהה חלונית ל[dismiss] ממוקד.
  static Object? showBesideMenuItem(
    BuildContext context, {
    required WidgetBuilder contentBuilder,
    required Rect itemGlobalRect,
    required double minWidth,
    bool touchTriggered = false,
    OverlayScrollAnchor? scrollAnchor,
    VoidCallback? onPinned,
    VoidCallback? onDismissed,
  }) {
    return _show(
      context,
      contentBuilder: contentBuilder,
      anchorPosition: itemGlobalRect.topLeft,
      anchorRect: itemGlobalRect,
      style: _PanelStyle.besideMenuItem(minWidth: minWidth),
      onDismissed: onDismissed,
      onPinned: onPinned,
      hoverMode: !touchTriggered,
      barrierBlocksBelow: touchTriggered,
      scrollAnchor: scrollAnchor,
      scrollOnPinOnly: true,
      // הנקודה מכוסה בתפריט הפתוח — לכידה כאן הייתה עוגנת בתפריט עצמו.
      captureScrollAnchor: false,
    );
  }

  static Object? _show(
    BuildContext context, {
    required WidgetBuilder contentBuilder,
    required Offset anchorPosition,
    Rect? anchorRect,
    _PanelStyle style = const _PanelStyle.floating(),
    VoidCallback? onDismissed,
    VoidCallback? onPinned,
    bool hoverMode = false,
    bool barrierBlocksBelow = false,
    OverlayScrollAnchor? scrollAnchor,
    bool scrollOnPinOnly = false,
    bool captureScrollAnchor = true,
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return null;
    // חלונית מקובעת נסגרת רק בלחיצה — ריחוף על עוגן אחר לא מחליף אותה.
    if (hoverMode && (_activePanel?._pinned ?? false)) return null;
    dismiss();
    // לכידת עוגן הגלילה חייבת להקדים את הוספת החלונית ל-overlay, אחרת
    // ה-hit-test יפגע בחלונית עצמה במקום בשורת הטקסט שמתחתיה.
    final anchor = captureScrollAnchor
        ? (scrollAnchor ?? OverlayScrollAnchor.capture(context, anchorPosition))
        : scrollAnchor;
    final token = Object();
    _token = token;
    _onDismissed = onDismissed;
    _entry = OverlayEntry(
      builder: (_) => _LinkPreviewPanel(
        contentBuilder: contentBuilder,
        anchorPosition: anchorPosition,
        anchorRect: anchorRect,
        style: style,
        onDismiss: dismiss,
        onPinned: onPinned,
        hoverMode: hoverMode,
        barrierBlocksBelow: barrierBlocksBelow,
        scrollAnchor: anchor,
        scrollOnPinOnly: scrollOnPinOnly,
      ),
    );
    overlay.insert(_entry!);
    return token;
  }

  /// האם [token] הוא של החלונית המוצגת כרגע. `null` — כל חלונית שתהיה.
  static bool _isActive(Object? token) =>
      token == null || identical(_token, token);

  /// מתזמנת סגירה קרובה (הסמן עזב את העוגן). כניסת הסמן לחלונית מבטלת אותה.
  static void scheduleHide([Object? token]) {
    if (!_isActive(token)) return;
    _activePanel?._scheduleHide();
  }

  /// מבטלת סגירה מתוזמנת (הסמן חזר לעוגן בזמן שהחלונית פתוחה).
  static void cancelScheduledHide([Object? token]) {
    if (!_isActive(token)) return;
    _activePanel?._cancelHide();
  }

  /// סוגרת את החלונית. [token] — סוגר רק אם היא עדיין המוצגת (ולא הוחלפה).
  static void dismiss({Object? token}) {
    if (!_isActive(token)) return;
    _entry?.remove();
    _entry = null;
    _token = null;
    final onDismissed = _onDismissed;
    _onDismissed = null;
    onDismissed?.call();
  }
}

/// עיצוב ומידות של חלונית התצוגה המקדימה: חלונית צפה ליד מילה, או חלונית
/// צמודה לפריט בתפריט הקשר — בגוון התפריט ועם מסגרת, כהמשך שלו.
class _PanelStyle {
  const _PanelStyle.floating()
    : maxWidth = 420,
      maxHeight = null,
      minWidth = 0,
      elevation = 8,
      anchorGap = 10,
      padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      _inMenu = false;

  const _PanelStyle.besideMenuItem({required this.minWidth})
    : maxWidth = 380,
      maxHeight = 360,
      elevation = 6,
      anchorGap = 6,
      padding = const EdgeInsets.all(12),
      _inMenu = true;

  final double maxWidth;

  /// `null` — גובה חופשי (התוכן עצמו מגביל את עצמו); אחרת גלילה פנימית.
  final double? maxHeight;
  final double minWidth;
  final double elevation;
  final double anchorGap;
  final EdgeInsets padding;
  final bool _inMenu;

  Color color(ColorScheme colorScheme) =>
      _inMenu ? colorScheme.surfaceContainer : colorScheme.surface;

  ShapeBorder shape(ColorScheme colorScheme) => RoundedRectangleBorder(
    borderRadius: AppTokens.borderRadiusAll,
    side: _inMenu
        ? BorderSide(color: colorScheme.outlineVariant)
        : BorderSide.none,
  );
}

/// תוכן תצוגה מקדימה להערה המוטמעת בגוף הספר.
class InlineBookNotePreviewContent extends StatelessWidget {
  final String content;
  final bool removeNikud;
  final bool removePunctuation;

  const InlineBookNotePreviewContent({
    super.key,
    required this.content,
    required this.removeNikud,
    required this.removePunctuation,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, settings) => ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 220),
        child: SingleChildScrollView(
          child: SmartTextWidget(
            text: content,
            settings: RenderSettings(
              removeNikud: removeNikud,
              removePunctuation: removePunctuation,
              removeTeamim: !settings.showTeamim,
              replaceHolyNames: settings.replaceHolyNames,
              fontSize: settings.commentatorsFontSize,
              fontFamily: settings.commentatorsFontFamily,
              fontWeight: settings.commentatorsFontBold
                  ? FontWeight.bold
                  : null,
              lineHeight: settings.lineHeight,
            ),
          ),
        ),
      ),
    );
  }
}

class _LinkPreviewPanel extends StatefulWidget {
  final WidgetBuilder contentBuilder;
  final Offset anchorPosition;

  /// כשמסופק — החלונית מוצבת לצד המלבן (פריט תפריט) ולא ליד נקודה.
  final Rect? anchorRect;
  final _PanelStyle style;
  final VoidCallback onDismiss;
  final VoidCallback? onPinned;
  final bool hoverMode;

  /// מחסום הסגירה חוסם גם את מה שמתחתיו (תפריט פתוח), כדי שהקשה מחוץ
  /// לחלונית תסגור רק אותה.
  final bool barrierBlocksBelow;
  final OverlayScrollAnchor? scrollAnchor;

  /// בתצוגה שצמודה לתפריט העוגן נדרש רק לאחר קיבוע: התפריט עצמו קבוע
  /// במקומו בזמן הריחוף.
  final bool scrollOnPinOnly;

  const _LinkPreviewPanel({
    required this.contentBuilder,
    required this.anchorPosition,
    required this.onDismiss,
    this.anchorRect,
    this.style = const _PanelStyle.floating(),
    this.onPinned,
    this.hoverMode = false,
    this.barrierBlocksBelow = false,
    this.scrollAnchor,
    this.scrollOnPinOnly = false,
  });

  @override
  State<_LinkPreviewPanel> createState() => _LinkPreviewPanelState();
}

class _LinkPreviewPanelState extends State<_LinkPreviewPanel> {
  static const double _screenPadding = 8;
  static const Duration _hideDelay = Duration(milliseconds: 250);

  final GlobalKey _panelKey = GlobalKey();
  Offset _offset = const Offset(_screenPadding, _screenPadding);
  bool _visible = false;
  Timer? _hideTimer;
  bool _pinned = false;

  /// מיקום העוגן בזמן הפתיחה — הפרש ממנו בזמן גלילה מזיז את החלונית.
  Offset? _anchorBaseline;
  Offset _scrollDelta = Offset.zero;
  bool _scrollUpdateScheduled = false;
  bool _tracksScroll = false;

  @override
  void initState() {
    super.initState();
    LinkPreviewOverlay._activePanel = this;
    if (!widget.scrollOnPinOnly) _startTrackingScroll();
    // מיקום דו-שלבי: בנייה סמויה למדידת הגודל, ואז הצמדה לנקודת הלחיצה.
    WidgetsBinding.instance.addPostFrameCallback((_) => _reposition());
  }

  @override
  void dispose() {
    if (identical(LinkPreviewOverlay._activePanel, this)) {
      LinkPreviewOverlay._activePanel = null;
    }
    if (_tracksScroll) widget.scrollAnchor?.removeListener(_onScrollChanged);
    _hideTimer?.cancel();
    super.dispose();
  }

  /// הודעת גלילה מגיעה בזמן layout — העדכון נדחה לסוף הפריים, שם המיקומים
  /// כבר סופיים ומותר לעדכן את ה-overlay.
  void _onScrollChanged() {
    if (_scrollUpdateScheduled) return;
    _scrollUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollUpdateScheduled = false;
      if (!mounted) return;
      final baseline = _anchorBaseline;
      if (baseline == null) return;
      final current = widget.scrollAnchor?.currentGlobalPosition();
      if (current == null) {
        // השורה שהחלונית עוגנה אליה כבר אינה חיה (נגללה רחוק) — סוגרים.
        widget.onDismiss();
        return;
      }
      final delta = current - baseline;
      if (delta != _scrollDelta) {
        setState(() => _scrollDelta = delta);
      }
    });
  }

  void _cancelHide() {
    _hideTimer?.cancel();
    _hideTimer = null;
  }

  void _scheduleHide() {
    if (_pinned) return;
    _hideTimer?.cancel();
    _hideTimer = Timer(_hideDelay, widget.onDismiss);
  }

  void _startTrackingScroll() {
    if (_tracksScroll) return;
    _tracksScroll = true;
    _anchorBaseline = widget.scrollAnchor?.currentGlobalPosition();
    widget.scrollAnchor?.addListener(_onScrollChanged);
  }

  /// לחיצה בתוך החלונית מקבעת אותה — נשארת עד הקשה במקום אחר בדף.
  void _pin() {
    _cancelHide();
    if (_pinned) return;
    setState(() => _pinned = true);
    _startTrackingScroll();
    widget.onPinned?.call();
  }

  static double _maxOffset(double available, double extent) =>
      (available - extent - _screenPadding)
          .clamp(_screenPadding, double.infinity)
          .toDouble();

  void _reposition() {
    final panelBox = _panelKey.currentContext?.findRenderObject();
    final overlayBox = Overlay.maybeOf(
      context,
      rootOverlay: true,
    )?.context.findRenderObject();
    if (panelBox is! RenderBox ||
        !panelBox.hasSize ||
        overlayBox is! RenderBox ||
        !overlayBox.hasSize) {
      return;
    }
    final panelSize = panelBox.size;
    final overlaySize = overlayBox.size;
    final anchorRect = widget.anchorRect;

    setState(() {
      _offset = anchorRect != null
          ? _offsetBesideRect(
              overlayBox.globalToLocal(anchorRect.topLeft) & anchorRect.size,
              panelSize,
              overlaySize,
            )
          : _offsetNearPoint(
              overlayBox.globalToLocal(widget.anchorPosition),
              panelSize,
              overlaySize,
            );
      _visible = true;
    });
  }

  Offset _offsetNearPoint(Offset anchor, Size panelSize, Size overlaySize) {
    final gap = widget.style.anchorGap;
    // אנכית: מתחת לנקודה, ואם אין מקום — מעליה.
    double top = anchor.dy + gap;
    if (top + panelSize.height > overlaySize.height - _screenPadding) {
      top = anchor.dy - gap - panelSize.height;
    }
    // אופקית (RTL): הצמדת קצה ימני לנקודה, ואז חיתוך לגבולות המסך.
    final left = anchor.dx - panelSize.width;
    return Offset(
      left.clamp(
        _screenPadding,
        _maxOffset(overlaySize.width, panelSize.width),
      ),
      top.clamp(
        _screenPadding,
        _maxOffset(overlaySize.height, panelSize.height),
      ),
    );
  }

  Offset _offsetBesideRect(Rect itemRect, Size panelSize, Size overlaySize) {
    final gap = widget.style.anchorGap;
    // העדפת צד: שמאלית לפריט (המשך כיוון הפתיחה הטבעי ב-RTL), אחרת ימינה,
    // ואם אין מקום מלא באף צד — הצמדה לקצה המסך בצד המרווח יותר.
    final leftCandidate = itemRect.left - gap - panelSize.width;
    final rightCandidate = itemRect.right + gap;
    final double dx;
    if (leftCandidate >= _screenPadding) {
      dx = leftCandidate;
    } else if (rightCandidate + panelSize.width <=
        overlaySize.width - _screenPadding) {
      dx = rightCandidate;
    } else {
      final spaceLeft = itemRect.left;
      final spaceRight = overlaySize.width - itemRect.right;
      dx = spaceLeft > spaceRight
          ? _screenPadding
          : _maxOffset(overlaySize.width, panelSize.width);
    }
    return Offset(
      dx,
      itemRect.top.clamp(
        _screenPadding,
        _maxOffset(overlaySize.height, panelSize.height),
      ),
    );
  }

  Widget _buildPanelChild(double maxWidth, double maxHeight) {
    final style = widget.style;
    final content = Padding(
      padding: style.padding,
      child: AppSelectionArea(child: Builder(builder: widget.contentBuilder)),
    );
    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: style.minWidth.clamp(0.0, maxWidth),
        maxWidth: maxWidth,
        maxHeight: maxHeight,
      ),
      child: maxHeight.isFinite
          ? SingleChildScrollView(child: content)
          : content,
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final screenSize = MediaQuery.of(context).size;
    final maxWidth = (screenSize.width - _screenPadding * 2)
        .clamp(0.0, style.maxWidth)
        .toDouble();
    final styleMaxHeight = style.maxHeight;
    final maxHeight = styleMaxHeight == null
        ? double.infinity
        : (screenSize.height - _screenPadding * 2)
              .clamp(0.0, styleMaxHeight)
              .toDouble();
    final colorScheme = Theme.of(context).colorScheme;
    final position = _offset + _scrollDelta;

    return Stack(
      children: [
        // מחסום שקוף — הקשה מחוץ לחלונית סוגרת (גם במגע, שאין בו onExit).
        // בריחוף אין מחסום עד לקיבוע: הוא היה בולע את הלחיצה הבאה; הסגירה
        // נעשית ביציאת הסמן מהעוגן/מהחלונית (scheduleHide).
        if (!widget.hoverMode || _pinned)
          Positioned.fill(
            child: GestureDetector(
              behavior: widget.barrierBlocksBelow && !_pinned
                  ? HitTestBehavior.opaque
                  : HitTestBehavior.translucent,
              onTap: widget.onDismiss,
              onSecondaryTapDown: (_) => widget.onDismiss(),
            ),
          ),
        Positioned(
          left: position.dx,
          top: position.dy,
          // בזמן המדידה הראשונית (טרם _visible) החלונית יושבת בפינה ב-hit-test
          // ומכסה את נקודת הריחוף — היה גונב את ה-hover מהעוגן ומזניק לולאת
          // סגירה-פתיחה (הבהוב). IgnorePointer מוציא אותה מ-hit-test עד שמוצבה.
          child: IgnorePointer(
            ignoring: !_visible,
            child: Opacity(
              opacity: _visible ? 1 : 0,
              child: MouseRegion(
                onEnter: (_) => _cancelHide(),
                onExit: (_) => _scheduleHide(),
                // התוכן נטען אסינכרונית (FutureBuilder); כשהוא מגיע החלונית גדלה
                // אחרי המדידה הראשונית ועלולה לחרוג מהמסך — שינוי גודל מפעיל
                // מיקום מחדש (בסוף הפריים, כי עדכון overlay אסור בזמן layout).
                child: NotificationListener<SizeChangedLayoutNotification>(
                  onNotification: (_) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _reposition();
                    });
                    return true;
                  },
                  child: SizeChangedLayoutNotifier(
                    child: Listener(
                      onPointerDown: (_) => _pin(),
                      child: Material(
                        key: _panelKey,
                        elevation: style.elevation,
                        color: style.color(colorScheme),
                        shape: style.shape(colorScheme),
                        clipBehavior: Clip.antiAlias,
                        child: _buildPanelChild(maxWidth, maxHeight),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
