import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/theme/theme_exports.dart';

import '../shamor_zachor_widget.dart';

/// אנימציית סיום במרכז הכלי, בלי רקע כהה ובלי חסימת לחיצות (q10 שאלה 19).
/// עולה ב־Overlay של החלון, ולכן ממוקמת לפי המלבן של הכלי.
class CompletionAnimationOverlay {
  /// מציג את [message] מעל הכלי ש־[context] בתוכו.
  static void show(BuildContext context, String message) {
    final overlay = Overlay.of(context);
    final area =
        context.findAncestorStateOfType<State<ShamorZachorWidget>>()?.context ??
        context;
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (entryContext) {
        final Widget animation = IgnorePointer(
          child: _CompletionAnimation(
            message: message,
            onComplete: () => overlayEntry.remove(),
          ),
        );
        final rect = _areaRect(area, overlay.context);
        return rect == null
            ? animation
            : Positioned.fromRect(rect: rect, child: animation);
      },
    );

    overlay.insert(overlayEntry);
  }

  /// המלבן של הכלי ביחס ל־Overlay; null כשהכלי כבר לא בעץ.
  static Rect? _areaRect(BuildContext area, BuildContext overlayContext) {
    if (!area.mounted) return null;
    final box = area.findRenderObject();
    final overlayBox = overlayContext.findRenderObject();
    if (box is! RenderBox || overlayBox is! RenderBox) return null;
    if (!box.hasSize || !box.attached) return null;
    return box.localToGlobal(Offset.zero, ancestor: overlayBox) & box.size;
  }
}

class _CompletionAnimation extends StatefulWidget {
  final String message;
  final VoidCallback onComplete;

  const _CompletionAnimation({
    required this.message,
    required this.onComplete,
  });

  @override
  State<_CompletionAnimation> createState() => _CompletionAnimationState();
}

class _CompletionAnimationState extends State<_CompletionAnimation>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _scaleAnimation =
        Tween<double>(
          begin: 0.0,
          end: 1.0,
        ).animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Interval(0.0, 0.5, curve: Curves.elasticOut),
          ),
        );

    _opacityAnimation =
        Tween<double>(
          begin: 1.0,
          end: 0.0,
        ).animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Interval(0.7, 1.0, curve: Curves.easeOut),
          ),
        );

    _controller.forward().then((_) => widget.onComplete());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Opacity(
              opacity: _opacityAnimation.value,
              child: Transform.scale(
                scale: _scaleAnimation.value,
                child: Container(
                  padding: const EdgeInsets.all(24),
                  margin: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: AppSurfaces.card(context),
                    borderRadius: AppTokens.borderRadiusAll,
                    boxShadow: [
                      BoxShadow(
                        color: cs.shadow.withValues(alpha: 0.24),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        FluentIcons.trophy_24_regular,
                        size: AppTokens.iconXL,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        widget.message,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
