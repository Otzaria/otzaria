import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';

/// מפתח גלובלי לניווט - חובה לחבר ל-MaterialApp
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// מפתח גלובלי ל-ScaffoldMessenger - נשמר לתאימות לאחור
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// מערכת התראות מודרנית בהשראת Windows 11
/// 
/// שימוש:
/// ```dart
/// UiSnack.show('ההודעה נשלחה בהצלחה');
/// UiSnack.showSuccess('הפעולה הושלמה');
/// UiSnack.showError('אירעה שגיאה');
/// ```
class UiSnack {
  static OverlayEntry? _currentOverlay;
  static Timer? _dismissTimer;

  /// הצגת הודעה סטנדרטית
  static void show(
    String message, {
    Duration? duration,
    Color? backgroundColor,
    IconData? icon,
    Color? iconColor,
    bool enableHaptic = true,
  }) {
    _showOverlay(
      message: message,
      duration: duration ?? const Duration(seconds: 6),
      backgroundColor: backgroundColor,
      icon: icon,
      iconColor: iconColor,
      enableHaptic: enableHaptic,
    );
  }

  /// הודעת שגיאה
  static void showError(String message, {Duration? duration, Color? backgroundColor}) {
    _showOverlay(
      message: message,
      icon: Icons.error_outline_rounded,
      iconColor: const Color(0xFFFF6B6B),
      duration: duration ?? const Duration(seconds: 5),
      backgroundColor: backgroundColor,
      enableHaptic: true,
    );
  }

  /// הודעת הצלחה
  static void showSuccess(String message, {Duration? duration, Color? backgroundColor}) {
    _showOverlay(
      message: message,
      icon: Icons.check_circle_outline_rounded,
      iconColor: const Color(0xFF6CCB5F),
      duration: duration ?? const Duration(seconds: 4),
      backgroundColor: backgroundColor,
      enableHaptic: true,
    );
  }

  /// הודעה צפה (תאימות לאחור)
  static void showFloating(String message, {Duration? duration, Color? backgroundColor}) {
    show(
      message, 
      duration: duration ?? const Duration(seconds: 4), 
      backgroundColor: backgroundColor
    );
  }

  /// הודעה עם משך זמן מותאם (תאימות לאחור)
  static void showWithDuration(String message, {Duration? duration, Color? backgroundColor}) {
     show(
       message,
       duration: duration ?? const Duration(seconds: 2),
       backgroundColor: backgroundColor,
     );
  }

  /// הודעה עם כפתור פעולה
  static void showWithAction({
    required String message,
    required String actionLabel,
    required VoidCallback onAction,
    Duration duration = const Duration(seconds: 5),
    IconData? icon,
    Color? iconColor,
    Color? actionTextColor,
    Color? backgroundColor,
  }) {
    _showOverlay(
      message: message,
      duration: duration,
      actionLabel: actionLabel,
      onAction: onAction,
      icon: icon,
      iconColor: iconColor,
      backgroundColor: backgroundColor,
    );
  }

  /// הודעה מהירה (800ms)
  static void showQuick(String message) {
    _showOverlay(
      message: message,
      duration: const Duration(milliseconds: 800),
      enableHaptic: false,
    );
  }

  // --- הלוגיקה הפנימית ---

  static void _showOverlay({
    required String message,
    required Duration duration,
    Color? backgroundColor,
    IconData? icon,
    Color? iconColor,
    String? actionLabel,
    VoidCallback? onAction,
    bool enableHaptic = false,
  }) {
    // הסרת הודעה קודמת
    _removeCurrentOverlay();

    // קבלת Context - עם בדיקת זמינות
    final context = navigatorKey.currentContext;
    if (context == null) {
      debugPrint('⚠️ UiSnack: navigatorKey.currentContext is null - Did you attach navigatorKey to MaterialApp?');
      return;
    }

    // פונקציה פנימית שמנסה להציג את ה-Overlay
    void tryShowOverlay() {
      // נסיון שליפה ראשון: דרך ה-NavigatorState (הכי אמין ל-root navigator)
      OverlayState? overlay = navigatorKey.currentState?.overlay;
      
      // נסיון שני: דרך ה-Context (חיפוש כלפי מעלה)
      if (overlay == null && context.mounted) {
        overlay = Overlay.maybeOf(context, rootOverlay: true);
      }

      if (overlay == null) {
        debugPrint('⚠️ UiSnack: Overlay not ready yet, scheduling retry...');
        
        // נסיון נוסף אחרי frame נוסף
        WidgetsBinding.instance.addPostFrameCallback((_) {
          OverlayState? retryOverlay = navigatorKey.currentState?.overlay;
          if (retryOverlay == null && context.mounted) {
            retryOverlay = Overlay.maybeOf(context, rootOverlay: true);
          }
          
          if (retryOverlay == null) {
            debugPrint('❌ UiSnack: Failed to find Overlay after retry');
            return;
          }
          _insertOverlay(
            retryOverlay,
            message: message,
            duration: duration,
            backgroundColor: backgroundColor,
            icon: icon,
            iconColor: iconColor,
            actionLabel: actionLabel,
            onAction: onAction,
            enableHaptic: enableHaptic,
          );
        });
        return;
      }

      _insertOverlay(
        overlay,
        message: message,
        duration: duration,
        backgroundColor: backgroundColor,
        icon: icon,
        iconColor: iconColor,
        actionLabel: actionLabel,
        onAction: onAction,
        enableHaptic: enableHaptic,
      );
    }

    // התחלת התהליך
    // אם אנחנו כבר בתוך Frame callback או באמצע בנייה, נדחה את ההצגה
    if (WidgetsBinding.instance.schedulerPhase != SchedulerPhase.idle) {
      WidgetsBinding.instance.addPostFrameCallback((_) => tryShowOverlay());
    } else {
      tryShowOverlay();
    }
  }

  static void _insertOverlay(
    OverlayState overlay, {
    required String message,
    required Duration duration,
    Color? backgroundColor,
    IconData? icon,
    Color? iconColor,
    String? actionLabel,
    VoidCallback? onAction,
    bool enableHaptic = false,
  }) {
    if (enableHaptic) {
      HapticFeedback.lightImpact();
    }

    // יצירת Entry
    _currentOverlay = OverlayEntry(
      builder: (overlayContext) => _Win11Toast(
        message: message,
        duration: duration,
        backgroundColor: backgroundColor,
        icon: icon,
        iconColor: iconColor,
        actionLabel: actionLabel,
        onAction: onAction,
        onDismiss: _removeCurrentOverlay,
      ),
    );

    // הוספה ל-Overlay
    overlay.insert(_currentOverlay!);

    // טיימר להסרה
    _dismissTimer = Timer(
      duration + const Duration(milliseconds: 500),
      _removeCurrentOverlay,
    );
  }

  static void _removeCurrentOverlay() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _currentOverlay?.remove();
    _currentOverlay = null;
  }

  // --- קבועים לטקסטים נפוצים ---
  static const String textCopied = 'הטקסט הועתק ללוח';
  static const String formattedTextCopied = 'הטקסט המעוצב הועתק ללוח';
  static const String copyError = 'שגיאה בהעתקה';
  static const String formattedCopyError = 'שגיאה בהעתקה מעוצבת';
  static const String sectionNotFound = 'Section not found';
  static const String bookNotFound = 'הספר איננו קיים';
  static const String noteCreated = 'ההערה נוצרה והוצבה בסרגל';
  static const String savedSuccessfully = 'השינויים נשמרו בהצלחה';
  static const String textNotFound = 'הטקסט לא נמצא';
  static const String noTextSelected = 'אנא בחר טקסט להעתקה';
  static const String cleanupCompleted = 'ניקוי טיוטות הושלם';
}

/// הווידג'ט של ההתראה - אנימציות ועיצוב Windows 11
class _Win11Toast extends StatefulWidget {
  final String message;
  final Duration duration;
  final Color? backgroundColor;
  final IconData? icon;
  final Color? iconColor;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onDismiss;

  const _Win11Toast({
    required this.message,
    required this.duration,
    required this.onDismiss,
    this.backgroundColor,
    this.icon,
    this.iconColor,
    this.actionLabel,
    this.onAction,
  });

  @override
  State<_Win11Toast> createState() => _Win11ToastState();
}

class _Win11ToastState extends State<_Win11Toast>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;
  Timer? _autoCloseTimer;

  @override
  void initState() {
    super.initState();

    // אנימציית כניסה ויציאה
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
      reverseDuration: const Duration(milliseconds: 500),
    );

    // קפיצה עדינה בכניסה (Windows 11 style)
    final curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInCubic,
    );

    _scaleAnim = Tween<double>(begin: 0.85, end: 1.0).animate(curve);
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.8),
      end: Offset.zero,
    ).animate(curve);

    // התחלת אנימציה
    _controller.forward();

    // טיימר סגירה
    _autoCloseTimer = Timer(widget.duration, _close);
  }

  void _close() {
    if (!mounted) return;
    _controller.reverse().then((_) {
      if (mounted) widget.onDismiss();
    });
  }

  @override
  void dispose() {
    _autoCloseTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    
    // צבעים בסגנון Windows 11 Acrylic (מותאם לנושא)
    final bgColor = widget.backgroundColor ??
        colorScheme.surfaceContainerHighest.withValues(alpha: 1);

    final textColor = colorScheme.onSurface;
    final borderColor = colorScheme.onSurface.withValues(alpha: isDark ? 0.2 : 0.15);

    return Positioned(
      bottom: 64,
      left: 20,
      right: 20,
      child: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Opacity(
              opacity: _fadeAnim.value,
              child: Transform.scale(
                scale: _scaleAnim.value,
                child: child,
              ),
            );
          },
          child: GestureDetector(
            onVerticalDragEnd: (details) {
              // החלקה כלפי מטה = סגירה
              if (details.primaryVelocity != null &&
                  details.primaryVelocity! > 300) {
                _close();
              }
            },
            child: Material(
              color: Colors.transparent,
              child: Container(
                constraints: const BoxConstraints(
                  maxWidth: 420,
                  minWidth: 300,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                    child: Container(
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: borderColor,
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 40,
                            offset: const Offset(0, 16),
                            spreadRadius: -4,
                          ),
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: widget.icon == null 
                            ? MainAxisAlignment.center 
                            : MainAxisAlignment.start,
                        children: [
                          if (widget.icon != null) ...[
                            Icon(
                              widget.icon,
                              color: widget.iconColor ?? textColor,
                              size: 24,
                            ),
                            const SizedBox(width: 16),
                            Container(
                              width: 1,
                              height: 24,
                              color: textColor.withValues(alpha: 0.15),
                            ),
                            const SizedBox(width: 16),
                          ],
                          Flexible(
                            child: Text(
                              widget.message,
                              style: TextStyle(
                                color: textColor,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.2,
                                height: 1.4,
                                fontFamily: 'Segoe UI',
                              ),
                              textAlign: widget.icon == null 
                                  ? TextAlign.center 
                                  : TextAlign.start,
                              textDirection: TextDirection.rtl,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (widget.actionLabel != null &&
                              widget.onAction != null) ...[
                            const SizedBox(width: 16),
                            TextButton(
                              onPressed: () {
                                widget.onAction!();
                                _close();
                              },
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                backgroundColor: isDark
                                    ? Colors.white.withValues(alpha: 0.12)
                                    : Colors.black.withValues(alpha: 0.08),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(
                                widget.actionLabel!,
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
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
    );
  }
}
