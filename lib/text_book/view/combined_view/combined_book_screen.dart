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

/// פריט "בחר מפרשים מרובים" יוצג כשיש callback `onOpenCommentatorsPaneWithFilter`
/// וטאב המפרשים אינו פעיל בחלונית הצד. הכלל זהה גם במצב "מפרשים מתחת":
/// אם המשתמש כבר פתח את חלונית הצד על המפרשים, אין צורך בפריט.
///
/// בניגוד ל-[shouldShowOpenCommentatorsPaneEntry], הפריט הזה לא תלוי
/// ב-`hasSelectedCommentators` — מטרתו לאפשר בחירה גם כשהבחירה ריקה.
@visibleForTesting
bool shouldShowSelectCommentatorsEntry({
  required bool hasOpenCommentatorsPaneWithFilterCallback,
  required bool isCommentatorsTabActive,
}) {
  return hasOpenCommentatorsPaneWithFilterCallback && !isCommentatorsTabActive;
}

/// קובע האם צריך לבנות מחדש את ה-SelectionArea החיצוני בתגובה לשינוי בעלות
/// ב-[SelectionSyncController]. הבנייה מחדש מתבצעת על-ידי קידום ערך
/// `_selectionAreaRevision` ששימש כ-`ValueKey` של ה-SelectionArea — ולכן
/// היא משחזרת את כל עץ הצאצאים, כולל `_CommentaryCard` במצב 'מפרשים מתחת'.
///
/// מטרת הבנייה היא לנקות בחירה ויזואלית של ה-SelectionArea שלנו כשאזור אחר
/// תפס בעלות. אם אין לנו בחירה משלנו — אין מה לנקות, ו-rebuild רק יהרוס
/// את עץ הצאצאים (במצב 'מפרשים מתחת' זה גורם לטעינה מחדש של המפרשים בכל
/// פעם שמנסים לסמן בהם טקסט).
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
  // שמירת הטקסט הנבחר האחרון
  final ValueNotifier<String?> _savedSelectedText =
      ValueNotifier<String?>(null);
  // שמירת האינדקס של השורה שממנה הטקסט הודגש
  final ValueNotifier<int?> _savedSelectedIndex = ValueNotifier<int?>(null);
  // שמירת reference ל-BLoC לשימוש ב-listeners
  late final TextBookBloc _textBookBloc;

  bool _hasScrolledToInitialPosition = false;

  // מנהל בחירת טקסט משופר
  late final TextSelectionManager _selectionManager;

  int _selectionAreaRevision = 0;
  final Object _selectionOwner = Object();

  // listener לניקוי בחירה - נשמור אותו כדי להסיר אותו ב-dispose
  void _onSelectionModeChanged() {
    if (!_selectionManager.isInSelectionMode && mounted) {
      // כשיוצאים ממצב בחירה, קוראים ל-setState כדי לכפות בנייה מחדש
      // של SelectionArea ולנקות את הבחירה באופן ויזואלי.
      setState(() {});
    }
  }

  /// פתיחת חלון הצד של המפרשים רק אם מוסיפים מפרשים ומפרשים מוגדרים בצד הטקסט (לא מתחת)
  void _openCommentatorsPane({required bool isAdding}) {
    if (isAdding &&
        !widget.showCommentaryAsExpansionTiles &&
        widget.onOpenCommentatorsPane != null) {
      widget.onOpenCommentatorsPane!();
    }
  }

  late final FocusNode _focusNode;

  bool _didRequestInitialFocus = false;

  // שמירת גובה הבלוק בפועל לחישובים דינאמיים
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
    // שמירת ה-BLoC מראש
    _textBookBloc = context.read<TextBookBloc>();

    // אתחול מנהל הבחירה
    _selectionManager = TextSelectionManager();

    // האזנה לשינויים במצב הבחירה כדי לכפות rebuild של SelectionArea
    _selectionManager.addListener(_onSelectionModeChanged);
    widget.selectionSyncController?.addListener(_handleExternalSelectionChange);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context
          .read<PersonalNotesBloc>()
          .add(LoadPersonalNotes(widget.tab.book.title));
    });

    // האזנה לשינויים במיקומי הפריטים כדי לאפס את הבחירה בגלילה
    widget.tab.positionsListener.itemPositions.addListener(_onScroll);
    // עדכון האינדקס ב-tab בזמן אמת
    widget.tab.positionsListener.itemPositions.addListener(_updateTabIndex);

    // האזנה לשינויים ב-state כדי לגלול למיקום הנכון בפעם הראשונה
    _textBookBloc.stream.listen((state) {
      if (state is TextBookLoaded &&
          !_hasScrolledToInitialPosition &&
          state.visibleIndices.isNotEmpty) {
        _hasScrolledToInitialPosition = true;
        final initialIndex = state.visibleIndices.first;
        debugPrint('DEBUG: גלילה אוטומטית למיקום שמור: $initialIndex');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && widget.tab.scrollController.isAttached) {
            unawaited(_scrollToSourceLine(initialIndex));
          }
        });
      }
    });

    // מוודא שהפוקוס מגיע לאזור הקריאה מיד אחרי פתיחת ספר
    // כדי שגלילה בחיצים תעבוד בלי לחיצה בעכבר, אך בלי לגנוב פוקוס משדות טקסט.
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

  // עדכון האינדקס הנוכחי ב-tab
  void _updateTabIndex() {
    final positions = widget.tab.positionsListener.itemPositions.value;
    if (positions.isNotEmpty) {
      // שומר את האינדקס של הפריט הראשון הנראה
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

  // פונקציה שתשלח אירוע איפוס ל-selectedIndex אם יש גלילה משמעותית
  void _onScroll() {
    // אנחנו רוצים את הלוגיקה הזו רק בתצוגה המפוצלת (SimpleBookView לשעבר)
    // שבה המפרשים מוצגים בפאנל צד (כלומר: לא ExpansionTiles)
    if (widget.showCommentaryAsExpansionTiles) return;

    final state = _textBookBloc.state;
    if (state is! TextBookLoaded) return;

    final currentSelectedIndex = state.selectedIndex;

    if (currentSelectedIndex != null) {
      // אם האינדקס הנבחר כבר לא נראה (האינדקסים הנראים שונו עקב גלילה)
      final visibleIndices = state.visibleIndices;
      if (!visibleIndices.contains(currentSelectedIndex)) {
        _addTextBookEventIfOpen(const UpdateSelectedIndex(null));
      }
    }
  }

  // מעקב אחר האינדקס הנוכחי שנבחר (לשימוש בהעתקה עם כותרות)
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

  /// helper קטן שמחזיר רשימת AppContextMenuEntry מקבוצה אחת
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
        label: 'הצג את כל $groupName',
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

  // בניית תפריט קונטקסט לאינדקס ספציפי של פסקה
  List<AppContextMenuEntry> _buildContextMenuForIndex(
      TextBookLoaded state,
      int paragraphIndex,
      BuildContext menuContext,
      String? selectedText,
      Offset tapPosition) {
    // מצב תצוגה מקדימה — תפריט מינימלי
    if (widget.isPreviewMode) {
      return [
        AppContextMenuEntry(
          label: 'העתק',
          icon: FluentIcons.copy_24_regular,
          enabled: selectedText != null && selectedText.trim().isNotEmpty,
          onTap: () => _copyFormattedText(selectedText),
        ),
      ];
    }

    final groups = state.commentatorGroups;
    final tanachGroup = CommentatorGroup.groupByTitle(groups, 'תורה שבכתב');
    final chazalGroup = CommentatorGroup.groupByTitle(groups, 'חז"ל');
    final rishonimGroup = CommentatorGroup.groupByTitle(groups, 'ראשונים');
    final acharonimGroup = CommentatorGroup.groupByTitle(groups, 'אחרונים');
    final modernGroup = CommentatorGroup.groupByTitle(groups, 'מחברי זמננו');
    final ungroupedGroup = CommentatorGroup.groupByTitle(groups, 'שאר מפרשים');

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
          label: 'פתח מפרשים בחלונית צד',
          onTap: () {
            _selectParagraphForContextMenu(paragraphIndex);
            _openCommentatorsPane(isAdding: true);
          },
        ),
      if (shouldShowSelectEntry)
        AppContextMenuEntry(
          label: 'פתח בחירת מפרשים בחלונית צד',
          onTap: () {
            _selectParagraphForContextMenu(paragraphIndex);
            widget.onOpenCommentatorsPaneWithFilter!();
          },
        ),
      if (shouldShowOpenPaneEntry || shouldShowSelectEntry)
        const AppContextMenuEntry.divider(),
      AppContextMenuEntry(
        label: 'הצג את כל המפרשים',
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
              label: 'פתח קישורים בחלונית צד',
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
        // החיפוש עובד תמיד על טקסט ללא ניקוד וטעמים — מנקים פעם אחת
        // לשימוש גם בתווית התפריט וגם בשאילתת החיפוש בפועל.
        final rawText = selectedText?.trim() ?? '';
        final cleanedText = utils.hasNikud(rawText)
            ? utils.removeVolwels(rawText).trim()
            : rawText;
        final hasSelectedText = cleanedText.isNotEmpty;
        final preview = hasSelectedText ? previewForLabel(cleanedText) : '';
        return AppContextMenuEntry(
          label: 'חיפוש',
          icon: FluentIcons.search_24_regular,
          enabled: hasSelectedText,
          children: hasSelectedText
              ? [
                  AppContextMenuEntry(
                    label: "חפש '$preview' בספר זה",
                    icon: FluentIcons.book_search_24_regular,
                    onTap: () =>
                        widget.openLeftPaneTab(1, searchText: cleanedText),
                  ),
                  AppContextMenuEntry(
                    label: "חפש '$preview' בכל הספרים",
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
        label: 'מפרשים',
        icon: FluentIcons.book_24_regular,
        enabled: state.availableCommentators.isNotEmpty,
        children: commentatorChildren,
      ),
      AppContextMenuEntry(
        label: 'קישורים',
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
        label: 'הוסף הערה אישית',
        icon: FluentIcons.note_add_24_regular,
        onTap: () => _showNoteEditor(selectedText),
      ),
      AppContextMenuEntry(
        label: 'דווח על טעות בספר',
        icon: FluentIcons.error_circle_24_regular,
        onTap: () => _openErrorReportDialog(
          selectedText ?? '',
          fallbackLineIndex: paragraphIndex,
        ),
      ),
      const AppContextMenuEntry.divider(),
      AppContextMenuEntry(
        label: 'העתק',
        icon: FluentIcons.copy_24_regular,
        enabled: selectedText != null && selectedText.trim().isNotEmpty,
        onTap: () => _copyFormattedText(selectedText),
      ),
      AppContextMenuEntry(
        label: 'העתק את כל הפסקה',
        icon: FluentIcons.document_copy_24_regular,
        enabled: paragraphIndex >= 0 && paragraphIndex < widget.data.length,
        onTap: () => _copyParagraphByIndex(paragraphIndex),
      ),
      AppContextMenuEntry(
        label: 'העתק טקסט מוצג',
        icon: FluentIcons.document_copy_24_regular,
        onTap: _copyVisibleText,
      ),
      // פריטי תפריט מפלאגינים
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

  /// פתיחת דיאלוג דיווח על טעות בספר
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

  /// העתקת פסקה לפי אינדקס (משתמש ב־widget.data[index] ומייצר גם HTML)
  Future<void> _copyParagraphByIndex(int index) async {
    if (index < 0 || index >= widget.data.length) return;

    final text = widget.data[index];
    if (text.trim().isEmpty) return;

    // קבלת ההגדרות הנוכחיות
    final settingsState = context.read<SettingsBloc>().state;
    final textBookState = context.read<TextBookBloc>().state;

    final removeNikud =
        textBookState is TextBookLoaded && textBookState.removeNikud;
    final processedText = removeNikud ? utils.removeVolwels(text) : text;

    final plainText = utils.stripHtmlIfNeeded(processedText);

    String finalText = plainText;
    String finalHtmlText = processedText;

    // אם צריך להוסיף כותרות
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

  /// העתקת הטקסט המוצג במסך ללוח
  void _copyVisibleText() async {
    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded || state.visibleIndices.isEmpty) return;

    // איסוף כל הטקסט הנראה במסך
    final visibleTexts = <String>[];
    for (final index in state.visibleIndices) {
      if (index >= 0 && index < widget.data.length) {
        visibleTexts.add(widget.data[index]);
      }
    }

    if (visibleTexts.isEmpty) return;

    final combinedText = visibleTexts.join('\n\n');

    // קבלת ההגדרות הנוכחיות
    final settingsState = context.read<SettingsBloc>().state;

    String finalText = combinedText;

    // אם צריך להוסיף כותרות
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

  /// עיצוב טקסט כ-HTML עם הגדרות הגופן הנוכחיות
  String _formatTextAsHtml(String text) {
    final settingsState = context.read<SettingsBloc>().state;
    return CopyUtils.buildStyledHtml(
      htmlText: text,
      fontFamily: settingsState.fontFamily,
      fontSize: widget.textSize,
    );
  }

  /// העתקת טקסט מעוצב (HTML) ללוח
  Future<void> _copyFormattedText([String? capturedText]) async {
    final plainText = capturedText ?? _savedSelectedText.value;

    debugPrint('_copyFormattedText called with: "$plainText"');
    debugPrint('_currentSelectedIndex: ${_currentSelectedIndex.value}');

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
        selectedIndex: _currentSelectedIndex.value,
        sourceContent: widget.data,
        textBookState: textBookState,
        settingsState: settingsState,
        fontFamily: settingsState.fontFamily,
        fontSize: widget.textSize,
      );
    } catch (e) {
      if (mounted) {
        UiSnack.showError('שגיאה בהעתקה מעוצבת: $e');
      }
    }
  }

  /// הצגת עורך ההערות
  Future<void> _showNoteEditor([String? capturedText]) async {
    final state = _textBookBloc.state;
    if (state is! TextBookLoaded) return;

    final selectedText = capturedText ?? _savedSelectedText.value;

    // משתמש בשורה שממנה הודגש טקסט (אם קיים), אחרת בשורה הנבחרת, אחרת בשורה הראשונה הנראית
    final currentIndex = _savedSelectedIndex.value ??
        state.selectedIndex ??
        (state.visibleIndices.isNotEmpty ? state.visibleIndices.first : 0);

    // קבלת הטקסט המזהה של השורה - אם יש טקסט נבחר, משתמשים בו (אחרי הסרת ניקוד), אחרת בטקסט המזהה (כמו שיוצג ככותרת)
    final referenceText = selectedText?.trim().isNotEmpty == true
        ? removeHebrewDiacritics(selectedText!.trim())
        : extractDisplayTextFromLines(
            state.content,
            currentIndex + 1,
            excludeBookTitle: widget.tab.book.title,
          );

    // טען טיוטה אם קיימת
    final draftService = PersonalNoteDraftService();
    final draft = await draftService.loadDraft(
      bookId: widget.tab.book.title,
      lineNumber: currentIndex + 1,
    );

    if (!mounted) return;

    // שלח event לפתיחת מצב יצירה בסיידבר
    context.read<PersonalNotesBloc>().add(StartCreatingPersonalNote(
          bookId: widget.tab.book.title,
          lineNumber: currentIndex + 1,
          referenceText: referenceText,
          selectedText: selectedText?.trim(),
          initialContent: draft?.content ?? '',
          initialFormat:
              draft?.contentFormat ?? PersonalNoteContentFormat.plain,
        ));

    // פתח את חלונית ההערות
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
            // שומר את גובה הבלוק בפועל לשימוש בחישובי הגלילה
            _viewportHeight = constraints.maxHeight;
            final settingsState = context.watch<SettingsBloc>().state;
            final readingSegments =
                _readingSegmentsForMode(settingsState.continuousReadingMode);

            return SelectionArea(
              key: ValueKey('combined_selection_$_selectionAreaRevision'),
              // SelectionArea אחד לכל הרשימה - מאפשר בחירה רציפה בין פסקאות
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
                // כניסה למצב בחירה כשיש טקסט נבחר
                if (!_selectionManager.isInSelectionMode) {
                  // שימוש באינדקס העליון הנראה במקום 0
                  _selectionManager.setAnchor(topmostVisibleIndex(
                      widget.tab.positionsListener.itemPositions.value));
                }

                // חשוב: כדי ש-Ctrl+C יעבוד מיד אחרי סימון טקסט עם העכבר
                // נוודא שהפוקוס נמצא על אזור הקריאה.
                _focusNode.requestFocus();

                // מחשב את מספר השורה המדויק של הטקסט המודגש
                // משתמש באותה לוגיקה כמו בדיווח שגיאות
                final TextBookLoaded? loadedState =
                    _textBookBloc.state is TextBookLoaded
                        ? _textBookBloc.state as TextBookLoaded
                        : null;
                int? foundIndex;
                var fixedPlain = plain;

                if (loadedState != null) {
                  final settingsState = context.read<SettingsBloc>().state;
                  // מקבל את השורה הראשונה הנראית
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

                  // מוצא את המיקום של הטקסט המודגש
                  final selectionStart = visibleText.indexOf(fixedPlain);

                  if (selectionStart >= 0) {
                    // סופר כמה שורות יש לפני הטקסט המודגש
                    final before = visibleText.substring(0, selectionStart);
                    final offset = '\n'.allMatches(before).length;
                    foundIndex = baseIndex + offset;
                  }

                  // fallback: אם לא הצלחנו לחשב אינדקס, נשתמש בשורה שנבחרה (אם קיימת)
                  foundIndex ??= loadedState.selectedIndex;
                }

                if (mounted) {
                  _savedSelectedText.value = fixedPlain;
                  _savedSelectedIndex.value = foundIndex;
                  _currentSelectedIndex.value = foundIndex;
                  widget.onSelectedTextChanged?.call(fixedPlain);

                  // שליחת event לפלאגינים עם ה-index המדויק
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
                    // macOS (למקרה שמריצים שם)
                    LogicalKeySet(
                      LogicalKeyboardKey.meta,
                      LogicalKeyboardKey.keyC,
                    ): const _CopySelectedTextIntent(),
                    // Esc לניקוי בחירה
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
                          // ניקוי הבחירה ב-SelectionArea
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
        // הטקסט של הספר - ללא SelectionArea נפרד, כי יש SelectionArea כללי
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          decoration: backgroundColor != null
              ? BoxDecoration(color: backgroundColor)
              : null,
          child: EnhancedGestureDetector(
            behavior: HitTestBehavior.translucent,
            onDragSelectionStart: () {
              // כניסה למצב בחירה בגלל drag
              if (!_selectionManager.isInSelectionMode) {
                _selectionManager.setAnchor(actionLineIndex());
              }
            },
            onSingleTap: () {
              if (continuous && !segment.isHeader) {
                return;
              }
              _focusNode.requestFocus();
              // מאפס את הטקסט השמור כשלוחצים על הפסקה
              if (mounted) {
                _savedSelectedText.value = null;
                _savedSelectedIndex.value = null;
                _currentSelectedIndex.value = null;
                widget.onSelectedTextChanged?.call(null);
              }
              // פשוט מעדכן את selectedIndex - זה יגרום לבנייה מחדש
              if (isSelected) {
                _addTextBookEventIfOpen(const UpdateSelectedIndex(null));
              } else {
                _addTextBookEventIfOpen(UpdateSelectedIndex(primaryLineIndex));

                // גלילה אוטומטית כך שהקטע יהיה בראש העמוד
                // רק אם יש מפרשים להצגה ואנחנו במצב ExpansionTiles
                if (widget.showCommentaryAsExpansionTiles &&
                    _hasCommentaries(state, primaryLineIndex)) {
                  // מחכים שה-UI יתעדכן עם פתיחת המפרש, ואז קופצים למיקום
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    Future.delayed(const Duration(milliseconds: 300), () {
                      if (mounted && widget.tab.scrollController.isAttached) {
                        // גלילה חכמה: נגלול כך שהטקסט הבא (index + 1) יהיה בתחתית
                        // המפרשים תופסים עד 75% מהבלוק
                        // נרצה שהטקסט הבא יהיה ב-90% מהבלוק (כלומר 10% מלמטה)
                        // כך נוודא שרואים: 15% טקסט למעלה, 75% מפרשים, 10% טקסט למטה
                        final nextIndex =
                            (index + 1).clamp(0, widget.data.length - 1);
                        widget.tab.scrollController.scrollTo(
                          index: nextIndex,
                          alignment:
                              0.9, // הטקסט הבא יהיה ב-90% מלמעלה (כלומר 10% מלמטה)
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
              // Double-click → בחירת פסקה שלמה
              // הערה: SelectionArea של Flutter לא תומך בבחירה פרוגרמטית,
              // לכן הפיצ'ר הזה לא מומש במלואו. SelectionArea יבצע את פעולת
              // ברירת המחדל שלו (בחירת מילה). לבחירת פסקה, המשתמש יכול
              // להשתמש ב-Shift+Click או Drag.
              _focusNode.requestFocus();
              _selectionManager.enterDoubleClickMode(actionLineIndex());
            },
            onShiftClick: () {
              // Shift+Click → בחירת טווח
              _focusNode.requestFocus();
              if (!_selectionManager.hasAnchor()) {
                // אם אין anchor, קובעים אותו
                _selectionManager.setAnchor(actionLineIndex());
              }
              // SelectionArea יטפל בבחירת הטווח
            },
            onSecondaryTapDown: (details) {
              // שומר את האינדקס הנוכחי לשימוש בתפריט ההקשר
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

                        // אם הערך שלילי, זו רמה שצריך לחשב לפי גודל המסך
                        // למשל -2 = רמה 2 = 90% מרוחב המסך
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

                        // הוספת קישורים מבוססי תווים לפני כל עיבוד אחר
                        // כי start/end מתייחסים לטקסט המקורי
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
                            // אם יש שגיאה, פשוט נשתמש בטקסט המקורי
                            dataWithLinks = data;
                          }
                        }

                        // הדגשה ממוקדת מקישור עומק: רק על הסעיף שצוין, ובלי
                        // להפעיל את שאר אפשרויות החיפוש (כתיב מלא/חסר וכו').
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
                                  title: const Text('הערה לשורה זו'),
                                  content: PersonalNoteContentView(note: note),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(),
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
        // המפרשים - ללא SelectionArea נפרד, כי יש SelectionArea כללי
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

  /// בדיקה אם יש מפרשים לאינדקס מסוים
  bool _hasCommentaries(TextBookLoaded state, int index) {
    // בדיקה אם יש קישורים רלוונטיים לאינדקס הזה
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
    // חישוב גובה המפרשים לפי גובה הבלוק בפועל (לא כל המסך):
    // המפרשים יהיו 75% מגובה הבלוק
    // השאר (25%) יתחלק: 15% למעלה (טקסט), 10% למטה (טקסט)
    final maxHeight = widget.viewportHeight > 0
        ? widget.viewportHeight * 0.75
        : MediaQuery.of(context).size.height * 0.75;

    return LayoutBuilder(
      builder: (context, constraints) {
        return BlocBuilder<SettingsBloc, SettingsState>(
          builder: (context, settingsState) {
            // שימוש באותו רוחב מקסימלי כמו הטקסט
            var textMaxWidth = settingsState.textMaxWidth;

            // אם הערך שלילי, זו רמה שצריך לחשב לפי גודל המסך
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
                    minHeight: 50, // מינימום גובה למניעת בעיות layout
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

            // אם יש רוחב מקסימלי, נמרכז את המפרשים באותו רוחב כמו הטקסט
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
