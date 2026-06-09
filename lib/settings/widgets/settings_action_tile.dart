import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';

/// שורת הגדרה עם אייקון, כותרת, תת-כותרת וכפתורי פעולה.
///
/// במסך רחב הכפתורים מוצגים ב-`trailing` של [ListTile]. במסך צר
/// (`<LayoutBreakpoints.compact`) הם עוברים לשורה תחת ה-subtitle.
class SettingsActionTile extends StatelessWidget {
  final IconData icon;
  final Widget title;
  final Widget subtitle;
  final List<Widget> actions;

  const SettingsActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actions,
  });

  SettingsActionTile.text({
    super.key,
    required this.icon,
    required String title,
    required String subtitle,
    TextDirection subtitleDirection = TextDirection.rtl,
    required this.actions,
  })  : title = Text(title, style: AppTextStyles.settingTitle),
        subtitle = Text(
          subtitle,
          style: AppTextStyles.settingSubtitle,
          textDirection: subtitleDirection,
          textAlign: subtitleDirection == TextDirection.ltr
              ? TextAlign.end
              : null,
        );

  /// קונסטרקטור ייעודי לנתיבי קבצים.
  /// מוסיף אוטומטית סימן LTR אחרי כל מפריד כדי למנוע שיבוש BiDi בנתיבים מעורבים.
  SettingsActionTile.path({
    super.key,
    required this.icon,
    required String title,
    required String? path,
    required String placeholder,
    required this.actions,
  })  : title = Text(title, style: AppTextStyles.settingTitle),
        subtitle = Text(
          (path != null && path.isNotEmpty) ? _formatPath(path) : placeholder,
          style: AppTextStyles.settingSubtitle,
          textDirection: (path != null && path.isNotEmpty)
              ? TextDirection.ltr
              : TextDirection.rtl,
          textAlign: (path != null && path.isNotEmpty) ? TextAlign.end : null,
        );

  static final RegExp _pathSeparatorRegExp = RegExp(r'[/\\]');

  static String _formatPath(String path) =>
      path.replaceAllMapped(_pathSeparatorRegExp, (m) => '${m[0]!}\u200E');

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < LayoutBreakpoints.compact;
        final actionsRow = Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: actions,
        );

        if (!isNarrow) {
          return ListTile(
            hoverColor: Colors.transparent,
            leading: Icon(icon),
            title: title,
            subtitle: subtitle,
            trailing: actionsRow,
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2, left: 16),
                    child: Icon(icon),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        title,
                        const SizedBox(height: 4),
                        subtitle,
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: actionsRow,
              ),
            ],
          ),
        );
      },
    );
  }
}
