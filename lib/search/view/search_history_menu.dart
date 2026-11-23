import 'dart:math';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/controls/app_icon_button.dart';
import 'package:otzaria/widgets/feedback/app_scrollbar.dart';
import 'package:otzaria/widgets/feedback/otzaria_empty_state.dart';
import 'package:otzaria/widgets/text/app_section_label.dart';
import 'package:otzaria_context_menu/otzaria_context_menu.dart'
    show AppMenuMetrics;
import 'package:otzaria_icons/otzaria_icons.dart';

/// מפתח התוכן של תפריט ההיסטוריה, לבדיקות.
const searchHistoryMenuKey = ValueKey('search-history-menu');

/// תוכן תפריט היסטוריית החיפושים שבשדה החיפוש: כותרת, ושורה לכל חיפוש
/// אחרון, עם מחיקה. כשאין היסטוריה מוצג מצב ריק.
///
/// הרכיב אינו יודע מה חיפוש מכיל: בחירה ומחיקה מועברות החוצה, ושם משוחזרים
/// הפרמטרים של החיפוש.
class SearchHistoryMenu extends StatefulWidget {
  const SearchHistoryMenu({
    super.key,
    required this.entries,
    required this.onSelect,
    required this.onRemove,
  });

  /// החיפושים להצגה, מהאחרון לראשון.
  final List<Bookmark> entries;
  final ValueChanged<Bookmark> onSelect;
  final ValueChanged<Bookmark> onRemove;

  @override
  State<SearchHistoryMenu> createState() => _SearchHistoryMenuState();
}

class _SearchHistoryMenuState extends State<SearchHistoryMenu> {
  // בקר משלו: התפריט נפתח מעל דיאלוג שכבר משתמש ב-PrimaryScrollController.
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.entries;
    final cs = Theme.of(context).colorScheme;
    // הרשימה גוללת בתוך התפריט, והתפריט לא עולה על מחצית גובה החלון.
    final maxListHeight = min(
      MediaQuery.sizeOf(context).height / 2,
      _kMaxListHeight,
    );
    return Column(
      key: searchHistoryMenuKey,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.spaceMD,
            vertical: AppTokens.spaceSM,
          ),
          child: AppSectionLabel(context.settingsText('היסטוריית חיפושים')),
        ),
        Divider(
          height: AppTokens.borderThin,
          color: AppSurfaces.subtleDivider(cs),
        ),
        if (entries.isEmpty)
          OtzariaEmptyState(
            isCompact: true,
            scrollable: false,
            icon: FluentIcons.history_24_regular,
            title: context.settingsText('אין עדיין חיפושים בהיסטוריה'),
          )
        else
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxListHeight),
            child: AppScrollbar(
              controller: _scrollController,
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.all(AppTokens.spaceXS),
                child: Column(
                  children: [
                    for (final entry in entries)
                      _SearchHistoryRow(
                        entry: entry,
                        onSelect: () => widget.onSelect(entry),
                        onRemove: () => widget.onRemove(entry),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

const double _kMaxListHeight = 360;

/// כותרת עשירה לפריט חיפוש: מבנה השאילתה בגופן רגיל, ואפשרויות המילה
/// מובחנות (גופן קטן, גוון הנושא). null כשאין אפשרויות — אז הכותרת הרגילה
/// (ref) מספיקה ואין צורך לפצל מחדש את השאילתה במנוע.
InlineSpan? searchTitleSpan(BuildContext context, Bookmark item) {
  final options = item.searchOptions;
  if (!item.isSearch ||
      options == null ||
      !options.values.any((map) => map.values.any((enabled) => enabled))) {
    return null;
  }
  final segments = buildSearchTitleSegments(
    query: item.book.title,
    effectiveOptions: options,
    alternativeWords: item.alternativeWords ?? const {},
    spacingValues: item.spacingValues ?? const {},
    negativeText: item.negativeSearchText ?? '',
  );
  final theme = Theme.of(context);
  final optionStyle = theme.textTheme.bodySmall?.copyWith(
    fontWeight: FontWeight.normal,
    color: theme.colorScheme.primary,
  );
  return TextSpan(
    children: [
      for (final segment in segments)
        TextSpan(
          text: segment.text,
          style: segment.isOption ? optionStyle : null,
        ),
    ],
  );
}

class _SearchHistoryRow extends StatelessWidget {
  const _SearchHistoryRow({
    required this.entry,
    required this.onSelect,
    required this.onRemove,
  });

  final Bookmark entry;
  final VoidCallback onSelect;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final metrics =
        theme.extension<AppMenuMetrics>() ??
        AppMenuMetrics.create(compactMenus: false);
    final touch = theme.materialTapTargetSize == MaterialTapTargetSize.padded;
    final formattedTitle = searchTitleSpan(context, entry);
    // חוקי הפיצול יכולים להשתנות בין גרסאות. התפריט מציג את הנוסח שנשמר.
    final title =
        formattedTitle != null && formattedTitle.toPlainText() == entry.ref
        ? formattedTitle
        : TextSpan(text: entry.ref);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.space2XS),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: AppTokens.borderRadiusAll,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onSelect,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: touch ? kMinInteractiveDimension : metrics.itemHeight,
            ),
            child: Padding(
              padding: const EdgeInsetsDirectional.only(
                start: AppTokens.spaceSMD,
                end: AppTokens.space2XS,
              ),
              child: Row(
                children: [
                  Icon(
                    OtzariaIcons.search_24_regular,
                    size: AppTokens.iconSM,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppTokens.spaceSM),
                  Expanded(
                    child: Tooltip(
                      message: entry.ref,
                      child: Text.rich(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  ),
                  AppIconButton(
                    icon: const Icon(FluentIcons.delete_24_regular),
                    size: AppIconButtonSize.small,
                    tooltip: context.settingsText('מחק מההיסטוריה'),
                    onPressed: onRemove,
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
