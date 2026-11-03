import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';
import 'package:otzaria/widgets/navigation/search_result_navigator.dart';
import 'package:otzaria/tabs/models/external_book_matches.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:otzaria/theme/app_tokens.dart';

/// מיקום העמוד [page] ביחס ל-[pages] הממוינים: [exact] כשהוא עצמו התאמה,
/// ו-[previous]/[next] — ההתאמות הקרובות לפניו ואחריו (אינדקסים).
@visibleForTesting
({int? exact, int? previous, int? next}) externalMatchCursor(
  List<int> pages,
  int page,
) {
  int? previous;
  int? exact;
  for (var i = 0; i < pages.length; i++) {
    if (pages[i] < page) {
      previous = i;
    } else {
      if (pages[i] == page) exact = i;
      final next = exact == null ? i : i + 1;
      return (
        exact: exact,
        previous: previous,
        next: next < pages.length ? next : null,
      );
    }
  }
  return (exact: null, previous: previous, next: null);
}

/// סרגל ניווט בין עמודי התאמה שסופקו על-ידי מנוע חיפוש חיצוני (תוסף).
///
/// מוצג מתחת לסרגל העליון של קורא ה-PDF רק כשלטאב יש [ExternalBookMatches].
/// ההדגשה בתוך העמוד אינה באחריותו — ספרי היברובוקס הם לרוב סריקות ללא שכבת
/// טקסט, ולכן הערך המרכזי הוא הקפיצה המדויקת בין עמודי ההתאמה.
class PdfExternalMatchesBar extends StatefulWidget {
  final PdfBookTab tab;
  final Future<void> Function(int page) onNavigateToPage;

  /// חיפוש מחדש בתוך הספר דרך הספק החיצוני. null = אין ספק רשום, ושדה
  /// החיפוש מוסתר (הניווט בין ההתאמות הקיימות עדיין פעיל).
  final Future<ExternalBookMatches?> Function(String query)? onProviderSearch;

  const PdfExternalMatchesBar({
    super.key,
    required this.tab,
    required this.onNavigateToPage,
    this.onProviderSearch,
  });

  @override
  State<PdfExternalMatchesBar> createState() => _PdfExternalMatchesBarState();
}

class _PdfExternalMatchesBarState extends State<PdfExternalMatchesBar> {
  late final TextEditingController _queryController;

  /// העמוד שבקורא — גם אחרי גלילה ידנית, כדי ש"הבא" ימשיך מהמקום הנוכחי.
  int _page = 1;
  bool _searching = false;
  String? _error;

  ExternalBookMatches? get _matches => widget.tab.externalMatches.value;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController(text: _matches?.query ?? '');
    widget.tab.externalMatches.addListener(_onMatchesChanged);
    _page = widget.tab.pageNumber;
    widget.tab.pdfViewerController.addListener(_onViewerChanged);
  }

  @override
  void dispose() {
    widget.tab.pdfViewerController.removeListener(_onViewerChanged);
    widget.tab.externalMatches.removeListener(_onMatchesChanged);
    _queryController.dispose();
    super.dispose();
  }

  void _onViewerChanged() {
    final controller = widget.tab.pdfViewerController;
    if (!mounted || !controller.isReady || _matches == null) return;
    final page = controller.pageNumber;
    if (page == null || page == _page) return;
    setState(() => _page = page);
  }

  void _onMatchesChanged() {
    if (!mounted) return;
    setState(() {
      final query = _matches?.query;
      if (query != null && query.isNotEmpty) _queryController.text = query;
    });
  }

  Future<void> _goToIndex(int index) async {
    final matches = _matches;
    if (matches == null || matches.pages.isEmpty) return;
    final clamped = index.clamp(0, matches.pages.length - 1);
    setState(() => _page = matches.pages[clamped]);
    await widget.onNavigateToPage(matches.pages[clamped]);
  }

  Future<void> _runProviderSearch() async {
    final search = widget.onProviderSearch;
    final query = _queryController.text.trim();
    if (search == null || query.isEmpty || _searching) return;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final result = await search(query);
      if (!mounted) return;
      if (result == null || result.isEmpty) {
        setState(() => _error = 'לא נמצאו התאמות');
        return;
      }
      widget.tab.externalMatches.value = result;
      await _goToIndex(0);
    } catch (_) {
      if (mounted) setState(() => _error = 'החיפוש בספר נכשל');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ExternalBookMatches?>(
      valueListenable: widget.tab.externalMatches,
      builder: (context, matches, _) {
        if (matches == null) return const SizedBox.shrink();
        final theme = Theme.of(context);
        final pages = matches.pages;
        final hasPages = pages.isNotEmpty;
        final cursor = externalMatchCursor(pages, _page);
        final position = cursor.exact == null ? '–' : '${cursor.exact! + 1}';
        return Material(
          color: theme.colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: Row(
              children: [
                Icon(
                  OtzariaIcons.book_search_24_regular,
                  size: AppTokens.iconSM,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                if (widget.onProviderSearch != null)
                  SizedBox(
                    width: 220,
                    child: RtlTextField(
                      controller: _queryController,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _runProviderSearch(),
                      decoration: InputDecoration(
                        hintText: 'חיפוש בספר...',
                        isDense: true,
                        border: InputBorder.none,
                        errorText: _error,
                        suffixIcon: _searching
                            ? const Padding(
                                padding: EdgeInsets.all(8),
                                child: SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : IconButton(
                                icon: const Icon(
                                  OtzariaIcons.search_24_regular,
                                  size: AppTokens.iconSM,
                                ),
                                tooltip: 'חפש',
                                onPressed: _runProviderSearch,
                              ),
                      ),
                    ),
                  )
                else if (matches.query.isNotEmpty)
                  Flexible(
                    child: Text(
                      '"${matches.query}"',
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                const Spacer(),
                if (hasPages)
                  SearchResultNavigator(
                    axis: Axis.horizontal,
                    previousTooltip: 'המופע הקודם',
                    nextTooltip: 'המופע הבא',
                    onPrevious: cursor.previous == null
                        ? null
                        : () => _goToIndex(cursor.previous!),
                    onNext: cursor.next == null
                        ? null
                        : () => _goToIndex(cursor.next!),
                    counter: Tooltip(
                      message: 'רשימת עמודי ההתאמה',
                      child: AppPopupMenuButton<int>(
                        onSelected: _goToIndex,
                        entries: [
                          for (var i = 0; i < pages.length; i++)
                            AppMenuEntry(value: i, label: 'עמוד ${pages[i]}'),
                        ],
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 4,
                          ),
                          child: Text(
                            'עמוד $_page · $position/${pages.length}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  Text('אין התאמות', style: theme.textTheme.bodySmall),
                IconButton(
                  icon: const Icon(FluentIcons.dismiss_24_regular),
                  iconSize: AppTokens.iconSM,
                  tooltip: 'סגור את סרגל ההתאמות',
                  onPressed: () => widget.tab.externalMatches.value = null,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
