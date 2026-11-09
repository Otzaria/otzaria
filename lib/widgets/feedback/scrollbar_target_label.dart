import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/theme/app_shadows.dart';

/// הצד שאליו תיפתח תווית היעד ביחס לנקודת העוגן (מיקום העכבר על הסרגל).
/// [left] — התווית גדלה שמאלה מהעוגן (כשהסרגל בקצה ימין של המסך, כמו ברוב
/// מסכי הקריאה בעברית). [right] — התווית גדלה ימינה (סרגל בקצה שמאל).
enum ScrollbarLabelSide { left, right }

/// מנהל הצגה של תווית-יעד צפה מעל פס הגלילה: ברחיפה/גרירה על הסרגל מציג את
/// כתובת המקום שאליו תתבצע הקפיצה.
///
/// משתמש ב-[OverlayEntry] ולא ב-`Stack`/`Positioned` מקומי משתי סיבות:
///   1. **ביצועים** — התווית מצוירת בשכבת ה-Overlay הראשית ומבודדת לחלוטין
///      מעץ הסרגל/הרשימה. עדכון מיקום או טקסט קורא רק ל-`markNeedsBuild` על
///      ה-entry ואינו בונה מחדש את הרשימה/ה-PDF.
///   2. **חיתוך** — הסרגל יושב ב-gutter צר; תווית בתוך אותו תת-עץ הייתה
///      נחתכת. ה-Overlay מצייר מעל הכול בקואורדינטות גלובליות.
///
/// יש לקרוא ל-[dispose] ב-`dispose` של ה-State המחזיק.
class ScrollbarTargetLabelController {
  OverlayEntry? _entry;
  Offset _anchor = Offset.zero;
  String _text = '';
  ScrollbarLabelSide _side = ScrollbarLabelSide.left;

  /// מציג או מעדכן את התווית. [anchor] הוא מיקום גלובלי (נקודת העכבר על
  /// הסרגל), [text] הכתובת להצגה, ו-[side] קובע לאיזה כיוון תיפתח התווית.
  void show(
    BuildContext context, {
    required Offset anchor,
    required String text,
    required ScrollbarLabelSide side,
  }) {
    if (text.trim().isEmpty) {
      hide();
      return;
    }
    _anchor = anchor;
    _text = text;
    _side = side;

    if (_entry == null) {
      final overlay = Overlay.maybeOf(context, rootOverlay: true);
      if (overlay == null) return;
      _entry = OverlayEntry(builder: _buildLabel);
      overlay.insert(_entry!);
    } else {
      _entry!.markNeedsBuild();
    }
  }

  /// מסיר את התווית אם היא מוצגת.
  void hide() {
    _entry?.remove();
    _entry = null;
  }

  void dispose() => hide();

  Widget _buildLabel(BuildContext context) {
    final theme = Theme.of(context);
    final screen = MediaQuery.of(context).size;
    const gap = 10.0;

    final label = Material(
      color: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(maxWidth: screen.width * 0.4),
        decoration: BoxDecoration(
          color: theme.colorScheme.inverseSurface,
          borderRadius: AppTokens.borderRadiusAll,
          boxShadow: AppShadows.floating(theme.colorScheme),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          _text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onInverseSurface,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );

    // FractionalTranslation(-0.5 ב-Y) ממרכז את התווית אנכית סביב נקודת העוגן
    // בלי לדעת מראש את גובהה.
    final centeredLabel = FractionalTranslation(
      translation: const Offset(0, -0.5),
      child: label,
    );

    // במסך נמוך מ-48px (טסטים / מזעור קיצוני) הגבול התחתון היה גדול מהעליון
    // ו-clamp היה זורק; במקרה כזה פשוט תוחמים לטווח המסך.
    final top = screen.height > 48.0
        ? _anchor.dy.clamp(24.0, screen.height - 24.0)
        : _anchor.dy.clamp(0.0, screen.height);

    if (_side == ScrollbarLabelSide.left) {
      return Positioned(
        right: (screen.width - _anchor.dx + gap).clamp(0.0, screen.width),
        top: top,
        child: centeredLabel,
      );
    }
    return Positioned(
      left: (_anchor.dx + gap).clamp(0.0, screen.width),
      top: top,
      child: centeredLabel,
    );
  }
}
