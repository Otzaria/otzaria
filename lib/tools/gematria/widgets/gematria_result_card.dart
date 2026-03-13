// lib/tools/gematria/widgets/gematria_result_card.dart
//
// שינויים:
//  • עיצוב דק — שורה אחת: מספר | נתיב + תצוגה | כפתור העתקה | כפתור ניווט
//  • SelectionArea → ניתן לסמן טקסט ולהעתיק Ctrl+C / תפריט הקשר
//  • isFocused: הדגשה ויזואלית עבור ניווט מקלדת ↑↓
//  • אין InkWell על כל הכרטיס

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/tools/gematria/models/gematria_search_result.dart';
import 'package:otzaria/utils/open_book.dart';
import 'package:otzaria/utils/text_manipulation.dart' as utils;
import 'package:otzaria/widgets/custom_ui_components.dart';

class GematriaResultCard extends StatelessWidget {
  final int number;
  final GematriaSearchResult result;
  final bool isFocused;
  final VoidCallback? onTap;

  const GematriaResultCard({
    super.key,
    required this.number,
    required this.result,
    this.isFocused = false,
    this.onTap,
  });

  void _copy(BuildContext context) {
    Clipboard.setData(
        ClipboardData(text: '${result.internalPath}\n${result.preview}'));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('הועתק ללוח'),
      duration: Duration(seconds: 1),
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _navigate(BuildContext context) {
    final book = TextBook(title: result.bookTitle);
    openBook(context, book, result.data.line - 1, result.preview,
        ignoreHistory: true);
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
                // ── מספר ──────────────────────────────────────────────────
                _NumberBadge(number: number),
                const SizedBox(width: AppTokens.spaceSM),
                // ── נתיב + תצוגה (Expanded) ───────────────────────────────
                Expanded(
                  child: BlocBuilder<SettingsBloc, SettingsState>(
                    builder: (context, state) {
                      String displayPath = result.internalPath.isNotEmpty
                          ? result.internalPath
                          : result.bookTitle;
                      if (state.replaceHolyNames) {
                        displayPath = utils.replaceHolyNames(displayPath);
                      }
                      String displayText = result.preview;
                      if (state.replaceHolyNames) {
                        displayText = utils.replaceHolyNames(displayText);
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // נתיב (קומפקטי)
                          SelectableText(
                            displayPath,
                            style: TextStyle(
                              fontSize: AppTokens.fontSM,
                              fontWeight: FontWeight.w500,
                              color: cs.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.right,
                            maxLines: 1,
                          ),
                          // טקסט
                          if (result.preview.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            _InlinePreview(
                              result: result,
                              state: state,
                              displayText: displayText,
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(width: AppTokens.spaceSM),
                // ── כפתורי פעולה (תמיד גלויים, בשורה) ───────────────────
                ToolCopyButton(onPressed: () => _copy(context)),
                const SizedBox(width: 4),
                ToolNavigateButton(onPressed: () => _navigate(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Number badge ─────────────────────────────────────────────────────────────
class _NumberBadge extends StatelessWidget {
  final int number;
  const _NumberBadge({required this.number});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Center(
        child: Text(
          '$number',
          style: TextStyle(
            color: cs.onPrimaryContainer,
            fontWeight: FontWeight.bold,
            fontSize: AppTokens.fontSM,
          ),
        ),
      ),
    );
  }
}

// ─── Inline preview (הקשר + ערך מודגש) ──────────────────────────────────────
class _InlinePreview extends StatelessWidget {
  final GematriaSearchResult result;
  final SettingsState state;
  final String displayText;
  const _InlinePreview({
    required this.result,
    required this.state,
    required this.displayText,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    String before = result.data.contextBefore;
    String after = result.data.contextAfter;
    if (state.replaceHolyNames) {
      before = utils.replaceHolyNames(before);
      after = utils.replaceHolyNames(after);
    }

    return SelectableText.rich(
      TextSpan(
        style: TextStyle(
          fontSize: state.fontSize - 1,
          fontFamily: state.fontFamily,
          color: cs.onSurface,
          height: 1.4,
        ),
        children: [
          if (before.isNotEmpty)
            TextSpan(
              text: '$before ',
              style: TextStyle(color: cs.onSurface.withValues(alpha: 0.45)),
            ),
          TextSpan(
            text: displayText,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          if (after.isNotEmpty)
            TextSpan(
              text: ' $after',
              style: TextStyle(color: cs.onSurface.withValues(alpha: 0.45)),
            ),
        ],
      ),
      textAlign: TextAlign.right,
      maxLines: 2,
    );
  }
}
