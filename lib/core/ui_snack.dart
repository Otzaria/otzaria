import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

/// מפתח גלובלי לניווט - חובה לחבר ל-MaterialApp
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// ─────────────────────────────────────────────────────────────────────────────
// טוקנים פנימיים
// ─────────────────────────────────────────────────────────────────────────────
abstract class _ToastTokens {
  /// פינות בצורת גלולה — כמו שורת החיפוש
  static const double radius = 28.0;

  static const double padH = AppTokens.spaceMD; // 16
  static const double padV = AppTokens.spaceSM; // 8

  static const double fontMessage = AppTokens.fontXL; // 18 — גדול יותר
  static const double fontAction = AppTokens.fontMD; // 14

  static const double maxWidth = 500;

  /// שקיפות רקע — מספיק שקוף כדי לראות את הרקע, מספיק אטום לקריאות
  static const double bgAlpha = 0.88;

  /// blur לאפקט זכוכית
  static const double blurSigma = 24.0;

  static const Duration animEnter = AppTokens.animFast; // 150ms
  static const Duration animExit = AppTokens.animNormal; // 250ms
}

// ─────────────────────────────────────────────────────────────────────────────
// סוגי ההתראה
// ─────────────────────────────────────────────────────────────────────────────
enum _SnackVariant { standard, error, warning }

// ─────────────────────────────────────────────────────────────────────────────
// UiSnack — ממשק ציבורי
// ─────────────────────────────────────────────────────────────────────────────
class UiSnack {
  static OverlayEntry? _currentOverlay;
  static Timer? _dismissTimer;

  static void show(
    String message, {
    Duration? duration,
    IconData? icon,
    bool enableHaptic = true,
  }) =>
      _showOverlay(
        message: message,
        variant: _SnackVariant.standard,
        duration: duration ?? const Duration(seconds: 6),
        icon: icon,
        enableHaptic: enableHaptic,
      );

  static void showError(String message, {Duration? duration}) => _showOverlay(
        message: message,
        variant: _SnackVariant.error,
        icon: FluentIcons.error_circle_24_regular,
        duration: duration ?? const Duration(seconds: 3),
        enableHaptic: true,
      );

  static void showSuccess(String message, {Duration? duration}) => _showOverlay(
        message: message,
        variant: _SnackVariant.standard,
        icon: FluentIcons.checkmark_circle_24_regular,
        duration: duration ?? const Duration(seconds: 3),
        enableHaptic: true,
      );

  static void showWarning(String message, {Duration? duration}) => _showOverlay(
        message: message,
        variant: _SnackVariant.warning,
        icon: FluentIcons.warning_24_regular,
        duration: duration ?? const Duration(seconds: 3),
        enableHaptic: true,
      );

  static void showWithAction({
    required String message,
    required String actionLabel,
    required VoidCallback onAction,
    Duration duration = const Duration(seconds: 5),
    IconData? icon,
  }) =>
      _showOverlay(
        message: message,
        variant: _SnackVariant.standard,
        duration: duration,
        actionLabel: actionLabel,
        onAction: onAction,
        icon: icon,
      );

  static void showQuick(String message) => _showOverlay(
        message: message,
        variant: _SnackVariant.standard,
        duration: const Duration(milliseconds: 800),
        enableHaptic: false,
      );

  /// בדיקה - חיצים מסתובבים, נשאר עד שמסתירים
  static void showChecking(String message) => _showOverlay(
        message: message,
        variant: _SnackVariant.standard,
        duration: const Duration(days: 365), // לא נסגר אוטומטית
        icon: FluentIcons.folder_sync_24_regular,
        enableHaptic: false,
        showCloseButton: true,
      );

  /// הורדה - אייקון הורדה, נשאר עד שמסתירים
  static void showDownloading(String message) => _showOverlay(
        message: message,
        variant: _SnackVariant.standard,
        duration: const Duration(days: 365), // לא נסגר אוטומטית
        icon: FluentIcons.arrow_download_24_regular,
        enableHaptic: false,
        showCloseButton: true,
      );

  /// הסתרת ההודעה הנוכחית
  static void hide() => _removeCurrentOverlay();
  // ── Internal ────────────────────────────────────────────────────────────────

  static void _showOverlay({
    required String message,
    required _SnackVariant variant,
    required Duration duration,
    IconData? icon,
    String? actionLabel,
    VoidCallback? onAction,
    bool enableHaptic = false,
    bool showCloseButton = false,
  }) {
    _removeCurrentOverlay();

    final context = navigatorKey.currentContext;
    if (context == null) {
      debugPrint('⚠️ UiSnack: navigatorKey.currentContext is null');
      return;
    }

    void tryShow() {
      OverlayState? overlay = navigatorKey.currentState?.overlay;
      if (overlay == null && context.mounted) {
        overlay = Overlay.maybeOf(context, rootOverlay: true);
      }

      if (overlay == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          OverlayState? retry = navigatorKey.currentState?.overlay;
          if (retry == null && context.mounted) {
            retry = Overlay.maybeOf(context, rootOverlay: true);
          }
          if (retry == null) return;
          _insert(retry,
              message: message,
              variant: variant,
              duration: duration,
              icon: icon,
              actionLabel: actionLabel,
              onAction: onAction,
              enableHaptic: enableHaptic);
        });
        return;
      }

      _insert(overlay,
          message: message,
          variant: variant,
          duration: duration,
          icon: icon,
          actionLabel: actionLabel,
          onAction: onAction,
          enableHaptic: enableHaptic);
    }

    if (WidgetsBinding.instance.schedulerPhase != SchedulerPhase.idle) {
      WidgetsBinding.instance.addPostFrameCallback((_) => tryShow());
    } else {
      tryShow();
    }
  }

  static void _insert(
    OverlayState overlay, {
    required String message,
    required _SnackVariant variant,
    required Duration duration,
    IconData? icon,
    String? actionLabel,
    VoidCallback? onAction,
    bool enableHaptic = false,
    bool showCloseButton = false,
  }) {
    if (enableHaptic) HapticFeedback.lightImpact();

    _currentOverlay = OverlayEntry(
      builder: (ctx) => _SnackToast(
        message: message,
        variant: variant,
        duration: duration,
        icon: icon,
        actionLabel: actionLabel,
        onAction: onAction,
        showCloseButton: showCloseButton,
        onDismiss: _removeCurrentOverlay,
      ),
    );

    overlay.insert(_currentOverlay!);

    _dismissTimer = Timer(
      duration + const Duration(milliseconds: 400),
      _removeCurrentOverlay,
    );
  }

  static void _removeCurrentOverlay() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _currentOverlay?.remove();
    _currentOverlay = null;
  }

  // ── קבועי טקסט ──────────────────────────────────────────────────────────────
  static const String textCopied = 'הטקסט הועתק ללוח';
  static const String formattedTextCopied = 'הטקסט המעוצב הועתק ללוח';
  static const String copyError = 'שגיאה בהעתקה';
  static const String formattedCopyError = 'שגיאה בהעתקה מעוצבת';
  static const String sectionNotFound = 'הדף לא נמצא בתוכן העניינים';
  static const String bookNotFound = 'הספר איננו קיים';
  static const String noteCreated = 'ההערה נוצרה והוצבה בסרגל';
  static const String savedSuccessfully = 'השינויים נשמרו בהצלחה';
  static const String textNotFound = 'הטקסט לא נמצא';
  static const String noTextSelected = 'אנא בחר טקסט להעתקה';
  static const String cleanupCompleted = 'ניקוי טיוטות הושלם';
}

// ─────────────────────────────────────────────────────────────────────────────
// _SnackToast — ווידג'ט פנימי
// ─────────────────────────────────────────────────────────────────────────────

class _SnackToast extends StatefulWidget {
  final String message;
  final _SnackVariant variant;
  final Duration duration;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool showCloseButton;
  final VoidCallback onDismiss;

  const _SnackToast({
    required this.message,
    required this.variant,
    required this.duration,
    required this.showCloseButton,
    required this.onDismiss,
    this.icon,
    this.actionLabel,
    this.onAction,
  });

  @override
  State<_SnackToast> createState() => _SnackToastState();
}

class _SnackToastState extends State<_SnackToast>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;
  Timer? _closeTimer;

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      vsync: this,
      duration: _ToastTokens.animEnter,
      reverseDuration: _ToastTokens.animExit,
    );

    final curve = CurvedAnimation(
      parent: _ctrl,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInCubic,
    );

    _scaleAnim = Tween<double>(begin: 0.88, end: 1.0).animate(curve);
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );

    _ctrl.forward();
    _closeTimer = Timer(widget.duration, _close);
  }

  void _close() {
    if (!mounted) return;
    _ctrl.reverse().then((_) {
      if (mounted) widget.onDismiss();
    });
  }

  @override
  void dispose() {
    _closeTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  /// צבעים לפי variant — נשענים על צבעי המערכת (ColorScheme)
  ({Color bg, Color fg, Color action}) _colors(ColorScheme cs) =>
      switch (widget.variant) {
        _SnackVariant.error => (
            bg: cs.errorContainer,
            fg: cs.onErrorContainer,
            action: cs.error,
          ),
        _SnackVariant.warning => (
            bg: cs.tertiaryContainer,
            fg: cs.onSurface, // שחור במצב בהיר, לבן במצב כהה
            action: cs.tertiary,
          ),
        _SnackVariant.standard => (
            bg: cs.surfaceContainerHighest,
            fg: cs.onSurface,
            action: cs.primary,
          ),
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = _colors(cs);

    // רקע שקוף-למחצה — מספיק אטום לקריאות, מספיק שקוף לאפקט עמוק
    final bgColor = c.bg.withValues(alpha: _ToastTokens.bgAlpha);

    return Positioned(
      // מיקום מקורי — מרחף מעל תחתית המסך
      bottom: 64,
      left: 20,
      right: 20,
      child: Center(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, child) => Opacity(
            opacity: _fadeAnim.value,
            child: Transform.scale(
              scale: _scaleAnim.value,
              child: child,
            ),
          ),
          child: GestureDetector(
            onVerticalDragEnd: (d) {
              if ((d.primaryVelocity ?? 0) > 200) _close();
            },
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: _ToastTokens.maxWidth,
              ),
              child: IntrinsicWidth(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(_ToastTokens.radius),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: _ToastTokens.blurSigma,
                      sigmaY: _ToastTokens.blurSigma,
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: Container(
                        decoration: BoxDecoration(
                          color: bgColor,
                          borderRadius:
                              BorderRadius.circular(_ToastTokens.radius),
                          //  ללא border — רק צל עדין לעומק
                          boxShadow: [
                            BoxShadow(
                              color: cs.shadow
                                  .withValues(alpha: isDark ? 0.35 : 0.12),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                              spreadRadius: -2,
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: _ToastTokens.padH,
                          vertical: _ToastTokens.padV,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.icon != null) ...[
                              Icon(widget.icon, color: c.fg, size: 20),
                              const SizedBox(width: AppTokens.spaceSM),
                            ],
                            Flexible(
                              child: Text(
                                widget.message,
                                style: TextStyle(
                                  color: c.fg,
                                  fontSize: _ToastTokens.fontMessage,
                                  fontWeight: FontWeight.w400,
                                  height: 1.4,
                                ),
                              ),
                            ),
                            if (widget.actionLabel != null &&
                                widget.onAction != null) ...[
                              const SizedBox(width: AppTokens.spaceSM),
                              TextButton(
                                onPressed: () {
                                  widget.onAction!();
                                  _close();
                                },
                                style: TextButton.styleFrom(
                                  foregroundColor: c.action,
                                  textStyle: const TextStyle(
                                    fontSize: _ToastTokens.fontAction,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  minimumSize: Size.zero,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: AppTokens.spaceSM,
                                      vertical: 4),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Text(widget.actionLabel!),
                              ),
                            ],
                            if (widget.showCloseButton) ...[
                              const SizedBox(width: AppTokens.spaceSM),
                              IconButton(
                                onPressed: _close,
                                icon: Icon(FluentIcons.dismiss_24_regular,
                                    color: c.fg, size: 18),
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                    minWidth: 32, minHeight: 32),
                              ),
                            ],
                          ],
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
