import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/search/utils/snippet_builder.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_book/utils/commentary_search_utils.dart';
import 'package:otzaria/theme/app_fonts.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;

/// ה-globalIndex של שורת התוצאה שתסומן ברשימת קטעי החיפוש.
///
/// כל מפרש תורם שורה אחת אך [currentIdx] מונה היקרויות — לכן השורה הנבחרת
/// היא האחרונה שה-globalIndex שלה <= currentIdx. השוואת שוויון ישירה תשאיר
/// את הניווט ללא סימון.
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
        fontFamily: settingsState.commentatorsFontFamily,
        color: colorScheme.onSurface,
        height: 1.5,
      ),
      highlightStyle: TextStyle(
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

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        if (item.isHeader) return _buildHeader(context, item.header!);
        return _buildResult(context, item.snippet!, selectedGlobalIndex);
      },
    );
  }

  Widget _buildHeader(BuildContext context, String header) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4, right: 4, left: 4),
      child: Row(
        children: [
          Icon(
            FluentIcons.text_align_right_24_regular,
            size: 16,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              header,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: Theme.of(context).colorScheme.primary,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResult(
    BuildContext context,
    CommentarySearchSnippet snippet,
    int selectedGlobalIndex,
  ) {
    final isSelected = snippet.globalIndex == selectedGlobalIndex;
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, settingsState) {
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? AppSurfaces.selectedItem(Theme.of(context).colorScheme)
                : null,
            border: Border.all(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outlineVariant,
              width: 1,
            ),
            borderRadius: AppTokens.borderRadiusAll,
          ),
          child: InkWell(
            onTap: () => widget.onSnippetTap(snippet.globalIndex),
            borderRadius: AppTokens.borderRadiusAll,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Text.rich(
                TextSpan(
                  children: _highlightSpans(context, settingsState, snippet),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
