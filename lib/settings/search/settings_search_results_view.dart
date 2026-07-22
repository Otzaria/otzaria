import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/settings/search/settings_search_models.dart';
import 'package:otzaria/settings/view/settings_screen.dart';
import 'package:otzaria/theme/layout_tokens.dart';
import 'package:otzaria/widgets/misc/rtl_icon.dart';

/// תצוגת תוצאות חיפוש בהגדרות — מוצגת באזור התוכן כאשר השאילתה אינה ריקה.
class SettingsSearchResultsView extends StatelessWidget {
  final String query;
  final List<SettingsSearchEntry> results;
  final ValueChanged<SettingsSearchEntry> onResultTap;

  const SettingsSearchResultsView({
    super.key,
    required this.query,
    required this.results,
    required this.onResultTap,
  });

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return _buildEmptyState(context);
    }

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: LayoutConstraints.panelContentMaxWidth,
        ),
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: results.length,
          separatorBuilder: (_, _) => const SizedBox(height: 6),
          itemBuilder: (context, index) {
            final entry = results[index];
            return _SearchResultTile(
              entry: entry,
              query: query,
              onTap: () => onResultTap(entry),
            );
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // עוטפים ב-CustomScrollView/SliverFillRemaining כדי שה-PrimaryScrollController
    // העוטף יקבל ScrollPosition פעיל גם כשאין תוצאות (אחרת ה-Scrollbar
    // החיצוני זורק "no ScrollPosition attached").
    return CustomScrollView(
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    FluentIcons.search_info_24_regular,
                    size: 48,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'לא נמצאו הגדרות תואמות',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'נסה לחפש מילים אחרות',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
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

class _SearchResultTile extends StatelessWidget {
  final SettingsSearchEntry entry;
  final String query;
  final VoidCallback onTap;

  const _SearchResultTile({
    required this.entry,
    required this.query,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final cardColor = isDark
        ? colorScheme.surfaceContainer
        : colorScheme.surface;

    return Material(
      color: cardColor,
      borderRadius: AppTokens.borderRadiusAll,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                _iconForTab(entry.tab),
                size: 22,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _HighlightedText(
                      text: entry.title,
                      query: query,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (entry.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      _HighlightedText(
                        text: entry.subtitle,
                        query: query,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.10),
                  borderRadius: AppTokens.borderRadiusAll,
                ),
                child: Text(
                  _tabLabel(entry.tab),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              RtlIcon(
                FluentIcons.chevron_left_24_regular,
                size: 18,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// טקסט עם הדגשה של חלקי השאילתה (כתום-עיצוב כרום).
class _HighlightedText extends StatelessWidget {
  final String text;
  final String query;
  final TextStyle? style;

  const _HighlightedText({
    required this.text,
    required this.query,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final highlightColor = colorScheme.primary.withValues(alpha: 0.20);
    final spans = _buildSpans(text, query, highlightColor);

    return RichText(
      text: TextSpan(
        style: style ?? DefaultTextStyle.of(context).style,
        children: spans,
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  List<TextSpan> _buildSpans(String text, String query, Color highlightColor) {
    if (query.trim().isEmpty) {
      return [TextSpan(text: text)];
    }
    final normalizedQuery = SettingsSearchEntry.normalize(query);
    if (normalizedQuery.isEmpty) {
      return [TextSpan(text: text)];
    }

    // נרמול הטקסט עם שמירת מיפוי ל-text המקורי. בשונה מ-`normalize()`
    // הכללי, פה שומרים על רווחים פנימיים (לא trim) כדי ששאילתות רב-
    // מיליות יודלקו נכון.
    final mapped = _normalizeWithMapping(text);
    final normalizedText = mapped.text;
    final origIndexFor = mapped.indexMap;
    if (normalizedText.isEmpty) {
      return [TextSpan(text: text)];
    }

    final spans = <TextSpan>[];
    var origCursor = 0;
    var searchFrom = 0;
    while (searchFrom < normalizedText.length) {
      final hit = normalizedText.indexOf(normalizedQuery, searchFrom);
      if (hit < 0) break;
      final hitEndExclusive = hit + normalizedQuery.length;
      // מיפוי הגבולות חזרה לטקסט המקורי
      final origStart = origIndexFor[hit];
      final origEnd = hitEndExclusive < origIndexFor.length
          ? origIndexFor[hitEndExclusive]
          : text.length;
      if (origStart > origCursor) {
        spans.add(TextSpan(text: text.substring(origCursor, origStart)));
      }
      spans.add(
        TextSpan(
          text: text.substring(origStart, origEnd),
          style: TextStyle(
            backgroundColor: highlightColor,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
      origCursor = origEnd;
      searchFrom = hitEndExclusive;
    }
    if (origCursor < text.length) {
      spans.add(TextSpan(text: text.substring(origCursor)));
    }
    return spans.isEmpty ? [TextSpan(text: text)] : spans;
  }

  /// נרמול טקסט עם מיפוי לאינדקסי המקור. שומר על רווחים פנימיים
  /// (חוסך trim) כך שחיפוש רב-מילי כמו "מצב כהה" יתאים לטקסט מקור
  /// "מצב כהה" עם רווחים מקוריים.
  ({String text, List<int> indexMap}) _normalizeWithMapping(String src) {
    final buf = StringBuffer();
    final mapping = <int>[];
    var prevWasSpace = true; // כדי שרווחים בהתחלה ייבלעו

    for (var i = 0; i < src.length; i++) {
      final ch = src[i];
      final code = src.codeUnitAt(i);

      // ניקוד עברי
      if (code >= 0x0591 && code <= 0x05C7) continue;

      // גרשיים
      if (ch == '"' || ch == "'" || ch == '׳' || ch == '״') continue;

      final lower = ch.toLowerCase();

      // איחוד רצף רווחים לרווח אחד
      if (lower == ' ' || lower == '\t' || lower == '\n' || lower == '\r') {
        if (prevWasSpace) continue;
        buf.write(' ');
        mapping.add(i);
        prevWasSpace = true;
      } else {
        buf.write(lower);
        mapping.add(i);
        prevWasSpace = false;
      }
    }

    return (text: buf.toString(), indexMap: mapping);
  }
}

IconData _iconForTab(SettingsTab tab) {
  switch (tab) {
    case SettingsTab.design:
      return FluentIcons.paint_brush_24_regular;
    case SettingsTab.text:
      return FluentIcons.book_24_regular;
    case SettingsTab.library:
      return FluentIcons.library_24_regular;
    case SettingsTab.tools:
      return FluentIcons.wrench_24_regular;
    case SettingsTab.shortcuts:
      return FluentIcons.keyboard_24_regular;
    case SettingsTab.system:
      return FluentIcons.settings_24_regular;
    case SettingsTab.about:
      return FluentIcons.people_team_24_regular;
  }
}

String _tabLabel(SettingsTab tab) {
  switch (tab) {
    case SettingsTab.design:
      return 'מראה';
    case SettingsTab.text:
      return 'כתב';
    case SettingsTab.library:
      return 'ספריה';
    case SettingsTab.tools:
      return 'כלים';
    case SettingsTab.shortcuts:
      return 'קיצורי מקשים';
    case SettingsTab.system:
      return 'מערכת';
    case SettingsTab.about:
      return 'אודות';
  }
}
