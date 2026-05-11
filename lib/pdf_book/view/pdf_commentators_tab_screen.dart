import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/tabs/models/pdf_commentators_tab.dart';
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
  List<MapEntry<String, int>>? _sortedHeadings;
  int _selectedHeadingIdx = 0;
  int _selectedParagraphIdx = 0;
  List<String>? _textLines;

  final _searchController = TextEditingController();
  final _totalResultsNotifier = ValueNotifier<int>(0);
  final _currentIdxNotifier = ValueNotifier<int>(0);
  final _openFilterNotifier = ValueNotifier<int>(0);
  final _panelKey = GlobalKey<PdfCommentaryPanelState>();

  @override
  void initState() {
    super.initState();
    _initHeadings();
    _loadTextContent();
  }

  void _initHeadings() {
    final headings = widget.tab.sourceTab.pdfHeadings?.getSortedHeadings();
    if (headings == null || headings.isEmpty) return;
    _sortedHeadings = headings;
    final currentTitle = widget.tab.sourceTab.currentTitle.value;
    final idx = headings.indexWhere((e) => e.key == currentTitle);
    _selectedHeadingIdx = idx >= 0 ? idx : 0;
    _selectedParagraphIdx = 0;
  }

  Future<void> _loadTextContent() async {
    final tab = widget.tab.sourceTab;
    try {
      final library = await DataRepository.instance.library;
      TextBook? textBook =
          library.findBookByTitle(tab.book.title, TextBook) as TextBook?;
      textBook ??=
          library.findBookByTitleFlexible(tab.book.title, TextBook) as TextBook?;
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

  /// פסקאות (שורות טקסט לא-ריקות) בתוך heading נבחר
  List<({int lineIdx, String text})> _getParagraphs(int headingIdx) {
    final lines = _textLines;
    if (lines == null) return const [];
    final headings = _sortedHeadings;
    if (headings == null || headingIdx >= headings.length) return const [];
    final start = headings[headingIdx].value;
    final end = headingIdx + 1 < headings.length
        ? headings[headingIdx + 1].value - 1
        : start + 100;
    final result = <({int lineIdx, String text})>[];
    for (int i = start; i <= end && i < lines.length; i++) {
      final clean = lines[i]
          .replaceAll(RegExp(r'<[^>]*>'), '')
          .replaceAll('&nbsp;', ' ')
          .trim();
      if (clean.isNotEmpty) result.add((lineIdx: i, text: clean));
    }
    return result;
  }

  /// טווח שורות לחלונית המפרשים
  ({int start, int end}) _getLineRangeForPara(
    int headingIdx,
    List<({int lineIdx, String text})> paragraphs,
    int paraIdx,
  ) {
    if (paragraphs.isNotEmpty && paraIdx < paragraphs.length) {
      final lineIdx = paragraphs[paraIdx].lineIdx;
      final nextLineIdx = paraIdx + 1 < paragraphs.length
          ? paragraphs[paraIdx + 1].lineIdx - 1
          : lineIdx + 1;
      return (start: lineIdx, end: nextLineIdx);
    }
    final headings = _sortedHeadings;
    if (headings == null || headingIdx >= headings.length) {
      final fallback = widget.tab.sourceTab.currentTextLineNumber ?? 0;
      return (
        start: fallback,
        end: widget.tab.sourceTab.currentTextLineNumberEnd ?? fallback + 50,
      );
    }
    final start = headings[headingIdx].value;
    final end = headingIdx + 1 < headings.length
        ? headings[headingIdx + 1].value - 1
        : start + 100;
    return (start: start, end: end);
  }

  /// טקסט preview — אם פסקה ≤3 מילים מוסיף גם תחילת הבאה
  String _getPreviewText(
      List<({int lineIdx, String text})> paragraphs, int paraIdx) {
    if (paragraphs.isEmpty || paraIdx >= paragraphs.length) return '';
    final text = paragraphs[paraIdx].text;
    final words =
        text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length <= 3 && paraIdx + 1 < paragraphs.length) {
      return '$text ${paragraphs[paraIdx + 1].text}';
    }
    return text;
  }

  @override
  Widget build(BuildContext context) {
    if (_sortedHeadings == null) _initHeadings();
    final paragraphs = _getParagraphs(_selectedHeadingIdx);
    final safeParaIdx = paragraphs.isEmpty
        ? 0
        : _selectedParagraphIdx.clamp(0, paragraphs.length - 1);
    final range = _getLineRangeForPara(_selectedHeadingIdx, paragraphs, safeParaIdx);
    final previewText = _getPreviewText(paragraphs, safeParaIdx);

    return Column(
      children: [
        _buildHeader(context, paragraphs: paragraphs, safeParaIdx: safeParaIdx,
            previewText: previewText),
        Expanded(
          child: PdfCommentaryPanel(
            key: _panelKey,
            tab: widget.tab.sourceTab,
            linksCount: widget.tab.sourceTab.links.length,
            linksLoading: false,
            isFullScreen: true,
            lineStartOverride: range.start,
            lineEndOverride: range.end,
            openBookCallback: (tab) {
              if (tab is TextBookTab) {
                openBook(context, tab.book, tab.index, '', ignoreHistory: false);
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
    required List<({int lineIdx, String text})> paragraphs,
    required int safeParaIdx,
    required String previewText,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final headings = _sortedHeadings;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Row(
        children: [
          // 1. כותרת
          Flexible(
            flex: 2,
            child: Text(
              widget.tab.sourceTab.book.title,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          const SizedBox(width: 4),
          // 2. דף (heading)
          if (headings != null && headings.isNotEmpty)
            Flexible(
              flex: 2,
              child: _CompactDropdown<int>(
                items: List.generate(headings.length, (i) => i),
                labelOf: (i) => headings[i].key,
                selected: _selectedHeadingIdx,
                hint: 'דף',
                onChanged: (i) {
                  if (i != null) {
                    setState(() {
                      _selectedHeadingIdx = i;
                      _selectedParagraphIdx = 0;
                      _searchController.clear();
                    });
                  }
                },
              ),
            ),
          const SizedBox(width: 4),
          // 3. פסקה
          if (paragraphs.isNotEmpty)
            Flexible(
              flex: 2,
              child: _CompactDropdown<int>(
                items: List.generate(paragraphs.length, (i) => i),
                labelOf: (i) {
                  final words = paragraphs[i]
                      .text
                      .split(RegExp(r'\s+'))
                      .where((w) => w.isNotEmpty)
                      .toList();
                  final preview = words.take(4).join(' ');
                  return words.length > 4 ? '$preview...' : preview;
                },
                selected: safeParaIdx,
                hint: 'פסקה',
                onChanged: (i) {
                  if (i != null) {
                    setState(() {
                      _selectedParagraphIdx = i;
                      _searchController.clear();
                    });
                  }
                },
              ),
            ),
          const SizedBox(width: 4),
          // 4. תצוגת טקסט (overlay)
          if (previewText.isNotEmpty)
            Flexible(
              flex: 2,
              child: _TextPreviewButton(text: previewText),
            ),
          const SizedBox(width: 4),
          // 5. חיפוש
          Flexible(
            flex: 3,
            child: _buildSearchField(context),
          ),
          const SizedBox(width: 4),
          // 6. כפתור בחירת מפרשים
          CommentatorsFilterButton(
            isActive: false,
            onPressed: () => _openFilterNotifier.value++,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            iconSize: 18,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: _totalResultsNotifier,
      builder: (context, total, _) => ValueListenableBuilder<int>(
        valueListenable: _currentIdxNotifier,
        builder: (context, currentIdx, _) => RtlTextField(
          controller: _searchController,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'חיפוש...',
            prefixIcon: const Icon(FluentIcons.search_24_regular, size: 16),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            suffixIcon: _searchController.text.isNotEmpty
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (total > 0) ...[
                        Text('${currentIdx + 1}/$total',
                            style: Theme.of(context).textTheme.bodySmall),
                        IconButton(
                          icon: const Icon(FluentIcons.chevron_up_24_regular,
                              size: 16),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 24, minHeight: 24),
                          onPressed: currentIdx > 0
                              ? () =>
                                  _panelKey.currentState?.navigateSearchPrev()
                              : null,
                        ),
                        IconButton(
                          icon: const Icon(FluentIcons.chevron_down_24_regular,
                              size: 16),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 24, minHeight: 24),
                          onPressed: currentIdx < total - 1
                              ? () =>
                                  _panelKey.currentState?.navigateSearchNext()
                              : null,
                        ),
                      ],
                      IconButton(
                        icon: const Icon(FluentIcons.dismiss_24_regular,
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
        ),
      ),
    );
  }
}

// ─── כפתור preview עם overlay ─────────────────────────────────────────────────

class _TextPreviewButton extends StatefulWidget {
  final String text;
  const _TextPreviewButton({required this.text});

  @override
  State<_TextPreviewButton> createState() => _TextPreviewButtonState();
}

class _TextPreviewButtonState extends State<_TextPreviewButton> {
  OverlayEntry? _entry;
  final _layerLink = LayerLink();

  void _toggle() {
    if (_entry != null) {
      _close();
      return;
    }
    _entry = OverlayEntry(
      builder: (ctx) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _close,
            ),
          ),
          CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            targetAnchor: Alignment.bottomLeft,
            followerAnchor: Alignment.topLeft,
            offset: const Offset(0, 2),
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxHeight: 200, maxWidth: 320),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(10),
                  child: Text(
                    widget.text,
                    style: const TextStyle(fontSize: 13),
                    textDirection: TextDirection.rtl,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_entry!);
    setState(() {});
  }

  void _close() {
    _entry?.remove();
    _entry = null;
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(_TextPreviewButton old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text && _entry != null) _close();
  }

  @override
  void dispose() {
    _entry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isOpen = _entry != null;
    return CompositedTransformTarget(
      link: _layerLink,
      child: GestureDetector(
        onTap: _toggle,
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: isOpen ? colorScheme.primaryContainer : colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isOpen ? colorScheme.primary : colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isOpen
                    ? FluentIcons.chevron_up_24_regular
                    : FluentIcons.text_description_24_regular,
                size: 14,
                color: isOpen
                    ? colorScheme.primary
                    : colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  widget.text,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  textDirection: TextDirection.rtl,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Dropdown קומפקטי ──────────────────────────────────────────────────────────

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


