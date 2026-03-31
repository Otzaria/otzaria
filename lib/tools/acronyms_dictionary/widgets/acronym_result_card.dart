// lib/tools/acronyms_dictionary/widgets/acronym_result_card.dart
//
// שינויים:
//  • שורה דקה: ראשי תיבות | חץ | פירוש(ים) | כפתור העתקה
//  • SelectionArea → Ctrl+C / תפריט הקשר
//  • isFocused: הדגשה לניווט מקלדת

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/custom_ui_components.dart';

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

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: isFocused
              ? cs.primaryContainer.withValues(alpha: 0.45)
              : toolCardColor(context),
          borderRadius: BorderRadius.circular(AppTokens.radiusMD),
          border: isFocused ? Border.all(color: cs.primary, width: 1.5) : null,
        ),
        child: SelectionArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.spaceMD,
              vertical: AppTokens.spaceSM,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // ── ראשי תיבות ────────────────────────────────────────────
                SizedBox(
                  width: 60,
                  child: SelectableText(
                    acronym,
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
                  child: Icon(Icons.arrow_back, size: 16, color: cs.primary),
                ),
                // ── פירוש(ים) ────────────────────────────────────────────
                Expanded(
                  child: meanings.length == 1
                      ? SelectableText(
                          meanings.first,
                          style: TextStyle(
                            fontSize: AppTokens.fontMD,
                            color: cs.onSurface,
                          ),
                          textAlign: TextAlign.right,
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: meanings.asMap().entries.map((e) {
                            return SelectableText(
                              '${e.key + 1}. ${e.value}',
                              style: TextStyle(
                                fontSize: AppTokens.fontSM,
                                color: cs.onSurface,
                                height: 1.4,
                              ),
                              textAlign: TextAlign.right,
                            );
                          }).toList(),
                        ),
                ),
                const SizedBox(width: AppTokens.spaceXS),
                // ── כפתור העתקה ─────────────────────────────────────────
                ToolCopyButton(onPressed: () => _copy(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
