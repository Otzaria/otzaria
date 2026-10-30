// lib/tools/acronyms_dictionary/widgets/acronym_result_card.dart
//
// כרטיס תוצאה לפירוש ראשי תיבות.
//  • במסך רחב: ראשי תיבות | פירוש(ים) | כפתור העתקה; במסך צר: הפירושים מתחת
//  • SelectionArea → Ctrl+C / תפריט הקשר

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/layout/tool_result_card_shell.dart';

class AcronymResultCard extends StatelessWidget {
  final String acronym;
  final List<String> meanings;

  const AcronymResultCard({
    super.key,
    required this.acronym,
    required this.meanings,
  });

  /// מתחת לרוחב הזה הפירושים יורדים מתחת לראשי התיבות.
  static const double _wideBreakpoint = 560;

  static const double _acronymColumnWidth = 160;

  /// Number of meanings above which they are laid out in two columns.
  static const int _twoColumnsFrom = 3;

  static const double _twoColumnsWidth = 440;

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
    final title = Text(
      acronym,
      style: TextStyle(
        fontSize: AppTokens.fontXL,
        fontWeight: FontWeight.w700,
        color: cs.onSurface,
      ),
    );
    final copy = SecondaryIconButton(
      icon: FluentIcons.copy_24_regular,
      tooltip: 'העתק',
      onPressed: () => _copy(context),
    );

    return ToolResultCardShell(
      outlined: true,
      padding: const EdgeInsets.all(AppTokens.spaceMD),
      bottomGap: AppTokens.spaceSM + AppTokens.spaceXS,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= _wideBreakpoint) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: _acronymColumnWidth, child: title),
                Expanded(child: _meanings(cs)),
                const SizedBox(width: AppTokens.spaceSM),
                copy,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: title),
                  const SizedBox(width: AppTokens.spaceSM),
                  copy,
                ],
              ),
              const SizedBox(height: AppTokens.spaceSM),
              _meanings(cs),
            ],
          );
        },
      ),
    );
  }

  Widget _meanings(ColorScheme cs) {
    final style = TextStyle(
      fontSize: AppTokens.fontMD,
      height: 1.5,
      color: cs.onSurface,
    );
    if (meanings.length == 1) {
      return Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(meanings.first, style: style),
      );
    }
    Widget item(int index, String meaning) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 24,
          child: Text(
            '${index + 1}.',
            style: style.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
        Expanded(child: Text(meaning, style: style)),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Long lists take two columns when there is room for them.
          final columns =
              meanings.length > _twoColumnsFrom &&
                  constraints.maxWidth >= _twoColumnsWidth
              ? 2
              : 1;
          final itemWidth =
              (constraints.maxWidth - AppTokens.spaceMD * (columns - 1)) /
              columns;
          return Wrap(
            spacing: AppTokens.spaceMD,
            runSpacing: AppTokens.spaceXS,
            children: [
              for (final (index, meaning) in meanings.indexed)
                SizedBox(width: itemWidth, child: item(index, meaning)),
            ],
          );
        },
      ),
    );
  }
}
