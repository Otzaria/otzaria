import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/search/utils/snippet_builder.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/book_common/utils/commentary_search_utils.dart';
import 'package:otzaria/theme/app_fonts.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/widgets/lists/nav_tree_tile.dart';

/// מאתר את שורת התוצאה האחרונה שאינה אחרי [currentIdx], שמונה היקרויות
/// ולא שורות.
@visibleForTesting
int resolveSelectedSnippetGlobalIndex(
  List<CommentarySearchSnippet> snippets,
  int currentIdx,
) {
  var selected = -1;
  for (final snippet in snippets) {
    if (snippet.globalIndex > currentIdx) break;
    selected = snippet.globalIndex;
  }
  return selected;
}

/// שורה ברשימה: כותרת מפרש או קטע תוצאה.
class _SearchResultItem {
  final String? header;
  final CommentarySearchSnippet? snippet;

  const _SearchResultItem.header(this.header) : snippet = null;
  const _SearchResultItem.result(this.snippet) : header = null;

  bool get isHeader => header != null;
}

/// רשימת קטעי תוצאות החיפוש במפרשים, מקובצת לפי מפרש ועם סימון התוצאה
/// הנוכחית. משותפת לכרטיסיית המפרשים בטקסט ולזו של ה-PDF.
class CommentarySearchResultsList extends StatefulWidget {
  final String query;
  final List<CommentarySearchSnippet> snippets;

  /// אינדקס ההיקרות הנוכחית (מונה היקרויות, לא שורות).
  final int currentIdx;

  /// ניווט אל ההיקרות שבראש הקטע שנלחץ.
  final ValueChanged<int> onSnippetTap;

  const CommentarySearchResultsList({
    super.key,
    required this.query,
    required this.snippets,
    required this.currentIdx,
    required this.onSnippetTap,
  });

  @override
  State<CommentarySearchResultsList> createState() =>
      _CommentarySearchResultsListState();
}

class _CommentarySearchResultsListState
    extends State<CommentarySearchResultsList> {
  final Map<String, List<InlineSpan>> _snippetSpansCache = {};

  List<InlineSpan> _highlightSpans(
    BuildContext context,
    SettingsState settingsState,
    CommentarySearchSnippet snippet,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final cacheKey =
        '${settingsState.commentatorsFontFamily}|'
        '${colorScheme.onSurface.toARGB32()}|${widget.query}|'
        '${snippet.globalIndex}|${snippet.snippet}';
    final cached = _snippetSpansCache[cacheKey];
    if (cached != null) return cached;

    final spans = SnippetBuilder.highlightLiteral(
      plainText: snippet.snippet,
      query: widget.query,
      defaultStyle: TextStyle(
        fontSize: 14,
        fontFamily: AppFonts.renderFontFamily(
          settingsState.commentatorsFontFamily,
        ),
        color: colorScheme.onSurface,
        height: 1.5,
      ),
      highlightStyle: TextStyle(
        fontFamily: AppFonts.renderFontFamily(
          settingsState.commentatorsFontFamily,
        ),
        fontWeight: FontWeight.bold,
        fontVariations: AppFonts.boldFontVariations(
          settingsState.commentatorsFontFamily,
        ),
        fontSize: 16,
        color: colorScheme.error,
      ),
    );

    if (_snippetSpansCache.length > 500) _snippetSpansCache.clear();
    _snippetSpansCache[cacheKey] = spans;
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.query.isEmpty) return const SizedBox.shrink();
    if (widget.snippets.isEmpty) {
      // total>0 בלבד מגיע לכאן (על total==0 מוצג 'אין תוצאות' ע"י ההורה)
      return Center(
        child: Text(
          'טוען תוצאות...',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }

    final selectedGlobalIndex = resolveSelectedSnippetGlobalIndex(
      widget.snippets,
      widget.currentIdx,
    );

    final items = <_SearchResultItem>[];
    String? lastPath;
    for (final snippet in widget.snippets) {
      if (snippet.path != lastPath) {
        items.add(
          _SearchResultItem.header(utils.getTitleFromPath(snippet.path)),
        );
        lastPath = snippet.path;
      }
      items.add(_SearchResultItem.result(snippet));
    }

    return NavTreeFocusGroup(
      child: ListView.builder(
        padding: kNavTreeListPadding,
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          if (item.isHeader) return NavTreeHeader(title: item.header!);
          return NavTreeGroupCard(
            // הקבוצה נפתחת אחרי כותרת מפרש ונסגרת לפני הכותרת הבאה.
            isGroupStart: index == 0 || items[index - 1].isHeader,
            isGroupEnd: index == items.length - 1 || items[index + 1].isHeader,
            child: _buildResult(context, item.snippet!, selectedGlobalIndex),
          );
        },
      ),
    );
  }

  Widget _buildResult(
    BuildContext context,
    CommentarySearchSnippet snippet,
    int selectedGlobalIndex,
  ) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, settingsState) {
        return NavTreeContentRow(
          isSelected: snippet.globalIndex == selectedGlobalIndex,
          onTap: () => widget.onSnippetTap(snippet.globalIndex),
          child: Text.rich(
            TextSpan(
              children: _highlightSpans(context, settingsState, snippet),
            ),
          ),
        );
      },
    );
  }
}
