import 'dart:async';

import 'package:flutter/material.dart';
import 'package:otzaria/text_book/utils/visible_index.dart';

import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/widgets/text/rtl_selection_shortcuts.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/widgets/misc/direct_link_menu_entries.dart';
import 'package:otzaria/widgets/misc/link_context_menu_entry.dart';
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
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/personal_notes/personal_notes_system.dart';
import 'package:otzaria/utils/text/copy_utils.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:otzaria/utils/text/global_search_helper.dart';
import 'package:otzaria/utils/text/ref_helper.dart';
import 'package:otzaria/utils/text/text_with_inline_links.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/widgets/feedback/scrollable_positioned_list_scrollbar.dart';
import 'package:otzaria/widgets/smart_text/smart_text.dart';
import 'package:otzaria/text_book/view/selection/text_selection_manager.dart';
import 'package:otzaria/text_book/view/selection/selection_sync_controller.dart';
import 'package:otzaria/text_book/view/selection/enhanced_gesture_detector.dart';
import 'package:otzaria/text_book/view/selection/selection_persistence.dart';
import 'package:otzaria/text_book/view/selection/selection_hit_test.dart';
import 'package:otzaria/text_book/view/selection/selected_text_copy.dart';
import 'package:otzaria/text_book/view/selection/selected_text_restore.dart';
import 'package:otzaria/text_book/view/error_report_dialog.dart';
import 'package:otzaria/tools/dictionary/dictionary_context_menu_entries.dart';
import 'package:otzaria/tools/dictionary/repository/dictionary_lookup_repository.dart';
import 'package:otzaria/utils/text/word_at_position.dart';
import 'package:otzaria/plugins/services/context_menu_registry.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/utils/fluent_icon_resolver.dart';
import 'package:otzaria/text_book/utils/inline_notes_utils.dart'
    as inline_notes;
import 'package:otzaria/text_book/utils/note_inline_render.dart';
import 'package:otzaria/text_book/utils/reading_segments.dart';
import 'package:otzaria/text_book/utils/reading_segment_navigation.dart';
import 'package:otzaria/text_book/view/widgets/continuous_reading_paragraph.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/utils/text/html_link_handler.dart';

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
  final void Function(String? text, int? lineIndex, int? column)?
      onSelectedTextChanged;
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

  // מיון לפי סדר הדורות (כמו במפרשים ובחלונית הקישורים).
  // מיון סינכרוני מהמטמון - הדורות נטענים מראש ב-BLoC בעת טעינת הקישורים.
  return CommentaryService.sortLinksByEraSync(visibleLinks);
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

/// מחזירה האם לשורה [index] יש מפרשים להצגה במצב "מפרשים מתחת".
///
/// מתחשבת גם במפרש ההערות הוירטואלי ([kNotesCommentatorTitle]): אם הוא
/// פעיל ויש הערות inline בשורה, יש מה להציג — גם כשאין קישורי מפרשים
/// אמיתיים. אחרת בודקת קישורי COMMENTARY/TARGUM למפרשים הפעילים.
@visibleForTesting
bool hasCommentariesForLine({
  required List<String> activeCommentators,
  required List<String> content,
  required Map<int, List<Link>> linksByLine,
  required int index,
}) {
  if (activeCommentators.contains(kNotesCommentatorTitle) &&
      inline_notes.notesForLines(content, [index]).isNotEmpty) {
    return true;
  }

  final lineLinks = linksByLine[index + 1];
  if (lineLinks == null || lineLinks.isEmpty) return false;

  final activeCommentatorsSet = activeCommentators.toSet();
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

/// מעבד טקסט גולמי לפי הגדרות התצוגה (טעמים/ניקוד/פיסוק), כך שפעולות
/// "העתק את כל הפסקה" ו"העתק טקסט מוצג" ישקפו את מה שמוצג בפועל על המסך —
/// באותו סדר עיבוד של [TextRendererService] (טעמים → ניקוד → פיסוק).
///
/// הערה: [utils.removeVolwels] מסיר גם ניקוד וגם טעמים, ולכן כש-[removeNikud]
/// פעיל הטעמים מוסרים ממילא ללא תלות ב-[showTeamim].
@visibleForTesting
String applyDisplayTextPreferences({
  required String text,
  required bool removeNikud,
  required bool removePunctuation,
  required bool showTeamim,
}) {
  var processed = text;
  if (!showTeamim) {
    processed = utils.removeTeamim(processed);
  }
  if (removeNikud) {
    processed = utils.removeVolwels(processed);
  }
  if (removePunctuation) {
    processed = utils.removePunctuation(processed);
  }
  return processed;
}

class _CombinedViewState extends State<CombinedView> {
  // שמירת הטקסט הנבחר האחרון
  final ValueNotifier<String?> _savedSelectedText =
      ValueNotifier<String?>(null);
  // שמירת האינדקס של השורה שממנה הטקסט הודגש
  final ValueNotifier<int?> _savedSelectedIndex = ValueNotifier<int?>(null);
  // טווח אינדקסי השורות שבתוך הבחירה הנוכחית (כולל הקצוות). משמש כדי שלחיצה
  // ימנית ברווח שבין שורות נבחרות תזוהה כלחיצה "על הבחירה" ולא תבטל אותה.
  int? _selectionLineStart;
  int? _selectionLineEnd;
  // עמודת ההתחלה של הבחירה בשורה הראשונה (רמז לזיהוי מופע נכון בטקסט חוזר).
  int? _selectionStartColumn;
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
    // רישום למיקוד אזור הקריאה במעבר טאב (לא ב-preview שאינו טאב פעיל).
    if (!widget.isPreviewMode) {
      FocusRepository().registerTabContentFocusRequester(widget.tab, () {
        if (_focusNode.canRequestFocus) _focusNode.requestFocus();
      });
    }
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
            unawaited(_scrollToSourceLine(state, initialIndex));
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
    if (!widget.isPreviewMode) {
      FocusRepository().unregisterTabContentFocusRequester(widget.tab);
    }
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
      _selectionLineStart = null;
      _selectionLineEnd = null;
      _selectionStartColumn = null;
    });
    widget.onSelectedTextChanged?.call(null, null, null);
  }

  /// האם יש לשמר את הבחירה בלחיצה ימנית בנקודה [globalPosition] על השורה
  /// [lineIndex], כאשר [lineContext] הוא ה-context של אותה שורה (לאיתור הפסקה).
  ///
  /// שומר את הבחירה כאשר הלחיצה נופלת על הטקסט המסומן בפועל — כולל הרווח שבין
  /// שורות-תצוגה של אותה שורת-מקור שנשברה (wrap), שמגושר ע"י
  /// `includeLineSpacingMiddle`. לחיצה על חלק לא-מסומן בשורה מחזירה `false` כדי
  /// שהבחירה תתבטל (כמו בתוכנה רגילה). כשהבדיקה הגאומטרית אינה ניתנת להכרעה
  /// (טקסט HTML מורכב וכו') חוזרים לברירת מחדל סלחנית — שמירת הבחירה כל עוד
  /// השורה בטווח, כדי לא לבטל בטעות.
  bool _shouldPreserveSelectionAt(
    Offset globalPosition,
    int lineIndex,
    BuildContext lineContext,
  ) {
    final start = _selectionLineStart;
    final end = _selectionLineEnd;
    if (start == null || end == null) return false;
    final lo = start <= end ? start : end;
    final hi = start <= end ? end : start;
    if (lineIndex < lo || lineIndex > hi) return false; // שורה מחוץ לבחירה

    final selectedText = _savedSelectedText.value;
    if (selectedText == null || selectedText.isEmpty) {
      return false; // אין בחירה פעילה — אין מה לשמר
    }
    final root = lineContext.findRenderObject();
    if (root == null) {
      return true; // יש בחירה אך אי אפשר לבדוק גאומטרית — סלחני
    }

    final segments = selectedText.split('\n');
    final offsetInRange = lineIndex - lo;
    final segment = (offsetInRange >= 0 && offsetInRange < segments.length)
        ? segments[offsetInRange]
        : selectedText;
    final edge = lo == hi
        ? SelectionSegmentEdge.substring
        : lineIndex == lo
            ? SelectionSegmentEdge.suffix
            : lineIndex == hi
                ? SelectionSegmentEdge.prefix
                : SelectionSegmentEdge.full;

    final onSelection = clickIsOnRenderedSelection(
      root: root,
      globalPosition: globalPosition,
      selectedSegment: segment,
      edge: edge,
      segmentStartHint: _selectionStartColumn,
    );
    return onSelection ?? true; // לא הוכרע — סלחני
  }

  // עדכון האינדקס הנוכחי ב-tab — חייב להמיר segmentIndex לשורת מקור.
  void _updateTabIndex() {
    final positions = widget.tab.positionsListener.itemPositions.value;
    if (positions.isEmpty) return;

    final state = _textBookBloc.state;
    if (state is! TextBookLoaded) return;

    final visiblePositions = positions
        .where(
          (position) =>
              position.itemTrailingEdge > 0 && position.itemLeadingEdge < 1,
        )
        .toList()
      ..sort((a, b) => a.itemLeadingEdge.compareTo(b.itemLeadingEdge));
    final source = visiblePositions.isNotEmpty ? visiblePositions : positions;

    if (!state.continuousReadingMode || state.readingSegments.isEmpty) {
      widget.tab.index = source.first.index;
      return;
    }
    // במצב רציף — translate segmentIndex לשורת מקור ראשונה
    final segmentIndex = source.first.index;
    if (segmentIndex >= 0 && segmentIndex < state.readingSegments.length) {
      widget.tab.index = state.readingSegments[segmentIndex].startLineIndex;
    }
  }

  Future<void> _scrollToSourceLine(TextBookLoaded state, int lineIndex) {
    return scrollToSourceLine(
      scrollController: widget.tab.scrollController,
      scrollOffsetController: widget.tab.mainOffsetController,
      positionsListener: widget.tab.positionsListener,
      segments: state.readingSegments,
      lineIndex: lineIndex,
      viewportExtent: _viewportHeight > 0
          ? _viewportHeight
          : (context.size?.height ?? MediaQuery.sizeOf(context).height),
      alignment: 0.05,
      duration: const Duration(milliseconds: 300),
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
        isSelected: groupActive,
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
          isSelected: isActive,
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
          label: 'פתח את חלונית המפרשים',
          icon: FluentIcons.panel_right_24_regular,
          isHighlighted: true,
          onTap: () {
            _selectParagraphForContextMenu(paragraphIndex);
            _openCommentatorsPane(isAdding: true);
          },
        ),
      if (shouldShowSelectEntry)
        AppContextMenuEntry(
          label: 'בחר מפרשים מרובים',
          icon: FluentIcons.filter_24_regular,
          isHighlighted: true,
          onTap: () {
            _selectParagraphForContextMenu(paragraphIndex);
            widget.onOpenCommentatorsPaneWithFilter!();
          },
        ),
      if (shouldShowOpenPaneEntry || shouldShowSelectEntry)
        const AppContextMenuEntry.divider(),
      AppContextMenuEntry(
        label: 'הצג את כל המפרשים',
        isSelected: allActive,
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
          ...paragraphLinks.map((link) => buildLinkContextMenuEntry(
                link: link,
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
          enabled: true,
          // ללא טקסט נבחר: פתיחת חיפוש רגיל בספר ללא שאילתה.
          onTap: hasSelectedText ? null : () => widget.openLeftPaneTab(1),
          children: hasSelectedText
              ? [
                  AppContextMenuEntry(
                    label: "חפש '$preview' בספר זה",
                    labelWidget: buildSearchMenuLabel(
                      selectedText: cleanedText,
                      suffix: 'בספר זה',
                    ),
                    icon: FluentIcons.search_24_regular,
                    onTap: () =>
                        widget.openLeftPaneTab(1, searchText: cleanedText),
                  ),
                  AppContextMenuEntry(
                    label: "חפש '$preview' בכל הספרים",
                    labelWidget: buildSearchMenuLabel(
                      selectedText: cleanedText,
                      suffix: 'בכל הספרים',
                    ),
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
      if (!state.book.isUserBook)
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
      // העתק קישור ישיר — מוצג רק אם יש book_id
      if (state.book.id != null) ...[
        const AppContextMenuEntry.divider(),
        AppContextMenuEntry(
          label: 'העתק קישור ישיר',
          icon: FluentIcons.link_24_regular,
          childrenBuilder: () => buildDirectLinkContextMenuEntries(
            bookId: state.book.id!,
            index: paragraphIndex,
            selectedText: selectedText,
          ),
        ),
      ],
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

  /// מחלץ את העדפות התצוגה מה-state ומעבד את הטקסט בהתאם, כך שההעתקה
  /// תשקף את מה שמוצג בפועל על המסך — בדיוק כמו [TextRendererService].
  String _applyDisplayTextPreferences(
    String text,
    TextBookState textBookState,
    SettingsState settingsState,
  ) {
    final removeNikud =
        textBookState is TextBookLoaded && textBookState.removeNikud;
    final removePunctuation =
        textBookState is TextBookLoaded && textBookState.removePunctuation;

    return applyDisplayTextPreferences(
      text: text,
      removeNikud: removeNikud,
      removePunctuation: removePunctuation,
      showTeamim: settingsState.showTeamim,
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

    final processedText =
        _applyDisplayTextPreferences(text, textBookState, settingsState);

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

    // קבלת ההגדרות הנוכחיות
    final settingsState = context.read<SettingsBloc>().state;

    // איסוף כל הטקסט הנראה במסך — עם אותן העדפות תצוגה (טעמים/ניקוד/פיסוק)
    // שמיושמות בפועל על המסך, כדי שההעתקה תשקף את מה שמוצג.
    final visibleTexts = <String>[];
    for (final index in state.visibleIndices) {
      if (index >= 0 && index < widget.data.length) {
        visibleTexts.add(
          _applyDisplayTextPreferences(
              widget.data[index], state, settingsState),
        );
      }
    }

    if (visibleTexts.isEmpty) return;

    final combinedText = visibleTexts.join('\n\n');
    final plainText = utils.stripHtmlIfNeeded(combinedText);

    String finalText = plainText;
    String finalHtmlText = combinedText;

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
        originalText: plainText,
        copyWithHeaders: settingsState.copyWithHeaders,
        copyHeaderFormat: settingsState.copyHeaderFormat,
        bookName: bookName,
        currentPath: currentPath,
      );

      finalHtmlText = CopyUtils.formatTextWithHeaders(
        originalText: combinedText,
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
          selectionColumn: _selectionStartColumn,
          initialContent: draft?.content ?? '',
          initialFormat:
              draft?.contentFormat ?? PersonalNoteContentFormat.plain,
        ));

    // פתח את חלונית ההערות
    widget.onOpenPersonalNotes?.call();
  }

  /// טיפול בלחיצה על סימון הערה אישית inline: מדגיש את השורה ופותח את החלונית.
  void _onInlineNoteTap(int lineIndex) {
    _addTextBookEventIfOpen(UpdateSelectedIndex(lineIndex));
    _addTextBookEventIfOpen(HighlightLine(lineIndex));
    // פותחים את ההערה עצמה בחלונית, גם אם מוגדר "סגור כברירת מחדל".
    context
        .read<PersonalNotesBloc>()
        .add(RequestExpandNotesForLine(lineIndex + 1));
    if (widget.onOpenPersonalNotes != null) {
      widget.onOpenPersonalNotes!.call();
    } else {
      _addTextBookEventIfOpen(const ToggleLeftPane(true));
    }
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
            context.watch<SettingsBloc>().state;

            return RtlSelectionShortcuts(
                child: SelectionArea(
              key: ValueKey('combined_selection_$_selectionAreaRevision'),
              // SelectionArea אחד לכל הרשימה - מאפשר בחירה רציפה בין פסקאות
              contextMenuBuilder: (context, selectableRegionState) {
                return const SizedBox.shrink();
              },
              onSelectionChanged: (selection) {
                final plain = selection?.plainText;
                // עדכון מעקב כיוון הגרירה (ל-RtlSelectionShortcuts).
                trackRtlSelection(plain);
                // שינוי בחירה זמני בזמן priming — לא לעבד.
                if (rtlSelectionPriming) return;
                if (!shouldPersistSelectedText(plain)) {
                  widget.selectionSyncController?.clear(_selectionOwner);
                  _selectionManager.exitSelectionMode();
                  _savedSelectedText.value = null;
                  _selectionLineStart = null;
                  _selectionLineEnd = null;
                  _selectionStartColumn = null;
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
                    // טווח השורות שהבחירה משתרעת עליהן — לזיהוי סלחני של לחיצה
                    // ימנית על הבחירה (כולל ברווח שבין שורות נבחרות).
                    _selectionLineStart = foundIndex;
                    _selectionLineEnd =
                        foundIndex + '\n'.allMatches(fixedPlain).length;
                    // עמודת ההתחלה של הבחירה בשורה הראשונה — רמז לזיהוי המופע
                    // הנכון כאשר אותו טקסט חוזר באותה שורה.
                    _selectionStartColumn =
                        selectionStart - (before.lastIndexOf('\n') + 1);
                  } else {
                    _selectionLineStart = null;
                    _selectionLineEnd = null;
                    _selectionStartColumn = null;
                  }

                  // fallback: אם לא הצלחנו לחשב אינדקס, נשתמש בשורה שנבחרה (אם קיימת)
                  foundIndex ??= loadedState.selectedIndex;
                }

                if (mounted) {
                  _savedSelectedText.value = fixedPlain;
                  _savedSelectedIndex.value = foundIndex;
                  _currentSelectedIndex.value = foundIndex;
                  widget.onSelectedTextChanged
                      ?.call(fixedPlain, foundIndex, _selectionStartColumn);

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
                    ClearSelectionIntent: CallbackAction<ClearSelectionIntent>(
                      onInvoke: (_) {
                        _selectionManager.exitSelectionMode();
                        // ניקוי הבחירה ב-SelectionArea
                        _savedSelectedText.value = null;
                        _savedSelectedIndex.value = null;
                        _currentSelectedIndex.value = null;
                        _selectionLineStart = null;
                        _selectionLineEnd = null;
                        _selectionStartColumn = null;
                        widget.onSelectedTextChanged?.call(null, null, null);
                        return null;
                      },
                    ),
                  },
                  child: widget.isPreviewMode
                      ? Scrollbar(
                          controller: _previewScrollController,
                          thumbVisibility: true,
                          thickness: 8.0,
                          radius: const Radius.circular(4.0),
                          child: ListView.builder(
                            controller: _previewScrollController,
                            itemCount: state.readingSegments.isNotEmpty
                                ? state.readingSegments.length
                                : widget.data.length,
                            itemBuilder: (context, index) {
                              return buildExpansiomTile(
                                ExpansibleController(),
                                index,
                                state,
                                const <int, List<PersonalNote>>{},
                              );
                            },
                          ),
                        )
                      : ScrollablePositionedListScrollbar(
                          scrollController: widget.tab.scrollController,
                          itemPositionsListener: widget.tab.positionsListener,
                          itemCount: state.readingSegments.isNotEmpty
                              ? state.readingSegments.length
                              : widget.data.length,
                          labelForIndex: state.tableOfContents.isEmpty
                              ? null
                              : (index) {
                                  // במצב קריאה רציף האינדקס הוא אינדקס
                                  // סגמנט; ממירים לשורת המקור כדי שמיפוי
                                  // ה-TOC (שמבוסס על מספרי שורות) יהיה נכון.
                                  final segments = state.readingSegments;
                                  final lineIndex = segments.isNotEmpty
                                      ? (index >= 0 && index < segments.length
                                          ? segments[index].startLineIndex
                                          : index)
                                      : index;
                                  final ref = refFromTocList(
                                      lineIndex, state.tableOfContents);
                                  return addBookTitleToRef(
                                      ref, state.book.title);
                                },
                          child: ProgressiveScroll(
                            focusNode: _focusNode,
                            maxSpeed: 10000.0,
                            curve: 10.0,
                            accelerationFactor: 5,
                            scrollController: widget.tab.mainOffsetController,
                            itemScrollController: widget.tab.scrollController,
                            child: BlocBuilder<PersonalNotesBloc,
                                PersonalNotesState>(
                              builder: (context, notesState) {
                                final noteMap = <int, List<PersonalNote>>{};
                                if (notesState.bookId == state.book.title) {
                                  for (final note in notesState.locatedNotes) {
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
                                );
                              },
                            ),
                          ),
                        ),
                ),
              ),
            ));
          },
        );
      },
    );
  }

  Widget buildOuterList(
    TextBookLoaded state,
    Map<int, List<PersonalNote>> noteMap,
  ) {
    // ה-ListView מאכלס itemCount=segments — במצב הרגיל זה 1:1 לשורות,
    // במצב רציף זה מספר הפסקאות. תרגום widget.tab.index (שורת מקור) →
    // segmentIndex לפני העברה ל-`initialScrollIndex`.
    final initialIndex = state.readingSegments.isNotEmpty
        ? segmentIndexForLine(state.readingSegments, widget.tab.index)
        : widget.tab.index;
    final itemCount = state.readingSegments.isNotEmpty
        ? state.readingSegments.length
        : widget.data.length;
    final clampedInitial =
        itemCount == 0 ? 0 : initialIndex.clamp(0, itemCount - 1);

    return ScrollablePositionedList.builder(
      key: ValueKey('combined-${widget.tab.book.title}'),
      initialScrollIndex: clampedInitial,
      itemPositionsListener: widget.tab.positionsListener,
      itemScrollController: widget.tab.scrollController,
      scrollOffsetController: widget.tab.mainOffsetController,
      itemCount: itemCount,
      itemBuilder: (context, index) {
        ExpansibleController controller = ExpansibleController();
        // מבודד את שכבת הצביעה של כל פריט - rebuild של פריט בודד (בחירה/
        // הדגשה) או emit של warming לא יצבע מחדש את כל ה-viewport.
        return RepaintBoundary(
          child: buildExpansiomTile(
            controller,
            index,
            state,
            noteMap,
          ),
        );
      },
    );
  }

  Widget buildExpansiomTile(
    ExpansibleController controller,
    int index,
    TextBookLoaded state,
    Map<int, List<PersonalNote>> noteMap,
  ) {
    // [index] הוא segmentIndex; ה-segment הזה עשוי לעטוף כמה שורות מקור.
    // במצב הרגיל זה 1:1 (segment.startLineIndex == index, sourceLineIndices=[index]).
    final segment =
        state.readingSegments.isNotEmpty && index < state.readingSegments.length
            ? state.readingSegments[index]
            : null;
    final primaryLineIndex = segment?.startLineIndex ?? index;
    final isContinuousParagraph = state.continuousReadingMode &&
        segment != null &&
        !segment.isHeader &&
        segment.sourceLineIndices.length > 1;

    // ריבוי-בחירה: הקטע נחשב נבחר אם שורת מקור כלשהי שבו נמצאת ב-selectedIndices.
    int? selectedLineInSegment;
    for (final selected in state.selectedIndices) {
      final inSegment =
          segment?.containsLine(selected) ?? (selected == primaryLineIndex);
      if (inSegment) {
        selectedLineInSegment = selected;
        break;
      }
    }
    final isSelected = selectedLineInSegment != null;
    final selectedLineIndex = selectedLineInSegment ?? primaryLineIndex;
    int actionLineIndex() {
      final currentIndex = _currentSelectedIndex.value;
      if (isContinuousParagraph &&
          currentIndex != null &&
          segment.containsLine(currentIndex)) {
        return currentIndex;
      }
      return selectedLineIndex;
    }

    final isHighlighted = state.highlightedLine != null &&
        (segment?.containsLine(state.highlightedLine!) ??
            state.highlightedLine == primaryLineIndex);
    // permanentHighlightLine מדגיש רקע צהוב כאשר אין highlightText (?mark בלבד)
    final isPermanentHighlight = state.permanentHighlightLine != null &&
        (segment?.containsLine(state.permanentHighlightLine!) ??
            state.permanentHighlightLine == primaryLineIndex) &&
        state.highlightText.isEmpty;
    final notesForLine =
        noteMap[primaryLineIndex + 1] ?? const <PersonalNote>[];

    final theme = Theme.of(context);
    final backgroundColor = () {
      // במצב רציף ההדגשה תיעשה בתוך הפסקה (לכל שורה הצבע שלה),
      // כך שאין צבע רקע לכלל ה-tile.
      if (isContinuousParagraph) return null;
      if (isPermanentHighlight) {
        return AppColors.permanentHighlight;
      }
      if (isHighlighted) {
        return theme.colorScheme.secondaryContainer.withValues(alpha: 0.4);
      }
      if (isSelected) {
        return theme.colorScheme.primary.withValues(alpha: 0.08);
      }
      return null;
    }();

    return Column(
      key: PageStorageKey(
          'segment-${segment?.startLineIndex ?? primaryLineIndex}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // הטקסט של הספר - ללא SelectionArea נפרד, כי יש SelectionArea כללי
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          // decoration קבוע (גם כשהצבע null) — מעבר null<->BoxDecoration היה
          // מוסיף/מסיר DecoratedBox ומשנה את עומק הטקסט ב-tree, מה שאיפס מצב
          // <details> פתוח (טקסט מוסתר) בכל בחירת שורה.
          decoration: BoxDecoration(color: backgroundColor),
          child: EnhancedGestureDetector(
            behavior: HitTestBehavior.translucent,
            onDragSelectionStart: () {
              // כניסה למצב בחירה בגלל drag
              if (!_selectionManager.isInSelectionMode) {
                _selectionManager.setAnchor(actionLineIndex());
              }
            },
            onSingleTap: () {
              // במצב רציף, לחיצה רגילה על פסקה לא בוחרת שורה — הלחיצה
              // הספציפית מטופלת בתוך ContinuousReadingParagraph (recognizer לכל שורה).
              if (isContinuousParagraph) {
                return;
              }
              _focusNode.requestFocus();
              // מאפס את הטקסט השמור כשלוחצים על הפסקה
              if (mounted) {
                _savedSelectedText.value = null;
                _savedSelectedIndex.value = null;
                _currentSelectedIndex.value = null;
                _selectionLineStart = null;
                _selectionLineEnd = null;
                _selectionStartColumn = null;
                widget.onSelectedTextChanged?.call(null, null, null);
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
            onCtrlClick: () {
              // Ctrl+Click → הוספה/הסרה של הקטע מבחירה מרובה (ללא גלילה אוטומטית)
              if (isContinuousParagraph) {
                return;
              }
              _focusNode.requestFocus();
              _addTextBookEventIfOpen(
                UpdateSelectedIndex(primaryLineIndex, additive: true),
              );
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
                padding: const EdgeInsets.symmetric(vertical: 4.0),
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

                        // במצב רציף — פסקה מכמה שורות מקור.
                        if (isContinuousParagraph) {
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

                        // איסוף קישורי inline (start/end מתייחסים לטקסט המקורי)
                        List<Link> linksForLine = const [];
                        if (settingsState.enableHtmlLinks) {
                          try {
                            linksForLine = state.links
                                .where((link) =>
                                    link.index1 == primaryLineIndex + 1 &&
                                    link.start != null &&
                                    link.end != null)
                                .toList();
                          } catch (e) {
                            linksForLine = const [];
                          }
                        }

                        // הזרקת סימוני הערות אישיות (וקישורי inline) ל-HTML.
                        final dataWithLinks = buildAnnotatedLineHtml(
                          rawLine: data,
                          notesForLine: notesForLine,
                          lineIndex0: primaryLineIndex,
                          underlineColor: Theme.of(context).colorScheme.primary,
                          inlineLinks: linksForLine,
                        );

                        // הדגשת טקסט ממוקד: highlightText מופעל רק בשורה permanentHighlightLine
                        final textWidget = SmartTextWidget(
                          text: dataWithLinks,
                          widgetKey: ValueKey(
                              'html_${widget.tab.book.title}_$primaryLineIndex'),
                          settings: RenderSettings(
                            removeNikud: state.removeNikud,
                            removePunctuation: state.removePunctuation,
                            removeTeamim: !settingsState.showTeamim,
                            replaceHolyNames: settingsState.replaceHolyNames,
                            searchText: (state.highlightText.isNotEmpty &&
                                    state.permanentHighlightLine == index)
                                ? state.highlightText
                                : state.searchText,
                            highlightYellowBackground:
                                state.highlightText.isNotEmpty &&
                                    state.permanentHighlightLine == index,
                            searchOptions: state.searchOptions,
                            alternativeWords: state.alternativeWords,
                            spacingValues: state.spacingValues,
                            isFuzzySearch: state.searchMode == SearchMode.fuzzy,
                            searchMode: state.searchMode,
                            searchDistance: state.searchDistance,
                            fontSize: widget.textSize,
                            fontFamily: settingsState.fontFamily,
                            lineHeight: settingsState.lineHeight,
                          ),
                          onOpenBook: widget.openBookCallback,
                          onNoteTap: notesForLine.isEmpty
                              ? null
                              : (line) => _onInlineNoteTap(line),
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

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(width: 16),
                            Expanded(child: constrainedText),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
              builder: (context, selectedText, child) {
                return AppContextMenuRegion(
                  // לחיצה ימנית על הטקסט המסומן (כולל הרווח שבין שורות-תצוגה של
                  // שורת-מקור שנשברה) לא תשחרר את הבחירה; לחיצה על חלק לא-מסומן
                  // מבטלת כרגיל.
                  shouldPreserveSelectionOnSecondaryTap: (globalPosition) =>
                      _shouldPreserveSelectionAt(
                          globalPosition, primaryLineIndex, context),
                  menuBuilder: (menuCtx, tapPos) => _buildContextMenuForIndex(
                    state,
                    primaryLineIndex,
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

  // ─── מצב קריאה רציף — רינדור פסקה מ-segment ────────────────────────────
  // הערה: כל הלוגיקה כאן היא רינדור בלבד. החיפוש/קישורים/הניקוד מופעלים
  // על הטקסט המקורי של כל שורה (לפני המיזוג), ורק התוצאות (HTML) מוצגות
  // יחד. כך החיפוש פר-שורה ממשיך לעבוד.

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
      // אותו עיצוב קישורים כמו במצב הרגיל (HtmlWidget): primary + קו תחתון.
      linkStyle: TextStyle(
        color: Theme.of(context).colorScheme.primary,
        decoration: TextDecoration.underline,
      ),
      onTapUrl: (url) async {
        await HtmlLinkHandler.handleLink(
          context,
          url,
          (tab) => widget.openBookCallback(tab),
        );
        return true;
      },
      onLineTap: (lineIndex) {
        final isCtrl = HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed;
        _focusNode.requestFocus();
        _savedSelectedText.value = null;
        _savedSelectedIndex.value = null;
        _currentSelectedIndex.value = lineIndex;
        _selectionLineStart = null;
        _selectionLineEnd = null;
        _selectionStartColumn = null;
        widget.onSelectedTextChanged?.call(null, null, null);
        if (isCtrl) {
          _addTextBookEventIfOpen(
            UpdateSelectedIndex(lineIndex, additive: true),
          );
        } else if (state.selectedIndex == lineIndex) {
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
          : state.selectedIndices.contains(lineIndex)
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
    return hasCommentariesForLine(
      activeCommentators: state.activeCommentators,
      content: state.content,
      linksByLine: state.linksByLine,
      index: index,
    );
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
                    fontSize: settingsState.commentatorsFontSize,
                    openBookCallback: widget.openBookCallback,
                    showSearch: false,
                    selectionSyncController: widget.selectionSyncController,
                    shrinkWrap: true,
                  ),
                ),
              ),
            );

            // מרכוז אופקי בלבד (topCenter) באותו רוחב כמו הטקסט. Center מלא
            // היה ממרכז גם אנכית וגורם לרווח למעלה כשהמפרשים מכווצים/קצרים.
            if (textMaxWidth > 0) {
              return Align(
                alignment: Alignment.topCenter,
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
