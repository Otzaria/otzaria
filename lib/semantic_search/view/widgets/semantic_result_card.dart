import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/view/tantivy_search_results.dart';
import 'package:otzaria/search_feedback/search_feedback_api.dart';
import 'package:otzaria/search_feedback/semantic_search_strings.dart';
import 'package:otzaria/semantic_search/models/semantic_result_item.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show MergedSibling, SemanticResultSource;

/// תווית מקור ההתאמה של [source].
String semanticSourceLabel(SemanticResultSource source) => switch (source) {
  SemanticResultSource.lexical => kSemanticSourceLexicalLabel,
  SemanticResultSource.semantic => kSemanticSourceSemanticLabel,
  SemanticResultSource.both => kSemanticSourceBothLabel,
};

/// כרטיס תוצאה של החיפוש הסמנטי, באותו מבנה של כרטיס החיפוש הרגיל.
class SemanticResultCard extends StatelessWidget {
  const SemanticResultCard({
    super.key,
    required this.item,
    required this.rank,
    required this.titleText,
    required this.snippetSpans,
    required this.vote,
    required this.isPreviewed,
    required this.groupIdenticalText,
    required this.onTap,
    required this.onKeyboardOpen,
    required this.onOpenInBackground,
    required this.onVote,
    required this.onCopy,
    required this.onOpenSibling,
    required this.onOpenSiblingInBackground,
    this.onDoubleTap,
    this.onPreviewSibling,
  });

  final SemanticResultItem item;
  final int rank;

  /// ההפניה לתצוגה (אחרי החלפת שמות קודש).
  final String titleText;
  final List<InlineSpan> snippetSpans;

  /// הסימון הנוכחי; `null` = לא סומן.
  final SearchFeedbackVote? vote;
  final bool isPreviewed;
  final bool groupIdenticalText;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback onKeyboardOpen;
  final VoidCallback onOpenInBackground;
  final ValueChanged<SearchFeedbackVote> onVote;
  final VoidCallback onCopy;
  final ValueChanged<MergedSibling> onOpenSibling;
  final ValueChanged<MergedSibling> onOpenSiblingInBackground;
  final ValueChanged<MergedSibling>? onPreviewSibling;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border.all(
          color: isPreviewed ? colorScheme.primary : colorScheme.outlineVariant,
          width: isPreviewed ? 1.5 : 1,
        ),
        borderRadius: AppTokens.borderRadiusAll,
      ),
      child: SearchResultOpenInNewTabRegion(
        onOpenInBackground: onOpenInBackground,
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.enter): onKeyboardOpen,
            const SingleActivator(LogicalKeyboardKey.numpadEnter):
                onKeyboardOpen,
          },
          child: InkWell(
            onTap: onTap,
            onDoubleTap: onDoubleTap,
            borderRadius: AppTokens.borderRadiusAll,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _RankBadge(rank: rank),
                  const SizedBox(width: 16),
                  Expanded(child: _buildContent(context)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (item.isPdf)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: Icon(
                  OtzariaIcons.book_pdf_24_regular,
                  size: 16,
                  color: colorScheme.primary,
                ),
              ),
            Expanded(
              child: Text(
                item.title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            SemanticSourceLabel(source: item.source),
            const SizedBox(width: 4),
            _VoteButton(
              key: ValueKey('semantic-like-$rank'),
              vote: SearchFeedbackVote.like,
              selected: vote == SearchFeedbackVote.like,
              onPressed: () => onVote(SearchFeedbackVote.like),
            ),
            _VoteButton(
              key: ValueKey('semantic-dislike-$rank'),
              vote: SearchFeedbackVote.dislike,
              selected: vote == SearchFeedbackVote.dislike,
              onPressed: () => onVote(SearchFeedbackVote.dislike),
            ),
            IconButton(
              icon: Icon(
                FluentIcons.copy_24_regular,
                size: 16,
                color: colorScheme.onSurfaceVariant,
              ),
              tooltip: context.settingsText('העתק טקסט'),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: onCopy,
            ),
          ],
        ),
        if (titleText.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              titleText,
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        const SizedBox(height: 8),
        RichText(
          textAlign: TextAlign.justify,
          text: TextSpan(
            style: TextStyle(
              fontSize: 16,
              color: colorScheme.onSurface,
              height: 1.5,
            ),
            children: snippetSpans,
          ),
        ),
        if (item.mergedCount > 1)
          MergedSiblingsSection(
            mergedCount: item.mergedCount,
            siblings: item.merged,
            groupingMode: groupIdenticalText
                ? ResultGroupingMode.identicalText
                : ResultGroupingMode.none,
            onOpenSibling: onOpenSibling,
            onOpenSiblingInBackground: onOpenSiblingInBackground,
            onPreviewSibling: onPreviewSibling,
          ),
      ],
    );
  }
}

/// תווית ניטרלית קטנה של מקור ההתאמה.
class SemanticSourceLabel extends StatelessWidget {
  const SemanticSourceLabel({super.key, required this.source});

  final SemanticResultSource source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        context.settingsText(semanticSourceLabel(source)),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 32),
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: AppTokens.borderRadiusAll,
      ),
      child: Center(
        widthFactor: 1,
        child: Text(
          '$rank',
          style: TextStyle(
            color: colorScheme.onPrimaryContainer,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}

class _VoteButton extends StatelessWidget {
  const _VoteButton({
    super.key,
    required this.vote,
    required this.selected,
    required this.onPressed,
  });

  final SearchFeedbackVote vote;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isLike = vote == SearchFeedbackVote.like;
    final IconData icon = switch ((isLike, selected)) {
      (true, true) => FluentIcons.thumb_like_24_filled,
      (true, false) => FluentIcons.thumb_like_24_regular,
      (false, true) => FluentIcons.thumb_dislike_24_filled,
      (false, false) => FluentIcons.thumb_dislike_24_regular,
    };
    return IconButton(
      isSelected: selected,
      icon: Icon(
        icon,
        size: 16,
        color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
      ),
      tooltip: context.settingsText(isLike ? 'אהבתי' : 'לא אהבתי'),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      onPressed: onPressed,
    );
  }
}
