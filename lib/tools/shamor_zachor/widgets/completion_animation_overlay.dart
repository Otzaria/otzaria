import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/layout/app_card.dart';

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
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;
  bool _announced = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: AppMotion.controller(const Duration(milliseconds: 2000)),
      vsync: this,
    );
    _scale = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.5, curve: Curves.elasticOut),
    );
    _opacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.7, 1.0, curve: Curves.easeOut),
      ),
    );
    _controller.forward().then((_) => widget.onComplete());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_announced) return;
    _announced = true;
    // ההודעה צפה ב-Overlay בלי פוקוס, ולכן קורא מסך לא יקרא אותה בלי הכרזה.
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        widget.message,
        Directionality.of(context),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: FadeTransition(
          opacity: _opacity,
          child: ScaleTransition(
            scale: _scale,
            child: Padding(
              padding: const EdgeInsets.all(AppTokens.spaceXL),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: LayoutConstraints.overlayPanelWidth,
                ),
                // AppCard בלי צל (DD-12); משטח צף מקבל את הצל של AppShadows.
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: AppTokens.borderRadiusAll,
                    boxShadow: AppShadows.floating(theme.colorScheme),
                  ),
                  child: AppCard(
                    padding: const EdgeInsets.all(AppTokens.spaceLG),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          OtzariaIcons.book_checkmark_24_regular,
                          size: AppTokens.iconXL,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(height: AppTokens.spaceMD),
                        Text(
                          widget.message,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleLarge,
                        ),
                      ],
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
