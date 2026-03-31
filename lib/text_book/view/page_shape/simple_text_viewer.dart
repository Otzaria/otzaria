import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/models/commentator_group.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_commentary_selection.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_settings_manager.dart';
import 'package:otzaria/utils/text_manipulation.dart' as utils;
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/books.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart' as ctx;
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/utils/copy_utils.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:otzaria/personal_notes/personal_notes_system.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/settings/services/nikud_display_service.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/widgets/smart_text/smart_text.dart';
import 'package:otzaria/text_book/view/error_report_dialog.dart';
import 'package:otzaria/text_book/view/selection/selection_persistence.dart';
import 'package:otzaria/text_book/view/selection/selected_text_copy.dart';
import 'package:otzaria/text_book/view/selection/selected_text_restore.dart';
import 'package:otzaria/tools/dictionary/dictionary_context_menu_entries.dart';
import 'package:otzaria/tools/dictionary/repository/dictionary_lookup_repository.dart';
import 'package:otzaria/widgets/custom_ui_components.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_debug_logger.dart';

/// תצוגת טקסט פשוטה - משמשת גם לטקסט המרכזי וגם למפרשים
class SimpleTextViewer extends StatefulWidget {
  final List<String> content;
  final double fontSize;
  final String? fontFamily;
  final Function(OpenedTab) openBookCallback;
  final ItemScrollController? scrollController;
  final ItemPositionsListener? positionsListener;
  final bool isMainText; // האם זה הטקסט המרכזי או מפרש
  final String? title; // כותרת (לכותרת עליונה)
  final String? bookTitle; // שם הספר (למפרשים - לפתיחה בטאב נפרד)
  final Set<int>? highlightedIndices; // אינדקסים להדגשה (למפרשים)
  final VoidCallback? onCommentatorChanged; // callback לרענון אחרי החלפת מפרש
  final bool useInternalScroll; // האם להשתמש בגלילה פנימית
  final ValueChanged<int>? onOpenSidebarTab;
  final ValueChanged<String?>?
      onOpenSearch; // callback לפתיחת חיפוש עם הטקסט הנבחר
  final TextBook? reportBook;

  const SimpleTextViewer({
    super.key,
    required this.content,
    required this.fontSize,
    this.fontFamily,
    required this.openBookCallback,
    this.scrollController,
    this.positionsListener,
    this.isMainText = false,
    this.title,
    this.bookTitle,
    this.highlightedIndices,
    this.onCommentatorChanged,
    this.useInternalScroll = true, // ברירת מחדל - עם גלילה פנימית
    this.onOpenSidebarTab,
    this.onOpenSearch,
    this.reportBook,
  });

  @override
  State<SimpleTextViewer> createState() => _SimpleTextViewerState();
}

class _SimpleTextViewerState extends State<SimpleTextViewer> {
  late final String _debugScope;
  int _buildCount = 0;
  late final ItemScrollController _scrollController;
  late final ItemPositionsListener _positionsListener;
  late final FocusNode _focusNode;
  VoidCallback? _positionsDebugListener;
  String? _savedSelectedText;
  int? _savedSelectedIndex;
  int _initialScrollRestoreAttempts = 0;
  int _initialPositionSnapshotCount = 0;
  int _rawPositionsCallbackCount = 0;
  String? _lastRawPositionsSignature;
  final Map<String, Future<bool>> _removeNikudCache = {};
  final DictionaryLookupRepository _dictionaryLookupRepository =
      DictionaryLookupRepository.instance;

  @override
  void initState() {
    super.initState();
    _debugScope = PageShapeDebugLogger.newScope(
      'simple-text-viewer',
      label: widget.title ??
          widget.bookTitle ??
          (widget.isMainText ? 'main-text' : 'commentary'),
    );
    _scrollController = widget.scrollController ?? ItemScrollController();
    _positionsListener =
        widget.positionsListener ?? ItemPositionsListener.create();
    _focusNode = FocusNode();
    PageShapeDebugLogger.log(
      'SimpleTextViewer',
      'initState',
      scope: _debugScope,
      data: {
        'isMainText': widget.isMainText,
        'title': widget.title,
        'bookTitle': widget.bookTitle,
        'contentLength': widget.content.length,
        'useInternalScroll': widget.useInternalScroll,
        'hasExternalScrollController': widget.scrollController != null,
        'hasExternalPositionsListener': widget.positionsListener != null,
      },
      level: 'LIFECYCLE',
    );

    if (widget.useInternalScroll) {
      _positionsDebugListener = () {
        _rawPositionsCallbackCount++;
        final positions = _positionsListener.itemPositions.value.toList()
          ..sort((a, b) => a.index.compareTo(b.index));
        final signature = _positionsSignature(positions);
        PageShapeDebugLogger.log(
          'SimpleTextViewer',
          'itemPositions listener נורה ב־SimpleTextViewer',
          scope: _debugScope,
          data: {
            'rawPositionsCallbackCount': _rawPositionsCallbackCount,
            'sameAsPrevious': signature == _lastRawPositionsSignature,
            ..._positionsSummary(positions),
          },
          level: 'SCROLL',
        );
        _lastRawPositionsSignature = signature;
      };
      _positionsListener.itemPositions.addListener(_positionsDebugListener!);
      PageShapeDebugLogger.log(
        'SimpleTextViewer',
        'נוסף מאזין דיבוג ל־itemPositions',
        scope: _debugScope,
        data: {
          'useInternalScroll': widget.useInternalScroll,
        },
        level: 'LIFECYCLE',
      );
    }
    // גלילה למיקום הנוכחי אחרי בניית הווידג'ט (רק לטקסט המרכזי)
    if (widget.isMainText) {
      _scheduleInitialScrollRestore();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusNode.requestFocus();
        }
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final state = context.read<TextBookBloc>().state;
        if (state is TextBookLoaded) {
          PageShapeDebugLogger.log(
            'SimpleTextViewer',
            'נשלחת טעינת הערות אישיות לטקסט הראשי',
            scope: _debugScope,
            data: {
              'bookTitle': state.book.title,
            },
          );
          context
              .read<PersonalNotesBloc>()
              .add(LoadPersonalNotes(state.book.title));
        }
      });
    }
  }

  @override
  void dispose() {
    if (_positionsDebugListener != null) {
      _positionsListener.itemPositions.removeListener(_positionsDebugListener!);
      PageShapeDebugLogger.log(
        'SimpleTextViewer',
        'הוסר מאזין דיבוג מ־itemPositions',
        scope: _debugScope,
        data: {
          'rawPositionsCallbackCount': _rawPositionsCallbackCount,
        },
        level: 'LIFECYCLE',
      );
    }
    PageShapeDebugLogger.log(
      'SimpleTextViewer',
      'dispose',
      scope: _debugScope,
      data: {
        'buildCount': _buildCount,
        'initialScrollRestoreAttempts': _initialScrollRestoreAttempts,
        'initialPositionSnapshotCount': _initialPositionSnapshotCount,
        'rawPositionsCallbackCount': _rawPositionsCallbackCount,
      },
      level: 'END',
    );
    _focusNode.dispose();
    super.dispose();
  }

  void _scheduleInitialScrollRestore() {
    PageShapeDebugLogger.log(
      'SimpleTextViewer',
      'תוזמן שחזור גלילה ראשוני',
      scope: _debugScope,
      data: {
        'attempt': _initialScrollRestoreAttempts,
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      _logVisiblePositionsSnapshot(
        'snapshot לפני ניסיון שחזור גלילה',
        attempt: _initialScrollRestoreAttempts,
      );

      final restored = _scrollToCurrentPosition();
      if (restored) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _logVisiblePositionsSnapshot(
            'snapshot אחרי בקשת שחזור גלילה',
            attempt: _initialScrollRestoreAttempts,
          );
        });
        return;
      }
      if (_initialScrollRestoreAttempts >= 10) {
        return;
      }

      _initialScrollRestoreAttempts++;
      PageShapeDebugLogger.log(
        'SimpleTextViewer',
        'שחזור גלילה ראשוני לא הצליח עדיין; מתוזמן ניסיון נוסף',
        scope: _debugScope,
        data: {
          'attempt': _initialScrollRestoreAttempts,
        },
        level: 'SCROLL',
      );
      Future.delayed(
        const Duration(milliseconds: 50),
        _scheduleInitialScrollRestore,
      );
    });
  }

  void _logVisiblePositionsSnapshot(
    String reason, {
    required int attempt,
  }) {
    _initialPositionSnapshotCount++;
    final positions = _positionsListener.itemPositions.value.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    PageShapeDebugLogger.log(
      'SimpleTextViewer',
      reason,
      scope: _debugScope,
      data: {
        'attempt': attempt,
        'snapshotCount': _initialPositionSnapshotCount,
        'scrollControllerAttached': _scrollController.isAttached,
        ..._positionsSummary(positions),
      },
      level: 'SCROLL',
    );
  }

  Map<String, Object?> _positionsSummary(Iterable<ItemPosition> positions) {
    final list = positions.toList(growable: false);
    return {
      'itemPositionsCount': list.length,
      'indices': PageShapeDebugLogger.summarizeIndices(
        list.map((position) => position.index),
      ),
      'items': list
          .take(6)
          .map((position) => {
                'index': position.index,
                'leadingEdge': position.itemLeadingEdge,
                'trailingEdge': position.itemTrailingEdge,
              })
          .toList(growable: false),
    };
  }

  String _positionsSignature(Iterable<ItemPosition> positions) {
    return positions
        .map(
          (position) =>
              '${position.index}:${position.itemLeadingEdge.toStringAsFixed(3)}:${position.itemTrailingEdge.toStringAsFixed(3)}',
        )
        .join('|');
  }

  /// גלילה למיקום הנוכחי (visibleIndices או selectedIndex)
  bool _scrollToCurrentPosition() {
    final bloc = context.read<TextBookBloc>();
    final state = bloc.state;
    if (state is! TextBookLoaded || !_scrollController.isAttached) {
      PageShapeDebugLogger.log(
        'SimpleTextViewer',
        'שחזור גלילה נכשל זמנית',
        scope: _debugScope,
        data: {
          'stateType': state.runtimeType,
          'scrollControllerAttached': _scrollController.isAttached,
        },
        level: 'SCROLL',
      );
      return false;
    }

    final targetIndex = state.visibleIndices.isNotEmpty
        ? state.visibleIndices.first
        : state.selectedIndex;

    if (targetIndex == null || targetIndex >= widget.content.length) {
      PageShapeDebugLogger.log(
        'SimpleTextViewer',
        'שחזור גלילה דולג כי targetIndex לא תקין',
        scope: _debugScope,
        data: {
          'targetIndex': targetIndex,
          'contentLength': widget.content.length,
        },
        level: 'SCROLL',
      );
      return false;
    }

    _scrollController.jumpTo(index: targetIndex);
    PageShapeDebugLogger.log(
      'SimpleTextViewer',
      'בוצע jumpTo לשחזור גלילה',
      scope: _debugScope,
      data: {
        'targetIndex': targetIndex,
      },
      level: 'SCROLL',
    );
    return true;
  }

  Future<bool> _resolveSelectionRemoveNikud(
    TextBookLoaded state,
    SettingsState settingsState,
  ) {
    if (widget.isMainText) {
      return Future.value(state.removeNikud);
    }

    final targetTitle = widget.bookTitle;
    if (targetTitle == null) {
      return Future.value(settingsState.defaultRemoveNikud);
    }

    return _removeNikudCache.putIfAbsent(
      '$targetTitle|${settingsState.defaultRemoveNikud}|${settingsState.removeNikudFromTanach}',
      () => resolveRemoveNikudForBook(
        title: targetTitle,
        defaultRemoveNikud: settingsState.defaultRemoveNikud,
        removeNikudFromTanach: settingsState.removeNikudFromTanach,
      ),
    );
  }

  RenderSettings _selectionRenderSettings({
    required TextBookLoaded state,
    required SettingsState settingsState,
    required bool removeNikud,
  }) {
    return RenderSettings(
      removeNikud: removeNikud,
      removePunctuation: state.removePunctuation,
      removeTeamim: !settingsState.showTeamim,
      replaceHolyNames: settingsState.replaceHolyNames,
      searchText: widget.isMainText ? state.searchText : '',
      fontSize: widget.fontSize,
      fontFamily: widget.fontFamily ?? settingsState.fontFamily,
      lineHeight: settingsState.lineHeight,
    );
  }

  List<int> _selectionSourceIndices() {
    final visibleIndices = _positionsListener.itemPositions.value
        .map((position) => position.index)
        .toSet()
        .toList()
      ..sort();

    if (visibleIndices.isNotEmpty) {
      return visibleIndices;
    }

    return List<int>.generate(widget.content.length, (index) => index);
  }

  Future<void> _handleSelectionChange(String? plainText) async {
    final persistedText = resolvePersistedSelectedText(
      previousSelectedText: _savedSelectedText,
      latestSelectedText: plainText,
    );

    if (!shouldPersistSelectedText(plainText)) {
      return;
    }

    final textBookState = context.read<TextBookBloc>().state;
    if (textBookState is! TextBookLoaded) {
      if (!mounted) return;
      setState(() {
        _savedSelectedText = persistedText;
      });
      return;
    }

    final settingsState = context.read<SettingsBloc>().state;
    final removeNikud =
        await _resolveSelectionRemoveNikud(textBookState, settingsState);
    final sourceIndices = _selectionSourceIndices();
    final renderSettings = _selectionRenderSettings(
      state: textBookState,
      settingsState: settingsState,
      removeNikud: removeNikud,
    );
    final renderedLines = sourceIndices
        .where((index) => index >= 0 && index < widget.content.length)
        .map(
          (index) => renderSelectionLine(
            rawText: widget.content[index],
            settings: renderSettings,
          ),
        )
        .toList();

    final restoredText = restoreSelectedTextLineBreaks(
      selectedText: persistedText!,
      visibleLines: renderedLines,
    );

    int? selectedIndex = _savedSelectedIndex;
    final visibleText = renderedLines.join('\n');
    final selectionStart = visibleText.indexOf(restoredText);
    if (selectionStart >= 0 && sourceIndices.isNotEmpty) {
      final before = visibleText.substring(0, selectionStart);
      selectedIndex = sourceIndices.first + '\n'.allMatches(before).length;
    }

    if (!mounted) return;
    setState(() {
      _savedSelectedText = restoredText;
      _savedSelectedIndex = selectedIndex;
    });
    _prefetchDictionaryLookups(restoredText);
  }

  void _prefetchDictionaryLookups(String? selectedText) {
    final trimmed = selectedText?.trim() ?? '';
    if (trimmed.isEmpty) {
      return;
    }

    unawaited(_dictionaryLookupRepository.ensureAramaicLoaded().catchError((_) {
      return;
    }));

    if (_dictionaryLookupRepository.isLikelyAcronym(trimmed)) {
      unawaited(
        _dictionaryLookupRepository.ensureAcronymsLoaded().catchError((_) {
          return;
        }),
      );
    }
  }

  /// טיפול באירועי מקלדת - חיצים לניווט
  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (!widget.isMainText) return false; // רק בטקסט המרכזי

    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded) return false;
    PageShapeDebugLogger.log(
      'SimpleTextViewer',
      'התקבל אירוע מקלדת',
      scope: _debugScope,
      data: {
        'logicalKey': event.logicalKey.keyLabel,
        'selectedIndex': state.selectedIndex,
      },
      level: 'KEY',
    );

    // חיצים למעלה ולמטה
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      final currentIndex = state.selectedIndex ?? 0;
      final nextIndex = (currentIndex + 1).clamp(0, widget.content.length - 1);
      if (nextIndex != currentIndex) {
        context.read<TextBookBloc>().add(UpdateSelectedIndex(nextIndex));
        if (_scrollController.isAttached) {
          PageShapeDebugLogger.log(
            'SimpleTextViewer',
            'גלילה מהמקלדת - ArrowDown',
            scope: _debugScope,
            data: {
              'currentIndex': currentIndex,
              'nextIndex': nextIndex,
            },
            level: 'SCROLL',
          );
          _scrollController.scrollTo(
            index: nextIndex,
            duration: const Duration(milliseconds: 200),
            alignment: 0.5,
          );
        }
      }
      return true;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      final currentIndex = state.selectedIndex ?? 0;
      final prevIndex = (currentIndex - 1).clamp(0, widget.content.length - 1);
      if (prevIndex != currentIndex) {
        context.read<TextBookBloc>().add(UpdateSelectedIndex(prevIndex));
        if (_scrollController.isAttached) {
          PageShapeDebugLogger.log(
            'SimpleTextViewer',
            'גלילה מהמקלדת - ArrowUp',
            scope: _debugScope,
            data: {
              'currentIndex': currentIndex,
              'prevIndex': prevIndex,
            },
            level: 'SCROLL',
          );
          _scrollController.scrollTo(
            index: prevIndex,
            duration: const Duration(milliseconds: 200),
            alignment: 0.5,
          );
        }
      }
      return true;
    }

    // Page Down
    if (event.logicalKey == LogicalKeyboardKey.pageDown) {
      final currentIndex = state.selectedIndex ?? 0;
      final nextIndex = (currentIndex + 10).clamp(0, widget.content.length - 1);
      context.read<TextBookBloc>().add(UpdateSelectedIndex(nextIndex));
      if (_scrollController.isAttached) {
        PageShapeDebugLogger.log(
          'SimpleTextViewer',
          'גלילה מהמקלדת - PageDown',
          scope: _debugScope,
          data: {
            'currentIndex': currentIndex,
            'nextIndex': nextIndex,
          },
          level: 'SCROLL',
        );
        _scrollController.scrollTo(
          index: nextIndex,
          duration: const Duration(milliseconds: 300),
          alignment: 0.5,
        );
      }
      return true;
    }

    // Page Up
    if (event.logicalKey == LogicalKeyboardKey.pageUp) {
      final currentIndex = state.selectedIndex ?? 0;
      final prevIndex = (currentIndex - 10).clamp(0, widget.content.length - 1);
      context.read<TextBookBloc>().add(UpdateSelectedIndex(prevIndex));
      if (_scrollController.isAttached) {
        PageShapeDebugLogger.log(
          'SimpleTextViewer',
          'גלילה מהמקלדת - PageUp',
          scope: _debugScope,
          data: {
            'currentIndex': currentIndex,
            'prevIndex': prevIndex,
          },
          level: 'SCROLL',
        );
        _scrollController.scrollTo(
          index: prevIndex,
          duration: const Duration(milliseconds: 300),
          alignment: 0.5,
        );
      }
      return true;
    }

    // Home - תחילת הספר
    if (event.logicalKey == LogicalKeyboardKey.home &&
        HardwareKeyboard.instance.isControlPressed) {
      context.read<TextBookBloc>().add(const UpdateSelectedIndex(0));
      if (_scrollController.isAttached) {
        PageShapeDebugLogger.log(
          'SimpleTextViewer',
          'גלילה מהמקלדת - Ctrl+Home',
          scope: _debugScope,
          level: 'SCROLL',
        );
        _scrollController.scrollTo(
          index: 0,
          duration: const Duration(milliseconds: 300),
        );
      }
      return true;
    }

    // End - סוף הספר
    if (event.logicalKey == LogicalKeyboardKey.end &&
        HardwareKeyboard.instance.isControlPressed) {
      final lastIndex = widget.content.length - 1;
      context.read<TextBookBloc>().add(UpdateSelectedIndex(lastIndex));
      if (_scrollController.isAttached) {
        PageShapeDebugLogger.log(
          'SimpleTextViewer',
          'גלילה מהמקלדת - Ctrl+End',
          scope: _debugScope,
          data: {
            'lastIndex': lastIndex,
          },
          level: 'SCROLL',
        );
        _scrollController.scrollTo(
          index: lastIndex,
          duration: const Duration(milliseconds: 300),
        );
      }
      return true;
    }

    return false;
  }

  /// תפריט הקשר - מעתיק מהתצוגה הרגילה
  ctx.ContextMenu<Object> _buildContextMenu(
      TextBookLoaded state, int index, BuildContext menuContext) {
    // בניית רשימת מפרשים אם זה מפרש (לא טקסט ראשי)
    List<ctx.MenuItem<Object>> commentatorMenuItems = [];
    if (!widget.isMainText && widget.bookTitle != null) {
      commentatorMenuItems = _buildCommentatorSwitchMenu(state);
    }

    final linksMenuItems = state.links
        .where(
          (link) =>
              link.index1 == index + 1 &&
              !LinkTypes.isCommentaryOrTargum(link.connectionType) &&
              link.start == null &&
              link.end == null,
        )
        .map(
          (link) => ctx.MenuItem<Object>(
            label: FutureBuilder<String>(
              future: link.displayReference,
              builder: (context, snapshot) {
                return Text(
                  snapshot.data ?? link.fallbackDisplayReference,
                  textDirection: TextDirection.rtl,
                );
              },
            ),
            onSelected: (_) {
              widget.openBookCallback(
                TextBookTab(
                  book: TextBook(
                    title: utils.getTitleFromPath(link.path2),
                  ),
                  index: link.index2 - 1,
                  openLeftPane: (Settings.getValue<bool>('key-pin-sidebar') ??
                          false) ||
                      (Settings.getValue<bool>('key-default-sidebar-open') ??
                          false),
                ),
              );
            },
          ),
        )
        .toList();

    final entries = <ctx.ContextMenuEntry<Object>>[];

    if (widget.isMainText) {
      entries.add(
        ctx.MenuItem<Object>(
          label: const Text('חיפוש'),
          icon: const Icon(FluentIcons.search_24_regular),
          onSelected: (_) {
            if (widget.onOpenSearch != null) {
              widget.onOpenSearch!(_savedSelectedText);
            } else {
              UiSnack.show('חיפוש לא זמין בתצוגה זו');
            }
          },
        ),
      );
    }

    // הוספת תפריט החלפת מפרש אם זה מפרש
    if (commentatorMenuItems.isNotEmpty) {
      if (entries.isNotEmpty) {
        entries.add(const ctx.MenuDivider());
      }
      entries.addAll(commentatorMenuItems);
    }

    if (linksMenuItems.isNotEmpty) {
      entries.add(const ctx.MenuDivider());
      entries.add(
        ctx.MenuItem<Object>.submenu(
          label: const Text('קישורים'),
          icon: const Icon(FluentIcons.link_24_regular),
          items: linksMenuItems,
        ),
      );
    }

    final dictionaryEntries = buildDictionaryContextMenuEntries(
      context: context,
      selectedText: _savedSelectedText,
      repository: _dictionaryLookupRepository,
    );
    if (dictionaryEntries.isNotEmpty) {
      entries.add(const ctx.MenuDivider());
      entries.addAll(dictionaryEntries);
    }

    entries.add(const ctx.MenuDivider());
    entries.addAll([
      // הערות אישיות
      ctx.MenuItem<Object>(
        label: const Text('הוסף הערה אישית '),
        icon: const Icon(FluentIcons.note_add_24_regular),
        onSelected: (_) => _createNoteForCurrentLine(index),
      ),
      // דיווח על טעות בספר
      ctx.MenuItem<Object>(
        label: const Text('דווח על טעות בספר'),
        icon: const Icon(FluentIcons.error_circle_24_regular),
        onSelected: (_) => _openErrorReportDialog(_savedSelectedText ?? ''),
      ),
      const ctx.MenuDivider(),
      // העתקה
      ctx.MenuItem<Object>(
        label: const Text('העתק'),
        icon: const Icon(FluentIcons.copy_24_regular),
        enabled:
            _savedSelectedText != null && _savedSelectedText!.trim().isNotEmpty,
        onSelected: (_) => _copyFormattedText(),
      ),
      ctx.MenuItem<Object>(
        label: const Text('העתק את כל הפסקה'),
        icon: const Icon(FluentIcons.document_copy_24_regular),
        enabled: index >= 0 && index < widget.content.length,
        onSelected: (_) => _copyParagraphByIndex(index),
      ),
      // [EDITING DISABLED]
      // const ctx.MenuDivider(),
      // // עריכת פסקה
      // ctx.MenuItem(
      //   label: const Text('ערוך פסקה זו'),
      //   icon: const Icon(FluentIcons.edit_24_regular),
      //   onSelected: (_) => _editParagraph(index),
      // ),
    ]);

    return ctx.ContextMenu<Object>(
        entries: _normalizeContextMenuEntries(entries));
  }

  List<ctx.ContextMenuEntry<Object>> _normalizeContextMenuEntries(
    List<ctx.ContextMenuEntry<Object>> entries,
  ) {
    final normalized = <ctx.ContextMenuEntry<Object>>[];

    for (final entry in entries) {
      final isDivider = entry is ctx.MenuDivider;
      final previousIsDivider =
          normalized.isNotEmpty && normalized.last is ctx.MenuDivider;

      if (isDivider && (normalized.isEmpty || previousIsDivider)) {
        continue;
      }

      normalized.add(entry);
    }

    while (normalized.isNotEmpty && normalized.last is ctx.MenuDivider) {
      normalized.removeLast();
    }

    return normalized;
  }

  /// יצירת הערה לשורה הנוכחית
  Future<void> _createNoteForCurrentLine(int index) async {
    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded) return;

    final selectedText = _savedSelectedText;
    final referenceText = selectedText?.trim().isNotEmpty == true
        ? utils.removeVolwels(selectedText!.trim())
        : widget.content[index];

    // טען טיוטה אם קיימת
    final draftService = PersonalNoteDraftService();
    final draft = await draftService.loadDraft(
      bookId: state.book.title,
      lineNumber: index + 1,
    );

    if (!mounted) return;

    // שלח event לפתיחת מצב יצירה בסיידבר
    context.read<PersonalNotesBloc>().add(StartCreatingPersonalNote(
          bookId: state.book.title,
          lineNumber: index + 1,
          referenceText: referenceText,
          selectedText: selectedText?.trim(),
          initialContent: draft?.content ?? '',
          initialFormat:
              draft?.contentFormat ?? PersonalNoteContentFormat.plain,
        ));
  }

  /// פתיחת דיאלוג דיווח על טעות בספר
  void _openErrorReportDialog(String selectedText) {
    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded) return;

    final resolvedBookTitle =
        (widget.bookTitle != null && widget.bookTitle!.trim().isNotEmpty)
            ? widget.bookTitle!
            : state.book.title;

    ErrorReportHelper.showErrorReportDialog(
      context: context,
      selectedText: selectedText,
      state: state,
      fontSize: widget.fontSize,
      bookTitle: resolvedBookTitle,
      savedSelectedIndex: _savedSelectedIndex,
      reportContent: widget.content,
      reportBook: widget.reportBook,
    );
  }

  // [EDITING DISABLED]
  // /// עריכת פסקה
  // void _editParagraph(int index) {
  //   if (index >= 0 && index < widget.content.length) {
  //     context.read<TextBookBloc>().add(OpenEditor(index: index));
  //   }
  // }

  /// העתקת פסקה לפי אינדקס
  Future<void> _copyParagraphByIndex(int index) async {
    if (index < 0 || index >= widget.content.length) return;

    final text = widget.content[index];
    if (text.trim().isEmpty) return;

    final settingsState = context.read<SettingsBloc>().state;
    final textBookState = context.read<TextBookBloc>().state;

    String finalText = text;
    String finalHtmlText = text;

    if (settingsState.copyWithHeaders != 'none' &&
        textBookState is TextBookLoaded) {
      final bookName = CopyUtils.extractBookName(textBookState.book);
      final currentPath = await CopyUtils.extractCurrentPath(
        textBookState.book,
        index,
        bookContent: textBookState.content,
      );

      finalText = CopyUtils.formatTextWithHeaders(
        originalText: text,
        copyWithHeaders: settingsState.copyWithHeaders,
        copyHeaderFormat: settingsState.copyHeaderFormat,
        bookName: bookName,
        currentPath: currentPath,
      );

      finalHtmlText = CopyUtils.formatTextWithHeaders(
        originalText: text,
        copyWithHeaders: settingsState.copyWithHeaders,
        copyHeaderFormat: settingsState.copyHeaderFormat,
        bookName: bookName,
        currentPath: currentPath,
      );
    }

    final item = DataWriterItem();
    item.add(Formats.plainText(finalText));
    item.add(Formats.htmlText(_formatTextAsHtml(finalHtmlText)));

    await SystemClipboard.instance?.write([item]);
  }

  /// עיצוב טקסט כ-HTML עם הגדרות הגופן הנוכחיות
  String _formatTextAsHtml(String text) {
    final settingsState = context.read<SettingsBloc>().state;
    return CopyUtils.buildStyledHtml(
      htmlText: text,
      fontFamily: widget.fontFamily ?? settingsState.fontFamily,
      fontSize: widget.fontSize,
    );
  }

  /// העתקת טקסט מעוצב
  Future<void> _copyFormattedText() async {
    final plainText = _savedSelectedText;

    if (plainText == null || plainText.trim().isEmpty) {
      UiSnack.show('אנא בחר טקסט להעתקה');
      return;
    }

    try {
      final settingsState = context.read<SettingsBloc>().state;
      final textBookState = context.read<TextBookBloc>().state;
      if (textBookState is! TextBookLoaded) return;

      await copySelectedTextForBook(
        plainText: plainText,
        selectedIndex: _savedSelectedIndex,
        sourceContent: widget.content,
        textBookState: textBookState,
        settingsState: settingsState,
        fontFamily: widget.fontFamily ?? settingsState.fontFamily,
        fontSize: widget.fontSize,
      );
    } catch (e) {
      if (mounted) {
        UiSnack.showError('שגיאה בהעתקה מעוצבת: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    _buildCount++;
    PageShapeDebugLogger.log(
      'SimpleTextViewer',
      'build',
      scope: _debugScope,
      data: {
        'buildCount': _buildCount,
        'isMainText': widget.isMainText,
        'contentLength': widget.content.length,
        'useInternalScroll': widget.useInternalScroll,
      },
      level: 'BUILD',
    );
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: widget.isMainText,
      onKeyEvent: (event) {
        if (_handleKeyEvent(event)) {
          // האירוע טופל
        }
      },
      child: Column(
        children: [
          // כותרת אופציונלית
          if (widget.title != null)
            Container(
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface.withAlpha(128),
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(context).dividerColor,
                    width: 0.5,
                  ),
                ),
              ),
              child: Center(
                child: Text(
                  widget.title!,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          // תוכן
          Expanded(
            child: BlocBuilder<TextBookBloc, TextBookState>(
              builder: (context, state) {
                if (state is! TextBookLoaded) {
                  return const Center(child: CircularProgressIndicator());
                }

                return BlocBuilder<PersonalNotesBloc, PersonalNotesState>(
                  builder: (context, notesState) {
                    final noteMap = <int, List<PersonalNote>>{};
                    if (notesState.bookId == state.book.title) {
                      for (final note in notesState.locatedNotes) {
                        final line = note.lineNumber;
                        if (line == null) continue;
                        noteMap.putIfAbsent(line, () => []).add(note);
                      }
                    }

                    return SelectionArea(
                      // ביטול תפריט ברירת המחדל של Flutter - נשתמש רק ב-ContextMenuRegion
                      contextMenuBuilder: (context, selectableRegionState) =>
                          const SizedBox.shrink(),
                      onSelectionChanged: (selection) {
                        _handleSelectionChange(selection?.plainText);
                      },
                      child: widget.useInternalScroll
                          ? ScrollablePositionedList.builder(
                              itemScrollController: _scrollController,
                              itemPositionsListener: _positionsListener,
                              itemCount: widget.content.length,
                              padding: const EdgeInsets.all(4),
                              itemBuilder: (context, index) =>
                                  _buildLine(index, state, context, noteMap),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: widget.content.length,
                              padding: const EdgeInsets.all(4),
                              itemBuilder: (context, index) =>
                                  _buildLine(index, state, context, noteMap),
                            ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLine(
    int index,
    TextBookLoaded state,
    BuildContext context,
    Map<int, List<PersonalNote>> noteMap,
  ) {
    final isSelected = widget.isMainText && state.selectedIndex == index;
    final isHighlighted = widget.isMainText && state.highlightedLine == index;

    // בדיקה חדשה - האם השורה מודגשת כפרשן קשור (מקומי)
    final isCommentaryHighlighted = !widget.isMainText &&
        (widget.highlightedIndices?.contains(index) ?? false);

    final theme = Theme.of(context);
    final backgroundColor = () {
      if (isHighlighted) {
        return theme.colorScheme.secondaryContainer
            .withAlpha((0.4 * 255).round());
      }
      if (isCommentaryHighlighted || isSelected) {
        // צבע הדגשה למפרש קשור - כמו השורה הנבחרת
        return theme.colorScheme.primary.withAlpha((0.08 * 255).round());
      }
      return null;
    }();

    final notesForLine = noteMap[index + 1] ?? const <PersonalNote>[];

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: widget.isMainText
          ? () {
              PageShapeDebugLogger.log(
                'SimpleTextViewer',
                'onTap על שורה בטקסט הראשי',
                scope: _debugScope,
                data: {
                  'index': index,
                  'isSelectedBefore': isSelected,
                },
              );
              // איפוס הטקסט השמור
              setState(() {
                _savedSelectedText = null;
                _savedSelectedIndex = null;
              });
              // עדכון selectedIndex רק בטקסט המרכזי
              if (isSelected) {
                context
                    .read<TextBookBloc>()
                    .add(const UpdateSelectedIndex(null));
              } else {
                context.read<TextBookBloc>().add(UpdateSelectedIndex(index));
              }
            }
          : null,
      onDoubleTap: !widget.isMainText && widget.bookTitle != null
          ? () {
              PageShapeDebugLogger.log(
                'SimpleTextViewer',
                'onDoubleTap על שורת מפרש - פתיחה בטאב נפרד',
                scope: _debugScope,
                data: {
                  'bookTitle': widget.bookTitle,
                  'index': index,
                },
              );
              // לחיצה כפולה במפרש - פתיחה בטאב נפרד
              widget.openBookCallback(TextBookTab(
                book: TextBook(title: widget.bookTitle!),
                index: index,
                openLeftPane:
                    (Settings.getValue<bool>('key-pin-sidebar') ?? false) ||
                        (Settings.getValue<bool>('key-default-sidebar-open') ??
                            false),
              ));
            }
          : null,
      onSecondaryTapDown: (details) {
        // שמירת האינדקס לשימוש בתפריט ההקשר
        PageShapeDebugLogger.log(
          'SimpleTextViewer',
          'onSecondaryTapDown',
          scope: _debugScope,
          data: {
            'index': index,
            'globalPositionDx': details.globalPosition.dx,
            'globalPositionDy': details.globalPosition.dy,
          },
        );
        setState(() {
          _savedSelectedIndex = index;
        });
      },
      child: ctx.ContextMenuRegion(
        contextMenu: _buildContextMenu(state, index, context),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          decoration: backgroundColor != null
              ? BoxDecoration(color: backgroundColor)
              : null,
          padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
          child: BlocBuilder<SettingsBloc, SettingsState>(
            builder: (context, settingsState) {
              final data = widget.content[index];
              final targetTitle =
                  widget.isMainText ? state.book.title : widget.bookTitle;
              // אם המשתמש לחץ על כפתור ניקוד (override), נשתמש בערך מה-state
              final bool? overrideRemoveNikud =
                  widget.isMainText ? state.removeNikud : null;
              final removeNikudFuture = (overrideRemoveNikud != null)
                  ? Future.value(overrideRemoveNikud)
                  : (targetTitle == null
                      ? Future.value(settingsState.defaultRemoveNikud)
                      : _removeNikudCache.putIfAbsent(
                          '$targetTitle|${settingsState.defaultRemoveNikud}|${settingsState.removeNikudFromTanach}',
                          () => resolveRemoveNikudForBook(
                            title: targetTitle,
                            defaultRemoveNikud:
                                settingsState.defaultRemoveNikud,
                            removeNikudFromTanach:
                                settingsState.removeNikudFromTanach,
                            categoryId: widget.isMainText
                                ? state.book.categoryId
                                : null,
                            fileType:
                                widget.isMainText ? state.book.fileType : null,
                          ),
                        ));

              // הדגשת טקסט חיפוש רק בטקסט המרכזי
              final searchText = widget.isMainText ? state.searchText : '';

              final textWidget = FutureBuilder<bool>(
                future: removeNikudFuture,
                initialData: state.removeNikud,
                builder: (context, snapshot) {
                  return SmartTextWidget(
                    text: data,
                    widgetKey: ValueKey('html_simple_text_$index'),
                    settings: RenderSettings(
                      removeNikud: snapshot.data ?? state.removeNikud,
                      removePunctuation: state.removePunctuation,
                      removeTeamim: !settingsState.showTeamim,
                      replaceHolyNames: settingsState.replaceHolyNames,
                      searchText: searchText,
                      fontSize: widget.fontSize,
                      fontFamily: widget.fontFamily ?? settingsState.fontFamily,
                      lineHeight: settingsState.lineHeight,
                    ),
                    onOpenBook: widget.openBookCallback,
                  );
                },
              );

              if (!widget.isMainText || notesForLine.isEmpty) {
                return textWidget;
              }

              final note = notesForLine.first;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Tooltip(
                    message: note.contentPlain,
                    child: GestureDetector(
                      onTap: () {
                        context
                            .read<TextBookBloc>()
                            .add(UpdateSelectedIndex(index));
                        context.read<TextBookBloc>().add(HighlightLine(index));
                        if (widget.onOpenSidebarTab != null) {
                          widget.onOpenSidebarTab!(1);
                        } else {
                          context
                              .read<TextBookBloc>()
                              .add(const ToggleLeftPane(true));
                        }
                      },
                      onLongPress: () {
                        showDialog(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('הערה לשורה זו'),
                            content: PersonalNoteContentView(note: note),
                            actions: [
                              FilledButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('סגור'),
                              ),
                            ],
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(left: 6, right: 2),
                        child: Icon(
                          FluentIcons.note_24_filled,
                          size: 12,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                  Expanded(child: textWidget),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// בניית תפריט החלפת מפרש
  List<ctx.MenuItem<Object>> _buildCommentatorSwitchMenu(TextBookLoaded state) {
    // קבלת רשימת המפרשים הזמינים
    final availableCommentators = state.availableCommentators;

    if (availableCommentators.isEmpty) {
      return [];
    }

    // קיבוץ המפרשים לפי קבוצות
    final groups = state.commentatorGroups;
    final tanachGroup = CommentatorGroup.groupByTitle(groups, 'תורה שבכתב');
    final chazalGroup = CommentatorGroup.groupByTitle(groups, 'תורה שבעל פה');
    final rishonimGroup = CommentatorGroup.groupByTitle(groups, 'ראשונים');
    final acharonimGroup = CommentatorGroup.groupByTitle(groups, 'אחרונים');
    final modernGroup = CommentatorGroup.groupByTitle(groups, 'מודרני');

    final allGrouped = [
      ...tanachGroup.commentators,
      ...chazalGroup.commentators,
      ...rishonimGroup.commentators,
      ...acharonimGroup.commentators,
      ...modernGroup.commentators,
    ];
    final ungrouped =
        availableCommentators.where((c) => !allGrouped.contains(c)).toList();

    // בניית תפריט משנה
    final submenuItems = <ctx.ContextMenuEntry<Object>>[];

    // הוספת קבוצות
    if (tanachGroup.commentators.isNotEmpty) {
      submenuItems
          .addAll(_buildCommentatorGroupItems(tanachGroup.commentators, state));
    }
    if (chazalGroup.commentators.isNotEmpty) {
      if (submenuItems.isNotEmpty) submenuItems.add(const ctx.MenuDivider());
      submenuItems
          .addAll(_buildCommentatorGroupItems(chazalGroup.commentators, state));
    }
    if (rishonimGroup.commentators.isNotEmpty) {
      if (submenuItems.isNotEmpty) submenuItems.add(const ctx.MenuDivider());
      submenuItems.addAll(
          _buildCommentatorGroupItems(rishonimGroup.commentators, state));
    }
    if (acharonimGroup.commentators.isNotEmpty) {
      if (submenuItems.isNotEmpty) submenuItems.add(const ctx.MenuDivider());
      submenuItems.addAll(
          _buildCommentatorGroupItems(acharonimGroup.commentators, state));
    }
    if (modernGroup.commentators.isNotEmpty) {
      if (submenuItems.isNotEmpty) submenuItems.add(const ctx.MenuDivider());
      submenuItems
          .addAll(_buildCommentatorGroupItems(modernGroup.commentators, state));
    }
    if (ungrouped.isNotEmpty) {
      if (submenuItems.isNotEmpty) submenuItems.add(const ctx.MenuDivider());
      submenuItems.addAll(_buildCommentatorGroupItems(ungrouped, state));
    }

    final normalizedSubmenuItems = _normalizeContextMenuEntries(submenuItems);
    if (normalizedSubmenuItems.isEmpty) {
      return [];
    }

    return [
      ctx.MenuItem<Object>.submenu(
        label: const Text('החלף מפרש'),
        icon: const Icon(FluentIcons.arrow_swap_24_regular),
        items: normalizedSubmenuItems,
      ),
    ];
  }

  /// בניית פריטי תפריט לקבוצת מפרשים
  List<ctx.ContextMenuEntry<Object>> _buildCommentatorGroupItems(
      List<String> commentators, TextBookLoaded state) {
    return commentators.map<ctx.ContextMenuEntry<Object>>((commentator) {
      final isSelected = commentator == widget.bookTitle;
      return ctx.MenuItem<Object>(
        label: Text(commentator),
        icon: isSelected ? const Icon(FluentIcons.checkmark_24_regular) : null,
        onSelected: (_) => _switchCommentator(commentator, state),
      );
    }).toList();
  }

  /// החלפת מפרש
  void _switchCommentator(String newCommentator, TextBookLoaded state) {
    if (newCommentator == widget.bookTitle) {
      return; // כבר מוצג מפרש זה
    }

    // צריך למצוא באיזה טור המפרש הנוכחי מוצג ולהחליף אותו
    final config = PageShapeSettingsManager.loadConfiguration(
      state.book.title,
      heCategories: state.book.heCategories,
    );

    if (config == null) return;

    // מציאת הטור שבו המפרש הנוכחי מוצג
    String? columnToUpdate;
    String? matchedSelection;
    for (final entry in config.entries) {
      if (entry.value == null) continue;

      // בדיקה אם המפרש הנוכחי תואם לערך בהגדרה
      final configValue = entry.value!;
      final currentTitle = widget.bookTitle!;

      if (isPageShapeMultiCommentatorsValue(configValue)) {
        for (final selection
            in decodePageShapeCommentatorsSelection(configValue)) {
          if (currentTitle == selection ||
              currentTitle.startsWith(selection) ||
              currentTitle.contains(selection) ||
              selection.startsWith(currentTitle) ||
              selection.contains(currentTitle)) {
            columnToUpdate = entry.key;
            matchedSelection = selection;
            break;
          }
        }
        if (columnToUpdate != null) {
          break;
        }
      }

      if (configValue == currentTitle ||
          currentTitle.startsWith(configValue) ||
          currentTitle.contains(configValue) ||
          configValue.startsWith(currentTitle) ||
          configValue.contains(currentTitle)) {
        columnToUpdate = entry.key;
        break;
      }
    }

    if (columnToUpdate == null) {
      debugPrint(
          '⚠️ PageShape: Could not find column for commentator "${widget.bookTitle}"');
      return;
    }

    // עדכון ההגדרה
    final updatedConfig = Map<String, String?>.from(config);
    if (matchedSelection != null) {
      final updatedSelection =
          decodePageShapeCommentatorsSelection(updatedConfig[columnToUpdate])
              .map((selection) =>
                  selection == matchedSelection ? newCommentator : selection)
              .toList();
      updatedConfig[columnToUpdate] =
          encodePageShapeCommentatorsSelection(updatedSelection);
    } else {
      updatedConfig[columnToUpdate] = newCommentator;
    }

    // בדיקה אם יש הגדרה ספציפית לספר (לא רק הדגל, אלא הגדרה ממשית)
    final hasActualBookConfig =
        PageShapeSettingsManager.loadConfiguration(state.book.title) != null;

    // אם יש הגדרה ספציפית לספר - שומרים לספר
    // אחרת - שומרים לקטגוריה (אם יש)
    final categoryToSave = !hasActualBookConfig &&
            state.book.heCategories != null &&
            state.book.heCategories!.isNotEmpty
        ? PageShapeSettingsManager.getActiveCategory(state.book.heCategories) ??
            PageShapeSettingsManager.getParentCategory(state.book.heCategories)
        : null;

    PageShapeSettingsManager.saveConfiguration(
      state.book.title,
      updatedConfig,
      saveToCategory: categoryToSave,
    );

    // קריאה ל-callback לרענון המסך
    widget.onCommentatorChanged?.call();
  }
}
