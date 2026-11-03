import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';
import 'package:otzaria/core/messages/common_messages.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

/// מפתח הניווט של החלון הנוכחי ([AppWindowKeys.current]) — חובה לחבר ל-MaterialApp.
/// קוד שיש לו `BuildContext` משתמש ב-[AppWindowKeys.of].
GlobalKey<NavigatorState> get navigatorKey => AppWindowKeys.current.navigator;

// ─────────────────────────────────────────────────────────────────────────────
// טוקנים פנימיים
// ─────────────────────────────────────────────────────────────────────────────
abstract class _ToastTokens {
  static const double padH = AppTokens.spaceMD; // 16
  static const double padV = AppTokens.spaceSM; // 8

  static const double fontMessage = AppTokens.fontXL; // 18 — גדול יותר

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
  /// חלונות שמוצגת בהם הודעה כרגע — כדי ש-`hide(owner:)` ימצא אותה מכל חלון.
  static final Set<_SnackSlot> _liveSlots = {};

  static void show(
    String message, {
    AppWindowKeys? window,
    Duration? duration,
    IconData? icon,
    bool enableHaptic = true,
    VoidCallback? onTap,
  }) => _showOverlay(
    window: window,
    message: message,
    variant: _SnackVariant.standard,
    duration: duration ?? const Duration(seconds: 6),
    icon: icon,
    enableHaptic: enableHaptic,
    onTap: onTap,
  );

  static void showError(
    String message, {
    AppWindowKeys? window,
    Duration? duration,
    VoidCallback? onTap,
  }) => _showOverlay(
    window: window,
    message: message,
    variant: _SnackVariant.error,
    icon: FluentIcons.error_circle_24_regular,
    duration: duration ?? const Duration(seconds: 3),
    enableHaptic: true,
    onTap: onTap,
  );

  static void showSuccess(
    String message, {
    AppWindowKeys? window,
    Duration? duration,
    VoidCallback? onTap,
  }) => _showOverlay(
    window: window,
    message: message,
    variant: _SnackVariant.standard,
    icon: FluentIcons.checkmark_circle_24_regular,
    duration: duration ?? const Duration(seconds: 3),
    enableHaptic: true,
    onTap: onTap,
  );

  static void showWarning(
    String message, {
    AppWindowKeys? window,
    Duration? duration,
    VoidCallback? onTap,
  }) => _showOverlay(
    window: window,
    message: message,
    variant: _SnackVariant.warning,
    icon: FluentIcons.warning_24_regular,
    duration: duration ?? const Duration(seconds: 3),
    enableHaptic: true,
    onTap: onTap,
  );

  static void showWithAction({
    required String message,
    required String actionLabel,
    required VoidCallback onAction,
    Duration duration = const Duration(seconds: 5),
    IconData? icon,
  }) => _showOverlay(
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
  static void showChecking(
    String message, {
    Object? owner,
    AppWindowKeys? window,
  }) => _showOverlay(
    window: window,
    owner: owner,
    message: message,
    variant: _SnackVariant.standard,
    duration: const Duration(days: 365), // לא נסגר אוטומטית
    icon: FluentIcons.folder_sync_24_regular,
    enableHaptic: false,
    showCloseButton: true,
  );

  /// מסתיר את ההודעה הנוכחית, או רק הודעה ששייכת ל-[owner].
  static void hide({Object? owner, AppWindowKeys? window}) {
    if (owner == null) {
      _removeOverlay((window ?? AppWindowKeys.current)._snackSlot);
      return;
    }
    for (final slot in _liveSlots.toList()) {
      if (identical(owner, slot.owner)) _removeOverlay(slot);
    }
  }
  // ── Internal ────────────────────────────────────────────────────────────────

  static void _showOverlay({
    AppWindowKeys? window,
    Object? owner,
    required String message,
    required _SnackVariant variant,
    required Duration duration,
    IconData? icon,
    String? actionLabel,
    VoidCallback? onAction,
    bool enableHaptic = false,
    bool showCloseButton = false,
    VoidCallback? onTap,
  }) {
    // החלון נקבע פעם אחת, כדי שכל ההמשך (גם אחרי פריים) יוצג באותו חלון.
    final keys = window ?? AppWindowKeys.current;
    final navigator = keys.navigator;
    final slot = keys._snackSlot;
    _removeOverlay(slot);
    final notificationOwner = slot.owner = owner ?? Object();
    _liveSlots.add(slot);

    final context = navigator.currentContext;
    if (context == null) {
      debugPrint('⚠️ UiSnack: navigatorKey.currentContext is null');
      _removeOverlay(slot);
      return;
    }

    void tryShow() {
      if (!identical(notificationOwner, slot.owner)) return;
      OverlayState? overlay = navigator.currentState?.overlay;
      if (overlay == null && context.mounted) {
        overlay = Overlay.maybeOf(context, rootOverlay: true);
      }

      if (overlay == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!identical(notificationOwner, slot.owner)) return;
          OverlayState? retry = navigator.currentState?.overlay;
          if (retry == null && context.mounted) {
            retry = Overlay.maybeOf(context, rootOverlay: true);
          }
          if (retry == null) return;
          _insert(
            slot,
            retry,
            message: message,
            variant: variant,
            duration: duration,
            icon: icon,
            actionLabel: actionLabel,
            onAction: onAction,
            enableHaptic: enableHaptic,
            showCloseButton: showCloseButton,
            onTap: onTap,
          );
        });
        return;
      }

      _insert(
        slot,
        overlay,
        message: message,
        variant: variant,
        duration: duration,
        icon: icon,
        actionLabel: actionLabel,
        onAction: onAction,
        enableHaptic: enableHaptic,
        showCloseButton: showCloseButton,
        onTap: onTap,
      );
    }

    if (WidgetsBinding.instance.schedulerPhase != SchedulerPhase.idle) {
      WidgetsBinding.instance.addPostFrameCallback((_) => tryShow());
    } else {
      tryShow();
    }
  }

  static void _insert(
    _SnackSlot slot,
    OverlayState overlay, {
    required String message,
    required _SnackVariant variant,
    required Duration duration,
    IconData? icon,
    String? actionLabel,
    VoidCallback? onAction,
    bool enableHaptic = false,
    bool showCloseButton = false,
    VoidCallback? onTap,
  }) {
    if (enableHaptic) HapticFeedback.lightImpact();

    final owner = slot.owner;
    final entry = slot.overlay = OverlayEntry(
      builder: (ctx) => _SnackToast(
        message: message,
        variant: variant,
        duration: duration,
        icon: icon,
        actionLabel: actionLabel,
        onAction: onAction,
        showCloseButton: showCloseButton,
        onDismiss: () => hide(owner: owner),
        onTap: onTap,
      ),
    );

    overlay.insert(entry);

    slot.dismissTimer = Timer(
      duration + const Duration(milliseconds: 400),
      () => hide(owner: owner),
    );
  }

  static void _removeOverlay(_SnackSlot slot) {
    slot.dismissTimer?.cancel();
    slot.dismissTimer = null;
    slot.overlay?.remove();
    slot.overlay = null;
    slot.owner = null;
    _liveSlots.remove(slot);
  }

  // ── קבועי טקסט — הערכים מרוכזים ב-CommonMessages ────────────────────────────
  static const String textCopied = CommonMessages.textCopied;
  static const String sectionNotFound = CommonMessages.sectionNotFound;
  static const String savedSuccessfully = CommonMessages.savedSuccessfully;
}

/// ההודעה המוצגת בחלון אחד — הודעה בחלון אחד אינה מסירה הודעה בחלון אחר.
class _SnackSlot {
  OverlayEntry? overlay;
  Object? owner;
  Timer? dismissTimer;
}

final _snackSlots = Expando<_SnackSlot>();

extension on AppWindowKeys {
  _SnackSlot get _snackSlot => _snackSlots[this] ??= _SnackSlot();
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
  final VoidCallback? onTap;

  const _SnackToast({
    required this.message,
    required this.variant,
    required this.duration,
    required this.showCloseButton,
    required this.onDismiss,
    this.icon,
    this.actionLabel,
    this.onAction,
    this.onTap,
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
  bool _entered = false;

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

    _closeTimer = Timer(widget.duration, _close);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ctrl
      ..duration = AppMotion.duration(context, _ToastTokens.animEnter)
      ..reverseDuration = AppMotion.duration(context, _ToastTokens.animExit);
    if (!_entered) {
      _entered = true;
      _announce();
      _ctrl.forward();
    }
  }

  @override
  void didUpdateWidget(_SnackToast oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message != widget.message) _announce();
  }

  /// ההודעה צפה ב-Overlay ואינה מקבלת פוקוס, ולכן קורא המסך לא יקרא אותה
  /// בלי הכרזה מפורשת.
  void _announce() {
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        widget.message,
        Directionality.of(context),
        assertiveness: widget.variant == _SnackVariant.error
            ? Assertiveness.assertive
            : Assertiveness.polite,
      ),
    );
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
  ({Color bg, Color fg, Color action}) _colors(
    ColorScheme cs,
    AppSurfaceColors surfaces,
  ) => switch (widget.variant) {
    _SnackVariant.error => (
      bg: cs.errorContainer,
      fg: cs.onErrorContainer,
      action: cs.error,
    ),
    _SnackVariant.warning => (
      bg: surfaces.warningContainer,
      fg: surfaces.onWarningContainer,
      action: surfaces.warning,
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
    final c = _colors(cs, AppSurfaceColors.of(context));

    // רקע שקוף-למחצה — מספיק אטום לקריאות, מספיק שקוף לאפקט עמוק
    final bgColor = c.bg.withValues(alpha: _ToastTokens.bgAlpha);

    return Positioned(
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
          child: MouseRegion(
            cursor: widget.onTap != null
                ? SystemMouseCursors.click
                : MouseCursor.defer,
            child: GestureDetector(
              onTap: widget.onTap == null
                  ? null
                  : () {
                      widget.onTap!();
                      _close();
                    },
              onVerticalDragEnd: (d) {
                if ((d.primaryVelocity ?? 0) > 200) _close();
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: _ToastTokens.maxWidth,
                ),
                child: IntrinsicWidth(
                  child: ClipRRect(
                    borderRadius: AppTokens.borderRadiusAll,
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
                            borderRadius: AppTokens.borderRadiusAll,
                            boxShadow: AppShadows.floating(cs),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: _ToastTokens.padH,
                            vertical: _ToastTokens.padV,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (widget.icon != null) ...[
                                Icon(
                                  widget.icon,
                                  color: c.fg,
                                  size: AppTokens.iconMD,
                                ),
                                const SizedBox(width: AppTokens.spaceSM),
                              ],
                              Flexible(
                                child: Text(
                                  widget.message,
                                  textAlign: TextAlign.center,
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
                                ActionButton.inline(
                                  text: widget.actionLabel!,
                                  color: c.action,
                                  onPressed: () {
                                    widget.onAction!();
                                    _close();
                                  },
                                ),
                              ],
                              if (widget.showCloseButton) ...[
                                const SizedBox(width: AppTokens.spaceSM),
                                IconButton(
                                  tooltip: context.settingsText('סגור'),
                                  onPressed: _close,
                                  icon: Icon(
                                    FluentIcons.dismiss_24_regular,
                                    color: c.fg,
                                    size: AppTokens.iconSM,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 32,
                                    minHeight: 32,
                                  ),
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
      ),
    );
  }
}
