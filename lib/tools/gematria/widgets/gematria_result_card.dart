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
    return ToolResultCardShell(
      isFocused: isFocused,
      onTap: onTap,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cs = Theme.of(context).colorScheme;
          final isNarrow = constraints.maxWidth < 700;
          final reservedEndSpace = isNarrow ? 84.0 : 92.0;
          final topInset = isNarrow ? 6.0 : 8.0;

          return BlocBuilder<SettingsBloc, SettingsState>(
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

              String before = result.data.contextBefore;
              String after = result.data.contextAfter;
              if (state.replaceHolyNames) {
                before = utils.replaceHolyNames(before);
                after = utils.replaceHolyNames(after);
              }

              return ConstrainedBox(
                constraints: BoxConstraints(minHeight: isNarrow ? 56 : 72),
                child: Stack(
                  children: [
                    Padding(
                      padding: EdgeInsetsDirectional.only(
                        end: reservedEndSpace,
                        top: topInset,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _NumberBadge(number: number),
                          const SizedBox(width: AppTokens.spaceSM),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  displayPath,
                                  style: TextStyle(
                                    fontSize: AppTokens.fontSM,
                                    fontWeight: FontWeight.w500,
                                    color: cs.onSurfaceVariant,
                                  ),
                                  textAlign: TextAlign.right,
                                  maxLines: isNarrow ? null : 1,
                                ),
                                if (result.preview.isNotEmpty) ...[
                                  SizedBox(height: isNarrow ? 7 : 9),
                                  Text.rich(
                                    TextSpan(
                                      style: TextStyle(
                                        fontSize: state.fontSize - 1,
                                        fontFamily: state.fontFamily,
                                        color: cs.onSurface,
                                        height: isNarrow ? 1.28 : 1.22,
                                      ),
                                      children: [
                                        if (before.isNotEmpty)
                                          TextSpan(
                                            text: '$before ',
                                            style: TextStyle(
                                              color: cs.onSurface.withValues(
                                                alpha: 0.45,
                                              ),
                                            ),
                                          ),
                                        TextSpan(
                                          text: displayText,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        if (after.isNotEmpty)
                                          TextSpan(
                                            text: ' $after',
                                            style: TextStyle(
                                              color: cs.onSurface.withValues(
                                                alpha: 0.45,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    textAlign: TextAlign.right,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    PositionedDirectional(
                      end: 0,
                      top: 0,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SecondaryIconButton(
                            icon: FluentIcons.copy_24_regular,
                            tooltip: 'העתק',
                            onPressed: () => _copy(context),
                          ),
                          const SizedBox(width: 4),
                          PrimaryIconButton(
                            onPressed: () => _navigate(context),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
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
