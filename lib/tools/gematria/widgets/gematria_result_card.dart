import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/tools/gematria/models/gematria_search_result.dart';
import 'package:otzaria/utils/navigation/open_book.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/layout/tool_result_card_shell.dart';

class GematriaResultCard extends StatelessWidget {
  final int number;
  final GematriaSearchResult result;

  const GematriaResultCard({
    super.key,
    required this.number,
    required this.result,
  });

  void _copy(BuildContext context) {
    Clipboard.setData(
      ClipboardData(text: '${result.internalPath}\n${result.preview}'),
    );
    UiSnack.show(UiSnack.textCopied);
  }

  void _navigate(BuildContext context) {
    final book = TextBook(title: result.bookTitle);
    openBook(
      context,
      book,
      result.data.line - 1,
      result.preview,
      ignoreHistory: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ToolResultCardShell(
      outlined: true,
      padding: const EdgeInsets.all(AppTokens.spaceMD),
      bottomGap: AppTokens.spaceSM + AppTokens.spaceXS,
      child: BlocBuilder<SettingsBloc, SettingsState>(
        builder: (context, state) {
          String holy(String text) => state.replaceHolyNames
              ? utils.replaceHolyNames(text, style: state.holyNameStyle)
              : text;
          final displayPath = holy(
            result.internalPath.isNotEmpty
                ? result.internalPath
                : result.bookTitle,
          );
          final displayText = holy(result.preview);
          final before = holy(result.data.contextBefore);
          final after = holy(result.data.contextAfter);
          final faded = TextStyle(color: cs.onSurface.withValues(alpha: 0.45));

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _NumberBadge(number: number),
                  const SizedBox(width: AppTokens.spaceSM),
                  Expanded(
                    child: Text(
                      displayPath,
                      style: TextStyle(
                        fontSize: AppTokens.fontMD,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppTokens.spaceSM),
                  SecondaryIconButton(
                    icon: FluentIcons.copy_24_regular,
                    tooltip: 'העתק',
                    onPressed: () => _copy(context),
                  ),
                  const SizedBox(width: AppTokens.spaceXS),
                  PrimaryIconButton(onPressed: () => _navigate(context)),
                ],
              ),
              if (result.preview.isNotEmpty) ...[
                const SizedBox(height: AppTokens.spaceSM),
                Text.rich(
                  TextSpan(
                    style: TextStyle(
                      fontSize: state.fontSize,
                      fontFamily: AppFonts.renderFontFamily(state.fontFamily),
                      color: cs.onSurface,
                      height: 1.4,
                    ),
                    children: [
                      if (before.isNotEmpty)
                        TextSpan(text: '$before ', style: faded),
                      TextSpan(
                        text: displayText,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (after.isNotEmpty)
                        TextSpan(text: ' $after', style: faded),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

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
        borderRadius: AppTokens.borderRadiusAll,
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
