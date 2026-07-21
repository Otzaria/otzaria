import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/misc/link_context_menu_entry.dart';
import 'package:otzaria/widgets/misc/overlay_scroll_anchor.dart';
import 'package:otzaria/widgets/smart_text/smart_text.dart';

/// חלונית צפה עם תצוגה מקדימה של מפרש, שנפתחת בריחוף או בלחיצה על עוגן-מילה.
///
/// ממוקמת ליד נקודת הריחוף/הלחיצה, מוגבלת ברוחב ובגובה (4 שורות), נסגרת כשהסמן
/// עוזב אותה או בהקשה מחוצה לה — ונשארת פתוחה כשהסמן נכנס לתוכה (לסימון
/// והעתקה). לחיצה בתוך החלונית מקבעת אותה: היא נשארת פתוחה גם כשהסמן יוצא,
/// עד הקשה במקום אחר בדף, וזזה יחד עם גלילת התוכן שעליו נפתחה.
/// לחיצה על הכותרת פותחת את היעד. מוצגת חלונית אחת בכל רגע.
class LinkPreviewOverlay {
  LinkPreviewOverlay._();

  static OverlayEntry? _entry;
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

  /// מציגה חלונית מקובעת עם תוכן [contentBuilder] במיקום [panelPosition]
  /// (קואורדינטות ה-overlay השורשי). משמשת לקיבוע תצוגה מקדימה שהגיעה
  /// מתפריט ההקשר. [scrollAnchor] — עוגן שנלכד בפתיחת התפריט, לתזוזה עם
  /// הגלילה. נסגרת בהקשה מחוץ לחלונית.
  static void showPinned(
    BuildContext context, {
    required WidgetBuilder contentBuilder,
    required Offset panelPosition,
    OverlayScrollAnchor? scrollAnchor,
    VoidCallback? onDismissed,
  }) {
    _show(
      context,
      // תוכן שהגיע מתפריט ההקשר אינו קצוץ-שורות — מגבילים גובה עם גלילה
      // פנימית כדי שחלונית ארוכה לא תגלוש מהמסך.
      contentBuilder: (context) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.5,
        ),
        child: SingleChildScrollView(
          child: Builder(builder: contentBuilder),
        ),
      ),
      anchorPosition: panelPosition,
      onDismissed: onDismissed,
      hoverMode: false,
      startPinned: true,
      initialPanelOffset: panelPosition,
      scrollAnchorOverride: scrollAnchor,
    );
  }

  static void _show(
    BuildContext context, {
    required WidgetBuilder contentBuilder,
    required Offset anchorPosition,
    VoidCallback? onDismissed,
    bool hoverMode = false,
    bool startPinned = false,
    Offset? initialPanelOffset,
    OverlayScrollAnchor? scrollAnchorOverride,
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    // חלונית מקובעת נסגרת רק בלחיצה — ריחוף על עוגן אחר לא מחליף אותה.
    if (hoverMode && (_activePanel?._pinned ?? false)) return;
    dismiss();
    // לכידת עוגן הגלילה חייבת להקדים את הוספת החלונית ל-overlay, אחרת
    // ה-hit-test יפגע בחלונית עצמה במקום בשורת הטקסט שמתחתיה. בקיבוע
    // מתפריט ההקשר אין ללכוד כאן — התפריט עדיין פתוח מעל הנקודה.
    final scrollAnchor = startPinned
        ? scrollAnchorOverride
        : (scrollAnchorOverride ??
              OverlayScrollAnchor.capture(context, anchorPosition));
    _onDismissed = onDismissed;
    _entry = OverlayEntry(
      builder: (_) => _LinkPreviewPanel(
        contentBuilder: contentBuilder,
        anchorPosition: anchorPosition,
        onDismiss: dismiss,
        hoverMode: hoverMode,
        startPinned: startPinned,
        initialPanelOffset: initialPanelOffset,
        scrollAnchor: scrollAnchor,
      ),
    );
    overlay.insert(_entry!);
  }

  /// מתזמנת סגירה קרובה (הסמן עזב את העוגן). כניסת הסמן לחלונית מבטלת אותה.
  static void scheduleHide() => _activePanel?._scheduleHide();

  /// מבטלת סגירה מתוזמנת (הסמן חזר לעוגן בזמן שהחלונית פתוחה).
  static void cancelScheduledHide() => _activePanel?._cancelHide();

  static void dismiss() {
    _entry?.remove();
    _entry = null;
    final onDismissed = _onDismissed;
    _onDismissed = null;
    onDismissed?.call();
  }
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
  final VoidCallback onDismiss;
  final bool hoverMode;
  final bool startPinned;
  final Offset? initialPanelOffset;
  final OverlayScrollAnchor? scrollAnchor;

  const _LinkPreviewPanel({
    required this.contentBuilder,
    required this.anchorPosition,
    required this.onDismiss,
    this.hoverMode = false,
    this.startPinned = false,
    this.initialPanelOffset,
    this.scrollAnchor,
  });

  @override
  State<_LinkPreviewPanel> createState() => _LinkPreviewPanelState();
}

class _LinkPreviewPanelState extends State<_LinkPreviewPanel> {
  static const double _maxWidth = 420;
  static const double _screenPadding = 8;
  static const double _anchorGap = 10;
  static const Duration _hideDelay = Duration(milliseconds: 250);

  final GlobalKey _panelKey = GlobalKey();
  Offset _offset = const Offset(_screenPadding, _screenPadding);
  bool _visible = false;
  Timer? _hideTimer;
  late bool _pinned = widget.startPinned;

  /// מיקום העוגן בזמן הפתיחה — הפרש ממנו בזמן גלילה מזיז את החלונית.
  Offset? _anchorBaseline;
  Offset _scrollDelta = Offset.zero;
  bool _scrollUpdateScheduled = false;

  @override
  void initState() {
    super.initState();
    LinkPreviewOverlay._activePanel = this;
    _anchorBaseline = widget.scrollAnchor?.currentGlobalPosition();
    widget.scrollAnchor?.addListener(_onScrollChanged);
    // מיקום דו-שלבי: בנייה סמויה למדידת הגודל, ואז הצמדה לנקודת הלחיצה.
    WidgetsBinding.instance.addPostFrameCallback((_) => _reposition());
  }

  @override
  void dispose() {
    if (identical(LinkPreviewOverlay._activePanel, this)) {
      LinkPreviewOverlay._activePanel = null;
    }
    widget.scrollAnchor?.removeListener(_onScrollChanged);
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

  /// לחיצה בתוך החלונית מקבעת אותה — נשארת עד הקשה במקום אחר בדף.
  void _pin() {
    _cancelHide();
    if (!_pinned) {
      setState(() => _pinned = true);
    }
  }

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

    // חלונית מקובעת מתפריט ההקשר נפתחת בדיוק במקום שבו עמדה התצוגה המקדימה.
    final fixedOffset = widget.initialPanelOffset;
    if (fixedOffset != null) {
      setState(() {
        _offset = Offset(
          fixedOffset.dx.clamp(
            _screenPadding,
            (overlaySize.width - panelSize.width - _screenPadding).clamp(
              _screenPadding,
              double.infinity,
            ),
          ),
          fixedOffset.dy.clamp(
            _screenPadding,
            (overlaySize.height - panelSize.height - _screenPadding).clamp(
              _screenPadding,
              double.infinity,
            ),
          ),
        );
        _visible = true;
      });
      return;
    }

    final anchor = overlayBox.globalToLocal(widget.anchorPosition);

    // אנכית: מתחת לנקודה, ואם אין מקום — מעליה.
    double top = anchor.dy + _anchorGap;
    if (top + panelSize.height > overlaySize.height - _screenPadding) {
      top = anchor.dy - _anchorGap - panelSize.height;
    }
    top = top.clamp(
      _screenPadding,
      (overlaySize.height - panelSize.height - _screenPadding).clamp(
        _screenPadding,
        double.infinity,
      ),
    );

    // אופקית (RTL): הצמדת קצה ימני לנקודה, ואז חיתוך לגבולות המסך.
    double left = anchor.dx - panelSize.width;
    left = left.clamp(
      _screenPadding,
      (overlaySize.width - panelSize.width - _screenPadding).clamp(
        _screenPadding,
        double.infinity,
      ),
    );

    setState(() {
      _offset = Offset(left, top);
      _visible = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final maxWidth = (MediaQuery.of(context).size.width - _screenPadding * 2)
        .clamp(0.0, _maxWidth)
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
              behavior: HitTestBehavior.translucent,
              onTap: widget.onDismiss,
            ),
          ),
        Positioned(
          left: position.dx,
          top: position.dy,
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
                      elevation: 8,
                      color: colorScheme.surface,
                      borderRadius: AppTokens.borderRadiusAll,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxWidth),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          child: SelectionArea(
                            child: Builder(builder: widget.contentBuilder),
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
      ],
    );
  }
}
