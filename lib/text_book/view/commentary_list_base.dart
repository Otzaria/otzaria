import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_fonts.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:flutter/gestures.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/widgets/text/rtl_selection_shortcuts.dart';
import 'package:otzaria/widgets/text/selection_copy_shortcuts.dart';
import 'package:otzaria/text_book/view/selection/selected_text_restore.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/services/target_line_links_service.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/utils/navigation/talmud_bavli_open_format.dart';
import 'package:otzaria/personal_notes/personal_notes_system.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/widgets/text_book_state_builder.dart';
import 'package:otzaria/widgets/commentary/commentary_content.dart';
import 'package:otzaria/text_book/view/error_report_dialog.dart';
import 'package:otzaria/text_book/models/commentary_scroll_request.dart';
import 'package:otzaria/text_book/models/commentator_group.dart';
import 'package:otzaria/text_book/utils/commentary_search_utils.dart';
import 'package:otzaria/text_display/models/text_display_profile.dart';
import 'package:otzaria/text_display/models/text_display_slot.dart';
// מיוצא כאן כדי שצרכני כרטיסיית הטקסט יייבאו אותו מנקודה אחת.
export 'package:otzaria/text_book/utils/commentary_search_utils.dart'
    show CommentarySearchSnippet;
import 'package:otzaria/text_book/utils/category_settings_utils.dart';
import 'package:otzaria/text_book/utils/commentary_title_visibility.dart';
import 'package:otzaria/text_book/utils/commentary_type_filter.dart';
import 'package:otzaria/text_book/utils/commentator_group_builder.dart';
import 'package:otzaria/text_book/utils/link_anchor_markers.dart';
import 'package:otzaria/text_book/view/commentators_list_screen.dart';
import 'package:otzaria/widgets/misc/commentators_filter_button.dart';
import 'package:otzaria/widgets/layout/commentators_filter_screen.dart';
import 'package:otzaria/widgets/lists/commentators_selection_panel.dart';
import 'package:otzaria/widgets/feedback/otzaria_empty_state.dart';
import 'package:otzaria/widgets/misc/progressive_scrolling.dart';
import 'package:otzaria/widgets/misc/smooth_wheel_scroll.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/utils/text/ref_helper.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/utils/ui/context_menu_utils.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:otzaria/widgets/feedback/app_future_builder.dart';
import 'package:otzaria/widgets/feedback/scrollable_positioned_list_scrollbar.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/text_book/utils/inline_notes_utils.dart'
    as inline_notes;
import 'package:otzaria/text_book/view/selection/selection_sync_controller.dart';
import 'package:otzaria/text_book/view/selection/selection_hit_test.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';
import 'package:otzaria/core/messages/text_book_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/printing/commentary_print_builder.dart';
import 'package:otzaria/printing/view/printing_screen.dart';

// Type alias לתאימות לאחור - משתמש ב-LinkGroup מה-Service
typedef CommentaryGroup = LinkGroup;

/// האם לחיצת ה-pointer צריכה למקד את אזור הגלילה (ProgressiveScroll).
/// לחיצה שכוללת כפתור ימני מוחרגת: מיקוד ה-ProgressiveScroll (אב ל-SelectionArea)
/// גוזל פוקוס מ-SelectableRegion ומוחק את ההדגשה בזמן פתיחת תפריט ההקשר.
/// [buttons] הוא bitmask, ולכן בודקים את הביט הימני ולא שוויון מלא.
bool shouldFocusScrollOnPointerDown(int buttons) =>
    (buttons & kSecondaryButton) == 0;

/// לוכד snapshot של הטקסט הנבחר לשימוש בפעולת ההעתקה של תפריט ההקשר.
/// נדרש כי לחיצה ימנית עלולה לשחרר את הבחירה (onSelectionChanged(null)) לפני
/// שהמשתמש בוחר "העתק" — קריאה חיה מהנוטיפייר באותו רגע הייתה מחזירה null.
String? captureSelectedTextForMenu(ValueListenable<String?> saved) =>
    saved.value;

/// מפתחות צ׳יפי סוגי המפרשים שקיימים בפועל בקישורי הקטע, בסדר
/// [LinkTypes.commentaryFilterTypes]. סוג בלי קישורים אינו מקבל צ׳יפ.
@visibleForTesting
List<String> buildCommentaryTypeChipKeys(List<Link> links) =>
    CommentaryTypeFilter.chipKeys(links);

/// הבחירה האפקטיבית: רק מפתחות שיש להם צ׳יפ בקטע הנוכחי. בחירה שאין לה אף
/// צ׳יפ קיים נחשבת ריקה = הצג הכל, ולא מסתירה את כל המפרשים.
@visibleForTesting
Set<String> effectiveCommentaryTypes({
  required Set<String> selectedTypes,
  required List<String> availableKeys,
}) => CommentaryTypeFilter.effectiveTypes(
  selectedTypes: selectedTypes,
  availableKeys: availableKeys,
);

/// האם המעבר משורות המקור [previous] אל [current] הוא מעבר לקטע אחר, שבו יש
/// להציג את המפרשים מתחילתם. שורת העוגן (הראשונה) קובעת: הרחבת הבחירה
/// (Ctrl+לחיצה) או גדילת חלון הנראוּת סביב אותו עוגן אינן מעבר לקטע.
@visibleForTesting
bool isCommentarySectionChange({
  required List<int> previous,
  required List<int> current,
}) {
  if (previous.isEmpty && current.isEmpty) return false;
  if (previous.isEmpty || current.isEmpty) return true;
  return previous.first != current.first;
}

/// האם מעבר קטע רשאי לאפס את הגלילה לראש הרשימה.
///
/// לחיצה על אות-עוגן שולחת קודם `UpdateSelectedIndex(sourceLine)`, ולכן
/// *אותה לחיצה* נחשבת גם מעבר קטע. האיפוס מתוזמן מה-build שנגרם ממנה —
/// כלומר **אחרי** הגלילה לעוגן — והיה מוחק אותה ב-`jumpTo(0)`. בממשק זה
/// נראה כאילו נפתח הקטע הראשון של המפרש, שהוא גם היעד של האות הראשונה,
/// ומכאן הרושם ש"רק האות הראשונה עובדת".
@visibleForTesting
bool shouldResetScrollForSectionChange({
  required bool hasPendingAnchorScroll,
}) => !hasPendingAnchorScroll;

class CommentaryListBase extends StatefulWidget {
  final Function(OpenedTab) openBookCallback;
  final double fontSize;
  final List<int>? indexes;
  final bool showSearch;
  final VoidCallback? onClosePane;
  final bool shrinkWrap;
  final ItemPositionsListener? itemPositionsListener;
  final List<String>? selectedCommentatorsOverride;
  final Set<String> hiddenCommentators;
  final List<CommentatorGroup>? commentatorGroupsOverride;
  final String? bookTitleOverride;
  final ValueChanged<List<String>>? onSelectedCommentatorsOverrideChanged;
  final SelectionSyncController? selectionSyncController;
  final ValueListenable<int>? openFilterRequest;
  final ValueNotifier<int>? openFilterNotifier;
  final ValueNotifier<int>? closeFilterNotifier;
  // כאשר מסופק, CommentaryListBase ישתמש בו לחיפוש ולא יציג שורת חיפוש פנימית
  final TextEditingController? externalSearchController;
  final ValueNotifier<int>? externalCurrentIndexNotifier;
  final ValueNotifier<int>? externalTotalResultsNotifier;

  /// מפה חיצונית: path של מפרש → מספר תוצאות חיפוש בו (ריק אם אין חיפוש)
  final ValueNotifier<Map<String, int>>? externalSearchResultsByPathNotifier;

  /// רשימת קטעי חיפוש חיצונית עם מידע לניווט (ריקה אם אין חיפוש)
  final ValueNotifier<List<CommentarySearchSnippet>>?
  externalSearchSnippetsNotifier;

  /// כשהדגל מופעל, ישתמש ב-availableCommentators (כל מפרשי הספר) ולא ב-activeCommentators
  final bool useAvailableCommentators;

  /// קולבק לפתיחת המפרשים בכרטיסייה חדשה. כש-null הלחצן לא יוצג.
  final VoidCallback? onOpenInNewTab;

  /// נוטיפייר חיצוני שמשתקף ממצב הכיווץ הגלובלי. שימוש: הורה רוצה להציג
  /// מחוץ לפאנל כפתור כווץ/הרחב מסונכרן.
  final ValueNotifier<bool>? externalAllExpandedNotifier;

  /// אם סופק, יקרא במקום פתיחת חלון בחירת המפרשים הפנימי (פופ-אפ).
  /// מאפשר להורה (למשל CommentatorsTabScreen) להפנות בחירת מפרשים ללשונית
  /// בסרגל הצד במקום פופ-אפ.
  final VoidCallback? onFilterOpenRequested;

  /// כשאמת, חלונית המפרשים תתפוס פוקוס אוטומטית כשהיא נטענת (לכרטיסיית
  /// המפרשים העצמאית, לא לתצוגה בתוך הספר שבה הפוקוס שייך לגוף הטקסט).
  final bool autofocus;

  /// מדגיש מחרוזת חיפוש חיצונית בלי להציג את ממשק החיפוש הפנימי.
  /// מיועד לתצוגה המשולבת, שבה החיפוש מנוהל ע"י ה-BLoC של הטקסט הראשי.
  final ValueListenable<String>? highlightQueryListenable;

  /// בחירת סוגי המפרשים המנוהלת ע"י ההורה. נדרש כשהצ׳יפים מוצגים בפאנל שההורה
  /// בונה (כרטיסיית המפרשים) — בלעדיו הסינון היה חל רק על הפאנל הפנימי.
  final CommentaryTypeSelection? typeSelection;
  final void Function(Link link, int lineNumber)? onOpenPersonalNote;
  final PersonalNotesLoader? personalNotesLoader;

  /// רוחב מקסימלי לתוכן הרשימה (הגדרת רוחב הטקסט), או null לרוחב מלא. מוחל
  /// בתוך פס הגלילה, כדי שהפס יישאר צמוד לדופן החלון ולא יידחק פנימה עם הטקסט.
  final double? contentMaxWidth;

  /// בקשות גלילה לקטע מפרש, מלחיצה על עוגן-אות בטקסט הראשי. משמש את מסלול
  /// "מפרשים בצד", שבו הרשימה יושבת בפאנל נפרד ואין להורה גישה ישירה אליה
  /// (במסלול "מפרשים מתחת" הכרטיס קורא ל-[CommentaryListBaseState.scrollToCommentator]
  /// דרך GlobalKey).
  final ValueListenable<CommentaryScrollRequest?>? scrollTargetListenable;

  const CommentaryListBase({
    super.key,
    required this.openBookCallback,
    required this.fontSize,
    this.indexes,
    required this.showSearch,
    this.onClosePane,
    this.shrinkWrap = true,
    this.itemPositionsListener,
    this.selectedCommentatorsOverride,
    this.hiddenCommentators = const {},
    this.commentatorGroupsOverride,
    this.bookTitleOverride,
    this.onSelectedCommentatorsOverrideChanged,
    this.selectionSyncController,
    this.openFilterRequest,
    this.openFilterNotifier,
    this.closeFilterNotifier,
    this.externalSearchController,
    this.externalCurrentIndexNotifier,
    this.externalTotalResultsNotifier,
    this.externalSearchResultsByPathNotifier,
    this.externalSearchSnippetsNotifier,
    this.useAvailableCommentators = false,
    this.onOpenInNewTab,
    this.externalAllExpandedNotifier,
    this.onFilterOpenRequested,
    this.autofocus = false,
    this.highlightQueryListenable,
    this.typeSelection,
    this.onOpenPersonalNote,
    this.personalNotesLoader,
    this.contentMaxWidth,
    this.scrollTargetListenable,
  });

  @override
  State<CommentaryListBase> createState() => CommentaryListBaseState();
}

class CommentaryListBaseState extends State<CommentaryListBase> {
  final TextEditingController _searchController = TextEditingController();
  final ValueNotifier<String> _searchQueryNotifier = ValueNotifier<String>('');
  final ScrollOffsetController scrollController = ScrollOffsetController();
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  final Map<String, GlobalKey> _itemKeys = {};
  // טקסט פשוט מרונדר לכל מפרש מוצג — לשחזור מעברי שורה בהעתקה רב-שורתית.
  final Map<String, String> _renderedTextByKey = {};
  // כותרת מרונדרת (displayReference) לכל מפרש מוצג — לשחזור מעברי שורה כשהבחירה
  // כוללת גם כותרות.
  final Map<String, String> _renderedTitleByKey = {};
  final ValueNotifier<int> _currentSearchIndexNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> _totalSearchResultsNotifier = ValueNotifier<int>(0);
  final Map<String, int> _searchResultsPerLink = {};
  int _lastScrollIndex = 0; // שומר את מיקום הגלילה האחרון
  // שורות המקור שהרשימה מציגה כרגע — לזיהוי מעבר לקטע אחר.
  List<int>? _sectionIndexes;
  bool _scrollToTopScheduled = false;
  // bucket מקומי: ScrollablePositionedList משחזר מיקום מ-PageStorage ודורס בכך
  // את initialScrollIndex, כך שקטע חדש נפתח על היסט הקטע הקודם (issue #846).
  final PageStorageBucket _listStorageBucket = PageStorageBucket();
  // מצב גלובלי של פתיחה/סגירה של כל המפרשים — חשוף ככ-ValueListenable כדי
  // שצרכנים חיצוניים (למשל CommentatorsTabScreen) יוכלו להאזין ולעדכן UI.
  final ValueNotifier<bool> _allExpandedNotifier = ValueNotifier<bool>(true);
  bool get _allExpanded => _allExpandedNotifier.value;
  set _allExpanded(bool value) => _allExpandedNotifier.value = value;
  final Map<String, bool> _expansionStates =
      {}; // מעקב אחרי מצב כל קבוצת מפרשים
  String? _cachedGroupingSignature;
  Future<List<CommentaryGroup>>? _cachedGroupsFuture;

  // הרשימה השטוחה: פריט נפרד לכל כותרת מפרש ולכל קטע — כך הרשימה נבנית
  // בעצלנות ולא כל מפרשי הקטע בבת אחת (מקור האיטיות ב-issue #844).
  Map<String, int> _groupHeaderFlatIndex = const {};
  Map<String, int> _linkFlatIndex = const {};
  // הערות אישיות פר ספר-מפרש, משותפות לכל הקטעים של אותו מפרש.
  final Map<String, Future<List<PersonalNote>>> _personalNotesByGroup = {};

  // Anti-jitter search stats
  Timer? _searchUpdateDebounce;
  final Map<String, int> _pendingCounts = {};
  // חישוב ספירות חיפוש ברקע על כל הקישורים — הרשימה וירטואלית ופריטים שלא
  // נבנו אינם מדווחים, לכן אסור להסתמך על ה-widgets לספירה.
  Timer? _searchComputeDebounce;
  int _searchComputeGen = 0;
  int _lastLinksSignature = 0;
  // מפה: link key → path2 (לצורך קיבוץ תוצאות לפי מפרש)
  final Map<String, String> _linkKeyToPath = {};
  // מפה: link key → קטעי טקסט (snippets) לתוצאות החיפוש
  final Map<String, List<String>> _searchSnippetsPerLink = {};

  final ValueNotifier<String?> _savedSelectedText = ValueNotifier<String?>(
    null,
  ); // טקסט נבחר לתפריט הקשר
  final ValueNotifier<Link?> _lastSelectedLink = ValueNotifier<Link?>(
    null,
  ); // ה-link האחרון שנוגעו בו (לכותרות בהעתקה)
  final Object _selectionOwner = Object(); // מזהה ייחודי לבעלות על הבחירה
  final GlobalKey<SelectionAreaState> _selectionAreaKey = GlobalKey();
  bool _showCommentatorsFilter = false; // האם להציג את מסך בחירת המפרשים
  bool _filterWasAutoOpened = false; // האם מסך הסינון נפתח אוטומטית (לא ידנית)
  // latch חד-פעמי: מסמן שהפתיחה האוטומטית דרך onFilterOpenRequested כבר נשלחה.
  // בלעדיו הקולבק היה נקרא בכל rebuild שבו עדיין אין מפרשים נבחרים (כי המסלול
  // הזה אינו משנה את _showCommentatorsFilter), מה שמציף את ההורה ב-side effect
  // ועלול ליצור לולאת rebuild. מתאפס כשהבחירה אינה ריקה — כדי שריקון עתידי
  // יפתח שוב את הבחירה.
  bool _autoFilterOpenNotified = false;
  bool _userInteractedWithFilter =
      false; // האם המשתמש בחר בעצמו בתוך פאנל הסינון
  final FocusNode _focusNode = FocusNode();
  final FocusNode _searchFocusNode = FocusNode();
  int _lastSeenFilterRequest = 0;
  bool _snippetsRebuildScheduled = false;
  // האם להציג את שדה החיפוש (true) או את שורת ארבעת הלחצנים (false)
  bool _showSearchField = false;
  // סינון לפי סוג מפרש (תרגום/מדרש וכו׳). מצב מקומי ולא מוגדר: הצ׳יפים תלויים
  // בקטע הנוכחי, ובחירה שנשמרה הייתה מסננת בשקט ספר אחר שנפתח אחריו.
  Set<String> _localCommentaryTypes = const {};

  Set<String> get _selectedCommentaryTypes =>
      widget.typeSelection?.value ?? _localCommentaryTypes;

  void _setSelectedCommentaryTypes(Set<String> types) {
    final external = widget.typeSelection;
    if (external != null) {
      external.value = types;
      return;
    }
    setState(() => _localCommentaryTypes = types);
  }

  String _getLinkKey(Link link) => commentaryLinkKey(link);

  // רשימה של כל ה-links לפי סדר הופעתם (נבנית מחדש בכל build)
  List<Link> _orderedLinks = [];

  /// היעד שממתין לגלילה: שם המפרש, ואופציונלית מפתח הקטע המדויק.
  ({String title, String? linkKey})? _pendingScrollTarget;
  bool _commentatorScrollScheduled = false;
  bool _commentatorScrollRunning = false;

  /// מזהה הבקשה הפעילה. בקשה חדשה מבטלת לולאת ניסיונות שעדיין רצה, אחרת
  /// היעד הישן היה ממשיך למשוך את הרשימה אחרי לחיצה על עוגן אחר.
  int _commentatorScrollGeneration = 0;

  /// מזהה הבקשה החיצונית האחרונה שטופלה (מסלול "מפרשים בצד").
  int _lastHandledScrollRequestId = 0;

  /// שורת המקור שממנה נלחץ העוגן האחרון. מעבר קטע *אליה* אינו מאפס את
  /// הגלילה — הוא נגרם מאותה לחיצה שביקשה אותה.
  int? _anchorScrollSectionLine;

  List<String> _allSelectedCommentators(TextBookLoaded state) {
    if (widget.selectedCommentatorsOverride != null) {
      return widget.selectedCommentatorsOverride!;
    }
    if (widget.useAvailableCommentators) {
      return state.availableCommentators;
    }
    return state.activeCommentators;
  }

  List<String> _selectedCommentators(TextBookLoaded state) {
    final selected = _allSelectedCommentators(state);
    return selected
        .where(
          (title) =>
              title != kNotesCommentatorTitle &&
              !widget.hiddenCommentators.contains(title),
        )
        .toList();
  }

  String _buildGroupingSignature(List<Link> links) {
    return links
        .map(
          (link) =>
              '${link.index1}|${link.path2}|${link.index2}|${link.connectionType}',
        )
        .join('||');
  }

  Future<List<CommentaryGroup>> _getCachedGroups(List<Link> links) {
    final signature = _buildGroupingSignature(links);
    if (_cachedGroupingSignature == signature && _cachedGroupsFuture != null) {
      return _cachedGroupsFuture!;
    }

    _cachedGroupingSignature = signature;
    _cachedGroupsFuture = CommentaryService.groupConsecutiveLinksAsync(links);
    return _cachedGroupsFuture!;
  }

  /// בונה את פריטי הרשימה השטוחה מהקבוצות, לפי מצב הכיווץ הנוכחי, ומעדכן
  /// את מיפויי האינדקסים לגלילה (כותרת קבוצה / קטע מפרש → אינדקס ברשימה).
  List<CommentaryFlatItem> _buildFlatItems(List<CommentaryGroup> groups) {
    final headerIdx = <String, int>{};
    final linkIdx = <String, int>{};
    final items = buildCommentaryFlatItems(
      groups: groups,
      isGroupExpanded: (title) => _expansionStates[title] ?? _allExpanded,
      linkKey: _getLinkKey,
      headerIndexOut: headerIdx,
      linkIndexOut: linkIdx,
    );
    _groupHeaderFlatIndex = headerIdx;
    _linkFlatIndex = linkIdx;
    return items;
  }

  void _toggleGroupExpansion(CommentaryGroup group) {
    final key = group.bookTitle;
    final expanded = !(_expansionStates[key] ?? _allExpanded);
    setState(() {
      _expansionStates[key] = expanded;
      _updateGlobalExpansionState();
    });
    if (expanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final headerIndex = _groupHeaderFlatIndex[key];
        if (headerIndex != null) _ensureExpandedGroupVisible(headerIndex);
      });
    }
  }

  Future<List<PersonalNote>> _personalNotesForGroup(CommentaryGroup group) {
    return _personalNotesByGroup.putIfAbsent(group.bookTitle, () {
      final loader = widget.personalNotesLoader;
      if (loader == null) return Future.value(const <PersonalNote>[]);
      return loader(
        group.bookTitle,
        categoryId: group.links.firstOrNull?.targetCategoryId,
      );
    });
  }

  void _refreshGroupPersonalNotes(String groupTitle) {
    setState(() => _personalNotesByGroup.remove(groupTitle));
  }

  List<CommentatorGroup> _commentatorGroups(TextBookLoaded state) {
    return widget.commentatorGroupsOverride ?? state.commentatorGroups;
  }

  /// צ׳יפי הסוגים, מכל קישורי חלון הקריאה ולא רק מהקטע הנראה — אחרת צ׳יפ
  /// נעלם וחוזר בדפדוף והבחירה מתאפסת. מסוננים לפי שם המפרש בלבד, כדי שלא
  /// יוצג צ׳יפ לסוג שכל מפרשיו מוסתרים.
  List<String> _typeChipKeys(
    TextBookLoaded state,
    List<String> selectedCommentators,
  ) => CommentaryTypeFilter.chipKeysForCommentators(
    links: state.links,
    selectedCommentators: selectedCommentators,
  );

  String _bookTitle(TextBookLoaded state) {
    return widget.bookTitleOverride ?? state.book.title;
  }

  /// אינדקסי השורות הנוכחיים (בחירה מרובה אם יש, אחרת הנראות) — לקביעת אילו
  /// מפרשים נדירים כן להציג ברשימת הבחירה.
  List<int> _currentIndexes(TextBookLoaded state) {
    final raw =
        widget.indexes ??
        (state.selectedIndices.isNotEmpty
            ? state.selectedIndices.toList()
            : state.visibleIndices);
    if (raw.isNotEmpty) return raw;
    return [
      state.selectedIndex ??
          (state.visibleIndices.isNotEmpty ? state.visibleIndices.first : 0),
    ];
  }

  int _getItemSearchIndex(Link link) {
    // מחשב את האינדקס המצטבר עד ל-link הנוכחי
    int cumulativeIndex = 0;
    final linkKey = _getLinkKey(link);

    for (final orderedLink in _orderedLinks) {
      final currentKey = _getLinkKey(orderedLink);
      if (currentKey == linkKey) {
        // מצאנו את ה-link הנוכחי
        final itemResults = _searchResultsPerLink[linkKey] ?? 0;
        if (itemResults == 0) return -1;

        // מחשב את האינדקס היחסי בתוך ה-link הזה
        final relativeIndex =
            _currentSearchIndexNotifier.value - cumulativeIndex;
        return (relativeIndex >= 0 && relativeIndex < itemResults)
            ? relativeIndex
            : -1;
      }
      cumulativeIndex += _searchResultsPerLink[currentKey] ?? 0;
    }

    return -1;
  }

  // מתודות ציבוריות לניווט בחיפוש (למשל מ-CommentatorsTabScreen)
  void navigateSearchPrev() {
    if (_currentSearchIndexNotifier.value > 0) {
      _currentSearchIndexNotifier.value--;
      _scrollToSearchResult();
    }
  }

  void navigateSearchNext() {
    if (_currentSearchIndexNotifier.value <
        _totalSearchResultsNotifier.value - 1) {
      _currentSearchIndexNotifier.value++;
      _scrollToSearchResult();
    }
  }

  /// ממקד את אזור הגלילה כדי שגלילה עם החיצים תעבוד בלי לחיצה. נקרא
  /// מכרטיסיית המפרשים כשהיא הופכת לטאב הפעיל.
  void requestScrollFocus() {
    if (_focusNode.canRequestFocus) _focusNode.requestFocus();
  }

  ValueNotifier<int> get totalSearchResultsNotifier =>
      _totalSearchResultsNotifier;
  ValueNotifier<int> get currentSearchIndexNotifier =>
      _currentSearchIndexNotifier;

  /// האזנה למצב הגלובלי של פתיחה/כיווץ כל המפרשים. שימושי לרכיבי הורה
  /// (כגון [CommentatorsTabScreen]) שמציגים לחצן כווץ/הרחב מחוץ לפאנל זה.
  ValueListenable<bool> get allExpandedListenable => _allExpandedNotifier;

  /// מתג מצב הכיווץ הגלובלי של כל המפרשים. מעדכן את כל הקבוצות בהתאם.
  void toggleAllExpanded() {
    setState(() {
      _allExpanded = !_allExpanded;
      for (final key in _expansionStates.keys) {
        _expansionStates[key] = _allExpanded;
      }
    });
  }

  /// ניווט לתוצאת חיפוש לפי אינדקס גלובלי (לשימוש חיצוני)
  void navigateToGlobalIndex(int index) {
    if (index < 0 || index >= _totalSearchResultsNotifier.value) return;
    _currentSearchIndexNotifier.value = index;
    _scrollToSearchResult();
  }

  void _onHighlightQueryChanged() {
    _searchUpdateDebounce?.cancel();
    _currentSearchIndexNotifier.value = 0;
    _totalSearchResultsNotifier.value = 0;
    _searchResultsPerLink.clear();
    _pendingCounts.clear();
    _scheduleSearchCompute();
  }

  void _onExternalSearchChanged() {
    final text = widget.externalSearchController!.text;
    if (_searchQueryNotifier.value != text) {
      _searchQueryNotifier.value = text;
      if (text.isNotEmpty) {
        setState(() {
          _allExpanded = true;
          for (final key in _expansionStates.keys) {
            _expansionStates[key] = true;
          }
        });
      }
      _currentSearchIndexNotifier.value = 0;
      _totalSearchResultsNotifier.value = 0;
      _searchResultsPerLink.clear();
      _pendingCounts.clear();
      _linkKeyToPath.clear();
      _searchSnippetsPerLink.clear();
      widget.externalSearchResultsByPathNotifier?.value = {};
      widget.externalSearchSnippetsNotifier?.value = [];
      _scheduleSearchCompute();
    }
  }

  void _onTypeSelectionChanged() {
    if (mounted) setState(() {});
  }

  void _handleSearchFocusChange() {
    if (!mounted) return;
    // אם איבדנו פוקוס והשדה ריק — חזור למצב לחצנים
    if (!_searchFocusNode.hasFocus &&
        _showSearchField &&
        _searchController.text.isEmpty) {
      setState(() => _showSearchField = false);
    }
  }

  void _openInlineSearch() {
    setState(() => _showSearchField = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  void _clearSearchAndCloseField() {
    _searchComputeDebounce?.cancel();
    _searchController.clear();
    _searchQueryNotifier.value = '';
    _currentSearchIndexNotifier.value = 0;
    _totalSearchResultsNotifier.value = 0;
    _searchResultsPerLink.clear();
    _pendingCounts.clear();
    setState(() => _showSearchField = false);
  }

  Widget _buildClosePaneButton() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
        borderRadius: AppTokens.borderRadiusAll,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        iconSize: 18,
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints(
          minWidth: 36,
          minHeight: 36,
        ),
        icon: const Icon(FluentIcons.dismiss_24_regular),
        onPressed: widget.onClosePane,
      ),
    );
  }

  Widget _buildButtonsRow(List<String> selectedCommentators) {
    const double gap = 16;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 1. בחירת מפרשים
        CommentatorsFilterButton(
          isActive: false,
          onPressed: _openCommentatorsFilter,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(
            minWidth: 40,
            minHeight: 40,
          ),
          iconSize: 20,
        ),
        // 2. הרחב/כווץ הכל — רק כשיש מפרשים נבחרים (לוגיקה מקורית)
        if (selectedCommentators.isNotEmpty) ...[
          const SizedBox(width: gap),
          IconButton(
            icon: Icon(
              _allExpanded
                  ? FluentIcons.arrow_collapse_all_24_regular
                  : FluentIcons.arrow_expand_all_24_regular,
            ),
            tooltip: _allExpanded ? 'כווץ את כל המפרשים' : 'הרחב את כל המפרשים',
            onPressed: () {
              setState(() {
                _allExpanded = !_allExpanded;
                for (var key in _expansionStates.keys) {
                  _expansionStates[key] = _allExpanded;
                }
              });
            },
          ),
        ],
        // 3. פתיחה בכרטיסייה חדשה
        if (widget.onOpenInNewTab != null) ...[
          const SizedBox(width: gap),
          IconButton(
            icon: const Icon(FluentIcons.open_24_regular),
            tooltip: 'פתח כרטסיית מפרשים',
            onPressed: widget.onOpenInNewTab,
          ),
        ],
        const SizedBox(width: gap),
        // 4. הפעלת שדה החיפוש
        IconButton(
          icon: const Icon(OtzariaIcons.search_24_regular),
          tooltip: 'חיפוש',
          onPressed: _openInlineSearch,
        ),
        // לחצן סגירת הפאנל — נשאר רק אם הקולבק קיים
        if (widget.onClosePane != null) ...[
          const SizedBox(width: gap),
          _buildClosePaneButton(),
        ],
      ],
    );
  }

  /// פותח את מסך ההדפסה עם המפרשים המוצגים כעת (מקובצים לפי מפרש).
  /// פומבי כדי שכרטיסיית המפרשים הייעודית תפעיל אותו מהסרגל/קיצור המקלדת.
  Future<void> printDisplayedCommentaries() async {
    final blocState = context.read<TextBookBloc>().state;
    if (blocState is! TextBookLoaded) return;

    final selectedCommentators = _selectedCommentators(blocState);
    final rawIndexes =
        widget.indexes ??
        (blocState.selectedIndices.isNotEmpty
            ? blocState.selectedIndices.toList()
            : blocState.visibleIndices);
    final indexes = rawIndexes.isNotEmpty
        ? rawIndexes
        : [
            blocState.selectedIndex ??
                (blocState.visibleIndices.isNotEmpty
                    ? blocState.visibleIndices.first
                    : 0),
          ];

    final links = await getLinksforIndexs(
      indexes: indexes,
      links: blocState.links,
      commentatorsToShow: selectedCommentators,
    );
    if (links.isEmpty) {
      UiSnack.show(TextBookMessages.noCommentatorsToPrint);
      return;
    }

    final groups = await _getCachedGroups(links);
    final blocks = await buildCommentaryPrintBlocks(groups);
    if (blocks.isEmpty) {
      UiSnack.show(TextBookMessages.noCommentatorsToPrint);
      return;
    }
    if (!mounted) return;

    final bookTitle = _bookTitle(blocState);
    final profile = blocState.commentaryDisplayProfile;
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PrintingScreen(
        data: Future.value(''),
        bookId: bookTitle,
        documentTitle: bookTitle,
        prebuiltBlocks: blocks,
        activeCommentators: groups
            .map((group) => group.bookTitle)
            .toList(growable: false),
        removeNikud: profile.removeNikud,
        removeTaamim: profile.removeTeamim,
      ),
    );
  }

  Widget _buildSearchFieldRow() {
    return Row(
      children: [
        Expanded(
          child: ValueListenableBuilder<String>(
            valueListenable: _searchQueryNotifier,
            builder: (context, query, _) {
              return ValueListenableBuilder<int>(
                valueListenable: _totalSearchResultsNotifier,
                builder: (context, total, _) {
                  return ValueListenableBuilder<int>(
                    valueListenable: _currentSearchIndexNotifier,
                    builder: (context, currentIndex, _) {
                      return RtlTextField(
                        focusNode: _searchFocusNode,
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'חפש בתוך המפרשים המוצגים...',
                          prefixIcon: const Icon(
                            OtzariaIcons.search_in_the_library_24_regular,
                          ),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (query.isNotEmpty && total > 1) ...[
                                if (currentIndex >= 0)
                                  Text(
                                    '${currentIndex + 1}/$total',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: const Icon(
                                    FluentIcons.chevron_up_24_regular,
                                  ),
                                  iconSize: 20,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 24,
                                    minHeight: 24,
                                  ),
                                  onPressed: currentIndex > 0
                                      ? () {
                                          _currentSearchIndexNotifier.value =
                                              currentIndex - 1;
                                          _scrollToSearchResult();
                                        }
                                      : null,
                                ),
                                IconButton(
                                  icon: const Icon(
                                    FluentIcons.chevron_down_24_regular,
                                  ),
                                  iconSize: 20,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 24,
                                    minHeight: 24,
                                  ),
                                  onPressed: currentIndex < total - 1
                                      ? () {
                                          _currentSearchIndexNotifier.value =
                                              currentIndex + 1;
                                          _scrollToSearchResult();
                                        }
                                      : null,
                                ),
                              ],
                              IconButton(
                                icon: const Icon(
                                  FluentIcons.dismiss_24_regular,
                                ),
                                tooltip: 'סגור חיפוש',
                                onPressed: _clearSearchAndCloseField,
                              ),
                            ],
                          ),
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: AppTokens.borderRadiusAll,
                          ),
                        ),
                        onChanged: (value) {
                          if (_searchQueryNotifier.value != value) {
                            _searchQueryNotifier.value = value;
                            _currentSearchIndexNotifier.value = -1;
                            _totalSearchResultsNotifier.value = 0;
                            _searchResultsPerLink.clear();
                            _pendingCounts.clear();
                            _scheduleSearchCompute();
                          }
                        },
                        onSubmitted: (_) {
                          navigateSearchNext();
                          _searchFocusNode.requestFocus();
                        },
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
        if (widget.onClosePane != null) ...[
          const SizedBox(width: 8),
          _buildClosePaneButton(),
        ],
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    // האזנה לשינויים במיקום הגלילה כדי לשמור את המיקום האחרון
    _itemPositionsListener.itemPositions.addListener(_updateLastScrollIndex);
    widget.selectionSyncController?.addListener(_handleExternalSelectionChange);
    widget.openFilterRequest?.addListener(_handleOpenFilterRequest);
    _lastSeenFilterRequest = widget.openFilterRequest?.value ?? 0;
    widget.openFilterNotifier?.addListener(_onOpenFilterRequest);
    widget.closeFilterNotifier?.addListener(_onCloseFilterRequest);
    _searchFocusNode.addListener(_handleSearchFocusChange);
    widget.typeSelection?.addListener(_onTypeSelectionChanged);
    // חיפוש חיצוני
    widget.externalSearchController?.addListener(_onExternalSearchChanged);
    widget.highlightQueryListenable?.addListener(_onHighlightQueryChanged);
    widget.scrollTargetListenable?.addListener(_onExternalScrollTargetChanged);
    // בקשה שנקבעה לפני שהרשימה נבנתה (הפאנל נפתח בעקבות אותה לחיצה) —
    // בלי הבדיקה הזו היא הייתה אובדת, כי ה-listener מגיב רק לשינוי.
    _onExternalScrollTargetChanged();
    if (widget.externalTotalResultsNotifier != null) {
      _totalSearchResultsNotifier.addListener(() {
        widget.externalTotalResultsNotifier!.value =
            _totalSearchResultsNotifier.value;
      });
    }
    if (widget.externalCurrentIndexNotifier != null) {
      _currentSearchIndexNotifier.addListener(() {
        widget.externalCurrentIndexNotifier!.value =
            _currentSearchIndexNotifier.value;
      });
    }
    // סנכרון מצב הכיווץ הגלובלי לנוטיפייר חיצוני (אם סופק)
    if (widget.externalAllExpandedNotifier != null) {
      widget.externalAllExpandedNotifier!.value = _allExpanded;
      _allExpandedNotifier.addListener(() {
        widget.externalAllExpandedNotifier!.value = _allExpanded;
      });
    }
  }

  @override
  void didUpdateWidget(CommentaryListBase oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectionSyncController != widget.selectionSyncController) {
      oldWidget.selectionSyncController?.removeListener(
        _handleExternalSelectionChange,
      );
      widget.selectionSyncController?.addListener(
        _handleExternalSelectionChange,
      );
    }
    if (oldWidget.openFilterRequest != widget.openFilterRequest) {
      oldWidget.openFilterRequest?.removeListener(_handleOpenFilterRequest);
      widget.openFilterRequest?.addListener(_handleOpenFilterRequest);
      _lastSeenFilterRequest = widget.openFilterRequest?.value ?? 0;
    }
    if (oldWidget.openFilterNotifier != widget.openFilterNotifier) {
      oldWidget.openFilterNotifier?.removeListener(_onOpenFilterRequest);
      widget.openFilterNotifier?.addListener(_onOpenFilterRequest);
    }
    if (oldWidget.closeFilterNotifier != widget.closeFilterNotifier) {
      oldWidget.closeFilterNotifier?.removeListener(_onCloseFilterRequest);
      widget.closeFilterNotifier?.addListener(_onCloseFilterRequest);
    }
    if (oldWidget.highlightQueryListenable != widget.highlightQueryListenable) {
      oldWidget.highlightQueryListenable?.removeListener(
        _onHighlightQueryChanged,
      );
      widget.highlightQueryListenable?.addListener(_onHighlightQueryChanged);
    }
    if (oldWidget.scrollTargetListenable != widget.scrollTargetListenable) {
      oldWidget.scrollTargetListenable?.removeListener(
        _onExternalScrollTargetChanged,
      );
      widget.scrollTargetListenable?.addListener(
        _onExternalScrollTargetChanged,
      );
      _onExternalScrollTargetChanged();
    }
    if (oldWidget.typeSelection != widget.typeSelection) {
      oldWidget.typeSelection?.removeListener(_onTypeSelectionChanged);
      widget.typeSelection?.addListener(_onTypeSelectionChanged);
    }
    // סגירה אוטומטית של מסך הסינון כאשר המפרשים עוברים מריק לא-ריק
    // (קורה כאשר המשתמש בוחר "כל המפרשים" מהתפריט הימני)
    if (_showCommentatorsFilter &&
        _filterWasAutoOpened &&
        !_userInteractedWithFilter &&
        (oldWidget.selectedCommentatorsOverride?.isEmpty ?? true) &&
        (widget.selectedCommentatorsOverride?.isNotEmpty ?? false)) {
      setState(() {
        _showCommentatorsFilter = false;
        _filterWasAutoOpened = false;
      });
    }
  }

  /// מציג את הרשימה מתחילתה. `jumpTo` ולא גלילה מונפשת: התוכן שמתחתיה מוחלף,
  /// ואנימציה על תוכן חדש נראית כתקלה. הקפיצה נדחית לסוף הפריים כדי שאפשר
  /// יהיה לקרוא לזה גם מתוך build.
  ///
  /// בקשת עוגן ממתינה גוברת: לחיצה על אות-עוגן שולחת קודם
  /// `UpdateSelectedIndex(sourceLine)`, ולכן *אותה לחיצה* נחשבת גם מעבר קטע.
  /// האיפוס מתוזמן מה-build שנגרם ממנה — כלומר **אחרי** הגלילה לעוגן — והיה
  /// מוחק אותה ב-`jumpTo(0)`. בממשק זה נראה כאילו נפתח הקטע הראשון של המפרש,
  /// שהוא גם היעד של האות הראשונה; לכן הבאג התחזה ל"רק א עובד".
  void scrollToTop() {
    // המיקום המשוחזר לבנייה הבאה מתאפס בכל מקרה — היסט הקטע הקודם אינו
    // מתאים לתוכן החדש, ובקשת העוגן ממילא תמקם מחדש.
    _lastScrollIndex = 0;
    if (!shouldResetScrollForSectionChange(
      hasPendingAnchorScroll: _hasPendingAnchorScroll,
    )) {
      return;
    }
    if (_scrollToTopScheduled) return;
    _scrollToTopScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToTopScheduled = false;
      if (!mounted || !_itemScrollController.isAttached) return;
      // גם בסדר ההפוך: הקפיצה תוזמנה, ורק אז הגיעה בקשת העוגן.
      if (!shouldResetScrollForSectionChange(
        hasPendingAnchorScroll: _hasPendingAnchorScroll,
      )) {
        return;
      }
      _itemScrollController.jumpTo(index: 0);
    });
  }

  /// האם יש בקשת גלילה לעוגן שטרם הושלמה — ממתינה או באמצע לולאת הניסיונות.
  bool get _hasPendingAnchorScroll =>
      _pendingScrollTarget != null || _commentatorScrollRunning;

  /// מעבר לקטע מקור אחר מציג את המפרשים מתחילתם — היסט הגלילה של הקטע הקודם
  /// אינו מתאים לתוכן החדש (issue #846).
  void _syncSectionScroll(List<int> currentIndexes) {
    final previous = _sectionIndexes;
    if (previous != null && listEquals(previous, currentIndexes)) return;
    _sectionIndexes = List<int>.unmodifiable(currentIndexes);
    if (previous == null) return;
    if (!isCommentarySectionChange(
      previous: previous,
      current: currentIndexes,
    )) {
      return;
    }
    // מעבר הקטע שנגרם מלחיצת העוגן עצמה אינו סיבה לאפס: `UpdateSelectedIndex`
    // מגיע דרך ה-bloc ולכן נוחת *אחרי* שהגלילה כבר הסתיימה, כשאין עוד בקשה
    // ממתינה לחסום אותו. בלי החריג הזה כל לחיצה נגמרה ב-jumpTo(0) מאוחר.
    if (currentIndexes.isNotEmpty &&
        currentIndexes.first == _anchorScrollSectionLine) {
      return;
    }
    // מעבר לקטע אחר מבטל את החריג: מכאן ואילך איפוס רגיל.
    _anchorScrollSectionLine = null;
    scrollToTop();
  }

  /// בקשת גלילה חיצונית (מסלול "מפרשים בצד"). מזהה הבקשה מונע טיפול כפול
  /// באותה לחיצה — ה-listener ובדיקת ה-initState/didUpdateWidget עלולים
  /// שניהם לראות את אותו ערך.
  void _onExternalScrollTargetChanged() {
    if (!mounted) return;
    final request = widget.scrollTargetListenable?.value;
    if (request == null || request.requestId <= _lastHandledScrollRequestId) {
      return;
    }
    _lastHandledScrollRequestId = request.requestId;
    scrollToCommentator(
      request.title,
      linkKey: request.linkKey,
      sourceLine: request.sourceLine,
    );
  }

  /// גולל אל המפרש בעל [title], ואם [linkKey] מסופק — אל הקטע המדויק שלו.
  ///
  /// נקרא משני מסלולי העוגן: `_CommentaryCard` (מפרשים מתחת לטקסט) ו-
  /// [CommentaryListBase.scrollTargetListenable] (מפרשים בצד).
  void scrollToCommentator(String title, {String? linkKey, int? sourceLine}) {
    _pendingScrollTarget = (title: title, linkKey: linkKey);
    _commentatorScrollGeneration++;
    if (sourceLine != null) _anchorScrollSectionLine = sourceLine;
    _schedulePendingCommentatorScroll();
  }

  void _schedulePendingCommentatorScroll() {
    if (_commentatorScrollScheduled) return;
    _commentatorScrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _commentatorScrollScheduled = false;
      unawaited(_runPendingCommentatorScroll());
    });
    // addPostFrameCallback אינו מבקש פריים בעצמו. בפועל תמיד הגיע פריים
    // (הלחיצה על העוגן משנה את הבחירה), אבל ההסתמכות הזו שקטה ושבירה —
    // מסלול שלא יגרור פריים היה מותיר את הבקשה תלויה בלי שום סימן.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// מספר ניסיונות הגלילה עד ויתור. הניסיון הראשון נצרך בדרך כלל לייצוב
  /// האינדקס (ראו הדרישה לשתי פתירות זהות), ולכן התקרה נדיבה.
  static const int _maxCommentatorScrollAttempts = 6;

  /// המתנה אחרי כל ניסיון, לפני מדידת המיקום שהתקבל.
  static const Duration _commentatorScrollSettle = Duration(milliseconds: 220);

  /// היעד: ראש אזור הגלילה.
  static const double _commentatorScrollAlignment = 0.0;

  /// סטייה נסבלת מ-[_commentatorScrollAlignment], כשבר מגובה אזור הגלילה.
  static const double _commentatorScrollTolerance = 0.02;

  /// גולל אל היעד הממתין, מודד, וחוזר עד שהוא באמת שם.
  ///
  /// ניסיון יחיד אינו מספיק: `ScrollablePositionedList` גולל לפריט שכבר בנוי
  /// דרך `animateTo` לאופסט **פיקסלים** שחושב מהפריסה שברגע ההתחלה, וגובהו
  /// של כל קטע מפרש נקבע רק אחרי ש-`link.content` נפתר ו-`CommentaryContent`
  /// מחליף את שלד הטעינה בטקסט. ככל שיש יותר מפרשים על הקטע כך גדל הפער
  /// שנפתח מעל היעד תוך כדי האנימציה — ולכן הגלילה נעצרה *לפני* המפרש
  /// המקושר. כאן מודדים את המיקום שהתקבל וגוללים שוב עד שהוא מתייצב.
  Future<void> _runPendingCommentatorScroll() async {
    // רץ יחיד. הרשימה מתזמנת בנייה מחדש גם באמצע ריצה (הקבוצות נבנות
    // אסינכרונית), ושתי לולאות במקביל היו מריצות שתי אנימציות גלילה זו
    // מול זו על אותו controller.
    if (_commentatorScrollRunning) {
      return;
    }
    _commentatorScrollRunning = true;
    try {
      // בקשה חדשה שנרשמה תוך כדי ריצה פותחת סבב חדש במקום להיבלע.
      for (var generation = -1; generation != _commentatorScrollGeneration;) {
        generation = _commentatorScrollGeneration;
        await _runCommentatorScrollAttempts(generation);
        if (!mounted) return;
      }
    } finally {
      _commentatorScrollRunning = false;
    }
  }

  Future<void> _runCommentatorScrollAttempts(int generation) async {
    var previousEdge = double.nan;
    int? lastResolvedIndex;

    for (var attempt = 0; attempt < _maxCommentatorScrollAttempts; attempt++) {
      if (!mounted || generation != _commentatorScrollGeneration) return;
      final target = _pendingScrollTarget;
      if (target == null) return;
      // הבקר מתנתק לרגע כשהרשימה נבנית מחדש — למשל כששינוי סדר המפרשים
      // מחליף את ה-key של SPL. יציאה כאן הייתה מאבדת את הבקשה בשקט, כי
      // הסבב הנוכחי מסתיים ואיש אינו מתזמן מחדש.
      if (!_itemScrollController.isAttached) {
        await Future<void>.delayed(_commentatorScrollSettle);
        continue;
      }

      // קבוצה מכווצת אינה פולטת פריטי קטע כלל, ולכן מפתח הקטע לא יימצא
      // לפני שהיא נפתחת. הפתיחה נכנסת לתוקף רק בפריים הבא.
      if (_expansionStates[target.title] == false) {
        setState(() => _expansionStates[target.title] = true);
        _schedulePendingCommentatorScroll();
        return;
      }

      // הרשימה טרם נמדדה — הפריים הראשון שלה. גלילה לפני שיש פריסה אינה
      // יכולה להצליח, ו-ScrollablePositionedList אף נופל עליה בפריסה
      // בלתי-חסומה. קורה כשהפאנל נפתח באותה לחיצה שיצרה את הבקשה.
      if (_itemPositionsListener.itemPositions.value.isEmpty) {
        await Future<void>.delayed(_commentatorScrollSettle);
        continue;
      }

      // מפתח הקטע טרם מופיע במיפוי: הרשימה עדיין מציגה את הקטע הקודם
      // ומיפויי האינדקסים שלה מיושנים. גלילה עכשיו הייתה קופצת לאינדקס של
      // הקטע הקודם — ובנוסף מפילה את SPL, שנדרש לפרוס פריט בזמן שהתוכן
      // מתחלף. ממתינים לפריים הבא במקום. נפילה-אחורה לכותרת נשמרת לניסיון
      // האחרון, שאז זה כבר באמת מפרש שאינו ברשימה.
      final isLastAttempt = attempt == _maxCommentatorScrollAttempts - 1;
      final index = _resolveCommentatorScrollIndex(
        target,
        allowHeaderFallback: target.linkKey == null || isLastAttempt,
      );
      if (index == null) {
        // מפה ריקה = הקבוצות עדיין נבנות (Future). בנייתן מתזמנת אותנו
        // מחדש, ולכן משאירים את היעד ממתין. מפה מלאה בלי המפרש בניסיון
        // האחרון = הוא אינו ברשימה כלל (סונן/הוסתר), ואין למה לחכות.
        if (_groupHeaderFlatIndex.isEmpty || !isLastAttempt) {
          await Future<void>.delayed(_commentatorScrollSettle);
          continue;
        }
        _pendingScrollTarget = null;
        return;
      }

      // הלחיצה על העוגן גם מסדרת מחדש את הרשימה (המפרש שנלחץ עולה לראש),
      // ולכן האינדקס שנפתר מיד אחריה עדיין שייך לסדר הישן. גלילה אליו לא
      // רק מיותרת — היא רצה בזמן שהעץ נבנה מחדש, ומייצרת שגיאות פריסה
      // אמיתיות (GlobalKey כפול, RenderBox ללא פריסה). לכן דורשים שתי
      // פתירות רצופות שמסכימות לפני שגוללים בפועל.
      // בניסיון האחרון גוללים בלי לדרוש יציבות — אחרת הדרישה בולעת את
      // ההזדמנות האחרונה, והנפילה-אחורה לכותרת לא מגיעה לגלול כלל.
      if (index != lastResolvedIndex && !isLastAttempt) {
        lastResolvedIndex = index;
        await Future<void>.delayed(_commentatorScrollSettle);
        continue;
      }

      // `jumpTo` ולא `scrollTo` מונפש, משלוש סיבות שכולן נצפו בשדה:
      //
      // 1. כשהיעד אינו בנוי, `scrollTo` בונה **רשימה שנייה** למעבר
      //    המונפש. הרשימה מקצה GlobalKey לכל קטע (`_itemKeys`), ואותו
      //    פריט שנבנה בשתי הרשימות בו-זמנית מייצר `Duplicate GlobalKey`
      //    ואחריו מפל שגיאות פריסה.
      // 2. ה-Future של אותו מעבר אינו מושלם לעולם אם הרשימה נבנית מחדש
      //    באמצעו — וזה בדיוק מה שקורה כשהמפרש שנלחץ עולה לראש.
      // 3. המעבר המונפש נעשה ב-`animateTo` לאופסט **פיקסלים** שחושב מראש,
      //    ולכן גדילת קטעים מעל היעד (תוכן שנטען) משאירה אותו קצר.
      //    `jumpTo` עוגן-לפי-אינדקס חסין לכל אלה.
      //
      // גם `scrollToTop` כאן כבר משתמש ב-`jumpTo` מאותו טעם — אנימציה על
      // תוכן שמתחלף נראית כתקלה.
      _itemScrollController.jumpTo(
        index: index,
        alignment: _commentatorScrollAlignment,
      );
      await Future<void>.delayed(_commentatorScrollSettle);
      if (!mounted || generation != _commentatorScrollGeneration) {
        return;
      }

      final edge = _leadingEdgeOfItem(index);
      if (edge == null) continue; // הפריט לא דווח עדיין — ניסיון נוסף
      if ((edge - _commentatorScrollAlignment).abs() <=
          _commentatorScrollTolerance) {
        break;
      }
      // אותו מיקום פעמיים = הרשימה בקצה ואינה יכולה להתקדם. ללא הבלם הזה
      // קטע אחרון קצר היה מייצר חמישה ניסיונות עקרים.
      if (!previousEdge.isNaN && (edge - previousEdge).abs() < 0.001) break;
      previousEdge = edge;
    }

    if (generation == _commentatorScrollGeneration) _pendingScrollTarget = null;
  }

  /// האינדקס ברשימה השטוחה שאליו יש לגלול.
  ///
  /// הקטע המדויק גובר על כותרת הקבוצה — זה מה שמבדיל בין שני קטעים של אותו
  /// מפרש על אותה שורה. יוצא מן הכלל: הקטע הראשון בקבוצה, שעבורו גוללים
  /// לכותרת כדי ששם המפרש יישאר גלוי מעל הטקסט.
  ///
  /// [allowHeaderFallback] — כשכבוי, מפתח קטע שאינו במיפוי מחזיר null במקום
  /// את הכותרת. הקורא ממתין אז לרשימה שתתעדכן, במקום לגלול לכותרת של
  /// הקטע — שהיא בדיוק הקטע הראשון של המפרש, כלומר הבאג המקורי.
  int? _resolveCommentatorScrollIndex(
    ({String title, String? linkKey}) target, {
    bool allowHeaderFallback = true,
  }) {
    final headerIndex = _groupHeaderFlatIndex[target.title];
    final linkKey = target.linkKey;
    final linkIndex = linkKey == null ? null : _linkFlatIndex[linkKey];
    if (linkIndex == null) return allowHeaderFallback ? headerIndex : null;
    if (headerIndex != null && linkIndex == headerIndex + 1) return headerIndex;
    return linkIndex;
  }

  /// הקצה העליון של הפריט [index] כשבר מגובה אזור הגלילה, או null אם הפריט
  /// אינו בנוי כלל. ערך מחוץ ל-[0,1] פירושו שהפריט מחוץ למסך — וזה בדיוק
  /// המצב שהלולאה מתקנת.
  double? _leadingEdgeOfItem(int index) {
    for (final position in _itemPositionsListener.itemPositions.value) {
      if (position.index == index) return position.itemLeadingEdge;
    }
    return null;
  }

  void _updateLastScrollIndex() {
    // הרשימה מדווחת גם פריטים שנבנו מחוץ למסך (cache) — מסננים לנראים בלבד.
    final positions = _itemPositionsListener.itemPositions.value;
    ItemPosition? firstVisible;
    for (final p in positions) {
      if (p.itemTrailingEdge <= 0 || p.itemLeadingEdge >= 1) continue;
      if (firstVisible == null || p.index < firstVisible.index) {
        firstVisible = p;
      }
    }
    if (firstVisible != null) {
      _lastScrollIndex = firstVisible.index;
    }
  }

  /// גולל כדי שתוכן קבוצה שזה עתה נפתחה ייכנס לתצוגה. ברשימה השטוחה הכותרת
  /// היא פריט קטן שאינו יודע את גובה התוכן שנפתח מתחתיו, לכן גוללים את
  /// הכותרת לראש רק כשהיא בחצי התחתון (שם לתוכן שנפתח אין מקום נראה).
  void _ensureExpandedGroupVisible(int headerIndex) {
    if (!_itemScrollController.isAttached) return;
    ItemPosition? pos;
    for (final p in _itemPositionsListener.itemPositions.value) {
      if (p.index == headerIndex) {
        pos = p;
        break;
      }
    }
    if (pos == null || pos.itemLeadingEdge <= 0.5) return;
    _itemScrollController.scrollTo(
      index: headerIndex,
      alignment: 0.05,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _openCommentatorsFilter() {
    setState(() {
      _showCommentatorsFilter = true;
      _filterWasAutoOpened = false;
    });
  }

  void _handleOpenFilterRequest() {
    if (!mounted) return;
    final newValue = widget.openFilterRequest?.value ?? 0;
    if (newValue <= _lastSeenFilterRequest) return;
    _lastSeenFilterRequest = newValue;
    _openCommentatorsFilter();
  }

  void _closeCommentatorsFilter() {
    setState(() {
      _showCommentatorsFilter = false;
      _userInteractedWithFilter = false;
    });
  }

  void _onOpenFilterRequest() {
    // אם ההורה ביקש להפנות בקשות פתיחה אליו (למשל לפתיחת לשונית בסרגל הצד),
    // קוראים לקולבק במקום לפתוח פופ-אפ פנימי.
    if (widget.onFilterOpenRequested != null) {
      widget.onFilterOpenRequested!();
      return;
    }
    setState(() {
      _showCommentatorsFilter = true;
      _userInteractedWithFilter = false;
    });
  }

  void _onCloseFilterRequest() {
    setState(() {
      _showCommentatorsFilter = false;
      _userInteractedWithFilter = false;
    });
  }

  @override
  void dispose() {
    _searchUpdateDebounce?.cancel();
    _searchComputeDebounce?.cancel();
    _itemPositionsListener.itemPositions.removeListener(_updateLastScrollIndex);
    widget.selectionSyncController?.clear(_selectionOwner);
    widget.selectionSyncController?.removeListener(
      _handleExternalSelectionChange,
    );
    widget.openFilterRequest?.removeListener(_handleOpenFilterRequest);
    widget.openFilterNotifier?.removeListener(_onOpenFilterRequest);
    widget.closeFilterNotifier?.removeListener(_onCloseFilterRequest);
    widget.externalSearchController?.removeListener(_onExternalSearchChanged);
    widget.highlightQueryListenable?.removeListener(_onHighlightQueryChanged);
    widget.scrollTargetListenable?.removeListener(
      _onExternalScrollTargetChanged,
    );
    widget.typeSelection?.removeListener(_onTypeSelectionChanged);
    _searchFocusNode.removeListener(_handleSearchFocusChange);
    _searchController.dispose();
    _savedSelectedText.dispose();
    _lastSelectedLink.dispose();
    _searchQueryNotifier.dispose();
    _currentSearchIndexNotifier.dispose();
    _totalSearchResultsNotifier.dispose();
    _allExpandedNotifier.dispose();
    _focusNode.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _handleExternalSelectionChange() {
    final controller = widget.selectionSyncController;
    if (controller == null || !mounted) return;
    final shouldClear = shouldClearSelectionOnExternalChange(
      activeOwner: controller.activeOwner,
      selfOwner: _selectionOwner,
      hasOwnSelection: _savedSelectedText.value != null,
    );
    if (!shouldClear) return;
    // ניקוי ישיר ולא החלפת מפתח: החלפה הייתה טוענת מחדש את כל המפרשים
    // ומאבדת את מיקום הגלילה בהם.
    _selectionAreaKey.currentState?.selectableRegion.clearSelection();
    _savedSelectedText.value = null;
    _lastSelectedLink.value = null;
  }

  Future<void> _scrollToSearchResult() async {
    if (_totalSearchResultsNotifier.value == 0 ||
        _orderedLinks.isEmpty ||
        !_itemScrollController.isAttached) {
      return;
    }

    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded) {
      return;
    }

    int cumulativeIndex = 0;
    Link? targetLink;

    // 1. מוצא את ה-link שמכיל את תוצאת החיפוש הנוכחית
    for (final link in _orderedLinks) {
      final linkKey = _getLinkKey(link);
      final itemResults = _searchResultsPerLink[linkKey] ?? 0;
      if (_currentSearchIndexNotifier.value < cumulativeIndex + itemResults) {
        targetLink = link;
        break;
      }
      cumulativeIndex += itemResults;
    }

    if (targetLink == null) {
      return;
    }

    // 2. מבטיח שהקבוצה של ה-link פתוחה (בקבוצה מכווצת הקטעים אינם ברשימה)
    final groupKey = utils.getTitleFromPath(targetLink.path2);

    final bool isCurrentlyExpanded = _expansionStates[groupKey] ?? true;

    // אם צריך לפתוח, פותח ומחכה לאנימציה
    if (!isCurrentlyExpanded) {
      setState(() {
        _expansionStates[groupKey] = true;
      });
    }

    // 4. ביצוע הגלילה בתוך Callback
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      // המתנה לסיום אנימציית הפתיחה אם הייתה
      if (!isCurrentlyExpanded) {
        await Future.delayed(const Duration(milliseconds: 200));
        if (!mounted) return;
      }

      final linkKey = _getLinkKey(targetLink!);
      final itemKey = _itemKeys[linkKey];
      final BuildContext? itemContext = itemKey?.currentContext;

      // בודק אם הפריט כבר בעץ הרינדור (לא נדרשת גלילה גסה להכניסו לזיכרון)
      final bool itemInRenderTree =
          itemContext != null &&
          itemContext.mounted &&
          itemContext.findRenderObject() is RenderBox;

      // שלב א': גלילה גסה לפריט השטוח של הקטע – רק אם הוא לא בעץ הרינדור
      if (!itemInRenderTree) {
        final flatIndex = _linkFlatIndex[linkKey];
        if (flatIndex != null && _itemScrollController.isAttached) {
          _itemScrollController.scrollTo(
            index: flatIndex,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            alignment: 0.05,
          );
        }
        await Future.delayed(const Duration(milliseconds: 350));
        if (!mounted) return;
      }

      // שלב ב': גלילה עדינה לפריט הספציפי
      final BuildContext? ctx = itemKey?.currentContext;
      if (ctx != null && ctx.mounted) {
        try {
          final RenderObject? itemRenderObj = ctx.findRenderObject();
          if (itemRenderObj is! RenderBox) return;
          final RenderBox itemBox = itemRenderObj;

          final ScrollableState scrollable = Scrollable.of(ctx);
          if (!scrollable.mounted) return;

          final RenderObject? viewportRenderObj = scrollable.context
              .findRenderObject();
          if (viewportRenderObj is! RenderBox) return;
          final RenderBox viewportBox = viewportRenderObj;

          final Offset itemOffset = itemBox.localToGlobal(
            Offset.zero,
            ancestor: viewportBox,
          );

          // מביא את הפריט ל-10% מראש הרשימה
          final double targetY = viewportBox.size.height * 0.1;
          final double scrollDelta = itemOffset.dy - targetY;

          if (scrollDelta.abs() > 10) {
            scrollController.animateScroll(
              offset: scrollDelta,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
            );
          }
        } catch (e) {
          debugPrint('Error during micro-scrolling: $e');
        }
      }
    });
  }

  void _scheduleSearchCompute() {
    _searchComputeDebounce?.cancel();
    // כשאין קישורים אין מה לחשב — טעינתם תפעיל תזמון מחדש (לפי חתימה).
    if (_orderedLinks.isEmpty) return;
    _searchComputeDebounce = Timer(
      const Duration(milliseconds: 250),
      _computeSearchCounts,
    );
  }

  /// עובר על כל הקישורים ומזין את משפך העדכון של ספירות/קטעי חיפוש, במקביל
  /// לדיווח (הזהה) מה-widgets שנבנו בפועל.
  Future<void> _computeSearchCounts() async {
    if (!mounted) return;
    final internalQuery = widget.showSearch ? _searchQueryNotifier.value : '';
    final query = internalQuery.isNotEmpty
        ? internalQuery
        : (widget.highlightQueryListenable?.value ?? '');
    final links = List<Link>.from(_orderedLinks);
    if (query.isEmpty || links.isEmpty) return;
    final gen = ++_searchComputeGen;

    final blocState = context.read<TextBookBloc>().state;
    final profile = blocState is TextBookLoaded
        ? blocState.commentaryDisplayProfile
        : TextDisplayProfile.defaults;
    final wantSnippets = widget.externalSearchSnippetsNotifier != null;

    for (final link in links) {
      String data;
      try {
        data = await link.content;
      } catch (_) {
        data = '';
      }
      if (!mounted || gen != _searchComputeGen) return;
      final count = countCommentarySearchMatches(
        content: data,
        query: query,
        displayProfile: profile,
        // התוכן מרונדר ב-CommentaryContent עם partialWordHighlight: true.
        partialWordMatch: true,
      );
      _updateSearchResultsCount(link, count);
      if (wantSnippets && count > 0) {
        _updateSearchSnippets(link, [
          buildCommentarySearchSnippet(
            content: data,
            query: query,
            displayProfile: profile,
          ),
        ]);
      }
    }
  }

  void _updateSearchResultsCount(Link link, int count) {
    if (!mounted) return;

    final key = _getLinkKey(link);
    // שמור את ה-path2 לצורך קיבוץ לפי מפרש
    _linkKeyToPath[key] = link.path2;
    // אם הכמות לא השתנתה, אין צורך לעשות כלום
    if (_searchResultsPerLink[key] == count) return;

    _pendingCounts[key] = count;

    // אם כבר יש טיימר פעיל, רק עדכנו את הרשימה הממתינה
    if (_searchUpdateDebounce?.isActive ?? false) return;

    // הפעלת הטיימר
    _searchUpdateDebounce = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      _searchResultsPerLink.addAll(_pendingCounts);
      _pendingCounts.clear();
      _totalSearchResultsNotifier.value = _searchResultsPerLink.values.fold(
        0,
        (sum, count) => sum + count,
      );

      // עדכון נוטיפייר חיצוני לתוצאות לפי מפרש
      if (widget.externalSearchResultsByPathNotifier != null) {
        final byPath = <String, int>{};
        for (final entry in _searchResultsPerLink.entries) {
          final path = _linkKeyToPath[entry.key] ?? '';
          if (path.isNotEmpty && entry.value > 0) {
            byPath[path] = (byPath[path] ?? 0) + entry.value;
          }
        }
        widget.externalSearchResultsByPathNotifier!.value = byPath;
      }

      // עדכון נוטיפייר קטעי החיפוש (snippets)
      _scheduleSnippetsNotifierRebuild();

      // תיקון אינדקס אם חרגנו מהגבולות
      if (_currentSearchIndexNotifier.value >=
              _totalSearchResultsNotifier.value &&
          _totalSearchResultsNotifier.value > 0) {
        _currentSearchIndexNotifier.value = 0;
      }
    });
  }

  void _updateSearchSnippets(Link link, List<String> snippets) {
    if (!mounted) return;
    final key = _getLinkKey(link);
    _searchSnippetsPerLink[key] = snippets;
    _scheduleSnippetsNotifierRebuild();
  }

  void _rebuildSnippetsNotifier() {
    if (widget.externalSearchSnippetsNotifier == null) return;
    final List<CommentarySearchSnippet> result = [];
    int globalIndex = 0;
    for (final link in _orderedLinks) {
      final key = _getLinkKey(link);
      final count = _searchResultsPerLink[key] ?? 0;
      final snippets = _searchSnippetsPerLink[key] ?? [];
      for (int i = 0; i < snippets.length; i++) {
        result.add(
          CommentarySearchSnippet(
            path: link.path2,
            snippet: snippets[i],
            globalIndex: globalIndex,
          ),
        );
      }
      globalIndex += count;
    }
    widget.externalSearchSnippetsNotifier!.value = result;
  }

  void _scheduleSnippetsNotifierRebuild() {
    if (widget.externalSearchSnippetsNotifier == null ||
        _snippetsRebuildScheduled ||
        !mounted) {
      return;
    }
    _snippetsRebuildScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _snippetsRebuildScheduled = false;
      if (!mounted) return;
      _rebuildSnippetsNotifier();
    });
  }

  void _updateGlobalExpansionState() {
    if (_expansionStates.isEmpty) return;

    // בודק אם כל המפרשים פתוחים
    final allExpanded = _expansionStates.values.every((state) => state == true);
    // בודק אם כל המפרשים סגורים
    final allCollapsed = _expansionStates.values.every(
      (state) => state == false,
    );

    // מעדכן את המצב הגלובלי רק אם כולם באותו מצב
    if (allExpanded) {
      _allExpanded = true;
    } else if (allCollapsed) {
      _allExpanded = false;
    }
    // אם יש מצב מעורב, לא משנים את _allExpanded
  }

  Widget _buildGroupHeader(CommentaryGroup group) {
    return _CommentaryGroupHeader(
      key: ValueKey('h:${group.bookTitle}'),
      bookTitle: group.bookTitle,
      fontSize: widget.fontSize,
      isExpanded: _expansionStates[group.bookTitle] ?? _allExpanded,
      onTap: () => _toggleGroupExpansion(group),
    );
  }

  // מטמון כתובות שורות המקור להכרעת הסתרת כותרת (issue #896); מתאפס עם ה-TOC.
  Object? _sourceRefTocIdentity;
  final Map<int, String> _sourceRefByIndex = {};

  String _sourceRefFor(TextBookLoaded state, int index1) {
    if (!identical(_sourceRefTocIdentity, state.tableOfContents)) {
      _sourceRefTocIdentity = state.tableOfContents;
      _sourceRefByIndex.clear();
    }
    return _sourceRefByIndex.putIfAbsent(
      index1,
      () => refFromTocList(index1 - 1, state.tableOfContents),
    );
  }

  /// האם להציג את כותרת המקור של מקטע: מוסתרת רק כשכל מקטעי הקבוצה מאותה
  /// שורת מקור והיעד הוא המקום הנקרא כעת — אחרת הכותרת נושאת מידע (issue #896).
  bool _shouldShowItemTitle(
    CommentaryGroup group,
    TextBookLoaded state,
    String displayTitle,
  ) {
    if (!groupSharesSingleSource(group.links)) return true;
    return !commentaryTitleMatchesReadingLocation(
      displayTitle: displayTitle,
      targetBookTitle: group.bookTitle,
      sourceBookTitle: state.book.title,
      sourceRef: _sourceRefFor(state, group.links.first.index1),
    );
  }

  static TextDisplayProfile _commentaryCopyProfile(TextBookLoaded state) =>
      state.displayProfile(
        target: TextTarget.commentary,
        channel: TextChannel.copy,
      );

  Widget _buildLinkItem(
    CommentaryGroup group,
    Link link,
    TextBookLoaded state,
  ) {
    return _CommentaryLinkItem(
      key: ValueKey(_getLinkKey(link)),
      link: link,
      fontSize: widget.fontSize,
      openBookCallback: widget.openBookCallback,
      displayProfile: state.commentaryDisplayProfile,
      copyDisplayProfile: _commentaryCopyProfile(state),
      showSearch: widget.showSearch,
      searchQueryListenable: _searchQueryNotifier,
      currentSearchIndexListenable: _currentSearchIndexNotifier,
      totalSearchResultsListenable: _totalSearchResultsNotifier,
      getItemSearchIndex: _getItemSearchIndex,
      updateSearchResultsCount: _updateSearchResultsCount,
      updateSearchSnippets: widget.externalSearchSnippetsNotifier != null
          ? _updateSearchSnippets
          : null,
      highlightQueryListenable: widget.highlightQueryListenable,
      itemKeys: _itemKeys,
      getLinkKey: _getLinkKey,
      savedSelectedTextListenable: _savedSelectedText,
      lastSelectedLinkListenable: _lastSelectedLink,
      // לחיצת עכבר על מפרש מסמנת אותו כיעד הייחוס להעתקת מקלדת (Ctrl+C),
      // כי ל-SelectionArea היחיד אין מידע על המפרש הספציפי שבו הבחירה.
      onLinkPointerDown: (link) => _lastSelectedLink.value = link,
      // מטמון הטקסט/הכותרת המרונדרים לכל מפרש מוצג — לשחזור מעברי שורה בהעתקה.
      onLinkRendered: (link, text) =>
          _renderedTextByKey[_getLinkKey(link)] = text,
      onLinkTitleRendered: (link, title) =>
          _renderedTitleByKey[_getLinkKey(link)] = title
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim(),
      onOpenPersonalNote: widget.onOpenPersonalNote,
      shouldShowItemTitle: (title) => _shouldShowItemTitle(group, state, title),
      personalNotes: _personalNotesForGroup(group),
      onNoteSaved: () => _refreshGroupPersonalNotes(group.bookTitle),
      restoreLineBreaks: _restoreLineBreaks,
    );
  }

  /// טיפול בשינוי בחירה ב-SelectionArea היחיד שעוטף את כל רשימת המפרשים
  /// (כשהרשימה אינה מקוננת בתוך SelectionArea חיצוני). מזין את הטקסט הנבחר
  /// לצורך העתקה ומסנכרן בעלות בחירה מול אזורים אחרים במסך.
  void _onListSelectionChanged(String? text) {
    // עדכון מעקב כיוון הגרירה (משמש את RtlSelectionShortcuts לבחירת הקצה).
    trackRtlSelection(text);
    // שינוי בחירה זמני בזמן priming — לא לעבד (שמירת טקסט/סנכרון).
    if (rtlSelectionPriming) return;
    if (text != null && text.trim().isNotEmpty) {
      _savedSelectedText.value = text;
      widget.selectionSyncController?.activate(
        _selectionOwner,
        selectionText: _restoreLineBreaks(text),
        selectionLink: _selectionSpansMultipleItems()
            ? null
            : _lastSelectedLink.value,
      );
    } else {
      _savedSelectedText.value = null;
      _lastSelectedLink.value = null;
      widget.selectionSyncController?.clear(_selectionOwner);
    }
  }

  /// האם הבחירה הנוכחית חוצה יותר מפריט מפרש אחד (לפי מיקום שני קצותיה).
  /// משמש כדי לא לייחס כותרת מקור (copyWithHeaders) למפרש בודד בהעתקת מקלדת
  /// כשהטקסט הנבחר בא מכמה מפרשים. נכשל "בטוח" (false) כשלא ניתן לקבוע.
  bool _selectionSpansMultipleItems() {
    SelectableRegionState? sa;
    for (final k in _itemKeys.values) {
      sa = k.currentContext?.findAncestorStateOfType<SelectableRegionState>();
      if (sa != null) break;
    }
    final saRender = sa?.context.findRenderObject();
    if (saRender is! RenderBox) return false;
    final List<TextSelectionPoint> eps;
    try {
      eps = sa!.selectionEndpoints;
    } catch (_) {
      return false;
    }
    if (eps.length < 2) return false;
    final p1 = saRender.localToGlobal(eps.first.point);
    final p2 = saRender.localToGlobal(eps.last.point);
    String? k1;
    String? k2;
    for (final entry in _itemKeys.entries) {
      final box = entry.value.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      if (rect.contains(p1)) k1 = entry.key;
      if (rect.contains(p2)) k2 = entry.key;
    }
    return k1 != null && k2 != null && k1 != k2;
  }

  /// משחזר מעברי שורה בטקסט נבחר רב-שורתי (Flutter מחזיר טקסט שטוח), לפי הטקסט
  /// המרונדר המוטמן של המפרשים המוצגים. אם לא נמצא — מחזיר את הטקסט כמות שהוא.
  String? _restoreLineBreaks(String? flat) {
    if (flat == null || flat.isEmpty || flat.contains('\n')) return flat;
    // סדר התצוגה לכל מפרש: כותרת (displayReference) ואז התוכן.
    final lines = <String>[];
    for (final link in _orderedLinks) {
      final key = _getLinkKey(link);
      final title = _renderedTitleByKey[key];
      if (title != null && title.isNotEmpty) lines.add(title);
      final content = _renderedTextByKey[key];
      if (content != null && content.isNotEmpty) lines.add(content);
    }
    if (lines.isEmpty) return flat;
    return restoreSelectedTextLineBreaks(
      selectedText: flat,
      visibleLines: lines,
    );
  }

  /// מגביל את רוחב הרשימה ל-[CommentaryListBase.contentMaxWidth]. יישור לראש
  /// ולא מרכוז — אחרת רשימה מכווצת (shrinkWrap) הייתה מתמרכזת אנכית.
  Widget _constrainToContentWidth(Widget list) {
    final maxWidth = widget.contentMaxWidth;
    if (maxWidth == null || maxWidth <= 0) return list;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: list,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return TextBookStateBuilder(
      buildWhen: (previous, current) {
        // מבטיח בניה מחדש רק כשיש שינוי בנתונים שמשפיעים על תצוגת המפרשים
        if (previous is! TextBookLoaded || current is! TextBookLoaded) {
          return true;
        }
        return !listEquals(
              previous.activeCommentators,
              current.activeCommentators,
            ) ||
            !listEquals(
              previous.availableCommentators,
              current.availableCommentators,
            ) ||
            previous.links != current.links || // השוואת רפרנס לביצועים
            !listEquals(previous.visibleIndices, current.visibleIndices) ||
            previous.selectedIndex != current.selectedIndex ||
            !setEquals(previous.selectedIndices, current.selectedIndices) ||
            previous.fontSize != current.fontSize ||
            previous.bodyDisplayProfile != current.bodyDisplayProfile ||
            previous.commentaryDisplayProfile !=
                current.commentaryDisplayProfile ||
            _commentaryCopyProfile(previous) != _commentaryCopyProfile(current);
      },
      loadingWidget: const Center(),
      builder: (context, state) {
        final selectedCommentators = _selectedCommentators(state);
        _syncSectionScroll(_currentIndexes(state));
        // איפוס ה-latch: ברגע שיש בחירה לא-ריקה, ריקון עתידי שלה צריך
        // לפתוח שוב את הבחירה (אך לא בכל rebuild בזמן שהבחירה נשארת ריקה).
        if (selectedCommentators.isNotEmpty) {
          _autoFilterOpenNotified = false;
        }
        final notesIsActive = _allSelectedCommentators(
          state,
        ).contains(kNotesCommentatorTitle);
        // כש'הערות' פעיל הוא משמש מפרש ברירת מחדל, ולכן בדרך כלל אין לפתוח
        // אוטומטית את בחירת המפרשים. חריג: כרטיסיית המפרשים מעבירה
        // onFilterOpenRequested ופותחת את הבחירה בלשונית צד נפרדת שאינה
        // מסתירה את ההערות — שם יש לפתוח גם כש'הערות' פעיל, אחרת כשאין
        // מפרשים נבחרים המשתמש נתקע על הודעת "אין הערות לקטע זה".
        final shouldAutoOpenOverrideFilter =
            widget.showSearch &&
            widget.onSelectedCommentatorsOverrideChanged != null &&
            selectedCommentators.isEmpty &&
            (widget.onFilterOpenRequested != null || !notesIsActive) &&
            !_autoFilterOpenNotified &&
            !_showCommentatorsFilter;

        if (shouldAutoOpenOverrideFilter) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted ||
                _showCommentatorsFilter ||
                _autoFilterOpenNotified) {
              return;
            }
            // בדיקה מחדש: אם המפרשים הזמינים כבר נטענו מאז תזמון הקריאה, לא פותחים את הסינון
            final currentBlocState = context.read<TextBookBloc>().state;
            if (currentBlocState is TextBookLoaded) {
              final currentSelected = _selectedCommentators(currentBlocState);
              if (currentSelected.isNotEmpty) return;
            }
            // אם ההורה רוצה לטפל בעצמו (לפתוח לשונית בסרגל הצד), מעבירים אליו.
            // מסמנים את ה-latch לפני הקריאה כדי שלא נשלח שוב באותו rebuild-cycle.
            if (widget.onFilterOpenRequested != null) {
              _autoFilterOpenNotified = true;
              widget.onFilterOpenRequested!();
              return;
            }
            setState(() {
              _showCommentatorsFilter = true;
              _filterWasAutoOpened = true;
            });
          });
          // כאשר ההורה מטפל בפתיחה, אין סיבה להחזיר ספינר טעינה — נמשיך לבנות
          // את התצוגה הרגילה (שתציג הודעת "אין מפרשים נבחרים" בהמשך).
          if (widget.onFilterOpenRequested == null) {
            return const Center(child: CircularProgressIndicator());
          }
        }

        final typeChipKeys = _typeChipKeys(state, selectedCommentators);
        final effectiveTypes = effectiveCommentaryTypes(
          selectedTypes: _selectedCommentaryTypes,
          availableKeys: typeChipKeys,
        );
        final visibleTypeChipKeys = CommentaryTypeFilter.visibleChipKeys(
          chipKeys: typeChipKeys,
          effectiveTypes: effectiveTypes,
        );

        Widget buildList() {
          return Builder(
            builder: (context) {
              // כשמשתמשים ב-availableCommentators, ממתינים שהם ייטענו
              if (widget.useAvailableCommentators &&
                  state.availableCommentators.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }

              // ריבוי-בחירה: כל הקטעים שנבחרו (Ctrl+לחיצה), לא רק העוגן.
              final currentIndexes = _currentIndexes(state);

              Widget? notesWidget;
              if (notesIsActive) {
                final relevantNotes = inline_notes.notesForLines(
                  state.content,
                  currentIndexes,
                );
                if (relevantNotes.isNotEmpty) {
                  notesWidget = _NotesCommentaryWidget(
                    notes: relevantNotes,
                    fontSize: widget.fontSize,
                    displayProfile: state.commentaryDisplayProfile,
                    openBookCallback: widget.openBookCallback,
                    state: state,
                    reportLineIndex:
                        state.selectedIndex ?? currentIndexes.first,
                    selectionSyncController: widget.selectionSyncController,
                  );
                } else if (selectedCommentators.isEmpty) {
                  notesWidget = const OtzariaEmptyState(
                    isCompact: true,
                    icon: FluentIcons.note_24_regular,
                    title: 'אין הערות לקטע זה',
                  );
                }
              }

              // בדיקה אם יש בכלל קישורים לאינדקסים הנוכחיים (ללא סינון מפרשים)
              final hasAnyCommentaryLinks = currentIndexes.any((idx) {
                final lineLinks = state.linksByLine[idx + 1];
                if (lineLinks == null) return false;
                return lineLinks.any(
                  (link) => LinkTypes.isDependentTextLink(link.connectionType),
                );
              });

              // סינון מהיר של קישורים רלוונטיים
              final hasRelevantLinks = currentIndexes.any((idx) {
                final lineLinks = state.linksByLine[idx + 1];
                if (lineLinks == null) return false;
                return lineLinks.any(
                  (link) => selectedCommentators.contains(
                    utils.getTitleFromPath(link.path2),
                  ),
                );
              });

              // אם אין קישורים רלוונטיים
              if (!hasRelevantLinks) {
                if (state.linksLoading) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        'טוען מפרשים...',
                        style: TextStyle(
                          fontSize: widget.fontSize * 0.7,
                          color: Colors.grey,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                if (notesWidget != null) {
                  return notesWidget;
                }
                // אם יש מפרשים זמינים אבל לא נבחרו בכלל - פתח אוטומטית את מסך הבחירה
                // (לא במצב useAvailableCommentators — שם מוצג הכל אוטומטית)
                if (widget.showSearch &&
                    !widget.useAvailableCommentators &&
                    hasAnyCommentaryLinks &&
                    selectedCommentators.isEmpty &&
                    !_showCommentatorsFilter) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      setState(() {
                        _showCommentatorsFilter = true;
                        _filterWasAutoOpened = true;
                      });
                    }
                  });
                  return const Center(child: CircularProgressIndicator());
                }

                // אין מפרשים בכלל לקטע הזה, או שיש מפרשים נבחרים אבל הם לא רלוונטיים
                return OtzariaEmptyState(
                  isCompact: true,
                  icon: OtzariaIcons.link_24_regular,
                  title: hasAnyCommentaryLinks
                      ? 'לא נמצאו מפרשים מהנבחרים לקטע זה'
                      : 'לא נמצאו מפרשים לקטע הנבחר',
                );
              }

              final commentaryWidget = FutureBuilder<List<Link>>(
                future: getLinksforIndexs(
                  indexes: currentIndexes,
                  links: state.links,
                  commentatorsToShow: selectedCommentators,
                  typesToShow: effectiveTypes,
                ),
                builder: (context, thisLinksSnapshot) {
                  if (!thisLinksSnapshot.hasData) {
                    // רק אם יש קישורים רלוונטיים, מציג אנימציית טעינה
                    return _buildSkeletonLoading();
                  }
                  if (thisLinksSnapshot.data!.isEmpty) {
                    // רשימה ריקה כאן נובעת מסינון הסוגים בלבד (יש קישורים
                    // רלוונטיים), ולכן מסבירים במקום להציג ריק בלי הסבר.
                    if (effectiveTypes.isEmpty) return const SizedBox.shrink();
                    return const OtzariaEmptyState(
                      isCompact: true,
                      icon: OtzariaIcons.link_24_regular,
                      title: 'לא נמצאו מפרשים מהסוגים שנבחרו',
                    );
                  }
                  final data = thisLinksSnapshot.data!;

                  // שומר את הסדר של ה-links לצורך חישוב אינדקס החיפוש
                  _orderedLinks = data;
                  if (_pendingScrollTarget != null) {
                    _schedulePendingCommentatorScroll();
                  }

                  // מנקה מפתחות ישנים ומכין מפתחות חדשים
                  final currentLinkKeys = data
                      .map((l) => _getLinkKey(l))
                      .toSet();

                  // קישורים חדשים (טעינה/מעבר שורה) — חישוב ספירות חיפוש
                  // מחדש אם יש שאילתה פעילה.
                  final linksSignature = Object.hashAll(currentLinkKeys);
                  if (linksSignature != _lastLinksSignature) {
                    _lastLinksSignature = linksSignature;
                    _scheduleSearchCompute();
                  }
                  _itemKeys.removeWhere(
                    (key, value) => !currentLinkKeys.contains(key),
                  );
                  for (final key in currentLinkKeys) {
                    _itemKeys.putIfAbsent(key, () => GlobalKey());
                  }
                  _renderedTextByKey.removeWhere(
                    (key, value) => !currentLinkKeys.contains(key),
                  );
                  _renderedTitleByKey.removeWhere(
                    (key, value) => !currentLinkKeys.contains(key),
                  );

                  // ניקוי ספירות חיפוש מקישורים שאינם בקטע הנוכחי
                  // (מניעת ספירה מנופחת ממעבר בין קטעים)
                  final staleSearchKeys = _searchResultsPerLink.keys
                      .where((key) => !currentLinkKeys.contains(key))
                      .toList();
                  if (staleSearchKeys.isNotEmpty) {
                    for (final key in staleSearchKeys) {
                      _searchResultsPerLink.remove(key);
                    }
                    _pendingCounts.removeWhere(
                      (key, _) => !currentLinkKeys.contains(key),
                    );
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      final newTotal = _searchResultsPerLink.values.fold(
                        0,
                        (sum, c) => sum + c,
                      );
                      _totalSearchResultsNotifier.value = newTotal;
                      if (_currentSearchIndexNotifier.value >= newTotal) {
                        _currentSearchIndexNotifier.value = 0;
                      }
                    });
                  }

                  _expansionStates.removeWhere(
                    (key, value) => !data.any(
                      (link) => key == utils.getTitleFromPath(link.path2),
                    ),
                  );

                  // מיירט גם את CopySelectionTextIntent, ולא רק את צירוף
                  // המקשים: בלעדיו Ctrl+C נופל להעתקת ברירת המחדל של Flutter,
                  // שכותבת ללוח את הבחירה כמות שהיא — גם כשהיא ריקה (#674).
                  return SelectionCopyShortcuts(
                    onCopy: () {
                      // בחירה החוצה כמה מפרשים — לא מייחסים כותרת מקור
                      // (היא הייתה משתייכת למפרש בודד בלבד).
                      final link = _selectionSpansMultipleItems()
                          ? null
                          : _lastSelectedLink.value;
                      ContextMenuUtils.copyFormattedText(
                        context: context,
                        savedSelectedText: _restoreLineBreaks(
                          _savedSelectedText.value,
                        ),
                        fontSize: widget.fontSize,
                        link: link,
                      );
                    },
                    child: Listener(
                      // לחיצה בכל מקום בחלונית ממקדת את ה-ProgressiveScroll
                      // כדי שגלילה עם החיצים תעבוד בלי לבחור טקסט קודם.
                      behavior: HitTestBehavior.translucent,
                      onPointerDown: (event) {
                        if (!shouldFocusScrollOnPointerDown(event.buttons)) {
                          return;
                        }
                        _focusNode.requestFocus();
                      },
                      child: AppFutureBuilder<List<CommentaryGroup>>(
                        future: _getCachedGroups(data),
                        loadingWidget: _buildSkeletonLoading(),
                        builder: (context, groups) {
                          for (final group in groups) {
                            final groupKey = group.bookTitle;
                            _expansionStates.putIfAbsent(
                              groupKey,
                              () => _allExpanded,
                            );
                          }
                          final flatItems = _buildFlatItems(groups);
                          // רק כאן מיפויי האינדקסים קיימים. ה-FutureBuilder
                          // החיצוני כבר לא יבנה מחדש כשה-Future של הקבוצות
                          // נפתר, ולכן בקשה שהגיעה לפני שהרשימה נבנתה הייתה
                          // נשארת תלויה בלי הרענון הזה.
                          if (_pendingScrollTarget != null) {
                            _schedulePendingCommentatorScroll();
                          }

                          final listView = ScrollablePositionedList.builder(
                            itemScrollController: _itemScrollController,
                            itemPositionsListener: _itemPositionsListener,
                            initialScrollIndex: flatItems.isEmpty
                                ? 0
                                : _lastScrollIndex.clamp(
                                    0,
                                    flatItems.length - 1,
                                  ),
                            key: ValueKey(
                              'commentary_${selectedCommentators.join(',')}',
                            ),
                            physics: const ClampingScrollPhysics(),
                            scrollOffsetController: scrollController,
                            shrinkWrap: widget.shrinkWrap,
                            itemCount: flatItems.length,
                            itemBuilder: (context, index) {
                              final item = flatItems[index];
                              final link = item.link;
                              final child = link == null
                                  ? _buildGroupHeader(item.group)
                                  : _buildLinkItem(item.group, link, state);
                              if (!item.showDivider) return child;
                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  child,
                                  const Divider(height: 1),
                                ],
                              );
                            },
                          );

                          // ProgressiveScroll עוטף את SelectionArea (מעליו),
                          // כך שגלילת החיצים נקלטת גם כש-SelectableRegion הוא
                          // ה-primaryFocus — האירוע מתפשט כלפי מעלה דרכו.
                          return ProgressiveScroll(
                            focusNode: _focusNode,
                            autofocus: widget.autofocus,
                            scrollController: scrollController,
                            maxSpeed: 10000.0,
                            curve: 10.0,
                            accelerationFactor: 5,
                            itemScrollController: _itemScrollController,
                            child: RtlSelectionShortcuts(
                              child: SelectionArea(
                                key: _selectionAreaKey,
                                contextMenuBuilder: (context, _) =>
                                    const SizedBox.shrink(),
                                onSelectionChanged: (selection) =>
                                    _onListSelectionChanged(
                                      selection?.plainText,
                                    ),
                                child: ScrollablePositionedListScrollbar(
                                  scrollController: _itemScrollController,
                                  offsetController: scrollController,
                                  itemPositionsListener: _itemPositionsListener,
                                  itemCount: flatItems.length,
                                  child: SmoothWheelScroll(
                                    child: PageStorage(
                                      bucket: _listStorageBucket,
                                      child: _constrainToContentWidth(listView),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
              );

              if (notesWidget == null) {
                return commentaryWidget;
              }

              // "הערות" + מפרשים. אסור ש"הערות" יתפוס חצי קבוע: `Flexible`
              // ו-`Expanded` שניהם flex:1 התחלקו 50/50, כך שהמפרשים קיבלו רק
              // חצי מהגובה (וכש"הערות" קצר נותר חלל ריק). במקום זאת מגבילים
              // את "הערות" לגובה התוכן שלו (עד ~45% מהגובה; הוא SingleChild-
              // ScrollView ולכן יגלול אם ארוך), והמפרשים מקבלים את כל השאר.
              return LayoutBuilder(
                builder: (ctx, c) {
                  final maxNotes = c.maxHeight.isFinite
                      ? c.maxHeight * 0.45
                      : double.infinity;
                  return Column(
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: maxNotes),
                        child: notesWidget,
                      ),
                      const Divider(height: 1),
                      Expanded(child: commentaryWidget),
                    ],
                  );
                },
              );
            },
          );
        }

        if (widget.showSearch) {
          // אם מסך בחירת המפרשים פתוח, מציג אותו במקום הרשימה
          if (_showCommentatorsFilter) {
            final groups = _commentatorGroups(state);
            final customSelection =
                widget.onSelectedCommentatorsOverrideChanged;
            return CommentatorsFilterScreen(
              onBack: _closeCommentatorsFilter,
              child: customSelection != null
                  ? CommentatorsSelectionPanel(
                      groups: groups,
                      // מעבירים את הבחירה המלאה (כולל 'הערות') ולא את
                      // selectedCommentators המסונן — אחרת תיבת הסימון של
                      // 'הערות' לעולם לא תוצג כמסומנת, ובחירת מפרש אחר תמחק
                      // אותו מהבחירה הפעילה.
                      selectedCommentators: _allSelectedCommentators(state),
                      onSelectionChanged: (list) {
                        _userInteractedWithFilter = true;
                        customSelection(list);
                      },
                      bookTitle: _bookTitle(state),
                      rareCommentators: state.rareCommentators,
                      lineRelevantCommentators: lineRelevantRareCommentators(
                        rareCommentators: state.rareCommentators,
                        currentIndexes: _currentIndexes(state),
                        linksByLine: state.linksByLine,
                      ),
                      typeChipKeys: visibleTypeChipKeys,
                      selectedTypeChips: effectiveTypes,
                      typeChipLabelBuilder: LinkTypes.hebrewLabel,
                      commentatorsByType:
                          CommentaryTypeFilter.commentatorsByType(state.links),
                      onTypeChipsChanged: _setSelectedCommentaryTypes,
                      heCategories: bookCategoriesSource(state.book),
                      onCategoryDefaultsSaved: () =>
                          TextBookPerBookSettings.clearActiveCommentators(
                            state.book,
                          ),
                    )
                  : CommentatorsListView(
                      onCommentatorSelected: _closeCommentatorsFilter,
                      typeChipKeys: visibleTypeChipKeys,
                      selectedTypeChips: effectiveTypes,
                      onTypeChipsChanged: _setSelectedCommentaryTypes,
                    ),
            );
          }

          // כאשר חיפוש חיצוני — מסתיר שורת חיפוש פנימית, רק רשימה
          if (widget.externalSearchController != null) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(fit: FlexFit.loose, child: buildList()),
              ],
            );
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: _showSearchField
                    ? _buildSearchFieldRow()
                    : _buildButtonsRow(selectedCommentators),
              ),
              Flexible(
                fit: FlexFit.loose,
                child: buildList(),
              ),
            ],
          );
        } else {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // כפתור גלובלי מעל הרשימה
              if (selectedCommentators.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      style: IconButton.styleFrom(
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.1),
                        foregroundColor: Theme.of(context).colorScheme.primary,
                      ),
                      icon: Icon(
                        _allExpanded
                            ? FluentIcons.arrow_collapse_all_24_regular
                            : FluentIcons.arrow_expand_all_24_regular,
                      ),
                      tooltip: _allExpanded
                          ? 'כווץ את כל המפרשים'
                          : 'הרחב את כל המפרשים',
                      onPressed: () {
                        setState(() {
                          _allExpanded = !_allExpanded;
                          // מעדכן את כל המצבים של הקבוצות
                          for (var key in _expansionStates.keys) {
                            _expansionStates[key] = _allExpanded;
                          }
                        });
                      },
                    ),
                  ),
                ),
              // הרשימה
              Flexible(
                child: buildList(),
              ),
            ],
          );
        }
      },
    );
  }

  /// בניית skeleton loading לפרשנות - מספר פרשנויות עם כותרת ושלוש שורות
  Widget _buildSkeletonLoading() {
    final baseColor = Theme.of(context).colorScheme.surfaceContainerHighest;

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 4, // מציג 4 שלדים של פרשנויות
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // כותרת הפרשן
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: _SkeletonLine(width: 0.3, height: 20, color: baseColor),
              ),
            ),
            // שלוש שורות תוכן
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: _SkeletonLine(width: 0.95, height: 16, color: baseColor),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: _SkeletonLine(width: 0.92, height: 16, color: baseColor),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: _SkeletonLine(width: 0.88, height: 16, color: baseColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Widget של שורה סטטית לשלד טעינה
class _SkeletonLine extends StatelessWidget {
  final double width;
  final double height;
  final Color color;

  const _SkeletonLine({
    required this.width,
    required this.color,
    this.height = 16,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: MediaQuery.of(context).size.width * width,
      decoration: BoxDecoration(
        color: color,
        borderRadius: AppTokens.borderRadiusAll,
      ),
    );
  }
}

/// פריט ברשימת המפרשים השטוחה: כותרת קבוצה (כש-[link] הוא null) או קטע מפרש
/// בודד. [showDivider] — הפריט האחרון של הקבוצה (המפריד מצויר אחריו).
@visibleForTesting
class CommentaryFlatItem {
  final CommentaryGroup group;
  final Link? link;
  final bool showDivider;

  const CommentaryFlatItem({
    required this.group,
    this.link,
    required this.showDivider,
  });
}

/// בונה את פריטי הרשימה השטוחה: פריט כותרת לכל קבוצה, ופריט לכל קטע רק
/// בקבוצה מורחבת — כך הרשימה נבנית בעצלנות (issue #844). [headerIndexOut]
/// ו-[linkIndexOut] מקבלים את מיפוי האינדקסים לגלילה.
@visibleForTesting
List<CommentaryFlatItem> buildCommentaryFlatItems({
  required List<CommentaryGroup> groups,
  required bool Function(String bookTitle) isGroupExpanded,
  required String Function(Link link) linkKey,
  required Map<String, int> headerIndexOut,
  required Map<String, int> linkIndexOut,
}) {
  final items = <CommentaryFlatItem>[];
  for (final group in groups) {
    final expanded = isGroupExpanded(group.bookTitle);
    headerIndexOut[group.bookTitle] = items.length;
    items.add(CommentaryFlatItem(group: group, showDivider: !expanded));
    if (!expanded) continue;
    for (int i = 0; i < group.links.length; i++) {
      final link = group.links[i];
      linkIndexOut[linkKey(link)] = items.length;
      items.add(
        CommentaryFlatItem(
          group: group,
          link: link,
          showDivider: i == group.links.length - 1,
        ),
      );
    }
  }
  return items;
}

/// כותרת קבוצת מפרשים ברשימה השטוחה — לחיצה מרחיבה/מכווצת דרך ההורה,
/// בלי להפריע לבחירת טקסט והעתקה (במקום ExpansionTile).
class _CommentaryGroupHeader extends StatelessWidget {
  final String bookTitle;
  final double fontSize;
  final bool isExpanded;
  final VoidCallback onTap;

  const _CommentaryGroupHeader({
    super.key,
    required this.bookTitle,
    required this.fontSize,
    required this.isExpanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 16.0,
          vertical: 12.0,
        ),
        child: Row(
          children: [
            AnimatedRotation(
              turns: isExpanded ? -0.25 : 0,
              duration: const Duration(milliseconds: 200),
              child: Icon(
                Icons.keyboard_arrow_left,
                size: 20,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: BlocBuilder<SettingsBloc, SettingsState>(
                builder: (context, settingsState) {
                  String displayTitle = bookTitle;
                  if (settingsState.replaceHolyNames) {
                    displayTitle = utils.replaceHolyNames(
                      displayTitle,
                      style: settingsState.holyNameStyle,
                    );
                  }
                  return Text(
                    displayTitle,
                    style: TextStyle(
                      fontSize: fontSize * 0.85,
                      fontWeight: FontWeight.bold,
                      fontVariations: AppFonts.boldFontVariations(
                        settingsState.commentatorsFontFamily,
                      ),
                      fontFamily: settingsState.commentatorsFontFamily,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// קטע מפרש בודד ברשימה השטוחה. פריט עצמאי ברשימה — נבנה רק כשהוא נגלל
/// לתצוגה, כך שפתיחת קטע עם המון מפרשים אינה בונה את כולם בבת אחת.
class _CommentaryLinkItem extends StatefulWidget {
  final Link link;
  final double fontSize;
  final Function(OpenedTab) openBookCallback;
  final TextDisplayProfile displayProfile;
  final TextDisplayProfile copyDisplayProfile;
  final bool showSearch;
  final ValueListenable<String> searchQueryListenable;
  final ValueListenable<int> currentSearchIndexListenable;
  final ValueListenable<int> totalSearchResultsListenable;
  final int Function(Link) getItemSearchIndex;
  final void Function(Link, int) updateSearchResultsCount;
  final void Function(Link, List<String>)? updateSearchSnippets;
  final Map<String, GlobalKey> itemKeys;
  final String Function(Link) getLinkKey;
  final ValueListenable<String?> savedSelectedTextListenable;
  final ValueListenable<Link?> lastSelectedLinkListenable;

  /// הערות ספר המפרש. אותו Future משותף לכל קטעי המפרש בקבוצה.
  final Future<List<PersonalNote>> personalNotes;

  /// נקרא אחרי שמירת הערה — ההורה מרענן את ה-Future המשותף של הקבוצה.
  final VoidCallback onNoteSaved;

  /// נקרא בלחיצת עכבר על פריט מפרש — לסימון המפרש הנבחר לייחוס העתקה.
  final void Function(Link link)? onLinkPointerDown;

  /// מדווח את הטקסט המרונדר של פריט מפרש — לשחזור מעברי שורה בהעתקה.
  final void Function(Link link, String renderedPlainText)? onLinkRendered;

  /// מדווח את כותרת הפריט המרונדרת (displayReference) — לשחזור מעברי שורה.
  final void Function(Link link, String renderedTitle)? onLinkTitleRendered;

  /// משחזר מעברי שורה בטקסט נבחר רב-שורתי (להעתקה מתפריט ההקשר).
  final String? Function(String?)? restoreLineBreaks;

  /// מחרוזת להדגשה מה-BLoC החיצוני, ללא שדה החיפוש הפנימי.
  final ValueListenable<String>? highlightQueryListenable;
  final void Function(Link link, int lineNumber)? onOpenPersonalNote;

  /// מכריע אם להציג את כותרת המקור (מקבל את הכותרת ללא אות העוגן).
  /// null = הצג תמיד.
  final bool Function(String displayTitle)? shouldShowItemTitle;

  const _CommentaryLinkItem({
    super.key,
    required this.link,
    required this.fontSize,
    required this.openBookCallback,
    required this.displayProfile,
    required this.copyDisplayProfile,
    required this.showSearch,
    required this.searchQueryListenable,
    required this.currentSearchIndexListenable,
    required this.totalSearchResultsListenable,
    required this.getItemSearchIndex,
    required this.updateSearchResultsCount,
    this.updateSearchSnippets,
    required this.itemKeys,
    required this.getLinkKey,
    required this.savedSelectedTextListenable,
    required this.lastSelectedLinkListenable,
    required this.personalNotes,
    required this.onNoteSaved,
    this.onLinkPointerDown,
    this.onLinkRendered,
    this.onLinkTitleRendered,
    this.restoreLineBreaks,
    this.highlightQueryListenable,
    this.onOpenPersonalNote,
    this.shouldShowItemTitle,
  });

  @override
  State<_CommentaryLinkItem> createState() => _CommentaryLinkItemState();
}

class _CommentaryLinkItemState extends State<_CommentaryLinkItem> {
  /// פותח את יעד הקישור בכרטיסייה חדשה (טקסט או PDF, לפי תבנית הפתיחה).
  Future<void> _navigateToLink(Link link) async {
    final tab = await buildLinkTargetTab(link);
    if (!mounted) return;
    widget.openBookCallback(tab);
  }

  @override
  Widget build(BuildContext context) {
    final link = widget.link;
    final Widget itemContent = ValueListenableBuilder<String?>(
      valueListenable: widget.savedSelectedTextListenable,
      child: Padding(
        key: widget.itemKeys[widget.getLinkKey(link)],
        padding: const EdgeInsets.only(
          right: 32.0,
          left: 16.0,
          top: 8.0,
          bottom: 8.0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BlocBuilder<SettingsBloc, SettingsState>(
              builder: (context, settingsState) {
                return FutureBuilder<String>(
                  future: link.displayReference,
                  builder: (context, snapshot) {
                    String displayTitle =
                        snapshot.data ?? link.fallbackDisplayReference;
                    final showTitle =
                        widget.shouldShowItemTitle?.call(displayTitle) ?? true;
                    // קישור עם עוגן-מילה: אות הסימון שמופיעה בגוף הטקסט
                    // נשמרת גם כשהכותרת מוסתרת — היא הקישור הוויזואלי להערה.
                    final markerLetter = link.anchorStart != null
                        ? anchorMarkerLetter(link)
                        : null;
                    if (!showTitle && markerLetter == null) {
                      // דיווח ריק דורס כותרת שדווחה קודם — לשחזור העתקה נכון.
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        widget.onLinkTitleRendered?.call(link, '');
                      });
                      return const SizedBox.shrink();
                    }
                    if (!showTitle) {
                      displayTitle = '($markerLetter)';
                    } else if (markerLetter != null) {
                      displayTitle = '($markerLetter) $displayTitle';
                    }
                    if (settingsState.replaceHolyNames) {
                      displayTitle = utils.replaceHolyNames(
                        displayTitle,
                        style: settingsState.holyNameStyle,
                      );
                    }
                    final reportedTitle = displayTitle;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      widget.onLinkTitleRendered?.call(
                        link,
                        reportedTitle,
                      );
                    });
                    return Text(
                      displayTitle,
                      style: TextStyle(
                        fontSize: widget.fontSize * 0.75,
                        fontWeight: FontWeight.normal,
                        fontFamily: settingsState.commentatorsFontFamily,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 4),
            AnimatedBuilder(
              animation: Listenable.merge([
                widget.searchQueryListenable,
                widget.currentSearchIndexListenable,
                widget.totalSearchResultsListenable,
                if (widget.highlightQueryListenable != null)
                  widget.highlightQueryListenable!,
              ]),
              builder: (context, _) {
                // שדה החיפוש הפנימי גובר כשהוקלד בו; כשהוא ריק נופלים
                // להדגשת מונח החיפוש החיצוני (מתוצאה שנחתה בהערה).
                final internalQuery = widget.showSearch
                    ? widget.searchQueryListenable.value
                    : '';
                final searchQuery = internalQuery.isNotEmpty
                    ? internalQuery
                    : (widget.highlightQueryListenable?.value ?? '');
                final currentSearchIndex =
                    (widget.showSearch ||
                        widget.highlightQueryListenable != null)
                    ? widget.getItemSearchIndex(link)
                    : 0;
                return AppContextMenuRegion(
                  // ריחוף מקדים את טעינת קישורי קטע היעד, כדי שהתפריט
                  // ייבנה מוכן. הלחיצה מכסה מגע/עט, שאין בהם ריחוף.
                  onHoverEnter: () =>
                      TargetLineLinksService.instance.prefetchOnHover(link),
                  onSecondaryTapDown: (_) =>
                      TargetLineLinksService.instance.prefetch(link),
                  // לחיצה ימנית על הטקסט המסומן בפועל לא תשחרר את הבחירה
                  // (התנהגות ברירת המחדל של SelectableRegion ב-Windows);
                  // לחיצה על חלק לא-מסומן מבטלת כרגיל. אין כאן מעקב
                  // פר-שורה — הבחירה מנוהלת ע"י SelectionArea יחיד — לכן
                  // מחשבים את קטע הבחירה ישירות מול הפסקה שעליה לחצו.
                  shouldPreserveSelectionOnSecondaryTap: (globalPosition) {
                    final selected = widget.savedSelectedTextListenable.value;
                    if (selected == null || selected.isEmpty) {
                      return false;
                    }
                    final root = context.findRenderObject();
                    if (root == null) return true; // סלחני
                    return clickIsOnSelectionWithinArea(
                          root: root,
                          globalPosition: globalPosition,
                          selectedText: selected,
                        ) ??
                        true; // לא הוכרע — סלחני
                  },
                  menuBuilder: (menuCtx, _) {
                    final savedTextAtBuild = captureSelectedTextForMenu(
                      widget.savedSelectedTextListenable,
                    );
                    return ContextMenuUtils.buildCommentaryContextMenu(
                      context: menuCtx,
                      link: link,
                      openBookCallback: widget.openBookCallback,
                      fontSize: widget.fontSize,
                      displayProfile: widget.displayProfile,
                      copyDisplayProfile: widget.copyDisplayProfile,
                      savedSelectedText: savedTextAtBuild,
                      onNavigateToLink: _navigateToLink,
                      onNoteSaved: widget.onNoteSaved,
                      onCopySelected: () => ContextMenuUtils.copyFormattedText(
                        context: menuCtx,
                        savedSelectedText:
                            (widget.restoreLineBreaks ?? (s) => s)(
                              savedTextAtBuild,
                            ),
                        fontSize: widget.fontSize,
                        // במצב הפאנל/כרטיסייה אין מעקב פר-פריט אחר
                        // המפרש הנבחר (אין SelectionArea פר-פריט), לכן
                        // נופלים חזרה ל-link של הפריט שעליו נפתח התפריט.
                        link: widget.lastSelectedLinkListenable.value ?? link,
                      ),
                      onCopySelectedWithoutNikud: () =>
                          ContextMenuUtils.copyFormattedText(
                            context: menuCtx,
                            savedSelectedText:
                                (widget.restoreLineBreaks ?? (s) => s)(
                                  savedTextAtBuild,
                                ),
                            fontSize: widget.fontSize,
                            link:
                                widget.lastSelectedLinkListenable.value ?? link,
                            removeNikud: true,
                          ),
                    );
                  },
                  child: CommentaryContent(
                    key: ValueKey(
                      '${link.index1}_${link.path2}_${link.index2}',
                    ),
                    link: link,
                    fontSize: widget.fontSize,
                    openBookCallback: widget.openBookCallback,
                    displayProfile: widget.displayProfile,
                    searchQuery: searchQuery,
                    currentSearchIndex: currentSearchIndex,
                    onSearchResultsCountChanged:
                        (widget.showSearch ||
                            widget.highlightQueryListenable != null)
                        ? (count) => widget.updateSearchResultsCount(
                            link,
                            count,
                          )
                        : null,
                    onSearchSnippetsChanged:
                        widget.showSearch && widget.updateSearchSnippets != null
                        ? (snippets) => widget.updateSearchSnippets!(
                            link,
                            snippets,
                          )
                        : null,
                    onRendered: (text) =>
                        widget.onLinkRendered?.call(link, text),
                    personalNotes: widget.personalNotes,
                    onOpenPersonalNote: widget.onOpenPersonalNote,
                  ),
                );
              },
            ),
          ],
        ),
      ),
      builder: (context, selectedText, child) => child!,
    );

    // הרשימה כולה עטופה ב-SelectionArea יחיד (בפאנל/בכרטיסייה/בתצוגה
    // המשולבת), ולכן מחזירים את התוכן ישירות — בלי SelectionArea
    // פר-פריט (שהיה הופך כל פריט ל"בלוק אטום" בבחירת מקלדת). עוטפים
    // ב-Listener שקוף כדי לזהות על איזה מפרש לחץ המשתמש (לייחוס בהעתקת
    // מקלדת Ctrl+C, שאין לה פריט-יעד).
    return Listener(
      onPointerDown: (_) => widget.onLinkPointerDown?.call(link),
      child: itemContent,
    );
  }
}

/// תצוגת המפרש הוירטואלי 'הערות' — מציגה את גוף ההערות ה-inline
/// (<i class="footnote">) של השורות הנבחרות כאילו היו רשימת מפרשים.
class _NotesCommentaryWidget extends StatefulWidget {
  final List<String> notes;
  final double fontSize;

  /// אותו פרופיל כמו טקסט המפרשים — ההערות מוצגות כמפרש.
  final TextDisplayProfile displayProfile;
  final Function(OpenedTab) openBookCallback;

  /// מצב הספר הראשי — דרוש לדיווח על טעות (ההערות inline בתוכו).
  final TextBookLoaded state;

  /// אינדקס השורה שאליה מיוחסות ההערות המוצגות — לדיווח הטעות.
  final int reportLineIndex;
  final SelectionSyncController? selectionSyncController;

  const _NotesCommentaryWidget({
    required this.notes,
    required this.fontSize,
    required this.displayProfile,
    required this.openBookCallback,
    required this.state,
    required this.reportLineIndex,
    this.selectionSyncController,
  });

  @override
  State<_NotesCommentaryWidget> createState() => _NotesCommentaryWidgetState();
}

class _NotesCommentaryWidgetState extends State<_NotesCommentaryWidget> {
  String? _selectedText;
  final Object _selectionOwner = Object();

  void _onNotesSelectionChanged(String? text) {
    _selectedText = text;
    if (text != null && text.trim().isNotEmpty) {
      widget.selectionSyncController?.activate(
        _selectionOwner,
        selectionText: text,
      );
    } else {
      widget.selectionSyncController?.clear(_selectionOwner);
    }
  }

  @override
  void dispose() {
    widget.selectionSyncController?.clear(_selectionOwner);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, settingsState) {
        // SelectionArea משלו: הרשימה הזו מוחזרת *מחוץ* ל-SelectionArea של
        // רשימת המפרשים (שנבנה רק סביב ה-ListView), ולכן בלעדיו לא ניתן
        // לבחור טקסט בהערות כלל.
        return SelectionCutFallthrough(
          child: RtlSelectionShortcuts(
            child: SelectionArea(
              // ביטול תפריט ברירת המחדל של Flutter — נשתמש ב-AppContextMenuRegion.
              contextMenuBuilder: (context, _) => const SizedBox.shrink(),
              onSelectionChanged: (selection) =>
                  _onNotesSelectionChanged(selection?.plainText),
              child: AppContextMenuRegion(
                // לחיצה ימנית על טקסט מסומן לא תשחרר את הבחירה (ברירת המחדל של
                // SelectableRegion ב-Windows); לחיצה מחוץ לבחירה מבטלת כרגיל.
                shouldPreserveSelectionOnSecondaryTap: (globalPosition) {
                  final selected = _selectedText;
                  if (selected == null || selected.isEmpty) return false;
                  final root = context.findRenderObject();
                  if (root == null) return true;
                  return clickIsOnSelectionWithinArea(
                        root: root,
                        globalPosition: globalPosition,
                        selectedText: selected,
                      ) ??
                      true;
                },
                menuBuilder: (menuCtx, _) => [
                  AppContextMenuEntry(
                    label: 'העתק',
                    icon: FluentIcons.copy_24_regular,
                    enabled:
                        _selectedText != null &&
                        _selectedText!.trim().isNotEmpty,
                    onTap: () => ContextMenuUtils.copyFormattedText(
                      context: menuCtx,
                      savedSelectedText: _selectedText,
                      fontSize: widget.fontSize,
                    ),
                  ),
                  if (showCopyWithoutNikud(_selectedText))
                    AppContextMenuEntry(
                      label: 'העתק בלי ניקוד',
                      icon: FluentIcons.text_clear_formatting_24_regular,
                      onTap: () => ContextMenuUtils.copyFormattedText(
                        context: menuCtx,
                        savedSelectedText: _selectedText,
                        fontSize: widget.fontSize,
                        removeNikud: true,
                      ),
                    ),
                  if (!widget.state.book.isUserBook) ...[
                    const AppContextMenuEntry.divider(),
                    AppContextMenuEntry(
                      label: 'דווח על טעות בספר',
                      icon: FluentIcons.error_circle_24_regular,
                      enabled:
                          _selectedText != null &&
                          _selectedText!.trim().isNotEmpty,
                      onTap: () => ErrorReportHelper.showErrorReportDialog(
                        context: menuCtx,
                        selectedText: _selectedText ?? '',
                        state: widget.state,
                        fontSize: widget.fontSize,
                        bookTitle: widget.state.book.title,
                        savedSelectedIndex: widget.reportLineIndex,
                      ),
                    ),
                  ],
                ],
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 12.0,
                        ),
                        child: Text(
                          kNotesCommentatorTitle,
                          style: TextStyle(
                            fontSize: widget.fontSize * 0.85,
                            fontWeight: FontWeight.bold,
                            fontVariations: AppFonts.boldFontVariations(
                              settingsState.commentatorsFontFamily,
                            ),
                            fontFamily: settingsState.commentatorsFontFamily,
                          ),
                        ),
                      ),
                      ...widget.notes.map((note) {
                        return Padding(
                          padding: const EdgeInsets.only(
                            right: 32.0,
                            left: 16.0,
                            bottom: 12.0,
                          ),
                          child: SmartTextWidget(
                            text: note,
                            settings: RenderSettings.fromProfile(
                              widget.displayProfile,
                              searchText: '',
                              currentSearchIndex: -1,
                              fontSize: widget.fontSize * 0.85,
                              fontFamily: settingsState.commentatorsFontFamily,
                              fontWeight: settingsState.commentatorsFontBold
                                  ? FontWeight.bold
                                  : null,
                              lineHeight: settingsState.lineHeight,
                            ),
                            onOpenBook: (tab) {
                              if (tab is TextBookTab) {
                                widget.openBookCallback(tab);
                              }
                            },
                          ),
                        );
                      }),
                      const Divider(height: 1),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
