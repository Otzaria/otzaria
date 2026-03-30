// lib/widgets/context_overlay_panel.dart
//
// ContextOverlayPanel — פאנל הגדרות overlay שצף מעל התוכן
//
// רכיב behavior/layout שמשתמש ב-FloatingPanel כמעטפת עיצובית.
// מטרתו לאחד את ההתנהגות של פאנלי הגדרות בלוח שנה, ספריה, וגימטריה.
//
// **מאפיינים:**
// • פתיחה וסגירה באנימציית slide מהצד
// • scrim לחיץ לסגירה
// • גובה מלא של אזור התוכן
// • צבע רקע לפי AppTopBar (secondaryContainer)
// • תמיכה בימין/שמאל
//
// **שימוש:**
// ```dart
// Stack(
//   children: [
//     MainContent(),
//     if (isSettingsPanelOpen)
//       ContextOverlayPanel(
//         isOpen: isSettingsPanelOpen,
//         onClose: () => setState(() => isSettingsPanelOpen = false),
//         child: MySettingsContent(),
//       ),
//   ],
// )
// ```

import 'package:flutter/material.dart';
import 'package:otzaria/widgets/floating_panel.dart';

class ContextOverlayPanel extends StatelessWidget {
  /// האם הפאנל פתוח
  final bool isOpen;

  /// callback לסגירת הפאנל
  final VoidCallback onClose;

  /// תוכן הפאנל
  final Widget child;

  /// רוחב הפאנל (ברירת מחדל: 400)
  final double width;

  /// יישור הפאנל (ברירת מחדל: start - ימין בעברית)
  final AlignmentDirectional alignment;

  /// צבע רקע (ברירת מחדל: secondaryContainer)
  final Color? backgroundColor;

  /// ריפוד פנימי אחיד לתוכן הפאנל
  final EdgeInsetsGeometry contentPadding;

  const ContextOverlayPanel({
    super.key,
    required this.isOpen,
    required this.onClose,
    required this.child,
    this.width = 400,
    this.alignment =
        AlignmentDirectional.centerEnd, // ברירת מחדל: שמאל בעברית (RTL)
    this.backgroundColor,
    this.contentPadding = const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 16),
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effectiveBackgroundColor = backgroundColor ?? cs.secondaryContainer;
    // centerEnd = שמאל פיזי ב-RTL, centerStart = ימין פיזי
    final isLeft = alignment == AlignmentDirectional.centerEnd;

    return IgnorePointer(
      ignoring: !isOpen,
      child: Stack(
        children: [
          // ── scrim (רקע שקוף לחיץ) ──────────────────────────────────────
          Positioned.fill(
            child: GestureDetector(
              onTap: onClose,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: isOpen ? 1.0 : 0.0,
                child: ColoredBox(
                  color: cs.scrim.withValues(alpha: 0.30),
                ),
              ),
            ),
          ),
          // ── הפאנל: צף עם פינות מעוגלות ושוליים מהצדדים ────────────────
          Positioned(
            top: 10,
            bottom: 12,
            left: isLeft ? 10 : null,
            right: isLeft ? null : 10,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: isOpen ? 1.0 : 0.0,
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                offset: isOpen
                    ? Offset.zero
                    : (isLeft
                        ? const Offset(-1, 0) // שמאל → יוצא שמאלה
                        : const Offset(1, 0)), // ימין → יוצא ימינה
                child: FloatingPanel(
                  elevation: 8,
                  color: effectiveBackgroundColor,
                  borderRadius: BorderRadius.circular(18),
                  child: SizedBox(
                    width: width,
                    child: SafeArea(
                      child: Padding(
                        padding: contentPadding,
                        child: child,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
