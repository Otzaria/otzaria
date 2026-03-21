// lib/tools/aramaic_dictionary/widgets/aramaic_result_card.dart
//
// שינויים:
//  • שורה דקה: מקור | חץ | תרגום | כפתור העתקה
//  • SelectionArea → Ctrl+C / תפריט הקשר
//  • isFocused: הדגשה לניווט מקלדת

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/custom_ui_components.dart';
import 'package:otzaria/widgets/tool_result_card_shell.dart';

class AramaicResultCard extends StatelessWidget {
  final String aramaic;
  final String hebrew;
  final bool isHebrewToAramaic;
  final bool isFocused;
  final VoidCallback? onTap;

  const AramaicResultCard({
    super.key,
    required this.aramaic,
    required this.hebrew,
    required this.isHebrewToAramaic,
    this.isFocused = false,
    this.onTap,
  });

  void _copy(BuildContext context) {
    final srcLabel = isHebrewToAramaic ? 'עברית' : 'ארמית';
    final tgtLabel = isHebrewToAramaic ? 'ארמית' : 'עברית';
    final src = isHebrewToAramaic ? hebrew : aramaic;
    final tgt = isHebrewToAramaic ? aramaic : hebrew;
    Clipboard.setData(ClipboardData(text: '$srcLabel: $src\n$tgtLabel: $tgt'));
    UiSnack.show(UiSnack.textCopied);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sourceWord = isHebrewToAramaic ? hebrew : aramaic;
    final targetWord = isHebrewToAramaic ? aramaic : hebrew;

    return ToolResultCardShell(
      isFocused: isFocused,
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: SelectableText(
              sourceWord,
              style: TextStyle(
                fontSize: AppTokens.fontLG,
                fontWeight: FontWeight.bold,
                color: cs.onSurface,
              ),
              textAlign: TextAlign.right,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Icon(
              isHebrewToAramaic
                  ? FluentIcons.arrow_left_24_filled
                  : FluentIcons.arrow_right_24_filled,
              size: 16,
              color: cs.primary,
            ),
          ),
          Expanded(
            child: SelectableText(
              targetWord,
              style: TextStyle(
                fontSize: AppTokens.fontLG,
                fontWeight: FontWeight.w500,
                color: cs.onSurface,
              ),
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: AppTokens.spaceXS),
          ToolCopyButton(onPressed: () => _copy(context)),
        ],
      ),
    );
  }
}
