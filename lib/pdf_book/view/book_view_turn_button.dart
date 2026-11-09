import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';

/// חץ הדפדוף העגול בתצוגת הספר של PDF: כפתור צף מעל העמוד
/// ([AppSurfaces.floatingControl]). ה-tooltip חל על כל העיגול.
class BookViewTurnButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final double size;
  final VoidCallback onPressed;

  const BookViewTurnButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.size,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final compactSize = size * 0.7;
    return Tooltip(
      message: tooltip,
      child: Container(
        width: compactSize,
        height: compactSize,
        decoration: BoxDecoration(
          color: AppSurfaces.floatingControl(cs),
          shape: BoxShape.circle,
          border: Border.all(color: AppSurfaces.floatingControlBorder(cs)),
          boxShadow: AppShadows.floating(cs),
        ),
        // ההדגשה נחתכת לעיגול של המכל.
        child: Material(
          color: Colors.transparent,
          // ui-lint: allow UIL-019 — כפתור אייקון בלבד עגול, ההדגשה נחתכת לעיגול (DD-04, q10 Q13)
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: Center(
              child: Icon(icon, color: cs.onSurface, size: compactSize * 0.5),
            ),
          ),
        ),
      ),
    );
  }
}
