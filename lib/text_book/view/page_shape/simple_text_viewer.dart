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
import 'package:otzaria/utils/text/global_search_helper.dart';
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
import 'package:otzaria/text_book/utils/reading_segment_navigation.dart';
import 'package:otzaria/text_book/utils/reading_segments.dart';
import 'package:otzaria/utils/text/html_link_handler.dart';
import 'package:otzaria/text_book/view/widgets/continuous_reading_paragraph.dart';
import 'package:otzaria/text_book/view/selection/selection_sync_controller.dart';

/// ╫₧╫ק╫צ╫ש╫¿╫פ ╫פ╫נ╫¥ ╫נ╫ש╫¿╫ץ╫ó ╫פ╫₧╫º╫£╫ף╫¬ ╫ª╫¿╫ש╫ת ╫£╫פ╫á╫ש╫ó ╫ע╫£╫ש╫£╫פ ╫¿╫ª╫ש╫ñ╫פ ╫ס╫ª╫ץ╫¿╫¬ ╫פ╫ף╫ú.
bool shouldHandlePageShapeNavigationKeyEvent(KeyEvent event) {
  return event is KeyDownEvent || event is KeyRepeatEvent;
}

/// ╫ס╫ץ╫ף╫º╫¬ ╫פ╫נ╫¥ ╫פ╫ñ╫ץ╫º╫ץ╫í ╫פ╫á╫ץ╫¢╫ק╫ש ╫á╫₧╫ª╫נ ╫ס╫¬╫ץ╫ת ╫⌐╫ף╫פ ╫º╫£╫ר ╫ר╫º╫í╫ר╫ץ╫נ╫£╫ש.
///
/// ╫á╫ף╫¿╫⌐ ╫ó╫ס╫ץ╫¿ "╫ª╫ץ╫¿╫¬ ╫פ╫ף╫ú", ╫¢╫ש ╫פ╫ó╫ץ╫¿╫ת ╫⌐╫£ ╫פ╫ó╫¿╫ץ╫¬ ╫נ╫ש╫⌐╫ש╫ץ╫¬ ╫₧╫ס╫ץ╫í╫í `flutter_quill`
/// ╫ץ╫נ╫ש╫á╫ץ ╫₧╫צ╫ץ╫פ╫פ ╫¬╫₧╫ש╫ף ╫¢-`EditableText` ╫¿╫ע╫ש╫£.
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

/// ╫ס╫ץ╫ף╫º╫¬ ╫פ╫נ╫¥ ╫פ╫ñ╫ץ╫º╫ץ╫í ╫פ╫á╫ץ╫¢╫ק╫ש ╫á╫₧╫ª╫נ ╫ס╫¬╫ץ╫ת ╫¬╫ñ╫¿╫ש╫ר (╫¢╫₧╫ץ ╫¬╫ñ╫¿╫ש╫ר ╫פ╫º╫⌐╫¿/╫¬╫¬-╫¬╫ñ╫¿╫ש╫ר).
///
/// ╫á╫ף╫¿╫⌐ ╫¢╫ף╫ש ╫⌐╫£╫נ ╫á╫ק╫צ╫ש╫¿ ╫ñ╫ץ╫º╫ץ╫í ╫£╫ר╫º╫í╫ר ╫ס╫צ╫₧╫ƒ ╫⌐╫פ╫₧╫⌐╫¬╫₧╫⌐ ╫ñ╫ץ╫¬╫ק ╫¬╫¬-╫¬╫ñ╫¿╫ש╫ר,
/// ╫¢╫ש ╫ע╫צ╫ש╫£╫¬ ╫פ╫ñ╫ץ╫º╫ץ╫í ╫¬╫í╫ע╫ץ╫¿ ╫נ╫¬ ╫פ╫¬╫¬-╫¬╫ñ╫¿╫ש╫ר ╫₧╫ש╫ף.
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

/// ╫º╫ץ╫ס╫ó╫¬ ╫₧╫נ╫ש╫צ╫פ ╫נ╫ש╫á╫ף╫º╫í ╫ש╫¬╫ק╫ש╫£ ╫á╫ש╫ץ╫ץ╫ר ╫פ╫₧╫º╫£╫ף╫¬ ╫ס╫ª╫ץ╫¿╫¬ ╫פ╫ף╫ú.
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

/// ╫₧╫ק╫צ╫ש╫¿╫פ ╫נ╫¬ ╫⌐╫ץ╫¿╫¬ ╫פ╫₧╫º╫ץ╫¿ ╫⌐╫ש╫⌐ ╫£╫⌐╫₧╫¿ ╫ס╫ó╫¬ ╫₧╫ó╫ס╫¿ ╫ס╫ש╫ƒ ╫¬╫ª╫ץ╫ע╫¬ ╫⌐╫ץ╫¿╫ץ╫¬ ╫£╫¬╫ª╫ץ╫ע╫פ ╫¿╫ª╫ש╫ñ╫פ.
///
/// ╫פ╫⌐╫ץ╫¿╫פ ╫פ╫¿╫נ╫⌐╫ץ╫á╫פ ╫⌐╫á╫¿╫נ╫ש╫¬ ╫ó╫£ ╫פ╫₧╫í╫ת ╫פ╫ש╫נ ╫פ╫ó╫ץ╫ע╫ƒ ╫פ╫₧╫ף╫ץ╫ש╫º ╫ס╫ש╫ץ╫¬╫¿; ╫נ╫¥ ╫נ╫ש╫ƒ ╫₧╫ש╫ף╫ó ╫ע╫£╫ש╫£╫פ
/// ╫צ╫₧╫ש╫ƒ, ╫₧╫⌐╫¬╫₧╫⌐╫ש╫¥ ╫ס╫⌐╫ץ╫¿╫פ ╫פ╫₧╫í╫ץ╫₧╫á╫¬ ╫¢╫ע╫ש╫ס╫ץ╫ש.
int? resolveDisplayModeRestoreLineIndex({
  required List<int> visibleIndices,
  required int? selectedIndex,
  required int contentLength,
}) {
  final targetIndex =
      visibleIndices.isNotEmpty ? visibleIndices.first : selectedIndex;
  if (targetIndex == null || targetIndex < 0 || targetIndex >= contentLength) {
    return null;
  }
  return targetIndex;
}

/// ╫¬╫ª╫ץ╫ע╫¬ ╫ר╫º╫í╫ר ╫ñ╫⌐╫ץ╫ר╫פ - ╫₧╫⌐╫₧╫⌐╫¬ ╫ע╫¥ ╫£╫ר╫º╫í╫ר ╫פ╫₧╫¿╫¢╫צ╫ש ╫ץ╫ע╫¥ ╫£╫₧╫ñ╫¿╫⌐╫ש╫¥
class SimpleTextViewer extends StatefulWidget {
  final List<String> content;
  final double fontSize;
  final String? fontFamily;
  final Function(OpenedTab) openBookCallback;
  final ItemScrollController? scrollController;
  final ItemPositionsListener? positionsListener;
  final bool isMainText; // ╫פ╫נ╫¥ ╫צ╫פ ╫פ╫ר╫º╫í╫ר ╫פ╫₧╫¿╫¢╫צ╫ש ╫נ╫ץ ╫₧╫ñ╫¿╫⌐
  final String? title; // ╫¢╫ץ╫¬╫¿╫¬ (╫£╫¢╫ץ╫¬╫¿╫¬ ╫ó╫£╫ש╫ץ╫á╫פ)
  final String? bookTitle; // ╫⌐╫¥ ╫פ╫í╫ñ╫¿ (╫£╫₧╫ñ╫¿╫⌐╫ש╫¥ - ╫£╫ñ╫¬╫ש╫ק╫פ ╫ס╫ר╫נ╫ס ╫á╫ñ╫¿╫ף)
  final Set<int>? highlightedIndices; // ╫נ╫ש╫á╫ף╫º╫í╫ש╫¥ ╫£╫פ╫ף╫ע╫⌐╫פ (╫£╫₧╫ñ╫¿╫⌐╫ש╫¥)
  final VoidCallback? onCommentatorChanged; // callback ╫£╫¿╫ó╫á╫ץ╫ƒ ╫נ╫ק╫¿╫ש ╫פ╫ק╫£╫ñ╫¬ ╫₧╫ñ╫¿╫⌐
  final bool useInternalScroll; // ╫פ╫נ╫¥ ╫£╫פ╫⌐╫¬╫₧╫⌐ ╫ס╫ע╫£╫ש╫£╫פ ╫ñ╫á╫ש╫₧╫ש╫¬
  final ValueChanged<int>? onOpenSidebarTab;
  final ValueChanged<String?>?
      onOpenSearch; // callback ╫£╫ñ╫¬╫ש╫ק╫¬ ╫ק╫ש╫ñ╫ץ╫⌐ ╫ó╫¥ ╫פ╫ר╫º╫í╫ר ╫פ╫á╫ס╫ק╫¿
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
    this.useInternalScroll = true, // ╫ס╫¿╫ש╫¿╫¬ ╫₧╫ק╫ף╫£ - ╫ó╫¥ ╫ע╫£╫ש╫£╫פ ╫ñ╫á╫ש╫₧╫ש╫¬
    this.onOpenSidebarTab,
    this.onOpenSearch,
    this.reportBook,
    this.selectionSyncController,
  });

  @override
  State<SimpleTextViewer> createState() => _SimpleTextViewerState();
}

class _SimpleTextViewerState extends State<SimpleTextViewer> {
  // ╫ף╫ע╫£ ╫í╫ר╫ר╫ש: ╫₧╫ץ╫á╫ó ╫₧╫פ╫ר╫º╫í╫ר ╫פ╫¿╫נ╫⌐╫ש ╫£╫ף╫¿╫ץ╫í ╫פ╫ó╫¬╫º╫פ ╫⌐╫¢╫ס╫¿ ╫ס╫ץ╫ª╫ó╫פ ╫ó"╫ש ╫₧╫ñ╫¿╫⌐
  static bool _commentaryCopyHandled = false;
  // ╫₧╫ª╫ס╫ש╫ó ╫í╫ר╫ר╫ש: ╫¿╫º ╫פ╫ñ╫¿╫⌐╫ƒ ╫פ╫נ╫ק╫¿╫ץ╫ƒ ╫⌐╫á╫ס╫ק╫¿ ╫ס╫ץ ╫ר╫º╫í╫ר ╫₧╫ר╫ñ╫£ ╫ס-Ctrl+C
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
  bool? _lastContinuousReadingMode;
  int? _pendingDisplayModeRestoreLineIndex;
  List<String>? _cachedReadingSegmentContent;
  bool? _cachedReadingSegmentContinuous;
  List<ReadingSegment> _cachedReadingSegments = const [];
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

  /// ╫₧╫נ╫צ╫ש╫ƒ ╫£╫⌐╫ש╫á╫ץ╫ש╫ש ╫ñ╫ץ╫º╫ץ╫í ╫ע╫£╫ץ╫ס╫£╫ש╫ש╫¥ ╫¢╫ף╫ש ╫£╫צ╫פ╫ץ╫¬ ╫í╫ע╫ש╫¿╫¬ ╫¬╫¬-╫¬╫ñ╫¿╫ש╫ר.
  ///
  /// ╫¢╫⌐╫פ╫ñ╫ץ╫º╫ץ╫í ╫ש╫ץ╫ª╫נ ╫₧╫¬╫ñ╫¿╫ש╫ר ╫פ╫º╫⌐╫¿ (╫פ╫ק╫£╫ú ╫₧╫ñ╫¿╫⌐ / ╫º╫ש╫⌐╫ץ╫¿╫ש╫¥) ╫ץ╫£╫נ ╫ק╫ץ╫צ╫¿ ╫נ╫ץ╫ר╫ץ╫₧╫ר╫ש╫¬
  /// ╫£╫ר╫º╫í╫ר ╫פ╫¿╫נ╫⌐╫ש, ╫₧╫º╫⌐╫ש ╫פ╫ק╫ש╫ª╫ש╫¥ ╫₧╫ñ╫í╫ש╫º╫ש╫¥ ╫£╫ó╫ס╫ץ╫ף ╫ó╫ף ╫⌐╫פ╫₧╫⌐╫¬╫₧╫⌐ ╫£╫ץ╫ק╫Ñ ╫⌐╫ץ╫ס.
  /// ╫נ╫á╫ק╫á╫ץ ╫₧╫ק╫צ╫ש╫¿╫ש╫¥ ╫ñ╫ץ╫º╫ץ╫í ╫¿╫º ╫נ╫¥ ╫פ╫ñ╫ץ╫º╫ץ╫í "╫₧╫¿╫ק╫ú" ╫ס-FocusScope ╫⌐╫£ page-shape
  /// ╫ó╫ª╫₧╫ץ - ╫£╫נ ╫נ╫¥ ╫פ╫₧╫⌐╫¬╫₧╫⌐ ╫פ╫ó╫ס╫ש╫¿ ╫ñ╫ץ╫º╫ץ╫í ╫ס╫₧╫¢╫ץ╫ץ╫ƒ ╫£╫¢╫ñ╫¬╫ץ╫¿ / ╫ף╫ש╫נ╫£╫ץ╫ע / ╫¿╫¢╫ש╫ס ╫נ╫ק╫¿.
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

    // ╫פ╫ñ╫ץ╫º╫ץ╫í ╫á╫ק╫⌐╫ס "╫₧╫¿╫ק╫ú" ╫נ╫ת ╫ץ╫¿╫º ╫נ╫¥ ╫פ╫ץ╫נ ╫á╫₧╫ª╫נ ╫ó╫£ FocusScopeNode ╫פ╫ó╫ץ╫ר╫ú ╫⌐╫£╫á╫ץ.
    // ╫נ╫¥ ╫פ╫ץ╫נ ╫ó╫£ widget ╫₧╫¢╫ץ╫ץ╫ƒ ╫נ╫ק╫¿ (╫¢╫ñ╫¬╫ץ╫¿, ╫ñ╫נ╫á╫£ ╫ª╫ף ╫ץ╫¢╫ץ') ╫נ╫ץ ╫ó╫£ scope ╫⌐╫£ ╫ף╫ש╫נ╫£╫ץ╫ע -
    // ╫פ╫₧╫⌐╫¬╫₧╫⌐ ╫ס╫ק╫¿ ╫ס╫ץ, ╫ץ╫נ╫í╫ץ╫¿ ╫£╫ע╫á╫ץ╫ס.
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

    // ╫נ╫¥ ╫פ╫₧╫⌐╫¬╫₧╫⌐ ╫¢╫ץ╫¬╫ס ╫ס╫⌐╫ף╫פ ╫ק╫ש╫ñ╫ץ╫⌐/╫º╫£╫ר ╫נ╫ק╫¿ - ╫£╫נ ╫£╫ע╫á╫ץ╫ס ╫₧╫₧╫á╫ץ ╫ñ╫ץ╫º╫ץ╫í
    if (_isTextInputFocused()) {
      return;
    }

    // ╫נ╫¥ ╫ñ╫¬╫ץ╫ק ╫¬╫¬-╫¬╫ñ╫¿╫ש╫ר (╫פ╫ק╫£╫ú ╫₧╫ñ╫¿╫⌐ / ╫º╫ש╫⌐╫ץ╫¿╫ש╫¥) - ╫£╫נ ╫£╫ע╫á╫ץ╫ס ╫₧╫₧╫á╫ץ ╫ñ╫ץ╫º╫ץ╫í,
    // ╫נ╫ק╫¿╫¬ ╫פ╫¬╫¬-╫¬╫ñ╫¿╫ש╫ר ╫ש╫ש╫í╫ע╫¿ ╫₧╫ש╫ף.
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

    // ╫₧╫נ╫צ╫ש╫ƒ ╫ע╫£╫ץ╫ס╫£╫ש ╫£-Ctrl+C ╫ס╫₧╫ñ╫¿╫⌐╫ש╫¥ (╫£╫£╫נ ╫ª╫ץ╫¿╫ת ╫ס╫ñ╫ץ╫º╫ץ╫í)
    if (!widget.isMainText) {
      HardwareKeyboard.instance.addHandler(_handleCommentaryCopyKeyEvent);
    }

    // ╫ע╫£╫ש╫£╫פ ╫£╫₧╫ש╫º╫ץ╫¥ ╫פ╫á╫ץ╫¢╫ק╫ש ╫נ╫ק╫¿╫ש ╫ס╫á╫ש╫ש╫¬ ╫פ╫ץ╫ץ╫ש╫ף╫ע'╫ר (╫¿╫º ╫£╫ר╫º╫í╫ר ╫פ╫₧╫¿╫¢╫צ╫ש)
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
    // ╫¿╫º ╫פ╫ñ╫¿╫⌐╫ƒ ╫⌐╫á╫ס╫ק╫¿ ╫ס╫ץ ╫ר╫º╫í╫ר ╫£╫נ╫ק╫¿╫ץ╫á╫פ ╫₧╫ר╫ñ╫£
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
        controller.activeOwner == null ||
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

  /// ╫ע╫£╫ש╫£╫פ ╫£╫₧╫ש╫º╫ץ╫¥ ╫פ╫á╫ץ╫¢╫ק╫ש (visibleIndices ╫נ╫ץ selectedIndex)
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

    final settingsState = context.read<SettingsBloc>().state;
    _scrollController.jumpTo(
      index: _segmentIndexForSourceLine(settingsState, targetIndex),
    );
    return true;
  }

  void _preserveScrollAfterDisplayModeChange({
    required TextBookLoaded state,
    required SettingsState settingsState,
    required bool continuous,
  }) {
    final previousContinuous = _lastContinuousReadingMode;
    _lastContinuousReadingMode = continuous;

    if (!widget.isMainText ||
        !widget.useInternalScroll ||
        previousContinuous == null ||
        previousContinuous == continuous) {
      return;
    }

    final targetIndex = resolveDisplayModeRestoreLineIndex(
      visibleIndices: state.visibleIndices,
      selectedIndex: state.selectedIndex,
      contentLength: widget.content.length,
    );
    if (targetIndex == null) {
      return;
    }

    _pendingDisplayModeRestoreLineIndex = targetIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted ||
          _pendingDisplayModeRestoreLineIndex != targetIndex ||
          !_scrollController.isAttached) {
        return;
      }

      await scrollToSourceLine(
        scrollController: _scrollController,
        scrollOffsetController: state.scrollOffsetController,
        positionsListener: _positionsListener,
        segments: _readingSegments(settingsState),
        lineIndex: targetIndex,
        viewportExtent:
            context.size?.height ?? MediaQuery.sizeOf(context).height,
        duration: Duration.zero,
      );

      if (mounted && _pendingDisplayModeRestoreLineIndex == targetIndex) {
        _pendingDisplayModeRestoreLineIndex = null;
      }
    });
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

  bool _isContinuousReadingMode(SettingsState settingsState) {
    return widget.isMainText && settingsState.continuousReadingMode;
  }

  List<ReadingSegment> _readingSegments(SettingsState settingsState) {
    final continuous = _isContinuousReadingMode(settingsState);
    if (!identical(_cachedReadingSegmentContent, widget.content) ||
        _cachedReadingSegmentContinuous != continuous) {
      _cachedReadingSegmentContent = widget.content;
      _cachedReadingSegmentContinuous = continuous;
      _cachedReadingSegments = buildReadingSegments(
        widget.content,
        continuous: continuous,
      );
    }
    return _cachedReadingSegments;
  }

  int _segmentIndexForSourceLine(
    SettingsState settingsState,
    int lineIndex,
  ) {
    return segmentIndexForLine(_readingSegments(settingsState), lineIndex);
  }

  List<int> _sourceIndicesForVisiblePositions(
    SettingsState settingsState,
    Iterable<ItemPosition> itemPositions,
  ) {
    final positions = itemPositions.toList();
    if (!_isContinuousReadingMode(settingsState)) {
      return positions.map((position) => position.index).toSet().toList()
        ..sort();
    }
    return sourceLineIndicesForSegmentViewports(
      _readingSegments(settingsState),
      positions.map(
        (position) => ReadingSegmentViewport(
          segmentIndex: position.index,
          leadingEdge: position.itemLeadingEdge,
          trailingEdge: position.itemTrailingEdge,
        ),
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
    final settingsState = context.read<SettingsBloc>().state;
    final visiblePositions = _positionsListener.itemPositions.value.toList();

    if (visiblePositions.isNotEmpty) {
      return _sourceIndicesForVisiblePositions(
        settingsState,
        visiblePositions,
      );
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

    final settingsState = context.read<SettingsBloc>().state;
    final liveVisibleIndices = _sourceIndicesForVisiblePositions(
      settingsState,
      _positionsListener.itemPositions.value,
    );
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
          index: _segmentIndexForSourceLine(settingsState, nextIndex),
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
          index: _segmentIndexForSourceLine(settingsState, prevIndex),
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
          index: _segmentIndexForSourceLine(settingsState, nextIndex),
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
          index: _segmentIndexForSourceLine(settingsState, prevIndex),
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
          index: _segmentIndexForSourceLine(settingsState, 0),
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
          index: _segmentIndexForSourceLine(settingsState, lastIndex),
          duration: const Duration(milliseconds: 300),
        );
      }
      _requestKeyboardFocusAfterFrame('navigation-end');
      return true;
    }

    return false;
  }

  /// ╫¬╫ñ╫¿╫ש╫ר ╫פ╫º╫⌐╫¿
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
          label: '╫ñ╫¬╫ק ╫ק╫£╫ץ╫á╫ש╫¬ ╫º╫ש╫⌐╫ץ╫¿╫ש╫¥',
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
      // ╫פ╫ק╫ש╫ñ╫ץ╫⌐ ╫ó╫ץ╫ס╫ף ╫¬╫₧╫ש╫ף ╫ó╫£ ╫ר╫º╫í╫ר ╫£╫£╫נ ╫á╫ש╫º╫ץ╫ף ╫ץ╫ר╫ó╫₧╫ש╫¥ Γאפ ╫₧╫á╫º╫ש╫¥ ╫ñ╫ó╫¥ ╫נ╫ק╫¬
      // ╫£╫⌐╫ש╫₧╫ץ╫⌐ ╫ע╫¥ ╫ס╫¬╫ץ╫ץ╫ש╫¬ ╫פ╫¬╫ñ╫¿╫ש╫ר ╫ץ╫ע╫¥ ╫ס╫⌐╫נ╫ש╫£╫¬╫¬ ╫פ╫ק╫ש╫ñ╫ץ╫⌐ ╫ס╫ñ╫ץ╫ó╫£.
      final rawText = capturedText?.trim() ?? '';
      final cleanedText = utils.hasNikud(rawText)
          ? utils.removeVolwels(rawText).trim()
          : rawText;
      final hasSelectedText = cleanedText.isNotEmpty;
      final preview = hasSelectedText ? previewForLabel(cleanedText) : '';
      entries.add(AppContextMenuEntry(
        label: '╫ק╫ש╫ñ╫ץ╫⌐',
        icon: FluentIcons.search_24_regular,
        enabled: hasSelectedText,
        children: hasSelectedText
            ? [
                AppContextMenuEntry(
                  label: "╫ק╫ñ╫⌐ '$preview' ╫ס╫í╫ñ╫¿ ╫צ╫פ",
                  icon: FluentIcons.book_search_24_regular,
                  onTap: () {
                    if (widget.onOpenSearch != null) {
                      widget.onOpenSearch!(cleanedText);
                    } else {
                      UiSnack.show('╫ק╫ש╫ñ╫ץ╫⌐ ╫£╫נ ╫צ╫₧╫ש╫ƒ ╫ס╫¬╫ª╫ץ╫ע╫פ ╫צ╫ץ');
                    }
                  },
                ),
                AppContextMenuEntry(
                  label: "╫ק╫ñ╫⌐ '$preview' ╫ס╫¢╫£ ╫פ╫í╫ñ╫¿╫ש╫¥",
                  icon: FluentIcons.library_24_regular,
                  onTap: () => openGlobalSearch(
                    context,
                    cleanedText,
                    insertAdjacent: true,
                  ),
                ),
              ]
            : null,
      ));
    }

    if (commentatorItems.isNotEmpty) {
      if (entries.isNotEmpty) entries.add(const AppContextMenuEntry.divider());
      entries.addAll(commentatorItems);
    }

    if (hasLinkItems) {
      entries.add(const AppContextMenuEntry.divider());
      entries.add(AppContextMenuEntry(
        label: '╫º╫ש╫⌐╫ץ╫¿╫ש╫¥',
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
        label: '╫פ╫ץ╫í╫ú ╫פ╫ó╫¿╫פ ╫נ╫ש╫⌐╫ש╫¬ ',
        icon: FluentIcons.note_add_24_regular,
        onTap: () => _createNoteForCurrentLine(index, capturedText),
      ),
      AppContextMenuEntry(
        label: '╫ף╫ץ╫ץ╫ק ╫ó╫£ ╫ר╫ó╫ץ╫¬ ╫ס╫í╫ñ╫¿',
        icon: FluentIcons.error_circle_24_regular,
        onTap: () => _openErrorReportDialog(capturedText ?? ''),
      ),
      const AppContextMenuEntry.divider(),
      AppContextMenuEntry(
        label: '╫פ╫ó╫¬╫º',
        icon: FluentIcons.copy_24_regular,
        enabled: capturedText != null && capturedText.trim().isNotEmpty,
        onTap: () => _copyFormattedText(capturedText),
      ),
      AppContextMenuEntry(
        label: '╫פ╫ó╫¬╫º ╫נ╫¬ ╫¢╫£ ╫פ╫ñ╫í╫º╫פ',
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

  /// ╫ש╫ª╫ש╫¿╫¬ ╫פ╫ó╫¿╫פ ╫£╫⌐╫ץ╫¿╫פ ╫פ╫á╫ץ╫¢╫ק╫ש╫¬
  Future<void> _createNoteForCurrentLine(int index,
      [String? capturedText]) async {
    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded) return;

    final selectedText = capturedText ?? _savedSelectedText;
    final referenceText = selectedText?.trim().isNotEmpty == true
        ? utils.removeVolwels(selectedText!.trim())
        : widget.content[index];

    // ╫ר╫ó╫ƒ ╫ר╫ש╫ץ╫ר╫פ ╫נ╫¥ ╫º╫ש╫ש╫₧╫¬
    final draftService = PersonalNoteDraftService();
    final draft = await draftService.loadDraft(
      bookId: state.book.title,
      lineNumber: index + 1,
    );

    if (!mounted) return;

    // ╫⌐╫£╫ק event ╫£╫ñ╫¬╫ש╫ק╫¬ ╫₧╫ª╫ס ╫ש╫ª╫ש╫¿╫פ ╫ס╫í╫ש╫ש╫ף╫ס╫¿
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

  /// ╫ñ╫¬╫ש╫ק╫¬ ╫ף╫ש╫נ╫£╫ץ╫ע ╫ף╫ש╫ץ╫ץ╫ק ╫ó╫£ ╫ר╫ó╫ץ╫¬ ╫ס╫í╫ñ╫¿
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
  // /// ╫ó╫¿╫ש╫¢╫¬ ╫ñ╫í╫º╫פ
  // void _editParagraph(int index) {
  //   if (index >= 0 && index < widget.content.length) {
  //     context.read<TextBookBloc>().add(OpenEditor(index: index));
  //   }
  // }

  /// ╫פ╫ó╫¬╫º╫¬ ╫ñ╫í╫º╫פ ╫£╫ñ╫ש ╫נ╫ש╫á╫ף╫º╫í
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

  /// ╫ó╫ש╫ª╫ץ╫ס ╫ר╫º╫í╫ר ╫¢-HTML ╫ó╫¥ ╫פ╫ע╫ף╫¿╫ץ╫¬ ╫פ╫ע╫ץ╫ñ╫ƒ ╫פ╫á╫ץ╫¢╫ק╫ש╫ץ╫¬
  String _formatTextAsHtml(String text) {
    final settingsState = context.read<SettingsBloc>().state;
    return CopyUtils.buildStyledHtml(
      htmlText: text,
      fontFamily: widget.fontFamily ?? settingsState.fontFamily,
      fontSize: widget.fontSize,
    );
  }

  /// ╫פ╫ó╫¬╫º╫¬ ╫ר╫º╫í╫ר ╫₧╫ó╫ץ╫ª╫ס
  Future<void> _copyFormattedText([String? capturedText]) async {
    // ╫₧╫ñ╫¿╫⌐ ╫¢╫ס╫¿ ╫ר╫ש╫ñ╫£ ╫ס╫פ╫ó╫¬╫º╫פ - ╫£╫נ ╫á╫ף╫¿╫ץ╫í
    if (widget.isMainText && _commentaryCopyHandled) return;

    final plainText = capturedText ?? _savedSelectedText;

    if (plainText == null || plainText.trim().isEmpty) {
      UiSnack.show('╫נ╫á╫נ ╫ס╫ק╫¿ ╫ר╫º╫í╫ר ╫£╫פ╫ó╫¬╫º╫פ');
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
        UiSnack.showError('╫⌐╫ע╫ש╫נ╫פ ╫ס╫פ╫ó╫¬╫º╫פ ╫₧╫ó╫ץ╫ª╫ס╫¬: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ╫¢╫ץ╫¬╫¿╫¬ ╫נ╫ץ╫ñ╫ª╫ש╫ץ╫á╫£╫ש╫¬
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
        // ╫¬╫ץ╫¢╫ƒ
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
                  final settingsState = context.watch<SettingsBloc>().state;
                  final readingSegments = _readingSegments(settingsState);
                  final continuous = _isContinuousReadingMode(settingsState);
                  _preserveScrollAfterDisplayModeChange(
                    state: state,
                    settingsState: settingsState,
                    continuous: continuous,
                  );

                  return SelectionArea(
                    key: ValueKey(
                      '${widget.isMainText ? 'main' : 'commentary'}_selection_$_selectionRevision',
                    ),
                    // ╫ס╫ש╫ר╫ץ╫£ ╫¬╫ñ╫¿╫ש╫ר ╫ס╫¿╫ש╫¿╫¬ ╫פ╫₧╫ק╫ף╫£ ╫⌐╫£ Flutter - ╫á╫⌐╫¬╫₧╫⌐ ╫¿╫º ╫ס-ContextMenuRegion
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
                          // ╫ס╫ק╫ש╫¿╫פ ╫ס╫ץ╫ר╫£╫פ ╫£╫ק╫£╫ץ╫ר╫ש╫ƒ Γאפ ╫₧╫á╫º╫ש╫¥ ╫¢╫ף╫ש ╫£╫נ ╫£╫נ╫ñ╫⌐╫¿ ╫פ╫ó╫¬╫º╫פ "╫¿╫ñ╫נ╫ש╫¥"
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
                                  itemCount: readingSegments.length,
                                  padding: const EdgeInsets.all(4),
                                  itemBuilder: (context, index) => _buildLine(
                                    index,
                                    state,
                                    context,
                                    noteMap,
                                    readingSegments[index],
                                    continuous,
                                  ),
                                )
                              : ListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: readingSegments.length,
                                  padding: const EdgeInsets.all(4),
                                  itemBuilder: (context, index) => _buildLine(
                                    index,
                                    state,
                                    context,
                                    noteMap,
                                    readingSegments[index],
                                    continuous,
                                  ),
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
    ReadingSegment segment,
    bool continuous,
  ) {
    final primaryLineIndex = segment.startLineIndex;
    final isSelected = widget.isMainText &&
        state.selectedIndex != null &&
        segment.containsLine(state.selectedIndex!);
    final isHighlighted = widget.isMainText &&
        state.highlightedLine != null &&
        segment.containsLine(state.highlightedLine!);
    // ╫á╫¬╫ñ╫í ╫ס╫צ╫₧╫ƒ BUILD (╫¢╫₧╫ץ selectedText ╫ס-ValueListenableBuilder ╫⌐╫£ Combined),
    // ╫¢╫ת ╫⌐╫ע╫¥ ╫נ╫¥ onSelectionChanged(null) ╫ש╫¿╫ץ╫Ñ ╫£╫ñ╫á╫ש menuBuilder, ╫פ-closure
    // ╫¢╫ס╫¿ ╫í╫ע╫ץ╫¿ ╫ó╫£ ╫פ╫ó╫¿╫ת ╫פ╫á╫¢╫ץ╫ƒ ╫₧╫פ╫ס╫á╫ש╫ש╫פ ╫פ╫נ╫ק╫¿╫ץ╫á╫פ.
    final savedTextAtBuild = _savedSelectedText;

    // ╫ס╫ף╫ש╫º╫פ ╫ק╫ף╫⌐╫פ - ╫פ╫נ╫¥ ╫פ╫⌐╫ץ╫¿╫פ ╫₧╫ץ╫ף╫ע╫⌐╫¬ ╫¢╫ñ╫¿╫⌐╫ƒ ╫º╫⌐╫ץ╫¿ (╫₧╫º╫ץ╫₧╫ש)
    final isCommentaryHighlighted = !widget.isMainText &&
        (widget.highlightedIndices?.contains(index) ?? false);

    final theme = Theme.of(context);
    final backgroundColor = () {
      if (!continuous && isHighlighted) {
        return theme.colorScheme.secondaryContainer
            .withAlpha((0.4 * 255).round());
      }
      if (isCommentaryHighlighted || (!continuous && isSelected)) {
        // ╫ª╫ס╫ó ╫פ╫ף╫ע╫⌐╫פ ╫£╫₧╫ñ╫¿╫⌐ ╫º╫⌐╫ץ╫¿ - ╫¢╫₧╫ץ ╫פ╫⌐╫ץ╫¿╫פ ╫פ╫á╫ס╫ק╫¿╫¬
        return theme.colorScheme.primary.withAlpha((0.08 * 255).round());
      }
      return null;
    }();

    final notesForLine =
        noteMap[primaryLineIndex + 1] ?? const <PersonalNote>[];

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: widget.isMainText && !(continuous && !segment.isHeader)
          ? () {
              _requestKeyboardFocus('line-tap-$primaryLineIndex');
              // ╫נ╫ש╫ñ╫ץ╫í ╫פ╫ר╫º╫í╫ר ╫פ╫⌐╫₧╫ץ╫¿
              setState(() {
                _savedSelectedText = null;
                _savedSelectedIndex = null;
              });
              // ╫ó╫ף╫¢╫ץ╫ƒ selectedIndex ╫¿╫º ╫ס╫ר╫º╫í╫ר ╫פ╫₧╫¿╫¢╫צ╫ש
              if (isSelected) {
                context
                    .read<TextBookBloc>()
                    .add(const UpdateSelectedIndex(null));
              } else {
                context
                    .read<TextBookBloc>()
                    .add(UpdateSelectedIndex(primaryLineIndex));
              }
            }
          : null,
      onDoubleTap: !widget.isMainText && widget.bookTitle != null
          ? () {
              // ╫£╫ק╫ש╫ª╫פ ╫¢╫ñ╫ץ╫£╫פ ╫ס╫₧╫ñ╫¿╫⌐ - ╫ñ╫¬╫ש╫ק╫פ ╫ס╫ר╫נ╫ס ╫á╫ñ╫¿╫ף
              widget.openBookCallback(TextBookTab(
                book: TextBook(title: widget.bookTitle!),
                index: primaryLineIndex,
                openLeftPane:
                    (Settings.getValue<bool>('key-pin-sidebar') ?? false) ||
                        (Settings.getValue<bool>('key-default-sidebar-open') ??
                            false),
              ));
            }
          : null,
      onSecondaryTapDown: (details) {
        // ╫⌐╫₧╫ש╫¿╫¬ ╫פ╫נ╫ש╫á╫ף╫º╫í ╫£╫⌐╫ש╫₧╫ץ╫⌐ ╫ס╫¬╫ñ╫¿╫ש╫ר ╫פ╫פ╫º╫⌐╫¿
        setState(() {
          _savedSelectedIndex = primaryLineIndex;
        });
      },
      child: AppContextMenuRegion(
        menuBuilder: (menuCtx, tapPos) {
          final contextMenuIndex = continuous && !segment.isHeader
              ? _savedSelectedIndex
              : primaryLineIndex;
          return _buildContextMenu(
            state,
            contextMenuIndex != null && segment.containsLine(contextMenuIndex)
                ? contextMenuIndex
                : primaryLineIndex,
            menuCtx,
            tapPos,
            savedTextAtBuild,
          );
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          decoration: backgroundColor != null
              ? BoxDecoration(color: backgroundColor)
              : null,
          padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
          child: BlocBuilder<SettingsBloc, SettingsState>(
            builder: (context, settingsState) {
              if (continuous && !segment.isHeader) {
                return _buildContinuousSegmentContent(
                  segment: segment,
                  state: state,
                  settingsState: settingsState,
                );
              }

              final data = widget.content[primaryLineIndex];
              final targetTitle =
                  widget.isMainText ? state.book.title : widget.bookTitle;
              // ╫נ╫¥ ╫פ╫₧╫⌐╫¬╫₧╫⌐ ╫£╫ק╫Ñ ╫ó╫£ ╫¢╫ñ╫¬╫ץ╫¿ ╫á╫ש╫º╫ץ╫ף (override), ╫á╫⌐╫¬╫₧╫⌐ ╫ס╫ó╫¿╫ת ╫₧╫פ-state
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

              // ╫פ╫ף╫ע╫⌐╫פ ╫₧╫₧╫ץ╫º╫ף╫¬ ╫₧╫º╫ש╫⌐╫ץ╫¿ ╫ó╫ץ╫₧╫º (╫¿╫º ╫ס╫ר╫º╫í╫ר ╫פ╫₧╫¿╫¢╫צ╫ש, ╫¿╫º ╫ó╫£ ╫פ╫í╫ó╫ש╫ú ╫⌐╫ª╫ץ╫ש╫ƒ)
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
                    widgetKey: ValueKey('html_simple_text_$primaryLineIndex'),
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
                            .add(UpdateSelectedIndex(primaryLineIndex));
                        context
                            .read<TextBookBloc>()
                            .add(HighlightLine(primaryLineIndex));
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
                          title: '╫פ╫ó╫¿╫פ ╫£╫⌐╫ץ╫¿╫פ ╫צ╫ץ',
                          customContent: PersonalNoteContentView(note: note),
                          confirmText: '╫í╫ע╫ץ╫¿',
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

  Widget _buildContinuousSegmentContent({
    required ReadingSegment segment,
    required TextBookLoaded state,
    required SettingsState settingsState,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final baseStyle = TextStyle(
      fontSize: widget.fontSize,
      fontFamily: widget.fontFamily ?? settingsState.fontFamily,
      height: settingsState.lineHeight,
      color: colorScheme.onSurface,
    );
    final paragraphLines = _buildContinuousParagraphLines(
      segment: segment,
      state: state,
      settingsState: settingsState,
      baseTextStyle: baseStyle,
    );

    return ContinuousReadingParagraph(
      lines: paragraphLines,
      baseStyle: baseStyle,
      onTapUrl: (url) => HtmlLinkHandler.handleLink(
        context,
        url,
        (tab) => widget.openBookCallback(tab),
      ),
      onLineTap: (lineIndex) {
        final isLineSelected = state.selectedIndex == lineIndex;
        _requestKeyboardFocus('line-tap-$lineIndex');
        setState(() {
          _savedSelectedText = null;
          _savedSelectedIndex = lineIndex;
        });
        if (isLineSelected) {
          context.read<TextBookBloc>().add(const UpdateSelectedIndex(null));
        } else {
          context.read<TextBookBloc>().add(UpdateSelectedIndex(lineIndex));
        }
      },
      onLineSecondaryTap: (lineIndex) {
        setState(() {
          _savedSelectedIndex = lineIndex;
        });
      },
    );
  }

  List<ContinuousReadingParagraphLine> _buildContinuousParagraphLines({
    required ReadingSegment segment,
    required TextBookLoaded state,
    required SettingsState settingsState,
    required TextStyle baseTextStyle,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final lines = <ContinuousReadingParagraphLine>[];
    for (final lineIndex in segment.sourceLineIndices) {
      if (lineIndex < 0 || lineIndex >= widget.content.length) {
        continue;
      }
      final backgroundColor = state.highlightedLine == lineIndex
          ? colorScheme.secondaryContainer.withAlpha((0.4 * 255).round())
          : state.selectedIndex == lineIndex
              ? colorScheme.primary.withAlpha((0.08 * 255).round())
              : null;
      final style = backgroundColor == null
          ? baseTextStyle
          : baseTextStyle.copyWith(backgroundColor: backgroundColor);
      final htmlText = _continuousLineHtml(
        widget.content[lineIndex],
        lineIndex: lineIndex,
        state: state,
        settingsState: settingsState,
      );

      lines.add(
        ContinuousReadingParagraphLine(
          lineIndex: lineIndex,
          text: utils.stripHtmlIfNeeded(htmlText).trim(),
          htmlText: htmlText,
          style: style,
        ),
      );
    }

    return lines;
  }

  String _continuousLineHtml(
    String rawText, {
    required int lineIndex,
    required TextBookLoaded state,
    required SettingsState settingsState,
  }) {
    final isPinpointTarget = widget.isMainText &&
        state.pinpointHighlightIndex == lineIndex &&
        state.pinpointHighlightText != null &&
        state.pinpointHighlightText!.isNotEmpty;
    final hasPinpoint =
        widget.isMainText && state.pinpointHighlightIndex != null;
    final searchText = isPinpointTarget
        ? state.pinpointHighlightText!
        : (hasPinpoint ? '' : (widget.isMainText ? state.searchText : ''));
    final useStateSearchSettings = widget.isMainText && !hasPinpoint;
    final effectiveSearchMode =
        useStateSearchSettings ? state.searchMode : SearchMode.exact;

    return TextRendererService.processText(
      rawText.trim(),
      RenderSettings(
        removeNikud: state.removeNikud,
        removePunctuation: state.removePunctuation,
        removeTeamim: !settingsState.showTeamim,
        replaceHolyNames: settingsState.replaceHolyNames,
        searchText: searchText,
        searchOptions: useStateSearchSettings ? state.searchOptions : const {},
        alternativeWords:
            useStateSearchSettings ? state.alternativeWords : const {},
        spacingValues: useStateSearchSettings ? state.spacingValues : const {},
        isFuzzySearch: effectiveSearchMode == SearchMode.fuzzy,
        searchMode: effectiveSearchMode,
        searchDistance: useStateSearchSettings ? state.searchDistance : 0,
        fontSize: widget.fontSize,
        fontFamily: widget.fontFamily ?? settingsState.fontFamily,
        lineHeight: settingsState.lineHeight,
      ),
    );
  }

  /// ╫ס╫á╫ש╫ש╫¬ ╫¬╫ñ╫¿╫ש╫ר ╫פ╫ק╫£╫ñ╫¬ ╫₧╫ñ╫¿╫⌐
  List<AppContextMenuEntry> _buildCommentatorSwitchMenu(TextBookLoaded state) {
    final availableCommentators = state.availableCommentators;
    if (availableCommentators.isEmpty) return [];

    final groups = state.commentatorGroups;
    final tanachGroup = CommentatorGroup.groupByTitle(groups, '╫¬╫ץ╫¿╫פ ╫⌐╫ס╫¢╫¬╫ס');
    final chazalGroup = CommentatorGroup.groupByTitle(groups, '╫ק╫צ"╫£');
    final rishonimGroup = CommentatorGroup.groupByTitle(groups, '╫¿╫נ╫⌐╫ץ╫á╫ש╫¥');
    final acharonimGroup = CommentatorGroup.groupByTitle(groups, '╫נ╫ק╫¿╫ץ╫á╫ש╫¥');
    final modernGroup = CommentatorGroup.groupByTitle(groups, '╫₧╫ק╫ס╫¿╫ש ╫צ╫₧╫á╫á╫ץ');
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
        label: '╫פ╫ק╫£╫ú ╫₧╫ñ╫¿╫⌐',
        icon: FluentIcons.arrow_swap_24_regular,
        children: normalized,
      ),
    ];
  }

  /// ╫פ╫ק╫£╫ñ╫¬ ╫₧╫ñ╫¿╫⌐
  void _switchCommentator(String newCommentator, TextBookLoaded state) {
    if (newCommentator == widget.bookTitle) {
      return; // ╫¢╫ס╫¿ ╫₧╫ץ╫ª╫ע ╫₧╫ñ╫¿╫⌐ ╫צ╫פ
    }

    // ╫ª╫¿╫ש╫ת ╫£╫₧╫ª╫ץ╫נ ╫ס╫נ╫ש╫צ╫פ ╫ר╫ץ╫¿ ╫פ╫₧╫ñ╫¿╫⌐ ╫פ╫á╫ץ╫¢╫ק╫ש ╫₧╫ץ╫ª╫ע ╫ץ╫£╫פ╫ק╫£╫ש╫ú ╫נ╫ץ╫¬╫ץ
    final config = PageShapeSettingsManager.loadConfiguration(
      state.book.title,
      heCategories: state.book.heCategories,
    );

    if (config == null) return;

    // ╫₧╫ª╫ש╫נ╫¬ ╫פ╫ר╫ץ╫¿ ╫⌐╫ס╫ץ ╫פ╫₧╫ñ╫¿╫⌐ ╫פ╫á╫ץ╫¢╫ק╫ש ╫₧╫ץ╫ª╫ע
    String? columnToUpdate;
    String? matchedSelection;
    for (final entry in config.entries) {
      if (entry.value == null) continue;

      // ╫ס╫ף╫ש╫º╫פ ╫נ╫¥ ╫פ╫₧╫ñ╫¿╫⌐ ╫פ╫á╫ץ╫¢╫ק╫ש ╫¬╫ץ╫נ╫¥ ╫£╫ó╫¿╫ת ╫ס╫פ╫ע╫ף╫¿╫פ
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
          'Γתá∩╕ן PageShape: Could not find column for commentator "${widget.bookTitle}"');
      return;
    }

    // ╫ó╫ף╫¢╫ץ╫ƒ ╫פ╫פ╫ע╫ף╫¿╫פ
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

    // ╫ס╫ף╫ש╫º╫פ ╫נ╫¥ ╫ש╫⌐ ╫פ╫ע╫ף╫¿╫פ ╫í╫ñ╫ª╫ש╫ñ╫ש╫¬ ╫£╫í╫ñ╫¿ (╫£╫נ ╫¿╫º ╫פ╫ף╫ע╫£, ╫נ╫£╫נ ╫פ╫ע╫ף╫¿╫פ ╫₧╫₧╫⌐╫ש╫¬)
    final hasActualBookConfig =
        PageShapeSettingsManager.loadConfiguration(state.book.title) != null;

    // ╫נ╫¥ ╫ש╫⌐ ╫פ╫ע╫ף╫¿╫פ ╫í╫ñ╫ª╫ש╫ñ╫ש╫¬ ╫£╫í╫ñ╫¿ - ╫⌐╫ץ╫₧╫¿╫ש╫¥ ╫£╫í╫ñ╫¿
    // ╫נ╫ק╫¿╫¬ - ╫⌐╫ץ╫₧╫¿╫ש╫¥ ╫£╫º╫ר╫ע╫ץ╫¿╫ש╫פ (╫נ╫¥ ╫ש╫⌐)
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

    // ╫º╫¿╫ש╫נ╫פ ╫£-callback ╫£╫¿╫ó╫á╫ץ╫ƒ ╫פ╫₧╫í╫ת
    widget.onCommentatorChanged?.call();
  }
}

class _CopyTextIntent extends Intent {
  const _CopyTextIntent();
}
