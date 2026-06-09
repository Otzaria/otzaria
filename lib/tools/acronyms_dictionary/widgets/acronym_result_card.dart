// lib/tools/acronyms_dictionary/widgets/acronym_result_card.dart
//
// כרטיס תוצאה לפירוש ראשי תיבות.
//  • שורה אחת: ראשי תיבות | חץ | פירוש(ים) | כפתור העתקה
//  • SelectionArea → Ctrl+C / תפריט הקשר

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/misc/rtl_icon.dart';
import 'package:otzaria/widgets/layout/tool_result_card_shell.dart';

class AcronymResultCard extends StatelessWidget {
  final String acronym;
  final List<String> meanings;
  final bool isFocused;
  final VoidCallback? onTap;

  const AcronymResultCard({
    super.key,
    required this.acronym,
    required this.meanings,
    this.isFocused = false,
    this.onTap,
  });

  void _copy(BuildContext context) {
    final meaningsText = meanings
        .asMap()
        .entries
        .map((e) => meanings.length > 1 ? '${e.key + 1}. ${e.value}' : e.value)
        .join('\n');
    Clipboard.setData(ClipboardData(text: '$acronym\n$meaningsText'));
    UiSnack.show(UiSnack.textCopied);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ToolResultCardShell(
      isFocused: isFocused,
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              acronym,
              style: TextStyle(
                fontSize: AppTokens.fontLG,
                fontWeight: FontWeight.bold,
                color: cs.onSurface,
              ),
              textAlign: TextAlign.right,
              textDirection: TextDirection.rtl,
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: 10,
              end: 12,
            ),
            child: RtlIcon(
              FluentIcons.arrow_left_24_filled,
              size: 16,
              color: cs.primary,
            ),
          ),
          Expanded(
            child: meanings.length == 1
                ? Text(
                    meanings.first,
                    style: TextStyle(
                      fontSize: AppTokens.fontMD,
                      color: cs.onSurface,
                    ),
                    textAlign: TextAlign.right,
                    textDirection: TextDirection.rtl,
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: meanings.asMap().entries.map((e) {
                      return Text(
                        '${e.key + 1}. ${e.value}',
                        style: TextStyle(
                          fontSize: AppTokens.fontMD,
                          color: cs.onSurface,
                          height: 1.4,
                        ),
                        textAlign: TextAlign.right,
                        textDirection: TextDirection.rtl,
                      );
                    }).toList(),
                  ),
          ),
          const SizedBox(width: AppTokens.spaceXS),
          SecondaryIconButton(
              icon: FluentIcons.copy_24_regular,
              tooltip: 'העתק',
              onPressed: () => _copy(context)),
        ],
      ),
    );
  }
}
