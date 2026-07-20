// lib/tools/aramaic_dictionary/widgets/aramaic_result_card.dart
//
// כרטיס תוצאה למילון ארמי-עברי.
//  • שורה אחת: מקור | חץ | תרגום | כפתור העתקה
//  • SelectionArea → Ctrl+C / תפריט הקשר

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/tools/dictionary/widgets/aramaic_dictionary_entry_view.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/misc/rtl_icon.dart';
import 'package:otzaria/widgets/layout/tool_result_card_shell.dart';

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
    final sourceIsHebrewDefinition = isHebrewToAramaic;
    final targetIsHebrewDefinition = !isHebrewToAramaic;

    return ToolResultCardShell(
      isFocused: isFocused,
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _DictionaryValue(
              value: sourceWord,
              isHebrewDefinition: sourceIsHebrewDefinition,
              textStyle: TextStyle(
                fontSize: AppTokens.fontLG,
                fontWeight: FontWeight.bold,
                color: cs.onSurface,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: 10,
              end: 12,
            ),
            child: RtlIcon(
              isHebrewToAramaic
                  ? FluentIcons.arrow_right_24_filled
                  : FluentIcons.arrow_left_24_filled,
              size: 16,
              color: cs.primary,
            ),
          ),
          Expanded(
            child: _DictionaryValue(
              value: targetWord,
              isHebrewDefinition: targetIsHebrewDefinition,
              textStyle: TextStyle(
                fontSize: AppTokens.fontLG,
                fontWeight: FontWeight.w500,
                color: cs.onSurface,
              ),
            ),
          ),
          const SizedBox(width: AppTokens.spaceXS),
          SecondaryIconButton(
            icon: FluentIcons.copy_24_regular,
            tooltip: 'העתק',
            onPressed: () => _copy(context),
          ),
        ],
      ),
    );
  }
}

class _DictionaryValue extends StatelessWidget {
  final String value;
  final bool isHebrewDefinition;
  final TextStyle textStyle;

  const _DictionaryValue({
    required this.value,
    required this.isHebrewDefinition,
    required this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    if (isHebrewDefinition) {
      return AramaicDictionaryEntryView(
        definition: value,
        compact: true,
      );
    }

    return Text(
      value,
      style: textStyle,
      textAlign: TextAlign.right,
    );
  }
}
