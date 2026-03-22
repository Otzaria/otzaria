import 'package:flutter/material.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';

/// Widget שמציג הדרכה על חלונית המפרשים בפעם הראשונה
class CommentaryPaneTooltip extends StatefulWidget {
  final Widget child;

  const CommentaryPaneTooltip({
    super.key,
    required this.child,
  });

  static bool _shownThisSession = false;
  static const String _settingsKey = 'key-commentary-pane-tooltip-shown';
  static const String _firstShownDateKey =
      'key-commentary-pane-tooltip-first-shown';

  @override
  State<CommentaryPaneTooltip> createState() => _CommentaryPaneTooltipState();
}

class _CommentaryPaneTooltipState extends State<CommentaryPaneTooltip>
    with SingleTickerProviderStateMixin {
  bool _showTooltip = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _checkIfShouldShow();
  }

  Future<void> _checkIfShouldShow() async {
    // אם כבר הוצג בהפעלה הנוכחית - לא מציגים שוב
    if (CommentaryPaneTooltip._shownThisSession) return;

    // בדיקה אם המשתמש כבר ראה - לא מציגים יותר
    final alreadyShown = Settings.getValue<bool>(
            CommentaryPaneTooltip._settingsKey,
            defaultValue: false) ??
        false;
    if (alreadyShown) return;

    // בדיקה אם עבר שבוע מאז ההצגה הראשונה
    final firstShownStr =
        Settings.getValue<String>(CommentaryPaneTooltip._firstShownDateKey);
    if (firstShownStr != null) {
      final firstShown = DateTime.tryParse(firstShownStr);
      if (firstShown != null) {
        final daysSinceFirst = DateTime.now().difference(firstShown).inDays;
        if (daysSinceFirst >= 7) {
          // עבר שבוע - לא מציגים יותר
          Settings.setValue<bool>(CommentaryPaneTooltip._settingsKey, true);
          return;
        }
      }
    } else {
      // זו הפעם הראשונה - שומרים את התאריך
      Settings.setValue<String>(CommentaryPaneTooltip._firstShownDateKey,
          DateTime.now().toIso8601String());
    }

    // מסמנים שהוצג בהפעלה הנוכחית
    CommentaryPaneTooltip._shownThisSession = true;

    // המתנה קצרה לפני הצגת ההדרכה
    await Future.delayed(const Duration(milliseconds: 1500));
    if (mounted) {
      _showOverlay();

      // נעלם אוטומטית אחרי 2 שניות
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && _showTooltip) {
          _dismissTooltip();
        }
      });
    }
  }

  void _showOverlay() {
    _removeOverlay();

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: 0,
        top: 0,
        child: CompositedTransformFollower(
          link: _layerLink,
          targetAnchor: Alignment.centerRight,
          followerAnchor: Alignment.centerLeft,
          offset: const Offset(8, 0),
          showWhenUnlinked: false,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Material(
              color: Colors.transparent,
              child: GestureDetector(
                onTap: _dismissTooltip,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.inverseSurface,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(context)
                              .colorScheme
                              .shadow
                              .withValues(alpha: 0.25),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                    ],
                  ),
                  child: Text(
                    'לחץ כאן למפרשים וקישורים ←',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onInverseSurface,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    textDirection: TextDirection.rtl,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
    setState(() => _showTooltip = true);
    _animationController.forward();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _dismissTooltip() {
    _animationController.reverse().then((_) {
      _removeOverlay();
      if (mounted) {
        setState(() => _showTooltip = false);
      }
    });
  }

  @override
  void dispose() {
    _removeOverlay();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: widget.child,
    );
  }
}
