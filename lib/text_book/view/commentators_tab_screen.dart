import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/models/commentators_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/commentary_list_base.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:otzaria/widgets/misc/commentators_filter_button.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';


const _kAllChapter = -1;

class CommentatorsTabScreen extends StatefulWidget {
  final CommentatorsTab tab;
  final Function(OpenedTab) openBookCallback;

  const CommentatorsTabScreen({
    super.key,
    required this.tab,
    required this.openBookCallback,
  });

  @override
  State<CommentatorsTabScreen> createState() => _CommentatorsTabScreenState();
}

class _CommentatorsTabScreenState extends State<CommentatorsTabScreen> {
  TocEntry? _selectedChapter;
  int _selectedVerseIdx = _kAllChapter;

  final _searchController = TextEditingController();
  final _totalResultsNotifier = ValueNotifier<int>(0);
  final _currentIdxNotifier = ValueNotifier<int>(0);
  final _openFilterNotifier = ValueNotifier<int>(0);

  final _commentaryKey = GlobalKey<CommentaryListBaseState>();
  bool _searchExpanded = false;

  @override
  void initState() {
    super.initState();
    // טעינת הספר והמפרשים ב-BLoC העצמאי
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final settings = context.read<SettingsBloc>().state;
      widget.tab.bloc.add(LoadContent(
        fontSize: settings.fontSize,
        showSplitView: false,
        removeNikud: settings.defaultRemoveNikud,
        loadCommentators: true,
      ));
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _totalResultsNotifier.dispose();
    _currentIdxNotifier.dispose();
    _openFilterNotifier.dispose();
    super.dispose();
  }

  List<TocEntry> _getChapters(List<TocEntry> toc) {
    final children = toc.expand((e) => e.children).toList();
    return children.isNotEmpty ? children : toc;
  }

  ({TocEntry? chapter, int verseIdx}) _findPos(
      List<TocEntry> chapters, int lineIndex) {
    TocEntry? bestChapter;
    int bestVerseIdx = _kAllChapter;
    for (final ch in chapters) {
      if (ch.index <= lineIndex) {
        bestChapter = ch;
        bestVerseIdx = _kAllChapter;
        for (int i = 0; i < ch.children.length; i++) {
          if (ch.children[i].index <= lineIndex) {
            bestVerseIdx = i;
          } else {
            break;
          }
        }
      } else {
        break;
      }
    }
    return (chapter: bestChapter, verseIdx: bestVerseIdx);
  }

  /// ממיר lineIndex ל-verseIdx עבור dropdown:
  /// - ספר עם פסוקי TOC → אינדקס הפסוק
  /// - ספר ללא פסוקי TOC → offset מתחילת הפרק
  int _lineToVerseIdx(TocEntry chapter, List<TocEntry> chapters, int lineIndex) {
    if (chapter.children.isNotEmpty) {
      for (int i = 0; i < chapter.children.length; i++) {
        if (chapter.children[i].index == lineIndex ||
            (i + 1 < chapter.children.length &&
                lineIndex < chapter.children[i + 1].index &&
                lineIndex >= chapter.children[i].index)) {
          return i;
        }
      }
      return _kAllChapter;
    } else {
      // ספר ללא TOC פסוק — offset מתחילת הפרק
      final offset = lineIndex - chapter.index;
      return offset >= 0 ? offset : _kAllChapter;
    }
  }

  List<int>? _computeIndexes(
      List<TocEntry> chapters, TocEntry? chapter, int verseIdx) {
    if (chapter == null) return null;

    if (verseIdx != _kAllChapter) {
      if (chapter.children.isNotEmpty) {
        // בחירת פסוק לפי TOC
        if (verseIdx < chapter.children.length) {
          final verse = chapter.children[verseIdx];
          if (verseIdx + 1 < chapter.children.length) {
            final nextIdx = chapter.children[verseIdx + 1].index;
            final count = nextIdx - verse.index;
            if (count > 1 && count <= 200) {
              return List.generate(count, (j) => verse.index + j);
            }
          }
          return [verse.index];
        }
      } else {
        // בחירת שורה/פסקה (ספרים ללא מבנה פסוק ב-TOC)
        // verseIdx = offset מתחילת הפרק
        return [chapter.index + verseIdx];
      }
    }

    // כל הפרק
    final ci = chapters.indexOf(chapter);
    if (ci >= 0 && ci + 1 < chapters.length) {
      final nextStart = chapters[ci + 1].index;
      final count = nextStart - chapter.index;
      if (count > 0) {
        return List.generate(count.clamp(1, 3000), (j) => chapter.index + j);
      }
    }
    if (chapter.children.isNotEmpty) {
      final lastChild = chapter.children.last;
      final count = lastChild.index - chapter.index + 1;
      if (count > 0) {
        return List.generate(count.clamp(1, 3000), (j) => chapter.index + j);
      }
    }
    return [chapter.index];
  }

  /// מחשב כמה שורות יש בפרק (לספרים ללא TOC ברמת פסוק)
  int _chapterLineCount(List<TocEntry> chapters, TocEntry chapter) {
    final ci = chapters.indexOf(chapter);
    final int end;
    if (ci >= 0 && ci + 1 < chapters.length) {
      end = chapters[ci + 1].index - 1;
    } else {
      end = chapter.index + 199;
    }
    return (end - chapter.index + 1).clamp(0, 200);
  }

  /// טוען את כל ה-links עבור הטווח הנוכחי דרך ה-BLoC העצמאי
  void _triggerLinkLoad(List<int> indices) {
    if (indices.isEmpty) return;
    widget.tab.bloc.add(LoadAllLinksForIndices(indices));
  }

  void _onChapterSelected(TocEntry ch, List<TocEntry> chapters) {
    setState(() {
      _selectedChapter = ch;
      _selectedVerseIdx = _kAllChapter;
    });
    // טוען links לכל הפרק
    final ci = chapters.indexOf(ch);
    final int endIdx;
    if (ci + 1 < chapters.length) {
      endIdx = chapters[ci + 1].index - 1;
    } else if (ch.children.isNotEmpty) {
      endIdx = ch.children.last.index;
    } else {
      endIdx = ch.index + 100;
    }
    final count = (endIdx - ch.index + 1).clamp(1, 3000);
    _triggerLinkLoad(List.generate(count, (j) => ch.index + j));
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<TextBookBloc>.value(
      value: widget.tab.bloc,
      child: Builder(builder: (context) {
        return BlocConsumer<TextBookBloc, TextBookState>(
          listenWhen: (_, __) => false, // BLoC עצמאי — לא עוקב אחרי שינויים חיצוניים
          listener: (_, __) {},
          buildWhen: (prev, curr) {
            if (prev is TextBookLoaded && curr is TextBookLoaded) {
              return prev.fontSize != curr.fontSize ||
                  prev.tableOfContents != curr.tableOfContents ||
                  prev.links != curr.links ||
                  prev.availableCommentators != curr.availableCommentators;
            }
            return true;
          },
          builder: (context, state) {
            if (state is! TextBookLoaded) {
              return const Center(child: CircularProgressIndicator());
            }

            final chapters = _getChapters(state.tableOfContents);

            // טעינת links ראשונית (בפעם הראשונה)
            if (_selectedChapter == null && chapters.isNotEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                final lineIndex = state.selectedIndex ??
                    (state.visibleIndices.isNotEmpty
                        ? state.visibleIndices.first
                        : 0);
                final pos = _findPos(chapters, lineIndex);
                if (pos.chapter != null) {
                  final hasSelectedLine =
                      widget.tab.initialSelectedLine != null;
                  if (hasSelectedLine) {
                    // הייתה שורה שנבחרה — פותח עליה בלבד
                    _triggerLinkLoad([lineIndex]);
                    setState(() {
                      _selectedChapter = pos.chapter;
                      _selectedVerseIdx = _lineToVerseIdx(
                          pos.chapter!, chapters, lineIndex);
                    });
                  } else {
                    // אין בחירה — פותח על כל הפרק
                    final chIdx = chapters.indexOf(pos.chapter!);
                    final int endIdx;
                    if (chIdx + 1 < chapters.length) {
                      endIdx = chapters[chIdx + 1].index - 1;
                    } else if (pos.chapter!.children.isNotEmpty) {
                      endIdx = pos.chapter!.children.last.index;
                    } else {
                      endIdx = pos.chapter!.index + 100;
                    }
                    final count =
                        (endIdx - pos.chapter!.index + 1).clamp(1, 3000);
                    _triggerLinkLoad(List.generate(
                        count, (j) => pos.chapter!.index + j));
                    setState(() {
                      _selectedChapter = pos.chapter;
                      _selectedVerseIdx = _kAllChapter;
                    });
                  }
                }
              });
            }

            final effectiveIndexes =
                _computeIndexes(chapters, _selectedChapter, _selectedVerseIdx);

            final chapterLabel = _tocLabel(chapters, 'פרק');
            final hasVerses =
                _selectedChapter != null && _selectedChapter!.children.isNotEmpty;
            final verseLabel = hasVerses
                ? _tocLabel(_selectedChapter!.children, 'פסוק')
                : 'פסוק';

            return Column(
              children: [
                _buildHeader(
                  context,
                  state: state,
                  chapters: chapters,
                  chapterLabel: chapterLabel,
                  verseLabel: verseLabel,
                  hasVerses: hasVerses,
                  effectiveIndexes: effectiveIndexes,
                ),
                Expanded(
                  child: CommentaryListBase(
                    key: _commentaryKey,
                    openBookCallback: widget.openBookCallback,
                    fontSize: state.fontSize,
                    indexes: effectiveIndexes,
                    showSearch: true,
                    useAvailableCommentators: true,
                    externalSearchController: _searchController,
                    externalTotalResultsNotifier: _totalResultsNotifier,
                    externalCurrentIndexNotifier: _currentIdxNotifier,
                    openFilterNotifier: _openFilterNotifier,
                  ),
                ),
              ],
            );
          },
        );
      }),
    );
  }

  void _selectVerseAndLoad(int verseIdx, List<TocEntry> chapters) {
    setState(() => _selectedVerseIdx = verseIdx);
    if (verseIdx == _kAllChapter) {
      _onChapterSelected(_selectedChapter!, chapters);
    } else if (_selectedChapter != null &&
        verseIdx < _selectedChapter!.children.length) {
      final verse = _selectedChapter!.children[verseIdx];
      final int endIdx = (verseIdx + 1 < _selectedChapter!.children.length)
          ? _selectedChapter!.children[verseIdx + 1].index - 1
          : verse.index + 50;
      final count = (endIdx - verse.index + 1).clamp(1, 200);
      _triggerLinkLoad(List.generate(count, (j) => verse.index + j));
    }
  }

  void _selectParaAndLoad(int paraIdx, List<TocEntry> chapters) {
    setState(() => _selectedVerseIdx = paraIdx);
    if (paraIdx == _kAllChapter) {
      _onChapterSelected(_selectedChapter!, chapters);
    } else if (_selectedChapter != null) {
      _triggerLinkLoad([_selectedChapter!.index + paraIdx]);
    }
  }

  Widget _buildHeader(
    BuildContext context, {
    required TextBookLoaded state,
    required List<TocEntry> chapters,
    required String chapterLabel,
    required String verseLabel,
    required bool hasVerses,
    required List<int>? effectiveIndexes,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    // בנייה של טקסט preview עבור הפסקה הנבחרת
    String previewText = '';
    if (effectiveIndexes != null && effectiveIndexes.isNotEmpty) {
      final lines = effectiveIndexes
          .where((i) => i >= 0 && i < state.content.length)
          .map((i) => state.content[i]
              .replaceAll(RegExp(r'<[^>]*>'), '')
              .replaceAll(RegExp(r'&[a-zA-Z]+;'), ' ')
              .replaceAll('&nbsp;', ' ')
              .trim())
          .where((l) => l.isNotEmpty)
          .toList();
      if (lines.isNotEmpty) {
        if (_selectedVerseIdx == _kAllChapter) {
          previewText = lines.join('\n');
        } else {
          previewText = lines.first;
        }
      }
    }

    // חישוב ניווט לפסוק/פסקה
    final verseCount = hasVerses ? (_selectedChapter?.children.length ?? 0) : 0;
    final lineCount = (!hasVerses && _selectedChapter != null)
        ? _chapterLineCount(chapters, _selectedChapter!)
        : 0;
    final hasNavItems = hasVerses ? verseCount > 0 : lineCount > 1;
    final listIdx = _selectedVerseIdx == _kAllChapter ? 0 : _selectedVerseIdx + 1;
    final maxListIdx = hasVerses ? verseCount : lineCount;

    // פריטי dropdown פסוק/פסקה
    final verseItems = [
      _kAllChapter,
      if (hasVerses)
        ...List.generate(_selectedChapter?.children.length ?? 0, (i) => i)
      else
        ...List.generate(lineCount, (i) => i),
    ];
    String verseItemLabel(int i) => i == _kAllChapter
        ? 'כל ה$chapterLabel'
        : hasVerses
            ? _selectedChapter!.children[i].text
            : 'פסקה ${i + 1}';

    final bodySmall = Theme.of(context).textTheme.bodySmall;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 380;
        final showSearchField = !isNarrow || _searchExpanded;

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: 0.08),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  // ── Section 1: filter + title ─────────────────────────────
                  Expanded(
                    flex: 2,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CommentatorsFilterButton(
                            isActive: false,
                            onPressed: () => _openFilterNotifier.value++,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 26, minHeight: 26),
                            iconSize: 15,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              'מפרשים על ${state.book.title}',
                              style: bodySmall?.copyWith(
                                  fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // ── Section 2: chapter dropdown ───────────────────────────
                  if (chapters.isNotEmpty) ...[
                    const _VDiv(),
                    Expanded(
                      flex: 2,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            value: _selectedChapter == null
                                ? null
                                : () {
                                    final i =
                                        chapters.indexOf(_selectedChapter!);
                                    return i >= 0 ? i : null;
                                  }(),
                            isExpanded: true,
                            isDense: true,
                            alignment: AlignmentDirectional.centerStart,
                            hint: Text(chapterLabel,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.start,
                                style: bodySmall),
                            icon: const SizedBox.shrink(),
                            iconSize: 0,
                            items: List.generate(
                              chapters.length,
                              (i) => DropdownMenuItem<int>(
                                value: i,
                                alignment: AlignmentDirectional.centerStart,
                                child: Text(chapters[i].text,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.start,
                                    style: bodySmall),
                              ),
                            ),
                            onChanged: (i) {
                              if (i != null) {
                                setState(() {
                                  _selectedChapter = chapters[i];
                                  _selectedVerseIdx = _kAllChapter;
                                });
                                _onChapterSelected(chapters[i], chapters);
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                  // ── Section 3: nav + verse dropdown ──────────────────────
                  if (hasNavItems && _selectedChapter != null) ...[
                    const _VDiv(),
                    _NavArrow(
                      icon: FluentIcons.chevron_left_24_regular,
                      enabled: listIdx > 0,
                      onPressed: () {
                        final newListIdx = listIdx - 1;
                        final newIdx =
                            newListIdx == 0 ? _kAllChapter : newListIdx - 1;
                        if (hasVerses) {
                          _selectVerseAndLoad(newIdx, chapters);
                        } else {
                          _selectParaAndLoad(newIdx, chapters);
                        }
                      },
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 80),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 2),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            value: _selectedVerseIdx,
                            isExpanded: true,
                            isDense: true,
                            hint: Text(hasVerses ? verseLabel : 'פסקה',
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: bodySmall),
                            icon: const SizedBox.shrink(),
                            iconSize: 0,
                            items: verseItems
                                .map((i) => DropdownMenuItem<int>(
                                      value: i,
                                      alignment: AlignmentDirectional.center,
                                      child: Text(verseItemLabel(i),
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                          style: bodySmall),
                                    ))
                                .toList(),
                            onChanged: (i) {
                              if (i == null) return;
                              if (hasVerses) {
                                _selectVerseAndLoad(i, chapters);
                              } else {
                                _selectParaAndLoad(i, chapters);
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                    _NavArrow(
                      icon: FluentIcons.chevron_right_24_regular,
                      enabled: listIdx < maxListIdx,
                      onPressed: () {
                        final newListIdx = listIdx + 1;
                        final newIdx =
                            newListIdx == 0 ? _kAllChapter : newListIdx - 1;
                        if (hasVerses) {
                          _selectVerseAndLoad(newIdx, chapters);
                        } else {
                          _selectParaAndLoad(newIdx, chapters);
                        }
                      },
                    ),
                  ],
                  // ── Section 4: preview ────────────────────────────────────
                  if (previewText.isNotEmpty) ...[
                    const _VDiv(),
                    Expanded(
                      flex: 2,
                      child: _TextPreviewButton(
                        text: previewText,
                        naked: false,
                        canOpen: previewText
                                .split(RegExp(r'\s+'))
                                .where((w) => w.isNotEmpty)
                                .length >
                            3,
                      ),
                    ),
                  ],
                  // ── Section 5: search ─────────────────────────────────────
                  const _VDiv(),
                  if (showSearchField)
                    Expanded(
                      flex: 3,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 4),
                        child: _buildSearchField(context,
                            showCollapseButton: isNarrow),
                      ),
                    )
                  else
                    IconButton(
                      icon: const Icon(FluentIcons.search_24_regular, size: 16),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      constraints:
                          const BoxConstraints(minWidth: 36, minHeight: 36),
                      tooltip: 'חיפוש',
                      onPressed: () =>
                          setState(() => _searchExpanded = true),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSearchField(BuildContext context,
      {bool showCollapseButton = false}) {
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
                      if (total > 1) ...[
                        Text('${currentIdx + 1}/$total',
                            style: Theme.of(context).textTheme.bodySmall),
                        IconButton(
                          icon: const Icon(FluentIcons.chevron_up_24_regular,
                              size: 16),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 24, minHeight: 24),
                          onPressed: currentIdx > 0
                              ? () => _commentaryKey.currentState
                                  ?.navigateSearchPrev()
                              : null,
                        ),
                        IconButton(
                          icon: const Icon(
                              FluentIcons.chevron_down_24_regular, size: 16),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 24, minHeight: 24),
                          onPressed: currentIdx < total - 1
                              ? () => _commentaryKey.currentState
                                  ?.navigateSearchNext()
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
                          setState(() {
                            if (showCollapseButton) _searchExpanded = false;
                          });
                        },
                      ),
                    ],
                  )
                : showCollapseButton
                    ? IconButton(
                        icon: const Icon(FluentIcons.dismiss_24_regular,
                            size: 16),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                            minWidth: 24, minHeight: 24),
                        onPressed: () =>
                            setState(() => _searchExpanded = false),
                      )
                    : null,
            isDense: true,
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(8.0)),
          ),
        ),
      ),
    );
  }

  String _tocLabel(List<TocEntry> entries, String fallback) {
    if (entries.isEmpty) return fallback;
    final text = entries.first.text.trim();
    final match = RegExp(r'^([א-ת]+)').firstMatch(text);
    final base = match?.group(1)?.trim() ?? '';
    return base.isNotEmpty ? base : fallback;
  }
}

// ─── Divider אנכי קומפקטי לתוך ה-pill ────────────────────────────────────────

class _VDiv extends StatelessWidget {
  const _VDiv();

  @override
  Widget build(BuildContext context) => VerticalDivider(
        width: 1,
        indent: 6,
        endIndent: 6,
        color: Theme.of(context).colorScheme.outlineVariant,
      );
}

// ─── כפתור חץ ניווט קומפקטי ───────────────────────────────────────────────

class _NavArrow extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  const _NavArrow({
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 30,
      height: 36,
      child: IconButton(
        padding: EdgeInsets.zero,
        icon: Icon(icon, size: 18),
        onPressed: enabled ? onPressed : null,
        style: IconButton.styleFrom(
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}



// ─── כפתור preview עם overlay ──────────────────────────────────────────────

class _TextPreviewButton extends StatefulWidget {
  final String text;
  final bool naked;
  final bool canOpen;
  const _TextPreviewButton(
      {required this.text, this.naked = false, this.canOpen = true});

  @override
  State<_TextPreviewButton> createState() => _TextPreviewButtonState();
}

class _TextPreviewButtonState extends State<_TextPreviewButton> {
  OverlayEntry? _entry;
  final _layerLink = LayerLink();

  void _toggle() {
    if (!widget.canOpen) return;
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
            targetAnchor: Alignment.bottomCenter,
            followerAnchor: Alignment.topCenter,
            offset: const Offset(0, 2),
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200, maxWidth: 320),
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

    // מצב naked — אייקון בלבד (לשימוש בתוך ה-pill)
    if (widget.naked) {
      return CompositedTransformTarget(
        link: _layerLink,
        child: IconButton(
          onPressed: _toggle,
          icon: Icon(
            isOpen
                ? FluentIcons.chevron_up_24_regular
                : FluentIcons.text_description_24_regular,
            size: 16,
            color: isOpen
                ? colorScheme.primary
                : colorScheme.onSurface.withValues(alpha: 0.6),
          ),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          tooltip: isOpen ? 'סגור תצוגה' : 'תצוגה מקדימה',
        ),
      );
    }

    return CompositedTransformTarget(
      link: _layerLink,
      child: GestureDetector(
        onTap: _toggle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isOpen
                    ? FluentIcons.chevron_up_24_regular
                    : FluentIcons.text_description_24_regular,
                size: 13,
                color: !widget.canOpen
                    ? colorScheme.onSurface.withValues(alpha: 0.35)
                    : isOpen
                        ? colorScheme.primary
                        : colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  widget.text,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: !widget.canOpen
                            ? colorScheme.onSurface.withValues(alpha: 0.45)
                            : colorScheme.onSurface.withValues(alpha: 0.75),
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


