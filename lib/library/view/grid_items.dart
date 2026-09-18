import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/data_providers/external_catalog_mapper.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'dart:math';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/messages/library_messages.dart';
import 'package:otzaria/data/book_locator.dart';
import 'package:otzaria/library/view/category_details_dialog.dart';
import 'package:otzaria/library/view/book_versions_dialog.dart';
import 'package:otzaria/text_book/utils/book_versions_action.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/text_book/view/book_source_dialog.dart';
import 'package:otzaria/widgets/dialogs/dialogs_exports.dart';
import 'package:otzaria/widgets/layout/app_card.dart';
import 'package:otzaria/utils/ui/book_format_icon.dart';

/// מספר התווים המרבי בתיאור קצר המוצג בכרטיס ספר, כולל שלוש הנקודות.
const kBookCardDescriptionMaxCharacters = 120;

/// מקצר תיאור לכרטיס ספר ושומר מקום לשלוש נקודות כשנדרש.
String truncateBookCardDescription(String description) {
  final trimmed = description.trim();
  if (trimmed.length <= kBookCardDescriptionMaxCharacters) return trimmed;
  final contentLength = kBookCardDescriptionMaxCharacters - 3;
  return '${trimmed.substring(0, contentLength).trimRight()}...';
}

String? _bookInfoTooltipText(Book book) {
  final fullDescription = book.heDesc?.trim();
  if (fullDescription != null && fullDescription.isNotEmpty) {
    return fullDescription;
  }
  final shortDescription = book.heShortDesc?.trim();
  return shortDescription == null || shortDescription.isEmpty
      ? null
      : shortDescription;
}

/// הטקסט שיוצג ב־Tooltip של לחצן המידע לקטגוריה.
String? categoryInfoText(Category category) {
  final fullDescription = category.description.trim();
  if (fullDescription.isNotEmpty) return fullDescription;

  final shortDescription = category.shortDescription.trim();
  return shortDescription.isEmpty ? null : shortDescription;
}

/// מחזיר את נתיב הלוגו של הקטלוג החיצוני שממנו מגיע הספר, או null אם זהו
/// ספר מקומי רגיל ללא מקור חיצוני.
///
/// ספר היברובוקס שהורד מקומית מומר ל-[PdfBook] (ראה
/// `FileSystemData.mapHebrewBooksToLocal`) אך שומר את [Book.externalLibraryId]
/// (למשל `hb:123`). לכן הזיהוי מסתמך על המזהה החיצוני האמין — ולא על נתיב
/// הקובץ, שעלול להכיל את המחרוזת `otzaria` ולגרום לזיהוי שגוי של כל ספר מקומי.
String? externalCatalogLogoAsset(Book book) {
  final id = book.externalLibraryId;
  final link = book is ExternalLibraryBook ? book.link.toString() : null;
  if ((id == null || id.isEmpty) && (link == null || link.isEmpty)) {
    return null;
  }
  switch (ExternalCatalogMapper.catalogFromLinkOrId(
    externalLibraryId: id,
    link: link,
  )) {
    case ExternalCatalogType.otzar:
      return 'assets/logos/otzar.ico';
    case ExternalCatalogType.hebrew:
      return 'assets/logos/hebrew_books.png';
    case null:
      return null;
  }
}

/// בונה את תוכן אייקון הספר: לוגו הקטלוג החיצוני אם קיים, אחרת אייקון לפי סוג הקובץ.
Widget _buildBookIconChild(Book book, ColorScheme cs, double iconSize) {
  final logoAsset = externalCatalogLogoAsset(book);
  if (logoAsset != null) {
    return Image.asset(
      logoAsset,
      width: iconSize,
      height: iconSize,
      fit: BoxFit.contain,
    );
  }
  return Icon(
    bookFormatIcon(book),
    color: cs.onSecondaryContainer,
    size: iconSize,
  );
}

bool _textOverflows({
  required BuildContext context,
  required String text,
  required TextStyle style,
  required int maxLines,
  required double maxWidth,
  required TextAlign textAlign,
}) {
  final textPainter = TextPainter(
    text: TextSpan(text: text, style: style),
    maxLines: maxLines,
    ellipsis: 'Γאª',
    textDirection: Directionality.of(context),
    textAlign: textAlign,
    textScaler: MediaQuery.textScalerOf(context),
  )..layout(maxWidth: maxWidth);

  return textPainter.didExceedMaxLines;
}

Decoration _libraryTooltipDecoration(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return BoxDecoration(
    color: cs.surfaceContainerHigh,
    borderRadius: AppTokens.borderRadiusAll,
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

  const LibraryOverflowTooltipText({
    super.key,
    required this.text,
    this.style,
    this.maxLines = 2,
    this.textAlign = TextAlign.right,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedStyle = style ?? DefaultTextStyle.of(context).style;

    return LayoutBuilder(
      builder: (context, constraints) {
        final hasOverflow =
            constraints.maxWidth.isFinite &&
            constraints.maxWidth > 0 &&
            _textOverflows(
              context: context,
              text: text,
              style: resolvedStyle,
              maxLines: maxLines,
              maxWidth: constraints.maxWidth,
              textAlign: textAlign,
            );

        final child = Text(
          text,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          textAlign: textAlign,
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
        style: theme.textTheme.titleMedium?.copyWith(
          color: theme.colorScheme.secondary,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  CategoryGridItem
//  Layout RTL: [info-icon?] [folder-icon] [12px] [Expanded text (right-aligned)]
//  במצב RTL: טקסט מימין, אייקונים משמאל כדי לשמור ויזואלית תקינה.
// ─────────────────────────────────────────────────────────────────────────────

class CategoryGridItem extends StatelessWidget {
  final Category category;
  final VoidCallback onCategoryClickCallback;
  final FocusNode? focusNode;
  final bool isSelected;

  const CategoryGridItem({
    super.key,
    required this.category,
    required this.onCategoryClickCallback,
    this.focusNode,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final infoText = categoryInfoText(category);
    return AppCard(
      onTap: onCategoryClickCallback,
      focusNode: focusNode,
      selected: isSelected,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          // שומר על סדר אייקונים משמאל וטקסט מימין בתוך ממשק RTL.
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  LibraryItemTitle(
                    text: category.title,
                    isFolder: true,
                  ),
                  // זמני: התיאור הקצר הוסר מגוף הכרטיס.
                  // if (category.shortDescription.isNotEmpty) ...[
                  //   const SizedBox(height: 3),
                  //   LibraryOverflowTooltipText(
                  //     text: category.shortDescription,
                  //     maxLines: 2,
                  //     textAlign: TextAlign.right,
                  //     style: theme.textTheme.bodySmall?.copyWith(
                  //       color: cs.onSecondaryContainer,
                  //     ),
                  //   ),
                  // ],
                ],
              ),
            ),
            const SizedBox(width: 18),
            if (infoText != null)
              ExcludeFocusTraversal(
                child: Tooltip(
                  message: infoText,
                  waitDuration: const Duration(milliseconds: 400),
                  textAlign: TextAlign.right,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  margin: const EdgeInsets.all(12),
                  constraints: const BoxConstraints(maxWidth: 320),
                  textStyle: _libraryTooltipTextStyle(context),
                  decoration: _libraryTooltipDecoration(context),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: IconButton(
                      onPressed: () =>
                          showCategoryDetailsDialog(context, category),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 28,
                        height: 28,
                      ),
                      icon: Icon(
                        FluentIcons.info_24_regular,
                        size: 15,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(width: 4),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: cs.secondaryContainer,
                borderRadius: AppTokens.borderRadiusAll,
              ),
              child: Icon(
                FluentIcons.folder_24_regular,
                color: cs.onSecondaryContainer,
                size: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  BookGridItem
//  Layout RTL: [action-col] [media-col] [12px] [Expanded text (right-aligned)]
//  במצב RTL: טקסט מימין, אייקונים משמאל כדי לשמור ויזואלית תקינה.
// ─────────────────────────────────────────────────────────────────────────────

class BookGridItem extends StatelessWidget {
  final bool showTopics;
  final bool isSelected;
  final Book book;
  final VoidCallback onBookClickCallback;
  final VoidCallback? onBookDeleted;
  final FocusNode? focusNode;

  const BookGridItem({
    super.key,
    required this.book,
    required this.onBookClickCallback,
    this.showTopics = false,
    this.isSelected = false,
    this.onBookDeleted,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onBookClickCallback,
      focusNode: focusNode,
      selected: isSelected,
      child: SizedBox.expand(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: _BookGridTextColumn(
                  book: book,
                  showTopics: showTopics,
                ),
              ),
              const SizedBox(width: 18),
              SizedBox(
                width: 32,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    _BookGridMediaColumn(
                      book: book,
                      showTopics: showTopics,
                    ),
                    _BookGridActionColumn(
                      book: book,
                      onBookDeleted: onBookDeleted,
                    ),
                  ],
                ),
              ),
            ],
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
    // אייקונים מעוצבים: 32×32 container, 16px icon או קונטיינר רחוק שיותר
    const double iconBoxSize = 32.0;
    const double iconSize = 16.0;

    final iconContainer = Container(
      width: iconBoxSize,
      height: iconBoxSize,
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: AppTokens.borderRadiusAll,
      ),
      child: Center(
        child: _buildBookIconChild(book, cs, iconSize),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        book.isUserBook
            ? Tooltip(
                message: 'ספר אישי',
                waitDuration: const Duration(milliseconds: 400),
                child: SizedBox(
                  width: iconBoxSize,
                  height: iconBoxSize,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      iconContainer,
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: cs.primary,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppSurfaces.card(context),
                              width: 1.5,
                            ),
                          ),
                          child: Icon(
                            FluentIcons.person_24_regular,
                            size: 8,
                            color: cs.onPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : iconContainer,
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
    // כותרת: onSurface כדי מבנה מאוחד ומסודר (ולא primary שיכול להיות מדי בולט)
    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
      color: theme.colorScheme.onSurface,
    );
    final authorStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSecondaryContainer,
    );
    // זמני: התיאור הקצר הוסר מגוף הכרטיס. להחזרה — בטלו את ההערות כאן ולהלן.
    // final descriptionStyle = theme.textTheme.bodySmall?.copyWith(
    //   color: theme.colorScheme.onSurfaceVariant,
    // );
    final topicsStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.secondary,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final titleOverflow =
            titleStyle != null &&
            constraints.maxWidth.isFinite &&
            constraints.maxWidth > 0 &&
            _textOverflows(
              context: context,
              text: book.title,
              style: titleStyle,
              maxLines: 2,
              maxWidth: constraints.maxWidth,
              textAlign: TextAlign.right,
            );

        final authorMaxLines = titleOverflow ? 1 : 2;
        final hasAuthor = (book.author ?? '').isNotEmpty;
        // final shortDescription = truncateBookCardDescription(
        //   book.heShortDesc ?? '',
        // );
        // final hasShortDescription = shortDescription.isNotEmpty;
        // final descriptionMaxLines = constraints.maxHeight < 100
        //     ? 1
        //     : titleOverflow
        //     ? 2
        //     : 3;
        // בתוצאות חיפוש מוצג נתיב הקטגוריות — הוא שמסביר למשתמש למה הספר
        // הותאם, ובספרים אישיים שם הספר יושב עליו ולא על הקובץ.
        final pathText = (book.categoryPath ?? '').trim().isNotEmpty
            ? book.categoryPath!.trim()
            : book.topics.trim();
        final hasTopics = showTopics && pathText.isNotEmpty;
        final topicsMaxLines = !hasTopics
            ? 0
            : constraints.maxHeight < 110
            ? 1
            : constraints.maxHeight < 140 ||
                  hasAuthor ||
                  titleOverflow // || hasShortDescription
            ? 2
            : 3;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.max,
          children: [
            LibraryOverflowTooltipText(
              text: book.title,
              maxLines: 2,
              textAlign: TextAlign.right,
              style: titleStyle,
            ),
            if (hasAuthor) ...[
              const SizedBox(height: 3),
              LibraryOverflowTooltipText(
                text: book.author!,
                maxLines: authorMaxLines,
                textAlign: TextAlign.right,
                style: authorStyle,
              ),
            ],
            // if (hasShortDescription) ...[
            //   const SizedBox(height: 4),
            //   Flexible(
            //     child: Text(
            //       shortDescription,
            //       maxLines: descriptionMaxLines,
            //       overflow: TextOverflow.ellipsis,
            //       textAlign: TextAlign.right,
            //       style: descriptionStyle,
            //     ),
            //   ),
            // ],
            if (hasTopics) ...[
              const Spacer(),
              LibraryOverflowTooltipText(
                text: pathText,
                maxLines: topicsMaxLines,
                textAlign: TextAlign.right,
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
    final infoTooltipText = _bookInfoTooltipText(book);

    final infoButton = Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: IconButton(
        onPressed: () => showBookDetailsDialog(context, book),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 28, height: 28),
        icon: Icon(
          FluentIcons.info_24_regular,
          size: 15,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );

    // הפעולות המשניות מוחרגות ממסלול הפוקוס — חיצים/Tab עוצרים רק על הכרטיס.
    return ExcludeFocusTraversal(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (infoTooltipText != null)
            Tooltip(
              message: infoTooltipText,
              waitDuration: const Duration(milliseconds: 400),
              textAlign: TextAlign.right,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              margin: const EdgeInsets.all(12),
              constraints: const BoxConstraints(maxWidth: 320),
              textStyle: _libraryTooltipTextStyle(context),
              decoration: _libraryTooltipDecoration(context),
              child: infoButton,
            )
          else
            infoButton,
          BookActionsMenuButton(book: book, onBookDeleted: onBookDeleted),
        ],
      ),
    );
  }
}

/// תפריט "אפשרויות נוספות" של ספר (גרסאות / מחיקה מהספרייה) — משותף לכרטיס
/// הרשת ולשורת העץ. מוצג רק כשיש בפועל פעולה זמינה, אחרת נעלם.
class BookActionsMenuButton extends StatelessWidget {
  final Book book;
  final VoidCallback? onBookDeleted;

  const BookActionsMenuButton({
    super.key,
    required this.book,
    required this.onBookDeleted,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<List<bool>>(
      future: Future.wait([
        _canDeleteBookFromLibrary(book),
        hasBookVersionsToOpen(book),
      ]),
      builder: (context, snapshot) {
        final canDelete = snapshot.data?[0] ?? false;
        final showVersions = snapshot.data?[1] ?? false;
        if (!canDelete && !showVersions) {
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
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onSelected: (value) {
              if (value == 'delete') {
                _showDeleteBookDialog(context, book, onBookDeleted);
              } else if (value == 'versions') {
                showBookVersionsDialog(context, book);
              }
            },
            entries: [
              if (showVersions)
                const AppMenuEntry<String>(
                  value: 'versions',
                  label: 'גרסאות',
                  icon: OtzariaIcons.books_stacked_high_24_regular,
                ),
              if (canDelete)
                const AppMenuEntry<String>(
                  value: 'delete',
                  label: 'מחק מהספרייה',
                  icon: FluentIcons.delete_24_regular,
                  isDestructive: true,
                ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  MyGridView
//  • FocusTraversalGroup כדי לנווט Tab בסדר קריאה (ולא קפיצה ציגזג)
// ─────────────────────────────────────────────────────────────────────────────

/// ריווח אחיד בין כרטיסי הרשת — משותף לתצוגת הספרייה ולתוצאות החיפוש.
const double kLibraryGridSpacing = 14;

/// גובה מינימלי לכרטיס ספר בתצוגה צרה — מספיק לכותרת (עד 2 שורות), למחבר
/// ולטור האייקונים בלי גלישה.
const double kNarrowGridCardMinHeight = 112;

/// השוליים של רשת הספרייה — משמשים גם בחישוב רוחב התא בפועל.
const double _kGridPadding = 30;

/// השוליים העליונים מעט קטנים יותר, כדי שהשורה הראשונה לא תיראה נמוכה מדי
/// מתחת לסרגל.
const double _kGridTopPadding = 24;

/// ניווט חיצים בין כרטיסי הרשת בלבד — הפוקוס עובר ברצף בין הכרטיסים
/// ולא בורח לכפתורי הסרגל/הצד (המסלול הכיווני של Flutter אינו תחום לרשת).
///
/// חיצי צד נעים ברצף על פני כל הפריטים (גם בין שורות); מעלה/מטה נעים בטור.
/// [onExitTop] נקרא בחץ-מעלה מהשורה הראשונה (חזרה לשדה החיפוש).
class LibraryGridKeyNavigator extends StatelessWidget {
  final int crossAxisCount;
  final VoidCallback? onExitTop;
  final Widget child;

  const LibraryGridKeyNavigator({
    super.key,
    required this.crossAxisCount,
    this.onExitTop,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) => _handleKey(context, node, event),
      child: child,
    );
  }

  KeyEventResult _handleKey(
    BuildContext context,
    FocusNode node,
    KeyEvent event,
  ) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final int? delta = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowLeft => isRtl ? 1 : -1,
      LogicalKeyboardKey.arrowRight => isRtl ? -1 : 1,
      LogicalKeyboardKey.arrowDown => crossAxisCount,
      LogicalKeyboardKey.arrowUp => -crossAxisCount,
      _ => null,
    };
    if (delta == null) return KeyEventResult.ignored;

    final cards = node.traversalDescendants.toList();
    final primary = FocusManager.instance.primaryFocus;
    final index = primary == null ? -1 : cards.indexOf(primary);
    if (index < 0) return KeyEventResult.ignored;

    var target = index + delta;
    if (delta.abs() == 1) target = target.clamp(0, cards.length - 1);
    if (target < 0) {
      onExitTop?.call();
      return KeyEventResult.handled;
    }
    if (target == index || target >= cards.length) {
      return KeyEventResult.handled;
    }
    focusCard(cards[target]);
    return KeyEventResult.handled;
  }

  /// ממקד כרטיס וגולל אותו לתצוגה (requestFocus לבדו אינו גולל).
  static void focusCard(FocusNode target) {
    target.requestFocus();
    final targetContext = target.context;
    if (targetContext == null) return;
    Scrollable.ensureVisible(
      targetContext,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
    );
    Scrollable.ensureVisible(
      targetContext,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
    );
  }
}

class MyGridView extends StatelessWidget {
  final List<Widget> items;
  final VoidCallback? onExitTop;

  const MyGridView({super.key, required this.items, this.onExitTop});

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
        final textAdjustment = textScale <= 1.0
            ? 1.0
            : (1.0 / (1.0 + ((textScale - 1.0) * 0.65)));
        final crossAxisCount = max(1, min(width ~/ 250, 5));

        // בתצוגה צרה (<800) הכרטיסים גבוהים במיוחד: מקטינים את גובהם בחצי,
        // עם רצפת גובה שמותירה מקום לשם הספר, למחבר ולטור האייקונים.
        final double childAspectRatio;
        if (width < 800) {
          final gridWidth = width - 2 * _kGridPadding;
          final cellWidth =
              (gridWidth - kLibraryGridSpacing * (crossAxisCount - 1)) /
              crossAxisCount;
          final halfHeight = cellWidth / (2 * baseRatio * textAdjustment);
          final minHeight = kNarrowGridCardMinHeight * textScale;
          childAspectRatio = cellWidth / max(minHeight, halfHeight);
        } else {
          childAspectRatio = (baseRatio * textAdjustment).clamp(1.45, 2.15);
        }

        return LibraryGridKeyNavigator(
          crossAxisCount: crossAxisCount,
          onExitTop: onExitTop,
          child: FocusTraversalGroup(
            policy: ReadingOrderTraversalPolicy(),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                _kGridPadding,
                _kGridTopPadding,
                _kGridPadding,
                _kGridPadding,
              ),
              child: GridView.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  childAspectRatio: childAspectRatio,
                  crossAxisSpacing: kLibraryGridSpacing,
                  mainAxisSpacing: kLibraryGridSpacing,
                ),
                itemCount: items.length,
                itemBuilder: (context, index) => items[index],
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// בודק האם ניתן למחוק את [book] דרך הספרייה.
///
/// מותר רק לספרי משתמש מסוג "עותק עצמאי" (התוכן שמור בתוכנה). ספר
/// "קריאה מהקבצים" (file-backed) נמחק רק ע"י מחיקת הקובץ מהדיסק, והספרייה
/// הרשמית אינה ניתנת למחיקה ע"י המשתמש.
Future<bool> _canDeleteBookFromLibrary(Book book) {
  return FileSystemData.instance.canDeleteUserBookFromLibrary(
    title: book.title,
    categoryId: book.categoryId,
    fileType: book.fileType ?? 'txt',
    source: book.source,
  );
}

Future<void> _showDeleteBookDialog(
  BuildContext context,
  Book book,
  VoidCallback? onBookDeleted,
) async {
  final confirmed = await showWarningDialog(
    context: context,
    title: 'למחוק את הספר?',
    content: 'הספר "${book.title}" יימחק מהספרייה.',
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
      throw Exception('המחיקה נכשלה');
    }

    UiSnack.show(LibraryMessages.bookDeletedFromLibrary(book.title));
  } catch (e) {
    UiSnack.showError(LibraryMessages.bookDeleteError(e));
  }
}
