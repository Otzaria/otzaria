import 'dart:async';

import 'package:flutter/material.dart';
import 'package:otzaria/text_book/utils/visible_index.dart';

import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/models/commentator_group.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/view/commentary_list_base.dart';
import 'package:otzaria/widgets/misc/progressive_scrolling.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/personal_notes/personal_notes_system.dart';
import 'package:otzaria/utils/text/copy_utils.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:otzaria/utils/text/global_search_helper.dart';
import 'package:otzaria/utils/text/html_link_handler.dart';
import 'package:otzaria/utils/text/text_with_inline_links.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/widgets/feedback/scrollable_positioned_list_scrollbar.dart';
import 'package:otzaria/widgets/smart_text/smart_text.dart';
import 'package:otzaria/text_book/view/selection/text_selection_manager.dart';
import 'package:otzaria/text_book/view/selection/selection_sync_controller.dart';
import 'package:otzaria/text_book/view/selection/enhanced_gesture_detector.dart';
import 'package:otzaria/text_book/view/selection/selection_persistence.dart';
import 'package:otzaria/text_book/view/selection/selected_text_copy.dart';
import 'package:otzaria/text_book/view/selection/selected_text_restore.dart';
import 'package:otzaria/text_book/view/error_report_dialog.dart';
import 'package:otzaria/tools/dictionary/dictionary_context_menu_entries.dart';
import 'package:otzaria/tools/dictionary/repository/dictionary_lookup_repository.dart';
import 'package:otzaria/utils/text/word_at_position.dart';
import 'package:otzaria/plugins/services/context_menu_registry.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/utils/fluent_icon_resolver.dart';
import 'package:otzaria/text_book/utils/reading_segment_navigation.dart';
import 'package:otzaria/text_book/utils/reading_segments.dart';
import 'package:otzaria/text_book/view/widgets/continuous_reading_paragraph.dart';

class CombinedView extends StatefulWidget {
  const CombinedView({
    super.key,
    required this.data,
    required this.openBookCallback,
    required this.openLeftPaneTab,
    required this.textSize,
    required this.showCommentaryAsExpansionTiles,
    required this.tab,
    this.onSelectedTextChanged,
    this.isPreviewMode = false,
    this.onOpenPersonalNotes,
    this.onOpenCommentatorsPane,
    this.onOpenCommentatorsPaneWithFilter,
    this.onOpenLinksPane,
    this.isCommentatorsTabActive,
    this.isLinksTabActive,
    this.selectionSyncController,
  });

  final List<String> data;
  final Function(OpenedTab) openBookCallback;
  final void Function(int, {String? searchText}) openLeftPaneTab;
  final double textSize;
  final bool showCommentaryAsExpansionTiles;
  final TextBookTab tab;
  final ValueChanged<String?>? onSelectedTextChanged;
  final bool isPreviewMode;
  final VoidCallback? onOpenPersonalNotes;
  final VoidCallback? onOpenCommentatorsPane;
  final VoidCallback? onOpenCommentatorsPaneWithFilter;
  final VoidCallback? onOpenLinksPane;
  final bool Function()? isCommentatorsTabActive;
  final bool Function()? isLinksTabActive;
  final SelectionSyncController? selectionSyncController;

  @override
  State<CombinedView> createState() => _CombinedViewState();
}

@visibleForTesting
List<Link> buildCombinedViewContextMenuLinksForParagraph({
  required Map<int, List<Link>> linksByLine,
  required int paragraphIndex,
}) {
  final lineLinks = linksByLine[paragraphIndex + 1] ?? const <Link>[];
  final visibleLinks = lineLinks.where((link) {
    return !LinkTypes.isCommentaryOrTargum(link.connectionType) &&
        link.start == null &&
        link.end == null;
  }).toList();

  final titles = <Link, String>{};
  final pathCache = <String, String>{};
  for (final link in visibleLinks) {
    titles[link] = pathCache.putIfAbsent(
      link.path2,
      () => utils.getTitleFromPath(link.path2),
    );
  }
  visibleLinks.sort((a, b) => titles[a]!.compareTo(titles[b]!));

  return visibleLinks;
}

@visibleForTesting
bool shouldShowOpenCommentatorsPaneEntry({
  required bool hasSelectedCommentators,
  required bool showCommentaryAsExpansionTiles,
  required bool isCommentatorsTabActive,
}) {
  return hasSelectedCommentators &&
      !showCommentaryAsExpansionTiles &&
      !isCommentatorsTabActive;
}

@visibleForTesting
bool shouldShowOpenLinksPaneEntry({
  required bool hasLinks,
  required bool isLinksTabActive,
}) {
  return hasLinks && !isLinksTabActive;
}

/// ╫ñ╫¿╫ש╫ר "╫ס╫ק╫¿ ╫₧╫ñ╫¿╫⌐╫ש╫¥ ╫₧╫¿╫ץ╫ס╫ש╫¥" ╫ש╫ץ╫ª╫ע ╫¢╫⌐╫ש╫⌐ callback `onOpenCommentatorsPaneWithFilter`
/// ╫ץ╫ר╫נ╫ס ╫פ╫₧╫ñ╫¿╫⌐╫ש╫¥ ╫נ╫ש╫á╫ץ ╫ñ╫ó╫ש╫£ ╫ס╫ק╫£╫ץ╫á╫ש╫¬ ╫פ╫ª╫ף. ╫פ╫¢╫£╫£ ╫צ╫פ╫פ ╫ע╫¥ ╫ס╫₧╫ª╫ס "╫₧╫ñ╫¿╫⌐╫ש╫¥ ╫₧╫¬╫ק╫¬":
/// ╫נ╫¥ ╫פ╫₧╫⌐╫¬╫₧╫⌐ ╫¢╫ס╫¿ ╫ñ╫¬╫ק ╫נ╫¬ ╫ק╫£╫ץ╫á╫ש╫¬ ╫פ╫ª╫ף ╫ó╫£ ╫פ╫₧╫ñ╫¿╫⌐╫ש╫¥, ╫נ╫ש╫ƒ ╫ª╫ץ╫¿╫ת ╫ס╫ñ╫¿╫ש╫ר.
///
/// ╫ס╫á╫ש╫ע╫ץ╫ף ╫£-[shouldShowOpenCommentatorsPaneEntry], ╫פ╫ñ╫¿╫ש╫ר ╫פ╫צ╫פ ╫£╫נ ╫¬╫£╫ץ╫ש
/// ╫ס-`hasSelectedCommentators` Γאפ ╫₧╫ר╫¿╫¬╫ץ ╫£╫נ╫ñ╫⌐╫¿ ╫ס╫ק╫ש╫¿╫פ ╫ע╫¥ ╫¢╫⌐╫פ╫ס╫ק╫ש╫¿╫פ ╫¿╫ש╫º╫פ.
@visibleForTesting
bool shouldShowSelectCommentatorsEntry({
  required bool hasOpenCommentatorsPaneWithFilterCallback,
  required bool isCommentatorsTabActive,
}) {
  return hasOpenCommentatorsPaneWithFilterCallback && !isCommentatorsTabActive;
}

/// ╫º╫ץ╫ס╫ó ╫פ╫נ╫¥ ╫ª╫¿╫ש╫ת ╫£╫ס╫á╫ץ╫¬ ╫₧╫ק╫ף╫⌐ ╫נ╫¬ ╫פ-SelectionArea ╫פ╫ק╫ש╫ª╫ץ╫á╫ש ╫ס╫¬╫ע╫ץ╫ס╫פ ╫£╫⌐╫ש╫á╫ץ╫ש ╫ס╫ó╫£╫ץ╫¬
/// ╫ס-[SelectionSyncController]. ╫פ╫ס╫á╫ש╫ש╫פ ╫₧╫ק╫ף╫⌐ ╫₧╫¬╫ס╫ª╫ó╫¬ ╫ó╫£-╫ש╫ף╫ש ╫º╫ש╫ף╫ץ╫¥ ╫ó╫¿╫ת
/// `_selectionAreaRevision` ╫⌐╫⌐╫ש╫₧╫⌐ ╫¢-`ValueKey` ╫⌐╫£ ╫פ-SelectionArea Γאפ ╫ץ╫£╫¢╫ƒ
/// ╫פ╫ש╫נ ╫₧╫⌐╫ק╫צ╫¿╫¬ ╫נ╫¬ ╫¢╫£ ╫ó╫Ñ ╫פ╫ª╫נ╫ª╫נ╫ש╫¥, ╫¢╫ץ╫£╫£ `_CommentaryCard` ╫ס╫₧╫ª╫ס '╫₧╫ñ╫¿╫⌐╫ש╫¥ ╫₧╫¬╫ק╫¬'.
///
/// ╫₧╫ר╫¿╫¬ ╫פ╫ס╫á╫ש╫ש╫פ ╫פ╫ש╫נ ╫£╫á╫º╫ץ╫¬ ╫ס╫ק╫ש╫¿╫פ ╫ץ╫ש╫צ╫ץ╫נ╫£╫ש╫¬ ╫⌐╫£ ╫פ-SelectionArea ╫⌐╫£╫á╫ץ ╫¢╫⌐╫נ╫צ╫ץ╫¿ ╫נ╫ק╫¿
/// ╫¬╫ñ╫í ╫ס╫ó╫£╫ץ╫¬. ╫נ╫¥ ╫נ╫ש╫ƒ ╫£╫á╫ץ ╫ס╫ק╫ש╫¿╫פ ╫₧╫⌐╫£╫á╫ץ Γאפ ╫נ╫ש╫ƒ ╫₧╫פ ╫£╫á╫º╫ץ╫¬, ╫ץ-rebuild ╫¿╫º ╫ש╫פ╫¿╫ץ╫í
/// ╫נ╫¬ ╫ó╫Ñ ╫פ╫ª╫נ╫ª╫נ╫ש╫¥ (╫ס╫₧╫ª╫ס '╫₧╫ñ╫¿╫⌐╫ש╫¥ ╫₧╫¬╫ק╫¬' ╫צ╫פ ╫ע╫ץ╫¿╫¥ ╫£╫ר╫ó╫ש╫á╫פ ╫₧╫ק╫ף╫⌐ ╫⌐╫£ ╫פ╫₧╫ñ╫¿╫⌐╫ש╫¥ ╫ס╫¢╫£
/// ╫ñ╫ó╫¥ ╫⌐╫₧╫á╫í╫ש╫¥ ╫£╫í╫₧╫ƒ ╫ס╫פ╫¥ ╫ר╫º╫í╫ר).
@visibleForTesting
bool shouldRebuildSelectionAreaOnExternalChange({
  required Object? activeOwner,
  required Object selfOwner,
  required bool hasOwnSelection,
}) {
  if (activeOwner == null) return false;
  if (identical(activeOwner, selfOwner)) return false;
  return hasOwnSelection;
}

class _CombinedViewState extends State<CombinedView> {
  // ╫⌐╫₧╫ש╫¿╫¬ ╫פ╫ר╫º╫í╫ר ╫פ╫á╫ס╫ק╫¿ ╫פ╫נ╫ק╫¿╫ץ╫ƒ
  final ValueNotifier<String?> _savedSelectedText =
      ValueNotifier<String?>(null);
  // ╫⌐╫₧╫ש╫¿╫¬ ╫פ╫נ╫ש╫á╫ף╫º╫í ╫⌐╫£ ╫פ╫⌐╫ץ╫¿╫פ ╫⌐╫₧╫₧╫á╫פ ╫פ╫ר╫º╫í╫ר ╫פ╫ץ╫ף╫ע╫⌐
  final ValueNotifier<int?> _savedSelectedIndex = ValueNotifier<int?>(null);
  // ╫⌐╫₧╫ש╫¿╫¬ reference ╫£-BLoC ╫£╫⌐╫ש╫₧╫ץ╫⌐ ╫ס-listeners
  late final TextBookBloc _textBookBloc;

  bool _hasScrolledToInitialPosition = false;

  // ╫₧╫á╫פ╫£ ╫ס╫ק╫ש╫¿╫¬ ╫ר╫º╫í╫ר ╫₧╫⌐╫ץ╫ñ╫¿
  late final TextSelectionManager _selectionManager;

  int _selectionAreaRevision = 0;
  final Object _selectionOwner = Object();

  // listener ╫£╫á╫ש╫º╫ץ╫ש ╫ס╫ק╫ש╫¿╫פ - ╫á╫⌐╫₧╫ץ╫¿ ╫נ╫ץ╫¬╫ץ ╫¢╫ף╫ש ╫£╫פ╫í╫ש╫¿ ╫נ╫ץ╫¬╫ץ ╫ס-dispose
  void _onSelectionModeChanged() {
    if (!_selectionManager.isInSelectionMode && mounted) {
      // ╫¢╫⌐╫ש╫ץ╫ª╫נ╫ש╫¥ ╫₧╫₧╫ª╫ס ╫ס╫ק╫ש╫¿╫פ, ╫º╫ץ╫¿╫נ╫ש╫¥ ╫£-setState ╫¢╫ף╫ש ╫£╫¢╫ñ╫ץ╫¬ ╫ס╫á╫ש╫ש╫פ ╫₧╫ק╫ף╫⌐
      // ╫⌐╫£ SelectionArea ╫ץ╫£╫á╫º╫ץ╫¬ ╫נ╫¬ ╫פ╫ס╫ק╫ש╫¿╫פ ╫ס╫נ╫ץ╫ñ╫ƒ ╫ץ╫ש╫צ╫ץ╫נ╫£╫ש.
      setState(() {});
    }
  }

  /// ╫ñ╫¬╫ש╫ק╫¬ ╫ק╫£╫ץ╫ƒ ╫פ╫ª╫ף ╫⌐╫£ ╫פ╫₧╫ñ╫¿╫⌐╫ש╫¥ ╫¿╫º ╫נ╫¥ ╫₧╫ץ╫í╫ש╫ñ╫ש╫¥ ╫₧╫ñ╫¿╫⌐╫ש╫¥ ╫ץ╫₧╫ñ╫¿╫⌐╫ש╫¥ ╫₧╫ץ╫ע╫ף╫¿╫ש╫¥ ╫ס╫ª╫ף ╫פ╫ר╫º╫í╫ר (╫£╫נ ╫₧╫¬╫ק╫¬)
  void _openCommentatorsPane({required bool isAdding}) {
    if (isAdding &&
        !widget.showCommentaryAsExpansionTiles &&
        widget.onOpenCommentatorsPane != null) {
      widget.onOpenCommentatorsPane!();
    }
  }

  late final FocusNode _focusNode;

  bool _didRequestInitialFocus = false;

  // ╫⌐╫₧╫ש╫¿╫¬ ╫ע╫ץ╫ס╫פ ╫פ╫ס╫£╫ץ╫º ╫ס╫ñ╫ץ╫ó╫£ ╫£╫ק╫ש╫⌐╫ץ╫ס╫ש╫¥ ╫ף╫ש╫á╫נ╫₧╫ש╫ש╫¥
  double _viewportHeight = 0;
  List<String>? _cachedReadingSegmentContent;
  bool? _cachedReadingSegmentContinuous;
  List<ReadingSegment> _cachedReadingSegments = const [];

  ScrollController? _previewScrollController;
  final DictionaryLookupRepository _dictionaryLookupRepository =
      DictionaryLookupRepository.instance;

  @override
  void initState() {
    super.initState();
    if (widget.isPreviewMode) {
      _previewScrollController = ScrollController();
    }
    _focusNode = FocusNode();
    // ╫⌐╫₧╫ש╫¿╫¬ ╫פ-BLoC ╫₧╫¿╫נ╫⌐
    _textBookBloc = context.read<TextBookBloc>();

    // ╫נ╫¬╫ק╫ץ╫£ ╫₧╫á╫פ╫£ ╫פ╫ס╫ק╫ש╫¿╫פ
    _selectionManager = TextSelectionManager();

    // ╫פ╫נ╫צ╫á╫פ ╫£╫⌐╫ש╫á╫ץ╫ש╫ש╫¥ ╫ס╫₧╫ª╫ס ╫פ╫ס╫ק╫ש╫¿╫פ ╫¢╫ף╫ש ╫£╫¢╫ñ╫ץ╫¬ rebuild ╫⌐╫£ SelectionArea
    _selectionManager.addListener(_onSelectionModeChanged);
    widget.selectionSyncController?.addListener(_handleExternalSelectionChange);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context
          .read<PersonalNotesBloc>()
          .add(LoadPersonalNotes(widget.tab.book.title));
    });

    // ╫פ╫נ╫צ╫á╫פ ╫£╫⌐╫ש╫á╫ץ╫ש╫ש╫¥ ╫ס╫₧╫ש╫º╫ץ╫₧╫ש ╫פ╫ñ╫¿╫ש╫ר╫ש╫¥ ╫¢╫ף╫ש ╫£╫נ╫ñ╫í ╫נ╫¬ ╫פ╫ס╫ק╫ש╫¿╫פ ╫ס╫ע╫£╫ש╫£╫פ
    widget.tab.positionsListener.itemPositions.addListener(_onScroll);
    // ╫ó╫ף╫¢╫ץ╫ƒ ╫פ╫נ╫ש╫á╫ף╫º╫í ╫ס-tab ╫ס╫צ╫₧╫ƒ ╫נ╫₧╫¬
    widget.tab.positionsListener.itemPositions.addListener(_updateTabIndex);

    // ╫פ╫נ╫צ╫á╫פ ╫£╫⌐╫ש╫á╫ץ╫ש╫ש╫¥ ╫ס-state ╫¢╫ף╫ש ╫£╫ע╫£╫ץ╫£ ╫£╫₧╫ש╫º╫ץ╫¥ ╫פ╫á╫¢╫ץ╫ƒ ╫ס╫ñ╫ó╫¥ ╫פ╫¿╫נ╫⌐╫ץ╫á╫פ
    _textBookBloc.stream.listen((state) {
      if (state is TextBookLoaded &&
          !_hasScrolledToInitialPosition &&
          state.visibleIndices.isNotEmpty) {
        _hasScrolledToInitialPosition = true;
        final initialIndex = state.visibleIndices.first;
        debugPrint('DEBUG: ╫ע╫£╫ש╫£╫פ ╫נ╫ץ╫ר╫ץ╫₧╫ר╫ש╫¬ ╫£╫₧╫ש╫º╫ץ╫¥ ╫⌐╫₧╫ץ╫¿: $initialIndex');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && widget.tab.scrollController.isAttached) {
            unawaited(_scrollToSourceLine(initialIndex));
          }
        });
      }
    });

    // ╫₧╫ץ╫ץ╫ף╫נ ╫⌐╫פ╫ñ╫ץ╫º╫ץ╫í ╫₧╫ע╫ש╫ó ╫£╫נ╫צ╫ץ╫¿ ╫פ╫º╫¿╫ש╫נ╫פ ╫₧╫ש╫ף ╫נ╫ק╫¿╫ש ╫ñ╫¬╫ש╫ק╫¬ ╫í╫ñ╫¿
    // ╫¢╫ף╫ש ╫⌐╫ע╫£╫ש╫£╫פ ╫ס╫ק╫ש╫ª╫ש╫¥ ╫¬╫ó╫ס╫ץ╫ף ╫ס╫£╫ש ╫£╫ק╫ש╫ª╫פ ╫ס╫ó╫¢╫ס╫¿, ╫נ╫ת ╫ס╫£╫ש ╫£╫ע╫á╫ץ╫ס ╫ñ╫ץ╫º╫ץ╫í ╫₧╫⌐╫ף╫ץ╫¬ ╫ר╫º╫í╫ר.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _didRequestInitialFocus) return;
      _didRequestInitialFocus = true;

      final primaryFocus = FocusManager.instance.primaryFocus;
      final focusContext = primaryFocus?.context;
      final isTextInputFocused = focusContext?.widget is EditableText ||
          focusContext?.findAncestorWidgetOfExactType<EditableText>() != null;

      if (!isTextInputFocused && !_focusNode.hasFocus) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void didUpdateWidget(covariant CombinedView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectionSyncController != widget.selectionSyncController) {
      oldWidget.selectionSyncController
          ?.removeListener(_handleExternalSelectionChange);
      widget.selectionSyncController
          ?.addListener(_handleExternalSelectionChange);
    }
    if (oldWidget.tab.book.title != widget.tab.book.title) {
      context
          .read<PersonalNotesBloc>()
          .add(LoadPersonalNotes(widget.tab.book.title));
    }
  }

  @override
  void dispose() {
    _previewScrollController?.dispose();
    widget.tab.positionsListener.itemPositions.removeListener(_onScroll);
    widget.tab.positionsListener.itemPositions.removeListener(_updateTabIndex);
    _savedSelectedText.dispose();
    _savedSelectedIndex.dispose();
    _currentSelectedIndex.dispose();
    _focusNode.dispose();
    widget.selectionSyncController
        ?.removeListener(_handleExternalSelectionChange);
    _selectionManager.removeListener(_onSelectionModeChanged);
    _selectionManager.dispose();
    super.dispose();
  }

  void _handleExternalSelectionChange() {
    final controller = widget.selectionSyncController;
    if (controller == null || !mounted) {
      return;
    }

    final shouldRebuild = shouldRebuildSelectionAreaOnExternalChange(
      activeOwner: controller.activeOwner,
      selfOwner: _selectionOwner,
      hasOwnSelection: _savedSelectedText.value != null ||
          _selectionManager.isInSelectionMode,
    );
    if (!shouldRebuild) {
      return;
    }

    _selectionManager.exitSelectionMode();
    setState(() {
      _selectionAreaRevision = controller.revision;
      _savedSelectedText.value = null;
      _savedSelectedIndex.value = null;
      _currentSelectedIndex.value = null;
    });
    widget.onSelectedTextChanged?.call(null);
  }

  // ╫ó╫ף╫¢╫ץ╫ƒ ╫פ╫נ╫ש╫á╫ף╫º╫í ╫פ╫á╫ץ╫¢╫ק╫ש ╫ס-tab
  void _updateTabIndex() {
    final positions = widget.tab.positionsListener.itemPositions.value;
    if (positions.isNotEmpty) {
      // ╫⌐╫ץ╫₧╫¿ ╫נ╫¬ ╫פ╫נ╫ש╫á╫ף╫º╫í ╫⌐╫£ ╫פ╫ñ╫¿╫ש╫ר ╫פ╫¿╫נ╫⌐╫ץ╫ƒ ╫פ╫á╫¿╫נ╫פ
      final segments = _readingSegmentsForCurrentMode();
      final visiblePositions = positions
          .where(
            (position) =>
                position.itemTrailingEdge > 0 && position.itemLeadingEdge < 1,
          )
          .toList()
        ..sort((a, b) => a.itemLeadingEdge.compareTo(b.itemLeadingEdge));
      final sourceIndices = sourceLineIndicesForSegmentViewports(
        segments,
        (visiblePositions.isNotEmpty ? visiblePositions : positions).map(
          (position) => ReadingSegmentViewport(
            segmentIndex: position.index,
            leadingEdge: position.itemLeadingEdge,
            trailingEdge: position.itemTrailingEdge,
          ),
        ),
      );
      if (sourceIndices.isNotEmpty) {
        widget.tab.index = sourceIndices.first;
      }
    }
  }

  List<ReadingSegment> _readingSegmentsForCurrentMode() {
    final continuous = context.read<SettingsBloc>().state.continuousReadingMode;
    return _readingSegmentsForMode(continuous);
  }

  List<ReadingSegment> _readingSegmentsForMode(bool continuous) {
    if (!identical(_cachedReadingSegmentContent, widget.data) ||
        _cachedReadingSegmentContinuous != continuous) {
      _cachedReadingSegmentContent = widget.data;
      _cachedReadingSegmentContinuous = continuous;
      _cachedReadingSegments = buildReadingSegments(
        widget.data,
        continuous: continuous,
      );
    }
    return _cachedReadingSegments;
  }

  Future<void> _scrollToSourceLine(
    int lineIndex, {
    double alignment = 0.05,
    Duration duration = const Duration(milliseconds: 300),
  }) {
    return scrollToSourceLine(
      scrollController: widget.tab.scrollController,
      scrollOffsetController: widget.tab.mainOffsetController,
      positionsListener: widget.tab.positionsListener,
      segments: _readingSegmentsForCurrentMode(),
      lineIndex: lineIndex,
      viewportExtent: _viewportHeight > 0
          ? _viewportHeight
          : (context.size?.height ?? MediaQuery.sizeOf(context).height),
      alignment: alignment,
      duration: duration,
      curve: Curves.easeInOut,
    );
  }

  void _addTextBookEventIfOpen(TextBookEvent event) {
    if (_textBookBloc.isClosed) {
      return;
    }
    _textBookBloc.add(event);
  }

  // ╫ñ╫ץ╫á╫º╫ª╫ש╫פ ╫⌐╫¬╫⌐╫£╫ק ╫נ╫ש╫¿╫ץ╫ó ╫נ╫ש╫ñ╫ץ╫í ╫£-selectedIndex ╫נ╫¥ ╫ש╫⌐ ╫ע╫£╫ש╫£╫פ ╫₧╫⌐╫₧╫ó╫ץ╫¬╫ש╫¬
  void _onScroll() {
    // ╫נ╫á╫ק╫á╫ץ ╫¿╫ץ╫ª╫ש╫¥ ╫נ╫¬ ╫פ╫£╫ץ╫ע╫ש╫º╫פ ╫פ╫צ╫ץ ╫¿╫º ╫ס╫¬╫ª╫ץ╫ע╫פ ╫פ╫₧╫ñ╫ץ╫ª╫£╫¬ (SimpleBookView ╫£╫⌐╫ó╫ס╫¿)
    // ╫⌐╫ס╫פ ╫פ╫₧╫ñ╫¿╫⌐╫ש╫¥ ╫₧╫ץ╫ª╫ע╫ש╫¥ ╫ס╫ñ╫נ╫á╫£ ╫ª╫ף (╫¢╫£╫ץ╫₧╫¿: ╫£╫נ ExpansionTiles)
    if (widget.showCommentaryAsExpansionTiles) return;

    final state = _textBookBloc.state;
    if (state is! TextBookLoaded) return;

    final currentSelectedIndex = state.selectedIndex;

    if (currentSelectedIndex != null) {
      // ╫נ╫¥ ╫פ╫נ╫ש╫á╫ף╫º╫í ╫פ╫á╫ס╫ק╫¿ ╫¢╫ס╫¿ ╫£╫נ ╫á╫¿╫נ╫פ (╫פ╫נ╫ש╫á╫ף╫º╫í╫ש╫¥ ╫פ╫á╫¿╫נ╫ש╫¥ ╫⌐╫ץ╫á╫ץ ╫ó╫º╫ס ╫ע╫£╫ש╫£╫פ)
      final visibleIndices = state.visibleIndices;
      if (!visibleIndices.contains(currentSelectedIndex)) {
        _addTextBookEventIfOpen(const UpdateSelectedIndex(null));
      }
    }
  }

  // ╫₧╫ó╫º╫ס ╫נ╫ק╫¿ ╫פ╫נ╫ש╫á╫ף╫º╫í ╫פ╫á╫ץ╫¢╫ק╫ש ╫⌐╫á╫ס╫ק╫¿ (╫£╫⌐╫ש╫₧╫ץ╫⌐ ╫ס╫פ╫ó╫¬╫º╫פ ╫ó╫¥ ╫¢╫ץ╫¬╫¿╫ץ╫¬)
  final ValueNotifier<int?> _currentSelectedIndex = ValueNotifier<int?>(null);

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

  /// helper ╫º╫ר╫ƒ ╫⌐╫₧╫ק╫צ╫ש╫¿ ╫¿╫⌐╫ש╫₧╫¬ AppContextMenuEntry ╫₧╫º╫ס╫ץ╫ª╫פ ╫נ╫ק╫¬
  List<AppContextMenuEntry> _buildGroup(
    String groupName,
    List<String>? group,
    TextBookLoaded st,
    int paragraphIndex,
  ) {
    if (group == null || group.isEmpty) return const [];
    final bool groupActive =
        group.every((title) => st.activeCommentators.contains(title));
    return [
      AppContextMenuEntry(
        label: '╫פ╫ª╫ע ╫נ╫¬ ╫¢╫£ $groupName',
        trailing:
            groupActive ? const Icon(FluentIcons.checkmark_24_regular) : null,
        onTap: () {
          _selectParagraphForContextMenu(paragraphIndex);
          final current = List<String>.from(st.activeCommentators);
          final isAdding = !groupActive;
          if (groupActive) {
            current.removeWhere(group.contains);
          } else {
            for (final title in group) {
              if (!current.contains(title)) current.add(title);
            }
          }
          context.read<TextBookBloc>().add(UpdateCommentators(current));
          _openCommentatorsPane(isAdding: isAdding);
        },
      ),
      ...group.map((title) {
        final bool isActive = st.activeCommentators.contains(title);
        return AppContextMenuEntry(
          label: title,
          trailing:
              isActive ? const Icon(FluentIcons.checkmark_24_regular) : null,
          onTap: () {
            _selectParagraphForContextMenu(paragraphIndex);
            final current = List<String>.from(st.activeCommentators);
            final isAdding = !current.contains(title);
            current.contains(title)
                ? current.remove(title)
                : current.add(title);
            context.read<TextBookBloc>().add(UpdateCommentators(current));
            _openCommentatorsPane(isAdding: isAdding);
          },
        );
      }),
    ];
  }

  // ╫ס╫á╫ש╫ש╫¬ ╫¬╫ñ╫¿╫ש╫ר ╫º╫ץ╫á╫ר╫º╫í╫ר ╫£╫נ╫ש╫á╫ף╫º╫í ╫í╫ñ╫ª╫ש╫ñ╫ש ╫⌐╫£ ╫ñ╫í╫º╫פ
  List<AppContextMenuEntry> _buildContextMenuForIndex(
      TextBookLoaded state,
      int paragraphIndex,
      BuildContext menuContext,
      String? selectedText,
      Offset tapPosition) {
    // ╫₧╫ª╫ס ╫¬╫ª╫ץ╫ע╫פ ╫₧╫º╫ף╫ש╫₧╫פ Γאפ ╫¬╫ñ╫¿╫ש╫ר ╫₧╫ש╫á╫ש╫₧╫£╫ש
    if (widget.isPreviewMode) {
      return [
        AppContextMenuEntry(
          label: '╫פ╫ó╫¬╫º',
          icon: FluentIcons.copy_24_regular,
          enabled: selectedText != null && selectedText.trim().isNotEmpty,
          onTap: () => _copyFormattedText(selectedText),
        ),
      ];
    }

    final groups = state.commentatorGroups;
    final tanachGroup = CommentatorGroup.groupByTitle(groups, '╫¬╫ץ╫¿╫פ ╫⌐╫ס╫¢╫¬╫ס');
    final chazalGroup = CommentatorGroup.groupByTitle(groups, '╫ק╫צ"╫£');
    final rishonimGroup = CommentatorGroup.groupByTitle(groups, '╫¿╫נ╫⌐╫ץ╫á╫ש╫¥');
    final acharonimGroup = CommentatorGroup.groupByTitle(groups, '╫נ╫ק╫¿╫ץ╫á╫ש╫¥');
    final modernGroup = CommentatorGroup.groupByTitle(groups, '╫₧╫ק╫ס╫¿╫ש ╫צ╫₧╫á╫á╫ץ');
    final ungroupedGroup = CommentatorGroup.groupByTitle(groups, '╫⌐╫נ╫¿ ╫₧╫ñ╫¿╫⌐╫ש╫¥');

    final allActive = state.activeCommentators
        .toSet()
        .containsAll(state.availableCommentators);
    final paragraphLinks = buildCombinedViewContextMenuLinksForParagraph(
      linksByLine: state.linksByLine,
      paragraphIndex: paragraphIndex,
    );
    final isCommentatorsTabActive =
        widget.isCommentatorsTabActive?.call() ?? false;
    final shouldShowOpenPaneEntry = shouldShowOpenCommentatorsPaneEntry(
      hasSelectedCommentators: state.activeCommentators.isNotEmpty,
      showCommentaryAsExpansionTiles: widget.showCommentaryAsExpansionTiles,
      isCommentatorsTabActive: isCommentatorsTabActive,
    );
    final shouldShowSelectEntry = shouldShowSelectCommentatorsEntry(
      hasOpenCommentatorsPaneWithFilterCallback:
          widget.onOpenCommentatorsPaneWithFilter != null,
      isCommentatorsTabActive: isCommentatorsTabActive,
    );

    final commentatorChildren = <AppContextMenuEntry>[
      if (shouldShowOpenPaneEntry)
        AppContextMenuEntry(
          label: '╫ñ╫¬╫ק ╫₧╫ñ╫¿╫⌐╫ש╫¥ ╫ס╫ק╫£╫ץ╫á╫ש╫¬ ╫ª╫ף',
          onTap: () {
            _selectParagraphForContextMenu(paragraphIndex);
            _openCommentatorsPane(isAdding: true);
          },
        ),
      if (shouldShowSelectEntry)
        AppContextMenuEntry(
          label: '╫ñ╫¬╫ק ╫ס╫ק╫ש╫¿╫¬ ╫₧╫ñ╫¿╫⌐╫ש╫¥ ╫ס╫ק╫£╫ץ╫á╫ש╫¬ ╫ª╫ף',
          onTap: () {
            _selectParagraphForContextMenu(paragraphIndex);
            widget.onOpenCommentatorsPaneWithFilter!();
          },
        ),
      if (shouldShowOpenPaneEntry || shouldShowSelectEntry)
        const AppContextMenuEntry.divider(),
      AppContextMenuEntry(
        label: '╫פ╫ª╫ע ╫נ╫¬ ╫¢╫£ ╫פ╫₧╫ñ╫¿╫⌐╫ש╫¥',
        trailing:
            allActive ? const Icon(FluentIcons.checkmark_24_regular) : null,
        onTap: () {
          _selectParagraphForContextMenu(paragraphIndex);
          context.read<TextBookBloc>().add(
                UpdateCommentators(
                  allActive
                      ? <String>[]
                      : List<String>.from(state.availableCommentators),
                ),
              );
          _openCommentatorsPane(isAdding: !allActive);
        },
      ),
      const AppContextMenuEntry.divider(),
      ..._buildGroup(
          tanachGroup.title, tanachGroup.commentators, state, paragraphIndex),
      if (tanachGroup.commentators.isNotEmpty &&
          chazalGroup.commentators.isNotEmpty)
        const AppContextMenuEntry.divider(),
      ..._buildGroup(
          chazalGroup.title, chazalGroup.commentators, state, paragraphIndex),
      if (chazalGroup.commentators.isNotEmpty &&
          rishonimGroup.commentators.isNotEmpty)
        const AppContextMenuEntry.divider(),
      ..._buildGroup(rishonimGroup.title, rishonimGroup.commentators, state,
          paragraphIndex),
      if (rishonimGroup.commentators.isNotEmpty &&
          acharonimGroup.commentators.isNotEmpty)
        const AppContextMenuEntry.divider(),
      ..._buildGroup(acharonimGroup.title, acharonimGroup.commentators, state,
          paragraphIndex),
      if (acharonimGroup.commentators.isNotEmpty &&
          modernGroup.commentators.isNotEmpty)
        const AppContextMenuEntry.divider(),
      ..._buildGroup(
          modernGroup.title, modernGroup.commentators, state, paragraphIndex),
      if ((tanachGroup.commentators.isNotEmpty ||
              chazalGroup.commentators.isNotEmpty ||
              rishonimGroup.commentators.isNotEmpty ||
              acharonimGroup.commentators.isNotEmpty ||
              modernGroup.commentators.isNotEmpty) &&
          ungroupedGroup.commentators.isNotEmpty)
        const AppContextMenuEntry.divider(),
      ..._buildGroup(ungroupedGroup.title, ungroupedGroup.commentators, state,
          paragraphIndex),
    ];

    final showOpenLinksPaneEntry = shouldShowOpenLinksPaneEntry(
      hasLinks: paragraphLinks.isNotEmpty,
      isLinksTabActive: widget.isLinksTabActive?.call() ?? false,
    );

    List<AppContextMenuEntry> buildLinkChildren() => [
          if (showOpenLinksPaneEntry) ...[
            AppContextMenuEntry(
              label: '╫ñ╫¬╫ק ╫º╫ש╫⌐╫ץ╫¿╫ש╫¥ ╫ס╫ק╫£╫ץ╫á╫ש╫¬ ╫ª╫ף',
              onTap: () => widget.onOpenLinksPane?.call(),
            ),
            const AppContextMenuEntry.divider(),
          ],
          ...paragraphLinks.map((link) => AppContextMenuEntry(
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
              )),
        ];

    return [
      () {
        // ╫פ╫ק╫ש╫ñ╫ץ╫⌐ ╫ó╫ץ╫ס╫ף ╫¬╫₧╫ש╫ף ╫ó╫£ ╫ר╫º╫í╫ר ╫£╫£╫נ ╫á╫ש╫º╫ץ╫ף ╫ץ╫ר╫ó╫₧╫ש╫¥ Γאפ ╫₧╫á╫º╫ש╫¥ ╫ñ╫ó╫¥ ╫נ╫ק╫¬
        // ╫£╫⌐╫ש╫₧╫ץ╫⌐ ╫ע╫¥ ╫ס╫¬╫ץ╫ץ╫ש╫¬ ╫פ╫¬╫ñ╫¿╫ש╫ר ╫ץ╫ע╫¥ ╫ס╫⌐╫נ╫ש╫£╫¬╫¬ ╫פ╫ק╫ש╫ñ╫ץ╫⌐ ╫ס╫ñ╫ץ╫ó╫£.
        final rawText = selectedText?.trim() ?? '';
        final cleanedText = utils.hasNikud(rawText)
            ? utils.removeVolwels(rawText).trim()
            : rawText;
        final hasSelectedText = cleanedText.isNotEmpty;
        final preview = hasSelectedText ? previewForLabel(cleanedText) : '';
        return AppContextMenuEntry(
          label: '╫ק╫ש╫ñ╫ץ╫⌐',
          icon: FluentIcons.search_24_regular,
          enabled: hasSelectedText,
          children: hasSelectedText
              ? [
                  AppContextMenuEntry(
                    label: "╫ק╫ñ╫⌐ '$preview' ╫ס╫í╫ñ╫¿ ╫צ╫פ",
                    icon: FluentIcons.book_search_24_regular,
                    onTap: () =>
                        widget.openLeftPaneTab(1, searchText: cleanedText),
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
        );
      }(),
      AppContextMenuEntry(
        label: '╫₧╫ñ╫¿╫⌐╫ש╫¥',
        icon: FluentIcons.book_24_regular,
        enabled: state.availableCommentators.isNotEmpty,
        children: commentatorChildren,
      ),
      AppContextMenuEntry(
        label: '╫º╫ש╫⌐╫ץ╫¿╫ש╫¥',
        icon: FluentIcons.link_24_regular,
        enabled: paragraphLinks.isNotEmpty,
        childrenBuilder: buildLinkChildren,
      ),
      ...(() {
        final dictionaryText = (selectedText?.trim().isNotEmpty == true)
            ? selectedText
            : wordAtGlobalPosition(tapPosition);
        final dictionaryEntries = buildDictionaryContextMenuEntries(
          context: context,
          selectedText: dictionaryText,
          repository: _dictionaryLookupRepository,
        );
        if (dictionaryEntries.isEmpty) {
          return const <AppContextMenuEntry>[];
        }
        return <AppContextMenuEntry>[
          const AppContextMenuEntry.divider(),
          ...dictionaryEntries,
        ];
      })(),
      const AppContextMenuEntry.divider(),
      AppContextMenuEntry(
        label: '╫פ╫ץ╫í╫ú ╫פ╫ó╫¿╫פ ╫נ╫ש╫⌐╫ש╫¬',
        icon: FluentIcons.note_add_24_regular,
        onTap: () => _showNoteEditor(selectedText),
      ),
      AppContextMenuEntry(
        label: '╫ף╫ץ╫ץ╫ק ╫ó╫£ ╫ר╫ó╫ץ╫¬ ╫ס╫í╫ñ╫¿',
        icon: FluentIcons.error_circle_24_regular,
        onTap: () => _openErrorReportDialog(
          selectedText ?? '',
          fallbackLineIndex: paragraphIndex,
        ),
      ),
      const AppContextMenuEntry.divider(),
      AppContextMenuEntry(
        label: '╫פ╫ó╫¬╫º',
        icon: FluentIcons.copy_24_regular,
        enabled: selectedText != null && selectedText.trim().isNotEmpty,
        onTap: () => _copyFormattedText(selectedText),
      ),
      AppContextMenuEntry(
        label: '╫פ╫ó╫¬╫º ╫נ╫¬ ╫¢╫£ ╫פ╫ñ╫í╫º╫פ',
        icon: FluentIcons.document_copy_24_regular,
        enabled: paragraphIndex >= 0 && paragraphIndex < widget.data.length,
        onTap: () => _copyParagraphByIndex(paragraphIndex),
      ),
      AppContextMenuEntry(
        label: '╫פ╫ó╫¬╫º ╫ר╫º╫í╫ר ╫₧╫ץ╫ª╫ע',
        icon: FluentIcons.document_copy_24_regular,
        onTap: _copyVisibleText,
      ),
      // ╫ñ╫¿╫ש╫ר╫ש ╫¬╫ñ╫¿╫ש╫ר ╫₧╫ñ╫£╫נ╫ע╫ש╫á╫ש╫¥
      ...() {
        final pluginItems = ContextMenuRegistry.instance.getAll();
        if (pluginItems.isEmpty) return const <AppContextMenuEntry>[];
        return <AppContextMenuEntry>[
          const AppContextMenuEntry.divider(),
          ...pluginItems.map((record) {
            final pluginId = record.$1;
            final item = record.$2;
            return AppContextMenuEntry(
              label: item.label,
              icon: fluentIconFromName(item.icon),
              onTap: () {
                unawaited(
                    PluginRuntimeDispatcher.instance.dispatchEventToPlugin(
                  pluginId,
                  'reader.context_menu_item_clicked',
                  {
                    'itemId': item.id,
                    'selectedText': selectedText ?? '',
                    'currentRef': state.currentTitle ?? '',
                    'currentBook': state.book.title,
                    'currentBookId': state.book.title,
                    'currentIndex': paragraphIndex,
                  },
                ));
              },
            );
          }),
        ];
      }(),
    ];
  }

  void _selectParagraphForContextMenu(int paragraphIndex) {
    _currentSelectedIndex.value = paragraphIndex;

    final state = _textBookBloc.state;
    if (state is TextBookLoaded && state.selectedIndex != paragraphIndex) {
      _addTextBookEventIfOpen(UpdateSelectedIndex(paragraphIndex));
    }
  }

  /// ╫ñ╫¬╫ש╫ק╫¬ ╫ף╫ש╫נ╫£╫ץ╫ע ╫ף╫ש╫ץ╫ץ╫ק ╫ó╫£ ╫ר╫ó╫ץ╫¬ ╫ס╫í╫ñ╫¿
  void _openErrorReportDialog(
    String selectedText, {
    int? fallbackLineIndex,
  }) {
    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded) return;

    ErrorReportHelper.showErrorReportDialog(
      context: context,
      selectedText: selectedText,
      state: state,
      fontSize: widget.textSize,
      bookTitle: widget.tab.book.title,
      savedSelectedIndex: fallbackLineIndex ?? _savedSelectedIndex.value,
    );
  }

  /// ╫פ╫ó╫¬╫º╫¬ ╫ñ╫í╫º╫פ ╫£╫ñ╫ש ╫נ╫ש╫á╫ף╫º╫í (╫₧╫⌐╫¬╫₧╫⌐ ╫ס╓╛widget.data[index] ╫ץ╫₧╫ש╫ש╫ª╫¿ ╫ע╫¥ HTML)
  Future<void> _copyParagraphByIndex(int index) async {
    if (index < 0 || index >= widget.data.length) return;

    final text = widget.data[index];
    if (text.trim().isEmpty) return;

    // ╫º╫ס╫£╫¬ ╫פ╫פ╫ע╫ף╫¿╫ץ╫¬ ╫פ╫á╫ץ╫¢╫ק╫ש╫ץ╫¬
    final settingsState = context.read<SettingsBloc>().state;
    final textBookState = context.read<TextBookBloc>().state;

    final removeNikud =
        textBookState is TextBookLoaded && textBookState.removeNikud;
    final processedText = removeNikud ? utils.removeVolwels(text) : text;

    final plainText = utils.stripHtmlIfNeeded(processedText);

    String finalText = plainText;
    String finalHtmlText = processedText;

    // ╫נ╫¥ ╫ª╫¿╫ש╫ת ╫£╫פ╫ץ╫í╫ש╫ú ╫¢╫ץ╫¬╫¿╫ץ╫¬
    if (settingsState.copyWithHeaders != 'none' &&
        textBookState is TextBookLoaded) {
      final bookName = CopyUtils.extractBookName(textBookState.book);
      final currentPath = await CopyUtils.extractCurrentPath(
        textBookState.book,
        index,
        bookContent: textBookState.content,
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

  /// ╫פ╫ó╫¬╫º╫¬ ╫פ╫ר╫º╫í╫ר ╫פ╫₧╫ץ╫ª╫ע ╫ס╫₧╫í╫ת ╫£╫£╫ץ╫ק
  void _copyVisibleText() async {
    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded || state.visibleIndices.isEmpty) return;

    // ╫נ╫ש╫í╫ץ╫ú ╫¢╫£ ╫פ╫ר╫º╫í╫ר ╫פ╫á╫¿╫נ╫פ ╫ס╫₧╫í╫ת
    final visibleTexts = <String>[];
    for (final index in state.visibleIndices) {
      if (index >= 0 && index < widget.data.length) {
        visibleTexts.add(widget.data[index]);
      }
    }

    if (visibleTexts.isEmpty) return;

    final combinedText = visibleTexts.join('\n\n');

    // ╫º╫ס╫£╫¬ ╫פ╫פ╫ע╫ף╫¿╫ץ╫¬ ╫פ╫á╫ץ╫¢╫ק╫ש╫ץ╫¬
    final settingsState = context.read<SettingsBloc>().state;

    String finalText = combinedText;

    // ╫נ╫¥ ╫ª╫¿╫ש╫ת ╫£╫פ╫ץ╫í╫ש╫ú ╫¢╫ץ╫¬╫¿╫ץ╫¬
    if (settingsState.copyWithHeaders != 'none') {
      final bookName = CopyUtils.extractBookName(state.book);
      final firstVisibleIndex = state.visibleIndices.first;
      final currentPath = await CopyUtils.extractCurrentPath(
        state.book,
        firstVisibleIndex,
        bookContent: state.content,
      );

      finalText = CopyUtils.formatTextWithHeaders(
        originalText: combinedText,
        copyWithHeaders: settingsState.copyWithHeaders,
        copyHeaderFormat: settingsState.copyHeaderFormat,
        bookName: bookName,
        currentPath: currentPath,
      );
    }

    finalText = CopyUtils.applyCopyPreferences(
      text: finalText,
      replaceHolyNames: settingsState.replaceHolyNames,
    );

    final combinedHtml = _formatTextAsHtml(finalText);

    final item = DataWriterItem();
    item.add(Formats.plainText(finalText.trimRight()));
    item.add(Formats.htmlText(combinedHtml));

    await SystemClipboard.instance?.write([item]);
  }

  /// ╫ó╫ש╫ª╫ץ╫ס ╫ר╫º╫í╫ר ╫¢-HTML ╫ó╫¥ ╫פ╫ע╫ף╫¿╫ץ╫¬ ╫פ╫ע╫ץ╫ñ╫ƒ ╫פ╫á╫ץ╫¢╫ק╫ש╫ץ╫¬
  String _formatTextAsHtml(String text) {
    final settingsState = context.read<SettingsBloc>().state;
    return CopyUtils.buildStyledHtml(
      htmlText: text,
      fontFamily: settingsState.fontFamily,
      fontSize: widget.textSize,
    );
  }

  /// ╫פ╫ó╫¬╫º╫¬ ╫ר╫º╫í╫ר ╫₧╫ó╫ץ╫ª╫ס (HTML) ╫£╫£╫ץ╫ק
  Future<void> _copyFormattedText([String? capturedText]) async {
    final plainText = capturedText ?? _savedSelectedText.value;

    debugPrint('_copyFormattedText called with: "$plainText"');
    debugPrint('_currentSelectedIndex: ${_currentSelectedIndex.value}');

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
        selectedIndex: _currentSelectedIndex.value,
        sourceContent: widget.data,
        textBookState: textBookState,
        settingsState: settingsState,
        fontFamily: settingsState.fontFamily,
        fontSize: widget.textSize,
      );
    } catch (e) {
      if (mounted) {
        UiSnack.showError('╫⌐╫ע╫ש╫נ╫פ ╫ס╫פ╫ó╫¬╫º╫פ ╫₧╫ó╫ץ╫ª╫ס╫¬: $e');
      }
    }
  }

  /// ╫פ╫ª╫ע╫¬ ╫ó╫ץ╫¿╫ת ╫פ╫פ╫ó╫¿╫ץ╫¬
  Future<void> _showNoteEditor([String? capturedText]) async {
    final state = _textBookBloc.state;
    if (state is! TextBookLoaded) return;

    final selectedText = capturedText ?? _savedSelectedText.value;

    // ╫₧╫⌐╫¬╫₧╫⌐ ╫ס╫⌐╫ץ╫¿╫פ ╫⌐╫₧╫₧╫á╫פ ╫פ╫ץ╫ף╫ע╫⌐ ╫ר╫º╫í╫ר (╫נ╫¥ ╫º╫ש╫ש╫¥), ╫נ╫ק╫¿╫¬ ╫ס╫⌐╫ץ╫¿╫פ ╫פ╫á╫ס╫ק╫¿╫¬, ╫נ╫ק╫¿╫¬ ╫ס╫⌐╫ץ╫¿╫פ ╫פ╫¿╫נ╫⌐╫ץ╫á╫פ ╫פ╫á╫¿╫נ╫ש╫¬
    final currentIndex = _savedSelectedIndex.value ??
        state.selectedIndex ??
        (state.visibleIndices.isNotEmpty ? state.visibleIndices.first : 0);

    // ╫º╫ס╫£╫¬ ╫פ╫ר╫º╫í╫ר ╫פ╫₧╫צ╫פ╫פ ╫⌐╫£ ╫פ╫⌐╫ץ╫¿╫פ - ╫נ╫¥ ╫ש╫⌐ ╫ר╫º╫í╫ר ╫á╫ס╫ק╫¿, ╫₧╫⌐╫¬╫₧╫⌐╫ש╫¥ ╫ס╫ץ (╫נ╫ק╫¿╫ש ╫פ╫í╫¿╫¬ ╫á╫ש╫º╫ץ╫ף), ╫נ╫ק╫¿╫¬ ╫ס╫ר╫º╫í╫ר ╫פ╫₧╫צ╫פ╫פ (╫¢╫₧╫ץ ╫⌐╫ש╫ץ╫ª╫ע ╫¢╫¢╫ץ╫¬╫¿╫¬)
    final referenceText = selectedText?.trim().isNotEmpty == true
        ? removeHebrewDiacritics(selectedText!.trim())
        : extractDisplayTextFromLines(
            state.content,
            currentIndex + 1,
            excludeBookTitle: widget.tab.book.title,
          );

    // ╫ר╫ó╫ƒ ╫ר╫ש╫ץ╫ר╫פ ╫נ╫¥ ╫º╫ש╫ש╫₧╫¬
    final draftService = PersonalNoteDraftService();
    final draft = await draftService.loadDraft(
      bookId: widget.tab.book.title,
      lineNumber: currentIndex + 1,
    );

    if (!mounted) return;

    // ╫⌐╫£╫ק event ╫£╫ñ╫¬╫ש╫ק╫¬ ╫₧╫ª╫ס ╫ש╫ª╫ש╫¿╫פ ╫ס╫í╫ש╫ש╫ף╫ס╫¿
    context.read<PersonalNotesBloc>().add(StartCreatingPersonalNote(
          bookId: widget.tab.book.title,
          lineNumber: currentIndex + 1,
          referenceText: referenceText,
          selectedText: selectedText?.trim(),
          initialContent: draft?.content ?? '',
          initialFormat:
              draft?.contentFormat ?? PersonalNoteContentFormat.plain,
        ));

    // ╫ñ╫¬╫ק ╫נ╫¬ ╫ק╫£╫ץ╫á╫ש╫¬ ╫פ╫פ╫ó╫¿╫ץ╫¬
    widget.onOpenPersonalNotes?.call();
  }

  RenderSettings _selectionRenderSettings(
    TextBookLoaded state,
    SettingsState settingsState,
  ) {
    return RenderSettings(
      removeNikud: state.removeNikud,
      removePunctuation: state.removePunctuation,
      removeTeamim: !settingsState.showTeamim,
      replaceHolyNames: settingsState.replaceHolyNames,
      searchText: state.searchText,
      searchOptions: state.searchOptions,
      alternativeWords: state.alternativeWords,
      spacingValues: state.spacingValues,
      isFuzzySearch: state.searchMode == SearchMode.fuzzy,
      searchMode: state.searchMode,
      searchDistance: state.searchDistance,
      fontSize: widget.textSize,
      fontFamily: settingsState.fontFamily,
      lineHeight: settingsState.lineHeight,
    );
  }

  List<String> _buildRenderedVisibleLines(
    TextBookLoaded state,
    SettingsState settingsState,
  ) {
    final renderSettings = _selectionRenderSettings(state, settingsState);
    return state.visibleIndices
        .where((idx) => idx >= 0 && idx < widget.data.length)
        .map(
          (idx) => renderSelectionLine(
            rawText: widget.data[idx],
            settings: renderSettings,
          ),
        )
        .toList();
  }

  Widget buildKeyboardListener() {
    return BlocBuilder<TextBookBloc, TextBookState>(
      bloc: context.read<TextBookBloc>(),
      builder: (context, state) {
        if (state is! TextBookLoaded) {
          return const Center(child: CircularProgressIndicator());
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            // ╫⌐╫ץ╫₧╫¿ ╫נ╫¬ ╫ע╫ץ╫ס╫פ ╫פ╫ס╫£╫ץ╫º ╫ס╫ñ╫ץ╫ó╫£ ╫£╫⌐╫ש╫₧╫ץ╫⌐ ╫ס╫ק╫ש╫⌐╫ץ╫ס╫ש ╫פ╫ע╫£╫ש╫£╫פ
            _viewportHeight = constraints.maxHeight;
            final settingsState = context.watch<SettingsBloc>().state;
            final readingSegments =
                _readingSegmentsForMode(settingsState.continuousReadingMode);

            return SelectionArea(
              key: ValueKey('combined_selection_$_selectionAreaRevision'),
              // SelectionArea ╫נ╫ק╫ף ╫£╫¢╫£ ╫פ╫¿╫⌐╫ש╫₧╫פ - ╫₧╫נ╫ñ╫⌐╫¿ ╫ס╫ק╫ש╫¿╫פ ╫¿╫ª╫ש╫ñ╫פ ╫ס╫ש╫ƒ ╫ñ╫í╫º╫נ╫ץ╫¬
              contextMenuBuilder: (context, selectableRegionState) {
                return const SizedBox.shrink();
              },
              onSelectionChanged: (selection) {
                final plain = selection?.plainText;
                if (!shouldPersistSelectedText(plain)) {
                  widget.selectionSyncController?.clear(_selectionOwner);
                  _selectionManager.exitSelectionMode();
                  _savedSelectedText.value = null;
                  return;
                }
                widget.selectionSyncController?.activate(_selectionOwner);
                // ╫¢╫á╫ש╫í╫פ ╫£╫₧╫ª╫ס ╫ס╫ק╫ש╫¿╫פ ╫¢╫⌐╫ש╫⌐ ╫ר╫º╫í╫ר ╫á╫ס╫ק╫¿
                if (!_selectionManager.isInSelectionMode) {
                  // ╫⌐╫ש╫₧╫ץ╫⌐ ╫ס╫נ╫ש╫á╫ף╫º╫í ╫פ╫ó╫£╫ש╫ץ╫ƒ ╫פ╫á╫¿╫נ╫פ ╫ס╫₧╫º╫ץ╫¥ 0
                  _selectionManager.setAnchor(topmostVisibleIndex(
                      widget.tab.positionsListener.itemPositions.value));
                }

                // ╫ק╫⌐╫ץ╫ס: ╫¢╫ף╫ש ╫⌐-Ctrl+C ╫ש╫ó╫ס╫ץ╫ף ╫₧╫ש╫ף ╫נ╫ק╫¿╫ש ╫í╫ש╫₧╫ץ╫ƒ ╫ר╫º╫í╫ר ╫ó╫¥ ╫פ╫ó╫¢╫ס╫¿
                // ╫á╫ץ╫ץ╫ף╫נ ╫⌐╫פ╫ñ╫ץ╫º╫ץ╫í ╫á╫₧╫ª╫נ ╫ó╫£ ╫נ╫צ╫ץ╫¿ ╫פ╫º╫¿╫ש╫נ╫פ.
                _focusNode.requestFocus();

                // ╫₧╫ק╫⌐╫ס ╫נ╫¬ ╫₧╫í╫ñ╫¿ ╫פ╫⌐╫ץ╫¿╫פ ╫פ╫₧╫ף╫ץ╫ש╫º ╫⌐╫£ ╫פ╫ר╫º╫í╫ר ╫פ╫₧╫ץ╫ף╫ע╫⌐
                // ╫₧╫⌐╫¬╫₧╫⌐ ╫ס╫נ╫ץ╫¬╫פ ╫£╫ץ╫ע╫ש╫º╫פ ╫¢╫₧╫ץ ╫ס╫ף╫ש╫ץ╫ץ╫ק ╫⌐╫ע╫ש╫נ╫ץ╫¬
                final TextBookLoaded? loadedState =
                    _textBookBloc.state is TextBookLoaded
                        ? _textBookBloc.state as TextBookLoaded
                        : null;
                int? foundIndex;
                var fixedPlain = plain;

                if (loadedState != null) {
                  final settingsState = context.read<SettingsBloc>().state;
                  // ╫₧╫º╫ס╫£ ╫נ╫¬ ╫פ╫⌐╫ץ╫¿╫פ ╫פ╫¿╫נ╫⌐╫ץ╫á╫פ ╫פ╫á╫¿╫נ╫ש╫¬
                  final baseIndex = loadedState.visibleIndices.isNotEmpty
                      ? loadedState.visibleIndices.first
                      : 0;

                  final visibleLines =
                      _buildRenderedVisibleLines(loadedState, settingsState);
                  final visibleText = visibleLines.join('\n');

                  fixedPlain = restoreSelectedTextLineBreaks(
                    selectedText: plain!,
                    visibleLines: visibleLines,
                  );

                  // ╫₧╫ץ╫ª╫נ ╫נ╫¬ ╫פ╫₧╫ש╫º╫ץ╫¥ ╫⌐╫£ ╫פ╫ר╫º╫í╫ר ╫פ╫₧╫ץ╫ף╫ע╫⌐
                  final selectionStart = visibleText.indexOf(fixedPlain);

                  if (selectionStart >= 0) {
                    // ╫í╫ץ╫ñ╫¿ ╫¢╫₧╫פ ╫⌐╫ץ╫¿╫ץ╫¬ ╫ש╫⌐ ╫£╫ñ╫á╫ש ╫פ╫ר╫º╫í╫ר ╫פ╫₧╫ץ╫ף╫ע╫⌐
                    final before = visibleText.substring(0, selectionStart);
                    final offset = '\n'.allMatches(before).length;
                    foundIndex = baseIndex + offset;
                  }

                  // fallback: ╫נ╫¥ ╫£╫נ ╫פ╫ª╫£╫ק╫á╫ץ ╫£╫ק╫⌐╫ס ╫נ╫ש╫á╫ף╫º╫í, ╫á╫⌐╫¬╫₧╫⌐ ╫ס╫⌐╫ץ╫¿╫פ ╫⌐╫á╫ס╫ק╫¿╫פ (╫נ╫¥ ╫º╫ש╫ש╫₧╫¬)
                  foundIndex ??= loadedState.selectedIndex;
                }

                if (mounted) {
                  _savedSelectedText.value = fixedPlain;
                  _savedSelectedIndex.value = foundIndex;
                  _currentSelectedIndex.value = foundIndex;
                  widget.onSelectedTextChanged?.call(fixedPlain);

                  // ╫⌐╫£╫ש╫ק╫¬ event ╫£╫ñ╫£╫נ╫ע╫ש╫á╫ש╫¥ ╫ó╫¥ ╫פ-index ╫פ╫₧╫ף╫ץ╫ש╫º
                  final selectionText = fixedPlain?.trim() ?? '';
                  if (selectionText.isNotEmpty && loadedState != null) {
                    unawaited(PluginRuntimeDispatcher.instance.dispatchEvent(
                      'reader.selection_changed',
                      {
                        'text': selectionText,
                        'currentRef': loadedState.currentTitle ?? '',
                        'currentBook': loadedState.book.title,
                        'currentBookId': loadedState.book.title,
                        'currentIndex': foundIndex ?? 0,
                      },
                    ));
                  }
                }
                _prefetchDictionaryLookups(fixedPlain);
              },
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: Shortcuts(
                  shortcuts: <ShortcutActivator, Intent>{
                    // Windows/Linux
                    LogicalKeySet(
                      LogicalKeyboardKey.control,
                      LogicalKeyboardKey.keyC,
                    ): const _CopySelectedTextIntent(),
                    // Windows "classic" copy
                    LogicalKeySet(
                      LogicalKeyboardKey.control,
                      LogicalKeyboardKey.insert,
                    ): const _CopySelectedTextIntent(),
                    // macOS (╫£╫₧╫º╫¿╫פ ╫⌐╫₧╫¿╫ש╫ª╫ש╫¥ ╫⌐╫¥)
                    LogicalKeySet(
                      LogicalKeyboardKey.meta,
                      LogicalKeyboardKey.keyC,
                    ): const _CopySelectedTextIntent(),
                    // Esc ╫£╫á╫ש╫º╫ץ╫ש ╫ס╫ק╫ש╫¿╫פ
                    LogicalKeySet(
                      LogicalKeyboardKey.escape,
                    ): const ClearSelectionIntent(),
                  },
                  child: Actions(
                    actions: <Type, Action<Intent>>{
                      _CopySelectedTextIntent:
                          CallbackAction<_CopySelectedTextIntent>(
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
                      ClearSelectionIntent:
                          CallbackAction<ClearSelectionIntent>(
                        onInvoke: (_) {
                          _selectionManager.exitSelectionMode();
                          // ╫á╫ש╫º╫ץ╫ש ╫פ╫ס╫ק╫ש╫¿╫פ ╫ס-SelectionArea
                          _savedSelectedText.value = null;
                          _savedSelectedIndex.value = null;
                          _currentSelectedIndex.value = null;
                          widget.onSelectedTextChanged?.call(null);
                          return null;
                        },
                      ),
                    },
                    child: Directionality(
                      textDirection: TextDirection.rtl,
                      child: widget.isPreviewMode
                          ? Scrollbar(
                              controller: _previewScrollController,
                              thumbVisibility: true,
                              thickness: 8.0,
                              radius: const Radius.circular(4.0),
                              child: ListView.builder(
                                controller: _previewScrollController,
                                itemCount: readingSegments.length,
                                itemBuilder: (context, index) {
                                  return buildExpansiomTile(
                                      ExpansibleController(),
                                      index,
                                      state,
                                      const <int, List<PersonalNote>>{},
                                      readingSegments[index],
                                      settingsState.continuousReadingMode);
                                },
                              ),
                            )
                          : ScrollablePositionedListScrollbar(
                              scrollController: widget.tab.scrollController,
                              itemPositionsListener:
                                  widget.tab.positionsListener,
                              itemCount: readingSegments.length,
                              child: ProgressiveScroll(
                                focusNode: _focusNode,
                                maxSpeed: 10000.0,
                                curve: 10.0,
                                accelerationFactor: 5,
                                scrollController:
                                    widget.tab.mainOffsetController,
                                child: BlocBuilder<PersonalNotesBloc,
                                    PersonalNotesState>(
                                  builder: (context, notesState) {
                                    final noteMap = <int, List<PersonalNote>>{};
                                    if (notesState.bookId == state.book.title) {
                                      for (final note
                                          in notesState.locatedNotes) {
                                        final line = note.lineNumber;
                                        if (line == null) continue;
                                        noteMap
                                            .putIfAbsent(line, () => [])
                                            .add(note);
                                      }
                                    }
                                    return buildOuterList(
                                      state,
                                      noteMap,
                                      readingSegments,
                                      settingsState.continuousReadingMode,
                                    );
                                  },
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget buildOuterList(
    TextBookLoaded state,
    Map<int, List<PersonalNote>> noteMap,
    List<ReadingSegment> readingSegments,
    bool continuous,
  ) {
    return ScrollablePositionedList.builder(
      key: ValueKey('combined-${widget.tab.book.title}'),
      initialScrollIndex:
          segmentIndexForLine(readingSegments, widget.tab.index),
      itemPositionsListener: widget.tab.positionsListener,
      itemScrollController: widget.tab.scrollController,
      scrollOffsetController: widget.tab.mainOffsetController,
      itemCount: readingSegments.length,
      itemBuilder: (context, index) {
        ExpansibleController controller = ExpansibleController();
        return buildExpansiomTile(
          controller,
          index,
          state,
          noteMap,
          readingSegments[index],
          continuous,
        );
      },
    );
  }

  Widget buildExpansiomTile(
    ExpansibleController controller,
    int index,
    TextBookLoaded state,
    Map<int, List<PersonalNote>> noteMap,
    ReadingSegment segment,
    bool continuous,
  ) {
    final primaryLineIndex = segment.startLineIndex;
    final isSelected = state.selectedIndex != null &&
        segment.containsLine(state.selectedIndex!);
    final selectedLineIndex = isSelected && state.selectedIndex != null
        ? state.selectedIndex!
        : primaryLineIndex;
    int actionLineIndex() {
      final currentIndex = _currentSelectedIndex.value;
      if (continuous &&
          !segment.isHeader &&
          currentIndex != null &&
          segment.containsLine(currentIndex)) {
        return currentIndex;
      }
      return selectedLineIndex;
    }

    final isHighlighted = state.highlightedLine != null &&
        segment.containsLine(state.highlightedLine!);
    final notesForLine =
        noteMap[primaryLineIndex + 1] ?? const <PersonalNote>[];

    final theme = Theme.of(context);
    final backgroundColor = () {
      if (!continuous && isHighlighted) {
        return theme.colorScheme.secondaryContainer.withValues(alpha: 0.4);
      }
      if (!continuous && isSelected) {
        return theme.colorScheme.primary.withValues(alpha: 0.08);
      }
      return null;
    }();

    return Column(
      key: PageStorageKey('segment-${segment.startLineIndex}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ╫פ╫ר╫º╫í╫ר ╫⌐╫£ ╫פ╫í╫ñ╫¿ - ╫£╫£╫נ SelectionArea ╫á╫ñ╫¿╫ף, ╫¢╫ש ╫ש╫⌐ SelectionArea ╫¢╫£╫£╫ש
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          decoration: backgroundColor != null
              ? BoxDecoration(color: backgroundColor)
              : null,
          child: EnhancedGestureDetector(
            behavior: HitTestBehavior.translucent,
            onDragSelectionStart: () {
              // ╫¢╫á╫ש╫í╫פ ╫£╫₧╫ª╫ס ╫ס╫ק╫ש╫¿╫פ ╫ס╫ע╫£╫£ drag
              if (!_selectionManager.isInSelectionMode) {
                _selectionManager.setAnchor(actionLineIndex());
              }
            },
            onSingleTap: () {
              if (continuous && !segment.isHeader) {
                return;
              }
              _focusNode.requestFocus();
              // ╫₧╫נ╫ñ╫í ╫נ╫¬ ╫פ╫ר╫º╫í╫ר ╫פ╫⌐╫₧╫ץ╫¿ ╫¢╫⌐╫£╫ץ╫ק╫ª╫ש╫¥ ╫ó╫£ ╫פ╫ñ╫í╫º╫פ
              if (mounted) {
                _savedSelectedText.value = null;
                _savedSelectedIndex.value = null;
                _currentSelectedIndex.value = null;
                widget.onSelectedTextChanged?.call(null);
              }
              // ╫ñ╫⌐╫ץ╫ר ╫₧╫ó╫ף╫¢╫ƒ ╫נ╫¬ selectedIndex - ╫צ╫פ ╫ש╫ע╫¿╫ץ╫¥ ╫£╫ס╫á╫ש╫ש╫פ ╫₧╫ק╫ף╫⌐
              if (isSelected) {
                _addTextBookEventIfOpen(const UpdateSelectedIndex(null));
              } else {
                _addTextBookEventIfOpen(UpdateSelectedIndex(primaryLineIndex));

                // ╫ע╫£╫ש╫£╫פ ╫נ╫ץ╫ר╫ץ╫₧╫ר╫ש╫¬ ╫¢╫ת ╫⌐╫פ╫º╫ר╫ó ╫ש╫פ╫ש╫פ ╫ס╫¿╫נ╫⌐ ╫פ╫ó╫₧╫ץ╫ף
                // ╫¿╫º ╫נ╫¥ ╫ש╫⌐ ╫₧╫ñ╫¿╫⌐╫ש╫¥ ╫£╫פ╫ª╫ע╫פ ╫ץ╫נ╫á╫ק╫á╫ץ ╫ס╫₧╫ª╫ס ExpansionTiles
                if (widget.showCommentaryAsExpansionTiles &&
                    _hasCommentaries(state, primaryLineIndex)) {
                  // ╫₧╫ק╫¢╫ש╫¥ ╫⌐╫פ-UI ╫ש╫¬╫ó╫ף╫¢╫ƒ ╫ó╫¥ ╫ñ╫¬╫ש╫ק╫¬ ╫פ╫₧╫ñ╫¿╫⌐, ╫ץ╫נ╫צ ╫º╫ץ╫ñ╫ª╫ש╫¥ ╫£╫₧╫ש╫º╫ץ╫¥
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    Future.delayed(const Duration(milliseconds: 300), () {
                      if (mounted && widget.tab.scrollController.isAttached) {
                        // ╫ע╫£╫ש╫£╫פ ╫ק╫¢╫₧╫פ: ╫á╫ע╫£╫ץ╫£ ╫¢╫ת ╫⌐╫פ╫ר╫º╫í╫ר ╫פ╫ס╫נ (index + 1) ╫ש╫פ╫ש╫פ ╫ס╫¬╫ק╫¬╫ש╫¬
                        // ╫פ╫₧╫ñ╫¿╫⌐╫ש╫¥ ╫¬╫ץ╫ñ╫í╫ש╫¥ ╫ó╫ף 75% ╫₧╫פ╫ס╫£╫ץ╫º
                        // ╫á╫¿╫ª╫פ ╫⌐╫פ╫ר╫º╫í╫ר ╫פ╫ס╫נ ╫ש╫פ╫ש╫פ ╫ס-90% ╫₧╫פ╫ס╫£╫ץ╫º (╫¢╫£╫ץ╫₧╫¿ 10% ╫₧╫£╫₧╫ר╫פ)
                        // ╫¢╫ת ╫á╫ץ╫ץ╫ף╫נ ╫⌐╫¿╫ץ╫נ╫ש╫¥: 15% ╫ר╫º╫í╫ר ╫£╫₧╫ó╫£╫פ, 75% ╫₧╫ñ╫¿╫⌐╫ש╫¥, 10% ╫ר╫º╫í╫ר ╫£╫₧╫ר╫פ
                        final nextIndex =
                            (index + 1).clamp(0, widget.data.length - 1);
                        widget.tab.scrollController.scrollTo(
                          index: nextIndex,
                          alignment:
                              0.9, // ╫פ╫ר╫º╫í╫ר ╫פ╫ס╫נ ╫ש╫פ╫ש╫פ ╫ס-90% ╫₧╫£╫₧╫ó╫£╫פ (╫¢╫£╫ץ╫₧╫¿ 10% ╫₧╫£╫₧╫ר╫פ)
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      }
                    });
                  });
                }
              }
            },
            onDoubleTap: () {
              // Double-click Γזע ╫ס╫ק╫ש╫¿╫¬ ╫ñ╫í╫º╫פ ╫⌐╫£╫₧╫פ
              // ╫פ╫ó╫¿╫פ: SelectionArea ╫⌐╫£ Flutter ╫£╫נ ╫¬╫ץ╫₧╫ת ╫ס╫ס╫ק╫ש╫¿╫פ ╫ñ╫¿╫ץ╫ע╫¿╫₧╫ר╫ש╫¬,
              // ╫£╫¢╫ƒ ╫פ╫ñ╫ש╫ª'╫¿ ╫פ╫צ╫פ ╫£╫נ ╫₧╫ץ╫₧╫⌐ ╫ס╫₧╫£╫ץ╫נ╫ץ. SelectionArea ╫ש╫ס╫ª╫ó ╫נ╫¬ ╫ñ╫ó╫ץ╫£╫¬
              // ╫ס╫¿╫ש╫¿╫¬ ╫פ╫₧╫ק╫ף╫£ ╫⌐╫£╫ץ (╫ס╫ק╫ש╫¿╫¬ ╫₧╫ש╫£╫פ). ╫£╫ס╫ק╫ש╫¿╫¬ ╫ñ╫í╫º╫פ, ╫פ╫₧╫⌐╫¬╫₧╫⌐ ╫ש╫¢╫ץ╫£
              // ╫£╫פ╫⌐╫¬╫₧╫⌐ ╫ס-Shift+Click ╫נ╫ץ Drag.
              _focusNode.requestFocus();
              _selectionManager.enterDoubleClickMode(actionLineIndex());
            },
            onShiftClick: () {
              // Shift+Click Γזע ╫ס╫ק╫ש╫¿╫¬ ╫ר╫ץ╫ץ╫ק
              _focusNode.requestFocus();
              if (!_selectionManager.hasAnchor()) {
                // ╫נ╫¥ ╫נ╫ש╫ƒ anchor, ╫º╫ץ╫ס╫ó╫ש╫¥ ╫נ╫ץ╫¬╫ץ
                _selectionManager.setAnchor(actionLineIndex());
              }
              // SelectionArea ╫ש╫ר╫ñ╫£ ╫ס╫ס╫ק╫ש╫¿╫¬ ╫פ╫ר╫ץ╫ץ╫ק
            },
            onSecondaryTapDown: (details) {
              // ╫⌐╫ץ╫₧╫¿ ╫נ╫¬ ╫פ╫נ╫ש╫á╫ף╫º╫í ╫פ╫á╫ץ╫¢╫ק╫ש ╫£╫⌐╫ש╫₧╫ץ╫⌐ ╫ס╫¬╫ñ╫¿╫ש╫ר ╫פ╫פ╫º╫⌐╫¿
              if (mounted) {
                _currentSelectedIndex.value = actionLineIndex();
              }
            },
            child: ValueListenableBuilder<String?>(
              valueListenable: _savedSelectedText,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  vertical: continuous ? 0.0 : 4.0,
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return BlocBuilder<SettingsBloc, SettingsState>(
                      builder: (context, settingsState) {
                        var textMaxWidth = settingsState.textMaxWidth;

                        // ╫נ╫¥ ╫פ╫ó╫¿╫ת ╫⌐╫£╫ש╫£╫ש, ╫צ╫ץ ╫¿╫₧╫פ ╫⌐╫ª╫¿╫ש╫ת ╫£╫ק╫⌐╫ס ╫£╫ñ╫ש ╫ע╫ץ╫ף╫£ ╫פ╫₧╫í╫ת
                        // ╫£╫₧╫⌐╫£ -2 = ╫¿╫₧╫פ 2 = 90% ╫₧╫¿╫ץ╫ק╫ס ╫פ╫₧╫í╫ת
                        if (textMaxWidth < 0) {
                          final level = (-textMaxWidth).toInt();
                          final widthPercent = 1.0 - (level * 0.05);
                          textMaxWidth = constraints.maxWidth * widthPercent;
                        }

                        if (continuous && !segment.isHeader) {
                          final segmentText = _buildContinuousSegmentText(
                            segment: segment,
                            state: state,
                            settingsState: settingsState,
                            baseTextStyle: TextStyle(
                              fontSize: widget.textSize,
                              fontFamily: settingsState.fontFamily,
                              height: settingsState.lineHeight,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          );

                          final constrainedText = textMaxWidth > 0
                              ? Center(
                                  child: ConstrainedBox(
                                    constraints:
                                        BoxConstraints(maxWidth: textMaxWidth),
                                    child: segmentText,
                                  ),
                                )
                              : segmentText;

                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(width: 16),
                              Expanded(child: constrainedText),
                            ],
                          );
                        }

                        String data = widget.data[primaryLineIndex];

                        // ╫פ╫ץ╫í╫ñ╫¬ ╫º╫ש╫⌐╫ץ╫¿╫ש╫¥ ╫₧╫ס╫ץ╫í╫í╫ש ╫¬╫ץ╫ץ╫ש╫¥ ╫£╫ñ╫á╫ש ╫¢╫£ ╫ó╫ש╫ס╫ץ╫ף ╫נ╫ק╫¿
                        // ╫¢╫ש start/end ╫₧╫¬╫ש╫ש╫ק╫í╫ש╫¥ ╫£╫ר╫º╫í╫ר ╫פ╫₧╫º╫ץ╫¿╫ש
                        String dataWithLinks = data;
                        if (settingsState.enableHtmlLinks) {
                          try {
                            final linksForLine = state.links
                                .where((link) =>
                                    link.index1 == primaryLineIndex + 1 &&
                                    link.start != null &&
                                    link.end != null)
                                .toList();

                            if (linksForLine.isNotEmpty) {
                              dataWithLinks =
                                  addInlineLinksToText(data, linksForLine);
                            }
                          } catch (e) {
                            // ╫נ╫¥ ╫ש╫⌐ ╫⌐╫ע╫ש╫נ╫פ, ╫ñ╫⌐╫ץ╫ר ╫á╫⌐╫¬╫₧╫⌐ ╫ס╫ר╫º╫í╫ר ╫פ╫₧╫º╫ץ╫¿╫ש
                            dataWithLinks = data;
                          }
                        }

                        // ╫פ╫ף╫ע╫⌐╫פ ╫₧╫₧╫ץ╫º╫ף╫¬ ╫₧╫º╫ש╫⌐╫ץ╫¿ ╫ó╫ץ╫₧╫º: ╫¿╫º ╫ó╫£ ╫פ╫í╫ó╫ש╫ú ╫⌐╫ª╫ץ╫ש╫ƒ, ╫ץ╫ס╫£╫ש
                        // ╫£╫פ╫ñ╫ó╫ש╫£ ╫נ╫¬ ╫⌐╫נ╫¿ ╫נ╫ñ╫⌐╫¿╫ץ╫ש╫ץ╫¬ ╫פ╫ק╫ש╫ñ╫ץ╫⌐ (╫¢╫¬╫ש╫ס ╫₧╫£╫נ/╫ק╫í╫¿ ╫ץ╫¢╫ץ').
                        final isPinpointTarget =
                            state.pinpointHighlightIndex == index &&
                                state.pinpointHighlightText != null &&
                                state.pinpointHighlightText!.isNotEmpty;
                        final hasPinpoint =
                            state.pinpointHighlightIndex != null;
                        final effectiveSearchText = isPinpointTarget
                            ? state.pinpointHighlightText!
                            : (hasPinpoint ? '' : state.searchText);
                        final effectiveSearchMode =
                            hasPinpoint ? SearchMode.exact : state.searchMode;
                        final effectiveSearchOptions = hasPinpoint
                            ? const <String, Map<String, bool>>{}
                            : state.searchOptions;
                        final effectiveAlternativeWords = hasPinpoint
                            ? const <int, List<String>>{}
                            : state.alternativeWords;
                        final effectiveSpacingValues = hasPinpoint
                            ? const <String, String>{}
                            : state.spacingValues;
                        final effectiveSearchDistance =
                            hasPinpoint ? 0 : state.searchDistance;

                        final textWidget = SmartTextWidget(
                          text: dataWithLinks,
                          widgetKey: ValueKey(
                              'html_${widget.tab.book.title}_$primaryLineIndex'),
                          settings: RenderSettings(
                            removeNikud: state.removeNikud,
                            removePunctuation: state.removePunctuation,
                            removeTeamim: !settingsState.showTeamim,
                            replaceHolyNames: settingsState.replaceHolyNames,
                            searchText: effectiveSearchText,
                            searchOptions: effectiveSearchOptions,
                            alternativeWords: effectiveAlternativeWords,
                            spacingValues: effectiveSpacingValues,
                            isFuzzySearch:
                                effectiveSearchMode == SearchMode.fuzzy,
                            searchMode: effectiveSearchMode,
                            searchDistance: effectiveSearchDistance,
                            fontSize: widget.textSize,
                            fontFamily: settingsState.fontFamily,
                            lineHeight: settingsState.lineHeight,
                          ),
                          onOpenBook: widget.openBookCallback,
                        );

                        final constrainedText = textMaxWidth > 0
                            ? Center(
                                child: ConstrainedBox(
                                  constraints:
                                      BoxConstraints(maxWidth: textMaxWidth),
                                  child: textWidget,
                                ),
                              )
                            : textWidget;

                        if (notesForLine.isEmpty) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(width: 16),
                              Expanded(child: constrainedText),
                            ],
                          );
                        }

                        final note = notesForLine.first;
                        final indicator = Tooltip(
                          message: note.contentPlain,
                          child: GestureDetector(
                            onTap: () {
                              _addTextBookEventIfOpen(
                                UpdateSelectedIndex(primaryLineIndex),
                              );
                              _addTextBookEventIfOpen(
                                  HighlightLine(primaryLineIndex));
                              if (widget.onOpenPersonalNotes != null) {
                                widget.onOpenPersonalNotes!.call();
                              } else {
                                _addTextBookEventIfOpen(
                                  const ToggleLeftPane(true),
                                );
                              }
                            },
                            onLongPress: () {
                              showDialog<void>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('╫פ╫ó╫¿╫פ ╫£╫⌐╫ץ╫¿╫פ ╫צ╫ץ'),
                                  content: PersonalNoteContentView(note: note),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(),
                                      child: const Text('╫í╫ע╫ץ╫¿'),
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
                        );

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            indicator,
                            Expanded(child: constrainedText),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
              builder: (context, selectedText, child) {
                final contextMenuIndex = continuous && !segment.isHeader
                    ? _currentSelectedIndex.value
                    : primaryLineIndex;
                return AppContextMenuRegion(
                  menuBuilder: (menuCtx, tapPos) => _buildContextMenuForIndex(
                    state,
                    contextMenuIndex != null &&
                            segment.containsLine(contextMenuIndex)
                        ? contextMenuIndex
                        : primaryLineIndex,
                    menuCtx,
                    selectedText,
                    tapPos,
                  ),
                  child: child!,
                );
              },
            ),
          ),
        ),
        // ╫פ╫₧╫ñ╫¿╫⌐╫ש╫¥ - ╫£╫£╫נ SelectionArea ╫á╫ñ╫¿╫ף, ╫¢╫ש ╫ש╫⌐ SelectionArea ╫¢╫£╫£╫ש
        if (widget.showCommentaryAsExpansionTiles &&
            isSelected &&
            _hasCommentaries(state, selectedLineIndex))
          _CommentaryCard(
            key: ValueKey('commentary_card_$selectedLineIndex'),
            index: selectedLineIndex,
            textSize: widget.textSize,
            openBookCallback: widget.openBookCallback,
            viewportHeight: _viewportHeight,
            selectionSyncController: widget.selectionSyncController,
          ),
      ],
    );
  }

  Widget _buildContinuousSegmentText({
    required ReadingSegment segment,
    required TextBookLoaded state,
    required SettingsState settingsState,
    required TextStyle baseTextStyle,
  }) {
    final paragraphLines = _buildContinuousParagraphLines(
      segment: segment,
      state: state,
      settingsState: settingsState,
      baseTextStyle: baseTextStyle,
    );

    return ContinuousReadingParagraph(
      lines: paragraphLines,
      baseStyle: baseTextStyle,
      onTapUrl: (url) => HtmlLinkHandler.handleLink(
        context,
        url,
        (tab) => widget.openBookCallback(tab),
      ),
      onLineTap: (lineIndex) {
        final isLineSelected = state.selectedIndex == lineIndex;
        _focusNode.requestFocus();
        _savedSelectedText.value = null;
        _savedSelectedIndex.value = null;
        _currentSelectedIndex.value = lineIndex;
        widget.onSelectedTextChanged?.call(null);
        if (isLineSelected) {
          _addTextBookEventIfOpen(const UpdateSelectedIndex(null));
        } else {
          _addTextBookEventIfOpen(UpdateSelectedIndex(lineIndex));
        }
      },
      onLineSecondaryTap: (lineIndex) {
        _currentSelectedIndex.value = lineIndex;
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
      if (lineIndex < 0 || lineIndex >= widget.data.length) {
        continue;
      }
      final backgroundColor = state.highlightedLine == lineIndex
          ? colorScheme.secondaryContainer.withValues(alpha: 0.4)
          : state.selectedIndex == lineIndex
              ? colorScheme.primary.withValues(alpha: 0.08)
              : null;
      final style = backgroundColor == null
          ? baseTextStyle
          : baseTextStyle.copyWith(backgroundColor: backgroundColor);
      final htmlText = _continuousLineHtml(
        widget.data[lineIndex],
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
    var textWithLinks = rawText;
    if (settingsState.enableHtmlLinks) {
      try {
        final linksForLine = state.links
            .where((link) =>
                link.index1 == lineIndex + 1 &&
                link.start != null &&
                link.end != null)
            .toList();
        if (linksForLine.isNotEmpty) {
          textWithLinks = addInlineLinksToText(rawText, linksForLine);
        }
      } catch (_) {
        textWithLinks = rawText;
      }
    }

    final isPinpointTarget = state.pinpointHighlightIndex == lineIndex &&
        state.pinpointHighlightText != null &&
        state.pinpointHighlightText!.isNotEmpty;
    final hasPinpoint = state.pinpointHighlightIndex != null;
    final effectiveSearchText = isPinpointTarget
        ? state.pinpointHighlightText!
        : (hasPinpoint ? '' : state.searchText);
    final Map<String, Map<String, bool>> effectiveSearchOptions =
        hasPinpoint ? const <String, Map<String, bool>>{} : state.searchOptions;
    final effectiveAlternativeWords =
        hasPinpoint ? const <int, List<String>>{} : state.alternativeWords;
    final effectiveSpacingValues =
        hasPinpoint ? const <String, String>{} : state.spacingValues;
    final effectiveSearchMode =
        hasPinpoint ? SearchMode.exact : state.searchMode;
    final effectiveSearchDistance = hasPinpoint ? 0 : state.searchDistance;

    return TextRendererService.processText(
      textWithLinks.trim(),
      RenderSettings(
        removeNikud: state.removeNikud,
        removePunctuation: state.removePunctuation,
        removeTeamim: !settingsState.showTeamim,
        replaceHolyNames: settingsState.replaceHolyNames,
        searchText: effectiveSearchText,
        searchOptions: effectiveSearchOptions,
        alternativeWords: effectiveAlternativeWords,
        spacingValues: effectiveSpacingValues,
        isFuzzySearch: effectiveSearchMode == SearchMode.fuzzy,
        searchMode: effectiveSearchMode,
        searchDistance: effectiveSearchDistance,
        fontSize: widget.textSize,
        fontFamily: settingsState.fontFamily,
        lineHeight: settingsState.lineHeight,
      ),
    );
  }

  /// ╫ס╫ף╫ש╫º╫פ ╫נ╫¥ ╫ש╫⌐ ╫₧╫ñ╫¿╫⌐╫ש╫¥ ╫£╫נ╫ש╫á╫ף╫º╫í ╫₧╫í╫ץ╫ש╫¥
  bool _hasCommentaries(TextBookLoaded state, int index) {
    // ╫ס╫ף╫ש╫º╫פ ╫נ╫¥ ╫ש╫⌐ ╫º╫ש╫⌐╫ץ╫¿╫ש╫¥ ╫¿╫£╫ץ╫ץ╫á╫ר╫ש╫ש╫¥ ╫£╫נ╫ש╫á╫ף╫º╫í ╫פ╫צ╫פ
    final lineLinks = state.linksByLine[index + 1];
    if (lineLinks == null || lineLinks.isEmpty) return false;

    final activeCommentatorsSet = state.activeCommentators.toSet();
    String? lastPath;
    String? lastTitle;

    return lineLinks.any((link) {
      final type = link.connectionType.toUpperCase();
      if (type != "COMMENTARY" && type != "TARGUM") return false;
      if (link.path2 != lastPath) {
        lastPath = link.path2;
        lastTitle = utils.getTitleFromPath(link.path2);
      }
      return lastTitle != null && activeCommentatorsSet.contains(lastTitle!);
    });
  }

  @override
  Widget build(BuildContext context) {
    return buildKeyboardListener();
  }

  // [EDITING DISABLED]
  // /// Opens the text editor for a specific paragraph
  // void _editParagraph(int paragraphIndex) {
  //   if (paragraphIndex >= 0 && paragraphIndex < widget.data.length) {
  //     context.read<TextBookBloc>().add(OpenEditor(index: paragraphIndex));
  //   }
  // }
}

class _CommentaryCard extends StatefulWidget {
  final int index;
  final double textSize;
  final Function(OpenedTab) openBookCallback;
  final double viewportHeight;
  final SelectionSyncController? selectionSyncController;

  const _CommentaryCard({
    super.key,
    required this.index,
    required this.textSize,
    required this.openBookCallback,
    required this.viewportHeight,
    this.selectionSyncController,
  });

  @override
  State<_CommentaryCard> createState() => _CommentaryCardState();
}

class _CommentaryCardState extends State<_CommentaryCard> {
  final GlobalKey<CommentaryListBaseState> _commentaryKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    // ╫ק╫ש╫⌐╫ץ╫ס ╫ע╫ץ╫ס╫פ ╫פ╫₧╫ñ╫¿╫⌐╫ש╫¥ ╫£╫ñ╫ש ╫ע╫ץ╫ס╫פ ╫פ╫ס╫£╫ץ╫º ╫ס╫ñ╫ץ╫ó╫£ (╫£╫נ ╫¢╫£ ╫פ╫₧╫í╫ת):
    // ╫פ╫₧╫ñ╫¿╫⌐╫ש╫¥ ╫ש╫פ╫ש╫ץ 75% ╫₧╫ע╫ץ╫ס╫פ ╫פ╫ס╫£╫ץ╫º
    // ╫פ╫⌐╫נ╫¿ (25%) ╫ש╫¬╫ק╫£╫º: 15% ╫£╫₧╫ó╫£╫פ (╫ר╫º╫í╫ר), 10% ╫£╫₧╫ר╫פ (╫ר╫º╫í╫ר)
    final maxHeight = widget.viewportHeight > 0
        ? widget.viewportHeight * 0.75
        : MediaQuery.of(context).size.height * 0.75;

    return LayoutBuilder(
      builder: (context, constraints) {
        return BlocBuilder<SettingsBloc, SettingsState>(
          builder: (context, settingsState) {
            // ╫⌐╫ש╫₧╫ץ╫⌐ ╫ס╫נ╫ץ╫¬╫ץ ╫¿╫ץ╫ק╫ס ╫₧╫º╫í╫ש╫₧╫£╫ש ╫¢╫₧╫ץ ╫פ╫ר╫º╫í╫ר
            var textMaxWidth = settingsState.textMaxWidth;

            // ╫נ╫¥ ╫פ╫ó╫¿╫ת ╫⌐╫£╫ש╫£╫ש, ╫צ╫ץ ╫¿╫₧╫פ ╫⌐╫ª╫¿╫ש╫ת ╫£╫ק╫⌐╫ס ╫£╫ñ╫ש ╫ע╫ץ╫ף╫£ ╫פ╫₧╫í╫ת
            if (textMaxWidth < 0) {
              final level = (-textMaxWidth).toInt();
              final widthPercent = 1.0 - (level * 0.05);
              textMaxWidth = constraints.maxWidth * widthPercent;
            }

            final commentaryContainer = Container(
              margin: const EdgeInsets.only(bottom: 8.0),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: maxHeight,
                    minHeight: 50, // ╫₧╫ש╫á╫ש╫₧╫ץ╫¥ ╫ע╫ץ╫ס╫פ ╫£╫₧╫á╫ש╫ó╫¬ ╫ס╫ó╫ש╫ץ╫¬ layout
                  ),
                  child: CommentaryListBase(
                    key: _commentaryKey,
                    indexes: [widget.index],
                    fontSize: widget.textSize,
                    openBookCallback: widget.openBookCallback,
                    showSearch: false,
                    selectionSyncController: widget.selectionSyncController,
                    shrinkWrap: true,
                  ),
                ),
              ),
            );

            // ╫נ╫¥ ╫ש╫⌐ ╫¿╫ץ╫ק╫ס ╫₧╫º╫í╫ש╫₧╫£╫ש, ╫á╫₧╫¿╫¢╫צ ╫נ╫¬ ╫פ╫₧╫ñ╫¿╫⌐╫ש╫¥ ╫ס╫נ╫ץ╫¬╫ץ ╫¿╫ץ╫ק╫ס ╫¢╫₧╫ץ ╫פ╫ר╫º╫í╫ר
            if (textMaxWidth > 0) {
              return Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: textMaxWidth),
                  child: commentaryContainer,
                ),
              );
            }
            return commentaryContainer;
          },
        );
      },
    );
  }
}

class _CopySelectedTextIntent extends Intent {
  const _CopySelectedTextIntent();
}
