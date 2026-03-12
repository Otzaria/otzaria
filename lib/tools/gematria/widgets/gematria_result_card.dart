// lib/tools/gematria/widgets/gematria_result_card.dart
//
// כרטיס תוצאת חיפוש גימטריה בודדת.
// הוצא מ-gematria_search_screen.dart לרכיב עצמאי.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/tools/gematria/models/gematria_search_result.dart';
import 'package:otzaria/utils/open_book.dart';
import 'package:otzaria/utils/text_manipulation.dart' as utils;

class GematriaResultCard extends StatelessWidget {
  final int number;
  final GematriaSearchResult result;

  const GematriaResultCard({
    super.key,
    required this.number,
    required this.result,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: AppTokens.spaceMD - 4),
      decoration: BoxDecoration(
        border: Border.all(
          color: cs.outline.withValues(alpha: 0.3),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(AppTokens.radiusMD),
      ),
      child: InkWell(
        onTap: () {
          final book = TextBook(title: result.bookTitle);
          openBook(
            context,
            book,
            result.data.line - 1,
            result.preview,
            ignoreHistory: true,
          );
        },
        borderRadius: BorderRadius.circular(AppTokens.radiusMD),
        hoverColor: cs.primaryContainer.withValues(alpha: 0.3),
        splashColor: cs.primaryContainer.withValues(alpha: 0.4),
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.spaceMD),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _NumberBadge(number: number),
              const SizedBox(width: AppTokens.spaceMD),
              Expanded(child: _CardContent(result: result)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Number badge (sequence number inside a coloured circle) ─────────────────

class _NumberBadge extends StatelessWidget {
  final int number;
  const _NumberBadge({required this.number});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(AppTokens.spaceSM),
      ),
      child: Center(
        child: Text(
          '$number',
          style: TextStyle(
            color: cs.onPrimaryContainer,
            fontWeight: FontWeight.bold,
            fontSize: AppTokens.fontLG,
          ),
        ),
      ),
    );
  }
}

// ─── Card content (path + rich text with context) ────────────────────────────

class _CardContent extends StatelessWidget {
  final GematriaSearchResult result;
  const _CardContent({required this.result});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, state) {
        String displayPath = result.internalPath.isNotEmpty
            ? result.internalPath
            : result.bookTitle;
        if (state.replaceHolyNames) {
          displayPath = utils.replaceHolyNames(displayPath);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              displayPath,
              style: TextStyle(
                fontSize: AppTokens.fontMD,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (result.preview.isNotEmpty) ...[
              const SizedBox(height: AppTokens.spaceSM),
              _RichPreview(result: result, state: state),
            ],
          ],
        );
      },
    );
  }
}

// ─── Rich text preview with context ──────────────────────────────────────────

class _RichPreview extends StatelessWidget {
  final GematriaSearchResult result;
  final SettingsState state;
  const _RichPreview({required this.result, required this.state});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    String displayText = result.preview;
    String contextBefore = result.data.contextBefore;
    String contextAfter = result.data.contextAfter;

    if (state.replaceHolyNames) {
      displayText = utils.replaceHolyNames(displayText);
      contextBefore = utils.replaceHolyNames(contextBefore);
      contextAfter = utils.replaceHolyNames(contextAfter);
    }

    final dimStyle = TextStyle(
      color: cs.onSurface.withValues(alpha: 0.4),
      fontWeight: FontWeight.w300,
    );

    return RichText(
      textAlign: TextAlign.right,
      text: TextSpan(
        style: TextStyle(
          fontSize: state.fontSize,
          fontFamily: state.fontFamily,
          color: cs.onSurface,
          height: 1.5,
        ),
        children: [
          if (contextBefore.isNotEmpty)
            TextSpan(text: '$contextBefore ', style: dimStyle),
          TextSpan(
            text: displayText,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: state.fontSize + 2,
            ),
          ),
          if (contextAfter.isNotEmpty)
            TextSpan(text: ' $contextAfter', style: dimStyle),
        ],
      ),
    );
  }
}
