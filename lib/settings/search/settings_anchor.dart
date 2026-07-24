import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/settings/search/settings_search_registry.dart';

/// עוטף SettingsCard (או כל ווידג'ט אחר) ומאפשר ניווט/הדגשה ממנגנון החיפוש.
///
/// שימוש:
/// ```
/// SettingsAnchor(
///   cardId: 'design.theme',
///   child: SettingsCard(...),
/// )
/// ```
///
/// - מרשם GlobalKey ב-SettingsSearchRegistry תחת cardId.
/// - מאזין לבקשות הבזק על ה-cardId שלו ומריץ אנימציה.
class SettingsAnchor extends StatefulWidget {
  final String cardId;
  final Widget child;

  const SettingsAnchor({
    super.key,
    required this.cardId,
    required this.child,
  });

  @override
  State<SettingsAnchor> createState() => _SettingsAnchorState();
}

class _SettingsAnchorState extends State<SettingsAnchor>
    with SingleTickerProviderStateMixin {
  final GlobalKey _key = GlobalKey();
  late final AnimationController _flashController;
  late final Animation<double> _flashAnimation;

  @override
  void initState() {
    super.initState();
    SettingsSearchRegistry.instance.registerAnchor(widget.cardId, _key);
    _flashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    );
    _flashAnimation =
        TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 1),
          TweenSequenceItem(tween: ConstantTween(1.0), weight: 2),
          TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 4),
        ]).animate(
          CurvedAnimation(
            parent: _flashController,
            curve: Curves.easeOutQuad,
          ),
        );

    SettingsSearchRegistry.instance
        .flashNotifierFor(widget.cardId)
        .addListener(_onFlashChanged);
  }

  @override
  void didUpdateWidget(covariant SettingsAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cardId != widget.cardId) {
      SettingsSearchRegistry.instance.unregisterAnchor(oldWidget.cardId, _key);
      SettingsSearchRegistry.instance
          .flashNotifierFor(oldWidget.cardId)
          .removeListener(_onFlashChanged);
      SettingsSearchRegistry.instance.registerAnchor(widget.cardId, _key);
      SettingsSearchRegistry.instance
          .flashNotifierFor(widget.cardId)
          .addListener(_onFlashChanged);
    }
  }

  @override
  void dispose() {
    SettingsSearchRegistry.instance
        .flashNotifierFor(widget.cardId)
        .removeListener(_onFlashChanged);
    SettingsSearchRegistry.instance.unregisterAnchor(widget.cardId, _key);
    _flashController.dispose();
    super.dispose();
  }

  void _onFlashChanged() {
    final flashing = SettingsSearchRegistry.instance
        .flashNotifierFor(widget.cardId)
        .value;
    if (flashing) {
      _flashController.forward(from: 0.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return KeyedSubtree(
      key: _key,
      child: AnimatedBuilder(
        animation: _flashAnimation,
        builder: (context, child) {
          final t = _flashAnimation.value;
          if (t == 0.0) return child!;
          return Container(
            decoration: BoxDecoration(
              borderRadius: AppTokens.borderRadiusAll,
              boxShadow: [
                BoxShadow(
                  color: colorScheme.primary.withValues(alpha: 0.35 * t),
                  blurRadius: 18 * t,
                  spreadRadius: 2 * t,
                ),
              ],
            ),
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}
