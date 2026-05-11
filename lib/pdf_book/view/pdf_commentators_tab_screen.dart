import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/tabs/models/pdf_commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/pdf_book/view/pdf_commentary_panel.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/widgets/misc/commentators_filter_button.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:otzaria/utils/navigation/open_book.dart';

/// מסך כרטסיית המפרשים של PDF — עצמאי לחלוטין, כמו CommentatorsTabScreen.
class PdfCommentatorsTabScreen extends StatefulWidget {
  final PdfCommentatorsTab tab;

  const PdfCommentatorsTabScreen({super.key, required this.tab});

  @override
  State<PdfCommentatorsTabScreen> createState() =>
      _PdfCommentatorsTabScreenState();
}

class _PdfCommentatorsTabScreenState extends State<PdfCommentatorsTabScreen> {
  // רשימת headings ממוינת (כותרת → מספר שורה בטקסט)
  List<MapEntry<String, int>>? _sortedHeadings;
  int _selectedHeadingIdx = 0;

  // תצוגת טקסט preview
  List<String>? _textLines;
  bool _previewExpanded = false;

  // חיפוש חיצוני המועבר ל-PdfCommentaryPanel
  final _searchController = TextEditingController();
  final _totalResultsNotifier = ValueNotifier<int>(0);
  final _currentIdxNotifier = ValueNotifier<int>(0);
  final _openFilterNotifier = ValueNotifier<int>(0);

  // GlobalKey לניווט חיפוש
  final _panelKey = GlobalKey<PdfCommentaryPanelState>();

  @override
  void initState() {
    super.initState();
    _initHeadings();
    _loadTextContent();
  }

  void _initHeadings() {
    final headings =
        widget.tab.sourceTab.pdfHeadings?.getSortedHeadings();
    if (headings == null || headings.isEmpty) return;
    _sortedHeadings = headings;

    // מאתחל לדף הנוכחי של ה-PDF
    final currentTitle = widget.tab.sourceTab.currentTitle.value;
    final idx = headings.indexWhere((e) => e.key == currentTitle);
    _selectedHeadingIdx = idx >= 0 ? idx : 0;
  }

  Future<void> _loadTextContent() async {
    final tab = widget.tab.sourceTab;
    try {
      final library = await DataRepository.instance.library;
      TextBook? textBook =
          library.findBookByTitle(tab.book.title, TextBook) as TextBook?;
      textBook ??=
          library.findBookByTitleFlexible(tab.book.title, TextBook)
              as TextBook?;
      if (textBook == null || !mounted) return;
      final text = await textBook.text;
      if (!mounted) return;
      setState(() {
        _textLines = text.split('\n');
      });
    } catch (e) {
      debugPrint('שגיאה בטעינת תוכן טקסט: $e');
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _totalResultsNotifier.dispose();
    _currentIdxNotifier.dispose();
    _openFilterNotifier.dispose();
    super.dispose();
  }

  /// מחשב את טווח השורות עבור heading נבחר
  ({int start, int end}) _getLineRange(int headingIdx) {
    final headings = _sortedHeadings;
    if (headings == null || headingIdx >= headings.length) {
      final fallback = widget.tab.sourceTab.currentTextLineNumber ?? 0;
      return (
        start: fallback,
        end: widget.tab.sourceTab.currentTextLineNumberEnd ?? fallback + 50
      );
    }
    final start = headings[headingIdx].value;
    final end = headingIdx + 1 < headings.length
        ? headings[headingIdx + 1].value - 1
        : start + 100;
    return (start: start, end: end);
  }

  /// שורות הטקסט לתצוגת preview עבור heading נבחר
  List<String> _getPreviewLines(int headingIdx) {
    final lines = _textLines;
    if (lines == null) return const [];
    final range = _getLineRange(headingIdx);
    return List.generate(
      (range.end - range.start + 1).clamp(0, 5),
      (i) {
        final idx = range.start + i;
        return idx < lines.length ? lines[idx].trim() : '';
      },
    ).where((l) => l.isNotEmpty).toList();
  }

  @override
  Widget build(BuildContext context) {
    // Lazy init — מנסה שוב אם pdfHeadings הגיע אחרי initState
    if (_sortedHeadings == null) {
      _initHeadings();
    }

    final sourceTab = widget.tab.sourceTab;
    final range = _getLineRange(_selectedHeadingIdx);
    final previewLines = _getPreviewLines(_selectedHeadingIdx);

    return Column(
      children: [
        _buildHeader(context, sourceTab: sourceTab, previewLines: previewLines),
        Expanded(
          child: PdfCommentaryPanel(
            key: _panelKey,
            tab: sourceTab,
            linksCount: sourceTab.links.length,
            linksLoading: false,
            isFullScreen: true,
            lineStartOverride: range.start,
            lineEndOverride: range.end,
            openBookCallback: (tab) {
              if (tab is TextBookTab) {
                openBook(context, tab.book, tab.index, '',
                    ignoreHistory: false);
              }
            },
            fontSize: 16.0,
            openFilterNotifier: _openFilterNotifier,
            externalSearchController: _searchController,
            externalTotalResultsNotifier: _totalResultsNotifier,
            externalCurrentIndexNotifier: _currentIdxNotifier,
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(
    BuildContext context, {
    required PdfBookTab sourceTab,
    required List<String> previewLines,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final headings = _sortedHeadings;

    // טקסט preview — שורה ראשונה בלבד, ללא HTML
    final plainFirst = previewLines.isNotEmpty
        ? previewLines.first
            .replaceAll(RegExp(r'<[^>]*>'), '')
            .replaceAll('&nbsp;', ' ')
            .trim()
        : '';
    final hasPreview = plainFirst.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border:
            Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      padding: const EdgeInsetsDirectional.only(
          start: 8, end: 8, top: 6, bottom: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // שורה יחידה: dropdown + פילטר + חיפוש + preview — הכל ביחד
          Row(
            children: [
              // Dropdown דף
              if (headings != null && headings.isNotEmpty)
                Flexible(
                  flex: 3,
                  child: _CompactDropdown<int>(
                    items: List.generate(headings.length, (i) => i),
                    labelOf: (i) => headings[i].key,
                    selected: _selectedHeadingIdx,
                    hint: 'דף',
                    onChanged: (i) {
                      if (i != null) {
                        setState(() {
                          _selectedHeadingIdx = i;
                          _previewExpanded = false;
                          _searchController.clear();
                        });
                      }
                    },
                  ),
                )
              else
                // אין headings — תצוגת דף נוכחי (read-only)
                Flexible(
                  flex: 3,
                  child: Container(
                    height: 30,
                    padding: const EdgeInsetsDirectional.only(start: 8, end: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      border: Border.all(color: colorScheme.outlineVariant),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: AlignmentDirectional.centerStart,
                    child: ValueListenableBuilder<String>(
                      valueListenable: sourceTab.currentTitle,
                      builder: (_, title, __) => Text(
                        title.isEmpty ? 'דף' : title,
                        style: Theme.of(context).textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 4),
              // כפתור בחירת מפרשים
              CommentatorsFilterButton(
                isActive: false,
                onPressed: () => _openFilterNotifier.value++,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 32, minHeight: 32),
                iconSize: 18,
              ),
              const SizedBox(width: 4),
              // שדה חיפוש
              Flexible(
                flex: 4,
                child: ValueListenableBuilder<int>(
                  valueListenable: _totalResultsNotifier,
                  builder: (context, total, _) {
                    return ValueListenableBuilder<int>(
                      valueListenable: _currentIdxNotifier,
                      builder: (context, currentIdx, _) {
                        return RtlTextField(
                          controller: _searchController,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: 'חיפוש...',
                            prefixIcon: const Icon(
                                FluentIcons.search_24_regular, size: 16),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (total > 0) ...[
                                        Text('${currentIdx + 1}/$total',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall),
                                        IconButton(
                                          icon: const Icon(
                                              FluentIcons
                                                  .chevron_up_24_regular,
                                              size: 16),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                              minWidth: 24, minHeight: 24),
                                          onPressed: currentIdx > 0
                                              ? () => _panelKey.currentState
                                                  ?.navigateSearchPrev()
                                              : null,
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                              FluentIcons
                                                  .chevron_down_24_regular,
                                              size: 16),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                              minWidth: 24, minHeight: 24),
                                          onPressed: currentIdx < total - 1
                                              ? () => _panelKey.currentState
                                                  ?.navigateSearchNext()
                                              : null,
                                        ),
                                      ],
                                      IconButton(
                                        icon: const Icon(
                                            FluentIcons.dismiss_24_regular,
                                            size: 16),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                            minWidth: 24, minHeight: 24),
                                        onPressed: () {
                                          _searchController.clear();
                                          setState(() {});
                                        },
                                      ),
                                    ],
                                  )
                                : null,
                            isDense: true,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8.0)),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              // Preview טקסט — inline, ניתן ללחיצה להרחבה
              if (hasPreview) ...[
                const SizedBox(width: 4),
                Flexible(
                  flex: 3,
                  child: GestureDetector(
                    onTap: () =>
                        setState(() => _previewExpanded = !_previewExpanded),
                    child: Container(
                      height: 30,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        border:
                            Border.all(color: colorScheme.outlineVariant),
                      ),
                      alignment: AlignmentDirectional.centerStart,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _previewExpanded
                                ? FluentIcons.chevron_up_24_regular
                                : FluentIcons.chevron_down_24_regular,
                            size: 12,
                            color: colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              plainFirst,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                      color: colorScheme.onSurface
                                          .withValues(alpha: 0.7)),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              textDirection: TextDirection.rtl,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          // הרחבת preview — מוצגת מתחת לשורה הראשית כשנלחץ
          if (hasPreview && _previewExpanded) ...[
            const SizedBox(height: 4),
            _buildPreview(context, previewLines),
          ],
        ],
      ),
    );
  }

  Widget _buildPreview(BuildContext context, List<String> lines) {
    final colorScheme = Theme.of(context).colorScheme;
    // מסיר תגיות HTML לתצוגה נקייה
    final plainFirst = lines.first
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .trim();
    final textStyle =
        Theme.of(context).textTheme.bodySmall ?? const TextStyle();

    return LayoutBuilder(builder: (context, constraints) {
      final tp = TextPainter(
        text: TextSpan(text: plainFirst, style: textStyle),
        maxLines: 1,
        textDirection: TextDirection.rtl,
      )..layout(maxWidth: constraints.maxWidth - 24);
      final overflows = tp.didExceedMaxLines || lines.length > 1;

      return GestureDetector(
        onTap: overflows
            ? () => setState(() => _previewExpanded = !_previewExpanded)
            : null,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          clipBehavior: Clip.hardEdge,
          child: AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeInOut,
            child: _previewExpanded
                ? ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 160),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        lines
                            .map((l) => l
                                .replaceAll(RegExp(r'<[^>]*>'), '')
                                .replaceAll('&nbsp;', ' ')
                                .trim())
                            .join('\n'),
                        style: textStyle,
                        textDirection: TextDirection.rtl,
                      ),
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                            start: 8, end: 8, top: 5, bottom: 5),
                        child: Text(
                          plainFirst,
                          style: textStyle,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          textDirection: TextDirection.rtl,
                        ),
                      ),
                      if (overflows)
                        Icon(
                          FluentIcons.chevron_down_24_regular,
                          size: 10,
                          color: colorScheme.onSurface.withValues(alpha: 0.4),
                        ),
                      if (overflows) const SizedBox(height: 2),
                    ],
                  ),
          ),
        ),
      );
    });
  }
}

// Dropdown קומפקטי — זהה ל-CommentatorsTabScreen
class _CompactDropdown<T> extends StatelessWidget {
  final List<T> items;
  final String Function(T) labelOf;
  final T? selected;
  final String hint;
  final ValueChanged<T?> onChanged;

  const _CompactDropdown({
    super.key,
    required this.items,
    required this.labelOf,
    required this.selected,
    required this.hint,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DropdownButtonHideUnderline(
      child: Container(
        height: 30,
        padding: const EdgeInsetsDirectional.only(start: 8, end: 2),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: DropdownButton<T>(
          value: selected,
          hint: Text(hint,
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis),
          isExpanded: true,
          isDense: true,
          items: items
              .map((item) => DropdownMenuItem<T>(
                    value: item,
                    child: Text(
                      labelOf(item),
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                ))
            .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

