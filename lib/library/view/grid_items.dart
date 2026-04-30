import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/widgets/data_source_indicator.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/services/book_details_service.dart';
import 'package:otzaria/text_book/view/book_source_dialog.dart';
import 'package:otzaria/widgets/app_menu.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:math';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/data/book_locator.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/widgets/dialogs/dialogs_exports.dart';

// ΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפא
//  ╫⌐╫ש╫á╫ץ╫ש╫ש╫¥:
//  Γאó ╫₧╫ס╫á╫פ Row: LTR ╫ó╫¥ icons ╫₧╫⌐╫₧╫נ╫£, ╫ר╫º╫í╫ר ╫₧╫ש╫₧╫ש╫ƒ (╫₧╫¬╫נ╫ש╫¥ ╫£-RTL UI).
//  Γאó ╫ª╫ס╫ó╫ש ╫ר╫º╫í╫ר: cs.onSurface ╫£╫¢╫ץ╫¬╫¿╫¬ ╫í╫ñ╫¿╫ש╫¥ (╫º╫¿╫ש╫נ ╫ס╫פ╫ש╫¿/╫¢╫פ╫פ), cs.primary ╫£╫¬╫ש╫º╫ש╫ץ╫¬.
//  Γאó ╫¿╫º╫ó ╫נ╫ש╫ש╫º╫ץ╫ƒ: cs.primary/secondary.withValues(alpha:0.12) Γאפ ╫ס╫ר╫ץ╫ק ╫ס╫פ╫ש╫¿+╫¢╫פ╫פ.
//  Γאó ╫נ╫ש╫ש╫º╫ץ╫ƒ ╫ס╫¢╫¿╫ר╫ש╫í: 32├ק32 container, 16px icon Γאפ ╫ñ╫¿╫ץ╫ñ╫ץ╫¿╫ª╫ש╫פ ╫ר╫ץ╫ס╫פ ╫ש╫ץ╫¬╫¿.
//  Γאó ╫¿╫ש╫ñ╫ץ╫ף ╫ó╫£╫ש╫ץ╫ƒ ╫ס-MyGridView: top: 8 Γאפ ╫¿╫ש╫ק╫ץ╫º ╫₧╫פ╫í╫¿╫ע╫£.
//  Γאó Focus ╫á╫ש╫ץ╫ץ╫ר ╫₧╫º╫£╫ף╫¬: CategoryGridItem + BookGridItem ╫¬╫ץ╫₧╫¢╫ש╫¥ ╫ס-Focus.
//  Γאó overflow: ellipsis + tooltip ╫ס╫¿╫ש╫ק╫ץ╫ú ╫ס╫¢╫£ ╫ר╫º╫í╫ר╫ש╫¥.
// ΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפא

TextStyle? _boldBodyStyle(BuildContext context) {
  return Theme.of(context).textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w600,
      );
}

TextStyle? _linkBodyStyle(BuildContext context) {
  final theme = Theme.of(context);
  return theme.textTheme.bodyMedium?.copyWith(
    color: theme.colorScheme.primary,
    decoration: TextDecoration.underline,
  );
}

TextStyle? _mutedBodyStyle(BuildContext context) {
  return Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurface,
      );
}

bool _textOverflows({
  required BuildContext context,
  required String text,
  required TextStyle style,
  required int maxLines,
  required double maxWidth,
  required TextDirection textDirection,
  required TextAlign textAlign,
}) {
  final textPainter = TextPainter(
    text: TextSpan(text: text, style: style),
    maxLines: maxLines,
    ellipsis: 'Γאª',
    textDirection: textDirection,
    textAlign: textAlign,
    textScaler: MediaQuery.textScalerOf(context),
  )..layout(maxWidth: maxWidth);

  return textPainter.didExceedMaxLines;
}

Decoration _libraryTooltipDecoration(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return BoxDecoration(
    color: cs.surfaceContainerHigh,
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.65)),
  );
}

TextStyle _libraryTooltipTextStyle(BuildContext context) {
  final theme = Theme.of(context);
  return (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
    color: theme.colorScheme.onSurface,
    fontSize: 14,
    height: 1.3,
  );
}

class LibraryOverflowTooltipText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final int maxLines;
  final TextAlign textAlign;
  final TextDirection? textDirection;

  const LibraryOverflowTooltipText({
    super.key,
    required this.text,
    this.style,
    this.maxLines = 2,
    this.textAlign = TextAlign.right,
    this.textDirection,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedStyle = style ?? DefaultTextStyle.of(context).style;
    final resolvedDirection = textDirection ?? Directionality.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final hasOverflow = constraints.maxWidth.isFinite &&
            constraints.maxWidth > 0 &&
            _textOverflows(
              context: context,
              text: text,
              style: resolvedStyle,
              maxLines: maxLines,
              maxWidth: constraints.maxWidth,
              textDirection: resolvedDirection,
              textAlign: textAlign,
            );

        final child = Text(
          text,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          textAlign: textAlign,
          textDirection: resolvedDirection,
          style: resolvedStyle,
        );

        if (!hasOverflow) {
          return child;
        }

        return Tooltip(
          message: text,
          waitDuration: const Duration(milliseconds: 300),
          preferBelow: false,
          verticalOffset: 18,
          textAlign: TextAlign.right,
          textStyle: _libraryTooltipTextStyle(context),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          margin: const EdgeInsets.all(12),
          constraints: const BoxConstraints(maxWidth: 260),
          decoration: _libraryTooltipDecoration(context),
          child: child,
        );
      },
    );
  }
}

class LibraryItemTitle extends StatelessWidget {
  final String text;
  final bool isFolder;
  final int maxLines;

  const LibraryItemTitle({
    super.key,
    required this.text,
    required this.isFolder,
    this.maxLines = 2,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LibraryOverflowTooltipText(
      text: text,
      maxLines: maxLines,
      textAlign: TextAlign.right,
      textDirection: TextDirection.rtl,
      style: theme.textTheme.titleMedium?.copyWith(
        fontWeight: isFolder ? FontWeight.w700 : FontWeight.w600,
        color:
            theme.textTheme.titleMedium?.color ?? theme.colorScheme.onSurface,
      ),
    );
  }
}

class HeaderItem extends StatelessWidget {
  final Category category;

  const HeaderItem({
    super.key,
    required this.category,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Text(
        category.title,
        textDirection: TextDirection.rtl,
        style: theme.textTheme.titleMedium?.copyWith(
          color: theme.colorScheme.secondary,
        ),
      ),
    );
  }
}

// ΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפא
//  CategoryGridItem
//  Layout LTR: [info-icon?] [folder-icon] [12px] [Expanded text (right-aligned)]
//  ╫ס╫¬╫ª╫ץ╫ע╫¬ RTL: ╫ר╫º╫í╫ר ╫₧╫ש╫₧╫ש╫ƒ, ╫נ╫ש╫ש╫º╫ץ╫á╫ש╫¥ ╫₧╫⌐╫₧╫נ╫£ Γאפ ╫ó╫º╫ס╫ש ╫ץ╫ס╫£╫¬╫ש ╫¬╫£╫ץ╫ש╫ש╫¥.
// ΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפא

class CategoryGridItem extends StatelessWidget {
  final Category category;
  final VoidCallback onCategoryClickCallback;
  final FocusNode? focusNode;

  const CategoryGridItem({
    super.key,
    required this.category,
    required this.onCategoryClickCallback,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Card(
      elevation: 0,
      color: AppSurfaces.card(context),
      clipBehavior: Clip.antiAlias,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        side: BorderSide.none,
        borderRadius: BorderRadius.all(Radius.circular(AppTokens.radiusXL)),
      ),
      child: InkWell(
        focusNode: focusNode,
        mouseCursor: SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(AppTokens.radiusXL),
        hoverColor: cs.primary.withValues(alpha: 0.06),
        hoverDuration: Durations.medium1,
        onTap: () => onCategoryClickCallback(),
        // Focus: Enter/Space Γזנ ╫₧╫ר╫ץ╫ñ╫£╫ש╫¥ ╫נ╫ץ╫ר╫ץ╫₧╫ר╫ש╫¬ ╫ó"╫ש InkWell
        // Arrow keys: ╫á╫₧╫í╫¿╫ש╫¥ ╫£╫פ╫ץ╫¿╫פ (grid) ╫ף╫¿╫ת bubble
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            // LTR: ╫נ╫ש╫ש╫º╫ץ╫á╫ש╫¥ ╫ס╫⌐╫₧╫נ╫£, ╫ר╫º╫í╫ר ╫ס╫ש╫₧╫ש╫ƒ Γאפ ╫₧╫¬╫נ╫ש╫¥ ╫£╫₧╫₧╫⌐╫º RTL ╫ó╫ס╫¿╫ש
            textDirection: TextDirection.rtl,
            children: [
              // ΓפאΓפא ╫נ╫ש╫ש╫º╫ץ╫ƒ ╫₧╫ש╫ף╫ó (╫⌐╫₧╫נ╫£ ╫º╫ש╫ª╫ץ╫á╫ש) ΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפא
              if (category.shortDescription.isNotEmpty)
                Tooltip(
                  message: category.shortDescription,
                  waitDuration: const Duration(milliseconds: 400),
                  child: Icon(
                    FluentIcons.info_24_regular,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.6),
                  ),
                ),
              // ΓפאΓפא ╫נ╫ש╫ש╫º╫ץ╫ƒ ╫¬╫ש╫º╫ש╫ש╫פ ΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפא
              const SizedBox(width: 4),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  FluentIcons.folder_24_filled,
                  color: cs.onSurfaceVariant,
                  size: 16,
                ),
              ),
              const SizedBox(width: 18),
              // ΓפאΓפא ╫ó╫₧╫ץ╫ף╫¬ ╫ר╫º╫í╫ר (╫ש╫₧╫ש╫ƒ) ΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפא
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      LibraryItemTitle(
                        text: category.title,
                        isFolder: true,
                      ),
                      if (category.shortDescription.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        LibraryOverflowTooltipText(
                          text: category.shortDescription,
                          maxLines: 2,
                          textAlign: TextAlign.right,
                          textDirection: TextDirection.rtl,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפא
//  BookGridItem
//  Layout LTR: [action-col] [media-col] [12px] [Expanded text (right-aligned)]
//  ╫ס╫¬╫ª╫ץ╫ע╫¬ RTL: ╫ר╫º╫í╫ר ╫₧╫ש╫₧╫ש╫ƒ, ╫נ╫ש╫ש╫º╫ץ╫á╫ש╫¥ ╫₧╫⌐╫₧╫נ╫£ Γאפ ╫ó╫º╫ס╫ש ╫ץ╫ס╫£╫¬╫ש ╫¬╫£╫ץ╫ש╫ש╫¥.
// ΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפא

class BookGridItem extends StatelessWidget {
  final bool showTopics;
  final Book book;
  final VoidCallback onBookClickCallback;
  final VoidCallback? onBookDeleted;
  final FocusNode? focusNode;

  const BookGridItem({
    super.key,
    required this.book,
    required this.onBookClickCallback,
    this.showTopics = false,
    this.onBookDeleted,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return GestureDetector(
      child: Card(
        elevation: 0,
        color: AppSurfaces.card(context),
        clipBehavior: Clip.antiAlias,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          side: BorderSide.none,
          borderRadius: BorderRadius.all(Radius.circular(AppTokens.radiusXL)),
        ),
        child: InkWell(
          focusNode: focusNode,
          mouseCursor: SystemMouseCursors.click,
          borderRadius: BorderRadius.circular(AppTokens.radiusXL),
          hoverColor: cs.primary.withValues(alpha: 0.06),
          onTap: () => onBookClickCallback(),
          hoverDuration: Durations.medium1,
          child: SizedBox.expand(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                // LTR: action column Γזע media column Γזע text column
                textDirection: TextDirection.rtl,
                children: [
                  // ΓפאΓפא ╫ó╫₧╫ץ╫ף╫¬ ╫ñ╫ó╫ץ╫£╫ץ╫¬ (╫⌐╫₧╫נ╫£ ╫º╫ש╫ª╫ץ╫á╫ש) ΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפא
                  _BookGridActionColumn(
                    book: book,
                    onBookDeleted: onBookDeleted,
                  ),
                  const SizedBox(width: 6),
                  // ΓפאΓפא ╫ó╫₧╫ץ╫ף╫¬ ╫₧╫ף╫ש╫פ (╫נ╫ש╫ש╫º╫ץ╫ƒ ╫í╫ñ╫¿) ΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפא
                  _BookGridMediaColumn(book: book, showTopics: showTopics),
                  const SizedBox(width: 18),
                  // ΓפאΓפא ╫ó╫₧╫ץ╫ף╫¬ ╫ר╫º╫í╫ר (╫ש╫₧╫ש╫ƒ) ΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפא
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _BookGridTextColumn(
                        book: book,
                        showTopics: showTopics,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BookGridMediaColumn extends StatelessWidget {
  final Book book;
  final bool showTopics;

  const _BookGridMediaColumn({
    required this.book,
    required this.showTopics,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    // ╫נ╫ש╫ש╫º╫ץ╫ƒ ╫º╫ר╫ƒ ╫ש╫ץ╫¬╫¿: 32├ק32 container, 16px icon Γאפ ╫ñ╫¿╫ץ╫ñ╫ץ╫¿╫ª╫ש╫פ ╫ר╫ץ╫ס╫פ ╫£╫ª╫ף ╫ר╫º╫í╫ר
    const double iconBoxSize = 32.0;
    const double iconSize = 16.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: iconBoxSize,
          height: iconBoxSize,
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: (book is PdfBook || book.fileType == 'pdf')
                ? Icon(
                    FluentIcons.document_pdf_24_regular,
                    color: cs.onSurfaceVariant,
                    size: iconSize,
                  )
                : book is ExternalLibraryBook
                    ? Image.asset(
                        (book as ExternalLibraryBook)
                                .link
                                .toString()
                                .contains('tablet.otzar.org')
                            ? 'assets/logos/otzar.ico'
                            : 'assets/logos/hebrew_books.png',
                        width: iconSize,
                        height: iconSize,
                        fit: BoxFit.contain,
                      )
                    : Icon(
                        book.fileType == 'docx'
                            ? FluentIcons.document_one_page_24_regular
                            : FluentIcons.document_text_24_regular,
                        color: cs.onSurfaceVariant,
                        size: iconSize,
                      ),
          ),
        ),
        if (kDebugMode && book is TextBook) ...[
          const SizedBox(height: 4),
          DataSourceIndicatorAsync(
            sourceFuture: FileSystemData.instance.getBookDataSource(
              book.title,
              categoryId: book.categoryId,
              fileType: book.fileType,
            ),
            size: 14,
          ),
        ],
      ],
    );
  }
}

class _BookGridTextColumn extends StatelessWidget {
  final Book book;
  final bool showTopics;

  const _BookGridTextColumn({
    required this.book,
    required this.showTopics,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // ╫¢╫ץ╫¬╫¿╫¬: onSurface Γאפ ╫º╫¿╫ש╫נ ╫ס╫⌐╫á╫ש ╫פ╫₧╫ª╫ס╫ש╫¥ (╫£╫נ primary ╫⌐╫ש╫¢╫ץ╫£ ╫£╫פ╫ש╫ץ╫¬ ╫ס╫ץ╫פ╫º ╫ס╫¢╫פ╫פ)
    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
      color: theme.colorScheme.onSurface,
    );
    final authorStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final topicsStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.primary.withValues(alpha: 0.85),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final titleOverflow = titleStyle != null &&
            constraints.maxWidth.isFinite &&
            constraints.maxWidth > 0 &&
            _textOverflows(
              context: context,
              text: book.title,
              style: titleStyle,
              maxLines: 2,
              maxWidth: constraints.maxWidth,
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.right,
            );

        final authorMaxLines = titleOverflow ? 1 : 2;
        final hasAuthor = (book.author ?? '').isNotEmpty;
        final hasTopics = showTopics && book.topics.trim().isNotEmpty;
        final topicsMaxLines = !hasTopics
            ? 0
            : constraints.maxHeight < 110
                ? 1
                : constraints.maxHeight < 140 || hasAuthor || titleOverflow
                    ? 2
                    : 3;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.max,
          children: [
            LibraryOverflowTooltipText(
              text: book.title,
              maxLines: 2,
              textAlign: TextAlign.justify,
              textDirection: TextDirection.rtl,
              style: titleStyle,
            ),
            if (hasAuthor) ...[
              const SizedBox(height: 3),
              LibraryOverflowTooltipText(
                text: book.author!,
                maxLines: authorMaxLines,
                textAlign: TextAlign.justify,
                textDirection: TextDirection.rtl,
                style: authorStyle,
              ),
            ],
            if (hasTopics) ...[
              const Spacer(),
              LibraryOverflowTooltipText(
                text: book.topics,
                maxLines: topicsMaxLines,
                textAlign: TextAlign.justify,
                textDirection: TextDirection.rtl,
                style: topicsStyle,
              ),
            ],
          ],
        );
      },
    );
  }
}

class _BookGridActionColumn extends StatelessWidget {
  final Book book;
  final VoidCallback? onBookDeleted;

  const _BookGridActionColumn({
    required this.book,
    required this.onBookDeleted,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FutureBuilder<String>(
          future: FileSystemData.instance.getBookDataSource(
            book.title,
            categoryId: book.categoryId,
            fileType: book.fileType,
          ),
          builder: (context, snapshot) {
            if (snapshot.data != 'DB') {
              return const SizedBox.shrink();
            }

            return SizedBox(
              width: 28,
              height: 28,
              child: AppPopupMenuButton<String>(
                icon: Icon(
                  FluentIcons.more_vertical_24_regular,
                  size: 15,
                  color: theme.colorScheme.secondary,
                ),
                tooltip: 'אפשרויות נוספות',
                position: PopupMenuPosition.under,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 28,
                  minHeight: 28,
                ),
                onSelected: (value) {
                  if (value == 'delete') {
                    _showDeleteBookDialog(context, book, onBookDeleted);
                  }
                },
                entries: const [
                  AppMenuEntry<String>(
                    value: 'delete',
                    label: 'מחק מה-DB',
                    icon: FluentIcons.delete_24_regular,
                    isDestructive: true,
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

// ΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפא
//  MyGridView
//  Γאó ╫¿╫ש╫ñ╫ץ╫ף top: 8 Γאפ ╫¿╫ש╫ק╫ץ╫ú ╫₧╫פ╫í╫¿╫ע╫£
//  Γאó FocusTraversalGroup Γאפ ╫á╫ש╫ץ╫ץ╫ר Tab ╫ס╫¬╫ץ╫ת ╫פ╫ע╫¿╫ש╫ף ╫ס╫£╫ס╫ף (╫£╫נ ╫º╫ץ╫ñ╫Ñ ╫£╫⌐╫ץ╫¿╫¬ ╫ק╫ש╫ñ╫ץ╫⌐)
// ΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפא

class MyGridView extends StatelessWidget {
  final List<Widget> items;

  const MyGridView({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1.0);
        final width = constraints.maxWidth;
        final baseRatio = width >= 1400
            ? 2.1
            : width >= 1100
                ? 1.95
                : width >= 800
                    ? 1.8
                    : 1.65;
        final textAdjustment =
            textScale <= 1.0 ? 1.0 : (1.0 / (1.0 + ((textScale - 1.0) * 0.65)));
        final childAspectRatio = (baseRatio * textAdjustment).clamp(1.45, 2.15);

        return FocusTraversalGroup(
          policy: ReadingOrderTraversalPolicy(),
          child: Padding(
            // top: 8 Γאפ ╫¿╫ש╫ק╫ץ╫ú ╫₧╫פ╫í╫¿╫ע╫£; horizontal: 45 Γאפ ╫⌐╫ץ╫£╫ש ╫ª╫ף
            padding:
                const EdgeInsets.only(top: 8, left: 45, right: 45, bottom: 0),
            child: GridView.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: max(1, min(constraints.maxWidth ~/ 250, 5)),
                childAspectRatio: childAspectRatio,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: items.length,
              itemBuilder: (context, index) => items[index],
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
            ),
          ),
        );
      },
    );
  }
}

/// ╫פ╫ª╫ע╫¬ ╫ק╫£╫ץ╫ƒ ╫₧╫ש╫ף╫ó ╫ó╫ס╫ץ╫¿ ╫í╫ñ╫¿
// ignore: unused_element
void _showBookInfoDialog(BuildContext context, Book book) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text(
          book.title,
          textAlign: TextAlign.right,
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (book.author != null && book.author!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: RichText(
                    textAlign: TextAlign.right,
                    text: TextSpan(
                      style: DefaultTextStyle.of(context).style,
                      children: [
                        TextSpan(
                          text: '╫₧╫ק╫ס╫¿: ',
                          style: _boldBodyStyle(context),
                        ),
                        TextSpan(text: book.author),
                      ],
                    ),
                  ),
                ),
              if (book.heCategories != null && book.heCategories!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: RichText(
                    textAlign: TextAlign.right,
                    text: TextSpan(
                      style: DefaultTextStyle.of(context).style,
                      children: [
                        TextSpan(
                          text: '╫º╫ר╫ע╫ץ╫¿╫ש╫פ: ',
                          style: _boldBodyStyle(context),
                        ),
                        TextSpan(text: book.heCategories),
                      ],
                    ),
                  ),
                ),
              if (book.heEra != null && book.heEra!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: RichText(
                    textAlign: TextAlign.right,
                    text: TextSpan(
                      style: DefaultTextStyle.of(context).style,
                      children: [
                        TextSpan(
                          text: '╫¬╫º╫ץ╫ñ╫פ: ',
                          style: _boldBodyStyle(context),
                        ),
                        TextSpan(text: book.heEra),
                      ],
                    ),
                  ),
                ),
              if ((book.compDateStringHe != null &&
                      book.compDateStringHe!.isNotEmpty) ||
                  (book.compPlaceStringHe != null &&
                      book.compPlaceStringHe!.isNotEmpty))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: RichText(
                    textAlign: TextAlign.right,
                    text: TextSpan(
                      style: DefaultTextStyle.of(context).style,
                      children: [
                        TextSpan(
                          text: '╫ק╫ש╫ס╫ץ╫¿: ',
                          style: _boldBodyStyle(context),
                        ),
                        TextSpan(
                          text: [
                            if (book.compPlaceStringHe != null &&
                                book.compPlaceStringHe!.isNotEmpty)
                              book.compPlaceStringHe,
                            if (book.compDateStringHe != null &&
                                book.compDateStringHe!.isNotEmpty)
                              book.compDateStringHe,
                          ].where((s) => s != null && s.isNotEmpty).join(', '),
                        ),
                      ],
                    ),
                  ),
                ),
              if ((book.pubDateStringHe != null &&
                      book.pubDateStringHe!.isNotEmpty) ||
                  (book.pubPlaceStringHe != null &&
                      book.pubPlaceStringHe!.isNotEmpty))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: RichText(
                    textAlign: TextAlign.right,
                    text: TextSpan(
                      style: DefaultTextStyle.of(context).style,
                      children: [
                        TextSpan(
                          text: '╫פ╫ץ╫ª╫נ╫פ ╫£╫נ╫ץ╫¿: ',
                          style: _boldBodyStyle(context),
                        ),
                        TextSpan(
                          text: [
                            if (book.pubPlaceStringHe != null &&
                                book.pubPlaceStringHe!.isNotEmpty)
                              book.pubPlaceStringHe,
                            if (book.pubDateStringHe != null &&
                                book.pubDateStringHe!.isNotEmpty)
                              book.pubDateStringHe,
                          ].where((s) => s != null && s.isNotEmpty).join(', '),
                        ),
                      ],
                    ),
                  ),
                ),
              if (book.extraTitles != null && book.extraTitles!.length > 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: RichText(
                    textAlign: TextAlign.right,
                    text: TextSpan(
                      style: DefaultTextStyle.of(context).style,
                      children: [
                        TextSpan(
                          text: '╫⌐╫₧╫ץ╫¬ ╫á╫ץ╫í╫ñ╫ש╫¥: ',
                          style: _boldBodyStyle(context),
                        ),
                        TextSpan(
                          text: book.extraTitles!
                              .where((title) => title != book.title)
                              .join(', '),
                        ),
                      ],
                    ),
                  ),
                ),
              if (book.heShortDesc != null && book.heShortDesc!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
                  child: RichText(
                    textAlign: TextAlign.right,
                    text: TextSpan(
                      style: DefaultTextStyle.of(context).style,
                      children: [
                        TextSpan(
                          text: '╫¬╫ש╫נ╫ץ╫¿ ╫₧╫º╫ץ╫ª╫¿ ╫ó╫£ ╫פ╫í╫ñ╫¿: ',
                          style: _boldBodyStyle(context),
                        ),
                        TextSpan(text: book.heShortDesc),
                      ],
                    ),
                  ),
                ),
              if (book.heDesc != null && book.heDesc!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
                  child: RichText(
                    textAlign: TextAlign.right,
                    text: TextSpan(
                      style: DefaultTextStyle.of(context).style,
                      children: [
                        TextSpan(
                          text: '╫¬╫ש╫נ╫ץ╫¿ ╫פ╫í╫ñ╫¿: ',
                          style: _boldBodyStyle(context),
                        ),
                        TextSpan(text: book.heDesc),
                      ],
                    ),
                  ),
                ),
              _buildBookSourceSection(book),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('╫í╫ע╫ץ╫¿'),
          ),
        ],
      );
    },
  );
}

Widget _buildBookSourceSection(Book book) {
  return FutureBuilder<Map<String, dynamic>>(
    future: _getBookSourceInfo(book),
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const SizedBox.shrink();
      }

      final sourceInfo = snapshot.data!;
      final displayInfo = sourceInfo['displayInfo'] as Map<String, String>;
      final displayText = displayInfo['text']!;
      final url = displayInfo['url']!;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 32),
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: url.isNotEmpty
                ? RichText(
                    textAlign: TextAlign.right,
                    text: TextSpan(
                      style: DefaultTextStyle.of(context).style,
                      children: [
                        TextSpan(
                          text: '╫₧╫º╫ץ╫¿ ╫פ╫í╫ñ╫¿: ',
                          style: _boldBodyStyle(context),
                        ),
                        WidgetSpan(
                          child: InkWell(
                            onTap: () async {
                              final uri = Uri.parse(url);
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri);
                              }
                            },
                            child: Text(
                              displayText,
                              style: _linkBodyStyle(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : RichText(
                    textAlign: TextAlign.right,
                    text: TextSpan(
                      style: DefaultTextStyle.of(context).style,
                      children: [
                        TextSpan(
                          text: '╫₧╫º╫ץ╫¿ ╫פ╫í╫ñ╫¿: ',
                          style: _boldBodyStyle(context),
                        ),
                        TextSpan(text: displayText),
                      ],
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: RichText(
              textAlign: TextAlign.right,
              text: TextSpan(
                style: _mutedBodyStyle(context),
                children: [
                  TextSpan(
                    text: '╫צ╫¢╫ץ╫ש╫ץ╫¬ ╫ש╫ץ╫ª╫¿╫ש╫¥: ',
                    style: _boldBodyStyle(context),
                  ),
                  TextSpan(
                    text: '╫פ╫₧╫ש╫ף╫ó ╫ש╫ץ╫ע╫ף╫¿ ╫ס╫פ╫₧╫⌐╫ת',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontStyle: FontStyle.italic,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );
}

Future<Map<String, dynamic>> _getBookSourceInfo(Book book) async {
  try {
    final bookDetails = await BookDetailsService().getBookDetails(book);
    final bookSource =
        bookDetails['╫¬╫ש╫º╫ש╫ש╫¬ ╫פ╫₧╫º╫ץ╫¿'] ?? '╫£╫נ ╫á╫₧╫ª╫נ ╫₧╫º╫ץ╫¿';
    final displayInfo = getSourceDisplayInfo(bookSource);

    return {
      'source': bookSource,
      'displayInfo': displayInfo,
    };
  } catch (e) {
    return {
      'source': '╫£╫נ ╫á╫₧╫ª╫נ ╫₧╫º╫ץ╫¿',
      'displayInfo': {'text': '╫£╫נ ╫á╫₧╫ª╫נ ╫₧╫º╫ץ╫¿', 'url': ''},
    };
  }
}

// ignore: unused_element
void _showCategoryInfoDialog(BuildContext context, Category category) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text(
          category.title,
          textAlign: TextAlign.right,
        ),
        content: SingleChildScrollView(
          child: Text(
            category.shortDescription,
            textAlign: TextAlign.right,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('╫í╫ע╫ץ╫¿'),
          ),
        ],
      );
    },
  );
}

Future<void> _showDeleteBookDialog(
    BuildContext context, Book book, VoidCallback? onBookDeleted) async {
  final confirmed = await showWarningDialog(
    context: context,
    title: 'למחוק את הספר?',
    content: 'הספר "${book.title}" יימחק ממסד הנתונים.',
    subtitle: 'לא ניתן לשחזר ספר שנמחק.',
    cancelText: 'ביטול',
    confirmText: 'מחק',
  );

  if (confirmed != true) {
    return;
  }

  await _deleteBook(book);
  onBookDeleted?.call();
}

Future<void> _deleteBook(Book book) async {
  try {
    final success = await BookLocator.deleteBook(
      book.title,
      category: book.category,
      categoryId: book.categoryId,
    );

    if (!success) {
      throw Exception('╫פ╫₧╫ק╫ש╫º╫פ ╫á╫¢╫⌐╫£╫פ');
    }

    UiSnack.show('╫פ╫í╫ñ╫¿ "${book.title}" ╫á╫₧╫ק╫º ╫ס╫פ╫ª╫£╫ק╫פ');
  } catch (e) {
    UiSnack.showError('╫⌐╫ע╫ש╫נ╫פ ╫ס╫₧╫ק╫ש╫º╫¬ ╫פ╫í╫ñ╫¿: $e');
  }
}
