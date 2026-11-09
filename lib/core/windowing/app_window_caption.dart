import 'package:flutter/material.dart';
import 'package:otzaria/core/windowing/app_drag_to_move_area.dart';
import 'package:otzaria/core/windowing/app_window_controller.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';
import 'package:otzaria/core/windowing/caption_button_colors.dart';
import 'package:otzaria/core/windowing/window_caption_hit_test.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:window_manager/window_manager.dart' show WindowCaptionButton;

/// כמו `WindowCaption` של window_manager (בלי כותרת), אבל הכפתורים ומצב
/// ה-maximize באים מה-[AppWindowScope] ולא מה-singleton. אותם כפתורים גם
/// במסך מלא: [fullscreen] מסתיר את ה-maximize ואת אזור הגרירה, ו-[onMinimize]
/// מחליף את המזעור (שם צריך לצאת קודם ממסך מלא).
class AppWindowCaption extends StatefulWidget {
  const AppWindowCaption({
    super.key,
    this.brightness,
    required this.tooltips,
    this.fullscreen = false,
    this.onMinimize,
  });

  final Brightness? brightness;

  /// השם הנגיש וה-tooltip של כל כפתור, בשפת הממשק.
  final AppWindowCaptionTooltips tooltips;
  final bool fullscreen;
  final Future<void> Function()? onMinimize;

  @override
  State<AppWindowCaption> createState() => _AppWindowCaptionState();
}

class _AppWindowCaptionState extends State<AppWindowCaption> {
  AppWindowController? _window;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final window = AppWindowScope.controllerOf(context);
    if (identical(window, _window)) return;
    _window?.stateChanges.removeListener(_onStateChanged);
    _window = window..stateChanges.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    _window?.stateChanges.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  Widget _tip(String message, Widget button) =>
      Tooltip(message: message, child: button);

  @override
  Widget build(BuildContext context) {
    final window = _window!;
    final tips = widget.tooltips;
    // פעילים גם מעל דיאלוג פתוח (DD-16).
    return WindowCaptionRegion(
      child: Row(
        mainAxisSize: widget.fullscreen ? MainAxisSize.min : MainAxisSize.max,
        children: [
          if (!widget.fullscreen)
            const Expanded(
              child: AppDragToMoveArea(
                child: SizedBox(height: double.infinity),
              ),
            ),
          // המקור בודק isMinimized ומשחזר; כפתור בחלון ממוזער אינו לחיץ.
          _tip(
            tips.minimize,
            WindowCaptionButton.minimize(
              brightness: widget.brightness,
              onPressed: widget.onMinimize ?? window.minimize,
            ),
          ),
          if (!widget.fullscreen)
            FutureBuilder<bool>(
              future: window.isMaximized(),
              builder: (context, snapshot) {
                if (snapshot.data == true) {
                  return _tip(
                    tips.restore,
                    WindowCaptionButton.unmaximize(
                      brightness: widget.brightness,
                      onPressed: window.unmaximize,
                    ),
                  );
                }
                return _tip(
                  tips.maximize,
                  WindowCaptionButton.maximize(
                    brightness: widget.brightness,
                    onPressed: window.maximize,
                  ),
                );
              },
            ),
          _tip(
            tips.close,
            WindowCaptionButton.close(
              brightness: widget.brightness,
              onPressed: window.close,
            ),
          ),
        ],
      ),
    );
  }
}

/// שמות כפתורי החלון, מתורגמים אצל הקורא (השכבה הזו לא מכירה את הקטלוג).
class AppWindowCaptionTooltips {
  const AppWindowCaptionTooltips({
    required this.minimize,
    required this.maximize,
    required this.restore,
    required this.close,
  });

  final String minimize;
  final String maximize;
  final String restore;
  final String close;
}

/// כפתור באותו מראה כמו כפתורי החלון של window_manager, עם אייקון לבחירה
/// (מסך מלא). הצבעים הם של כפתורי מערכת ההפעלה ([CaptionButtonColors]).
class AppCaptionIconButton extends StatefulWidget {
  const AppCaptionIconButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.brightness,
    required this.tooltip,
  });

  /// רוחב כפתור חלון ב-Windows.
  static const double width = 46;

  final VoidCallback onPressed;
  final IconData icon;
  final Brightness brightness;
  final String tooltip;

  @override
  State<AppCaptionIconButton> createState() => _AppCaptionIconButtonState();
}

class _AppCaptionIconButtonState extends State<AppCaptionIconButton> {
  bool _isHovering = false;
  bool _isPressed = false;

  void _onHover(bool hovered) {
    if (_isHovering != hovered) {
      setState(() => _isHovering = hovered);
    }
  }

  void _onPressedState(bool pressed) {
    if (_isPressed != pressed) {
      setState(() => _isPressed = pressed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = CaptionButtonColors.of(
      brightness: widget.brightness,
      hovering: _isHovering,
      pressed: _isPressed,
    );

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onExit: (_) => _onHover(false),
        onHover: (_) => _onHover(true),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _onPressedState(true),
          onTapCancel: () => _onPressedState(false),
          onTapUp: (_) => _onPressedState(false),
          onTap: widget.onPressed,
          child: Container(
            constraints: const BoxConstraints(
              minWidth: AppCaptionIconButton.width,
              minHeight: 32,
            ),
            decoration: BoxDecoration(color: colors.background),
            child: Center(
              child: Icon(
                widget.icon,
                size: AppTokens.iconSM,
                color: colors.icon,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
