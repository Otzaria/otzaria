import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/widgets/layout/meta_chip.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/search/view/search_result_source_tag.dart';

/// שורת הכותרת בכרטיס תוצאה של ספק חיצוני: שם הספר, מספר המופעים בו, תגית
/// המקור וכפתור העתקת הגזיר.
///
/// הפריסה מיישרת את התגית ואת הכפתור לקצה השורה (הכותרת היא [Expanded]),
/// כדי שיישבו על אותו קו שבו הם יושבים בכרטיס של המנוע המובנה. שאר הרכיבים
/// אינם גמישים, ולכן כל אחד מהם מוגבל ברוחבו: שם המדור מגיע מהתוסף ואורכו
/// אינו ידוע מראש, וכיתוב המופעים מתקצר למספר בלבד בשורה צרה.
class ExternalResultTitleRow extends StatelessWidget {
  /// מתחת לרוחב הזה נשאר ממספר המופעים המספר בלבד.
  static const narrowWidth = 420.0;

  /// חלק הרוחב שתגית המקור לא תחרוג ממנו.
  static const _tagWidthFraction = 0.3;

  final String title;
  final int hitCount;
  final String sourceTag;

  /// גזיר הטקסט להעתקה; null כשעוד לא התקבל גזיר — ואז אין כפתור העתקה.
  final String? copyText;

  const ExternalResultTitleRow({
    super.key,
    required this.title,
    required this.hitCount,
    required this.sourceTag,
    this.copyText,
  });

  /// רוחב משבצת כפתור ההעתקה, כולל הרווח שלפניו. המשבצת נשמרת גם כשאין
  /// גזיר להעתיק, כדי שהתגיות של כל השורות יישבו על אותו קו.
  static const _copySlotWidth = 44.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // בשורה צרה אין מקום לשם הספר לצד כל השאר, ולכן המונה והתגית יורדים
        // לשורה משלהם במקום לכווץ את שם הספר לשתי אותיות.
        final compact = constraints.maxWidth < narrowWidth;
        if (!compact) {
          return Row(
            children: [
              Expanded(child: _buildTitle(context)),
              if (hitCount > 0) ...[
                const SizedBox(width: 8),
                _buildHitCountPill(context, compact: false),
              ],
              if (sourceTag.isNotEmpty) ...[
                const SizedBox(width: 8),
                _buildTag(constraints.maxWidth),
              ],
              _buildCopySlot(context),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: _buildTitle(context)),
                _buildCopySlot(context),
              ],
            ),
            if (hitCount > 0 || sourceTag.isNotEmpty)
              Row(
                children: [
                  if (hitCount > 0) _buildHitCountPill(context, compact: true),
                  const Spacer(),
                  if (sourceTag.isNotEmpty) _buildTag(constraints.maxWidth),
                ],
              ),
          ],
        );
      },
    );
  }

  Widget _buildTitle(BuildContext context) => Text(
    title,
    style: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.bold,
      color: Theme.of(context).colorScheme.primary,
    ),
    overflow: TextOverflow.ellipsis,
  );

  Widget _buildTag(double rowWidth) => ConstrainedBox(
    constraints: BoxConstraints(maxWidth: rowWidth * _tagWidthFraction),
    child: SearchResultSourceTag(label: sourceTag),
  );

  Widget _buildCopySlot(BuildContext context) {
    final text = copyText;
    if (text == null) return const SizedBox(width: _copySlotWidth);
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 4),
      child: _buildCopyButton(context, text),
    );
  }

  /// מספר המופעים בספר, לצד שמו: מספר עירום בקצה הכרטיס לא אמר מה הוא סופר.
  /// בשורה צרה נשאר המספר בלבד, עם הכיתוב המלא בהצבעה.
  Widget _buildHitCountPill(BuildContext context, {required bool compact}) {
    final label = hitCount == 1 ? 'תוצאה אחת בספר' : '$hitCount תוצאות בספר';
    return MetaChip(
      size: MetaChipSize.small,
      label: compact ? '$hitCount' : label,
      tooltip: label,
    );
  }

  /// העתקת גזיר הטקסט, כמו בכרטיס תוצאה של המנוע המובנה — הגזיר כבר בידינו,
  /// ואין סיבה שדווקא כאן יידרש לפתוח את הספר כדי להעתיק ממנו.
  Widget _buildCopyButton(BuildContext context, String snippet) {
    return IconButton(
      icon: Icon(
        FluentIcons.copy_24_regular,
        size: 16,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      tooltip: 'העתק טקסט',
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      onPressed: () {
        Clipboard.setData(ClipboardData(text: snippet));
        UiSnack.show(UiSnack.textCopied);
      },
    );
  }
}
