import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/library/models/library_book_selection.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

// מתחת לרוחב הזה הטקסט והכפתורים לא נכנסים בשורה אחת.
const double _kSingleRowMinWidth = 400;

/// סרגל בתחתית רשימת הספרייה כשיש ספרים שנבחרו לפתיחה בבת אחת.
class LibrarySelectionBar extends StatelessWidget {
  final LibraryBookSelection selection;
  final VoidCallback onOpen;

  const LibrarySelectionBar({
    super.key,
    required this.selection,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: selection,
      builder: (context, _) {
        if (selection.isEmpty) return const SizedBox.shrink();
        final count = selection.length;
        final cs = Theme.of(context).colorScheme;
        // קורא מסך מכריז על שינוי המספר בכל בחירה.
        final label = Semantics(
          liveRegion: true,
          child: Text(
            count == 1
                ? context.settingsText('ספר אחד נבחר')
                : context.settingsText(
                    '{count} ספרים נבחרו',
                    args: {'count': count},
                  ),
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(color: cs.onSecondaryContainer),
          ),
        );
        final actions = [
          ActionButton.inline(
            text: context.settingsText('ביטול בחירה'),
            tooltip: context.settingsText('ביטול הבחירה (Esc)'),
            onPressed: selection.clear,
          ),
          ActionButton.recommended(
            text: context.settingsText('פתח נבחרים'),
            icon: FluentIcons.open_24_regular,
            onPressed: onOpen,
          ),
        ];
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTokens.spaceSMD,
            0,
            AppTokens.spaceSMD,
            AppTokens.spaceSM,
          ),
          child: Material(
            color: AppSurfaces.selectedRow(cs),
            elevation: AppTokens.elevation2,
            borderRadius: AppTokens.borderRadiusAll,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.spaceSMD,
                vertical: AppTokens.spaceSM,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // ברשימה צרה (תצוגה מקדימה פתוחה בחלון קטן) אין מקום לכל
                  // השורה: הטקסט למעלה והכפתורים מתחתיו, בשורה או בשתיים.
                  if (constraints.maxWidth < _kSingleRowMinWidth) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        label,
                        const SizedBox(height: AppTokens.spaceXS),
                        Wrap(
                          spacing: AppTokens.spaceSM,
                          runSpacing: AppTokens.spaceXS,
                          children: actions,
                        ),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: label),
                      actions[0],
                      const SizedBox(width: AppTokens.spaceSM),
                      actions[1],
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
