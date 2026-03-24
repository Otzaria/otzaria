import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/daf_yomi/calendar.dart';
import 'package:otzaria/widgets/buttons/action_buttons.dart';

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
/// **שינויים:**
/// • הסגנון נלקח מברירות המחדל של AppTopBar.
/// • כפתור לוח שנה משתמש ב-ToolbarActionButton לאחידות מול שאר הסרגל.
/// • רק התאריך מודגש; טקסט הדף נשאר רגיל.
/// • מצב דו־שורי במסך מגע משתמש ב-TextTheme של הסרגל למניעת רינדור מטושטש.
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
    final dividerColor = cs.onSecondaryContainer.withValues(alpha: 0.22);
    final dateStyle =
        _primaryTextStyle(context, isCompact: true, emphasized: true);
    final dafStyle = _secondaryTextStyle(context, isCompact: true);

    return Container(
      decoration: BoxDecoration(
        color: cs.onSecondaryContainer.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── אזור טקסט — פותח דף יומי ──────────────────────────────────
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
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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

          // ── מפריד ──────────────────────────────────────────────────────
          Container(
            width: 1,
            height: 20,
            color: dividerColor,
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ToolbarActionButton(
              tooltip: 'פתח לוח שנה',
              icon: FluentIcons.calendar_24_regular,
              compact: false,
              emphasis: ToolbarActionButtonEmphasis.subtle,
              onPressed: onCalendarTap,
            ),
          ),
        ],
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

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // ── טקסט — פותח דף יומי ──────────────────────────────────────
        Tooltip(
          message: 'פתח דף יומי: $dafText',
          child: InkWell(
            onTap: () => onDafYomiTap(tractate, formatAmud(dafAmud)),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: textWidget,
            ),
          ),
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: ToolbarActionButton(
            tooltip: 'פתח לוח שנה',
            icon: FluentIcons.calendar_24_regular,
            compact: true,
            emphasis: ToolbarActionButtonEmphasis.subtle,
            onPressed: onCalendarTap,
          ),
        ),
      ],
    );
  }
}
