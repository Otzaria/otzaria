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
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';

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
  bool _previewExpanded = false;

  final _searchController = TextEditingController();
  final _totalResultsNotifier = ValueNotifier<int>(0);
  final _currentIdxNotifier = ValueNotifier<int>(0);
  final _openFilterNotifier = ValueNotifier<int>(0);

  final _commentaryKey = GlobalKey<CommentaryListBaseState>();

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
      _previewExpanded = false;
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

    // אוסף שורות תוכן עבור האינדקסים הנבחרים
    final previewLines = effectiveIndexes == null
        ? const <String>[]
        : effectiveIndexes
            .where((i) => i >= 0 && i < state.content.length)
            .map((i) => state.content[i].trim())
            .where((l) => l.isNotEmpty)
            .toList();

    final hasPreview = previewLines.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      padding: const EdgeInsetsDirectional.only(start: 8, end: 8, top: 6, bottom: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // שורה 1: שם ספר
          Row(
            children: [
              const Icon(FluentIcons.book_24_regular, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'מפרשים | ${state.book.title}',
                  style: Theme.of(context).textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // שורה 2: כל הפקדים באותה שורה עם Flexible
          Row(
            children: [
              // Dropdown פרק
              if (chapters.isNotEmpty)
                Flexible(
                  flex: 3,
                  child: _CompactDropdown<int>(
                    items: List.generate(chapters.length, (i) => i),
                    labelOf: (i) => chapters[i].text,
                    selected: _selectedChapter == null
                        ? null
                        : () {
                            final i = chapters.indexOf(_selectedChapter!);
                            return i >= 0 ? i : null;
                          }(),
                    hint: chapterLabel,
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
              // Dropdown פסוק
              if (hasVerses) ...[
                const SizedBox(width: 4),
                Flexible(
                  flex: 3,
                  child: _CompactDropdown<int>(
                    items: [
                      _kAllChapter,
                      ...List.generate(_selectedChapter!.children.length, (i) => i)
                    ],
                    labelOf: (i) => i == _kAllChapter
                        ? 'כל ה$chapterLabel'
                        : _selectedChapter!.children[i].text,
                    selected: _selectedVerseIdx,
                    hint: verseLabel,
                    onChanged: (i) {
                      if (i != null) {
                        setState(() {
                          _selectedVerseIdx = i;
                          _previewExpanded = false;
                        });
                        if (i == _kAllChapter) {
                          _onChapterSelected(_selectedChapter!, chapters);
                        } else if (i < _selectedChapter!.children.length) {
                          final verse = _selectedChapter!.children[i];
                          final int endIdx;
                          if (i + 1 < _selectedChapter!.children.length) {
                            endIdx = _selectedChapter!.children[i + 1].index - 1;
                          } else {
                            endIdx = verse.index + 50;
                          }
                          final count = (endIdx - verse.index + 1).clamp(1, 200);
                          _triggerLinkLoad(
                              List.generate(count, (j) => verse.index + j));
                        }
                      }
                    },
                  ),
                ),
              ],
              // Dropdown שורה/פסקה (לספרים ללא מבנה פסוק ב-TOC)
              if (!hasVerses && _selectedChapter != null) ...() {
                final lineCount =
                    _chapterLineCount(chapters, _selectedChapter!);
                if (lineCount <= 1) return const <Widget>[];
                return [
                  const SizedBox(width: 4),
                  Flexible(
                    flex: 3,
                    child: _CompactDropdown<int>(
                      items: [
                        _kAllChapter,
                        ...List.generate(lineCount, (i) => i),
                      ],
                      labelOf: (i) =>
                          i == _kAllChapter ? 'כל ה$chapterLabel' : 'פסקה ${i + 1}',
                      selected: _selectedVerseIdx,
                      hint: 'פסקה',
                      onChanged: (i) {
                        if (i != null) {
                          setState(() {
                            _selectedVerseIdx = i;
                            _previewExpanded = false;
                          });
                          if (i == _kAllChapter) {
                            _onChapterSelected(_selectedChapter!, chapters);
                          } else {
                            _triggerLinkLoad([_selectedChapter!.index + i]);
                          }
                        }
                      },
                    ),
                  ),
                ];
              }(),
              const SizedBox(width: 4),
              // כפתור בחירת מפרשים
              CommentatorsFilterButton(
                isActive: false,
                onPressed: () => _openFilterNotifier.value++,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                iconSize: 18,
              ),
              const SizedBox(width: 4),
              // שדה חיפוש — באותה שורה
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
                          decoration: InputDecoration(
                            hintText: 'חיפוש...',
                            prefixIcon: const Icon(
                                FluentIcons.search_24_regular, size: 16),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (total > 1) ...[
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
                                              ? () => _commentaryKey
                                                  .currentState
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
                                              ? () => _commentaryKey
                                                  .currentState
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
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8.0)),
                          ),
                          onChanged: (_) => setState(() {}),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
          // שורה 3: תצוגת הטקסט (expandable, inline)
          if (hasPreview) ...[
            const SizedBox(height: 4),
            LayoutBuilder(builder: (context, constraints) {
              final plainText = previewLines.first
                  .replaceAll(RegExp(r'<[^>]*>'), '')
                  .replaceAll('&nbsp;', ' ')
                  .trim();
              final textStyle =
                  Theme.of(context).textTheme.bodySmall ?? const TextStyle();
              // בדיקה אם הטקסט גולש — אם כן, מציגים חץ הרחבה
              final tp = TextPainter(
                text: TextSpan(text: plainText, style: textStyle),
                maxLines: 1,
                textDirection: TextDirection.rtl,
              )..layout(maxWidth: constraints.maxWidth - 24);
              final overflows = tp.didExceedMaxLines || previewLines.length > 1;

              return GestureDetector(
                onTap: overflows
                    ? () => setState(
                        () => _previewExpanded = !_previewExpanded)
                    : null,
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: colorScheme.outlineVariant),
                  ),
                  clipBehavior: Clip.hardEdge,
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeInOut,
                    child: _previewExpanded
                        ? ConstrainedBox(
                            constraints:
                                const BoxConstraints(maxHeight: 160),
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(8),
                              child: SmartTextWidget(
                                text: previewLines.join('\n'),
                                settings: RenderSettings(
                                  removeNikud: state.removeNikud,
                                  fontSize: state.fontSize * 0.82,
                                  lineHeight: 1.6,
                                ),
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
                                  plainText,
                                  style: textStyle,
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                              // חץ הרחבה — רק אם הטקסט גולש
                              if (overflows)
                                Icon(
                                  FluentIcons.chevron_down_24_regular,
                                  size: 10,
                                  color: colorScheme.onSurface
                                      .withValues(alpha: 0.4),
                                ),
                              if (overflows) const SizedBox(height: 2),
                            ],
                          ),
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  String _tocLabel(List<TocEntry> entries, String fallback) {
    if (entries.isEmpty) return fallback;
    final text = entries.first.text.trim();
    // רק המילה הראשונה — למשל "דף א" → "דף", "פרק ב" → "פרק"
    final match = RegExp(r'^([\u05d0-\u05ea]+)').firstMatch(text);
    final base = match?.group(1)?.trim() ?? '';
    return base.isNotEmpty ? base : fallback;
  }
}

class _CompactDropdown<T> extends StatelessWidget {
  final List<T> items;
  final String Function(T) labelOf;
  final T? selected;
  final String hint;
  final ValueChanged<T?> onChanged;

  const _CompactDropdown({
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
          isExpanded: true,
          value: selected,
          hint: Text(hint,
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis),
          items: items
              .map((item) => DropdownMenuItem<T>(
                    value: item,
                    child: Text(
                      labelOf(item),
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ))
              .toList(),
          onChanged: onChanged,
          style: Theme.of(context).textTheme.bodySmall,
          icon: const Icon(Icons.arrow_drop_down, size: 16),
          isDense: true,
        ),
      ),
    );
  }
}


