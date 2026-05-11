import 'dart:async';
import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/models/commentator_group.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_commentary_selection.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_settings_manager.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/models/books.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/utils/text/copy_utils.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:otzaria/personal_notes/personal_notes_system.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/settings/services/nikud_display_service.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/widgets/smart_text/smart_text.dart';
import 'package:otzaria/text_book/view/error_report_dialog.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria/text_book/view/selection/selection_persistence.dart';
import 'package:otzaria/text_book/view/selection/selected_text_copy.dart';
import 'package:otzaria/text_book/view/selection/selected_text_restore.dart';
import 'package:otzaria/tools/dictionary/dictionary_context_menu_entries.dart';
import 'package:otzaria/tools/dictionary/repository/dictionary_lookup_repository.dart';
import 'package:otzaria/utils/text/word_at_position.dart';
import 'package:otzaria/plugins/services/context_menu_registry.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/utils/fluent_icon_resolver.dart';
import 'package:otzaria/text_book/view/selection/selection_sync_controller.dart';

/// מחזירה האם אירוע המקלדת צריך להניע גלילה רציפה בצורת הדף.
bool shouldHandlePageShapeNavigationKeyEvent(KeyEvent event) {
  return event is KeyDownEvent || event is KeyRepeatEvent;
}

/// בודקת האם הפוקוס הנוכחי נמצא בתוך שדה קלט טקסטואלי.
///
/// נדרש עבור "צורת הדף", כי העורך של הערות אישיות מבוסס `flutter_quill`
/// ואינו מזוהה תמיד כ-`EditableText` רגיל.
bool isTextInputFocusNode(FocusNode? focusNode) {
  final focusContext = focusNode?.context;
  if (focusContext == null) {
    return false;
  }

  if (_isTextInputWidget(focusContext.widget)) {
    return true;
  }

  return focusContext.findAncestorWidgetOfExactType<EditableText>() != null ||
      _hasQuillEditorAncestor(focusContext);
}

/// בודקת האם הפוקוס הנוכחי נמצא בתוך תפריט (כמו תפריט הקשר/תת-תפריט).
///
/// נדרש כדי שלא נחזיר פוקוס לטקסט בזמן שהמשתמש פותח תת-תפריט,
/// כי גזילת הפוקוס תסגור את התת-תפריט מיד.
bool isMenuFocusNode(FocusNode? focusNode) {
  final focusContext = focusNode?.context;
  if (focusContext == null) {
    return false;
  }

  if (_isMenuWidget(focusContext.widget)) {
    return true;
  }

  var hasMenuAncestor = false;
  focusContext.visitAncestorElements((element) {
    if (_isMenuWidget(element.widget)) {
      hasMenuAncestor = true;
      return false;
    }
    return true;
  });
  return hasMenuAncestor;
}

bool _hasQuillEditorAncestor(BuildContext context) {
  var hasQuillAncestor = false;
  context.visitAncestorElements((element) {
    if (_isTextInputWidget(element.widget)) {
      hasQuillAncestor = true;
      return false;
    }
    return true;
  });
  return hasQuillAncestor;
}

bool _isTextInputWidget(Widget widget) {
  if (widget is EditableText) {
    return true;
  }

  final runtimeTypeName = widget.runtimeType.toString();
  return runtimeTypeName.contains('TextField') ||
      runtimeTypeName.contains('EditableText') ||
      runtimeTypeName.contains('QuillRawEditor') ||
      runtimeTypeName.contains('RawEditor') ||
      runtimeTypeName.contains('QuillEditor');
}

bool _isMenuWidget(Widget widget) {
  return widget is MenuItemButton ||
      widget is SubmenuButton ||
      widget is MenuAnchor;
}

/// קובעת מאיזה אינדקס יתחיל ניווט המקלדת בצורת הדף.
int resolvePageShapeNavigationBaseIndex({
  required int? selectedIndex,
  required List<int> liveVisibleIndices,
  required List<int> stateVisibleIndices,
}) {
  final sortedLiveVisibleIndices = List<int>.from(liveVisibleIndices)..sort();
  final sortedStateVisibleIndices = List<int>.from(stateVisibleIndices)..sort();

  if (selectedIndex != null) {
    if (sortedLiveVisibleIndices.isEmpty && sortedStateVisibleIndices.isEmpty) {
      return selectedIndex;
    }

    if (sortedLiveVisibleIndices.contains(selectedIndex) ||
        sortedStateVisibleIndices.contains(selectedIndex)) {
      return selectedIndex;
    }
  }

  if (sortedLiveVisibleIndices.isNotEmpty) {
    return sortedLiveVisibleIndices.first;
  }

  if (sortedStateVisibleIndices.isNotEmpty) {
    return sortedStateVisibleIndices.first;
  }

  return selectedIndex ?? 0;
}

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
  final SelectionSyncController? selectionSyncController;

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
    this.selectionSyncController,
  });

  @override
  State<SimpleTextViewer> createState() => _SimpleTextViewerState();
}

class _SimpleTextViewerState extends State<SimpleTextViewer> {
  // דגל סטטי: מונע מהטקסט הראשי לדרוס העתקה שכבר בוצעה ע"י מפרש
  static bool _commentaryCopyHandled = false;
  // מצביע סטטי: רק הפרשן האחרון שנבחר בו טקסט מטפל ב-Ctrl+C
  static _SimpleTextViewerState? _lastActiveCommentary;

  late final ItemScrollController _scrollController;
  late final ItemPositionsListener _positionsListener;
  FocusNode? _keyboardFocusNode;
  bool _shouldPreserveKeyboardFocus = false;
  bool _pendingKeyboardFocusRestore = false;
  bool _wasMenuFocused = false;
  String? _savedSelectedText;
  int? _savedSelectedIndex;
  int _initialScrollRestoreAttempts = 0;
  final Map<String, Future<bool>> _removeNikudCache = {};
  final DictionaryLookupRepository _dictionaryLookupRepository =
      DictionaryLookupRepository.instance;
  final Object _selectionOwner = Object();
  int _selectionRevision = 0;

  bool _isTextInputFocused() {
    return isTextInputFocusNode(FocusManager.instance.primaryFocus);
  }

  bool _isMenuFocused() {
    return isMenuFocusNode(FocusManager.instance.primaryFocus);
  }

  /// מאזין לשינויי פוקוס גלובליים כדי לזהות סגירת תת-תפריט.
  ///
  /// כשהפוקוס יוצא מתפריט הקשר (החלף מפרש / קישורים) ולא חוזר אוטומטית
  /// לטקסט הראשי, מקשי החיצים מפסיקים לעבוד עד שהמשתמש לוחץ שוב.
  /// אנחנו מחזירים פוקוס רק אם הפוקוס "מרחף" ב-FocusScope של page-shape
  /// עצמו - לא אם המשתמש העביר פוקוס במכוון לכפתור / דיאלוג / רכיב אחר.
  void _handleGlobalFocusChange() {
    if (!mounted || !widget.isMainText) {
      return;
    }

    final isMenuNow = _isMenuFocused();
    final menuJustClosed = _wasMenuFocused && !isMenuNow;
    _wasMenuFocused = isMenuNow;

    if (!menuJustClosed) {
      return;
    }

    final myFocusNode = _keyboardFocusNode;
    if (myFocusNode == null || myFocusNode.hasFocus) {
      return;
    }

    // הפוקוס נחשב "מרחף" אך ורק אם הוא נמצא על FocusScopeNode העוטף שלנו.
    // אם הוא על widget מכוון אחר (כפתור, פאנל צד וכו') או על scope של דיאלוג -
    // המשתמש בחר בו, ואסור לגנוב.
    final primaryFocus = FocusManager.instance.primaryFocus;
    if (primaryFocus is! FocusScopeNode) {
      return;
    }
    if (primaryFocus != myFocusNode.enclosingScope) {
      return;
    }

    _requestKeyboardFocusAfterFrame('menu-closed');
  }

  void _ensureKeyboardFocusAfterLoss(String reason) {
    if (!widget.isMainText ||
        !_shouldPreserveKeyboardFocus ||
        _pendingKeyboardFocusRestore ||
        _isTextInputFocused() ||
        _isMenuFocused()) {
      return;
    }

    _pendingKeyboardFocusRestore = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pendingKeyboardFocusRestore = false;
      if (!mounted || _isTextInputFocused() || _isMenuFocused()) {
        return;
      }
      _requestKeyboardFocus(reason);
    });
  }

  FocusNode get _resolvedKeyboardFocusNode {
    return _keyboardFocusNode ??= FocusNode(
      debugLabel: 'PageShapeContentFocus',
    )..addListener(() {
        if (!(_keyboardFocusNode?.hasFocus ?? false)) {
          _ensureKeyboardFocusAfterLoss('focus-node-lost');
        }
      });
  }

  void _requestKeyboardFocus(String reason) {
    final focusNode = _resolvedKeyboardFocusNode;
    if (!widget.isMainText || !focusNode.canRequestFocus) {
      return;
    }

    // אם המשתמש כותב בשדה חיפוש/קלט אחר - לא לגנוב ממנו פוקוס
    if (_isTextInputFocused()) {
      return;
    }

    // אם פתוח תת-תפריט (החלף מפרש / קישורים) - לא לגנוב ממנו פוקוס,
    // אחרת התת-תפריט ייסגר מיד.
    if (_isMenuFocused()) {
      return;
    }

    _shouldPreserveKeyboardFocus = true;
    focusNode.requestFocus();
  }

  void _requestKeyboardFocusAfterFrame(String reason) {
    if (!widget.isMainText) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _requestKeyboardFocus(reason);
    });
  }

  @override
  void initState() {
    super.initState();
    _scrollController = widget.scrollController ?? ItemScrollController();
    _positionsListener =
        widget.positionsListener ?? ItemPositionsListener.create();
    _resolvedKeyboardFocusNode;

    // מאזין גלובלי ל-Ctrl+C במפרשים (ללא צורך בפוקוס)
    if (!widget.isMainText) {
      HardwareKeyboard.instance.addHandler(_handleCommentaryCopyKeyEvent);
    }

    // גלילה למיקום הנוכחי אחרי בניית הווידג'ט (רק לטקסט המרכזי)
    if (widget.isMainText) {
      FocusManager.instance.addListener(_handleGlobalFocusChange);
      _scheduleInitialScrollRestore();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _requestKeyboardFocus('initial-post-frame');
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final state = context.read<TextBookBloc>().state;
        if (state is TextBookLoaded) {
          context
              .read<PersonalNotesBloc>()
              .add(LoadPersonalNotes(state.book.title));
        }
      });
    }

    widget.selectionSyncController?.addListener(_handleExternalSelectionChange);
  }

  bool _handleCommentaryCopyKeyEvent(KeyEvent event) {
    // רק הפרשן שנבחר בו טקסט לאחרונה מטפל
    if (_lastActiveCommentary != this) return false;
    if (event is! KeyDownEvent) return false;
    final isCtrlC = HardwareKeyboard.instance.isControlPressed &&
        event.logicalKey == LogicalKeyboardKey.keyC;
    final isMetaC = HardwareKeyboard.instance.isMetaPressed &&
        event.logicalKey == LogicalKeyboardKey.keyC;
    if ((isCtrlC || isMetaC) &&
        _savedSelectedText != null &&
        _savedSelectedText!.trim().isNotEmpty) {
      _commentaryCopyHandled = true;
      _copyFormattedText().whenComplete(() {
        Future.delayed(const Duration(milliseconds: 100), () {
          _commentaryCopyHandled = false;
        });
      });
      return true;
    }
    return false;
  }

  @override
  void dispose() {
    widget.selectionSyncController
        ?.removeListener(_handleExternalSelectionChange);
    if (widget.isMainText) {
      FocusManager.instance.removeListener(_handleGlobalFocusChange);
    }
    if (!widget.isMainText) {
      HardwareKeyboard.instance.removeHandler(_handleCommentaryCopyKeyEvent);
      if (_lastActiveCommentary == this) _lastActiveCommentary = null;
    }
    _keyboardFocusNode?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SimpleTextViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectionSyncController != widget.selectionSyncController) {
      oldWidget.selectionSyncController
          ?.removeListener(_handleExternalSelectionChange);
      widget.selectionSyncController
          ?.addListener(_handleExternalSelectionChange);
    }
  }

  void _handleExternalSelectionChange() {
    final controller = widget.selectionSyncController;
    if (controller == null ||
        identical(controller.activeOwner, _selectionOwner)) {
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _selectionRevision = controller.revision;
      _savedSelectedText = null;
      _savedSelectedIndex = null;
    });

    if (!widget.isMainText && _lastActiveCommentary == this) {
      _lastActiveCommentary = null;
    }
  }

  @override
  void reassemble() {
    final shouldRestoreFocus =
        widget.isMainText && (_keyboardFocusNode?.hasFocus ?? false);
    _keyboardFocusNode?.dispose();
    _keyboardFocusNode = null;
    super.reassemble();
    if (shouldRestoreFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _requestKeyboardFocus('hot-reload-reassemble');
      });
    }
  }

  void _scheduleInitialScrollRestore() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final restored = _scrollToCurrentPosition();
      if (restored) {
        return;
      }
      if (_initialScrollRestoreAttempts >= 10) {
        return;
      }

      _initialScrollRestoreAttempts++;
      Future.delayed(
        const Duration(milliseconds: 50),
        _scheduleInitialScrollRestore,
      );
    });
  }

  /// גלילה למיקום הנוכחי (visibleIndices או selectedIndex)
  bool _scrollToCurrentPosition() {
    final bloc = context.read<TextBookBloc>();
    final state = bloc.state;
    if (state is! TextBookLoaded || !_scrollController.isAttached) {
      return false;
    }

    final targetIndex = state.visibleIndices.isNotEmpty
        ? state.visibleIndices.first
        : state.selectedIndex;

    if (targetIndex == null || targetIndex >= widget.content.length) {
      return false;
    }

    _scrollController.jumpTo(index: targetIndex);
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

    final categoryId = widget.reportBook?.categoryId;
    final fileType = widget.reportBook?.fileType;
    return _removeNikudCache.putIfAbsent(
      _removeNikudCacheKey(
        title: targetTitle,
        defaultRemoveNikud: settingsState.defaultRemoveNikud,
        removeNikudFromTanach: settingsState.removeNikudFromTanach,
        categoryId: categoryId,
        fileType: fileType,
      ),
      () => resolveRemoveNikudForBook(
        title: targetTitle,
        defaultRemoveNikud: settingsState.defaultRemoveNikud,
        removeNikudFromTanach: settingsState.removeNikudFromTanach,
        categoryId: categoryId,
        fileType: fileType,
      ),
    );
  }

  String _removeNikudCacheKey({
    required String title,
    required bool defaultRemoveNikud,
    required bool removeNikudFromTanach,
    int? categoryId,
    String? fileType,
  }) {
    return '$title|$defaultRemoveNikud|$removeNikudFromTanach|$categoryId|$fileType';
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
      searchOptions: widget.isMainText ? state.searchOptions : const {},
      alternativeWords: widget.isMainText ? state.alternativeWords : const {},
      spacingValues: widget.isMainText ? state.spacingValues : const {},
      isFuzzySearch: widget.isMainText && state.searchMode == SearchMode.fuzzy,
      searchMode: widget.isMainText ? state.searchMode : SearchMode.exact,
      searchDistance: widget.isMainText ? state.searchDistance : 0,
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
      if (mounted) setState(() => _savedSelectedText = null);
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

  bool _handleNavigationLogicalKey(
    LogicalKeyboardKey logicalKey, {
    required bool isControlPressed,
    required String source,
  }) {
    if (!widget.isMainText) {
      return false;
    }

    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded) {
      return false;
    }

    final liveVisibleIndices = _positionsListener.itemPositions.value
        .map((position) => position.index)
        .toList();
    final currentIndex = resolvePageShapeNavigationBaseIndex(
      selectedIndex: state.selectedIndex,
      liveVisibleIndices: liveVisibleIndices,
      stateVisibleIndices: state.visibleIndices,
    );

    if (logicalKey == LogicalKeyboardKey.arrowDown) {
      final nextIndex = (currentIndex + 1).clamp(0, widget.content.length - 1);
      if (nextIndex == currentIndex) {
        return true;
      }
      context.read<TextBookBloc>().add(UpdateSelectedIndex(nextIndex));
      if (_scrollController.isAttached) {
        _scrollController.scrollTo(
          index: nextIndex,
          duration: const Duration(milliseconds: 200),
          alignment: 0.5,
        );
      }
      _requestKeyboardFocusAfterFrame('navigation-arrow-down');
      return true;
    }

    if (logicalKey == LogicalKeyboardKey.arrowUp) {
      final prevIndex = (currentIndex - 1).clamp(0, widget.content.length - 1);
      if (prevIndex == currentIndex) {
        return true;
      }
      context.read<TextBookBloc>().add(UpdateSelectedIndex(prevIndex));
      if (_scrollController.isAttached) {
        _scrollController.scrollTo(
          index: prevIndex,
          duration: const Duration(milliseconds: 200),
          alignment: 0.5,
        );
      }
      _requestKeyboardFocusAfterFrame('navigation-arrow-up');
      return true;
    }

    if (logicalKey == LogicalKeyboardKey.pageDown) {
      final nextIndex = (currentIndex + 10).clamp(0, widget.content.length - 1);
      context.read<TextBookBloc>().add(UpdateSelectedIndex(nextIndex));
      if (_scrollController.isAttached) {
        _scrollController.scrollTo(
          index: nextIndex,
          duration: const Duration(milliseconds: 300),
          alignment: 0.5,
        );
      }
      _requestKeyboardFocusAfterFrame('navigation-page-down');
      return true;
    }

    if (logicalKey == LogicalKeyboardKey.pageUp) {
      final prevIndex = (currentIndex - 10).clamp(0, widget.content.length - 1);
      context.read<TextBookBloc>().add(UpdateSelectedIndex(prevIndex));
      if (_scrollController.isAttached) {
        _scrollController.scrollTo(
          index: prevIndex,
          duration: const Duration(milliseconds: 300),
          alignment: 0.5,
        );
      }
      _requestKeyboardFocusAfterFrame('navigation-page-up');
      return true;
    }

    if (logicalKey == LogicalKeyboardKey.home && isControlPressed) {
      context.read<TextBookBloc>().add(const UpdateSelectedIndex(0));
      if (_scrollController.isAttached) {
        _scrollController.scrollTo(
          index: 0,
          duration: const Duration(milliseconds: 300),
        );
      }
      _requestKeyboardFocusAfterFrame('navigation-home');
      return true;
    }

    if (logicalKey == LogicalKeyboardKey.end && isControlPressed) {
      final lastIndex = widget.content.length - 1;
      context.read<TextBookBloc>().add(UpdateSelectedIndex(lastIndex));
      if (_scrollController.isAttached) {
        _scrollController.scrollTo(
          index: lastIndex,
          duration: const Duration(milliseconds: 300),
        );
      }
      _requestKeyboardFocusAfterFrame('navigation-end');
      return true;
    }

    return false;
  }

  /// תפריט הקשר
  List<AppContextMenuEntry> _buildContextMenu(TextBookLoaded state, int index,
      BuildContext menuContext, Offset tapPosition, String? capturedText) {
    List<AppContextMenuEntry> commentatorItems = [];
    if (!widget.isMainText && widget.bookTitle != null) {
      commentatorItems = _buildCommentatorSwitchMenu(state);
    }

    final lineLinks = state.linksByLine[index + 1] ?? const <Link>[];
    List<AppContextMenuEntry> buildLinksItems() {
      final items = <AppContextMenuEntry>[];
      if (widget.onOpenSidebarTab != null) {
        items.add(AppContextMenuEntry(
          label: 'פתח חלונית קישורים',
          icon: FluentIcons.panel_right_24_regular,
          onTap: () => widget.onOpenSidebarTab!(0),
        ));
        items.add(const AppContextMenuEntry.divider());
      }
      items.addAll(lineLinks
          .where((link) =>
              !LinkTypes.isCommentaryOrTargum(link.connectionType) &&
              link.start == null &&
              link.end == null)
          .map((link) => AppContextMenuEntry(
                label: link.fallbackDisplayReference,
                labelWidget: FutureBuilder<String>(
                  future: link.displayReference,
                  builder: (context, snapshot) => Text(
                    snapshot.data ?? link.fallbackDisplayReference,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: TextDirection.rtl,
                  ),
                ),
                onTap: () => widget.openBookCallback(
                  TextBookTab(
                    book: TextBook(title: utils.getTitleFromPath(link.path2)),
                    index: link.index2 - 1,
                    openLeftPane: (Settings.getValue<bool>('key-pin-sidebar') ??
                            false) ||
                        (Settings.getValue<bool>('key-default-sidebar-open') ??
                            false),
                  ),
                ),
              )));
      return items;
    }

    final hasLinkItems = lineLinks.any((link) =>
        !LinkTypes.isCommentaryOrTargum(link.connectionType) &&
        link.start == null &&
        link.end == null);

    final entries = <AppContextMenuEntry>[];

    if (widget.isMainText) {
      entries.add(AppContextMenuEntry(
        label: 'חיפוש',
        icon: FluentIcons.search_24_regular,
        onTap: () {
          if (widget.onOpenSearch != null) {
            widget.onOpenSearch!(capturedText);
          } else {
            UiSnack.show('חיפוש לא זמין בתצוגה זו');
          }
        },
      ));
    }

    if (commentatorItems.isNotEmpty) {
      if (entries.isNotEmpty) entries.add(const AppContextMenuEntry.divider());
      entries.addAll(commentatorItems);
    }

    if (hasLinkItems) {
      entries.add(const AppContextMenuEntry.divider());
      entries.add(AppContextMenuEntry(
        label: 'קישורים',
        icon: FluentIcons.link_24_regular,
        childrenBuilder: buildLinksItems,
      ));
    }

    final dictionaryText = (capturedText?.trim().isNotEmpty == true)
        ? capturedText
        : wordAtGlobalPosition(tapPosition);
    final dictionaryEntries = buildDictionaryContextMenuEntries(
      context: context,
      selectedText: dictionaryText,
      repository: _dictionaryLookupRepository,
    );
    if (dictionaryEntries.isNotEmpty) {
      entries.add(const AppContextMenuEntry.divider());
      entries.addAll(dictionaryEntries);
    }

    entries.add(const AppContextMenuEntry.divider());
    entries.addAll([
      AppContextMenuEntry(
        label: 'הוסף הערה אישית ',
        icon: FluentIcons.note_add_24_regular,
        onTap: () => _createNoteForCurrentLine(index, capturedText),
      ),
      AppContextMenuEntry(
        label: 'דווח על טעות בספר',
        icon: FluentIcons.error_circle_24_regular,
        onTap: () => _openErrorReportDialog(capturedText ?? ''),
      ),
      const AppContextMenuEntry.divider(),
      AppContextMenuEntry(
        label: 'העתק',
        icon: FluentIcons.copy_24_regular,
        enabled: capturedText != null && capturedText.trim().isNotEmpty,
        onTap: () => _copyFormattedText(capturedText),
      ),
      AppContextMenuEntry(
        label: 'העתק את כל הפסקה',
        icon: FluentIcons.document_copy_24_regular,
        enabled: index >= 0 && index < widget.content.length,
        onTap: () => _copyParagraphByIndex(index),
      ),
    ]);

    if (widget.isMainText) {
      final pluginItems = ContextMenuRegistry.instance.getAll();
      if (pluginItems.isNotEmpty) {
        entries.add(const AppContextMenuEntry.divider());
        for (final record in pluginItems) {
          final pluginId = record.$1;
          final item = record.$2;
          entries.add(AppContextMenuEntry(
            label: item.label,
            icon: fluentIconFromName(item.icon),
            onTap: () {
              unawaited(PluginRuntimeDispatcher.instance.dispatchEventToPlugin(
                pluginId,
                'reader.context_menu_item_clicked',
                {
                  'itemId': item.id,
                  'selectedText': capturedText ?? '',
                  'currentRef': state.currentTitle ?? '',
                  'currentBook': state.book.title,
                  'currentBookId': state.book.title,
                  'currentIndex': index,
                },
              ));
            },
          ));
        }
      }
    }

    return _normalizeEntries(entries);
  }

  List<AppContextMenuEntry> _normalizeEntries(
      List<AppContextMenuEntry> entries) {
    final result = <AppContextMenuEntry>[];
    for (final e in entries) {
      if (e.isDivider) {
        if (result.isEmpty || result.last.isDivider) continue;
        result.add(e);
      } else {
        result.add(e);
      }
    }
    while (result.isNotEmpty && result.last.isDivider) {
      result.removeLast();
    }
    return result;
  }

  /// יצירת הערה לשורה הנוכחית
  Future<void> _createNoteForCurrentLine(int index,
      [String? capturedText]) async {
    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded) return;

    final selectedText = capturedText ?? _savedSelectedText;
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

    final bool removeNikud;
    if (widget.reportBook != null) {
      final targetTitle = widget.reportBook!.title;
      final categoryId = widget.reportBook!.categoryId;
      final fileType = widget.reportBook!.fileType;
      removeNikud = await _removeNikudCache.putIfAbsent(
        _removeNikudCacheKey(
          title: targetTitle,
          defaultRemoveNikud: settingsState.defaultRemoveNikud,
          removeNikudFromTanach: settingsState.removeNikudFromTanach,
          categoryId: categoryId,
          fileType: fileType,
        ),
        () => resolveRemoveNikudForBook(
          title: targetTitle,
          defaultRemoveNikud: settingsState.defaultRemoveNikud,
          removeNikudFromTanach: settingsState.removeNikudFromTanach,
          categoryId: categoryId,
          fileType: fileType,
        ),
      );
    } else {
      removeNikud =
          textBookState is TextBookLoaded && textBookState.removeNikud;
    }
    final processedText = removeNikud ? utils.removeVolwels(text) : text;

    final plainText = utils.stripHtmlIfNeeded(processedText);

    String finalText = plainText;
    String finalHtmlText = processedText;

    if (settingsState.copyWithHeaders != 'none' &&
        textBookState is TextBookLoaded) {
      final headerBook = widget.reportBook ?? textBookState.book;
      final bookName = CopyUtils.extractBookName(headerBook);
      final currentPath = await CopyUtils.extractCurrentPath(
        headerBook,
        index,
        bookContent:
            widget.reportBook != null ? widget.content : textBookState.content,
      );

      finalText = CopyUtils.formatTextWithHeaders(
        originalText: plainText,
        copyWithHeaders: settingsState.copyWithHeaders,
        copyHeaderFormat: settingsState.copyHeaderFormat,
        bookName: bookName,
        currentPath: currentPath,
      );

      finalHtmlText = CopyUtils.formatTextWithHeaders(
        originalText: processedText,
        copyWithHeaders: settingsState.copyWithHeaders,
        copyHeaderFormat: settingsState.copyHeaderFormat,
        bookName: bookName,
        currentPath: currentPath,
      );
    }

    final copyContent = CopyUtils.applyCopyPreferencesForClipboard(
      plainText: finalText,
      htmlText: finalHtmlText,
      replaceHolyNames: settingsState.replaceHolyNames,
    );

    final item = DataWriterItem();
    item.add(Formats.plainText(copyContent.plainText.trimRight()));
    item.add(Formats.htmlText(_formatTextAsHtml(copyContent.htmlText)));

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
  Future<void> _copyFormattedText([String? capturedText]) async {
    // מפרש כבר טיפל בהעתקה - לא נדרוס
    if (widget.isMainText && _commentaryCopyHandled) return;

    final plainText = capturedText ?? _savedSelectedText;

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
        headerBookOverride: widget.reportBook,
        headerContentOverride:
            widget.reportBook != null ? widget.content : null,
      );
    } catch (e) {
      if (mounted) {
        UiSnack.showError('שגיאה בהעתקה מעוצבת: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
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
                    key: ValueKey(
                      '${widget.isMainText ? 'main' : 'commentary'}_selection_$_selectionRevision',
                    ),
                    // ביטול תפריט ברירת המחדל של Flutter - נשתמש רק ב-ContextMenuRegion
                    contextMenuBuilder: (context, selectableRegionState) =>
                        const SizedBox.shrink(),
                    onSelectionChanged: (selection) {
                      if (selection != null &&
                          selection.plainText.trim().isNotEmpty) {
                        widget.selectionSyncController
                            ?.activate(_selectionOwner);
                      } else {
                        widget.selectionSyncController?.clear(_selectionOwner);
                      }
                      _handleSelectionChange(selection?.plainText);
                      _requestKeyboardFocus('selection-changed');
                      if (!widget.isMainText) {
                        if (selection != null &&
                            selection.plainText.isNotEmpty) {
                          _lastActiveCommentary = this;
                        } else if (selection == null &&
                            _lastActiveCommentary == this) {
                          // בחירה בוטלה לחלוטין — מנקים כדי לא לאפשר העתקה "רפאים"
                          _lastActiveCommentary = null;
                        }
                      }
                    },
                    child: Actions(
                      actions: {
                        _CopyTextIntent: CallbackAction<_CopyTextIntent>(
                          onInvoke: (_) {
                            _copyFormattedText();
                            return null;
                          },
                        ),
                        CopySelectionTextIntent:
                            CallbackAction<CopySelectionTextIntent>(
                          onInvoke: (_) {
                            _copyFormattedText();
                            return null;
                          },
                        ),
                      },
                      child: Shortcuts(
                        shortcuts: {
                          LogicalKeySet(LogicalKeyboardKey.control,
                              LogicalKeyboardKey.keyC): const _CopyTextIntent(),
                          LogicalKeySet(LogicalKeyboardKey.meta,
                              LogicalKeyboardKey.keyC): const _CopyTextIntent(),
                        },
                        child: Focus(
                          focusNode: _resolvedKeyboardFocusNode,
                          autofocus: widget.isMainText,
                          canRequestFocus: widget.isMainText,
                          onFocusChange: (hasFocus) {
                            if (!hasFocus) {
                              _ensureKeyboardFocusAfterLoss(
                                'focus-widget-lost',
                              );
                            }
                          },
                          onKeyEvent: (_, event) {
                            if (!shouldHandlePageShapeNavigationKeyEvent(
                                event)) {
                              return KeyEventResult.ignored;
                            }

                            final handled = _handleNavigationLogicalKey(
                              event.logicalKey,
                              isControlPressed:
                                  HardwareKeyboard.instance.isControlPressed,
                              source: 'content-focus',
                            );
                            return handled
                                ? KeyEventResult.handled
                                : KeyEventResult.ignored;
                          },
                          child: widget.useInternalScroll
                              ? ScrollablePositionedList.builder(
                                  itemScrollController: _scrollController,
                                  itemPositionsListener: _positionsListener,
                                  itemCount: widget.content.length,
                                  padding: const EdgeInsets.all(4),
                                  itemBuilder: (context, index) => _buildLine(
                                      index, state, context, noteMap),
                                )
                              : ListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: widget.content.length,
                                  padding: const EdgeInsets.all(4),
                                  itemBuilder: (context, index) => _buildLine(
                                      index, state, context, noteMap),
                                ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLine(
    int index,
    TextBookLoaded state,
    BuildContext context,
    Map<int, List<PersonalNote>> noteMap,
  ) {
    // נתפס בזמן BUILD (כמו selectedText ב-ValueListenableBuilder של Combined),
    // כך שגם אם onSelectionChanged(null) ירוץ לפני menuBuilder, ה-closure
    // כבר סגור על הערך הנכון מהבנייה האחרונה.
    final savedTextAtBuild = _savedSelectedText;

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
              _requestKeyboardFocus('line-tap-$index');
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
        setState(() {
          _savedSelectedIndex = index;
        });
      },
      child: AppContextMenuRegion(
        menuBuilder: (menuCtx, tapPos) =>
            _buildContextMenu(state, index, menuCtx, tapPos, savedTextAtBuild),
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
                          _removeNikudCacheKey(
                            title: targetTitle,
                            defaultRemoveNikud:
                                settingsState.defaultRemoveNikud,
                            removeNikudFromTanach:
                                settingsState.removeNikudFromTanach,
                            categoryId: widget.isMainText
                                ? state.book.categoryId
                                : widget.reportBook?.categoryId,
                            fileType: widget.isMainText
                                ? state.book.fileType
                                : widget.reportBook?.fileType,
                          ),
                          () => resolveRemoveNikudForBook(
                            title: targetTitle,
                            defaultRemoveNikud:
                                settingsState.defaultRemoveNikud,
                            removeNikudFromTanach:
                                settingsState.removeNikudFromTanach,
                            categoryId: widget.isMainText
                                ? state.book.categoryId
                                : widget.reportBook?.categoryId,
                            fileType: widget.isMainText
                                ? state.book.fileType
                                : widget.reportBook?.fileType,
                          ),
                        ));

              // הדגשה ממוקדת מקישור עומק (רק בטקסט המרכזי, רק על הסעיף שצוין)
              final isPinpointTarget = widget.isMainText &&
                  state.pinpointHighlightIndex == index &&
                  state.pinpointHighlightText != null &&
                  state.pinpointHighlightText!.isNotEmpty;
              final hasPinpoint =
                  widget.isMainText && state.pinpointHighlightIndex != null;
              final searchText = isPinpointTarget
                  ? state.pinpointHighlightText!
                  : (hasPinpoint
                      ? ''
                      : (widget.isMainText ? state.searchText : ''));
              final useStateSearchSettings = widget.isMainText && !hasPinpoint;
              final effectiveSearchMode =
                  useStateSearchSettings ? state.searchMode : SearchMode.exact;

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
                      searchOptions: useStateSearchSettings
                          ? state.searchOptions
                          : const {},
                      alternativeWords: useStateSearchSettings
                          ? state.alternativeWords
                          : const {},
                      spacingValues: useStateSearchSettings
                          ? state.spacingValues
                          : const {},
                      isFuzzySearch: effectiveSearchMode == SearchMode.fuzzy,
                      searchMode: effectiveSearchMode,
                      searchDistance:
                          useStateSearchSettings ? state.searchDistance : 0,
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
                        showSingleActionDialog(
                          context: context,
                          title: 'הערה לשורה זו',
                          customContent: PersonalNoteContentView(note: note),
                          confirmText: 'סגור',
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
  List<AppContextMenuEntry> _buildCommentatorSwitchMenu(TextBookLoaded state) {
    final availableCommentators = state.availableCommentators;
    if (availableCommentators.isEmpty) return [];

    final groups = state.commentatorGroups;
    final tanachGroup = CommentatorGroup.groupByTitle(groups, 'תורה שבכתב');
    final chazalGroup = CommentatorGroup.groupByTitle(groups, 'חז"ל');
    final rishonimGroup = CommentatorGroup.groupByTitle(groups, 'ראשונים');
    final acharonimGroup = CommentatorGroup.groupByTitle(groups, 'אחרונים');
    final modernGroup = CommentatorGroup.groupByTitle(groups, 'מחברי זמננו');
    final allGrouped = [
      ...tanachGroup.commentators,
      ...chazalGroup.commentators,
      ...rishonimGroup.commentators,
      ...acharonimGroup.commentators,
      ...modernGroup.commentators,
    ];
    final ungrouped =
        availableCommentators.where((c) => !allGrouped.contains(c)).toList();

    List<AppContextMenuEntry> buildGroup(List<String> commentators) =>
        commentators
            .map((c) => AppContextMenuEntry(
                  label: c,
                  icon: c == widget.bookTitle
                      ? FluentIcons.checkmark_24_regular
                      : null,
                  onTap: () => _switchCommentator(c, state),
                ))
            .toList();

    final children = <AppContextMenuEntry>[
      ...buildGroup(tanachGroup.commentators),
      if (tanachGroup.commentators.isNotEmpty &&
          chazalGroup.commentators.isNotEmpty)
        const AppContextMenuEntry.divider(),
      ...buildGroup(chazalGroup.commentators),
      if (chazalGroup.commentators.isNotEmpty &&
          rishonimGroup.commentators.isNotEmpty)
        const AppContextMenuEntry.divider(),
      ...buildGroup(rishonimGroup.commentators),
      if (rishonimGroup.commentators.isNotEmpty &&
          acharonimGroup.commentators.isNotEmpty)
        const AppContextMenuEntry.divider(),
      ...buildGroup(acharonimGroup.commentators),
      if (acharonimGroup.commentators.isNotEmpty &&
          modernGroup.commentators.isNotEmpty)
        const AppContextMenuEntry.divider(),
      ...buildGroup(modernGroup.commentators),
      if ((tanachGroup.commentators.isNotEmpty ||
              chazalGroup.commentators.isNotEmpty ||
              rishonimGroup.commentators.isNotEmpty ||
              acharonimGroup.commentators.isNotEmpty ||
              modernGroup.commentators.isNotEmpty) &&
          ungrouped.isNotEmpty)
        const AppContextMenuEntry.divider(),
      ...buildGroup(ungrouped),
    ];

    final normalized = _normalizeEntries(children);
    if (normalized.isEmpty) return [];

    return [
      AppContextMenuEntry(
        label: 'החלף מפרש',
        icon: FluentIcons.arrow_swap_24_regular,
        children: normalized,
      ),
    ];
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

class _CopyTextIntent extends Intent {
  const _CopyTextIntent();
}
