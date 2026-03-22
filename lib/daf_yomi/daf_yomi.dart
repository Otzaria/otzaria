import 'package:flutter/material.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/daf_yomi/calendar.dart';

/// ווידג'ט דף יומי ולוח שנה.
///
/// **2 מצבים:**
/// • [compact] = false (touch/ברירת מחדל):
///   - 2 אזורי לחיצה: טקסט (תאריך + דף) ואייקון לוח שנה
///   - padding מלא, כפי שהיה
///
/// • [compact] = true (desktop/Chrome):
///   - גרסה דחוסה: תאריך בשורה אחת, דף בשורה שנייה (גופן קטן)
///   - ללא מפריד, padding מוקטן
///   - מתאים לסרגל עליון דחוס
class DafYomi extends StatelessWidget {
  final VoidCallback onCalendarTap;
  final Function(String tractate, String daf) onDafYomiTap;

  /// true = מצב desktop — גרסה דחוסה שמתאימה לסרגל צר
  final bool compact;

  const DafYomi({
    super.key,
    required this.onCalendarTap,
    required this.onDafYomiTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) {
        final Daf dafYomi = getDafYomi(DateTime.now());
        final tractate = dafYomi.getMasechta();
        final dafAmud = dafYomi.getDaf();

        return compact
            ? _buildCompact(context, tractate, dafAmud)
            : _buildStandard(context, tractate, dafAmud);
      },
    );
  }

  // ── מצב touch (סטנדרטי) ─────────────────────────────────────────────────

  Widget _buildStandard(BuildContext context, String tractate, int dafAmud) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // טקסטים — פותחים את הדף היומי
          Tooltip(
            message: 'פתח דף יומי',
            child: InkWell(
              onTap: () => onDafYomiTap(tractate, formatAmud(dafAmud)),
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(8),
                bottomRight: Radius.circular(8),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      getHebrewDateFormattedAsString(DateTime.now()),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.secondary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                      textDirection: TextDirection.rtl,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'דף היומי: $tractate ${formatAmud(dafAmud)}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.secondary,
                        fontSize: 11,
                      ),
                      textDirection: TextDirection.rtl,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // מפריד
          Container(
            width: 1,
            height: 24,
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
          ),

          // אייקון לוח שנה
          Tooltip(
            message: 'פתח לוח שנה',
            child: InkWell(
              onTap: onCalendarTap,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                bottomLeft: Radius.circular(8),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Icon(
                  Icons.calendar_month_outlined,
                  color: Theme.of(context).colorScheme.secondary,
                  size: 24,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── מצב desktop/compact ──────────────────────────────────────────────────

  Widget _buildCompact(BuildContext context, String tractate, int dafAmud) {
    final cs = Theme.of(context).colorScheme;
    final dafText = '$tractate ${formatAmud(dafAmud)}';
    final dateText = getHebrewDateFormattedAsString(DateTime.now());

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // לחצן דף יומי — טקסט דחוס
        Tooltip(
          message: 'פתח דף יומי: $dafText',
          child: InkWell(
            onTap: () => onDafYomiTap(tractate, formatAmud(dafAmud)),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    dateText,
                    style: TextStyle(
                      color: cs.secondary,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    textDirection: TextDirection.rtl,
                  ),
                  Text(
                    dafText,
                    style: TextStyle(color: cs.secondary, fontSize: 10),
                    textDirection: TextDirection.rtl,
                  ),
                ],
              ),
            ),
          ),
        ),

        // אייקון לוח שנה קטן
        Tooltip(
          message: 'פתח לוח שנה',
          child: InkWell(
            onTap: onCalendarTap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Icon(
                Icons.calendar_month_outlined,
                color: cs.secondary,
                size: 18,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
