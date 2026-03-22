import 'package:flutter/material.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/daf_yomi/calendar.dart';

/// ווידג'ט דף יומי ולוח שנה — 2 מצבי תצוגה.
///
/// • [compact] = false (touch/ברירת מחדל):
///   שני אזורי לחיצה — טקסט בשתי שורות + אייקון לוח שנה.
///
/// • [compact] = true (desktop):
///   גרסה דחוסה. כשיש מספיק רוחב ([inlineDate] = true) —
///   תאריך ודף מוצגים בשורה אחת (" • " ביניהם).
///   כשהמסך צר — מוצגים בשתי שורות קצרות.
///
/// כדי למנוע overflow: כל הטקסטים משתמשים ב-[TextOverflow.ellipsis]
/// ורוחב הווידג'ט מוגבל ע"י [maxWidth] (ברירת מחדל: 220).
class DafYomi extends StatelessWidget {
  final VoidCallback onCalendarTap;
  final Function(String tractate, String daf) onDafYomiTap;

  /// true = מצב desktop — גרסה דחוסה
  final bool compact;

  /// true = תאריך ודף באותה שורה (רלוונטי רק ב-compact)
  final bool inlineDate;

  /// רוחב מקסימלי של הווידג'ט (כדי למנוע overflow)
  final double? maxWidth;

  const DafYomi({
    super.key,
    required this.onCalendarTap,
    required this.onDafYomiTap,
    this.compact = false,
    this.inlineDate = false,
    this.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    final Daf dafYomi = getDafYomi(DateTime.now());
    final tractate = dafYomi.getMasechta();
    final dafAmud = dafYomi.getDaf();
    final dafText = '$tractate ${formatAmud(dafAmud)}';
    final dateText = getHebrewDateFormattedAsString(DateTime.now());

    final Widget content = compact
        ? _buildCompact(context, dateText, dafText)
        : _buildStandard(context, dateText, dafText, tractate, dafAmud);

    if (maxWidth != null) {
      return ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth!),
        child: content,
      );
    }
    return content;
  }

  // ── Touch / standard ────────────────────────────────────────────────────

  Widget _buildStandard(BuildContext context, String dateText, String dafText,
      String tractate, int dafAmud) {
    final cs = Theme.of(context).colorScheme;
    return IntrinsicHeight(
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // טקסטים — פותח דף יומי
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
                        dateText,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: TextStyle(
                          color: cs.secondary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                        textDirection: TextDirection.rtl,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'דף היומי: $dafText',
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: TextStyle(color: cs.secondary, fontSize: 11),
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
              color: cs.outline.withValues(alpha: 0.3),
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
                    color: cs.secondary,
                    size: 22,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Desktop / compact ────────────────────────────────────────────────────

  Widget _buildCompact(BuildContext context, String dateText, String dafText) {
    final cs = Theme.of(context).colorScheme;

    // תצוגה inline: תאריך • דף יומי בשורה אחת
    final textWidget = inlineDate
        ? Text(
            '$dateText  •  $dafText',
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: TextStyle(color: cs.secondary, fontSize: 11),
            textDirection: TextDirection.rtl,
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                dateText,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: TextStyle(
                  color: cs.secondary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
                textDirection: TextDirection.rtl,
              ),
              Text(
                dafText,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: TextStyle(color: cs.secondary, fontSize: 10),
                textDirection: TextDirection.rtl,
              ),
            ],
          );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // טקסט — פותח דף יומי
        Tooltip(
          message: 'פתח דף יומי: $dafText',
          child: InkWell(
            onTap: () {
              final Daf d = getDafYomi(DateTime.now());
              onDafYomiTap(d.getMasechta(), formatAmud(d.getDaf()));
            },
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: textWidget,
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
                size: 17,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
