import 'package:otzaria/text_book/view/widgets/selection_gutter_painter.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/text_book/utils/reader_paragraph_copy.dart';
import 'package:otzaria/text_book/utils/reader_menu_entries.dart';
import 'package:otzaria/text_book/utils/reader_plugin_menu_entries.dart';
import 'package:otzaria/book_common/utils/commentators_menu.dart';
import 'package:otzaria/shortcuts/dynamic/dynamic_shortcut.dart';
import 'package:otzaria/shortcuts/dynamic/dynamic_shortcut_registry.dart';
import 'package:otzaria/text_display/view/copy_as_menu.dart';

import 'dart:async';

import 'package:flutter/gestures.dart' show kPrimaryMouseButton;
import 'package:flutter/cupertino.dart'
    show cupertinoTextSelectionHandleControls;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform, visibleForTesting;
import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/utils/reader_build_policy.dart';
import 'package:otzaria/text_book/utils/reading_segment_navigation.dart';
import 'package:otzaria/bookmarks/utils/section_bookmark.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/book_common/models/commentator_group.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_commentary_selection.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_settings_manager.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_workspace_scope.dart';
import 'package:otzaria/tools/dictionary/widgets/laaz_commentary_subblock.dart';
import 'package:otzaria/utils/navigation/talmud_bavli_open_format.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/services/target_line_links_service.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/text_book/models/book_notes.dart';
import 'package:otzaria/widgets/feedback/scrollable_positioned_list_scrollbar.dart';
import 'package:positioned_sliver_list/positioned_list.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/widgets/text/rtl_selection_shortcuts.dart';
import 'package:otzaria/widgets/text/selection_copy_shortcuts.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/utils/ui/context_menu_utils.dart' show ContextMenuUtils;
import 'package:otzaria/core/messages/text_book_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/personal_notes/personal_notes_system.dart';
import 'package:otzaria/personal_notes/widgets/personal_notes_sidebar.dart';
import 'package:otzaria/personal_notes/utils/personal_note_source_selection.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_changes.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/view/widgets/book_source_banner.dart';
import 'package:otzaria/text_book/view/sibling_commentaries_menu.dart';
import 'package:otzaria/text_book/view/tabbed_commentary_panel.dart';
import 'package:otzaria/widgets/smart_text/smart_text.dart';
import 'package:otzaria/text_book/view/error_report_dialog.dart';
import 'package:otzaria/widgets/misc/direct_link_menu_entries.dart';
import 'package:otzaria/widgets/misc/smooth_wheel_scroll.dart';
import 'package:otzaria/text_book/view/selection/enhanced_gesture_detector.dart';
import 'package:otzaria/text_book/view/selection/selection_persistence.dart';
import 'package:otzaria/book_common/selection/selection_hit_test.dart';
import 'package:otzaria/text_book/view/selection/selected_text_copy.dart';
import 'package:otzaria/book_common/selection/selected_text_restore.dart';
import 'package:otzaria/book_protection/models/book_protection.dart';
import 'package:otzaria/book_protection/repository/book_protection_repository.dart';
import 'package:otzaria/book_protection/utils/copy_guard.dart';
import 'package:otzaria/tools/dictionary/repository/dictionary_lookup_repository.dart';
import 'package:otzaria/plugins/services/plugin_highlight_reveal_service.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/models/plugin_book_identity.dart';
import 'package:otzaria/text_book/view/selection/selection_sync_controller.dart';
import 'package:otzaria/book_common/utils/commentary_plugin_menu_entries.dart';
import 'package:otzaria/plugins/utils/plugin_context_menu_entries.dart';
import 'package:otzaria/text_book/utils/commentators_context_menu.dart';
import 'package:otzaria/text_book/utils/note_inline_render.dart';
import 'package:otzaria/text_book/utils/inline_notes_utils.dart'
    as inline_notes;
import 'package:otzaria/book_common/utils/link_anchor_markers.dart';
import 'package:otzaria/text_book/utils/link_preview_utils.dart';
import 'package:otzaria/text_book/utils/numbered_note_markers.dart';
import 'package:otzaria/text_book/utils/reading_segments.dart';
import 'package:otzaria/text_book/view/reader_line/reader_line_item.dart';
import 'package:otzaria/text_book/view/reader_line/reader_line_render.dart';
import 'package:otzaria/text_book/view/reader_line/reader_line_spec.dart';
import 'package:otzaria/text_book/view/widgets/unloaded_paragraph_placeholder.dart';
import 'package:otzaria/text_display/text_display_exports.dart';
import 'package:otzaria/widgets/misc/link_preview_overlay.dart';
import 'package:otzaria/text_book/view/reading_viewport/line_scroll_controller.dart';
import 'package:otzaria/text_book/view/widgets/reading_extent_estimation.dart';
import 'package:otzaria/theme/app_fonts.dart';

/// מחזירה האם אירוע המקלדת צריך להניע גלילה/ניווט שורה בצורת הדף.
///
/// [isShiftPressed] - כש-Shift לחוץ הניווט מוותר, כדי שחיצים ירחיבו את בחירת
/// הטקסט (Shift+חץ) במקום לדלג בין שורות או לגלול.
/// חריג: Shift+Space — גלילה מסך אחד אחורה, כמקובל בקוראים.
bool shouldHandlePageShapeNavigationKeyEvent(
  KeyEvent event, {
  bool isShiftPressed = false,
}) {
  if (isShiftPressed && event.logicalKey != LogicalKeyboardKey.space) {
    return false;
  }
  return event is KeyDownEvent || event is KeyRepeatEvent;
}

@visibleForTesting
Map<String, dynamic> buildPageShapePluginSelectionPayload({
  required String selectedText,
  required String bookTitle,
  required int sectionIndex,
  String? currentRef,
  int? bookDbId,
  String? bookType,
  String? bookSource,
}) {
  return {
    'text': selectedText,
    'renderedSelectedText': selectedText,
    'currentRef': currentRef ?? '',
    'currentBook': bookTitle,
    'currentBookId': bookTitle,
    'bookId': bookTitle,
    'currentIndex': sectionIndex,
    'sectionIndex': sectionIndex,
    'id': ?bookDbId,
    'type': ?bookType,
    'source': ?bookSource,
  };
}

/// הפעולה שיש לבצע על אירוע מקלדת בחלונית מפרש (בצורת הדף).
enum CommentaryKeyAction { none, copy, addNote, reportError }

/// מחליטה איזו פעולה לבצע על אירוע מקלדת בחלונית מפרש, ללא תופעות לוואי.
///
/// המפרשים בצורת הדף לוכדים קיצורים גלובלית (ללא פוקוס): רק חלונית המפרש
/// שבה סומן טקסט לאחרונה ([isActiveCommentary]) מטפלת. בלי טיפול כאן, קיצור
/// "הוסף הערה" מתבעבע אל ה-`KeyboardListener` של הספר הראשי ופותח הערה על
/// גוף הספר במקום על המפרש — וגם מבטל את הבחירה.
///
/// [addNoteShortcut] - מחרוזת קיצור "הוסף הערה" מההגדרות (כגון `'ctrl+n'`).
/// פרמטרי ה-modifiers האופציונליים מאפשרים בדיקות יחידה בלי מצב חומרה אמיתי.
CommentaryKeyAction resolveCommentaryKeyAction({
  required KeyEvent event,
  required bool isActiveCommentary,
  required bool hasSelection,
  required bool hasSelectedIndex,
  required String addNoteShortcut,
  String reportErrorShortcut = '',
  bool isReportUnavailable = false,
  bool? isControlPressed,
  bool? isShiftPressed,
  bool? isAltPressed,
  bool? isMetaPressed,
}) {
  // כל הקיצורים כאן רלוונטיים רק במפרש הפעיל וכשיש בו טקסט מסומן.
  if (!isActiveCommentary) return CommentaryKeyAction.none;
  if (event is! KeyDownEvent) return CommentaryKeyAction.none;
  if (!hasSelection) return CommentaryKeyAction.none;

  final ctrl = isControlPressed ?? HardwareKeyboard.instance.isControlPressed;
  final meta = isMetaPressed ?? HardwareKeyboard.instance.isMetaPressed;
  if ((ctrl || meta) && event.logicalKey == LogicalKeyboardKey.keyC) {
    return CommentaryKeyAction.copy;
  }

  final matchesAddNote = ShortcutHelper.matchesShortcut(
    event,
    addNoteShortcut,
    isControlPressed: isControlPressed,
    isShiftPressed: isShiftPressed,
    isAltPressed: isAltPressed,
    isMetaPressed: isMetaPressed,
  );
  if (matchesAddNote && hasSelectedIndex) {
    return CommentaryKeyAction.addNote;
  }

  if (!isReportUnavailable &&
      reportErrorShortcut.isNotEmpty &&
      ShortcutHelper.matchesShortcut(
        event,
        reportErrorShortcut,
        isControlPressed: isControlPressed,
        isShiftPressed: isShiftPressed,
        isAltPressed: isAltPressed,
        isMetaPressed: isMetaPressed,
      )) {
    return CommentaryKeyAction.reportError;
  }

  return CommentaryKeyAction.none;
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

/// האם הפוקוס באזור בחירה שאינו הטקסט הראשי — חלונית מפרש, או חלונית צפה
/// (שכבת-על מחוץ לכל מסך; פאנל צד באותו מסך אינו נחשב).
bool isOtherSelectionFocusNode(FocusNode? focusNode) {
  final context = focusNode?.context;
  if (context == null) return false;
  final viewer = context.findAncestorStateOfType<_SimpleTextViewerState>();
  if (viewer != null) return !viewer.widget.isMainText;
  return ModalRoute.of(context) == null &&
      context.findAncestorStateOfType<SelectableRegionState>() != null;
}

/// היסט הגלילה של מקש בחלונית מפרש: שורה = 50px, עמוד = 80% מהחלונית
/// (כמו `ScrollAction` של Flutter). null — המקש אינו מקש גלילה.
@visibleForTesting
double? commentaryKeyScrollOffset(
  LogicalKeyboardKey key,
  double viewportHeight,
) {
  if (key == LogicalKeyboardKey.arrowDown) return 50;
  if (key == LogicalKeyboardKey.arrowUp) return -50;
  if (key == LogicalKeyboardKey.pageDown) return viewportHeight * 0.8;
  if (key == LogicalKeyboardKey.pageUp) return -viewportHeight * 0.8;
  return null;
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

  // הקטע הנבחר אינו על המסך. נמשיך מקצה החלון הנראה שבכיוון הקטע: אם הקטע
  // מתחת לחלון (השהיית גלילה בלחיצה רציפה על חץ-למטה, או גלילה ידנית מעלה) —
  // נמשיך מהקצה התחתון כדי שהניווט ימשיך למטה ולא יקפוץ לראש החלון.
  int? edgeTowardSelected(List<int> sortedVisible) {
    if (sortedVisible.isEmpty) return null;
    if (selectedIndex != null && selectedIndex > sortedVisible.last) {
      return sortedVisible.last;
    }
    return sortedVisible.first;
  }

  final liveEdge = edgeTowardSelected(sortedLiveVisibleIndices);
  if (liveEdge != null) return liveEdge;

  final stateEdge = edgeTowardSelected(sortedStateVisibleIndices);
  if (stateEdge != null) return stateEdge;

  return selectedIndex ?? 0;
}

/// שומרת הערת מפרש דרך ה-repository, ממפה את תוצאת העורך לקריאת `addNote`.
///
/// מופרדת לפונקציה עצמאית כדי לאפשר בדיקה ישירה של מיפוי הפרמטרים (ה-`bookId`
/// של המפרש, מספר השורה והתוכן) ללא תלות ב-UI של עורך ה-Quill.
@visibleForTesting
Future<void> saveCommentaryNoteToRepository({
  required PersonalNotesRepository repository,
  required String bookId,
  required int lineNumber,
  required PersonalNoteEditorResult result,
  String? selectedText,
  int? selectionColumn,
  String? sourceSelectedText,
  int? sourceSelectionOffset,
  bool punctuationHidden = false,
  int? categoryId,
}) {
  return repository.addNote(
    bookId: bookId,
    lineNumber: lineNumber,
    content: result.content,
    contentPlain: result.contentPlain,
    contentFormat: result.contentFormat,
    selectedText: selectedText,
    selectionColumn: selectionColumn,
    sourceSelectedText: sourceSelectedText,
    sourceSelectionOffset: sourceSelectionOffset,
    punctuationHidden: punctuationHidden,
    categoryId: categoryId,
  );
}

const _readerListPadding = EdgeInsets.all(4);

/// תצוגת טקסט פשוטה - משמשת גם לטקסט המרכזי וגם למפרשים
class SimpleTextViewer extends StatefulWidget {
  final List<String> content;
  final double fontSize;
  final String? fontFamily;
  final Function(OpenedTab) openBookCallback;

  /// גלילה ומיקום של טקסט ראשי, בשורות מקור. בלעדיו נוצר אחד פנימי.
  final LineScrollController? lines;

  /// בקרי הרשימה של מפרש; לטקסט ראשי הם באים מ-[lines].
  final ItemScrollController? scrollController;
  final ItemPositionsListener? positionsListener;

  /// גלילה יחסית בפיקסלים של מפרש; בלעדיו הסנכרון הרציף נופל לקפיצות.
  final ScrollOffsetController? scrollOffsetController;
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

  /// הטאב שאליו שייכת תצוגה זו. משמש לזיהוי האם הטאב פעיל כרגע — כדי שטאב
  /// צורת-הדף שנשמר חי ברקע לא יחטוף פוקוס מקלדת וישבור בחירת טקסט בטאב הפעיל.
  final OpenedTab? tab;

  /// מחזירה את כתובת היעד עבור אינדקס פריט בסרגל הגלילה. כשהיא מסופקת,
  /// ריחוף/גרירה על הסרגל הפנימי מציגים תווית צפה עם הכתובת. כשהיא null
  /// אין תווית. רלוונטי רק כש-[useInternalScroll] = true.
  final String Function(int index)? labelForIndex;

  /// repository לשמירת הערות מפרשים. ניתן להזרקה בבדיקות; בייצור נוצר ברירת מחדל.
  final PersonalNotesRepository? notesRepository;
  final bool isPersonalNotesTabActive;
  final void Function(String bookId, int? categoryId, int lineNumber)?
  onOpenCommentaryPersonalNote;

  /// לשונית המפרשים פתוחה כרגע בחלונית הצד — פריטי הפתיחה בתפריט ההקשר
  /// מיותרים במצב זה.
  final bool isCommentatorsTabActive;

  /// The links tab of the side pane is open, so the entry that opens it is
  /// left out of the context menu.
  final bool isLinksTabActive;

  /// פתיחת לשונית המפרשים בחלונית הצד. כש-null תת-התפריט "מפרשים" לא יוצג.
  final VoidCallback? onOpenCommentatorsPane;

  /// פתיחת לשונית המפרשים עם חלונית בחירת המפרשים פרושה.
  final VoidCallback? onOpenCommentatorsPaneWithFilter;

  /// קישורי עוגן של ספר המפרש עצמו אל מפרשי-העל שלו (מפתח: מספר שורה
  /// 1-based) — סמני אותיות שער הציון וכד' בעמודת מפרש בצורת הדף.
  /// בטקסט הראשי נשאר null: העוגנים שם נקראים מ-state.linksByLine.
  final Map<int, List<Link>>? anchorLinksByLine;

  /// הערות השוליים (`line_note`) של ספר המפרש, שעליהן נמדדים [anchorLinksByLine].
  final BookNotes anchorBookNotes;

  const SimpleTextViewer({
    super.key,
    required this.content,
    required this.fontSize,
    this.fontFamily,
    required this.openBookCallback,
    this.lines,
    this.scrollController,
    this.positionsListener,
    this.scrollOffsetController,
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
    this.tab,
    this.onOpenCommentaryPersonalNote,
    this.labelForIndex,
    this.notesRepository,
    this.isPersonalNotesTabActive = false,
    this.isCommentatorsTabActive = false,
    this.isLinksTabActive = false,
    this.onOpenCommentatorsPane,
    this.onOpenCommentatorsPaneWithFilter,
    this.anchorLinksByLine,
    this.anchorBookNotes = BookNotes.empty,
  });

  /// האם חלונית מפרש זה עתה טיפלה בקיצור "הוסף הערה".
  ///
  /// בצורת הדף הפוקוס נשאר על הטקסט הראשי גם כשהבחירה במפרש, ולכן אירוע
  /// הקיצור מתבעבע אל ה-`KeyboardListener` של הספר הראשי גם אחרי שהמפרש טיפל
  /// בו. הספר הראשי בודק דגל זה כדי לא לפתוח הערה כפולה על גוף הספר.
  static bool get commentaryNoteHandledRecently =>
      _SimpleTextViewerState._commentaryNoteHandled;

  /// כמו [commentaryNoteHandledRecently], עבור קיצור "דווח על טעות בספר".
  static bool get commentaryReportHandledRecently =>
      _SimpleTextViewerState._commentaryReportHandled;

  @override
  State<SimpleTextViewer> createState() => _SimpleTextViewerState();
}

/// המפרש הפעיל של חלון אחד — קיצור בחלון אחד לא ינותב למפרש של חלון אחר.
class _ActiveCommentarySlot {
  _SimpleTextViewerState? viewer;
}

final _activeCommentarySlots = Expando<_ActiveCommentarySlot>();

extension on AppWindowKeys {
  _ActiveCommentarySlot get _activeCommentary =>
      _activeCommentarySlots[this] ??= _ActiveCommentarySlot();
}

class _SimpleTextViewerState extends State<SimpleTextViewer> {
  // דגל סטטי: מונע מהטקסט הראשי לדרוס העתקה שכבר בוצעה ע"י מפרש
  static bool _commentaryCopyHandled = false;
  // דגל סטטי: מונע מהטקסט הראשי לפתוח הערה כפולה אחרי שמפרש טיפל בקיצור
  static bool _commentaryNoteHandled = false;
  // דגל סטטי: מונע מהטקסט הראשי לפתוח דיווח כפול אחרי שמפרש טיפל בקיצור
  static bool _commentaryReportHandled = false;
  // רק הפרשן האחרון שנבחר בו טקסט מטפל ב-Ctrl+C — אחד בכל חלון.
  late final _ActiveCommentarySlot _activeCommentarySlot;
  _SimpleTextViewerState? get _lastActiveCommentary =>
      _activeCommentarySlot.viewer;
  set _lastActiveCommentary(_SimpleTextViewerState? viewer) =>
      _activeCommentarySlot.viewer = viewer;

  /// של החלון הזה, לא של החלון הפעיל; נלכד ב-initState כדי ש-dispose לא יחפש.
  late final FocusRepository _focus;

  late ItemScrollController _scrollController;
  late ItemPositionsListener _positionsListener;
  ScrollOffsetController? _offsetController;
  LineScrollController? _ownedLines;
  ReadingViewportBinding? _viewportBinding;
  ReadingAnchor? _initialAnchor;

  /// קיים לטקסט ראשי בלבד.
  LineScrollController? get _lines =>
      widget.isMainText ? (widget.lines ?? _ownedLines) : null;
  FocusNode? _keyboardFocusNode;
  bool _shouldPreserveKeyboardFocus = false;

  bool _pendingKeyboardFocusRestore = false;
  bool _wasMenuFocused = false;
  String? _savedSelectedText;
  // הבחירה בלי ציוני המפרשים שהוזרקו לתצוגה, כפי שהיא בשורת המקור.
  SourceSelection? _sourceSelection;
  String? _contextMenuSelectedText;

  /// זמן הלחיצה הימנית האחרונה — לזיהוי אירוע בחירה ריקה רגעי שהיא פולטת.
  DateTime? _secondaryTapDownAt;

  bool get _isWithinSecondaryTapWindow =>
      _secondaryTapDownAt != null &&
      DateTime.now().difference(_secondaryTapDownAt!) <
          const Duration(milliseconds: 500);
  int? _savedSelectedIndex;
  // טווח אינדקסי השורות שבתוך הבחירה הנוכחית (כולל הקצוות). משמש כדי שלחיצה
  // ימנית ברווח שבין שורות נבחרות תזוהה כלחיצה "על הבחירה" ולא תבטל אותה —
  // הרווח הוויזואלי שייך הית-טסטית לווידג'ט של שורה נבחרת.
  int? _selectionLineStart;
  int? _selectionLineEnd;
  // עמודת ההתחלה של הבחירה בשורה הראשונה (רמז לזיהוי מופע נכון בטקסט חוזר).
  int? _selectionStartColumn;
  int? _selectionPointerColumn;
  int? _selectionPointerLineIndex;
  final DictionaryLookupRepository _dictionaryLookupRepository =
      DictionaryLookupRepository.instance;
  final ParagraphCommentatorsCache _paragraphCommentatorsCache =
      ParagraphCommentatorsCache();
  List<Link>? _anchorStyleSourceLinks;
  Map<String, int> _anchorStyleCache = const {};
  late final AppWindowKeys _previewWindow;
  Timer? _previewHoverTimer;
  List<PersonalNote> _commentaryNotes = const [];
  int _commentaryNotesLoadGeneration = 0;
  StreamSubscription<String>? _notesChangesSubscription;

  /// מזהה הריחוף הממתין. טעינה אסינכרונית שהתחילה בודקת אותו לאחר ה-await —
  /// ביטול ה-Timer לבדו אינו עוצר טעינה שכבר יצאה לדרך.
  int _previewHoverGeneration = 0;

  /// ביטול ריחוף ממתין: גם ה-Timer וגם טעינה אסינכרונית שכבר התחילה.
  void _cancelPendingPreview() {
    _previewHoverTimer?.cancel();
    _previewHoverGeneration++;
  }

  /// סמן-האות שחלונית התצוגה שלו פתוחה כעת (שורה + אינדקס בשורה) — מודגש בטקסט
  /// כדי לקשר ויזואלית בין הסמן לחלונית.
  int? _activeAnchorLine;
  int? _activeAnchorIndex;
  bool _disposed = false;

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

  // תת-התפריט "מפרשים נוספים על הדף" — רק בטקסט הראשי (ספר המפרש הנקרא).
  SiblingCommentariesController? _siblingController;
  final Object _selectionOwner = Object();
  final GlobalKey<SelectableRegionState> _selectionRegionKey = GlobalKey();
  late final FocusNode _selectionFocusNode;

  Map<String, int> _anchorStyles(TextBookLoaded state) {
    if (!identical(_anchorStyleSourceLinks, state.links)) {
      _anchorStyleSourceLinks = state.links;
      _anchorStyleCache = anchorStyleIndexByCommentator(state.links);
    }
    return _anchorStyleCache;
  }

  Map<int, List<Link>>? _ownAnchorStyleSource;
  Map<String, int> _ownAnchorStyleCache = const {};

  Map<String, int> _ownAnchorStyles() {
    final source = widget.anchorLinksByLine;
    if (source == null) return const {};
    if (!identical(_ownAnchorStyleSource, source)) {
      _ownAnchorStyleSource = source;
      _ownAnchorStyleCache = anchorStyleIndexByCommentator(
        source.values.expand((links) => links),
      );
    }
    return _ownAnchorStyleCache;
  }

  List<Link> _ownAnchorLinksAt(int lineIndex) {
    final links = widget.anchorLinksByLine?[lineIndex + 1];
    if (links == null || links.isEmpty) return const [];
    return links.where((link) => link.anchorStart != null).toList();
  }

  /// סמני עוגן של מפרש-על (שער הציון וכד') בעמודת מפרש — מקור הקישורים הוא
  /// המפה שסופקה לחלונית, לא ה-state של הספר הראשי.
  String _injectOwnAnchorMarkers(
    String rawLine,
    int lineIndex,
    TextBookLoaded state,
  ) {
    if (!state.commentaryDisplayProfile.showAnchorMarkers) return rawLine;
    final anchorLinks = _ownAnchorLinksAt(lineIndex);
    if (anchorLinks.isEmpty) return rawLine;
    return injectLinkAnchorMarkers(
      rawLine: rawLine,
      anchorLinks: anchorLinks,
      styleIndexByCommentator: _ownAnchorStyles(),
      lineIndex: lineIndex,
      activeIndex: lineIndex == _activeAnchorLine ? _activeAnchorIndex : null,
      notes: widget.anchorBookNotes.notesAt(lineIndex),
    );
  }

  String _injectPreviewMarkers(
    String rawLine,
    int lineIndex,
    TextBookLoaded state,
  ) {
    var result = inline_notes.addInlineNotePreviewLinks(
      rawLine,
      lineIndex: lineIndex,
      dbNotes: state.bookNotes,
    );
    // סמני-מספר מודפסים, למשל (9), שההערה שלהם בספר "הערות על…" המקושר כמפרש.
    if (numberedNoteLinks(
      state.linksByLine[lineIndex + 1] ?? const <Link>[],
    ).isNotEmpty) {
      result = addNumberedNoteMarkerLinks(result, lineIndex: lineIndex);
    }
    return _injectBodyAnchorMarkers(result, lineIndex, state);
  }

  /// [note] — גוף ההערה ה-[note] של השורה במקום השורה עצמה.
  String _injectBodyAnchorMarkers(
    String rawLine,
    int lineIndex,
    TextBookLoaded state, {
    int? note,
  }) {
    if (!state.bodyDisplayProfile.showAnchorMarkers) return rawLine;
    // מהדורה חלופית: העוגנים ממופים לנוסח הראשי — במיקומים שגויים כאן.
    if (state.book.versionTitle != null) return rawLine;
    final anchorLinks = (state.linksByLine[lineIndex + 1] ?? const <Link>[])
        .where((link) => link.anchorStart != null)
        .toList();
    if (anchorLinks.isEmpty) return rawLine;
    return injectLinkAnchorMarkers(
      rawLine: rawLine,
      anchorLinks: anchorLinks,
      styleIndexByCommentator: _anchorStyles(state),
      lineIndex: lineIndex,
      activeIndex: lineIndex == _activeAnchorLine ? _activeAnchorIndex : null,
      notes: state.bookNotes.notesAt(lineIndex),
      note: note,
    );
  }

  ({Link link, int line, int index})? _anchorLinkFromUrl(
    String url,
    TextBookLoaded state,
  ) {
    final parts = Uri.tryParse(url)?.queryParameters['ref']?.split('_');
    if (parts == null || parts.length != 2) return null;
    final line = int.tryParse(parts[0]);
    final index = int.tryParse(parts[1]);
    if (line == null || index == null) return null;
    final anchorLinks = widget.anchorLinksByLine != null
        ? _ownAnchorLinksAt(line)
        : (state.linksByLine[line + 1] ?? const <Link>[])
              .where((link) => link.anchorStart != null)
              .toList();
    if (index < 0 || index >= anchorLinks.length) return null;
    return (link: anchorLinks[index], line: line, index: index);
  }

  Future<void> _openAnchorTarget(Link link) {
    LinkPreviewOverlay.dismiss(window: AppWindowKeys.of(context));
    return openLinkTarget(link, (tab) => widget.openBookCallback(tab));
  }

  /// ריחוף על סמן-מספר: ההתאמה בין הסמן להערה נעשית לפי תוכן ההערה, ולכן היא
  /// אסינכרונית. אם אין הערה תואמת — לא נפתחת חלונית.
  void _handleNumberedNoteMarkerHover(
    String url,
    Offset globalPosition, {
    bool hoverMode = true,
  }) {
    LinkPreviewOverlay.cancelScheduledHide(AppWindowKeys.of(context));
    _cancelPendingPreview();
    final line = noteMarkerLineFromUrl(url);
    final bloc = context.read<TextBookBloc>();
    final state = bloc.state;
    if (line == null || state is! TextBookLoaded) return;
    final links = state.linksByLine[line + 1] ?? const <Link>[];
    final generation = _previewHoverGeneration;
    final delay = Duration(milliseconds: hoverMode ? 280 : 0);
    _previewHoverTimer = Timer(delay, () async {
      final link = await numberedNoteLinkFromUrl(url, links);
      if (!mounted || link == null) return;
      if (generation != _previewHoverGeneration ||
          !identical(context.read<TextBookBloc>(), bloc)) {
        return;
      }
      LinkPreviewOverlay.show(
        context,
        link: link,
        globalPosition: globalPosition,
        hoverMode: hoverMode,
        removeNikud: state.commentaryRemoveNikud,
        removePunctuation: state.commentaryRemovePunctuation,
        maxFontSize: widget.fontSize,
        onOpen: () => _openAnchorTarget(link),
      );
    });
  }

  bool _handlePreviewTap(String url) {
    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded) return false;
    final anchor = _anchorLinkFromUrl(url, state);
    if (anchor == null) return false;
    _cancelPendingPreview();
    _openAnchorTarget(anchor.link);
    return true;
  }

  void _handlePreviewHover(String url, Offset globalPosition) {
    if (url.startsWith('otzaria://note-marker')) {
      _handleNumberedNoteMarkerHover(url, globalPosition);
      return;
    }
    if (url.startsWith('otzaria://note') && widget.isPersonalNotesTabActive) {
      return;
    }
    LinkPreviewOverlay.cancelScheduledHide(AppWindowKeys.of(context));
    _cancelPendingPreview();
    final bloc = context.read<TextBookBloc>();
    final currentState = bloc.state;
    if (currentState is TextBookLoaded) {
      // סימון העוגן מחליף את MouseRegion ויוצר exit/enter מלאכותיים.
      // הסגירה כבר בוטלה לעיל; אין לתזמן פתיחה מחדש לאותו עוגן.
      final anchor = _anchorLinkFromUrl(url, currentState);
      if (anchor != null &&
          anchor.line == _activeAnchorLine &&
          anchor.index == _activeAnchorIndex) {
        return;
      }
      final previewLink = anchor?.link ?? inlineLinkFromPreviewUrl(url);
      if (previewLink != null) prefetchLinkPreview(previewLink);
    }
    _previewHoverTimer = Timer(const Duration(milliseconds: 280), () {
      if (mounted && identical(context.read<TextBookBloc>(), bloc)) {
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
    _cancelPendingPreview();
    _showUrlPreview(url, globalPosition, hoverMode: false);
  }

  void _showUrlPreview(
    String url,
    Offset globalPosition, {
    required bool hoverMode,
  }) {
    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded) return;

    if (url.startsWith('otzaria://book-note')) {
      final note = inline_notes.inlineNoteFromPreviewUrl(
        state.content,
        url,
        dbNotes: state.bookNotes,
        decorateBody: (line, note, body) =>
            _injectBodyAnchorMarkers(body, line, state, note: note),
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
          maxFontSize: widget.fontSize,
          onAnchorTap: _handlePreviewTap,
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
            (line, {note}) => _lines?.scrollToLine(line - 1),
          ),
        ),
      );
      return;
    }

    final anchor = _anchorLinkFromUrl(url, state);
    final link = anchor?.link ?? inlineLinkFromPreviewUrl(url);
    if (link == null) return;
    LinkPreviewOverlay.show(
      context,
      link: link,
      globalPosition: globalPosition,
      hoverMode: hoverMode,
      removeNikud: state.commentaryRemoveNikud,
      removePunctuation: state.commentaryRemovePunctuation,
      maxFontSize: widget.fontSize,
      onOpen: () => _openAnchorTarget(link),
      onDismissed: anchor == null ? null : () => _setActiveAnchor(null, null),
    );
    if (anchor != null) _setActiveAnchor(anchor.line, anchor.index);
  }

  void _handlePreviewHoverExit(String url) {
    _cancelPendingPreview();
    LinkPreviewOverlay.scheduleHide(_previewWindow);
  }

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

    // אם אזור אחר (מפרש) מחזיק כעת בחירת טקסט פעילה - אל תחטוף ממנו פוקוס.
    // אחרת ה-SelectableRegion של המפרש יאבד פוקוס מקלדת, ו-Shift+חץ ירחיב
    // את בחירת הטקסט הראשי (או יתחיל בחירה חדשה) במקום את בחירת המפרש.
    final activeOwner = widget.selectionSyncController?.activeOwner;
    if (activeOwner != null && !identical(activeOwner, _selectionOwner)) {
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
    return _keyboardFocusNode ??= FocusNode(debugLabel: 'PageShapeContentFocus')
      ..addListener(() {
        if (!(_keyboardFocusNode?.hasFocus ?? false)) {
          _ensureKeyboardFocusAfterLoss('focus-node-lost');
        }
      });
  }

  /// האם הטאב של תצוגה זו הוא הטאב הפעיל (כולל היותו צד בתצוגה משולבת).
  /// טאבים נשמרים חיים (KeepAlive); טאב רקע אסור לו לחטוף פוקוס מקלדת, אחרת
  /// בחירת טקסט בטאב הפעיל נשברת מיד (issue #472).
  bool _isTabInForeground() {
    final tab = widget.tab;
    if (tab == null || !mounted) return tab == null;
    // מסך הקריאה נשמר חי ב-PageView גם כשהמשתמש במסך אחר (כלים/תוספים/הגדרות);
    // בלי הבדיקה הזו צורת-הדף תחטוף פוקוס משדות קלט של תוספים (issue #472).
    if (context.read<NavigationBloc>().state.currentScreen != Screen.reading) {
      return false;
    }
    // רק החלונית הפעילה נחשבת בחזית: כשכל חלוניות הטאב ענו "כן", שתי תצוגות
    // צורת-דף החזירו זו לזו את הפוקוס בלי סוף.
    return identical(context.read<TabsBloc>().state.activePane, tab);
  }

  void _requestKeyboardFocus(String reason) {
    final focusNode = _resolvedKeyboardFocusNode;
    if (!widget.isMainText || !focusNode.canRequestFocus) {
      return;
    }

    if (!_isTabInForeground()) {
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

    // לחיצה בחלונית מפרש או בחלונית צפה — המקשים (חיצים, Ctrl+C) שייכים לה.
    if (isOtherSelectionFocusNode(FocusManager.instance.primaryFocus)) {
      return;
    }

    _shouldPreserveKeyboardFocus = true;
    focusNode.requestFocus();
  }

  /// גלילת חלונית מפרש במקלדת, בצעדי ברירת המחדל של `ScrollAction` ב-Flutter.
  bool _scrollCommentaryByKey(LogicalKeyboardKey key) {
    final controller = widget.scrollOffsetController;
    final viewportHeight = context.size?.height;
    if (controller == null || viewportHeight == null) return false;
    final offset = commentaryKeyScrollOffset(key, viewportHeight);
    if (offset == null) return false;
    controller.animateScroll(
      offset: offset,
      duration: const Duration(milliseconds: 100),
    );
    return true;
  }

  /// לחיצה מעבירה את מקשי הגלילה לחלונית שנלחצה. אחרי הפריים — כי
  /// ה-SelectableRegion לוקח את הפוקוס לעצמו באותה לחיצה.
  void _focusKeyboardAfterPointerDown() {
    if (widget.isMainText) {
      _requestKeyboardFocusAfterFrame('pointer-down');
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _resolvedKeyboardFocusNode.requestFocus();
    });
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

  void _configureScrollControllers() {
    if (widget.isMainText) {
      final lines = widget.lines ?? (_ownedLines ??= LineScrollController());
      _initialAnchor = lines.captureAnchor();
      if (_initialAnchor == null) {
        final tab = widget.tab;
        final state = context.read<TextBookBloc>().state;
        final initialLine = state is TextBookLoaded
            ? state.visibleIndices.firstOrNull ?? state.selectedIndex ?? 0
            : 0;
        _initialAnchor = tab is TextBookTab
            ? tab.readingAnchor
            : ReadingAnchor(
                line: initialLine,
                alignment: initialReadingAlignment(initialLine),
              );
      }
      _scrollController = lines.itemController;
      _positionsListener = lines.positionsListener;
      _offsetController = lines.offsetController;
    } else {
      _scrollController = widget.scrollController ?? ItemScrollController();
      _positionsListener =
          widget.positionsListener ?? ItemPositionsListener.create();
      _offsetController = widget.scrollOffsetController;
    }
  }

  @override
  void initState() {
    super.initState();
    _previewWindow = AppWindowKeys.of(context);
    _activeCommentarySlot = AppWindowKeys.of(context)._activeCommentary;
    _focus = FocusRepository.of(context);
    _configureScrollControllers();
    _selectionFocusNode = FocusNode(debugLabel: 'SelectionAreaFocus');
    _resolvedKeyboardFocusNode;
    final dynamicTab = widget.tab;
    if (dynamicTab is TextBookTab) {
      dynamicTab.dynamicCopyRequestNotifier.addListener(_onDynamicCopyRequest);
    }

    // מאזין גלובלי לקיצורי מפרש (העתקה / הוספת הערה) ללא צורך בפוקוס
    if (!widget.isMainText) {
      HardwareKeyboard.instance.addHandler(_handleCommentaryKeyEvent);
      _loadCommentaryNotes();
      _notesChangesSubscription = PersonalNotesChanges.stream.listen(
        _handleNotesChanged,
      );
    }

    // גלילה למיקום הנוכחי אחרי בניית הווידג'ט (רק לטקסט המרכזי)
    if (widget.isMainText) {
      _siblingController = SiblingCommentariesController(
        loadSiblings: (sourceLink) {
          final bloc = context.read<TextBookBloc>();
          final state = bloc.state;
          if (state is! TextBookLoaded) return Future.value(const <Link>[]);
          return bloc.repository.getSiblingCommentaries(
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
      FocusManager.instance.addListener(_handleGlobalFocusChange);
      // רישום למנגנון הפוקוס הפר-טאבי כדי שמעבר *חזרה* לטאב צורת-הדף ימקד את
      // אזור הקריאה דרך reading_screen (גלילה בחצים עובדת מיד).
      final tab = widget.tab;
      if (tab != null) {
        _focus.registerTabContentFocusRequester(
          tab,
          () => _requestKeyboardFocus('tab-content-focus'),
        );
      }
      _attachViewport();

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
          context.read<PersonalNotesBloc>().add(
            LoadPersonalNotes(personalNotesBookKey(state.book)),
          );
        }
      });
    }

    widget.selectionSyncController?.addListener(_handleExternalSelectionChange);
    PluginHighlightRevealService.instance.addListener(
      _handlePluginHighlightReveal,
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _handlePluginHighlightReveal(),
    );
  }

  void _handlePluginHighlightReveal() {
    final highlight = PluginHighlightRevealService.instance.highlight;
    final tab = widget.tab;
    if (!mounted ||
        highlight == null ||
        tab is! TextBookTab ||
        highlight.bookId != tab.book.title) {
      return;
    }
    final lines = _lines;
    if (lines == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        lines.scrollToLine(
          highlight.sectionIndex,
          alignment: .35,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeInOut,
        ),
      );
    });
  }

  bool _handleCommentaryKeyEvent(KeyEvent event) {
    if (!AppWindowKeys.isActiveWindow(context)) return false;
    // קיצור דינמי על אותו צירוף גובר, ו-KeyboardShortcuts מפעיל אותו.
    if (DynamicShortcutRegistry.instance.match(event) != null) return false;
    final addNoteShortcut =
        ShortcutValidator.getShortcutValue(ShortcutValidator.addNoteKey) ?? '';
    final reportErrorShortcut =
        ShortcutValidator.getShortcutValue(ShortcutValidator.reportErrorKey) ??
        '';
    final state = context.read<TextBookBloc>().state;
    final reportBook =
        widget.reportBook ?? (state is TextBookLoaded ? state.book : null);
    final isReportUnavailable =
        reportBook != null && !reportBook.isOfficialLibraryBook;
    final action = resolveCommentaryKeyAction(
      event: event,
      isActiveCommentary: _lastActiveCommentary == this,
      hasSelection:
          _savedSelectedText != null && _savedSelectedText!.trim().isNotEmpty,
      hasSelectedIndex: _savedSelectedIndex != null,
      addNoteShortcut: addNoteShortcut,
      reportErrorShortcut: reportErrorShortcut,
      isReportUnavailable: isReportUnavailable,
    );

    if (isReportUnavailable &&
        reportErrorShortcut.isNotEmpty &&
        ShortcutHelper.matchesShortcut(event, reportErrorShortcut)) {
      return true;
    }

    switch (action) {
      case CommentaryKeyAction.copy:
        _commentaryCopyHandled = true;
        _copyFormattedText().whenComplete(() {
          Future.delayed(const Duration(milliseconds: 100), () {
            _commentaryCopyHandled = false;
          });
        });
        return true;
      case CommentaryKeyAction.addNote:
        // הערה אישית ממפרש חייבת להישמר תחת ספר המפרש (דרך
        // _createNoteForCurrentLine), ולא על גוף הספר הראשי. האירוע מתבעבע אל
        // ה-KeyboardListener של הספר הראשי גם אחרי טיפול כאן, ולכן מסמנים דגל
        // שהספר הראשי בודק כדי לא לפתוח הערה כפולה.
        _commentaryNoteHandled = true;
        // איפוס קצר ובלתי תלוי באורך חיי הדיאלוג — צריך להישאר דולק רק למשך
        // התבעבוע הסינכרוני אל ה-KeyboardListener של הספר הראשי.
        Future.delayed(const Duration(milliseconds: 100), () {
          _commentaryNoteHandled = false;
        });
        _createNoteForCurrentLine(_savedSelectedIndex!);
        return true;
      case CommentaryKeyAction.reportError:
        _commentaryReportHandled = true;
        Future.delayed(const Duration(milliseconds: 100), () {
          _commentaryReportHandled = false;
        });
        _openErrorReportDialog(_savedSelectedText ?? '');
        return true;
      case CommentaryKeyAction.none:
        return false;
    }
  }

  @override
  void dispose() {
    PluginHighlightRevealService.instance.removeListener(
      _handlePluginHighlightReveal,
    );
    _disposed = true;
    final dynamicTab = widget.tab;
    if (dynamicTab is TextBookTab) {
      dynamicTab.dynamicCopyRequestNotifier.removeListener(
        _onDynamicCopyRequest,
      );
    }
    _cancelPendingPreview();
    final binding = _viewportBinding;
    if (binding != null) _lines?.detach(binding);
    _ownedLines?.dispose();
    if (widget.isMainText) LinkPreviewOverlay.dismiss(window: _previewWindow);
    widget.selectionSyncController?.removeListener(
      _handleExternalSelectionChange,
    );
    if (widget.isMainText) {
      FocusManager.instance.removeListener(_handleGlobalFocusChange);
      final tab = widget.tab;
      if (tab != null) {
        _focus.unregisterTabContentFocusRequester(tab);
      }
    }
    if (!widget.isMainText) {
      HardwareKeyboard.instance.removeHandler(_handleCommentaryKeyEvent);
      if (_lastActiveCommentary == this) _lastActiveCommentary = null;
      _notesChangesSubscription?.cancel();
    }
    _selectionFocusNode.dispose();
    _keyboardFocusNode?.dispose();
    _siblingController?.dispose();
    _paragraphCommentatorsCache.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SimpleTextViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectionSyncController != widget.selectionSyncController) {
      oldWidget.selectionSyncController?.removeListener(
        _handleExternalSelectionChange,
      );
      widget.selectionSyncController?.addListener(
        _handleExternalSelectionChange,
      );
    }
    if (!widget.isMainText &&
        (oldWidget.bookTitle != widget.bookTitle ||
            oldWidget.reportBook?.categoryId !=
                widget.reportBook?.categoryId)) {
      _loadCommentaryNotes();
    }
    // side-by-side אינו ממפתח לפי identity — מעבר ספר עלול לשמר את ה-State.
    final oldTab = oldWidget.tab;
    final newTab = widget.tab;
    if (!identical(oldTab, newTab)) {
      if (oldTab is TextBookTab) {
        oldTab.dynamicCopyRequestNotifier.removeListener(_onDynamicCopyRequest);
      }
      if (newTab is TextBookTab) {
        newTab.dynamicCopyRequestNotifier.addListener(_onDynamicCopyRequest);
      }
      if (widget.isMainText) {
        if (oldTab != null) {
          _focus.unregisterTabContentFocusRequester(oldTab);
        }
        if (newTab != null) {
          _focus.registerTabContentFocusRequester(
            newTab,
            () => _requestKeyboardFocus('tab-content-focus'),
          );
        }
      }
    }
    if (widget.isMainText && !identical(oldWidget.lines, widget.lines)) {
      final oldLines = oldWidget.lines ?? _ownedLines;
      final binding = _viewportBinding;
      if (binding != null) oldLines?.detach(binding);
      _viewportBinding = null;
      final owned = _ownedLines;
      _ownedLines = null;
      owned?.dispose();
      _selectionRegionKey.currentState?.clearSelection();
      _configureScrollControllers();
      _attachViewport();
    }
    if (widget.isMainText &&
        oldTab is TextBookTab &&
        newTab is TextBookTab &&
        !sameSourceIdentity(oldTab.book, newTab.book)) {
      // ה-State עלול להישמר במעבר ספר — מטמון ה"מפרשים הנוספים" ממופה לפי
      // שורה בלבד, ולכן חייב להתאפס כדי לא להחזיר מפרשים של הספר הקודם.
      _siblingController?.clear();
    }
  }

  Future<void> _loadCommentaryNotes() async {
    // טעינה ישנה שמסתיימת אחרי חדשה הייתה מחזירה הערה שכבר נמחקה.
    final generation = ++_commentaryNotesLoadGeneration;
    final bookTitle = widget.bookTitle;
    if (widget.isMainText || bookTitle == null || bookTitle.isEmpty) return;
    final notes = await (widget.notesRepository ?? PersonalNotesRepository())
        .loadNotes(
          _commentaryNotesKey(bookTitle),
          categoryId: widget.reportBook?.categoryId,
        );
    if (!mounted || generation != _commentaryNotesLoadGeneration) return;
    setState(() => _commentaryNotes = notes);
  }

  void _handleNotesChanged(String bookId) {
    final bookTitle = widget.bookTitle;
    if (bookTitle != null && bookId == _commentaryNotesKey(bookTitle)) {
      _loadCommentaryNotes();
    }
  }

  void _handleExternalSelectionChange() {
    final controller = widget.selectionSyncController;
    if (controller == null || !mounted) {
      return;
    }

    final shouldClear = shouldClearSelectionOnExternalChange(
      activeOwner: controller.activeOwner,
      selfOwner: _selectionOwner,
      hasOwnSelection: _savedSelectedText != null,
    );
    if (!shouldClear) {
      return;
    }

    // ניקוי ישיר ללא שינוי מפתח — הרשימה לא נהרסת ואין קפיצה
    _selectionRegionKey.currentState?.clearSelection();

    setState(() {
      _savedSelectedText = null;
      _savedSelectedIndex = null;
      _selectionLineStart = null;
      _selectionLineEnd = null;
      _selectionStartColumn = null;
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

  Widget _trackUserScroll(Widget list) => _lines?.trackUserScroll(list) ?? list;

  /// מחבר את הטקסט הראשי ל-[LineScrollController].
  void _attachViewport() {
    final lines = _lines;
    if (lines == null) return;
    final binding = ReadingViewportBinding(
      segments: () {
        final state = context.read<TextBookBloc>().state;
        return state is TextBookLoaded ? readingSegmentsOf(state) : null;
      },
      viewportExtent: _viewportExtent,
    );
    _viewportBinding = binding;
    lines.attach(binding);
  }

  /// נקרא רק בניווט, אחרי הפריסה — לא מתוך initState.
  double _viewportExtent() =>
      _disposed ? 0 : context.size?.height ?? MediaQuery.sizeOf(context).height;

  /// השורות הגלויות: בטקסט ראשי מהמיקום הנמדד, במפרש לפי פריטי הרשימה.
  List<int> _visibleSourceLines() {
    final lines = _lines;
    if (lines != null) return lines.position.value?.visibleLines ?? const [];
    return _positionsListener.itemPositions.value
        .map((position) => position.index)
        .toSet()
        .toList()
      ..sort();
  }

  /// היעד של הטור. טור מפרש אינו תנ"ך, ולכן חל עליו פרופיל המפרשים
  /// ולא הפטור שהתנ"ך מקבל מהגדרת "הצג ניקוד בתנ"ך".
  TextTarget get _textTarget =>
      widget.isMainText ? TextTarget.body : TextTarget.commentary;

  TextDisplayProfile _displayProfile(TextBookLoaded state) =>
      state.displayProfile(target: _textTarget);

  RenderSettings _selectionRenderSettings({
    required TextBookLoaded state,
    required SettingsState settingsState,
  }) {
    return RenderSettings.fromProfile(
      _displayProfile(state),
      searchText: widget.isMainText ? state.searchText : '',
      searchOptions: widget.isMainText ? state.searchOptions : const {},
      alternativeWords: widget.isMainText ? state.alternativeWords : const {},
      spacingValues: widget.isMainText ? state.spacingValues : const {},
      isFuzzySearch: widget.isMainText && state.searchMode == SearchMode.fuzzy,
      searchMode: widget.isMainText ? state.searchMode : SearchMode.exact,
      searchDistance: widget.isMainText ? state.searchDistance : 0,
      matchPolicy: widget.isMainText
          ? state.matchPolicy
          : SearchMatchPolicy.standard,
      partialWordHighlight: widget.isMainText && !state.searchWholeWord,
      fontSize: widget.fontSize,
      fontFamily: widget.fontFamily ?? settingsState.fontFamily,
      fontWeight:
          (widget.isMainText
              ? settingsState.fontBold
              : settingsState.commentatorsFontBold)
          ? FontWeight.bold
          : null,
      lineHeight: settingsState.lineHeight,
    );
  }

  List<int> _selectionSourceIndices() {
    final visible = _visibleSourceLines();
    if (visible.isNotEmpty) return visible;

    return List<int>.generate(widget.content.length, (index) => index);
  }

  Future<void> _handleSelectionChange(String? plainText) async {
    // עדכון מעקב כיוון הגרירה (ל-RtlSelectionShortcuts).
    trackRtlSelection(plainText);
    // שינוי בחירה זמני בזמן priming — לא לעבד.
    if (rtlSelectionPriming) return;
    final persistedText = resolvePersistedSelectedText(
      previousSelectedText: _savedSelectedText,
      latestSelectedText: plainText,
    );

    if (!shouldPersistSelectedText(plainText)) {
      if (widget.isMainText) {
        context.read<TextBookBloc>().add(
          const UpdateSelectedTextForNote(
            text: null,
            sectionIndex: null,
            start: null,
            end: null,
          ),
        );
      }
      if (mounted) {
        setState(() {
          _savedSelectedText = null;
          _selectionLineStart = null;
          _selectionLineEnd = null;
          _selectionStartColumn = null;
        });
      }
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
    final sourceIndices = _selectionSourceIndices();
    final renderSettings = _selectionRenderSettings(
      state: textBookState,
      settingsState: settingsState,
    );
    final selectionLines = <int, SelectionLine>{};
    SelectionLine lineAt(int index) =>
        selectionLines[index] ??= renderSelectionLineWithMarkers(
          rawText: _selectionMarkerLine(index, textBookState),
          settings: renderSettings,
        );
    final window = buildSelectionWindow(
      visibleIndices: sourceIndices,
      totalLines: widget.content.length,
      selectionLength: persistedText!.length,
      renderLine: (index) => lineAt(index).text,
    );
    final renderedLines = window.lines;
    final baseIndex = window.baseIndex;
    final windowIndices = List<int>.generate(
      renderedLines.length,
      (offset) => baseIndex + offset,
    );
    final previousIndex = sessionSelectionIndex(
      savedSelectedText: _savedSelectedText,
      savedSelectedIndex: _savedSelectedIndex,
    );
    final restored = restoreSelectedTextLineBreaksDetailed(
      selectedText: persistedText,
      visibleLines: renderedLines,
      preferredLine: previousIndex == null ? null : previousIndex - baseIndex,
      paragraphs: widget.isMainText
          ? readerSelectionParagraphs(
              layout: readingLayoutOf(textBookState),
              lines: widget.content,
              baseIndex: baseIndex,
            )
          : null,
    );
    final restoredText = restored.text;

    final location = resolveSelectionLocation(
      restored: restored,
      baseIndex: baseIndex,
      fallbackIndex: previousIndex,
    );
    final pointerLocation = locateSingleLineSelectionAtPointer(
      renderedLines: renderedLines,
      sourceIndices: windowIndices,
      selectedText: restoredText,
      pointerLineIndex: _selectionPointerLineIndex,
      pointerColumn: _selectionPointerColumn,
    );
    final selectedIndex = pointerLocation?.lineIndex ?? location.selectedIndex;
    final lineStart = pointerLocation?.lineIndex ?? location.lineStart;
    final lineEnd = pointerLocation?.lineIndex ?? location.lineEnd;
    final startColumn = pointerLocation?.column ?? location.startColumn;
    final sourceSelection = lineStart == null || startColumn == null
        ? null
        : SourceSelection.strip(
            shownText: restoredText,
            lines: [
              for (var i = lineStart; i <= (lineEnd ?? lineStart); i++)
                lineAt(i),
            ],
            startColumn: startColumn,
          );

    if (!mounted) return;
    setState(() {
      _savedSelectedText = restoredText;
      _sourceSelection = sourceSelection;
      _savedSelectedIndex = selectedIndex;
      _selectionLineStart = lineStart;
      _selectionLineEnd = lineEnd;
      _selectionStartColumn = startColumn;
    });
    final source = SourceSelection.resolve(
      sourceSelection,
      restoredText,
      startColumn,
    );
    final sourceText = source.text;
    if (widget.isMainText) {
      // בבחירה רב-שורתית אין טווח חד-פסקתי תקף — start/end של השורה
      // הראשונה בלבד גרמו ל-reader.getSelection להחזיר עוגן חלקי מטעה.
      final isSingleSectionSelection = !sourceText.contains('\n');
      context.read<TextBookBloc>().add(
        UpdateSelectedTextForNote(
          text: sourceText,
          sectionIndex: selectedIndex,
          start: isSingleSectionSelection ? source.column : null,
          end: isSingleSectionSelection && source.column != null
              ? source.column! + sourceText.length
              : null,
        ),
      );
      unawaited(
        PluginRuntimeDispatcher.instance.dispatchEvent(
          'reader.selection_changed',
          buildPageShapePluginSelectionPayload(
            selectedText: limitTextToCopySegments(
              textBookState.protection,
              sourceText,
            ),
            bookTitle: textBookState.book.title,
            sectionIndex:
                selectedIndex ??
                _selectionPointerLineIndex ??
                textBookState.selectedIndex ??
                0,
            currentRef: textBookState.currentTitle,
            bookDbId: textBookState.book.id,
            bookType: PluginBookIdentity.typeOf(textBookState.book),
            bookSource: PluginBookIdentity.sourceOf(textBookState.book),
          ),
        ),
      );
    }
    _prefetchDictionaryLookups(sourceText);
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

    final selectedText = _savedSelectedText;
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

  bool _handleNavigationLogicalKey(
    LogicalKeyboardKey logicalKey, {
    required bool isAltPressed,
    bool isShiftPressed = false,
    required String source,
  }) {
    if (!widget.isMainText) {
      return false;
    }

    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded) {
      return false;
    }

    final liveVisibleIndices = _visibleSourceLines();
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
      unawaited(
        _lines?.scrollToLine(
          nextIndex,
          duration: const Duration(milliseconds: 200),
          alignment: 0.5,
        ),
      );
      _requestKeyboardFocusAfterFrame('navigation-arrow-down');
      return true;
    }

    if (logicalKey == LogicalKeyboardKey.arrowUp) {
      final prevIndex = (currentIndex - 1).clamp(0, widget.content.length - 1);
      if (prevIndex == currentIndex) {
        return true;
      }
      context.read<TextBookBloc>().add(UpdateSelectedIndex(prevIndex));
      unawaited(
        _lines?.scrollToLine(
          prevIndex,
          duration: const Duration(milliseconds: 200),
          alignment: 0.5,
        ),
      );
      _requestKeyboardFocusAfterFrame('navigation-arrow-up');
      return true;
    }

    if (logicalKey == LogicalKeyboardKey.pageDown) {
      if (!_scrollPage(forward: true)) return false;
      _requestKeyboardFocusAfterFrame('navigation-page-down');
      return true;
    }

    if (logicalKey == LogicalKeyboardKey.pageUp) {
      if (!_scrollPage(forward: false)) return false;
      _requestKeyboardFocusAfterFrame('navigation-page-up');
      return true;
    }

    if (logicalKey == LogicalKeyboardKey.home && !isAltPressed) {
      context.read<TextBookBloc>().add(const UpdateSelectedIndex(0));
      unawaited(
        _lines?.scrollToLine(
          0,
          alignment: 0,
          duration: const Duration(milliseconds: 300),
        ),
      );
      _requestKeyboardFocusAfterFrame('navigation-home');
      return true;
    }

    if (logicalKey == LogicalKeyboardKey.end && !isAltPressed) {
      final lastIndex = widget.content.length - 1;
      context.read<TextBookBloc>().add(UpdateSelectedIndex(lastIndex));
      unawaited(
        _lines?.scrollToLine(
          lastIndex,
          alignment: 0,
          duration: const Duration(milliseconds: 300),
        ),
      );
      _requestKeyboardFocusAfterFrame('navigation-end');
      return true;
    }

    if (logicalKey == LogicalKeyboardKey.space) {
      final visibleSourceIndices = _visibleSourceLines();
      final pageSize = visibleSourceIndices.isNotEmpty
          ? visibleSourceIndices.length
          : 10;
      final delta = isShiftPressed ? -pageSize : pageSize;
      final targetIndex = (currentIndex + delta).clamp(
        0,
        widget.content.length - 1,
      );
      if (targetIndex == currentIndex) return true;
      context.read<TextBookBloc>().add(UpdateSelectedIndex(targetIndex));
      unawaited(
        _lines?.scrollToLine(
          targetIndex,
          duration: const Duration(milliseconds: 300),
          alignment: 0.0,
        ),
      );
      _requestKeyboardFocusAfterFrame('navigation-space');
      return true;
    }

    return false;
  }

  bool _scrollPage({required bool forward}) {
    final scroll = _scrollController.scrollController;
    if (scroll == null ||
        !scroll.hasClients ||
        !scroll.position.hasContentDimensions) {
      return false;
    }
    final position = scroll.position;
    final delta = position.viewportDimension * 0.8 * (forward ? 1 : -1);
    _lines?.beginUserNavigation();
    unawaited(
      position.animateTo(
        (position.pixels + delta).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      ),
    );
    return true;
  }

  /// תפריט הקשר
  List<AppContextMenuEntry> _buildContextMenu(
    TextBookLoaded state,
    int index,
    BuildContext menuContext,
    Offset tapPosition,
    String? capturedText, {
    TextRange? lineRange,
  }) {
    // גם לקישורים: linksByLine מכסה רק את חלון הטעינה סביב האזור הנראה.
    if (widget.isMainText) _prefetchParagraphCommentators(state, index);
    List<AppContextMenuEntry> commentatorItems = [];
    if (!widget.isMainText && widget.bookTitle != null) {
      commentatorItems = _buildCommentatorSwitchMenu(state);
    }

    List<Link> currentLineLinks() => paragraphReferenceLinks(
      linksByLine: state.linksByLine,
      paragraphIndex: index,
      queriedLinks: _paragraphCommentatorsCache.referenceLinks(
        state.book,
        index,
      ),
    );
    List<AppContextMenuEntry> buildLinksItems() =>
        buildParagraphLinksMenuChildren(
          links: currentLineLinks(),
          isLoading: _paragraphCommentatorsCache.isLoading(state.book, index),
          removeNikud: state.commentaryRemoveNikud,
          removePunctuation: state.commentaryRemovePunctuation,
          maxFontSize: widget.fontSize,
          openPaneEntry:
              widget.onOpenSidebarTab != null &&
                  shouldShowOpenLinksPaneEntry(
                    hasLinks: true,
                    isLinksTabActive: widget.isLinksTabActive,
                  )
              ? buildOpenLinksPaneEntry(
                  onTap: () => widget.onOpenSidebarTab!(kLinksTabIndex),
                )
              : null,
          onOpenLink: (link) =>
              openLinkTarget(link, (tab) => widget.openBookCallback(tab)),
        );

    final hasLinkItems =
        currentLineLinks().isNotEmpty ||
        _paragraphCommentatorsCache.isLoading(state.book, index);

    final entries = <AppContextMenuEntry>[];
    final source = SourceSelection.resolve(
      _sourceSelection,
      capturedText,
      _selectionStartColumn,
    );
    final sourceText = source.text;

    if (widget.isMainText) {
      final menuSelection = ReaderMenuSelection(sourceText);

      // שורת אייקונים עליונה בסגנון Windows 11 — הרשימה המלאה נשארת מתחת.
      entries.add(
        buildReaderIconRow(
          context: context,
          selection: menuSelection,
          book: state.book,
          paragraphIndex: index,
          selectedText: capturedText,
          protection: state.protection,
          onCopy: () => _copyFormattedText(capturedText),
          onAddNote: () => _createNoteForCurrentLine(index, capturedText),
        ),
      );
      entries.add(_copyAsEntry(state, capturedText));
      entries.add(const AppContextMenuEntry.divider());

      entries.add(
        AppContextMenuEntry(
          label: menuSelection.hasText
              ? 'חפש "${menuSelection.quote(10)}" בספר זה'
              : 'חיפוש',
          icon: OtzariaIcons.book_search_24_regular,
          // Without a selection the search opens empty, as in the combined
          // view.
          onTap: () {
            final openSearch = widget.onOpenSearch;
            if (openSearch == null) {
              UiSnack.show(TextBookMessages.searchUnavailableInThisView);
              return;
            }
            openSearch(menuSelection.hasText ? menuSelection.cleaned : null);
          },
        ),
      );
    }

    if (commentatorItems.isNotEmpty) {
      if (entries.isNotEmpty) entries.add(const AppContextMenuEntry.divider());
      entries.addAll(commentatorItems);
    }

    if (!widget.isMainText && entries.isNotEmpty) {
      entries.add(const AppContextMenuEntry.divider());
    }
    if (widget.isMainText) {
      entries.add(
        AppContextMenuEntry(
          label: kParagraphCommentatorsMenuLabel,
          icon: OtzariaIcons.book_24_regular,
          enabled: state.availableCommentators.isNotEmpty,
          childrenBuilder: () => _buildCommentatorsMenuItems(state, index),
          childrenRefreshStream: _paragraphCommentatorsCache.changes,
        ),
      );
      entries.add(
        AppContextMenuEntry(
          label: 'קישורים',
          icon: OtzariaIcons.links_24_regular,
          enabled: hasLinkItems,
          childrenBuilder: buildLinksItems,
          childrenRefreshStream: _paragraphCommentatorsCache.changes,
        ),
      );
    } else {
      entries.addAll(_buildTargetLineEntries(state, index));
    }

    if (widget.isMainText && _siblingController != null) {
      final sourceLink = _siblingController!.sourceLinkForLine(
        state.linksByLine,
        index + 1,
      );
      final siblingEntry = _siblingController!.buildEntry(
        lineIndex: index,
        sourceLink: sourceLink,
        removeNikud: state.commentaryRemoveNikud,
        removePunctuation: state.commentaryRemovePunctuation,
        maxFontSize: widget.fontSize,
        onNavigate: (link) =>
            openLinkTarget(link, (tab) => widget.openBookCallback(tab)),
      );
      if (siblingEntry != null) entries.add(siblingEntry);
    }

    entries.addAll(
      buildReaderDictionaryEntries(
        context: context,
        selectedText: sourceText,
        tapPosition: tapPosition,
        repository: _dictionaryLookupRepository,
      ),
    );

    entries.add(const AppContextMenuEntry.divider());
    final reportTargetBook = widget.reportBook ?? state.book;
    entries.addAll([
      if (widget.isMainText)
        AppContextMenuEntry(
          label: 'הוסף סימניה לקטע זה',
          icon: FluentIcons.bookmark_add_24_regular,
          onTap: () => addTextSectionBookmark(context, state, index),
        ),
      // בטקסט ראשי "הוסף הערה" ו"העתק" קיימים כאייקונים למעלה; במפרשים
      // (ללא שורת אייקונים) הם נשארים כאן ברשימה.
      if (!widget.isMainText)
        AppContextMenuEntry(
          label: 'הוסף הערה אישית ',
          icon: FluentIcons.note_add_24_regular,
          onTap: () => _createNoteForCurrentLine(index, capturedText),
        ),
      if (reportTargetBook.isOfficialLibraryBook)
        AppContextMenuEntry(
          label: 'דווח על טעות בספר',
          icon: FluentIcons.error_circle_24_regular,
          onTap: () => _openErrorReportDialog(capturedText ?? ''),
        ),
      const AppContextMenuEntry.divider(),
      if (!widget.isMainText) ...[
        AppContextMenuEntry(
          label: 'העתק',
          icon: FluentIcons.copy_24_regular,
          enabled: capturedText != null && capturedText.trim().isNotEmpty,
          onTap: () => _copyFormattedText(capturedText),
        ),
        _copyAsEntry(state, capturedText),
      ],
      AppContextMenuEntry(
        label: 'העתק את כל הפסקה',
        icon: FluentIcons.document_copy_24_regular,
        enabled: index >= 0 && index < widget.content.length,
        onTap: () => _copyParagraphByIndex(index),
      ),
    ]);

    // העתק קישור ישיר — בטקסט ראשי מוצג כאייקון בשורה העליונה; במפרשים
    // (ללא שורת אייקונים) נשאר כתת-תפריט ברשימה לפי book_id של widget.reportBook.
    if (widget.isMainText) {
      entries.addAll(
        buildReaderPluginMenuEntries(
          tabId: readerBookTabId(widget.tab, state),
          root: context.findRenderObject(),
          state: state,
          lines: widget.content,
          paragraphIndex: index,
          hasSelection: sourceText?.trim().isNotEmpty == true,
          selectedText: sourceText,
          anchor: (
            lineStart: _selectionLineStart,
            lineEnd: _selectionLineEnd,
            startColumn: source.column,
            pointerColumn: SourceSelection.resolvePointerColumn(
              _sourceSelection,
              capturedText,
              _selectionPointerColumn,
              lineStart: _selectionLineStart,
              pointerLineIndex: _selectionPointerLineIndex,
            ),
          ),
          settings: () => _selectionRenderSettings(
            state: state,
            settingsState: menuContext.read<SettingsBloc>().state,
          ),
          tapPosition: tapPosition,
          menuContext: menuContext,
          selectionContext: 'reader-page-shape-selection',
          lineRange: lineRange,
        ),
      );
    } else {
      // רק book_id של המפרש; categoryId אינו תחליף — הוא היה פותח ספר אחר.
      final commentaryBookId = widget.reportBook?.id;
      if (commentaryBookId != null) {
        entries.add(const AppContextMenuEntry.divider());
        entries.add(
          buildCopyDirectLinkEntry(
            bookId: commentaryBookId,
            source: widget.reportBook?.source ?? BookSource.official,
            index: index,
            selectedText: capturedText,
            protection: () => _textProtection(state),
          ),
        );
      }
      entries.addAll(
        _commentaryPluginEntries(state, index, sourceText, menuContext),
      );
    }

    return _normalizeEntries(entries);
  }

  /// פריטי התוספים בהקשרי המפרש, לשורה [index] בעמודת המפרש.
  List<AppContextMenuEntry> _commentaryPluginEntries(
    TextBookLoaded state,
    int index,
    String? selectedText,
    BuildContext menuContext,
  ) {
    final title = widget.bookTitle;
    final book =
        widget.reportBook ?? (title == null ? null : TextBook(title: title));
    if (!hasPluginContextMenuItems ||
        book == null ||
        index < 0 ||
        index >= widget.content.length) {
      return const [];
    }
    final ref = widget.labelForIndex?.call(index);
    // נקבע עכשיו: עד הלחיצה הבחירה כבר עשויה להתאפס.
    final segmentCount = selectionSegmentCount(
      start: _selectionLineStart,
      end: _selectionLineEnd,
      text: selectedText ?? '',
    );
    return buildCommentaryPluginMenuEntries(
      target: (
        book: book,
        sectionIndex: index,
        currentRef: ref == null || ref.isEmpty ? null : ref,
      ),
      // עמודת המפרש נגללת לצד הספר כולו, ושורה בה אינה ממופה לשורה ראשית אחת.
      mainBook: (
        book: state.book,
        currentRef: state.currentTitle,
        sectionIndex: null,
        pageNumber: null,
      ),
      selectedText: selectedText,
      copyGuard: () async => (
        protection: await _textProtection(state),
        segmentCount: segmentCount,
      ),
      menuContext: menuContext,
    );
  }

  /// השורה כפי שהיא מוצגת לבחירה: עם ציוני המפרשים של הטור.
  String _selectionMarkerLine(int index, TextBookLoaded state) {
    final rawLine = widget.content[index];
    if (widget.isMainText) {
      return _injectBodyAnchorMarkers(rawLine, index, state);
    }
    return widget.anchorLinksByLine == null
        ? rawLine
        : _injectOwnAnchorMarkers(rawLine, index, state);
  }

  /// תתי-התפריטים "מפרשים" ו"קישורים" של שורת המפרש שנלחצה — כמו בלחיצה ימנית
  /// על מפרש בחלונית הצד. נגזרים מספר המפרש עצמו, לא מקישורי הספר הראשי:
  /// [index] הוא שורה בתוך ספר המפרש, ו-`state.linksByLine` שייך לספר הראשי.
  List<AppContextMenuEntry> _buildTargetLineEntries(
    TextBookLoaded state,
    int index,
  ) {
    final book = widget.reportBook;
    if (book == null) return const [];
    // בלי categoryId השאילתה על ספר המפרש נכשלת, ותת-התפריט היה נתקע על
    // "שגיאה בטעינה" במקום פשוט לא להופיע.
    if (book.categoryId == null && !book.isUserBook) return const [];

    final targetLink = Link(
      heRef: book.title,
      index1: 0,
      path2: book.title,
      index2: index + 1,
      connectionType: 'commentary',
      targetCategoryId: book.categoryId,
      targetFileType: book.fileType,
      targetSource: book.source,
    );

    Future<void> navigate(Link link) =>
        openLinkTarget(link, (tab) => widget.openBookCallback(tab));

    final service = TargetLineLinksService.instance;
    // טעינה כבר בפתיחת התפריט, כדי שתת-התפריט לא ייפתח על "טוען…".
    service.prefetch(targetLink);
    return [
      service.buildCommentariesEntry(
        link: targetLink,
        onNavigate: navigate,
        removeNikud: state.commentaryRemoveNikud,
        removePunctuation: state.commentaryRemovePunctuation,
        maxFontSize: widget.fontSize,
      ),
      service.buildLinksEntry(
        link: targetLink,
        onNavigate: navigate,
        removeNikud: state.commentaryRemoveNikud,
        removePunctuation: state.commentaryRemovePunctuation,
        maxFontSize: widget.fontSize,
      ),
    ];
  }

  /// פריטי תת-התפריט "מפרשים על פסקה זו" — זהים לתצוגה הרגילה, ומשנים את
  /// בחירת המפרשים שבלשונית המפרשים בחלונית הצד (לא את טורי צורת הדף).
  List<AppContextMenuEntry> _buildCommentatorsMenuItems(
    TextBookLoaded state,
    int index,
  ) {
    final isLoading = _paragraphCommentatorsCache.isLoading(state.book, index);
    final showOpenPane = shouldShowOpenCommentatorsPaneEntry(
      hasSelectedCommentators: state.activeCommentators.isNotEmpty,
      showCommentaryAsExpansionTiles: false,
      isCommentatorsTabActive: widget.isCommentatorsTabActive,
    );
    final showSelect = shouldShowSelectCommentatorsEntry(
      hasOpenCommentatorsPaneWithFilterCallback:
          widget.onOpenCommentatorsPaneWithFilter != null,
      isCommentatorsTabActive: widget.isCommentatorsTabActive,
    );

    // חלונית המפרשים נגזרת מ-selectedIndex; בלי הסנכרון הזה לחיצה ימנית על
    // שורה רחוקה הייתה מציגה את המפרשים של השורה שנבחרה קודם בלחיצה שמאלית.
    void selectClickedLine() {
      if (!mounted || state.selectedIndex == index) return;
      context.read<TextBookBloc>().add(UpdateSelectedIndex(index));
    }

    return buildCommentatorsContextMenuChildren(
      getActiveCommentators: () => state.activeCommentators,
      availableCommentators: paragraphCommentators(
        availableCommentators: state.availableCommentators,
        content: widget.content,
        bookNotes: widget.isMainText ? state.bookNotes : null,
        paragraphIndex: index,
        linksByLine: state.linksByLine,
        queriedCommentators: isLoading
            ? const <String>[]
            : _paragraphCommentatorsCache.value(state.book, index),
      ),
      commentatorGroups: state.commentatorGroups,
      linksLoading: state.linksLoading || isLoading,
      onOpenPane: showOpenPane && widget.onOpenCommentatorsPane != null
          ? () {
              selectClickedLine();
              widget.onOpenCommentatorsPane!();
            }
          : null,
      onSelectMultiple: showSelect
          ? () {
              selectClickedLine();
              widget.onOpenCommentatorsPaneWithFilter!();
            }
          : null,
      onCommentatorsChanged: (commentators, {required isAdding}) {
        selectClickedLine();
        context.read<TextBookBloc>().add(UpdateCommentators(commentators));
        if (isAdding) widget.onOpenCommentatorsPane?.call();
      },
    );
  }

  void _prefetchParagraphCommentators(TextBookLoaded state, int index) {
    unawaited(
      _paragraphCommentatorsCache
          .prefetch(
            repository: context.read<TextBookBloc>().repository,
            book: state.book,
            paragraphIndex: index,
          )
          .onError((error, stackTrace) {
            debugPrint('שגיאה בטעינת מפרשי הפסקה: $error\n$stackTrace');
          }),
    );
  }

  List<AppContextMenuEntry> _normalizeEntries(
    List<AppContextMenuEntry> entries,
  ) {
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
  Future<void> _createNoteForCurrentLine(
    int index, [
    String? capturedText,
  ]) async {
    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded) return;

    final source = SourceSelection.resolve(
      _sourceSelection,
      capturedText ?? _savedSelectedText,
      _selectionStartColumn,
    );
    final selectedText = source.text;
    final settingsState = context.read<SettingsBloc>().state;
    final mappedSelection = selectedText?.trim().isNotEmpty == true
        ? mapPersonalNoteSourceSelection(
            bookId: widget.bookTitle ?? state.book.title,
            lineIndex: index,
            rawLine: widget.content[index],
            settings: _selectionRenderSettings(
              state: state,
              settingsState: settingsState,
            ),
            selectedText: selectedText!.trim(),
            startHint: source.column,
          )
        : null;
    final referenceText = selectedText?.trim().isNotEmpty == true
        ? utils.removeVolwels(selectedText!.trim())
        : widget.content[index];

    // הערה שנוצרת מתוך מפרש (לא הטקסט הראשי) חייבת להישמר תחת ספר המפרש
    // עצמו, עם מספר השורה המקומי בתוך תוכן המפרש. הסיידבר של צורת הדף קשור
    // תמיד לספר הראשי, לכן אי אפשר להשתמש בו — פותחים דיאלוג עצמאי ושומרים
    // ישירות דרך ה-repository, בלי לשבש את ה-PersonalNotesBloc של הספר הראשי.
    if (!widget.isMainText && widget.bookTitle != null) {
      await _createCommentaryNote(
        bookTitle: widget.bookTitle!,
        lineNumber: index + 1,
        referenceText: referenceText,
        selectedText: selectedText?.trim(),
        selectionColumn: source.column,
        sourceSelectedText: mappedSelection?.text,
        sourceSelectionOffset: mappedSelection?.offset,
        punctuationHidden: state.commentaryRemovePunctuation,
      );
      return;
    }

    // טען טיוטה אם קיימת
    final draftService = PersonalNoteDraftService();
    final draft = await draftService.loadDraft(
      bookId: personalNotesBookKey(state.book),
      categoryId: state.book.categoryId,
      lineNumber: index + 1,
    );

    if (!mounted) return;

    // שלח event לפתיחת מצב יצירה בסיידבר
    context.read<PersonalNotesBloc>().add(
      StartCreatingPersonalNote(
        bookId: personalNotesBookKey(state.book),
        lineNumber: index + 1,
        referenceText: referenceText,
        selectedText: selectedText?.trim(),
        selectionColumn: source.column,
        sourceSelectedText: mappedSelection?.text,
        sourceSelectionOffset: mappedSelection?.offset,
        punctuationHidden: state.removePunctuation,
        initialContent: draft?.content ?? '',
        initialFormat: draft?.contentFormat ?? PersonalNoteContentFormat.plain,
      ),
    );
  }

  /// טיפול בלחיצה על סימון הערה אישית inline: מדגיש את השורה ופותח את החלונית.
  void _onInlineNoteTap(int lineIndex) {
    context.read<TextBookBloc>().add(UpdateSelectedIndex(lineIndex));
    context.read<TextBookBloc>().add(HighlightLine(lineIndex));
    // פותחים את ההערה עצמה בחלונית, גם אם מוגדר "סגור כברירת מחדל".
    context.read<PersonalNotesBloc>().add(
      RequestExpandNotesForLine(lineIndex + 1),
    );
    if (widget.onOpenSidebarTab != null) {
      widget.onOpenSidebarTab!(kNotesTabIndex);
    } else {
      context.read<TextBookBloc>().add(const ToggleLeftPane(true));
    }
  }

  /// מפתח ההערות של ספר המפרש — לפי מקורו כשהספר המלא ידוע.
  String _commentaryNotesKey(String bookTitle) {
    final book = widget.reportBook;
    return book != null && book.title == bookTitle
        ? personalNotesBookKey(book)
        : bookTitle;
  }

  /// יצירת הערה על מפרש (בצורת הדף) — נשמרת תחת ספר המפרש עצמו.
  ///
  /// [bookTitle] - שם ספר המפרש (למשל "רש"י")
  /// [lineNumber] - מספר השורה המקומי בתוך תוכן המפרש (1-based)
  /// [referenceText] - טקסט הייחוס המוצג בכותרת ההערה
  /// [selectedText] - הטקסט שסומן, אם קיים
  Future<void> _createCommentaryNote({
    required String bookTitle,
    required int lineNumber,
    required String referenceText,
    String? selectedText,
    int? selectionColumn,
    String? sourceSelectedText,
    int? sourceSelectionOffset,
    bool punctuationHidden = false,
  }) async {
    final notesKey = _commentaryNotesKey(bookTitle);
    final categoryId = widget.reportBook?.categoryId;

    // טען טיוטה קיימת (אם יש) כדי לתמוך בשחזור טקסט לא שמור — כמו במסלול הרגיל.
    final draftService = PersonalNoteDraftService();
    final draft = await draftService.loadDraft(
      bookId: notesKey,
      categoryId: categoryId,
      lineNumber: lineNumber,
    );

    if (!mounted) return;

    final result = await showDialog<PersonalNoteEditorResult>(
      context: context,
      builder: (dialogContext) => PersonalNoteEditorDialog(
        title: 'הערה חדשה - $bookTitle',
        referenceText: referenceText,
        icon: FluentIcons.note_add_24_regular,
        bookId: notesKey,
        categoryId: categoryId,
        // draftLineNumber מאפשר לדיאלוג לשמור/לנקות טיוטה בעת סגירה.
        draftLineNumber: lineNumber,
        initialContent: draft?.content ?? '',
        initialContentFormat:
            draft?.contentFormat ?? PersonalNoteContentFormat.plain,
      ),
    );

    if (result == null || result.contentPlain.trim().isEmpty) return;

    try {
      await saveCommentaryNoteToRepository(
        repository: widget.notesRepository ?? PersonalNotesRepository(),
        bookId: notesKey,
        lineNumber: lineNumber,
        result: result,
        selectedText: selectedText,
        selectionColumn: selectionColumn,
        sourceSelectedText: sourceSelectedText,
        sourceSelectionOffset: sourceSelectionOffset,
        punctuationHidden: punctuationHidden,
        categoryId: categoryId,
      );
      if (mounted) UiSnack.showSuccess(TextBookMessages.noteSaved);
    } catch (e) {
      if (mounted) UiSnack.showError(TextBookMessages.noteSaveError(e));
    }
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
      selectedText: SourceSelection.resolve(
        _sourceSelection,
        selectedText,
        null,
      ).text,
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
  Future<void> _copyParagraphByIndex(
    int index, {
    TextDisplayProfile? profile,
    bool plainTextOnly = false,
  }) async {
    if (index < 0 || index >= widget.content.length) return;

    final text = widget.content[index];
    if (text.trim().isEmpty) return;

    final settingsState = context.read<SettingsBloc>().state;
    final textBookState = context.read<TextBookBloc>().state;
    final loaded = textBookState is TextBookLoaded ? textBookState : null;

    // ההעתקה משקפת את התצוגה — פרופיל ערוץ ההעתקה של הטור (או פרופיל
    // מפורש מ"העתק כ..." / קיצור דינמי).
    await copyParagraphToClipboard(
      processedText: loaded != null
          ? applyTextDisplayProfile(
              text,
              profile ??
                  loaded.displayProfile(
                    target: _textTarget,
                    channel: TextChannel.copy,
                  ),
            )
          : text,
      index: index,
      copyWithHeaders: settingsState.copyWithHeaders,
      copyHeaderFormat: settingsState.copyHeaderFormat,
      headerBook: loaded == null ? null : (widget.reportBook ?? loaded.book),
      bookContent: widget.reportBook != null ? widget.content : loaded?.content,
      isLineLoaded: widget.reportBook == null
          ? loaded?.isContentLineLoaded
          : null,
      fontFamily: widget.fontFamily ?? settingsState.fontFamily,
      fontSize: widget.fontSize,
      plainTextOnly: plainTextOnly,
    );
  }

  /// העתקת טקסט מעוצב
  /// "העתק כ..." — וריאציות ההעתקה מפרופיל ערוץ ההעתקה של הטור.
  AppContextMenuEntry _copyAsEntry(
    TextBookLoaded state,
    String? selectedText,
  ) => buildCopyAsMenuEntry(
    base: state.displayProfile(target: _textTarget, channel: TextChannel.copy),
    selectedText: selectedText,
    onCopy: (profile) => _copyFormattedText(selectedText, false, profile),
  );

  /// בקשת העתקה מקיצור דינמי — הגוף מנתב למפרש הפעיל באותו מסך.
  void _onDynamicCopyRequest() {
    final tab = widget.tab;
    if (tab is! TextBookTab || !mounted) return;
    final request = tab.dynamicCopyRequestNotifier.value;
    if (request == null) return;
    final viewer = request.target == _textTarget ? this : _lastActiveCommentary;
    if (viewer == null ||
        !viewer.mounted ||
        request.target != viewer._textTarget) {
      return;
    }
    if (viewer != this &&
        (widget.selectionSyncController == null ||
            !identical(
              widget.selectionSyncController,
              viewer.widget.selectionSyncController,
            ))) {
      return;
    }
    tab.dynamicCopyRequestNotifier.value = null;
    switch (request.kind) {
      case DynamicShortcutKind.copySelectionWith:
        viewer._copyFormattedText(
          null,
          false,
          request.profile,
          request.plainTextOnly,
        );
      case DynamicShortcutKind.copyParagraphWith:
        final index = viewer._savedSelectedIndex;
        if (index != null) {
          viewer._copyParagraphByIndex(
            index,
            profile: request.profile,
            plainTextOnly: request.plainTextOnly,
          );
        }
      case DynamicShortcutKind.setTextDisplay:
        break;
    }
  }

  /// הגבלת המו"ל של הטקסט שבעמודה: הספר הראשי, או המפרש שבעמודת מפרש.
  Future<BookProtection> _textProtection(TextBookLoaded state) {
    if (widget.isMainText) return Future.value(state.protection);
    final reportBook = widget.reportBook;
    return reportBook != null
        ? BookProtectionRepository.instance.forBook(reportBook)
        : BookProtectionRepository.instance.forTitle(widget.bookTitle ?? '');
  }

  Future<void> _copyFormattedText([
    String? capturedText,
    bool removeNikud = false,
    TextDisplayProfile? profile,
    bool plainTextOnly = false,
  ]) async {
    // מפרש כבר טיפל בהעתקה - לא נדרוס
    if (widget.isMainText && _commentaryCopyHandled) return;

    final plainText = capturedText ?? _savedSelectedText;

    if (plainText == null || plainText.trim().isEmpty) {
      UiSnack.show(TextBookMessages.selectTextToCopy);
      return;
    }

    try {
      final textBookState = context.read<TextBookBloc>().state;
      if (textBookState is! TextBookLoaded) return;
      final protection = await _textProtection(textBookState);
      if (!mounted) return;
      final settingsState = context.read<SettingsBloc>().state;

      await copySelectedTextForBook(
        plainText: plainText,
        selectedIndex: _savedSelectedIndex,
        sourceContent: widget.content,
        textBookState: textBookState,
        protection: protection,
        segmentCount: selectionSegmentCount(
          start: _selectionLineStart,
          end: _selectionLineEnd,
          text: plainText,
        ),
        settingsState: settingsState,
        fontFamily: widget.fontFamily ?? settingsState.fontFamily,
        fontSize: widget.fontSize,
        headerBookOverride: widget.reportBook,
        headerContentOverride: widget.reportBook != null
            ? widget.content
            : null,
        removeNikud: removeNikud,
        copyProfile: profile,
        copyTarget: _textTarget,
        source: _sourceSelection,
        plainTextOnly: plainTextOnly,
      );
    } catch (e) {
      if (mounted) {
        UiSnack.showError(TextBookMessages.formattedCopyError(e));
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
            // טור מפרש אינו מסמן את השורה הנבחרת; קשורותיה מגיעות ב-highlightedIndices.
            buildWhen: widget.isMainText
                ? shouldRebuildReader
                : shouldRebuildIgnoringSelection,
            builder: (context, state) {
              if (state is! TextBookLoaded) {
                return const Center(child: CircularProgressIndicator());
              }

              return BlocBuilder<PersonalNotesBloc, PersonalNotesState>(
                // שאר שדות ה-bloc (חיפוש, טיוטה) משתנים בכל הקשה; הבנייה
                // קוראת רק את אלה, וטור מפרש אף לא אותם.
                buildWhen: (previous, current) =>
                    widget.isMainText &&
                    (previous.bookId != current.bookId ||
                        previous.locatedNotes != current.locatedNotes),
                builder: (context, notesState) {
                  final noteMap = <int, List<PersonalNote>>{};
                  final visibleNotes = widget.isMainText
                      ? (notesState.bookId == personalNotesBookKey(state.book)
                            ? notesState.locatedNotes
                            : const <PersonalNote>[])
                      : _commentaryNotes;
                  for (final note in visibleNotes) {
                    if (note.hasLocation) {
                      final line = note.lineNumber;
                      if (line == null) continue;
                      noteMap.putIfAbsent(line, () => []).add(note);
                    }
                  }
                  final continuous =
                      widget.isMainText && state.continuousReadingMode;
                  final segments = widget.isMainText
                      ? readingSegmentsOf(state)
                      : null;
                  final itemCount = segments?.length ?? widget.content.length;
                  return RtlSelectionShortcuts(
                    child: SelectableRegion(
                      key: _selectionRegionKey,
                      focusNode: _selectionFocusNode,
                      selectionControls: switch (defaultTargetPlatform) {
                        TargetPlatform.android || TargetPlatform.fuchsia =>
                          materialTextSelectionHandleControls,
                        TargetPlatform.iOS =>
                          cupertinoTextSelectionHandleControls,
                        _ => emptyTextSelectionControls,
                      },
                      // ביטול תפריט ברירת המחדל של Flutter - נשתמש רק ב-ContextMenuRegion
                      contextMenuBuilder: (context, selectableRegionState) =>
                          const SizedBox.shrink(),
                      onSelectionChanged: (selection) {
                        // לחיצה ימנית משמרת-בחירה פולטת אירוע בחירה ריקה רגעי;
                        // עיבודו היה מוחק את הטקסט השמור ושובר את Ctrl+C (issue #937).
                        if (selection != null &&
                            selection.plainText.trim().isEmpty &&
                            _isWithinSecondaryTapWindow) {
                          return;
                        }
                        if (selection != null &&
                            selection.plainText.trim().isNotEmpty) {
                          widget.selectionSyncController?.activate(
                            _selectionOwner,
                          );
                        } else {
                          widget.selectionSyncController?.clear(
                            _selectionOwner,
                          );
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
                          CopySelectionTextIntent: FormattedCopyAction(
                            _copyFormattedText,
                          ),
                        },
                        child: Shortcuts(
                          shortcuts: {
                            LogicalKeySet(
                              LogicalKeyboardKey.control,
                              LogicalKeyboardKey.keyC,
                            ): const _CopyTextIntent(),
                            LogicalKeySet(
                              LogicalKeyboardKey.meta,
                              LogicalKeyboardKey.keyC,
                            ): const _CopyTextIntent(),
                          },
                          child: Focus(
                            focusNode: _resolvedKeyboardFocusNode,
                            autofocus:
                                widget.isMainText && _isTabInForeground(),
                            onFocusChange: (hasFocus) {
                              if (!hasFocus) {
                                _ensureKeyboardFocusAfterLoss(
                                  'focus-widget-lost',
                                );
                              }
                            },
                            onKeyEvent: (_, event) {
                              if (!shouldHandlePageShapeNavigationKeyEvent(
                                event,
                                isShiftPressed:
                                    HardwareKeyboard.instance.isShiftPressed,
                              )) {
                                return KeyEventResult.ignored;
                              }

                              final handled = widget.isMainText
                                  ? _handleNavigationLogicalKey(
                                      event.logicalKey,
                                      isAltPressed:
                                          ShortcutHelper.isAltModifierPressed,
                                      isShiftPressed: HardwareKeyboard
                                          .instance
                                          .isShiftPressed,
                                      source: 'content-focus',
                                    )
                                  : _scrollCommentaryByKey(event.logicalKey);
                              return handled
                                  ? KeyEventResult.handled
                                  : KeyEventResult.ignored;
                            },
                            child: widget.useInternalScroll
                                ? ScrollablePositionedListScrollbar(
                                    scrollController: _scrollController,
                                    onNavigationStart:
                                        _lines?.beginUserNavigation,
                                    itemCount: itemCount,
                                    labelForIndex: widget.labelForIndex,
                                    child: SmoothWheelScroll(
                                      child: _trackUserScroll(
                                        _buildInternalList(
                                          state,
                                          noteMap,
                                          segments,
                                          continuous,
                                        ),
                                      ),
                                    ),
                                  )
                                : ListView.builder(
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    itemCount: itemCount,
                                    padding: const EdgeInsets.all(4),
                                    itemBuilder: (context, index) =>
                                        _buildLineItem(
                                          context,
                                          index,
                                          state,
                                          noteMap,
                                          segments,
                                          continuous,
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
          ),
        ),
      ],
    );
  }

  Widget _buildInternalList(
    TextBookLoaded state,
    Map<int, List<PersonalNote>> noteMap,
    ReadingSegments? segments,
    bool continuous,
  ) {
    final currentAnchor = _lines?.captureAnchor();
    final anchor = currentAnchor ?? _initialAnchor;
    TargetRectResolver? initialResolver;
    if (segments != null &&
        anchor != null &&
        (currentAnchor != null ||
            anchor.line != 0 ||
            anchor.intraLineFraction != 0 ||
            anchor.alignment != 0)) {
      initialResolver = readingAnchorTargetRectResolver(
        segments: () => _viewportBinding?.segments() ?? segments,
        lineIndex: anchor.line,
        intraLineFraction: anchor.intraLineFraction,
        measure: _lines?.itemBoxes.lineExtent,
        isCurrent: () => mounted && !_disposed,
      );
    }
    Widget buildList(ItemExtentEstimator? estimate, Object? estimationKey) =>
        ScrollablePositionedList.builder(
          key: ValueKey((
            _scrollController,
            context.read<TextBookBloc>(),
            continuous,
          )),
          itemScrollController: _scrollController,
          itemPositionsListener: _positionsListener,
          scrollOffsetController: _offsetController,
          itemCount: segments?.length ?? widget.content.length,
          initialScrollIndex: segments == null || anchor == null
              ? 0
              : segments.layout.itemForLine(anchor.line),
          initialAlignment: anchor?.alignment ?? 0,
          initialTargetRectResolver: initialResolver,
          cacheExtentScreens: TickerMode.valuesOf(context).enabled
              ? kReaderCacheExtentScreens
              : 0,
          estimateExtent: estimate,
          estimationKey: estimationKey,
          padding: _readerListPadding,
          itemBuilder: (context, index) {
            final item = _buildLineItem(
              context,
              index,
              state,
              noteMap,
              segments,
              continuous,
            );
            final lines = _lines;
            return lines == null || segments == null
                ? item
                : wrapReaderItem(
                    item: index,
                    layout: segments.layout,
                    boxes: lines.itemBoxes,
                    child: item,
                  );
          },
        );
    if (segments == null) return buildList(null, null);
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, settings) {
        final family = widget.fontFamily ?? settings.fontFamily;
        final weight = settings.fontBold ? FontWeight.bold : null;
        return ReadingExtentEstimation(
          segments: segments,
          controller: _scrollController,
          fontSize: widget.fontSize,
          fontFamily: AppFonts.renderFontFamily(family),
          fontWeight: weight,
          fontVariations: AppFonts.boldFontVariations(
            family,
            weight ?? FontWeight.normal,
          ),
          lineHeight: settings.lineHeight,
          textWidth: (width) => width > 8 ? width - 8 : width,
          crossAxisPadding: _readerListPadding.horizontal,
          builder: buildList,
        );
      },
    );
  }

  /// עוטף את [_buildLine]; מוסיף את באנר קרדיט מקור הספר מעל השורה הראשונה.
  Widget _buildLineItem(
    BuildContext context,
    int index,
    TextBookLoaded state,
    Map<int, List<PersonalNote>> noteMap,
    ReadingSegments? segments,
    bool continuous,
  ) {
    final line = _buildLine(
      index,
      state,
      context,
      noteMap,
      segments != null && index < segments.length ? segments[index] : null,
      continuous,
    );
    final bannerText = state.protection.bannerText;
    if (index == 0 && widget.isMainText && state.protection.hasBanner) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BookSourceBanner(text: bannerText!, fontSize: widget.fontSize),
          line,
        ],
      );
    }
    return line;
  }

  Widget _buildLine(
    int index,
    TextBookLoaded state,
    BuildContext context,
    Map<int, List<PersonalNote>> noteMap,
    ReadingSegment? segment,
    bool continuous,
  ) {
    final primaryLineIndex = segment?.startLineIndex ?? index;
    final isMultiLine =
        continuous &&
        segment != null &&
        !segment.isHeader &&
        segment.sourceLineIndices.length > 1;
    if (isMultiLine && !segment.isLoaded) {
      return UnloadedParagraphPlaceholder(
        lineCount: segment.sourceLineIndices.length,
        fontSize: widget.fontSize,
      );
    }
    final itemLines = segment?.sourceLineIndices ?? [primaryLineIndex];
    bool inItem(int line) =>
        segment?.containsLine(line) ?? line == primaryLineIndex;
    final selectedLines = widget.isMainText
        ? {
            for (final selected in state.selectedIndices)
              if (inItem(selected)) selected,
          }
        : const <int>{};
    final isSelected = selectedLines.isNotEmpty;
    // נתפס בזמן BUILD (כמו selectedText ב-ValueListenableBuilder של Combined),
    // כך שגם אם onSelectionChanged(null) ירוץ לפני menuBuilder, ה-closure
    // כבר סגור על הערך הנכון מהבנייה האחרונה.
    final savedTextAtBuild = _savedSelectedText;

    final theme = Theme.of(context);
    // ברקע ובסמן של פריט רב-שורתי מטפלות השורות עצמן.
    final backgroundColor = isMultiLine
        ? null
        : readerLineBackgroundColor(
            readerLineMarks(
              state,
              primaryLineIndex,
              isMainText: widget.isMainText,
              isRelated: widget.highlightedIndices?.contains(index) ?? false,
            ).background,
            theme.colorScheme,
          );

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

    final Widget gutterChild = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(color: backgroundColor),
      // Paint selection over the paragraph without changing text margins.
      padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
      child: BlocBuilder<SettingsBloc, SettingsState>(
        builder: (context, settingsState) {
          final lineContext = _readerLineContext(state, settingsState, noteMap);
          if (isMultiLine) {
            return _buildMultiLineItem(itemLines, state, lineContext, noteMap);
          }
          final textWidget = ReaderLineBlock(
            lineIndex: primaryLineIndex,
            child: _lineTextWidget(
              buildReaderLineSpec(primaryLineIndex, lineContext),
              state,
              notesForLine,
            ),
          );
          // בטור מפרש רש"י: לעזי רש"י מתחת לשורה (מסתתר לבד אם אין).
          // בדיקת הכותרת כאן חוסכת בניית תת-הבלוק בכל שורה של טור שאינו רש"י.
          if (!widget.isMainText &&
              widget.bookTitle != null &&
              isRashiTitle(widget.bookTitle!)) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                textWidget,
                LaazCommentarySubBlock.forLine(
                  rashiBookTitle: widget.bookTitle!,
                  rashiLineIndex: primaryLineIndex + 1,
                  baseFontSize: widget.fontSize,
                ),
              ],
            );
          }
          return textWidget;
        },
      ),
    );

    // EnhancedGestureDetector ולא GestureDetector רגיל: לחיצה משולשת לבחירת
    // פסקה ב-SelectableRegion חייבת לא לזלוג ל-onTap שמאפס את הבחירה.
    return Builder(
      builder: (itemContext) => EnhancedGestureDetector(
        behavior: HitTestBehavior.translucent,
        onSingleTap: widget.isMainText
            ? () {
                final line = lineAtPointer();
                if (line == null) return;
                _requestKeyboardFocus('line-tap-$line');
                // איפוס הטקסט השמור
                setState(() {
                  _savedSelectedText = null;
                  _savedSelectedIndex = null;
                  _selectionLineStart = null;
                  _selectionLineEnd = null;
                  _selectionStartColumn = null;
                });
                context.read<TextBookBloc>().add(
                  UpdateSelectedIndex(
                    state.selectedIndices.contains(line) ? null : line,
                  ),
                );
              }
            : null,
        onCtrlClick: widget.isMainText
            ? () {
                // Ctrl+Click → הוספה/הסרה של השורה מבחירה מרובה
                final line = lineAtPointer();
                if (line == null) return;
                _requestKeyboardFocus('line-tap-$line');
                context.read<TextBookBloc>().add(
                  UpdateSelectedIndex(line, additive: true),
                );
              }
            : null,
        onDoubleTap: !widget.isMainText && widget.bookTitle != null
            ? () {
                // לחיצה כפולה במפרש - פתיחה בטאב נפרד
                widget.openBookCallback(
                  TextBookTab(
                    book: TextBook(title: widget.bookTitle!),
                    index: primaryLineIndex,
                    openLeftPane:
                        (Settings.getValue<bool>('key-pin-sidebar') ?? false) ||
                        (Settings.getValue<bool>('key-default-sidebar-open') ??
                            false),
                  ),
                );
              }
            : null,
        child: Listener(
          onPointerDown: (event) {
            if (event.buttons != kPrimaryMouseButton) return;
            _focusKeyboardAfterPointerDown();
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
          child: AppContextMenuRegion(
            // שמירת האינדקס דרך ה-Listener של AppContextMenuRegion (מחוסן מהזירה),
            // כך שגם כשלחיצה ימנית חוסמת את SelectableRegion ושומרת בחירה — האינדקס
            // עדיין נשמר עבור פעולות התפריט.
            onSecondaryTapDown: (details) {
              _secondaryTapDownAt = DateTime.now();
              final hit = hitAt(itemContext, details.globalPosition);
              final root = hit?.root ?? context.findRenderObject();
              final selectedTextAtSecondaryTap =
                  _savedSelectedText?.trim().isNotEmpty == true
                  ? _savedSelectedText
                  : savedTextAtBuild;
              final occurrenceStart =
                  root == null || selectedTextAtSecondaryTap == null
                  ? null
                  : renderedSelectionStartAtPosition(
                      root: root,
                      globalPosition: details.globalPosition,
                      selectedSegment: selectedTextAtSecondaryTap,
                      lineRange: hit?.lineRange,
                    );
              setState(() {
                _contextMenuSelectedText = selectedTextAtSecondaryTap;
                _savedSelectedIndex = hit?.lineIndex ?? primaryLineIndex;
                if (occurrenceStart != null) {
                  _selectionStartColumn = occurrenceStart;
                }
              });
            },
            // לחיצה ימנית על הטקסט המסומן (כולל הרווח שבין שורות-תצוגה של שורת-מקור
            // שנשברה) לא תשחרר את הבחירה; לחיצה על חלק לא-מסומן מבטלת כרגיל.
            shouldPreserveSelectionOnSecondaryTap: (globalPosition) {
              final hit = hitAt(itemContext, globalPosition);
              return _shouldPreserveSelectionAt(
                globalPosition,
                hit?.lineIndex ?? primaryLineIndex,
                context,
                hit: hit,
              );
            },
            menuBuilder: (menuCtx, tapPos) {
              final hit = hitAt(itemContext, tapPos);
              final currentSelectedText =
                  _contextMenuSelectedText?.trim().isNotEmpty == true
                  ? _contextMenuSelectedText
                  : _savedSelectedText?.trim().isNotEmpty == true
                  ? _savedSelectedText
                  : savedTextAtBuild;
              return [
                ...ContextMenuUtils.buildInlineLinkContextMenuEntries(
                  menuCtx,
                  tapPos,
                ),
                ..._buildContextMenu(
                  state,
                  hit?.lineIndex ?? primaryLineIndex,
                  menuCtx,
                  tapPos,
                  currentSelectedText,
                  lineRange: hit?.lineRange,
                ),
              ];
            },
            child: isMultiLine
                ? ReaderLineGutter(
                    color: theme.colorScheme.primary,
                    selectedLines: selectedLines,
                    foreground: true,
                    child: gutterChild,
                  )
                : CustomPaint(
                    foregroundPainter: isSelected
                        ? SelectionGutterPainter(theme.colorScheme.primary)
                        : null,
                    child: gutterChild,
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
    lines: widget.content,
    profile: _displayProfile(state),
    isMainText: widget.isMainText,
    fontSize: widget.fontSize,
    fontFamily: widget.fontFamily ?? settingsState.fontFamily,
    fontWeight:
        (widget.isMainText
            ? settingsState.fontBold
            : settingsState.commentatorsFontBold)
        ? FontWeight.bold
        : null,
    lineHeight: settingsState.lineHeight,
    isRelated: widget.isMainText
        ? null
        : (line) => widget.highlightedIndices?.contains(line) ?? false,
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
    final rawText = widget.content[lineIndex];
    // קישורי inline שייכים לטקסט הראשי; סימוני הערות שייכים גם למפרש.
    final inlineLinks =
        widget.isMainText &&
            settingsState.enableHtmlLinks &&
            state.book.versionTitle == null
        ? (state.linksByLine[lineIndex + 1] ?? const <Link>[])
              .where((link) => link.start != null && link.end != null)
              .toList()
        : const <Link>[];
    var data = rawText;
    if (widget.isMainText) {
      // קישורי inline ראשונים — האופסטים שלהם גולמיים; אחריהם השמות, לפני
      // כל הזרקה שמוסיפה תוכן גלוי.
      data = _injectPreviewMarkers(
        injectDivineNameMarkers(
          injectInlineLinks(data, inlineLinks),
          state.divineNames,
          lineIndex,
        ),
        lineIndex,
        state,
      );
    } else if (widget.anchorLinksByLine != null) {
      data = _injectOwnAnchorMarkers(data, lineIndex, state);
    }
    // סימוני הערות אישיות — אחרונים.
    return buildAnnotatedLineHtml(
      rawLine: data,
      sourceLine: rawText,
      notesForLine: notesForLine,
      lineIndex0: lineIndex,
      underlineColor: Theme.of(context).colorScheme.primary,
      replaceHolyNames: _displayProfile(state).replaceHolyNames,
    );
  }

  /// מצב הניקוד/פיסוק של הטאב חל גם על טורי המפרשים.
  Widget _lineTextWidget(
    ReaderLineSpec spec,
    TextBookLoaded state,
    List<PersonalNote> notesForLine,
  ) {
    final lineIndex = spec.lineIndex;
    final main = widget.isMainText;
    final hasOwnAnchors = widget.anchorLinksByLine != null;
    return SmartTextWidget(
      text: spec.html,
      highlightBookId: main ? state.book.title : null,
      highlightBookUid: main ? PluginBookIdentity.uidOf(state.book) : null,
      highlightBookDbId: main ? state.book.id : null,
      highlightBookType: main ? PluginBookIdentity.typeOf(state.book) : null,
      highlightBookSource: main
          ? PluginBookIdentity.sourceOf(state.book)
          : null,
      highlightSectionIndex: main ? lineIndex : null,
      highlightSourceText: main ? spec.sourceText : null,
      widgetKey: ValueKey('html_simple_text_$lineIndex'),
      settings: spec.settings,
      onOpenBook: widget.openBookCallback,
      onNoteTap: notesForLine.isEmpty
          ? null
          : main
          ? (line) => _onInlineNoteTap(line)
          : (_) {
              final openInSidebar = widget.onOpenCommentaryPersonalNote;
              if (openInSidebar != null && widget.bookTitle != null) {
                openInSidebar(
                  _commentaryNotesKey(widget.bookTitle!),
                  widget.reportBook?.categoryId,
                  lineIndex + 1,
                );
              } else {
                showPersonalNotesDialog(context: context, notes: notesForLine);
              }
            },
      onAnchorTap: main || hasOwnAnchors ? _handlePreviewTap : null,
      onAnchorHover: main || hasOwnAnchors ? _handlePreviewHover : null,
      onAnchorHoverExit: main || hasOwnAnchors ? _handlePreviewHoverExit : null,
      onTouchPreview: main || hasOwnAnchors ? _handleTouchPreview : null,
    );
  }

  /// פריט של כמה שורות: רצפים ממוזגים לפסקה, ושורות-בלוק בנפרד.
  Widget _buildMultiLineItem(
    List<int> itemLines,
    TextBookLoaded state,
    ReaderLineContext lineContext,
    Map<int, List<PersonalNote>> noteMap,
  ) => buildReaderMultiLineItem(
    context,
    itemLines: itemLines,
    lineContext: lineContext,
    blockText: (spec) => _lineTextWidget(
      spec,
      state,
      noteMap[spec.lineIndex + 1] ?? const <PersonalNote>[],
    ),
    onTapUrl: (url) => handleReaderParagraphUrl(
      context,
      url,
      onTouchPreview: _handleTouchPreview,
      onAnchorTap: _handlePreviewTap,
      onNoteTap: _onInlineNoteTap,
      openBook: (tab) => widget.openBookCallback(tab),
    ),
    onAnchorHover: _handlePreviewHover,
    onAnchorExit: _handlePreviewHoverExit,
  );

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
    final ungrouped = availableCommentators
        .where((c) => !allGrouped.contains(c))
        .toList();

    List<AppContextMenuEntry> buildGroup(List<String> commentators) =>
        commentators
            .map(
              (c) => AppContextMenuEntry(
                label: c,
                icon: c == widget.bookTitle
                    ? FluentIcons.checkmark_24_regular
                    : null,
                onTap: () => _switchCommentator(c, state),
              ),
            )
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
    final workspaceId = activePageShapeWorkspaceId(context);
    final config = PageShapeSettingsManager.loadConfiguration(
      state.book.title,
      heCategories: state.book.heCategories,
      workspaceId: workspaceId,
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
        for (final selection in decodePageShapeCommentatorsSelection(
          configValue,
        )) {
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
        '⚠️ PageShape: Could not find column for commentator "${widget.bookTitle}"',
      );
      return;
    }

    // עדכון ההגדרה
    final updatedConfig = Map<String, String?>.from(config);
    if (matchedSelection != null) {
      final updatedSelection =
          decodePageShapeCommentatorsSelection(updatedConfig[columnToUpdate])
              .map(
                (selection) =>
                    selection == matchedSelection ? newCommentator : selection,
              )
              .toList();
      updatedConfig[columnToUpdate] = encodePageShapeCommentatorsSelection(
        updatedSelection,
      );
    } else {
      updatedConfig[columnToUpdate] = newCommentator;
    }

    // כששולחן העבודה מחזיק בחירה משלו לספר, ההחלפה נשמרת אליה - אחרת היא
    // נכתבת לספר/לקטגוריה ונדרסת מיד בטעינה הבאה.
    final workspaceToSave = PageShapeSettingsManager.commentatorWorkspaceTarget(
      workspaceId,
      state.book.title,
    );

    // בדיקה אם יש הגדרה ספציפית לספר (לא רק הדגל, אלא הגדרה ממשית)
    final hasActualBookConfig =
        PageShapeSettingsManager.loadConfiguration(state.book.title) != null;

    // אם יש הגדרה ספציפית לספר - שומרים לספר
    // אחרת - שומרים לקטגוריה (אם יש)
    final categoryToSave =
        workspaceToSave == null &&
            !hasActualBookConfig &&
            state.book.heCategories != null &&
            state.book.heCategories!.isNotEmpty
        ? PageShapeSettingsManager.getActiveCategory(state.book.heCategories) ??
              PageShapeSettingsManager.getParentCategory(
                state.book.heCategories,
              )
        : null;

    PageShapeSettingsManager.saveConfiguration(
      state.book.title,
      updatedConfig,
      saveToCategory: categoryToSave,
      saveToWorkspaceId: workspaceToSave,
    );

    // קריאה ל-callback לרענון המסך
    widget.onCommentatorChanged?.call();
  }
}

class _CopyTextIntent extends Intent {
  const _CopyTextIntent();
}
