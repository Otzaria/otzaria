import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/data/book_identity.dart';
import 'package:otzaria/text_book/models/book_notes.dart';
import 'package:otzaria/text_book/view/widgets/selection_gutter_painter.dart';
import 'package:otzaria/shortcuts/dynamic/dynamic_shortcut.dart';
import 'package:otzaria/text_book/utils/reader_paragraph_copy.dart';
import 'package:otzaria/text_book/utils/reader_menu_entries.dart';
import 'package:otzaria/text_book/utils/reader_plugin_menu_entries.dart';
import 'package:otzaria/book_common/utils/commentators_menu.dart';
import 'package:otzaria/text_display/view/copy_as_menu.dart';

import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter/gestures.dart' show kPrimaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:otzaria/text_book/view/reading_viewport/line_scroll_controller.dart';
import 'package:otzaria/text_book/view/reading_viewport/reading_scrollbar_label.dart';

import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/widgets/lists/scroll_position_reanchor.dart';
import 'package:otzaria/widgets/text/rtl_selection_shortcuts.dart';
import 'package:otzaria/widgets/text/selection_copy_shortcuts.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/widgets/misc/smooth_wheel_scroll.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/book_common/models/commentator_group.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/models/commentary_scroll_request.dart';
import 'package:otzaria/text_book/view/commentary_list_base.dart';
import 'package:otzaria/text_book/view/sibling_commentaries_menu.dart';
import 'package:otzaria/utils/ui/context_menu_utils.dart';
import 'package:otzaria/widgets/misc/progressive_scrolling.dart';
import 'package:positioned_sliver_list/positioned_list.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/utils/navigation/talmud_bavli_open_format.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/personal_notes/personal_notes_system.dart';
import 'package:otzaria/personal_notes/widgets/personal_notes_sidebar.dart';
import 'package:otzaria/personal_notes/utils/personal_note_source_selection.dart';
import 'package:otzaria/bookmarks/utils/section_bookmark.dart';
import 'package:otzaria/core/messages/text_book_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/widgets/feedback/scrollable_positioned_list_scrollbar.dart';
import 'package:otzaria/widgets/layout/reading_area_width.dart';
import 'package:otzaria/widgets/selection/item_selection_container.dart';
import 'package:otzaria/widgets/smart_text/smart_text.dart';
import 'package:otzaria/text_book/view/selection/text_selection_manager.dart';
import 'package:otzaria/text_book/view/selection/selection_sync_controller.dart';
import 'package:otzaria/text_book/utils/reader_build_policy.dart';
import 'package:otzaria/text_book/view/selection/enhanced_gesture_detector.dart';
import 'package:otzaria/text_book/view/selection/selection_persistence.dart';
import 'package:otzaria/book_common/selection/selection_hit_test.dart';
import 'package:otzaria/text_book/view/selection/selected_text_copy.dart';
import 'package:otzaria/book_common/selection/selected_text_restore.dart';
import 'package:otzaria/book_common/selection/commentary_selection.dart';
import 'package:otzaria/book_protection/models/book_protection.dart';
import 'package:otzaria/book_protection/utils/copy_guard.dart';
import 'package:otzaria/text_book/view/error_report_dialog.dart';
import 'package:otzaria/text_book/view/widgets/book_source_banner.dart';
import 'package:otzaria/tools/dictionary/repository/dictionary_lookup_repository.dart';
import 'package:otzaria/tools/dictionary/widgets/laaz_commentary_subblock.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/services/plugin_correction_session_service.dart';
import 'package:otzaria/plugins/view/plugin_correction_paragraph.dart';
import 'package:otzaria/plugins/services/plugin_highlight_reveal_service.dart';
import 'package:otzaria/plugins/models/plugin_book_identity.dart';
import 'package:otzaria/text_book/utils/commentators_context_menu.dart';
import 'package:otzaria/text_book/utils/inline_notes_utils.dart'
    as inline_notes;
import 'package:otzaria/book_common/utils/link_anchor_markers.dart';
import 'package:otzaria/text_book/utils/link_preview_utils.dart';
import 'package:otzaria/text_book/utils/numbered_note_markers.dart';
import 'package:otzaria/widgets/misc/link_preview_overlay.dart';
import 'package:otzaria/text_book/utils/note_inline_render.dart';
import 'package:otzaria/text_book/utils/reading_segments.dart';
import 'package:otzaria/text_book/utils/reading_segment_navigation.dart';
import 'package:otzaria/text_book/utils/section_search_utils.dart';
import 'package:otzaria/text_display/text_display_exports.dart';
import 'package:otzaria/text_book/utils/inline_section_markers.dart';
import 'package:otzaria/text_book/view/reader_line/reader_line_item.dart';
import 'package:otzaria/text_book/view/reader_line/reader_line_render.dart';
import 'package:otzaria/text_book/view/reader_line/reader_line_spec.dart';
import 'package:otzaria/text_book/view/widgets/unloaded_paragraph_placeholder.dart';
import 'package:otzaria/text_book/view/widgets/reading_extent_estimation.dart';
import 'package:otzaria/theme/theme_exports.dart';

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
    this.onOpenCommentaryPersonalNote,
    this.onOpenCommentatorsPane,
    this.onOpenCommentatorsPaneWithFilter,
    this.onCommentaryPaneScrollRequested,
    this.onOpenLinksPane,
    this.isCommentatorsTabActive,
    this.isLinksTabActive,
    this.isPersonalNotesTabActive,
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
  final void Function(Link link, int lineNumber)? onOpenCommentaryPersonalNote;
  final VoidCallback? onOpenCommentatorsPane;
  final VoidCallback? onOpenCommentatorsPaneWithFilter;

  /// לחיצה על עוגן-אות במצב "מפרשים בצד": ההורה מזרים את שם המפרש ואת
  /// [commentaryLinkKey] של הקטע אל פאנל המפרשים, שאינו בעץ הזה.
  final void Function(String title, String linkKey, int? sourceLine)?
  onCommentaryPaneScrollRequested;
  final VoidCallback? onOpenLinksPane;
  final bool Function()? isCommentatorsTabActive;
  final bool Function()? isLinksTabActive;
  final bool Function()? isPersonalNotesTabActive;
  final SelectionSyncController? selectionSyncController;

  @override
  State<CombinedView> createState() => _CombinedViewState();
}

@visibleForTesting
bool shouldOpenPreviewLinkInBook(Link link) =>
    LinkTypes.normalize(link.connectionType) == LinkTypes.linker;

@visibleForTesting
List<String> activatePreviewCommentator({
  required List<String> activeCommentators,
  required Link link,
}) {
  final title = utils.getTitleFromPath(link.path2);
  if (title.isEmpty || activeCommentators.contains(title)) {
    return activeCommentators;
  }
  return [...activeCommentators, title];
}

@visibleForTesting
List<Link> buildCombinedViewContextMenuLinksForParagraph({
  required Map<int, List<Link>> linksByLine,
  required int paragraphIndex,
  List<Link>? queriedLinks,
}) => paragraphReferenceLinks(
  linksByLine: linksByLine,
  paragraphIndex: paragraphIndex,
  queriedLinks: queriedLinks,
);

@visibleForTesting
bool shouldShowPersonalNotePreview({required bool isPersonalNotesTabActive}) =>
    !isPersonalNotesTabActive;

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
  BookNotes? bookNotes,
}) {
  if (activeCommentators.contains(kNotesCommentatorTitle) &&
      inline_notes.notesForLines(content, [
        index,
      ], dbNotes: bookNotes).isNotEmpty) {
    return true;
  }

  final lineLinks = linksByLine[index + 1];
  if (lineLinks == null || lineLinks.isEmpty) return false;

  final activeCommentatorsSet = activeCommentators.toSet();
  String? lastPath;
  String? lastTitle;

  return lineLinks.any((link) {
    if (!LinkTypes.isDependentTextLink(link.connectionType)) return false;
    if (link.path2 != lastPath) {
      lastPath = link.path2;
      lastTitle = utils.getTitleFromPath(link.path2);
    }
    return lastTitle != null && activeCommentatorsSet.contains(lastTitle!);
  });
}

/// מטמון מוגבל לרינדור שורות חלון הבחירה לאורך גרירה אחת.
/// אינו מחזיק את רשימת שורות המקור.
@visibleForTesting
class SelectionLineCache {
  static const _maxLines = 2000;
  // עד 256 KiB של תוכן UTF-16, בנוסף לתקורת המפה והמחרוזות.
  static const _maxCharacters = 128 * 1024;
  int _characters = 0;
  final Map<int, SelectionLine> _lines = {};
  WeakReference<List<String>>? _data;
  RenderSettings? _settings;
  Object? _markerKey;

  /// [injectMarkers] מזריק ציונים; [markerKey] מזהה את נתוניהם והפרופיל,
  /// ונשאר זהה בעדכוני גרירה שאינם משנים אותם.
  SelectionLine Function(int index) lines(
    List<String> data,
    RenderSettings settings, {
    String Function(String rawLine, int index)? injectMarkers,
    Object? markerKey,
  }) {
    if (!identical(_data?.target, data) ||
        _settings != settings ||
        _markerKey != markerKey) {
      clear();
      _data = WeakReference(data);
      _settings = settings;
      _markerKey = markerKey;
    }
    SelectionLine render(int i) => renderSelectionLineWithMarkers(
      rawText: injectMarkers?.call(data[i], i) ?? data[i],
      settings: settings,
    );
    return (i) {
      final cached = _lines[i];
      if (cached != null) return cached;
      final line = render(i);
      if (_lines.length < _maxLines &&
          _characters + line.text.length <= _maxCharacters) {
        _lines[i] = line;
        _characters += line.text.length;
      }
      return line;
    };
  }

  void clear() {
    _lines.clear();
    _characters = 0;
    _data = null;
    _settings = null;
    _markerKey = null;
  }
}

@visibleForTesting
({
  String text,
  Link? link,
  Future<CommentaryCopyGuard?> Function()? copyGuard,
})?
commentarySelectionForCopy({
  required SelectionSyncController? controller,
  required Object mainTextOwner,
}) {
  final text = controller?.activeSelectionText;
  if (controller == null ||
      identical(controller.activeOwner, mainTextOwner) ||
      text == null ||
      text.trim().isEmpty) {
    return null;
  }
  return (
    text: text,
    link: controller.activeSelectionLink,
    copyGuard: controller.activeCopyGuard,
  );
}

/// מעבד טקסט גולמי לפי פרופיל ערוץ ההעתקה, כך שפעולת "העתק את כל הפסקה"
/// תשקף את מה שמוצג בפועל על המסך.
@visibleForTesting
String applyDisplayTextPreferences({
  required String text,
  required TextDisplayProfile profile,
}) => applyTextDisplayProfile(text, profile);

@visibleForTesting
bool shouldHandleCommentaryScrollTarget({
  required int cardIndex,
  required int targetLineIndex,
}) => cardIndex == targetLineIndex;

/// יעד הגלילה בכרטיס המפרשים שמתחת לשורה: השורה שממנה נלחץ העוגן, המפרש,
/// ומפתח הקטע המדויק שהעוגן מקשר אליו ([commentaryLinkKey]).
typedef _CommentaryScrollTarget = ({
  int lineIndex,
  String title,
  String? linkKey,
});

final _detailsTag = RegExp(r'<details\b', caseSensitive: false);

class _ChildBuilder extends StatelessWidget {
  const _ChildBuilder({required this.builder, required this.child});

  final Widget Function(BuildContext context, Widget child) builder;
  final Widget child;

  @override
  Widget build(BuildContext context) => builder(context, child);
}

// מעבר אנימציה בונה שתי רשימות; scope מבדיל בין עותקי אותו פריט.
class _ParagraphStateKey extends GlobalKey {
  const _ParagraphStateKey(this.scope, this.index) : super.constructor();
  final Object scope;
  final int index;

  @override
  bool operator ==(Object other) =>
      other is _ParagraphStateKey &&
      identical(scope, other.scope) &&
      index == other.index;

  @override
  int get hashCode => Object.hash(identityHashCode(scope), index);
}

class _CombinedViewState extends State<CombinedView> {
  /// מאגר הפוקוס של החלון; נשמר כאן כי ב-dispose אסור לחפש ב-context.
  late final FocusRepository _focus;

  PageStorageBucket _commentaryStorage = PageStorageBucket();
  bool _localCorrectionActive = false;
  bool _anchorHandledCurrentTap = false;
  ParagraphCommentatorsCache _paragraphCommentatorsCache =
      ParagraphCommentatorsCache();

  final ValueNotifier<_CommentaryScrollTarget?> _anchorScrollTargetNotifier =
      ValueNotifier<_CommentaryScrollTarget?>(null);

  // שמירת הטקסט הנבחר האחרון
  final ValueNotifier<String?> _savedSelectedText = ValueNotifier<String?>(
    null,
  );
  // שמירת האינדקס של השורה שממנה הטקסט הודגש
  final ValueNotifier<int?> _savedSelectedIndex = ValueNotifier<int?>(null);
  // הבחירה בלי ציוני המפרשים שהוזרקו לתצוגה, כפי שהיא בשורת המקור.
  SourceSelection? _sourceSelection;
  // טווח אינדקסי השורות שבתוך הבחירה הנוכחית (כולל הקצוות). משמש כדי שלחיצה
  // ימנית ברווח שבין שורות נבחרות תזוהה כלחיצה "על הבחירה" ולא תבטל אותה.
  int? _selectionLineStart;
  int? _selectionLineEnd;
  // עמודת ההתחלה של הבחירה בשורה הראשונה (רמז לזיהוי מופע נכון בטקסט חוזר).
  int? _selectionStartColumn;
  int? _selectionPointerColumn;
  int? _selectionPointerLineIndex;
  // שמירת reference ל-BLoC לשימוש ב-listeners
  late TextBookBloc _textBookBloc;
  StreamSubscription<TextBookState>? _textBookSubscription;

  // תת-התפריט "מפרשים נוספים על הדף" (רק בספרי מפרש).
  late final SiblingCommentariesController _siblingController;

  bool _hasScrolledToInitialPosition = false;

  // הקצאת וריאנט טיפוגרפי קבוע לכל מפרש עם עוגני-מילה. ממוזכר לפי זהות
  // רשימת הקישורים של ה-state (מתחלפת רק כשהקישורים נטענים מחדש).
  List<Link>? _anchorStyleSourceLinks;
  Map<String, int> _anchorStyleCache = const {};

  bool _disposed = false;
  final Map<int, GlobalKey> _commentaryCardKeys = {};
  int? _commentaryRevealLine;
  int _commentaryRevealGeneration = 0;
  bool _commentaryRevealSelectionObserved = false;
  bool _commentaryRevealAtEnd = false;
  HeaderAnchorHandle? _commentaryCardAnchor;

  /// השהיית ריחוף לפני פתיחת חלונית העוגן (מונעת הבהובים במעבר-סמן חולף).
  Timer? _anchorHoverTimer;

  /// מזהה הריחוף הממתין. טעינה אסינכרונית שהתחילה בודקת אותו לאחר ה-await —
  /// ביטול ה-Timer לבדו אינו עוצר טעינה שכבר יצאה לדרך.
  int _anchorHoverGeneration = 0;

  /// ביטול ריחוף ממתין: גם ה-Timer וגם טעינה אסינכרונית שכבר התחילה.
  void _cancelPendingAnchorHover() {
    _anchorHoverTimer?.cancel();
    _anchorHoverGeneration++;
  }

  /// סמן-האות שחלונית התצוגה שלו פתוחה כעת (שורה + אינדקס בשורה) — מודגש בטקסט
  /// כדי לקשר ויזואלית בין הסמן לחלונית.
  int? _activeAnchorLine;
  int? _activeAnchorIndex;

  /// מסמן/מנקה את הסמן הפעיל. נקרא גם מ-onDismissed של החלונית — ולכן חייב
  /// לשרוד קריאה אחרי dispose (ה-dismiss שב-dispose מפעיל את ה-callback).
  void _setActiveAnchor(int? line, int? index) {
    if (_disposed || !mounted) return;
    if (_activeAnchorLine == line && _activeAnchorIndex == index) return;
    setState(() {
      _activeAnchorLine = line;
      _activeAnchorIndex = index;
    });
  }

  Map<String, int> _anchorStyles(TextBookLoaded state) {
    if (!identical(_anchorStyleSourceLinks, state.links)) {
      _anchorStyleSourceLinks = state.links;
      _anchorStyleCache = anchorStyleIndexByCommentator(state.links);
    }
    return _anchorStyleCache;
  }

  /// סמני עוגן-מילה, למשל (א), בנקודה המדויקת בשורה. מוזרקים על שורת המקור
  /// כפי שנשמרה — לפני הזרקות שמוסיפות תוכן גלוי (הערות אישיות וכד'), כי
  /// anchorStart נמדד בתווים גלויים של התוכן השמור. [note] — גוף ההערה
  /// ה-[note] של השורה במקום השורה עצמה.
  String _injectAnchorMarkersForLine(
    String rawLine,
    int lineIndex0,
    TextBookLoaded state, {
    int? note,
  }) {
    if (!state.bodyDisplayProfile.showAnchorMarkers) return rawLine;
    // מהדורה חלופית: העוגנים ממופים לנוסח הראשי — במיקומים שגויים כאן.
    if (state.book.versionTitle != null) return rawLine;
    // linksByLine ולא state.links: סינון על כל קישורי הספר (עשרות אלפים)
    // פר-שורה פר-build מקרטע את הגלילה.
    final anchorLinks = (state.linksByLine[lineIndex0 + 1] ?? const <Link>[])
        .where((link) => link.anchorStart != null)
        .toList();
    if (anchorLinks.isEmpty) return rawLine;
    return injectLinkAnchorMarkers(
      rawLine: rawLine,
      anchorLinks: anchorLinks,
      styleIndexByCommentator: _anchorStyles(state),
      lineIndex: lineIndex0,
      activeIndex: lineIndex0 == _activeAnchorLine ? _activeAnchorIndex : null,
      notes: state.bookNotes.notesAt(lineIndex0),
      note: note,
    );
  }

  /// סמני-מספר מודפסים, למשל (9), בספרים שהערותיהם יושבות בספר "הערות על…"
  /// המקושר כמפרש. רק עטיפה בעוגן — הטקסט הגלוי לא משתנה.
  String _injectNumberedNoteMarkers(
    String rawLine,
    int lineIndex0,
    TextBookLoaded state,
  ) {
    final links = numberedNoteLinks(
      state.linksByLine[lineIndex0 + 1] ?? const <Link>[],
    );
    if (links.isEmpty) return rawLine;
    return addNumberedNoteMarkerLinks(rawLine, lineIndex: lineIndex0);
  }

  /// פענוח `otzaria://anchor?ref=<line>_<i>` לקישור-העוגן, יחד עם השורה
  /// והאינדקס (להדגשת הסמן הפעיל).
  ({Link link, int line, int index})? _anchorLinkFromUrl(String url) {
    final ref = Uri.tryParse(url)?.queryParameters['ref'];
    final parts = ref?.split('_');
    if (parts == null || parts.length != 2) return null;
    final line = int.tryParse(parts[0]);
    final i = int.tryParse(parts[1]);
    if (line == null || i == null) return null;
    final state = _textBookBloc.state;
    if (state is! TextBookLoaded) return null;
    final anchorLinks = (state.linksByLine[line + 1] ?? const <Link>[])
        .where((link) => link.anchorStart != null)
        .toList();
    if (i < 0 || i >= anchorLinks.length) return null;
    return (link: anchorLinks[i], line: line, index: i);
  }

  /// פתיחת יעד התצוגה המקדימה: חלונית מתאימה, או ספר עבור Linker.
  Future<void> _openPreviewDestination(Link link, {int? sourceLine}) async {
    LinkPreviewOverlay.dismiss(window: AppWindowKeys.of(context));
    if (!shouldOpenPreviewLinkInBook(link)) {
      if (sourceLine != null) {
        final state = _textBookBloc.state;
        if (state is! TextBookLoaded ||
            state.selectedIndex != sourceLine ||
            state.selectedIndices.length != 1) {
          _addTextBookEventIfOpen(UpdateSelectedIndex(sourceLine));
        }
      }
      if (LinkTypes.isDependentTextLink(link.connectionType)) {
        final state = _textBookBloc.state;
        if (state is TextBookLoaded) {
          final commentators = activatePreviewCommentator(
            activeCommentators: state.activeCommentators,
            link: link,
          );
          if (!identical(commentators, state.activeCommentators)) {
            _addTextBookEventIfOpen(
              UpdateCommentators(commentators, displayOrderOnly: true),
            );
          }
          if (widget.showCommentaryAsExpansionTiles) {
            final title = utils.getTitleFromPath(link.path2);
            if (title.isNotEmpty) {
              if (sourceLine != null) {
                final target = (
                  lineIndex: sourceLine,
                  title: title,
                  linkKey: commentaryLinkKey(link),
                );
                _anchorScrollTargetNotifier.value = null;
                _anchorScrollTargetNotifier.value = target;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _anchorScrollTargetNotifier.value == target) {
                    _anchorScrollTargetNotifier.value = null;
                  }
                });
              }
            }
            return;
          }
          // מפרשים בצד: הפאנל הוא ווידג'ט אחר בעץ, ולכן הבקשה עוברת דרך ההורה.
          _requestPaneCommentaryScroll(link, sourceLine);
        }
        if (widget.showCommentaryAsExpansionTiles) {
          return;
        }
        final openPane = widget.onOpenCommentatorsPane;
        if (openPane != null) {
          openPane();
          return;
        }
      } else {
        final openPane = widget.onOpenLinksPane;
        if (openPane != null) {
          openPane();
          return;
        }
      }
    }
    await openLinkTarget(link, _openTab);
  }

  /// מבקש מפאנל המפרשים שבצד לגלול לקטע שהעוגן מקשר אליו. שקט כשההורה לא
  /// חיבר קולבק (למשל תצוגה מקדימה של ספר), שם הפאנל אינו קיים כלל.
  void _requestPaneCommentaryScroll(Link link, int? sourceLine) {
    final request = widget.onCommentaryPaneScrollRequested;
    final title = utils.getTitleFromPath(link.path2);
    if (request == null) return;
    if (title.isEmpty) return;
    request(title, commentaryLinkKey(link), sourceLine);
  }

  void _openTab(OpenedTab tab) {
    if (!_disposed) widget.openBookCallback(tab);
  }

  Future<void> _openLinkTarget(Link link) {
    LinkPreviewOverlay.dismiss(window: AppWindowKeys.of(context));
    return openLinkTarget(link, _openTab);
  }

  /// [activeAnchor] — כשהחלונית נפתחה מסמן-אות, הסמן מודגש כל עוד היא פתוחה.
  void _showLinkPreview(
    Link link,
    Offset globalPosition, {
    required bool hoverMode,
    ({int line, int index})? activeAnchor,
  }) {
    final state = _textBookBloc.state;
    final loaded = state is TextBookLoaded ? state : null;
    LinkPreviewOverlay.show(
      context,
      link: link,
      globalPosition: globalPosition,
      hoverMode: hoverMode,
      removeNikud: loaded?.commentaryRemoveNikud,
      removePunctuation: loaded?.commentaryRemovePunctuation,
      maxFontSize: widget.textSize,
      onOpen: () => _openLinkTarget(link),
      onDismissed: activeAnchor == null
          ? null
          : () => _setActiveAnchor(null, null),
    );
    if (activeAnchor != null) {
      _setActiveAnchor(activeAnchor.line, activeAnchor.index);
    }
  }

  /// לחיצה על עוגן מנתבת אותו כמו לחיצה על כותרת חלונית התצוגה.
  bool _handleAnchorTap(String url) {
    final anchor = _anchorLinkFromUrl(url);
    if (anchor == null) return false;
    _anchorHandledCurrentTap = true;
    // מאפסים אחרי 400ms — יותר מה-300ms של EnhancedGestureDetector,
    // כדי שה-onSingleTap המתוזמן לא יבטל את הבחירה שנפתחה.
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _anchorHandledCurrentTap = false;
    });
    _cancelPendingAnchorHover();
    _openPreviewDestination(anchor.link, sourceLine: anchor.line);
    return true;
  }

  /// ריחוף מעל עוגן-מילה — תצוגה מקדימה אחרי השהיה קצרה (מונעת הבהובים
  /// כשהסמן רק חולף). כניסה חוזרת לעוגן מבטלת סגירה מתוזמנת של החלונית.
  void _handleAnchorHover(String url, Offset globalPosition) {
    if (url.startsWith('otzaria://note-marker')) {
      _handleNumberedNoteMarkerHover(url, globalPosition);
      return;
    }
    if (url.startsWith('otzaria://note') &&
        !shouldShowPersonalNotePreview(
          isPersonalNotesTabActive:
              widget.isPersonalNotesTabActive?.call() ?? false,
        )) {
      return;
    }
    LinkPreviewOverlay.cancelScheduledHide(AppWindowKeys.of(context));
    _cancelPendingAnchorHover();

    // סימון העוגן מחליף את MouseRegion ויוצר exit/enter מלאכותיים.
    // הסגירה כבר בוטלה לעיל; אין לתזמן פתיחה מחדש לאותו עוגן.
    final anchor = _anchorLinkFromUrl(url);
    if (anchor != null &&
        anchor.line == _activeAnchorLine &&
        anchor.index == _activeAnchorIndex) {
      return;
    }

    final previewLink = anchor?.link ?? inlineLinkFromPreviewUrl(url);
    if (previewLink != null) prefetchLinkPreview(previewLink);
    _anchorHoverTimer = Timer(const Duration(milliseconds: 280), () {
      if (!_disposed && mounted) {
        _showUrlPreview(url, globalPosition, hoverMode: true);
      }
    });
  }

  /// הקשת מגע על קישור שבמחשב נפתח בריחוף — אותה חלונית, מקובעת מיד.
  void _handleTouchPreview(String url, Offset globalPosition) {
    if (url.startsWith('otzaria://note-marker')) {
      _handleNumberedNoteMarkerHover(url, globalPosition, hoverMode: false);
      return;
    }
    _cancelPendingAnchorHover();
    _showUrlPreview(url, globalPosition, hoverMode: false);
  }

  void _showUrlPreview(
    String url,
    Offset globalPosition, {
    required bool hoverMode,
  }) {
    final state = _textBookBloc.state;
    if (state is! TextBookLoaded) return;

    if (url.startsWith('otzaria://book-note')) {
      final note = inline_notes.inlineNoteFromPreviewUrl(
        state.content,
        url,
        dbNotes: state.bookNotes,
        decorateBody: (line, note, body) =>
            _injectAnchorMarkersForLine(body, line, state, note: note),
      );
      if (note == null) return;
      LinkPreviewOverlay.showContent(
        context,
        globalPosition: globalPosition,
        hoverMode: hoverMode,
        contentBuilder: (_) => InlineBookNotePreviewContent(
          content: note,
          removeNikud: state.removeNikud,
          removePunctuation: state.removePunctuation,
          maxFontSize: widget.textSize,
          onAnchorTap: _handleAnchorTap,
        ),
      );
      return;
    }

    if (url.startsWith('otzaria://note')) {
      final line = int.tryParse(
        Uri.tryParse(url)?.queryParameters['line'] ?? '',
      );
      if (line == null) return;
      final notes = context
          .read<PersonalNotesBloc>()
          .state
          .locatedNotes
          .where((note) => note.lineNumber == line + 1)
          .toList();
      if (notes.isEmpty) return;
      LinkPreviewOverlay.showContent(
        context,
        globalPosition: globalPosition,
        hoverMode: hoverMode,
        contentBuilder: (_) => PersonalNotesListView(
          notes: notes,
          maxHeight: 220,
          onLinkTap: (url) => openNoteLink(
            context,
            url,
            notes.first.bookId,
            (line, {note}) => widget.tab.lines.scrollToLine(line - 1),
          ),
        ),
      );
      return;
    }

    final anchor = _anchorLinkFromUrl(url);
    final link = anchor?.link ?? inlineLinkFromPreviewUrl(url);
    if (link == null) return;
    _showLinkPreview(
      link,
      globalPosition,
      hoverMode: hoverMode,
      activeAnchor: anchor == null
          ? null
          : (line: anchor.line, index: anchor.index),
    );
  }

  /// ריחוף על סמן-מספר: ההתאמה בין הסמן להערה נעשית לפי תוכן ההערה, ולכן היא
  /// אסינכרונית. אם אין הערה תואמת — לא נפתחת חלונית.
  void _handleNumberedNoteMarkerHover(
    String url,
    Offset globalPosition, {
    bool hoverMode = true,
  }) {
    LinkPreviewOverlay.cancelScheduledHide(AppWindowKeys.of(context));
    _cancelPendingAnchorHover();
    final line = noteMarkerLineFromUrl(url);
    final state = _textBookBloc.state;
    if (line == null || state is! TextBookLoaded) return;
    final links = state.linksByLine[line + 1] ?? const <Link>[];
    final generation = _anchorHoverGeneration;
    final delay = Duration(milliseconds: hoverMode ? 280 : 0);
    _anchorHoverTimer = Timer(delay, () async {
      final link = await numberedNoteLinkFromUrl(url, links);
      if (_disposed || !mounted || link == null) return;
      if (generation != _anchorHoverGeneration) return;
      _showLinkPreview(link, globalPosition, hoverMode: hoverMode);
    });
  }

  /// הסמן עזב את העוגן — ביטול הצגה ממתינה וסגירה מתוזמנת של חלונית פתוחה
  /// (מתבטלת אם הסמן נכנס לחלונית עצמה או חוזר לעוגן).
  void _handleAnchorHoverExit(String url) {
    _cancelPendingAnchorHover();
    LinkPreviewOverlay.scheduleHide(_previewWindow);
  }

  late final ReadingViewportBinding _viewportBinding = ReadingViewportBinding(
    segments: () {
      final state = _textBookBloc.state;
      return state is TextBookLoaded ? readingSegmentsOf(state) : null;
    },
    viewportExtent: () => _viewportHeight > 0
        ? _viewportHeight
        : (_disposed ? 0 : MediaQuery.sizeOf(context).height),
  );

  /// סמני חלוקה לפי lineIndex — אותיות פסקה במדרש רבה, סעיפים בנושאי-כלים.
  Map<int, String> _sectionMarkersByLine = const {};

  /// כותרות נושא (מבנה `Topic`) לפי lineIndex, שאינן כתובות בגוף הספר.
  Map<int, List<String>> _sectionHeadingsByLine = const {};

  // מנהל בחירת טקסט משופר
  late final TextSelectionManager _selectionManager;

  final GlobalKey<SelectionAreaState> _selectionAreaKey = GlobalKey();
  final Object _selectionOwner = Object();

  void _endSelectionPointer({required bool takeFocus}) {
    if (!_isSelectionPointerDown) return;
    _isSelectionPointerDown = false;
    _selectionLineCache.clear();
    if (_pendingSelectionClear) _clearSelectionState();
    if (takeFocus && !_hasLocalCorrections) _focusNode.requestFocus();
    _flushDeferredSelectionAreaRefresh();
  }

  void _flushDeferredSelectionAreaRefresh() {
    if (!_needsSelectionAreaRefreshOnPointerUp) return;
    _needsSelectionAreaRefreshOnPointerUp = false;
    if (!mounted || _selectionManager.isInSelectionMode) return;
    setState(() {});
  }

  void _clearSelectionBeforeJump() {
    if (_savedSelectedText.value == null) return;
    _selectionAreaKey.currentState?.selectableRegion.clearSelection();
  }

  void _clearSelectionState() {
    _pendingSelectionClear = false;
    widget.selectionSyncController?.clear(_selectionOwner);
    _selectionManager.exitSelectionMode();
    _savedSelectedText.value = null;
    _selectionLineStart = null;
    _selectionLineEnd = null;
    _selectionStartColumn = null;
  }

  void _onSelectionModeChanged() {
    if (_selectionManager.isInSelectionMode || !mounted) return;
    if (_isSelectionPointerDown) {
      _needsSelectionAreaRefreshOnPointerUp = true;
      return;
    }
    setState(() {});
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
  final _selectionAreaFocusNode = _KeepSelectionOnWindowBlurFocusNode();

  bool _didRequestInitialFocus = false;

  bool _isSelectionPointerDown = false;
  bool _needsSelectionAreaRefreshOnPointerUp = false;
  bool _pendingSelectionClear = false;

  // שמירת גובה הבלוק בפועל לחישובים דינאמיים
  double _viewportHeight = 0;

  final DictionaryLookupRepository _dictionaryLookupRepository =
      DictionaryLookupRepository.instance;

  late final AppWindowKeys _previewWindow;

  @override
  void initState() {
    super.initState();
    _previewWindow = AppWindowKeys.of(context);
    _focus = FocusRepository.of(context);
    _localCorrectionActive = _hasLocalCorrections;
    PluginCorrectionSessionService.instance.addListener(
      _onLocalCorrectionChanged,
    );
    _focusNode = FocusNode();
    _textBookBloc = context.read<TextBookBloc>();

    _siblingController = SiblingCommentariesController(
      loadSiblings: (sourceLink) {
        final state = _textBookBloc.state;
        if (state is! TextBookLoaded) return Future.value(const <Link>[]);
        return _textBookBloc.repository.getSiblingCommentaries(
          sourceBookTitle: utils.getTitleFromPath(sourceLink.path2),
          sourceCategoryId: sourceLink.targetCategoryId,
          sourceBookSource: sourceLink.targetSource,
          sourceLineIndex: sourceLink.index2 - 1,
          currentBookTitle: state.book.title,
          currentCategoryId: state.book.categoryId,
          currentBookSource: state.book.source,
        );
      },
    );

    _loadSectionMarkers();

    // אתחול מנהל הבחירה
    _selectionManager = TextSelectionManager();

    _selectionManager.addListener(_onSelectionModeChanged);
    widget.selectionSyncController?.addListener(_handleExternalSelectionChange);
    PluginHighlightRevealService.instance.addListener(
      _handlePluginHighlightReveal,
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _handlePluginHighlightReveal(),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<PersonalNotesBloc>().add(
        LoadPersonalNotes(personalNotesBookKey(widget.tab.book)),
      );
    });

    _attachTabBindings(widget);
    _subscribeToTextBook();

    // מוודא שהפוקוס מגיע לאזור הקריאה מיד אחרי פתיחת ספר
    // כדי שגלילה בחיצים תעבוד בלי לחיצה בעכבר, אך בלי לגנוב פוקוס משדות טקסט.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _didRequestInitialFocus) return;
      _didRequestInitialFocus = true;

      final primaryFocus = FocusManager.instance.primaryFocus;
      final focusContext = primaryFocus?.context;
      final isTextInputFocused =
          focusContext?.widget is EditableText ||
          focusContext?.findAncestorWidgetOfExactType<EditableText>() != null;

      if (!isTextInputFocused && !_focusNode.hasFocus) {
        _focusNode.requestFocus();
      }
    });
  }

  void _attachTabBindings(CombinedView view) {
    final lines = view.tab.lines;
    lines.position.addListener(_onScroll);
    lines.navigationEpoch.addListener(_cancelCommentaryReveal);
    lines.addBeforeJumpListener(_clearSelectionBeforeJump);
    lines.attach(_viewportBinding);
    view.tab.dynamicCopyRequestNotifier.addListener(_onDynamicCopyRequest);
    if (!view.isPreviewMode) {
      _focus.registerTabContentFocusRequester(view.tab, () {
        if (_focusNode.canRequestFocus) _focusNode.requestFocus();
      });
    }
  }

  void _detachTabBindings(CombinedView view) {
    final lines = view.tab.lines;
    _cancelCommentaryRevealFor(lines);
    lines.position.removeListener(_onScroll);
    lines.navigationEpoch.removeListener(_cancelCommentaryReveal);
    lines.removeBeforeJumpListener(_clearSelectionBeforeJump);
    lines.detach(_viewportBinding);
    view.tab.dynamicCopyRequestNotifier.removeListener(_onDynamicCopyRequest);
    if (!view.isPreviewMode) {
      _focus.unregisterTabContentFocusRequester(view.tab);
    }
  }

  void _subscribeToTextBook() {
    unawaited(_textBookSubscription?.cancel());
    _textBookSubscription = _textBookBloc.stream.listen(_onTextBookState);
    _onTextBookState(_textBookBloc.state);
  }

  void _onTextBookState(TextBookState state) {
    if (state is! TextBookLoaded) return;
    _scrollToInitialPosition(state);
    final line = _commentaryRevealLine;
    if (line == null) return;
    if (state.selectedIndex == line && state.selectedIndices.contains(line)) {
      if (!_commentaryRevealSelectionObserved) {
        _commentaryRevealSelectionObserved = true;
        final generation = _commentaryRevealGeneration;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_positionCommentaryCard(line, generation));
        });
      }
    } else if (_commentaryRevealSelectionObserved) {
      _cancelCommentaryReveal();
    }
  }

  void _resetBookState() {
    _cancelCommentaryReveal();
    _cancelPendingAnchorHover();
    LinkPreviewOverlay.dismiss(window: AppWindowKeys.of(context));
    _activeAnchorLine = null;
    _activeAnchorIndex = null;
    _anchorHandledCurrentTap = false;
    _localCorrectionActive = _hasLocalCorrections;
    _hasScrolledToInitialPosition = false;
    _commentaryCardKeys.clear();
    _commentaryStorage = PageStorageBucket();
    _anchorStyleSourceLinks = null;
    _anchorStyleCache = const {};
    _sectionMarkersByLine = const {};
    _sectionHeadingsByLine = const {};
    _siblingController.clear();
    _paragraphCommentatorsCache.dispose();
    _paragraphCommentatorsCache = ParagraphCommentatorsCache();
    _selectionLineCache.clear();
    _isSelectionPointerDown = false;
    _needsSelectionAreaRefreshOnPointerUp = false;
    _selectionPointerColumn = null;
    _selectionPointerLineIndex = null;
    _sourceSelection = null;
    _savedSelectedIndex.value = null;
    _currentSelectedIndex.value = null;
    _anchorScrollTargetNotifier.value = null;
    _clearSelectionState();
    _selectionAreaKey.currentState?.selectableRegion.clearSelection();
  }

  void _updateTextBookBloc() {
    final bloc = context.read<TextBookBloc>();
    if (identical(bloc, _textBookBloc)) return;
    _textBookBloc = bloc;
    _resetBookState();
    _subscribeToTextBook();
    _loadSectionMarkers();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateTextBookBloc();
  }

  /// פתיחה מחיפוש או מקישור עם הדגשה: יעד המילה המודגשת, סביב מרכז התצוגה —
  /// בעקביות עם סרגל תוצאות החיפוש. יעד שכבר ממתין (ניווט, החלפת תצוגה) קודם.
  void _scrollToInitialPosition(TextBookLoaded state) {
    if (_hasScrolledToInitialPosition) return;
    _hasScrolledToInitialPosition = true;
    final lines = widget.tab.lines;
    if (lines.hasPendingTarget) return;
    final initialIndex = widget.tab.index;
    final query = state.searchText.isNotEmpty
        ? state.searchText
        : state.isHighlightYellowBackground(initialIndex)
        ? state.highlightText
        : '';
    final isFromSearch =
        query.isNotEmpty && initialIndex < state.content.length;
    if (!isFromSearch) return;
    final intraLineFraction = matchFractionInLine(
      state.content[initialIndex],
      query,
      wholeWord: state.searchWholeWord,
      searchOptions: state.searchOptions,
      alternativeWords: state.alternativeWords,
      spacingValues: state.spacingValues,
      isFuzzy: state.searchMode == SearchMode.fuzzy,
      searchDistance: state.searchDistance,
      matchPolicy: state.matchPolicy,
    );
    unawaited(
      lines.scrollToLine(
        initialIndex,
        duration: const Duration(milliseconds: 300),
        intraLineFraction: intraLineFraction,
        alignment: kSearchResultAnchorAlignment,
      ),
    );
  }

  void _handlePluginHighlightReveal() {
    final highlight = PluginHighlightRevealService.instance.highlight;
    if (!mounted ||
        highlight == null ||
        highlight.bookId != widget.tab.book.title) {
      return;
    }
    final tab = widget.tab;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(tab, widget.tab)) return;
      unawaited(
        widget.tab.lines.scrollToLine(
          highlight.sectionIndex,
          alignment: .35,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeInOut,
        ),
      );
    });
  }

  @override
  void didUpdateWidget(covariant CombinedView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectionSyncController != widget.selectionSyncController) {
      oldWidget.selectionSyncController?.removeListener(
        _handleExternalSelectionChange,
      );
      oldWidget.selectionSyncController?.clear(_selectionOwner);
      widget.selectionSyncController?.addListener(
        _handleExternalSelectionChange,
      );
    }
    if (personalNotesBookKey(oldWidget.tab.book) !=
        personalNotesBookKey(widget.tab.book)) {
      context.read<PersonalNotesBloc>().add(
        LoadPersonalNotes(personalNotesBookKey(widget.tab.book)),
      );
    }
    final tabChanged =
        !identical(oldWidget.tab, widget.tab) ||
        oldWidget.isPreviewMode != widget.isPreviewMode;
    if (tabChanged) _detachTabBindings(oldWidget);
    if (tabChanged ||
        !sameSourceIdentity(oldWidget.tab.book, widget.tab.book)) {
      _resetBookState();
      _loadSectionMarkers();
    }
    _updateTextBookBloc();
    if (tabChanged) _attachTabBindings(widget);
    _onTextBookState(_textBookBloc.state);
  }

  String? _loadedLineAt(int lineIndex) {
    final state = _textBookBloc.state;
    if (state is! TextBookLoaded) return null;
    final content = state.content;
    return lineIndex >= 0 && lineIndex < content.length
        ? content[lineIndex]
        : null;
  }

  Future<void> _loadSectionMarkers() async {
    final tab = widget.tab;
    final book = tab.book;
    // הסימנים ממופים ל-lineIndex של הטקסט הממוזג במסד — מהדורה חלופית
    // (version_line) או ספר שתוכנו מוגש מקבצים ממוספרים אחרת.
    if (book.versionTitle != null) return;
    final InlineSectionMarks marks;
    if (book.isUserBook) {
      marks = await DatabaseLibraryProvider.instance.getUserInlineSectionMarks(
        book,
        _loadedLineAt,
      );
    } else {
      if (book.source.isOfficial &&
          LibraryProviderManager.instance.getProviderForBook(
                book.title,
                categoryId: book.categoryId,
                fileType: book.fileType,
              )
              is! DatabaseLibraryProvider) {
        return;
      }
      marks = await DatabaseLibraryProvider.instance
          .getInlineSectionMarksByLineIndex(
            book.title,
            categoryId: book.categoryId,
            source: book.source,
          );
    }
    // מעבר מהיר בין ספרים עלול לסיים await זה אחרי החלפת הספר.
    if (!mounted || !identical(tab, widget.tab)) return;
    if (marks.markers.isEmpty &&
        marks.headings.isEmpty &&
        _sectionMarkersByLine.isEmpty &&
        _sectionHeadingsByLine.isEmpty) {
      return;
    }
    setState(() {
      _sectionMarkersByLine = marks.markers;
      _sectionHeadingsByLine = marks.headings;
    });
  }

  @override
  void dispose() {
    PluginCorrectionSessionService.instance.removeListener(
      _onLocalCorrectionChanged,
    );
    unawaited(_textBookSubscription?.cancel());
    PluginHighlightRevealService.instance.removeListener(
      _handlePluginHighlightReveal,
    );
    _disposed = true;
    _detachTabBindings(widget);
    _cancelPendingAnchorHover();
    LinkPreviewOverlay.dismiss(window: _previewWindow);
    _savedSelectedText.dispose();
    _savedSelectedIndex.dispose();
    _currentSelectedIndex.dispose();
    _anchorScrollTargetNotifier.dispose();
    _focusNode.dispose();
    _selectionAreaFocusNode.dispose();
    widget.selectionSyncController?.removeListener(
      _handleExternalSelectionChange,
    );
    _selectionManager.removeListener(_onSelectionModeChanged);
    _selectionManager.dispose();
    _siblingController.dispose();
    _paragraphCommentatorsCache.dispose();
    super.dispose();
  }

  void _handleExternalSelectionChange() {
    final controller = widget.selectionSyncController;
    if (controller == null || !mounted) {
      return;
    }

    final shouldClear = shouldClearSelectionOnExternalChange(
      activeOwner: controller.activeOwner,
      selfOwner: _selectionOwner,
      hasOwnSelection:
          _savedSelectedText.value != null ||
          _selectionManager.isInSelectionMode,
    );
    if (!shouldClear) {
      return;
    }

    // ניקוי ישיר ולא החלפת מפתח: כרטיס המפרשים מקונן בעץ הזה, והחלפת מפתח
    // הייתה הורסת אותו יחד עם הבחירה שזה עתה סומנה בו (issue #674).
    _selectionAreaKey.currentState?.selectableRegion.clearSelection();

    _selectionManager.exitSelectionMode();
    setState(() {
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
    BuildContext lineContext, {
    ReaderLineHit? hit,
  }) {
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
    final root = hit?.root ?? lineContext.findRenderObject();
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
      lineRange: hit?.lineRange,
    );
    return onSelection ?? true; // לא הוכרע — סלחני
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

    unawaited(
      _dictionaryLookupRepository.ensureAramaicLoaded().catchError((_) {
        return;
      }),
    );

    if (_dictionaryLookupRepository.isLikelyAcronym(trimmed)) {
      unawaited(
        _dictionaryLookupRepository.ensureAcronymsLoaded().catchError((_) {
          return;
        }),
      );
    }
  }

  // בניית תפריט קונטקסט לאינדקס ספציפי של פסקה
  List<AppContextMenuEntry> _buildContextMenuForIndex(
    TextBookLoaded state,
    int paragraphIndex,
    BuildContext menuContext,
    String? selectedText,
    Offset tapPosition, {
    TextRange? lineRange,
  }) {
    // מצב תצוגה מקדימה — תפריט מינימלי
    if (widget.isPreviewMode || _hasLocalCorrections) {
      return [
        AppContextMenuEntry(
          label: 'העתק',
          icon: FluentIcons.copy_24_regular,
          enabled: selectedText != null && selectedText.trim().isNotEmpty,
          onTap: () => _copyFormattedText(selectedText),
        ),
        _copyAsEntry(state, selectedText),
      ];
    }

    // גם לקישורים: linksByLine מכסה רק את חלון הטעינה סביב האזור הנראה.
    _prefetchParagraphCommentators(state, paragraphIndex);

    List<Link> currentParagraphLinks() =>
        buildCombinedViewContextMenuLinksForParagraph(
          linksByLine: state.linksByLine,
          paragraphIndex: paragraphIndex,
          queriedLinks: _paragraphCommentatorsCache.referenceLinks(
            state.book,
            paragraphIndex,
          ),
        );
    final hasParagraphLinks =
        currentParagraphLinks().isNotEmpty ||
        _paragraphCommentatorsCache.isLoading(state.book, paragraphIndex);
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

    List<AppContextMenuEntry> buildCommentatorChildren() {
      final isLoading = _paragraphCommentatorsCache.isLoading(
        state.book,
        paragraphIndex,
      );
      return buildCommentatorsContextMenuChildren(
        getActiveCommentators: () => state.activeCommentators,
        availableCommentators: paragraphCommentators(
          availableCommentators: state.availableCommentators,
          content: state.content,
          bookNotes: state.bookNotes,
          paragraphIndex: paragraphIndex,
          linksByLine: state.linksByLine,
          queriedCommentators: isLoading
              ? const <String>[]
              : _paragraphCommentatorsCache.value(state.book, paragraphIndex),
        ),
        commentatorGroups: state.commentatorGroups,
        linksLoading: state.linksLoading || isLoading,
        onOpenPane: shouldShowOpenPaneEntry
            ? () {
                _selectParagraphForContextMenu(paragraphIndex);
                _openCommentatorsPane(isAdding: true);
              }
            : null,
        onSelectMultiple: shouldShowSelectEntry
            ? () {
                _selectParagraphForContextMenu(paragraphIndex);
                widget.onOpenCommentatorsPaneWithFilter!();
              }
            : null,
        onCommentatorsChanged: (commentators, {required isAdding}) {
          _selectParagraphForContextMenu(paragraphIndex);
          context.read<TextBookBloc>().add(UpdateCommentators(commentators));
          _openCommentatorsPane(isAdding: isAdding);
        },
      );
    }

    List<AppContextMenuEntry> buildLinkChildren() {
      final showOpenLinksPaneEntry = shouldShowOpenLinksPaneEntry(
        hasLinks: true,
        isLinksTabActive: widget.isLinksTabActive?.call() ?? false,
      );
      return buildParagraphLinksMenuChildren(
        links: currentParagraphLinks(),
        isLoading: _paragraphCommentatorsCache.isLoading(
          state.book,
          paragraphIndex,
        ),
        removeNikud: state.commentaryRemoveNikud,
        removePunctuation: state.commentaryRemovePunctuation,
        maxFontSize: widget.textSize,
        openPaneEntry: showOpenLinksPaneEntry
            ? buildOpenLinksPaneEntry(
                onTap: () => widget.onOpenLinksPane?.call(),
              )
            : null,
        onOpenLink: (link) => openLinkTarget(link, _openTab),
      );
    }

    final source = SourceSelection.resolve(
      _sourceSelection,
      selectedText,
      _selectionStartColumn,
    );
    final sourceText = source.text;
    final menuSelection = ReaderMenuSelection(sourceText);

    return [
      // שורת אייקונים עליונה בסגנון Windows 11 — הרשימה המלאה נשארת מתחת.
      buildReaderIconRow(
        context: context,
        selection: menuSelection,
        book: state.book,
        paragraphIndex: paragraphIndex,
        selectedText: selectedText,
        protection: state.protection,
        onCopy: () => _copyFormattedText(selectedText),
        onAddNote: () => _showNoteEditor(
          selectedText,
          _currentSelectedIndex.value ?? paragraphIndex,
        ),
      ),
      _copyAsEntry(state, selectedText),
      const AppContextMenuEntry.divider(),
      AppContextMenuEntry(
        label: menuSelection.hasText
            ? 'חפש "${menuSelection.quote(10)}" בספר זה'
            : 'חיפוש',
        icon: FluentIcons.search_24_regular,
        onTap: menuSelection.hasText
            ? () => widget.openLeftPaneTab(1, searchText: menuSelection.cleaned)
            : () => widget.openLeftPaneTab(1),
      ),
      AppContextMenuEntry(
        label: kParagraphCommentatorsMenuLabel,
        icon: OtzariaIcons.book_24_regular,
        enabled: state.availableCommentators.isNotEmpty,
        childrenBuilder: buildCommentatorChildren,
        childrenRefreshStream: _paragraphCommentatorsCache.changes,
      ),
      AppContextMenuEntry(
        label: 'קישורים',
        icon: OtzariaIcons.links_24_regular,
        enabled: hasParagraphLinks,
        childrenBuilder: buildLinkChildren,
        childrenRefreshStream: _paragraphCommentatorsCache.changes,
      ),
      ...() {
        final sourceLink = _siblingController.sourceLinkForLine(
          state.linksByLine,
          paragraphIndex + 1,
        );
        final entry = _siblingController.buildEntry(
          lineIndex: paragraphIndex,
          sourceLink: sourceLink,
          removeNikud: state.commentaryRemoveNikud,
          removePunctuation: state.commentaryRemovePunctuation,
          maxFontSize: widget.textSize,
          onNavigate: (link) => openLinkTarget(link, _openTab),
        );
        return entry == null
            ? const <AppContextMenuEntry>[]
            : <AppContextMenuEntry>[entry];
      }(),
      ...buildReaderDictionaryEntries(
        context: context,
        selectedText: sourceText,
        tapPosition: tapPosition,
        repository: _dictionaryLookupRepository,
      ),
      const AppContextMenuEntry.divider(),
      AppContextMenuEntry(
        label: 'הוסף סימניה לקטע זה',
        icon: FluentIcons.bookmark_add_24_regular,
        onTap: () => addTextSectionBookmark(context, state, paragraphIndex),
      ),
      if (state.book.isOfficialLibraryBook)
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
        label: 'העתק את כל הפסקה',
        icon: FluentIcons.document_copy_24_regular,
        enabled: paragraphIndex >= 0 && paragraphIndex < widget.data.length,
        onTap: () => _copyParagraphByIndex(paragraphIndex),
      ),
      ...buildReaderPluginMenuEntries(
        root: context.findRenderObject(),
        state: state,
        tabId: readerBookTabId(widget.tab, state),
        lines: widget.data,
        paragraphIndex: paragraphIndex,
        hasSelection: menuSelection.hasText,
        selectedText: sourceText,
        anchor: (
          lineStart: _selectionLineStart,
          lineEnd: _selectionLineEnd,
          startColumn: source.column,
          pointerColumn: SourceSelection.resolvePointerColumn(
            _sourceSelection,
            selectedText,
            _selectionPointerColumn,
            lineStart: _selectionLineStart,
            pointerLineIndex: _selectionPointerLineIndex,
          ),
        ),
        settings: () => _selectionRenderSettings(
          state,
          menuContext.read<SettingsBloc>().state,
        ),
        tapPosition: tapPosition,
        menuContext: menuContext,
        lineRange: lineRange,
      ),
    ];
  }

  void _prefetchParagraphCommentators(
    TextBookLoaded state,
    int paragraphIndex,
  ) {
    unawaited(
      _paragraphCommentatorsCache
          .prefetch(
            repository: context.read<TextBookBloc>().repository,
            book: state.book,
            paragraphIndex: paragraphIndex,
          )
          .onError((error, stackTrace) {
            debugPrint('שגיאה בטעינת מפרשי הפסקה: $error\n$stackTrace');
          }),
    );
  }

  void _selectParagraphForContextMenu(int paragraphIndex) {
    _currentSelectedIndex.value = paragraphIndex;

    final state = _textBookBloc.state;
    if (state is TextBookLoaded && state.selectedIndex != paragraphIndex) {
      _addTextBookEventIfOpen(UpdateSelectedIndex(paragraphIndex));
    }
  }

  /// פתיחת דיאלוג דיווח על טעות בספר
  void _openErrorReportDialog(String selectedText, {int? fallbackLineIndex}) {
    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded) return;

    ErrorReportHelper.showErrorReportDialog(
      context: context,
      selectedText: SourceSelection.resolve(
        _sourceSelection,
        selectedText,
        null,
      ).text,
      state: state,
      fontSize: widget.textSize,
      bookTitle: widget.tab.book.title,
      savedSelectedIndex: fallbackLineIndex ?? _savedSelectedIndex.value,
    );
  }

  /// מעבד את הטקסט לפי פרופיל ערוץ ההעתקה של גוף הספר.
  String _applyDisplayTextPreferences(
    String text,
    TextBookState textBookState,
  ) {
    if (textBookState is! TextBookLoaded) return text;
    return applyDisplayTextPreferences(
      text: text,
      profile: textBookState.displayProfile(
        target: TextTarget.body,
        channel: TextChannel.copy,
      ),
    );
  }

  /// העתקת פסקה לפי אינדקס (משתמש ב־widget.data[index] ומייצר גם HTML)
  Future<void> _copyParagraphByIndex(
    int index, {
    TextDisplayProfile? profile,
    bool plainTextOnly = false,
  }) async {
    if (index < 0 || index >= widget.data.length) return;

    final text = widget.data[index];
    if (text.trim().isEmpty) return;

    final settingsState = context.read<SettingsBloc>().state;
    final textBookState = context.read<TextBookBloc>().state;
    final loaded = textBookState is TextBookLoaded ? textBookState : null;

    await copyParagraphToClipboard(
      processedText: profile != null
          ? applyTextDisplayProfile(text, profile)
          : _applyDisplayTextPreferences(text, textBookState),
      index: index,
      copyWithHeaders: settingsState.copyWithHeaders,
      copyHeaderFormat: settingsState.copyHeaderFormat,
      headerBook: loaded?.book,
      bookContent: loaded?.content,
      isLineLoaded: loaded?.isContentLineLoaded,
      fontFamily: settingsState.fontFamily,
      fontSize: widget.textSize,
      plainTextOnly: plainTextOnly,
    );
  }

  /// העתקת טקסט מעוצב (HTML) ללוח
  /// "העתק כ..." — וריאציות ההעתקה מפרופיל ערוץ ההעתקה של הגוף.
  AppContextMenuEntry _copyAsEntry(
    TextBookLoaded state,
    String? selectedText,
  ) => buildCopyAsMenuEntry(
    base: state.displayProfile(
      target: TextTarget.body,
      channel: TextChannel.copy,
    ),
    selectedText: selectedText,
    onCopy: (profile) => _copyFormattedText(selectedText, false, profile),
  );

  /// בקשת העתקה מקיצור דינמי (ראה DynamicShortcutDispatcher).
  void _onDynamicCopyRequest() {
    final request = widget.tab.dynamicCopyRequestNotifier.value;
    if (request == null || !mounted) return;
    widget.tab.dynamicCopyRequestNotifier.value = null;
    switch (request.kind) {
      case DynamicShortcutKind.copySelectionWith:
        _copyFormattedText(null, false, request.profile, request.plainTextOnly);
      case DynamicShortcutKind.copyParagraphWith:
        final state = _textBookBloc.state;
        final index =
            _currentSelectedIndex.value ??
            (state is TextBookLoaded ? state.selectedIndex : null);
        if (index != null) {
          _copyParagraphByIndex(
            index,
            profile: request.profile,
            plainTextOnly: request.plainTextOnly,
          );
        }
      case DynamicShortcutKind.setTextDisplay:
        break;
    }
  }

  Future<void> _copyFormattedText([
    String? capturedText,
    bool removeNikud = false,
    TextDisplayProfile? profile,
    bool plainTextOnly = false,
  ]) async {
    final plainText = capturedText ?? _savedSelectedText.value;

    debugPrint('_copyFormattedText called with: "$plainText"');
    debugPrint('_currentSelectedIndex: ${_currentSelectedIndex.value}');

    if (plainText == null || plainText.trim().isEmpty) {
      final controller = widget.selectionSyncController;
      final commentarySelection = commentarySelectionForCopy(
        controller: controller,
        mainTextOwner: _selectionOwner,
      );
      if (commentarySelection != null) {
        final guard = await commentarySelection.copyGuard?.call();
        if (!mounted) return;
        final settingsState = context.read<SettingsBloc>().state;
        await ContextMenuUtils.copyFormattedText(
          context: context,
          savedSelectedText: commentarySelection.text,
          fontSize: settingsState.commentatorsFontSize,
          link: commentarySelection.link,
          removeNikud: removeNikud,
          copyProfile: profile,
          plainTextOnly: plainTextOnly,
          protection: guard?.protection,
          segmentCount: guard?.segmentCount,
        );
        return;
      }
      UiSnack.show(TextBookMessages.selectTextToCopy);
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
        segmentCount: selectionSegmentCount(
          start: _selectionLineStart,
          end: _selectionLineEnd,
          text: plainText,
        ),
        settingsState: settingsState,
        fontFamily: settingsState.fontFamily,
        fontSize: widget.textSize,
        removeNikud: removeNikud,
        copyProfile: profile,
        copyTarget: TextTarget.body,
        source: _sourceSelection,
        plainTextOnly: plainTextOnly,
      );
    } catch (e) {
      if (mounted) {
        UiSnack.showError(TextBookMessages.formattedCopyError(e));
      }
    }
  }

  /// הצגת עורך ההערות
  Future<void> _showNoteEditor([
    String? capturedText,
    int? clickedIndex,
  ]) async {
    final state = _textBookBloc.state;
    if (state is! TextBookLoaded) return;

    final source = SourceSelection.resolve(
      _sourceSelection,
      capturedText ?? _savedSelectedText.value,
      _selectionStartColumn,
    );
    final selectedText = source.text;
    final hasSelection = selectedText?.trim().isNotEmpty == true;

    // בחירה פעילה מקבלת קדימות; בלעדיה משתמשים בשורת הלחיצה,
    // כי האינדקס השמור עשוי להישאר מבחירה קודמת.
    final currentIndex =
        (hasSelection ? _savedSelectedIndex.value : null) ??
        clickedIndex ??
        _savedSelectedIndex.value ??
        state.selectedIndex ??
        widget.tab.index;

    // קבלת הטקסט המזהה של השורה - אם יש טקסט נבחר, משתמשים בו (אחרי הסרת ניקוד), אחרת בטקסט המזהה (כמו שיוצג ככותרת)
    final referenceText = selectedText?.trim().isNotEmpty == true
        ? removeHebrewDiacritics(selectedText!.trim())
        : extractDisplayTextFromLines(
            state.content,
            currentIndex + 1,
            excludeBookTitle: widget.tab.book.title,
          );
    final sourceSelection = hasSelection
        ? mapPersonalNoteSourceSelection(
            bookId: personalNotesBookKey(widget.tab.book),
            lineIndex: currentIndex,
            rawLine: state.content[currentIndex],
            settings: _selectionRenderSettings(
              state,
              context.read<SettingsBloc>().state,
            ),
            selectedText: selectedText!.trim(),
            startHint: source.column,
          )
        : null;

    // טען טיוטה אם קיימת
    final draftService = PersonalNoteDraftService();
    final draft = await draftService.loadDraft(
      bookId: personalNotesBookKey(widget.tab.book),
      categoryId: widget.tab.book.categoryId,
      lineNumber: currentIndex + 1,
    );

    if (!mounted) return;

    // שלח event לפתיחת מצב יצירה בסיידבר
    context.read<PersonalNotesBloc>().add(
      StartCreatingPersonalNote(
        bookId: personalNotesBookKey(widget.tab.book),
        lineNumber: currentIndex + 1,
        referenceText: referenceText,
        selectedText: selectedText?.trim(),
        selectionColumn: source.column,
        sourceSelectedText: sourceSelection?.text,
        sourceSelectionOffset: sourceSelection?.offset,
        punctuationHidden: state.removePunctuation,
        initialContent: draft?.content ?? '',
        initialFormat: draft?.contentFormat ?? PersonalNoteContentFormat.plain,
      ),
    );

    // פתח את חלונית ההערות
    widget.onOpenPersonalNotes?.call();
  }

  /// טיפול בלחיצה על סימון הערה אישית inline: מדגיש את השורה ופותח את החלונית.
  void _onInlineNoteTap(int lineIndex) {
    _addTextBookEventIfOpen(UpdateSelectedIndex(lineIndex));
    _addTextBookEventIfOpen(HighlightLine(lineIndex));
    openPersonalNotesTarget(
      context.read<PersonalNotesBloc>(),
      bookId: personalNotesBookKey(widget.tab.book),
      categoryId: widget.tab.book.categoryId,
      lineNumber: lineIndex + 1,
    );
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
    return RenderSettings.fromProfile(
      state.bodyDisplayProfile,
      searchText: state.searchText,
      searchOptions: state.searchOptions,
      alternativeWords: state.alternativeWords,
      spacingValues: state.spacingValues,
      isFuzzySearch: state.searchMode == SearchMode.fuzzy,
      searchMode: state.searchMode,
      searchDistance: state.searchDistance,
      matchPolicy: state.matchPolicy,
      partialWordHighlight: !state.searchWholeWord,
      fontSize: widget.textSize,
      fontFamily: settingsState.fontFamily,
      fontWeight: settingsState.fontBold ? FontWeight.bold : null,
      lineHeight: settingsState.lineHeight,
    );
  }

  ({
    SelectionWindow window,
    SelectionLine Function(int) lineAt,
    SelectionParagraphs? paragraphs,
  })
  _buildSelectionWindow(
    TextBookLoaded state,
    SettingsState settingsState,
    int selectionLength,
  ) {
    final renderSettings = _selectionRenderSettings(state, settingsState);
    final lineAt = _selectionLineCache.lines(
      widget.data,
      renderSettings,
      markerKey: (
        state.linksByLine,
        state.bodyDisplayProfile.showAnchorMarkers,
        state.book.versionTitle,
      ),
      injectMarkers: (rawLine, index) =>
          _injectAnchorMarkersForLine(rawLine, index, state),
    );
    final window = buildSelectionWindow(
      visibleIndices: state.visibleIndices,
      totalLines: widget.data.length,
      selectionLength: selectionLength,
      renderLine: (index) => lineAt(index).text,
    );
    final paragraphs = readerSelectionParagraphs(
      layout: readingLayoutOf(state),
      lines: widget.data,
      baseIndex: window.baseIndex,
      sectionHeadings: _sectionHeadingsByLine,
      splitsAfter: (line) =>
          widget.showCommentaryAsExpansionTiles &&
          state.selectedIndices.contains(line) &&
          _hasCommentaries(state, line),
    );
    return (window: window, lineAt: lineAt, paragraphs: paragraphs);
  }

  final _selectionLineCache = SelectionLineCache();

  @visibleForTesting
  int get debugSelectionCachedLineCount => _selectionLineCache._lines.length;

  Widget buildKeyboardListener(TextBookBloc bloc) {
    return BlocBuilder<TextBookBloc, TextBookState>(
      bloc: bloc,
      buildWhen: shouldRebuildReader,
      builder: (context, state) {
        if (state is! TextBookLoaded) {
          return const Center(child: CircularProgressIndicator());
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            // שומר את גובה הבלוק בפועל לשימוש בחישובי הגלילה
            _viewportHeight = constraints.maxHeight;

            // יירוט Ctrl+C ממוקם *מעל* ה-SelectionArea — שם מנגנון ה-override
            // של CopySelectionTextIntent מאתר אותו. מתחתיו הוא בלתי-נראה, ואז
            // רצה העתקת ברירת המחדל של Flutter: בלחיצה בודדת הבחירה מתכווצת
            // ל-plainText ריק, והיא נכתבת ללוח כפריט ריק (issue #674).
            return SelectionCopyShortcuts(
              onCopy: _copyFormattedText,
              child: RtlSelectionShortcuts(
                child: Listener(
                  onPointerDown: (event) {
                    if (event.buttons == kPrimaryMouseButton) {
                      _isSelectionPointerDown = true;
                    }
                  },
                  onPointerUp: (_) => _endSelectionPointer(takeFocus: true),
                  onPointerCancel: (_) =>
                      _endSelectionPointer(takeFocus: false),
                  child: SelectionArea(
                    key: _selectionAreaKey,
                    focusNode: _selectionAreaFocusNode,
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
                        if (_isSelectionPointerDown) {
                          _pendingSelectionClear = true;
                          return;
                        }
                        _clearSelectionState();
                        return;
                      }
                      _pendingSelectionClear = false;
                      if (_hasLocalCorrections) {
                        _savedSelectedText.value = plain;
                        _sourceSelection = null;
                        widget.onSelectedTextChanged?.call(null, null, null);
                        return;
                      }
                      widget.selectionSyncController?.activate(_selectionOwner);
                      // כניסה למצב בחירה כשיש טקסט נבחר
                      if (!_selectionManager.isInSelectionMode) {
                        // שימוש באינדקס העליון הנראה במקום 0
                        _selectionManager.setAnchor(widget.tab.index);
                      }

                      // חשוב: כדי ש-Ctrl+C יעבוד מיד אחרי סימון טקסט עם העכבר
                      // נוודא שהפוקוס נמצא על אזור הקריאה.
                      if (!_isSelectionPointerDown) _focusNode.requestFocus();

                      // מחשב את מספר השורה המדויק של הטקסט המודגש
                      // משתמש באותה לוגיקה כמו בדיווח שגיאות
                      final TextBookLoaded? loadedState =
                          _textBookBloc.state is TextBookLoaded
                          ? _textBookBloc.state as TextBookLoaded
                          : null;
                      int? foundIndex;
                      var fixedPlain = plain;
                      SourceSelection? sourceSelection;

                      if (loadedState != null) {
                        final settingsState = context
                            .read<SettingsBloc>()
                            .state;
                        final (
                          :window,
                          :lineAt,
                          :paragraphs,
                        ) = _buildSelectionWindow(
                          loadedState,
                          settingsState,
                          plain!.length,
                        );
                        final baseIndex = window.baseIndex;
                        final visibleLines = window.lines;
                        final previousIndex = sessionSelectionIndex(
                          savedSelectedText: _savedSelectedText.value,
                          savedSelectedIndex: _savedSelectedIndex.value,
                        );
                        final restored = restoreSelectedTextLineBreaksDetailed(
                          selectedText: plain,
                          visibleLines: visibleLines,
                          preferredLine: previousIndex == null
                              ? null
                              : previousIndex - baseIndex,
                          paragraphs: paragraphs,
                        );
                        fixedPlain = restored.text;

                        final location = resolveSelectionLocation(
                          restored: restored,
                          baseIndex: baseIndex,
                          fallbackIndex: loadedState.selectedIndex,
                        );
                        final sourceIndices = List<int>.generate(
                          visibleLines.length,
                          (offset) => baseIndex + offset,
                        );
                        final pointerLocation =
                            locateSingleLineSelectionAtPointer(
                              renderedLines: visibleLines,
                              sourceIndices: sourceIndices,
                              selectedText: fixedPlain,
                              pointerLineIndex: _selectionPointerLineIndex,
                              pointerColumn: _selectionPointerColumn,
                            );
                        foundIndex =
                            pointerLocation?.lineIndex ??
                            location.selectedIndex;
                        // טווח השורות שהבחירה משתרעת עליהן — לזיהוי סלחני של לחיצה
                        // ימנית על הבחירה, ועמודת ההתחלה — רמז לזיהוי המופע הנכון
                        // כשאותו טקסט חוזר באותה שורה.
                        _selectionLineStart =
                            pointerLocation?.lineIndex ?? location.lineStart;
                        _selectionLineEnd =
                            pointerLocation?.lineIndex ?? location.lineEnd;
                        _selectionStartColumn =
                            pointerLocation?.column ?? location.startColumn;
                        final startLine = _selectionLineStart;
                        final startColumn = _selectionStartColumn;
                        if (startLine != null && startColumn != null) {
                          sourceSelection = SourceSelection.strip(
                            shownText: fixedPlain,
                            lines: [
                              for (
                                var i = startLine;
                                i <= (_selectionLineEnd ?? startLine);
                                i++
                              )
                                lineAt(i),
                            ],
                            startColumn: startColumn,
                          );
                        }
                        if (!_isSelectionPointerDown) {
                          _selectionLineCache.clear();
                        }
                      }

                      final source = SourceSelection.resolve(
                        sourceSelection,
                        fixedPlain,
                        _selectionStartColumn,
                      );
                      if (mounted) {
                        _savedSelectedText.value = fixedPlain;
                        _sourceSelection = sourceSelection;
                        _savedSelectedIndex.value = foundIndex;
                        _currentSelectedIndex.value = foundIndex;
                        widget.onSelectedTextChanged?.call(
                          source.text,
                          foundIndex,
                          source.column,
                        );

                        // שליחת event לפלאגינים עם ה-index המדויק
                        final selectionText = limitTextToCopySegments(
                          loadedState?.protection ?? BookProtection.none,
                          source.text?.trim() ?? '',
                        );
                        if (selectionText.isNotEmpty && loadedState != null) {
                          unawaited(
                            PluginRuntimeDispatcher.instance.dispatchEvent(
                              'reader.selection_changed',
                              {
                                'text': selectionText,
                                'currentRef': loadedState.currentTitle ?? '',
                                'currentBook': loadedState.book.title,
                                'currentBookId': loadedState.book.title,
                                'currentIndex': foundIndex ?? 0,
                                'id': ?loadedState.book.id,
                                'type': PluginBookIdentity.typeOf(
                                  loadedState.book,
                                ),
                                'source': PluginBookIdentity.sourceOf(
                                  loadedState.book,
                                ),
                              },
                            ),
                          );
                        }
                      }
                      _prefetchDictionaryLookups(source.text);
                    },
                    child: Shortcuts(
                      // Ctrl+C / Cmd+C מטופלים ב-SelectionCopyShortcuts שמעל.
                      shortcuts: <ShortcutActivator, Intent>{
                        // Windows "classic" copy
                        LogicalKeySet(
                          LogicalKeyboardKey.control,
                          LogicalKeyboardKey.insert,
                        ): const _CopySelectedTextIntent(),
                        // Esc לניקוי בחירה
                        LogicalKeySet(LogicalKeyboardKey.escape):
                            const ClearSelectionIntent(),
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
                          ClearSelectionIntent: _ClearSelectionAction(this),
                        },
                        child: widget.isPreviewMode
                            ? _buildPreviewList(state)
                            : ScrollablePositionedListScrollbar(
                                scrollController:
                                    widget.tab.lines.itemController,
                                itemCount: readingLayoutOf(state).itemCount,
                                onNavigationStart:
                                    widget.tab.lines.beginUserNavigation,
                                labelForIndex: state.tableOfContents.isEmpty
                                    ? null
                                    : (index) =>
                                          readingScrollbarLabel(state, index),
                                child: ProgressiveScroll(
                                  focusNode: _focusNode,
                                  maxSpeed: 10000.0,
                                  curve: 10.0,
                                  accelerationFactor: 312.5,
                                  scrollController:
                                      widget.tab.lines.itemController,
                                  onNavigationStart:
                                      widget.tab.lines.beginUserNavigation,
                                  child:
                                      BlocBuilder<
                                        PersonalNotesBloc,
                                        PersonalNotesState
                                      >(
                                        // שאר שדות ה-bloc (חיפוש, טיוטה) משתנים
                                        // בכל הקשה, והבנייה קוראת רק את אלה.
                                        buildWhen: (previous, current) =>
                                            previous.bookId != current.bookId ||
                                            previous.locatedNotes !=
                                                current.locatedNotes,
                                        builder: (context, notesState) {
                                          final noteMap =
                                              <int, List<PersonalNote>>{};
                                          if (notesState.bookId ==
                                              personalNotesBookKey(
                                                state.book,
                                              )) {
                                            for (final note
                                                in notesState.locatedNotes) {
                                              final line = note.lineNumber;
                                              if (line == null) continue;
                                              noteMap
                                                  .putIfAbsent(line, () => [])
                                                  .add(note);
                                            }
                                          }
                                          return SmoothWheelScroll(
                                            child: ScrollPositionReanchor(
                                              layoutKey: context.select(
                                                (SettingsBloc bloc) =>
                                                    bloc.state.lineHeight,
                                              ),
                                              preferredIndex:
                                                  _selectedItemIndex(state),
                                              isNavigationActive: () =>
                                                  widget.tab.lines.isNavigating,
                                              boxForIndex: widget
                                                  .tab
                                                  .lines
                                                  .itemBoxes
                                                  .boxForItem,
                                              scrollController: widget
                                                  .tab
                                                  .lines
                                                  .itemController,
                                              positionsListener: widget
                                                  .tab
                                                  .lines
                                                  .positionsListener,
                                              child: buildOuterList(
                                                state,
                                                noteMap,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
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

  Widget _buildPreviewList(TextBookLoaded state) {
    final layout = readingLayoutOf(state);
    final itemCount = layout.itemCount;
    // כמו ב-buildOuterList: פתיחה במיקום הטאב (תצוגה מקדימה של תוצאת
    // חיפוש נפתחת בקטע שנמצא, לא בראש הספר).
    final anchor = widget.tab.readingAnchor;
    final initialIndex = layout.itemForLine(anchor.line);
    final clampedInitial = itemCount == 0
        ? 0
        : initialIndex.clamp(0, itemCount - 1);

    return ScrollablePositionedListScrollbar(
      scrollController: widget.tab.lines.itemController,
      itemCount: itemCount,
      onNavigationStart: widget.tab.lines.beginUserNavigation,
      child: SmoothWheelScroll(
        child: _trackReadingScroll(
          _withReadingExtentEstimation(
            state,
            builder: (estimateExtent, estimationKey, _) =>
                ScrollablePositionedList.builder(
                  key: ValueKey((widget.tab, _textBookBloc)),
                  initialScrollIndex: clampedInitial,
                  initialAlignment: anchor.alignment,
                  initialTargetRectResolver: _initialReadingTargetResolver(
                    state,
                    anchor,
                  ),
                  cacheExtentScreens: TickerMode.valuesOf(context).enabled
                      ? kReaderCacheExtentScreens
                      : 0,
                  estimateExtent: estimateExtent,
                  estimationKey: estimationKey,
                  itemScrollController: widget.tab.lines.itemController,
                  itemPositionsListener: widget.tab.lines.positionsListener,
                  scrollOffsetController: widget.tab.lines.offsetController,
                  itemCount: itemCount,
                  itemBuilder: (context, index) => wrapReaderItem(
                    item: index,
                    layout: readingSegmentsOf(state).layout,
                    boxes: widget.tab.lines.itemBoxes,
                    child: RepaintBoundary(
                      child: buildExpansiomTile(
                        index,
                        state,
                        const <int, List<PersonalNote>>{},
                      ),
                    ),
                  ),
                ),
          ),
        ),
      ),
    );
  }

  TargetRectResolver? _initialReadingTargetResolver(
    TextBookLoaded state,
    ReadingAnchor anchor,
  ) {
    if (widget.tab.lines.captureAnchor() == null &&
        anchor.line == 0 &&
        anchor.intraLineFraction == 0 &&
        anchor.alignment == 0) {
      return null;
    }
    return readingAnchorTargetRectResolver(
      segments: () {
        final latest = _textBookBloc.state;
        return readingSegmentsOf(latest is TextBookLoaded ? latest : state);
      },
      lineIndex: anchor.line,
      intraLineFraction: anchor.intraLineFraction,
      measure: widget.tab.lines.itemBoxes.lineExtent,
    );
  }

  /// [builder] מקבל גם את רוחב עמודת הטקסט לפי רוחב הפריט (null בתצוגה מקדימה).
  Widget _withReadingExtentEstimation(
    TextBookLoaded state, {
    double crossAxisPadding = 0,
    required Widget Function(
      ItemExtentEstimator,
      Object,
      double Function(double)? columnWidth,
    )
    builder,
  }) => Builder(
    builder: (context) {
      final metrics = context.select(
        (SettingsBloc bloc) => (
          fontFamily: bloc.state.fontFamily,
          fontBold: bloc.state.fontBold,
          lineHeight: bloc.state.lineHeight,
          textMaxWidth: bloc.state.textMaxWidth,
        ),
      );
      // נקרא ב-build ולא בכל הערכה. הבסיס נכנס למפתח הפריסה של הרשימה ולא
      // ל-styleKey, כדי שגרירת חלון תידחה כמו שינוי רוחב.
      final baseWidth = widget.isPreviewMode
          ? null
          : ReadingAreaWidth.maybeOf(context);
      final setting = metrics.textMaxWidth;
      // בלי הגבלה (0) כל הפריט ברוחב מלא, כולל כרטיס המפרשים — אז העמודה היא הרוחב.
      double columnWidth(double width) {
        final column = resolveTextColumnMaxWidth(
          setting: setting,
          availableWidth: width,
          baseWidth: baseWidth ?? width,
        );
        return column > 0 ? column : width;
      }

      final columnWidthOrNull = widget.isPreviewMode ? null : columnWidth;
      return ReadingExtentEstimation(
        segments: readingSegmentsOf(state),
        controller: widget.tab.lines.itemController,
        fontSize: widget.textSize,
        fontFamily: AppFonts.renderFontFamily(metrics.fontFamily),
        fontWeight: metrics.fontBold ? FontWeight.bold : null,
        fontVariations: AppFonts.boldFontVariations(
          metrics.fontFamily,
          metrics.fontBold ? FontWeight.bold : FontWeight.normal,
        ),
        lineHeight: metrics.lineHeight,
        styleKey: setting,
        textWidth: columnWidthOrNull,
        crossAxisPadding: crossAxisPadding,
        builder: (estimator, estimationKey) =>
            builder(estimator, estimationKey, columnWidthOrNull),
      );
    },
  );

  int? _selectedItemIndex(TextBookLoaded state) {
    final line = state.selectedIndex;
    final layout = readingLayoutOf(state);
    if (line == null || layout.isEmpty) return line;
    return layout.itemForLine(line);
  }

  Widget buildOuterList(
    TextBookLoaded state,
    Map<int, List<PersonalNote>> noteMap,
  ) {
    // פריט לכל שורה במצב רגיל ולכל פסקה במצב רציף; tab.index הוא שורת מקור.
    final layout = readingLayoutOf(state);
    _commentaryCardKeys.removeWhere(
      (line, _) => !state.selectedIndices.contains(line),
    );
    final anchor = widget.tab.readingAnchor;
    final initialIndex = layout.itemForLine(anchor.line);
    final itemCount = layout.itemCount;
    final clampedInitial = itemCount == 0
        ? 0
        : initialIndex.clamp(0, itemCount - 1);

    // מרווח ברוחב המסילה בקצה הנגדי ממרכז את הטקסט; הוא בתוך הרשימה ולא
    // סביבה, כדי שטעם שבולט אחרי המילה האחרונה בשורה לא ייחתך בגבול שלה.
    final padding = const EdgeInsetsDirectional.only(
      end: ScrollablePositionedListScrollbar.trackWidth,
    ).resolve(Directionality.of(context));
    // המצב ב-key מאלץ יצירת רשימה חדשה בהחלפת מצב רציף, כך שהפריים הראשון
    // כבר מצויר ב-initialScrollIndex הנכון — בלי הבזק של מיקום שגוי.
    final list = _withReadingExtentEstimation(
      state,
      crossAxisPadding: padding.horizontal,
      builder: (estimateExtent, estimationKey, columnWidth) =>
          ScrollablePositionedList.builder(
            key: ValueKey(
              (widget.tab, _textBookBloc, state.continuousReadingMode),
            ),
            initialScrollIndex: clampedInitial,
            initialAlignment: anchor.alignment,
            initialTargetRectResolver: _initialReadingTargetResolver(
              state,
              anchor,
            ),
            cacheExtentScreens: TickerMode.valuesOf(context).enabled
                ? kReaderCacheExtentScreens
                : 0,
            estimateExtent: estimateExtent,
            estimationKey: estimationKey,
            // הגבהים תלויים ברוחב העמודה בלבד; הבאנר שבפריט 0 פרוס ברוחב המלא.
            crossAxisLayoutKey: columnWidth == null
                ? null
                : state.protection.hasBanner
                ? (width) => (width, columnWidth(width))
                : columnWidth,
            padding: padding,
            itemPositionsListener: widget.tab.lines.positionsListener,
            itemScrollController: widget.tab.lines.itemController,
            scrollOffsetController: widget.tab.lines.offsetController,
            itemCount: itemCount,
            itemBuilder: (context, index) {
              // מבודד את שכבת הצביעה של כל פריט - rebuild של פריט בודד (בחירה/
              // הדגשה) או emit של warming לא יצבע מחדש את כל ה-viewport.
              final tile = RepaintBoundary(
                child: buildExpansiomTile(index, state, noteMap),
              );
              final bannerText = state.protection.bannerText;
              final item = ItemSelectionContainer(
                child: index == 0 && state.protection.hasBanner
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          BookSourceBanner(
                            text: bannerText!,
                            fontSize: widget.textSize,
                          ),
                          tile,
                        ],
                      )
                    : tile,
              );
              return wrapReaderItem(
                item: index,
                layout: readingSegmentsOf(state).layout,
                boxes: widget.tab.lines.itemBoxes,
                child: item,
              );
            },
          ),
    );
    return PageStorage(
      key: ObjectKey(_commentaryStorage),
      bucket: _commentaryStorage,
      child: _trackReadingScroll(list),
    );
  }

  Widget _trackReadingScroll(Widget child) => Listener(
    onPointerDown: (event) => EnhancedGestureDetector.cancelPendingTap(
      _commentaryStorage,
      exceptPointer: event.pointer,
    ),
    onPointerSignal: (_) =>
        EnhancedGestureDetector.cancelPendingTap(_commentaryStorage),
    child: NotificationListener<ScrollStartNotification>(
      onNotification: (notification) {
        if (notification.depth == 0) _cancelCommentaryReveal();
        return false;
      },
      child: widget.tab.lines.trackUserScroll(child),
    ),
  );

  Widget buildExpansiomTile(
    int index,
    TextBookLoaded state,
    Map<int, List<PersonalNote>> noteMap,
  ) {
    // [index] הוא מספר הפריט; פריט של מצב רציף עשוי לעטוף כמה שורות מקור.
    final segments = readingSegmentsOf(state);
    final segment = index < segments.length ? segments[index] : null;
    final primaryLineIndex = segment?.startLineIndex ?? index;
    final isMultiLine =
        state.continuousReadingMode &&
        segment != null &&
        !segment.isHeader &&
        segment.sourceLineIndices.length > 1;
    if (isMultiLine && !segment.isLoaded) {
      return UnloadedParagraphPlaceholder(
        lineCount: segment.sourceLineIndices.length,
        fontSize: widget.textSize,
      );
    }
    final itemLines = segment?.sourceLineIndices ?? [primaryLineIndex];
    bool inItem(int line) =>
        segment?.containsLine(line) ?? line == primaryLineIndex;

    final selectedLines = {
      for (final selected in state.selectedIndices)
        if (inItem(selected)) selected,
    };
    final isSelected = selectedLines.isNotEmpty;
    // גם השורה של לחיצה בפריט שלא פגעה בשורה — הכרטיס שבתוכו שייך לה.
    final selectedLineIndex = isSelected
        ? state.selectedIndices.firstWhere(inItem)
        : primaryLineIndex;
    final marks = readerLineMarks(state, primaryLineIndex);
    final notesForLine =
        noteMap[primaryLineIndex + 1] ?? const <PersonalNote>[];

    ReaderLineHit? hitAt(BuildContext itemContext, Offset globalPosition) =>
        readerItemHit(itemContext, globalPosition, isMultiLine: isMultiLine);

    int? lineAtPointer() => readerItemPointerLine(
      pointerLine: _selectionPointerLineIndex,
      inItem: inItem,
      isMultiLine: isMultiLine,
      primaryLine: primaryLineIndex,
    );

    final theme = Theme.of(context);
    // ברקע ובסמן של פריט רב-שורתי מטפלות השורות עצמן.
    final backgroundColor = isMultiLine
        ? null
        : readerLineBackgroundColor(marks.background, theme.colorScheme);
    final sectionHeadings = isMultiLine
        ? null
        : _sectionHeadingsByLine[primaryLineIndex];

    Widget paragraph(Key key) => Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // הכותרת אינה חלק מהשורה: מחוץ לרקע הבחירה ולמחוות שלה.
        if (sectionHeadings != null)
          AppContextMenuRegion(
            shouldPreserveSelectionOnSecondaryTap: (position) =>
                _shouldPreserveSelectionAt(position, primaryLineIndex, context),
            menuBuilder: (menuContext, position) => _buildContextMenuForIndex(
              state,
              primaryLineIndex,
              menuContext,
              _savedSelectedText.value,
              position,
            ),
            child: _buildSectionHeadings(state, sectionHeadings),
          ),
        // הטקסט של הספר - ללא SelectionArea נפרד, כי יש SelectionArea כללי
        Builder(
          builder: (itemContext) => AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            // decoration קבוע שומר על עומק הטקסט ועל מצב <details> בבחירה.
            decoration: BoxDecoration(color: backgroundColor),
            child: _withSelectionGutter(
              isMultiLine: isMultiLine,
              isSelected: isSelected,
              selectedLines: selectedLines,
              color: theme.colorScheme.primary,
              child: Listener(
                onPointerDown: (event) {
                  if (event.buttons != kPrimaryMouseButton) return;
                  _cancelCommentaryReveal();
                  final hit = hitAt(itemContext, event.position);
                  final root = context.findRenderObject();
                  _selectionPointerLineIndex = isMultiLine
                      ? hit?.lineIndex
                      : primaryLineIndex;
                  _selectionPointerColumn = hit != null || isMultiLine
                      ? hit?.column
                      : root == null
                      ? null
                      : renderedTextOffsetAtPosition(
                          root: root,
                          globalPosition: event.position,
                        );
                },
                child: EnhancedGestureDetector(
                  coordinationGroup: _commentaryStorage,
                  behavior: HitTestBehavior.translucent,
                  onDragSelectionStart: () {
                    if (_hasLocalCorrections) return;
                    // כניסה למצב בחירה בגלל drag
                    final line = lineAtPointer();
                    if (line != null && !_selectionManager.isInSelectionMode) {
                      _selectionManager.setAnchor(line);
                    }
                  },
                  onSingleTap: () {
                    if (_hasLocalCorrections) return;
                    if (_anchorHandledCurrentTap) {
                      _anchorHandledCurrentTap = false;
                      return;
                    }
                    final line = lineAtPointer();
                    if (line == null) return;
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
                    if (state.selectedIndices.contains(line)) {
                      _addTextBookEventIfOpen(const UpdateSelectedIndex(null));
                      return;
                    }
                    _addTextBookEventIfOpen(UpdateSelectedIndex(line));
                    if (widget.showCommentaryAsExpansionTiles &&
                        _hasCommentaries(state, line)) {
                      _revealCommentaryCardBelow(line);
                    }
                  },
                  onDoubleTap: () {
                    if (_hasLocalCorrections) return;
                    // SelectionArea בוחר את המילה; כאן רק מצב הבחירה של השורה.
                    final line = lineAtPointer();
                    if (line == null) return;
                    _focusNode.requestFocus();
                    _selectionManager.enterDoubleClickMode(line);
                  },
                  onShiftClick: () {
                    if (_hasLocalCorrections) return;
                    // Shift+Click → בחירת טווח; SelectionArea בוחר את הטקסט.
                    final line = lineAtPointer();
                    if (line == null) return;
                    _focusNode.requestFocus();
                    if (!_selectionManager.hasAnchor()) {
                      _selectionManager.setAnchor(line);
                    }
                  },
                  onCtrlClick: () {
                    if (_hasLocalCorrections) return;
                    // Ctrl+Click → הוספה/הסרה של השורה מבחירה מרובה
                    final line = lineAtPointer();
                    if (line == null) return;
                    _focusNode.requestFocus();
                    _addTextBookEventIfOpen(
                      UpdateSelectedIndex(line, additive: true),
                    );
                  },
                  onSecondaryTapDown: (details) {
                    // שומר את השורה שנלחצה לשימוש בתפריט ההקשר
                    if (!mounted) return;
                    final hit = hitAt(itemContext, details.globalPosition);
                    _currentSelectedIndex.value =
                        hit?.lineIndex ?? selectedLineIndex;
                    final root = hit?.root ?? context.findRenderObject();
                    final selectedText = _savedSelectedText.value;
                    final occurrenceStart = root == null || selectedText == null
                        ? null
                        : renderedSelectionStartAtPosition(
                            root: root,
                            globalPosition: details.globalPosition,
                            selectedSegment: selectedText,
                            lineRange: hit?.lineRange,
                          );
                    if (occurrenceStart != null) {
                      _selectionStartColumn = occurrenceStart;
                    }
                  },
                  // הטקסט הנבחר נקרא בפתיחת התפריט; האזנה אליו בנתה מחדש את
                  // שכבת התפריט של כל שורה גלויה בכל שינוי בבחירה.
                  child: _ChildBuilder(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2.0),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return BlocBuilder<SettingsBloc, SettingsState>(
                            builder: (context, settingsState) {
                              // בתצוגה מקדימה הרוחב הזמין הוא של החלונית, לא של
                              // אזור קריאה — הגבלת רוחב הטקסט הייתה מצרה אותו שוב.
                              final textMaxWidth = widget.isPreviewMode
                                  ? 0.0
                                  : textColumnMaxWidthOf(
                                      context,
                                      setting: settingsState.textMaxWidth,
                                      availableWidth: constraints.maxWidth,
                                    );
                              final lineContext = _readerLineContext(
                                state,
                                settingsState,
                                noteMap,
                              );
                              final content = isMultiLine
                                  ? _buildMultiLineItem(
                                      itemContext,
                                      itemLines,
                                      state,
                                      lineContext,
                                      settingsState,
                                      noteMap,
                                      commentaryAfter:
                                          widget.showCommentaryAsExpansionTiles &&
                                              isSelected &&
                                              _hasCommentaries(
                                                state,
                                                selectedLineIndex,
                                              )
                                          ? selectedLineIndex
                                          : null,
                                    )
                                  : ReaderLineBlock(
                                      lineIndex: primaryLineIndex,
                                      child: _lineTextWidget(
                                        buildReaderLineSpec(
                                          primaryLineIndex,
                                          lineContext,
                                        ),
                                        state,
                                        notesForLine,
                                      ),
                                    );
                              return textMaxWidth > 0
                                  ? Center(
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(
                                          maxWidth: textMaxWidth,
                                        ),
                                        child: content,
                                      ),
                                    )
                                  : content;
                            },
                          );
                        },
                      ),
                    ),
                    builder: (context, child) {
                      return AppContextMenuRegion(
                        // לחיצה ימנית על הטקסט המסומן (כולל הרווח שבין שורות-תצוגה של
                        // שורת-מקור שנשברה) לא תשחרר את הבחירה; לחיצה על חלק לא-מסומן
                        // מבטלת כרגיל.
                        shouldPreserveSelectionOnSecondaryTap:
                            (globalPosition) {
                              final hit = hitAt(itemContext, globalPosition);
                              return _shouldPreserveSelectionAt(
                                globalPosition,
                                hit?.lineIndex ?? selectedLineIndex,
                                context,
                                hit: hit,
                              );
                            },
                        menuBuilder: (menuCtx, tapPos) {
                          final hit = hitAt(itemContext, tapPos);
                          return [
                            ...ContextMenuUtils.buildInlineLinkContextMenuEntries(
                              menuCtx,
                              tapPos,
                            ),
                            ..._buildContextMenuForIndex(
                              state,
                              hit?.lineIndex ?? selectedLineIndex,
                              menuCtx,
                              _savedSelectedText.value,
                              tapPos,
                              lineRange: hit?.lineRange,
                            ),
                          ];
                        },
                        child: child,
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
        // ספר רש"י כספר ראשי: לעזי השורות מתחתיהן, כמו בחלונית המפרשים.
        if (isRashiTitle(state.book.title))
          for (final lineIndex in itemLines)
            SelectionContainer.disabled(
              child: _inTextColumn(
                LaazCommentarySubBlock.forLine(
                  rashiBookTitle: state.book.title,
                  rashiLineIndex: lineIndex + 1,
                  baseFontSize: widget.textSize,
                ),
              ),
            ),
        // בפריט רב-שורתי הכרטיס מוצג בתוכו, מתחת לשורה שנלחצה (issue #875).
        if (!isMultiLine &&
            widget.showCommentaryAsExpansionTiles &&
            isSelected &&
            _hasCommentaries(state, selectedLineIndex))
          _buildCommentaryCard(state, selectedLineIndex),
      ],
    );

    // החלפת עוגן מחליפה slivers; רק תוכן אינטראקטיבי צריך לעבור ביניהם.
    if (_detailsTag.hasMatch(widget.data[primaryLineIndex])) {
      return Builder(
        builder: (itemContext) => paragraph(
          _ParagraphStateKey(Scrollable.of(itemContext), primaryLineIndex),
        ),
      );
    }
    return paragraph(PageStorageKey('segment-$primaryLineIndex'));
  }

  /// סמן הבחירה שבשוליים: לפריט של שורה אחת — לכל גובהו; לפריט רב-שורתי —
  /// רק לאורך השורות הנבחרות.
  Widget _withSelectionGutter({
    required bool isMultiLine,
    required bool isSelected,
    required Set<int> selectedLines,
    required Color color,
    required Widget child,
  }) {
    if (isMultiLine) {
      return ReaderLineGutter(
        color: color,
        selectedLines: selectedLines,
        child: child,
      );
    }
    // הטקסט מצויר מעל הסמן כדי שאותיות בקצה השורה לא יוסתרו.
    return CustomPaint(
      painter: isSelected ? SelectionGutterPainter(color) : null,
      child: child,
    );
  }

  void _cancelCommentaryReveal() =>
      _cancelCommentaryRevealFor(widget.tab.lines);

  void _cancelCommentaryRevealFor(LineScrollController lines) {
    if (_commentaryRevealLine == null) return;
    _commentaryRevealGeneration++;
    _commentaryRevealLine = null;
    _commentaryRevealSelectionObserved = false;
    _commentaryCardAnchor?.cancel();
    _commentaryCardAnchor = null;
    final controller = lines.itemController.listController;
    controller?.cancelPositioning();
    controller?.stickTarget = null;
  }

  void _revealCommentaryCardBelow(int line) {
    final scroll = widget.tab.lines.itemController.scrollController;
    final atEnd =
        scroll != null &&
        scroll.hasClients &&
        scroll.position.extentAfter <= 0.5;
    widget.tab.lines.beginUserNavigation();
    _commentaryRevealLine = line;
    _commentaryRevealAtEnd = atEnd;
    if (atEnd) {
      widget.tab.lines.itemController.listController?.stickTarget =
          const StickTarget.bottom();
    }
    _onTextBookState(_textBookBloc.state);
  }

  Future<void> _positionCommentaryCard(int line, int generation) async {
    if (!mounted || generation != _commentaryRevealGeneration) return;
    final lines = widget.tab.lines;
    final scroll = lines.itemController.scrollController;
    final card = _commentaryCardKeys[line]?.currentContext?.findRenderObject();
    if (scroll == null ||
        !scroll.hasClients ||
        card is! RenderBox ||
        !card.hasSize) {
      return;
    }
    final viewport = RenderAbstractViewport.of(card);
    final viewportBox = viewport as RenderBox;
    final top = card.localToGlobal(Offset.zero, ancestor: viewportBox).dy;
    final height = scroll.position.viewportDimension;
    final tail = scroll.position.extentAfter + height - top - card.size.height;
    if (_commentaryRevealAtEnd &&
        tail <= height * 0.25 &&
        top >= 0 &&
        card.size.height + tail <= height + 0.5) {
      return;
    }
    lines.itemController.listController?.stickTarget = null;
    if (scroll.position.isScrollingNotifier.value) scroll.jumpTo(scroll.offset);
    if (top >= 0 && top <= height * 0.15) {
      _commentaryCardAnchor = lines.itemController.listController
          ?.preserveHeader(card);
      return;
    }
    final state = _textBookBloc.state;
    if (state is! TextBookLoaded) return;
    final index = readingLayoutOf(state).itemForLine(line);
    await lines.itemController.withoutNotifying(
      () => lines.itemController.jumpToAsync(
        index: index,
        alignment: 0.15,
        targetRectResolver: (_, item) {
          final target = _commentaryCardKeys[line]?.currentContext
              ?.findRenderObject();
          if (target is! RenderBox || !target.hasSize) return null;
          final offset = target.localToGlobal(Offset.zero, ancestor: item);
          return offset & target.size;
        },
      ),
    );
    if (!mounted ||
        generation != _commentaryRevealGeneration ||
        !card.attached) {
      return;
    }
    _commentaryCardAnchor = lines.itemController.listController?.preserveHeader(
      card,
    );
  }

  /// מציב את [child] ברוחב עמודת הטקסט, כמו שורות הספר.
  Widget _inTextColumn(Widget child) => LayoutBuilder(
    builder: (context, constraints) => BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, settingsState) {
        final width = widget.isPreviewMode
            ? 0.0
            : textColumnMaxWidthOf(
                context,
                setting: settingsState.textMaxWidth,
                availableWidth: constraints.maxWidth,
              );
        return width > 0
            ? Center(
                child: SizedBox(width: width, child: child),
              )
            : child;
      },
    ),
  );

  /// כותרות נושא/פרשה שמוזרקות מעל השורה, ברוחב עמודת הטקסט.
  Widget _buildSectionHeadings(TextBookLoaded state, List<String> headings) {
    return LayoutBuilder(
      builder: (context, constraints) =>
          BlocBuilder<SettingsBloc, SettingsState>(
            builder: (context, settingsState) {
              final textMaxWidth = widget.isPreviewMode
                  ? 0.0
                  : textColumnMaxWidthOf(
                      context,
                      setting: settingsState.textMaxWidth,
                      availableWidth: constraints.maxWidth,
                    );
              final text = _sectionHeadingsText(state, settingsState, headings);
              return textMaxWidth > 0
                  ? Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: textMaxWidth),
                        child: text,
                      ),
                    )
                  : text;
            },
          ),
    );
  }

  Widget _sectionHeadingsText(
    TextBookLoaded state,
    SettingsState settingsState,
    List<String> headings,
  ) => SmartTextWidget(
    text: sectionHeadingsHtml(headings),
    settings: RenderSettings.fromProfile(
      state.bodyDisplayProfile,
      fontSize: widget.textSize,
      fontFamily: settingsState.fontFamily,
      fontWeight: settingsState.fontBold ? FontWeight.bold : null,
      lineHeight: settingsState.lineHeight,
    ),
  );

  /// כרטיס המפרשים שמוצג מתחת לשורה נבחרת במצב "מפרשים מתחת לטקסט".
  /// SelectionArea משלו; disabled מנתק אותו מאזור הבחירה של הטקסט הראשי —
  /// קינון SelectionArea שובר את ההעתקה (issue #530).
  Widget _buildCommentaryCard(TextBookLoaded state, int lineIndex) {
    _commentaryCardKeys.removeWhere(
      (line, key) => line != lineIndex && key.currentContext == null,
    );
    return KeyedSubtree(
      key: _commentaryCardKeys.putIfAbsent(lineIndex, GlobalKey.new),
      child: PageStorage(
        bucket: _commentaryStorage,
        child: KeyedSubtree(
          key: PageStorageKey((
            BookIdentity.keyOf(state.book),
            state.book.versionTitle,
            lineIndex,
          )),
          child: SelectionContainer.disabled(
            child: _CommentaryCard(
              key: ValueKey('commentary_card_$lineIndex'),
              index: lineIndex,
              textSize: widget.textSize,
              openBookCallback: widget.openBookCallback,
              viewportHeight: _viewportHeight,
              selectionSyncController: widget.selectionSyncController,
              searchText: state.searchText,
              scrollTargetListenable: _anchorScrollTargetNotifier,
              onOpenPersonalNote: widget.onOpenCommentaryPersonalNote,
            ),
          ),
        ),
      ),
    );
  }

  ReaderLineContext _readerLineContext(
    TextBookLoaded state,
    SettingsState settingsState,
    Map<int, List<PersonalNote>> noteMap,
  ) => ReaderLineContext(
    state: state,
    lines: widget.data,
    profile: state.bodyDisplayProfile,
    fontSize: widget.textSize,
    fontFamily: settingsState.fontFamily,
    fontWeight: settingsState.fontBold ? FontWeight.bold : null,
    lineHeight: settingsState.lineHeight,
    sectionHeadings: _sectionHeadingsByLine,
    lineHtml: (line) => _lineHtml(
      line,
      state,
      settingsState,
      noteMap[line + 1] ?? const <PersonalNote>[],
    ),
  );

  /// השורה עם כל ההזרקות, לפני עיבוד התצוגה.
  String _lineHtml(
    int lineIndex,
    TextBookLoaded state,
    SettingsState settingsState,
    List<PersonalNote> notesForLine,
  ) {
    final rawText = widget.data[lineIndex];
    final linksForLine =
        settingsState.enableHtmlLinks && state.book.versionTitle == null
        ? (state.linksByLine[lineIndex + 1] ?? const <Link>[])
              .where((link) => link.start != null && link.end != null)
              .toList()
        : const <Link>[];
    // קישורי inline ראשונים — האופסטים שלהם גולמיים.
    var data = injectDivineNameMarkers(
      injectInlineLinks(rawText, linksForLine),
      state.divineNames,
      lineIndex,
    );
    data = inline_notes.addInlineNotePreviewLinks(
      data,
      lineIndex: lineIndex,
      dbNotes: state.bookNotes,
    );
    data = _injectNumberedNoteMarkers(data, lineIndex, state);
    // סמני עוגן-מילה — לפני כל עיבוד שמוסיף תוכן גלוי.
    data = _injectAnchorMarkersForLine(data, lineIndex, state);
    // סמן חלוקה (אות/סעיף) — תוכן גלוי, אחרי סמני העוגן.
    data = prependSectionMarker(data, _sectionMarkersByLine[lineIndex]);
    // סימוני הערות אישיות — אחרונים.
    return buildAnnotatedLineHtml(
      rawLine: data,
      sourceLine: rawText,
      notesForLine: notesForLine,
      lineIndex0: lineIndex,
      underlineColor: Theme.of(context).colorScheme.primary,
      replaceHolyNames: state.bodyDisplayProfile.replaceHolyNames,
    );
  }

  Widget _lineTextWidget(
    ReaderLineSpec spec,
    TextBookLoaded state,
    List<PersonalNote> notesForLine,
  ) {
    final lineIndex = spec.lineIndex;
    final text = SmartTextWidget(
      text: spec.html,
      highlightBookId: state.book.title,
      highlightBookUid: PluginBookIdentity.uidOf(state.book),
      highlightBookDbId: state.book.id,
      highlightBookType: PluginBookIdentity.typeOf(state.book),
      highlightBookSource: PluginBookIdentity.sourceOf(state.book),
      highlightSectionIndex: lineIndex,
      highlightSourceText: spec.sourceText,
      widgetKey: ValueKey('html_${widget.tab.book.title}_$lineIndex'),
      settings: spec.settings,
      onOpenBook: widget.openBookCallback,
      onNoteTap: notesForLine.isEmpty ? null : (line) => _onInlineNoteTap(line),
      onAnchorTap: _handleAnchorTap,
      onAnchorHover: _handleAnchorHover,
      onAnchorHoverExit: _handleAnchorHoverExit,
      onTouchPreview: _handleTouchPreview,
    );
    if (widget.isPreviewMode) return text;
    return PluginCorrectionParagraph(
      tabId: _correctionTabId,
      sectionIndex: lineIndex,
      sourceText: spec.sourceText,
      settings: spec.settings,
      original: text,
      sessionActive: _hasLocalCorrections,
    );
  }

  /// פריט של כמה שורות: רצפים ממוזגים לפסקה, שורות-בלוק בנפרד, וכרטיס
  /// המפרשים מתחת לשורה [commentaryAfter].
  Widget _buildMultiLineItem(
    BuildContext context,
    List<int> itemLines,
    TextBookLoaded state,
    ReaderLineContext lineContext,
    SettingsState settingsState,
    Map<int, List<PersonalNote>> noteMap, {
    int? commentaryAfter,
  }) => buildReaderMultiLineItem(
    context,
    itemLines: itemLines,
    lineContext: lineContext,
    blockText: (spec) => _lineTextWidget(
      spec,
      state,
      noteMap[spec.lineIndex + 1] ?? const <PersonalNote>[],
    ),
    blockHeadings: (headings) =>
        _sectionHeadingsText(state, settingsState, headings),
    onTapUrl: (url) => handleReaderParagraphUrl(
      context,
      url,
      onTouchPreview: _handleTouchPreview,
      onAnchorTap: _handleAnchorTap,
      onNoteTap: _onInlineNoteTap,
      openBook: (tab) => widget.openBookCallback(tab),
    ),
    onAnchorHover: _handleAnchorHover,
    onAnchorExit: _handleAnchorHoverExit,
    splitAfter: commentaryAfter,
    belowSplit: (line) => _buildCommentaryCard(state, line),
    // שדה עריכה הוא לפסקת מקור אחת; פסקה ממוזגת אינה ניתנת לעריכה.
    linesAsBlocks: _hasLocalCorrections,
  );

  /// בדיקה אם יש מפרשים לאינדקס מסוים
  bool _hasCommentaries(TextBookLoaded state, int index) {
    return hasCommentariesForLine(
      activeCommentators: state.activeCommentators,
      content: state.content,
      linksByLine: state.linksByLine,
      index: index,
      bookNotes: state.bookNotes,
    );
  }

  @override
  Widget build(BuildContext context) {
    // קישורים פנימיים מנווטים דרך ה-scope — גם בתצוגה המקדימה, שאינה בתוך הקורא.
    final bloc = context.select<TextBookBloc, TextBookBloc>((bloc) => bloc);
    return LineScrollScope(
      controller: widget.tab.lines,
      child: buildKeyboardListener(bloc),
    );
  }

  String get _correctionTabId =>
      PluginCorrectionSessionService.knownTabIdFor(widget.tab) ?? '';

  bool get _hasLocalCorrections =>
      !widget.isPreviewMode &&
      PluginCorrectionSessionService.instance.hasSessionForTab(
        _correctionTabId,
      );

  /// הבחירה חסומה כל עוד הסשן פעיל, ולכן מנקים אותה רק בפתיחה ובסיום.
  void _onLocalCorrectionChanged() {
    if (!mounted || _disposed) return;
    final active = _hasLocalCorrections;
    if (active == _localCorrectionActive) return;
    _localCorrectionActive = active;
    setState(() {});
    if (!active && _focusNode.hasFocus) _focusNode.requestFocus();
    _sourceSelection = null;
    _savedSelectedIndex.value = null;
    _currentSelectedIndex.value = null;
    _clearSelectionState();
    _selectionAreaKey.currentState?.selectableRegion.clearSelection();
    widget.onSelectedTextChanged?.call(null, null, null);
  }
}

// ב-Windows אובדן פוקוס החלון מעביר את הפוקוס ל-rootScope כשה-lifecycle עדיין
// resumed; בלי זה SelectableRegion מנקה את הבחירה.
class _KeepSelectionOnWindowBlurFocusNode extends FocusNode {
  @override
  void notifyListeners() {
    if (SchedulerBinding.instance.lifecycleState == AppLifecycleState.resumed &&
        FocusManager.instance.primaryFocus == FocusManager.instance.rootScope) {
      return;
    }
    super.notifyListeners();
  }
}

class _CommentaryCard extends StatefulWidget {
  final int index;
  final double textSize;
  final Function(OpenedTab) openBookCallback;
  final double viewportHeight;
  final SelectionSyncController? selectionSyncController;
  final String searchText;
  final ValueListenable<_CommentaryScrollTarget?> scrollTargetListenable;
  final void Function(Link link, int lineNumber)? onOpenPersonalNote;

  const _CommentaryCard({
    super.key,
    required this.index,
    required this.textSize,
    required this.openBookCallback,
    required this.viewportHeight,
    this.selectionSyncController,
    this.searchText = '',
    required this.scrollTargetListenable,
    this.onOpenPersonalNote,
  });

  @override
  State<_CommentaryCard> createState() => _CommentaryCardState();
}

class _CommentaryCardState extends State<_CommentaryCard> {
  final GlobalKey<CommentaryListBaseState> _commentaryKey = GlobalKey();
  late final ValueNotifier<String> _highlightNotifier;
  final ValueNotifier<int> _totalNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> _currentIndexNotifier = ValueNotifier<int>(0);

  void _onScrollTargetChanged() {
    final target = widget.scrollTargetListenable.value;
    if (target == null ||
        !shouldHandleCommentaryScrollTarget(
          cardIndex: widget.index,
          targetLineIndex: target.lineIndex,
        )) {
      return;
    }
    _commentaryKey.currentState?.scrollToCommentator(
      target.title,
      linkKey: target.linkKey,
      sourceLine: target.lineIndex,
    );
  }

  @override
  void initState() {
    super.initState();
    _highlightNotifier = ValueNotifier<String>(widget.searchText);
    widget.scrollTargetListenable.addListener(_onScrollTargetChanged);
    // בדיקה מיידית: אולי הנוטיפייר כבר הוגדר לפני שה-card נוצר
    final initialTarget = widget.scrollTargetListenable.value;
    if (initialTarget != null &&
        shouldHandleCommentaryScrollTarget(
          cardIndex: widget.index,
          targetLineIndex: initialTarget.lineIndex,
        )) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _commentaryKey.currentState?.scrollToCommentator(
            initialTarget.title,
            linkKey: initialTarget.linkKey,
            sourceLine: initialTarget.lineIndex,
          );
        }
      });
    }
  }

  @override
  void didUpdateWidget(_CommentaryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollTargetListenable != widget.scrollTargetListenable) {
      oldWidget.scrollTargetListenable.removeListener(_onScrollTargetChanged);
      widget.scrollTargetListenable.addListener(_onScrollTargetChanged);
    }
    if (oldWidget.searchText != widget.searchText) {
      _highlightNotifier.value = widget.searchText;
    }
  }

  @override
  void dispose() {
    widget.scrollTargetListenable.removeListener(_onScrollTargetChanged);
    _highlightNotifier.dispose();
    _totalNotifier.dispose();
    _currentIndexNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // התקציב כולל גם את סרגל החיפוש והמרווחים, כדי שכותרת הכרטיס תישאר גלויה.
    final maxHeight = widget.viewportHeight > 0
        ? widget.viewportHeight * 0.75
        : MediaQuery.of(context).size.height * 0.75;

    return LayoutBuilder(
      builder: (context, constraints) {
        return BlocBuilder<SettingsBloc, SettingsState>(
          builder: (context, settingsState) {
            // שימוש באותו רוחב מקסימלי כמו הטקסט
            final textMaxWidth = textColumnMaxWidthOf(
              context,
              setting: settingsState.textMaxWidth,
              availableWidth: constraints.maxWidth,
            );

            final commentaryContainer = Container(
              margin: const EdgeInsets.only(bottom: 8.0),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: AppTokens.borderRadiusAll,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: AppTokens.borderRadiusAll,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: maxHeight,
                    minHeight: maxHeight < 50 ? maxHeight : 50,
                  ),
                  child: CommentaryListBase(
                    key: _commentaryKey,
                    indexes: [widget.index],
                    fontSize: settingsState.commentatorsFontSize,
                    openBookCallback: widget.openBookCallback,
                    showSearch: false,
                    selectionSyncController: widget.selectionSyncController,
                    shrinkWrap: true,
                    highlightQueryListenable: _highlightNotifier,
                    externalTotalResultsNotifier: _totalNotifier,
                    externalCurrentIndexNotifier: _currentIndexNotifier,
                    onOpenPersonalNote: widget.onOpenPersonalNote,
                    personalNotesLoader: loadStoredPersonalNotes,
                  ),
                ),
              ),
            );

            final content = ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.searchText.isNotEmpty)
                    _CommentarySearchNavBar(
                      totalNotifier: _totalNotifier,
                      currentIndexNotifier: _currentIndexNotifier,
                      onPrev: () =>
                          _commentaryKey.currentState?.navigateSearchPrev(),
                      onNext: () =>
                          _commentaryKey.currentState?.navigateSearchNext(),
                    ),
                  Flexible(child: commentaryContainer),
                ],
              ),
            );

            // מרכוז אופקי בלבד (topCenter) באותו רוחב כמו הטקסט. Center מלא
            // היה ממרכז גם אנכית וגורם לרווח למעלה כשהמפרשים מכווצים/קצרים.
            if (textMaxWidth > 0) {
              return Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: textMaxWidth),
                  child: content,
                ),
              );
            }
            return content;
          },
        );
      },
    );
  }
}

/// סרגל ניווט מינימלי לתוצאות חיפוש במפרשים (תצוגה משולבת).
/// מופיע בין שורת הטקסט הראשי לכרטיס המפרשים כשיש תוצאות חיפוש.
class _CommentarySearchNavBar extends StatelessWidget {
  final ValueNotifier<int> totalNotifier;
  final ValueNotifier<int> currentIndexNotifier;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const _CommentarySearchNavBar({
    required this.totalNotifier,
    required this.currentIndexNotifier,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: totalNotifier,
      builder: (context, total, _) {
        if (total == 0) return const SizedBox.shrink();
        return ValueListenableBuilder<int>(
          valueListenable: currentIndexNotifier,
          builder: (context, current, _) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'במפרשים: ${current + 1}/$total',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: const Icon(
                        FluentIcons.chevron_up_24_regular,
                        size: 16,
                      ),
                      onPressed: current > 0 ? onPrev : null,
                      tooltip: 'תוצאה קודמת במפרשים',
                    ),
                  ),
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: const Icon(
                        FluentIcons.chevron_down_24_regular,
                        size: 16,
                      ),
                      onPressed: current < total - 1 ? onNext : null,
                      tooltip: 'תוצאה הבאה במפרשים',
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _CopySelectedTextIntent extends Intent {
  const _CopySelectedTextIntent();
}

/// פעיל רק כשקיימת בחירה — אחרת ESC מחלחל הלאה (למשל יציאה ממסך מלא
/// ב-KeyboardShortcuts הגלובלי) במקום להיבלע כאן.
class _ClearSelectionAction extends Action<ClearSelectionIntent> {
  _ClearSelectionAction(this._view);

  final _CombinedViewState _view;

  @override
  bool get isActionEnabled =>
      _view._selectionManager.isInSelectionMode ||
      _view._savedSelectedText.value != null;

  @override
  Object? invoke(ClearSelectionIntent intent) {
    _view._selectionManager.exitSelectionMode();
    _view._savedSelectedText.value = null;
    _view._savedSelectedIndex.value = null;
    _view._currentSelectedIndex.value = null;
    _view._selectionLineStart = null;
    _view._selectionLineEnd = null;
    _view._selectionStartColumn = null;
    _view.widget.onSelectedTextChanged?.call(null, null, null);
    return null;
  }
}
