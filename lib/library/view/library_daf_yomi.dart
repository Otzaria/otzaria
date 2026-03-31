import 'package:flutter/material.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/tools/calendar/helpers/calendar_date_helpers.dart';

/// ווידג'ט דף יומי — 2 מצבי תצוגה.
///
/// • [compact] = false (touch/ברירת מחדל):
///   אזור לחיצה אחד — טקסט בשתי שורות.
///
/// • [compact] = true (desktop):
///   גרסה דחוסה. כשיש מספיק רוחב ([inlineDate] = true) —
///   תאריך ודף מוצגים בשורה אחת (" • " ביניהם).
///   כשהמסך צר — מוצגים בשתי שורות קצרות.
///
/// **אחריות:**
/// • מציג תאריך עברי + דף יומי.
/// • פתיחת הדף היומי מטופלת דרך [onDafYomiTap].
/// • ניווט ללוח השנה הוא אחריות של הסרגל המכיל.
class LibraryDafYomi extends StatelessWidget {
  final Function(String tractate, String daf) onDafYomiTap;

  /// true = מצב desktop — גרסה דחוסה
  final bool compact;

  /// true = תאריך ודף באותה שורה (רלוונטי רק ב-compact)
  final bool inlineDate;

  /// רוחב מקסימלי של הווידג'ט (כדי למנוע overflow)
  final double? maxWidth;

  const LibraryDafYomi({
    super.key,
    required this.onDafYomiTap,
    this.compact = false,
    this.inlineDate = false,
    this.maxWidth,
  });

  static const _toolbarTextHeightBehavior = TextHeightBehavior(
    applyHeightToFirstAscent: false,
    applyHeightToLastDescent: false,
  );

  TextStyle _primaryTextStyle(
    BuildContext context, {
    required bool isCompact,
    required bool emphasized,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final baseStyle = (isCompact
            ? theme.textTheme.labelSmall
            : theme.textTheme.labelMedium) ??
        const TextStyle();
    return baseStyle.copyWith(
      color: cs.onSecondaryContainer,
      fontWeight: emphasized ? FontWeight.w700 : FontWeight.w500,
      fontSize: isCompact ? 11 : 12,
      height: 1.0,
    );
  }

  TextStyle _secondaryTextStyle(BuildContext context,
      {required bool isCompact}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final baseStyle =
        (isCompact ? theme.textTheme.labelSmall : theme.textTheme.bodySmall) ??
            const TextStyle();
    return baseStyle.copyWith(
      color: cs.onSecondaryContainer.withValues(alpha: 0.84),
      fontWeight: FontWeight.w400,
      fontSize: isCompact ? 10.5 : 11,
      height: 1.0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final Daf dafYomi = getDafYomi(DateTime.now());
    final tractate = dafYomi.getMasechta();
    final dafAmud = dafYomi.getDaf();
    final dafText = '$tractate ${formatAmud(dafAmud)}';
    final dateText = getHebrewDateFormattedAsString(DateTime.now());

    final Widget content = compact
        ? _buildCompact(context, dateText, dafText, tractate, dafAmud)
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

  Widget _buildStandard(
    BuildContext context,
    String dateText,
    String dafText,
    String tractate,
    int dafAmud,
  ) {
    final cs = Theme.of(context).colorScheme;
    final dateStyle =
        _primaryTextStyle(context, isCompact: true, emphasized: true);
    final dafStyle = _secondaryTextStyle(context, isCompact: true);

    return Container(
      decoration: BoxDecoration(
        color: cs.onSecondaryContainer.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Tooltip(
        message: 'פתח דף יומי',
        child: InkWell(
          onTap: () => onDafYomiTap(tractate, formatAmud(dafAmud)),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  dateText,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: dateStyle,
                  textDirection: TextDirection.rtl,
                  textHeightBehavior: _toolbarTextHeightBehavior,
                  strutStyle: StrutStyle.fromTextStyle(
                    dateStyle,
                    forceStrutHeight: true,
                    leading: 0,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'דף היומי: $dafText',
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: dafStyle,
                  textDirection: TextDirection.rtl,
                  textHeightBehavior: _toolbarTextHeightBehavior,
                  strutStyle: StrutStyle.fromTextStyle(
                    dafStyle,
                    forceStrutHeight: true,
                    leading: 0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Desktop / compact ────────────────────────────────────────────────────

  Widget _buildCompact(
    BuildContext context,
    String dateText,
    String dafText,
    String tractate,
    int dafAmud,
  ) {
    final dateStyle =
        _primaryTextStyle(context, isCompact: true, emphasized: true);
    final dafStyle = _secondaryTextStyle(context, isCompact: true);
    final inlineStyle =
        _primaryTextStyle(context, isCompact: true, emphasized: false);

    // תצוגה inline: תאריך • דף יומי בשורה אחת
    final textWidget = inlineDate
        ? Text(
            '$dateText  •  $dafText',
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: inlineStyle,
            textDirection: TextDirection.rtl,
            textHeightBehavior: _toolbarTextHeightBehavior,
            strutStyle: StrutStyle.fromTextStyle(
              inlineStyle,
              forceStrutHeight: true,
              leading: 0,
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                dateText,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: dateStyle,
                textDirection: TextDirection.rtl,
                textHeightBehavior: _toolbarTextHeightBehavior,
                strutStyle: StrutStyle.fromTextStyle(
                  dateStyle,
                  forceStrutHeight: true,
                  leading: 0,
                ),
              ),
              Text(
                dafText,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: dafStyle,
                textDirection: TextDirection.rtl,
                textHeightBehavior: _toolbarTextHeightBehavior,
                strutStyle: StrutStyle.fromTextStyle(
                  dafStyle,
                  forceStrutHeight: true,
                  leading: 0,
                ),
              ),
            ],
          );

    return Tooltip(
      message: 'פתח דף יומי: $dafText',
      child: InkWell(
        onTap: () => onDafYomiTap(tractate, formatAmud(dafAmud)),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: textWidget,
        ),
      ),
    );
  }
}
