import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/data/book_identity.dart';
import 'package:otzaria/book_common/bloc/commentary_search_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:otzaria/widgets/misc/rtl_icon.dart';
import 'package:otzaria/book_common/view/content_width.dart';
import 'package:otzaria/book_common/selection/commentary_selection.dart';
import 'package:otzaria/book_common/selection/commentary_copy_guard.dart';
import 'package:otzaria/book_common/utils/commentary_search_results.dart';
import 'package:otzaria/book_common/utils/commentary_flat_items.dart';
import 'package:otzaria/theme/app_fonts.dart';
import 'package:otzaria/theme/app_theme_data.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:flutter/gestures.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/widgets/text/rtl_selection_shortcuts.dart';
import 'package:otzaria/widgets/text/selection_copy_shortcuts.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/book_protection/repository/book_protection_repository.dart';
import 'package:otzaria/book_protection/utils/copy_guard.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/plugins/utils/plugin_context_menu_entries.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/services/target_line_links_service.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/utils/navigation/talmud_bavli_open_format.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/personal_notes/personal_notes_system.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_changes.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/widgets/text_book_state_builder.dart';
import 'package:otzaria/widgets/commentary/commentary_content.dart';
import 'package:otzaria/text_book/view/error_report_dialog.dart';
import 'package:otzaria/text_book/models/commentary_scroll_request.dart';
import 'package:otzaria/book_common/models/commentator_group.dart';
import 'package:otzaria/book_common/utils/commentary_search_utils.dart';
import 'package:otzaria/text_display/models/text_display_profile.dart';
import 'package:otzaria/text_display/models/text_display_slot.dart';
// מיוצא כאן כדי שצרכני כרטיסיית הטקסט יייבאו אותו מנקודה אחת.
export 'package:otzaria/book_common/utils/commentary_search_utils.dart'
    show CommentarySearchSnippet;
import 'package:otzaria/book_common/utils/category_settings_utils.dart';
import 'package:otzaria/book_common/utils/commentary_plugin_menu_entries.dart';
import 'package:otzaria/text_book/utils/commentary_title_visibility.dart';
import 'package:otzaria/book_common/utils/commentary_type_filter.dart';
import 'package:otzaria/book_common/utils/commentator_group_builder.dart';
import 'package:otzaria/book_common/utils/link_anchor_markers.dart';
import 'package:otzaria/text_book/view/commentators_list_screen.dart';
import 'package:otzaria/widgets/misc/commentators_filter_button.dart';
import 'package:otzaria/widgets/misc/link_preview_overlay.dart';
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
import 'package:positioned_sliver_list/positioned_list.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';
import 'package:otzaria/widgets/feedback/scrollable_positioned_list_scrollbar.dart';
import 'package:flutter/foundation.dart';

import 'dart:async';

import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/text_book/utils/inline_notes_utils.dart'
    as inline_notes;
import 'package:otzaria/text_book/view/selection/selection_sync_controller.dart';
import 'package:otzaria/book_common/selection/selection_hit_test.dart';
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

/// מסיר מ-[states] מפרשים שאין להם עוד קישור ב-[links].
@visibleForTesting
void pruneCommentaryExpansionStates(
  Map<String, bool> states,
  List<Link> links,
) {
  if (states.isEmpty) return;
  final missing = states.keys.toSet();
  for (final link in links) {
    missing.remove(utils.getTitleFromPath(link.path2));
    if (missing.isEmpty) return;
  }
  states.removeWhere((key, value) => missing.contains(key));
}

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

  /// כשהדגל מופעל, יציג את כל מפרשי הספר (בסדר commentatorGroups) ולא את activeCommentators
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

  /// false כשהחלונית שמכילה את הרשימה סגורה אך נשארת בעץ.
  final bool isPaneOpen;

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
    this.isPaneOpen = true,
  });

  @override
  State<CommentaryListBase> createState() => CommentaryListBaseState();
}

enum _CommentaryStorageSlot { expansion }

// לשוניות שומרות את העץ; כרטיסים בתוך הספר משתחררים מחוץ למטמון הגלילה.
class CommentaryListBaseState extends State<CommentaryListBase>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => !widget.shrinkWrap;

  PageStorageBucket? _inlineStorage;
  Object? _inlineStorageIdentifier;
  final TextEditingController _searchController = TextEditingController();
  final ValueNotifier<String> _searchQueryNotifier = ValueNotifier<String>('');
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
  Map<String, int> get _searchResultsPerLink => _searchBloc.state.counts;
  int _lastScrollIndex = 0; // שומר את מיקום הגלילה האחרון
  // שורות המקור שהרשימה מציגה כרגע — לזיהוי מעבר לקטע אחר.
  List<int>? _sectionIndexes;
  // מצב גלובלי של פתיחה/סגירה של כל המפרשים — חשוף ככ-ValueListenable כדי
  // שצרכנים חיצוניים (למשל CommentatorsTabScreen) יוכלו להאזין ולעדכן UI.
  final ValueNotifier<bool> _allExpandedNotifier = ValueNotifier<bool>(true);
  bool get _allExpanded => _allExpandedNotifier.value;
  set _allExpanded(bool value) => _allExpandedNotifier.value = value;
  final Map<String, bool> _expansionStates =
      {}; // מעקב אחרי מצב כל קבוצת מפרשים
  String? _cachedGroupingSignature;
  List<Link>? _cachedGroupingSource;
  Future<List<CommentaryGroup>>? _cachedGroupsFuture;
  List<CommentaryGroup>? _lastResolvedGroups;
  List<int>? _lastResolvedGroupIndexes;
  Object? _lastResolvedGroupBook;
  bool _groupsReady = false;

  // הרשימה השטוחה: פריט נפרד לכל כותרת מפרש ולכל קטע — כך הרשימה נבנית
  // בעצלנות ולא כל מפרשי הקטע בבת אחת (מקור האיטיות ב-issue #844).
  Map<String, int> _groupHeaderFlatIndex = const {};
  Map<String, int> _linkFlatIndex = const {};
  final ListController _listController = ListController();
  final Map<String, GlobalKey> _headerKeys = {};
  HeaderAnchorHandle? _headerAnchor;
  Map<Key, int> _flatIndexByKey = const {};
  int _flatItemsRevision = 0;
  ({
    List<CommentaryGroup> groups,
    Map<String, bool> expansion,
    List<CommentaryFlatItem> items,
  })?
  _flatSnapshot;

  @visibleForTesting
  int get debugFlatItemsRevision => _flatItemsRevision;
  int _searchScrollGeneration = 0;
  // הערות אישיות פר ספר-מפרש, משותפות לכל הקטעים של אותו מפרש.
  final Map<String, Future<List<PersonalNote>>> _personalNotesByGroup = {};
  StreamSubscription<String>? _notesChangesSubscription;

  ({
    List<Link> links,
    List<int> indexes,
    List<String> commentators,
    Set<String> types,
    Future<List<Link>> future,
  })?
  _cachedLinks;

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
  // הבקשה אינה בונה מחדש, ולכן זוכרים שנשלחה עד שנבחרו מפרשים,
  // כדי לא להציף את ההורה בזמן שהבחירה ריקה.
  bool _autoFilterOpenNotified = false;
  bool _userInteractedWithFilter =
      false; // האם המשתמש בחר בעצמו בתוך פאנל הסינון
  final FocusNode _focusNode = FocusNode();
  final FocusNode _searchFocusNode = FocusNode();
  int _lastSeenFilterRequest = 0;
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

  Future<CommentaryCopyGuard?> _multiItemCopyGuard() async {
    final links = selectedItemLinks(_itemKeys, _orderedLinks, _getLinkKey);
    if (links.isEmpty) return null;
    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded) return null;
    return buildCommentaryCopyGuard(
      links,
      selectionOf: (link) => CommentarySelectionTracker.selectionIn(
        _itemKeys[_getLinkKey(link)]!,
      ),
      renderSettings: RenderSettings.fromProfile(
        state.commentaryDisplayProfile,
      ),
    );
  }

  /// הקישור של הבחירה כשהיא בתוך פריט יחיד, גם בלי לחיצה שסימנה אותו.
  Link? _singleSelectedLink() {
    final links = selectedItemLinks(_itemKeys, _orderedLinks, _getLinkKey);
    return links.length == 1 ? links.single : null;
  }

  // סדר הקישורים המוצגים, שעליו מבוססים היסטי החיפוש.
  List<Link> _orderedLinks = [];
  Map<String, int>? _searchResultOffsets;

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
      // סדר התצוגה נגזר מהרשימה, ולכן בסדר הקבוצות (דורות, בסיסיים ראשונים)
      // ולא ב-availableCommentators הממוין לפי א"ב.
      return [for (final g in state.commentatorGroups) ...g.commentators];
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
              '${link.index1}|${link.contentIdentityKey}|${link.connectionType}',
        )
        .join('||');
  }

  // getLinksforIndexs סורק את כל קישורי הספר; future חדש גם גורם לבנייה נוספת
  // כשהוא נפתר, ולכן נוצר מחדש רק כשהקלטים משתנים.
  Future<List<Link>> _getCachedLinks(
    List<int> indexes,
    List<Link> links,
    List<String> commentators,
    Set<String> types,
  ) {
    final cached = _cachedLinks;
    if (cached != null &&
        identical(cached.links, links) &&
        listEquals(cached.indexes, indexes) &&
        listEquals(cached.commentators, commentators) &&
        setEquals(cached.types, types)) {
      return cached.future;
    }
    final future = getLinksforIndexs(
      indexes: indexes,
      links: links,
      commentatorsToShow: commentators,
      typesToShow: types,
    );
    _cachedLinks = (
      links: links,
      indexes: indexes,
      commentators: commentators,
      types: types,
      future: future,
    );
    return future;
  }

  Future<List<CommentaryGroup>> _getCachedGroups(List<Link> links) {
    if (identical(links, _cachedGroupingSource)) return _cachedGroupsFuture!;
    _cachedGroupingSource = links;
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
    final snapshot = _flatSnapshot;
    if (snapshot != null &&
        identical(snapshot.groups, groups) &&
        groups.every(
          (group) =>
              snapshot.expansion[group.bookTitle] ==
              (_expansionStates[group.bookTitle] ?? _allExpanded),
        )) {
      return snapshot.items;
    }
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
    _flatIndexByKey = {
      for (var i = 0; i < items.length; i++) _flatItemKey(items[i]): i,
    };
    _headerKeys.removeWhere((title, _) => !headerIdx.containsKey(title));
    _flatItemsRevision++;
    _flatSnapshot = (
      groups: groups,
      expansion: {
        for (final group in groups)
          group.bookTitle: _expansionStates[group.bookTitle] ?? _allExpanded,
      },
      items: items,
    );
    return items;
  }

  /// הקישורים ש-[_itemKeys] סונכרנו אליהם; בנייה על אותה רשימה אינה גוזרת שוב.
  List<Link>? _keyedLinks;

  /// מפתחות הפריטים והטקסט המרונדר — רק לקישורים של [links].
  void _syncItemKeys(List<Link> links) {
    if (identical(_keyedLinks, links)) return;
    _keyedLinks = links;
    final currentLinkKeys = links.map(_getLinkKey).toSet();
    _itemKeys.removeWhere((key, _) => !currentLinkKeys.contains(key));
    for (final key in currentLinkKeys) {
      _itemKeys.putIfAbsent(key, GlobalKey.new);
    }
    _renderedTextByKey.removeWhere((key, _) => !currentLinkKeys.contains(key));
    _renderedTitleByKey.removeWhere((key, _) => !currentLinkKeys.contains(key));
  }

  Key _flatItemKey(CommentaryFlatItem item) => item.link == null
      ? ValueKey('h:${item.group.bookTitle}')
      : ValueKey('l:${_getLinkKey(item.link!)}');

  bool _preserveGroupHeader(String? title) {
    final render = _headerKeys[title]?.currentContext?.findRenderObject();
    if (render is! RenderBox || !render.hasSize) return false;
    final viewport = RenderAbstractViewport.maybeOf(render);
    if (viewport is! RenderBox) return false;
    final viewportBox = viewport as RenderBox;
    final top = render.localToGlobal(Offset.zero, ancestor: viewportBox).dy;
    if (top + render.size.height <= 0 || top >= viewportBox.size.height) {
      return false;
    }
    final scroll = _itemScrollController.scrollController;
    if (scroll != null &&
        scroll.hasClients &&
        scroll.position.isScrollingNotifier.value) {
      scroll.jumpTo(scroll.offset);
    }
    final handle = _listController.preserveHeader(render);
    if (handle == null) return false;
    _headerAnchor = handle;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      handle.cancel();
      if (identical(_headerAnchor, handle)) _headerAnchor = null;
    });
    return true;
  }

  void _cancelHeaderAnchor() {
    _headerAnchor?.cancel();
    _headerAnchor = null;
  }

  void _cancelPendingNavigation() {
    _cancelSearchNavigation();
    _commentatorScrollGeneration++;
    _pendingScrollTarget = null;
  }

  Widget _trackHeaderScroll(Widget child) => Listener(
    onPointerDown: (_) => _cancelPendingNavigation(),
    onPointerSignal: (_) => _cancelPendingNavigation(),
    child: NotificationListener<ScrollStartNotification>(
      onNotification: (notification) {
        if (notification.depth == 0) _cancelHeaderAnchor();
        return false;
      },
      child: child,
    ),
  );

  void _toggleGroupExpansion(CommentaryGroup group) {
    _cancelPendingNavigation();
    final generation = _commentatorScrollGeneration;
    final key = group.bookTitle;
    final expanded = !(_expansionStates[key] ?? _allExpanded);
    final headerIndex = _groupHeaderFlatIndex[key];
    final headerEdge = expanded || headerIndex == null
        ? null
        : _leadingEdgeOfItem(headerIndex);
    final preserved = !expanded && _preserveGroupHeader(key);
    setState(() {
      _expansionStates[key] = expanded;
      _updateGlobalExpansionState();
    });
    if (expanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || generation != _commentatorScrollGeneration) return;
        final index = _groupHeaderFlatIndex[key];
        if (index != null) _ensureExpandedGroupVisible(index);
      });
    } else if (!preserved && headerEdge != null) {
      _reanchorAfterCollapse(key, headerEdge);
    }
  }

  Future<List<PersonalNote>> _personalNotesForGroup(CommentaryGroup group) {
    // המפתח כמו בשמירה מתפריט המפרש: לפי מקור ספר היעד.
    final key = personalNotesBookKeyFor(
      group.bookTitle,
      group.links.firstOrNull?.targetSource ?? BookSource.official,
    );
    return _personalNotesByGroup.putIfAbsent(key, () {
      final loader = widget.personalNotesLoader;
      if (loader == null) return Future.value(const <PersonalNote>[]);
      return loader(
        key,
        categoryId: group.links.firstOrNull?.targetCategoryId,
      );
    });
  }

  void _handleNotesChanged(String bookId) {
    if (!mounted || !_personalNotesByGroup.containsKey(bookId)) return;
    setState(() {
      _personalNotesByGroup.remove(bookId);
    });
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
    final linkKey = _getLinkKey(link);
    if ((_searchResultsPerLink[linkKey] ?? 0) == 0) return -1;
    return commentarySearchRelativeIndex(
      key: linkKey,
      currentIndex: _currentSearchIndexNotifier.value,
      offsets: _searchResultOffsets ??= commentarySearchOffsets(
        _orderedLinks.map(_getLinkKey),
        _searchResultsPerLink,
      ),
      countsByKey: _searchResultsPerLink,
    );
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
    _cancelPendingNavigation();
    final collapsing = _allExpanded;
    final anchorTitle = collapsing
        ? groupTitleAtFlatIndex(_groupHeaderFlatIndex, _lastScrollIndex)
        : null;
    final preserved = collapsing && _preserveGroupHeader(anchorTitle);
    setState(() {
      _allExpanded = !_allExpanded;
      for (final key in _expansionStates.keys) {
        _expansionStates[key] = _allExpanded;
      }
    });
    if (collapsing && !preserved) _reanchorAfterCollapse(anchorTitle, 0);
  }

  /// ניווט לתוצאת חיפוש לפי אינדקס גלובלי (לשימוש חיצוני)
  void navigateToGlobalIndex(int index) {
    if (index < 0 || index >= _totalSearchResultsNotifier.value) return;
    _currentSearchIndexNotifier.value = index;
    _scrollToSearchResult();
  }

  void _onHighlightQueryChanged() {
    _cancelSearchNavigation();
    _currentSearchIndexNotifier.value = 0;
    _searchResultOffsets = null;
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
      _currentSearchIndexNotifier.value = -1;
      _searchResultOffsets = null;
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
    _searchController.clear();
    _searchQueryNotifier.value = '';
    _currentSearchIndexNotifier.value = 0;
    _searchResultOffsets = null;
    _scheduleSearchCompute();
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
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        icon: const Icon(FluentIcons.dismiss_24_regular),
        onPressed: widget.onClosePane,
      ),
    );
  }

  Widget _buildButtonsRow(List<String> selectedCommentators) {
    const double gap = 16;
    // גובה 36 כשדה החיפוש המצומצם, כדי שפתיחת החיפוש לא תזיז את הרשימה.
    return IconButtonTheme(
      data: IconButtonThemeData(
        style: (Theme.of(context).iconButtonTheme.style ?? const ButtonStyle())
            .copyWith(
              visualDensity:
                  Theme.of(context).extension<AppMenuMetrics>()?.compactMenus ==
                      true
                  ? const VisualDensity(vertical: -1)
                  : null,
            ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 1. בחירת מפרשים
          CommentatorsFilterButton(
            isActive: false,
            onPressed: _openCommentatorsFilter,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
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
              tooltip: _allExpanded
                  ? 'כווץ את כל המפרשים'
                  : 'הרחב את כל המפרשים',
              onPressed: toggleAllExpanded,
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
            icon: const Icon(FluentIcons.search_24_regular),
            tooltip: 'חיפוש',
            onPressed: _openInlineSearch,
          ),
          // לחצן סגירת הפאנל — נשאר רק אם הקולבק קיים
          if (widget.onClosePane != null) ...[
            const SizedBox(width: gap),
            _buildClosePaneButton(),
          ],
        ],
      ),
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
    final blocks = await buildCommentaryPrintBlocks(groups, keepHtml: true);
    if (blocks.isEmpty) {
      UiSnack.show(TextBookMessages.noCommentatorsToPrint);
      return;
    }
    if (!mounted) return;

    final protection = await BookProtectionRepository.instance
        .strictestForLinks(links);
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
        protection: protection,
        activeCommentators: groups
            .map((group) => group.bookTitle)
            .toList(growable: false),
        commentaryDisplayProfile: blocState.displayProfile(
          target: TextTarget.commentary,
          channel: TextChannel.export,
        ),
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
                      return OtzariaSearchField(
                        focusNode: _searchFocusNode,
                        controller: _searchController,
                        hintText: 'חפש בתוך המפרשים המוצגים...',
                        icon: OtzariaIcons.search_in_library_24_regular,
                        // Enter מנווט לתוצאה הבאה ומחזיר את הפוקוס לשדה; בחירת
                        // הכל בקבלת פוקוס הייתה מוחקת את השאילתה בתו הבא.
                        selectAllOnFocus: false,
                        trailingActions: [
                          if (query.isNotEmpty && total > 1) ...[
                            if (currentIndex >= 0)
                              OtzariaSearchAction.resultCounter(
                                current: currentIndex + 1,
                                total: total,
                                context: context,
                              ),
                            OtzariaSearchAction.prevResult(
                              onPressed: currentIndex > 0
                                  ? () {
                                      _currentSearchIndexNotifier.value =
                                          currentIndex - 1;
                                      _scrollToSearchResult();
                                    }
                                  : null,
                            ),
                            OtzariaSearchAction.nextResult(
                              onPressed: currentIndex < total - 1
                                  ? () {
                                      _currentSearchIndexNotifier.value =
                                          currentIndex + 1;
                                      _scrollToSearchResult();
                                    }
                                  : null,
                            ),
                          ],
                          OtzariaSearchAction.icon(
                            iconData: FluentIcons.dismiss_24_regular,
                            tooltip: 'סגור חיפוש',
                            onPressed: _clearSearchAndCloseField,
                          ),
                        ],
                        onChanged: (value) {
                          if (_searchQueryNotifier.value != value) {
                            _searchQueryNotifier.value = value;
                            _currentSearchIndexNotifier.value = -1;
                            _searchResultOffsets = null;
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
    _searchSubscription = _searchBloc.stream.listen(_applySearchState);
    _updateInlineStorage();
    if (widget.shrinkWrap && _inlineStorageIdentifier != null) {
      final saved = _inlineStorage?.readState(
        context,
        identifier: _inlineStorageIdentifier,
      );
      if (saved is (bool, Map<String, bool>)) {
        _allExpanded = saved.$1;
        _expansionStates.addAll(saved.$2);
      }
    }
    _searchQueryNotifier.addListener(_cancelSearchNavigation);
    // האזנה לשינויים במיקום הגלילה כדי לשמור את המיקום האחרון
    _itemPositionsListener.itemPositions.addListener(_updateLastScrollIndex);
    widget.selectionSyncController?.addListener(_handleExternalSelectionChange);
    widget.openFilterRequest?.addListener(_handleOpenFilterRequest);
    _lastSeenFilterRequest = widget.openFilterRequest?.value ?? 0;
    widget.openFilterNotifier?.addListener(_onOpenFilterRequest);
    widget.closeFilterNotifier?.addListener(_onCloseFilterRequest);
    _searchFocusNode.addListener(_handleSearchFocusChange);
    widget.typeSelection?.addListener(_onTypeSelectionChanged);
    _notesChangesSubscription = PersonalNotesChanges.stream.listen(
      _handleNotesChanged,
    );
    // חיפוש חיצוני
    widget.externalSearchController?.addListener(_onExternalSearchChanged);
    widget.highlightQueryListenable?.addListener(_onHighlightQueryChanged);
    widget.scrollTargetListenable?.addListener(_onExternalScrollTargetChanged);
    // בקשה שנקבעה לפני שהרשימה נבנתה (הפאנל נפתח בעקבות אותה לחיצה) —
    // בלי הבדיקה הזו היא הייתה אובדת, כי ה-listener מגיב רק לשינוי.
    _onExternalScrollTargetChanged();
    _totalSearchResultsNotifier.addListener(_publishExternalState);
    _currentSearchIndexNotifier.addListener(_publishExternalState);
    _allExpandedNotifier.addListener(_publishExternalState);
    _publishExternalState();
    if (widget.externalSearchController != null) _onExternalSearchChanged();
  }

  void _publishExternalState() {
    final total = widget.externalTotalResultsNotifier;
    final current = widget.externalCurrentIndexNotifier;
    final expanded = widget.externalAllExpandedNotifier;
    final byPath = widget.externalSearchResultsByPathNotifier;
    final snippets = widget.externalSearchSnippetsNotifier;
    final search = _searchBloc.state;
    if ((total == null || total.value == _totalSearchResultsNotifier.value) &&
        (current == null ||
            current.value == _currentSearchIndexNotifier.value) &&
        (expanded == null || expanded.value == _allExpanded) &&
        (byPath == null || identical(byPath.value, search.countsByPath)) &&
        (snippets == null || identical(snippets.value, search.snippets))) {
      return;
    }
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _publishExternalState();
      });
      return;
    }
    total?.value = _totalSearchResultsNotifier.value;
    current?.value = _currentSearchIndexNotifier.value;
    expanded?.value = _allExpanded;
    byPath?.value = search.countsByPath;
    snippets?.value = search.snippets;
  }

  void _updateInlineStorage() {
    _inlineStorage = PageStorage.maybeOf(context);
    Object? keys;
    bool collect(BuildContext element) {
      final key = element.widget.key;
      if (key is PageStorageKey) keys = (keys, key);
      return element.widget is! PageStorage;
    }

    if (collect(context)) context.visitAncestorElements(collect);
    _inlineStorageIdentifier = keys == null
        ? null
        : (_CommentaryStorageSlot.expansion, keys);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateInlineStorage();
  }

  @override
  void didUpdateWidget(CommentaryListBase oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shrinkWrap != widget.shrinkWrap) updateKeepAlive();
    _publishExternalState();
    if (oldWidget.externalSearchController != widget.externalSearchController) {
      oldWidget.externalSearchController?.removeListener(
        _onExternalSearchChanged,
      );
      widget.externalSearchController?.addListener(_onExternalSearchChanged);
      if (widget.externalSearchController != null) {
        _onExternalSearchChanged();
      } else {
        _clearSearchAndCloseField();
      }
    }
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
      _onHighlightQueryChanged();
    }
    if (oldWidget.scrollTargetListenable != widget.scrollTargetListenable) {
      oldWidget.scrollTargetListenable?.removeListener(
        _onExternalScrollTargetChanged,
      );
      widget.scrollTargetListenable?.addListener(
        _onExternalScrollTargetChanged,
      );
      _lastHandledScrollRequestId = 0;
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

  /// מחליף קטע מראש הרשימה אחרי פריסה; בקשת עוגן גוברת על האיפוס.
  void scrollToTop() {
    // המיקום המשוחזר לבנייה הבאה מתאפס בכל מקרה — היסט הקטע הקודם אינו
    // מתאים לתוכן החדש, ובקשת העוגן ממילא תמקם מחדש.
    _lastScrollIndex = 0;
    if (!shouldResetScrollForSectionChange(
      hasPendingAnchorScroll: _hasPendingAnchorScroll,
    )) {
      return;
    }
    final generation = _commentatorScrollGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _commentatorScrollGeneration ||
          !_itemScrollController.isAttached) {
        return;
      }
      // גם בסדר ההפוך: הקפיצה תוזמנה, ורק אז הגיעה בקשת העוגן.
      if (!shouldResetScrollForSectionChange(
        hasPendingAnchorScroll: _hasPendingAnchorScroll,
      )) {
        return;
      }
      _itemScrollController.jumpTo(index: 0);
    });
  }

  /// בקשת עוגן שממתינה לנתונים או לפריסה.
  bool get _hasPendingAnchorScroll => _pendingScrollTarget != null;

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
    if (currentIndexes.contains(_anchorScrollSectionLine)) {
      return;
    }
    _commentatorScrollGeneration++;
    _pendingScrollTarget = null;
    _cancelHeaderAnchor();
    _listController.cancelPositioning();
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
    _cancelHeaderAnchor();
    _listController.cancelPositioning();
    _searchScrollGeneration++;
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
    // בקשה חיצונית עשויה להגיע בלי שינוי אחר שמבקש פריים.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _runPendingCommentatorScroll() async {
    if (_commentatorScrollRunning || !mounted) return;
    _commentatorScrollRunning = true;
    final generation = _commentatorScrollGeneration;
    final revision = _flatItemsRevision;
    try {
      final target = _pendingScrollTarget;
      if (target == null ||
          !_groupsReady ||
          !_itemScrollController.isAttached) {
        return;
      }
      if (_expansionStates[target.title] == false) {
        setState(() => _expansionStates[target.title] = true);
        _schedulePendingCommentatorScroll();
        return;
      }
      if (_groupHeaderFlatIndex.isEmpty) return;
      final sourceLine = _anchorScrollSectionLine;
      if (sourceLine != null &&
          !(_sectionIndexes?.contains(sourceLine) ?? false)) {
        return;
      }
      final index = _resolveCommentatorScrollIndex(target);
      if (index != null) {
        await _itemScrollController.jumpToAsync(index: index);
      }
      if (!mounted || generation != _commentatorScrollGeneration) return;
      if (revision == _flatItemsRevision) {
        final key = index == _groupHeaderFlatIndex[target.title]
            ? _headerKeys[target.title]
            : _itemKeys[target.linkKey];
        final render = key?.currentContext?.findRenderObject();
        if (render is RenderBox && render.attached && render.hasSize) {
          _headerAnchor = _listController.preserveHeader(render);
        }
        _pendingScrollTarget = null;
      }
    } finally {
      _commentatorScrollRunning = false;
      if (mounted &&
          _pendingScrollTarget != null &&
          (generation != _commentatorScrollGeneration ||
              revision != _flatItemsRevision)) {
        _schedulePendingCommentatorScroll();
      }
    }
  }

  /// קטע ראשון בקבוצה מתיישר לכותרת; שאר הקטעים מתיישרים לעצמם.
  int? _resolveCommentatorScrollIndex(
    ({String title, String? linkKey}) target,
  ) {
    final headerIndex = _groupHeaderFlatIndex[target.title];
    final linkKey = target.linkKey;
    final linkIndex = linkKey == null ? null : _linkFlatIndex[linkKey];
    if (linkIndex == null) return headerIndex;
    if (headerIndex != null && linkIndex == headerIndex + 1) return headerIndex;
    return linkIndex;
  }

  /// הקצה העליון של הפריט [index] כשבר מגובה אזור הגלילה, או null אם הפריט
  /// אינו בנוי כלל. ערך מחוץ ל-[0,1] פירושו שהפריט מחוץ למסך.
  double? _leadingEdgeOfItem(int index) {
    for (final position in _itemPositionsListener.itemPositions.value) {
      if (position.index == index) return position.itemLeadingEdge;
    }
    return null;
  }

  /// מחזיר את כותרת [groupTitle] לקצה שלה אחרי כיווץ: פריטי הקבוצה שהרשימה
  /// עוגנה בהם נעלמים, והיא הייתה נעצרת במפרש אחר (#1174).
  void _reanchorAfterCollapse(String? groupTitle, double alignment) {
    if (groupTitle == null) return;
    final generation = _commentatorScrollGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _commentatorScrollGeneration ||
          !_itemScrollController.isAttached) {
        return;
      }
      final index = _groupHeaderFlatIndex[groupTitle];
      if (index == null) return;
      _itemScrollController.jumpTo(
        index: index,
        alignment: alignment.clamp(0.0, 1.0),
      );
    });
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
  void deactivate() {
    if (widget.shrinkWrap && _inlineStorageIdentifier != null) {
      // ה-sliver עשוי לנתק את הפריט מאבותיו לפני deactivate.
      _inlineStorage?.writeState(
        context,
        (_allExpanded, Map<String, bool>.of(_expansionStates)),
        identifier: _inlineStorageIdentifier,
      );
    }
    super.deactivate();
  }

  @override
  void dispose() {
    unawaited(_searchSubscription?.cancel());
    unawaited(_searchBloc.close());

    _searchScrollGeneration++;
    _commentatorScrollGeneration++;
    _cancelHeaderAnchor();
    _listController.dispose();
    _notesChangesSubscription?.cancel();
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
    _cancelHeaderAnchor();
    _listController.cancelPositioning();
    final generation = ++_searchScrollGeneration;
    _commentatorScrollGeneration++;
    _pendingScrollTarget = null;
    if (_totalSearchResultsNotifier.value == 0 || _orderedLinks.isEmpty) return;
    var cumulativeIndex = 0;
    Link? targetLink;
    for (final link in _orderedLinks) {
      final results = _searchResultsPerLink[_getLinkKey(link)] ?? 0;
      if (_currentSearchIndexNotifier.value < cumulativeIndex + results) {
        targetLink = link;
        break;
      }
      cumulativeIndex += results;
    }
    if (targetLink == null) return;
    final linkKey = _getLinkKey(targetLink);
    final groupTitle = utils.getTitleFromPath(targetLink.path2);
    if (!(_expansionStates[groupTitle] ?? _allExpanded)) {
      setState(() => _expansionStates[groupTitle] = true);
    }
    WidgetsBinding.instance.ensureVisualUpdate();
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || generation != _searchScrollGeneration) return;
    while (mounted && generation == _searchScrollGeneration) {
      final index = _linkFlatIndex[linkKey];
      if (index == null || !_itemScrollController.isAttached) return;
      await _itemScrollController.jumpToAsync(index: index, alignment: 0.1);
      if (_linkFlatIndex[linkKey] == index) return;
    }
  }

  void _cancelSearchNavigation() {
    _cancelHeaderAnchor();
    _searchScrollGeneration++;
    _listController.cancelPositioning();
  }

  late final CommentarySearchBloc _searchBloc = CommentarySearchBloc(
    keyOf: _getLinkKey,
  );
  StreamSubscription<CommentarySearchState>? _searchSubscription;

  void _scheduleSearchCompute() {
    final internalQuery = widget.showSearch ? _searchQueryNotifier.value : '';
    final blocState = context.read<TextBookBloc>().state;
    _searchBloc.add(
      CommentarySearchRequested(
        links: _orderedLinks,
        query: internalQuery.isNotEmpty
            ? internalQuery
            : widget.highlightQueryListenable?.value ?? '',
        displayProfile: blocState is TextBookLoaded
            ? blocState.commentaryDisplayProfile
            : TextDisplayProfile.defaults,
        includeSnippets: widget.externalSearchSnippetsNotifier != null,
      ),
    );
  }

  void _applySearchState(CommentarySearchState state) {
    if (!mounted) return;
    if (state.counts.isEmpty) setState(() {});
    _searchResultOffsets = null;
    _totalSearchResultsNotifier.value = state.total;
    if (_currentSearchIndexNotifier.value >= state.total && state.total > 0) {
      _currentSearchIndexNotifier.value = 0;
    }
    _publishExternalState();
  }

  void _updateSearchResultsCount(Link link, int count, int generation) {
    if (!mounted) return;
    _searchBloc.add(
      CommentarySearchReported(
        generation: generation,
        key: _getLinkKey(link),
        count: count,
      ),
    );
  }

  void _updateSearchSnippets(Link link, List<String> snippets, int generation) {
    if (!mounted) return;
    _searchBloc.add(
      CommentarySearchReported(
        generation: generation,
        key: _getLinkKey(link),
        snippets: snippets,
      ),
    );
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
      key: _headerKeys.putIfAbsent(group.bookTitle, GlobalKey.new),
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
    final generation = _searchBloc.generation;
    final key = _getLinkKey(link);
    // שומרים את הרשימה בזמן חישוב הסדר, אך לא מציירים קישור שכבר הוסר.
    if (!_itemKeys.containsKey(key)) return const SizedBox.shrink();
    return _CommentaryLinkItem(
      key: ValueKey(key),
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
      updateSearchResultsCount: (link, count) =>
          _updateSearchResultsCount(link, count, generation),
      updateSearchSnippets: widget.externalSearchSnippetsNotifier != null
          ? (link, snippets) =>
                _updateSearchSnippets(link, snippets, generation)
          : null,
      highlightQueryListenable: widget.highlightQueryListenable,
      itemKeys: _itemKeys,
      getLinkKey: _getLinkKey,
      multiItemCopyGuard: _multiItemCopyGuard,
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
        selectionLink: selectionSpansMultipleItems(_itemKeys)
            ? null
            : _lastSelectedLink.value ?? _singleSelectedLink(),
        copyGuard: _multiItemCopyGuard,
      );
    } else {
      _savedSelectedText.value = null;
      _lastSelectedLink.value = null;
      widget.selectionSyncController?.clear(_selectionOwner);
    }
  }

  /// משחזר מעברי שורה בטקסט נבחר רב-שורתי (Flutter מחזיר טקסט שטוח), לפי הטקסט
  /// המרונדר המוטמן של המפרשים המוצגים. אם לא נמצא — מחזיר את הטקסט כמות שהוא.
  String? _restoreLineBreaks(String? flat) => restoreCommentaryLineBreaks(
    flat,
    orderedKeys: _orderedLinks.map(_getLinkKey),
    titlesByKey: _renderedTitleByKey,
    textsByKey: _renderedTextByKey,
  );

  Widget? _lastView;

  /// חלונית סגורה נשארת בעץ; בלי זה כל גלילה בספר טוענת ובונה את מפרשי הקטע.
  Widget Function(BuildContext, TextBookLoaded) _skipWhilePaneClosed(
    Widget Function(BuildContext, TextBookLoaded) build,
  ) => (context, state) {
    if (widget.isPaneOpen || _lastView == null || _hasPendingAnchorScroll) {
      return _lastView = build(context, state);
    }
    return _lastView!;
  };

  @override
  Widget build(BuildContext context) {
    super.build(context);
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
            // שורות קבועות (מפרש מתחת לשורה) אינן תלויות בגלילה.
            (widget.indexes == null &&
                !listEquals(previous.visibleIndices, current.visibleIndices)) ||
            previous.selectedIndex != current.selectedIndex ||
            !setEquals(previous.selectedIndices, current.selectedIndices) ||
            previous.fontSize != current.fontSize ||
            previous.bodyDisplayProfile != current.bodyDisplayProfile ||
            previous.commentaryDisplayProfile !=
                current.commentaryDisplayProfile ||
            _commentaryCopyProfile(previous) != _commentaryCopyProfile(current);
      },
      loadingWidget: const Center(),
      builder: _skipWhilePaneClosed((context, state) {
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
                  dbNotes: state.bookNotes,
                  decorateBody: (line, note, body) =>
                      noteBodyWithAnchors(state, line, note, body),
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
                _orderedLinks = [];
                _scheduleSearchCompute();
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
                  icon: OtzariaIcons.links_24_regular,
                  title: hasAnyCommentaryLinks
                      ? 'לא נמצאו מפרשים מהנבחרים לקטע זה'
                      : 'לא נמצאו מפרשים לקטע הנבחר',
                );
              }

              final commentaryWidget = FutureBuilder<List<Link>>(
                future: _getCachedLinks(
                  currentIndexes,
                  state.links,
                  selectedCommentators,
                  effectiveTypes,
                ),
                builder: (context, thisLinksSnapshot) {
                  final linksReady =
                      thisLinksSnapshot.connectionState == ConnectionState.done;
                  if (!linksReady) _groupsReady = false;
                  if (!thisLinksSnapshot.hasData) {
                    // רק אם יש קישורים רלוונטיים, מציג אנימציית טעינה
                    return _buildSkeletonLoading();
                  }
                  if (thisLinksSnapshot.data!.isEmpty) {
                    _orderedLinks = [];
                    _scheduleSearchCompute();
                    if (linksReady) _pendingScrollTarget = null;
                    // רשימה ריקה כאן נובעת מסינון הסוגים בלבד (יש קישורים
                    // רלוונטיים), ולכן מסבירים במקום להציג ריק בלי הסבר.
                    if (effectiveTypes.isEmpty) return const SizedBox.shrink();
                    return const OtzariaEmptyState(
                      isCompact: true,
                      icon: OtzariaIcons.links_24_regular,
                      title: 'לא נמצאו מפרשים מהסוגים שנבחרו',
                    );
                  }
                  final data = thisLinksSnapshot.data!;

                  // שומר את הסדר של ה-links לצורך חישוב אינדקס החיפוש
                  _orderedLinks = data;
                  _searchResultOffsets = null;
                  if (_pendingScrollTarget != null) {
                    _schedulePendingCommentatorScroll();
                  }

                  _scheduleSearchCompute();
                  _syncItemKeys(data);
                  pruneCommentaryExpansionStates(_expansionStates, data);

                  // מיירט גם את CopySelectionTextIntent, ולא רק את צירוף
                  // המקשים: בלעדיו Ctrl+C נופל להעתקת ברירת המחדל של Flutter,
                  // שכותבת ללוח את הבחירה כמות שהיא — גם כשהיא ריקה (#674).
                  return SelectionCopyShortcuts(
                    onCopy: () async {
                      // בחירה החוצה כמה מפרשים — לא מייחסים כותרת מקור
                      // (היא הייתה משתייכת למפרש בודד בלבד).
                      final link = selectionSpansMultipleItems(_itemKeys)
                          ? null
                          : _lastSelectedLink.value ?? _singleSelectedLink();
                      final guard = await _multiItemCopyGuard();
                      if (!context.mounted) return;
                      await ContextMenuUtils.copyFormattedText(
                        context: context,
                        savedSelectedText: _restoreLineBreaks(
                          _savedSelectedText.value,
                        ),
                        fontSize: widget.fontSize,
                        link: link,
                        protection: guard?.protection,
                        segmentCount: guard?.segmentCount,
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
                      child: FutureBuilder<List<CommentaryGroup>>(
                        future: _getCachedGroups(data),
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            _groupsReady = false;
                            _pendingScrollTarget = null;
                            return Center(
                              child: Text('שגיאה: ${snapshot.error}'),
                            );
                          }
                          final bookScope = (
                            BookIdentity.keyOf(state.book),
                            state.book.versionTitle,
                          );
                          final resolved =
                              snapshot.connectionState == ConnectionState.done
                              ? snapshot.data
                              : null;
                          _groupsReady = linksReady && resolved != null;
                          final groups =
                              resolved ??
                              (_lastResolvedGroupBook == bookScope &&
                                      listEquals(
                                        _lastResolvedGroupIndexes,
                                        currentIndexes,
                                      )
                                  ? _lastResolvedGroups
                                  : null);
                          if (groups == null) return _buildSkeletonLoading();
                          if (_groupsReady) {
                            _lastResolvedGroups = groups;
                            _lastResolvedGroupBook = bookScope;
                            _lastResolvedGroupIndexes = List.of(currentIndexes);
                          }
                          for (final group in groups) {
                            final groupKey = group.bookTitle;
                            _expansionStates.putIfAbsent(
                              groupKey,
                              () => _allExpanded,
                            );
                          }
                          final flatItems = _buildFlatItems(groups);
                          // מפת היעדים מתעדכנת רק אחרי שהקבוצות מוכנות.
                          if (_pendingScrollTarget != null) {
                            _schedulePendingCommentatorScroll();
                          }

                          final listView = ScrollablePositionedList.builder(
                            itemScrollController: _itemScrollController,
                            itemPositionsListener: _itemPositionsListener,
                            listController: _listController,
                            restorePosition: widget.shrinkWrap,
                            findChildIndexCallback: (key) =>
                                _flatIndexByKey[key],
                            initialScrollIndex: flatItems.isEmpty
                                ? 0
                                : _lastScrollIndex.clamp(
                                    0,
                                    flatItems.length - 1,
                                  ),
                            physics: const ClampingScrollPhysics(),
                            shrinkWrap: widget.shrinkWrap,
                            itemCount: flatItems.length,
                            itemBuilder: (context, index) {
                              final item = flatItems[index];
                              final link = item.link;
                              final child = link == null
                                  ? _buildGroupHeader(item.group)
                                  : _buildLinkItem(item.group, link, state);
                              return KeyedSubtree(
                                key: _flatItemKey(item),
                                child: item.showDivider
                                    ? Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          child,
                                          const Divider(height: 1),
                                        ],
                                      )
                                    : child,
                              );
                            },
                          );

                          // ProgressiveScroll עוטף את SelectionArea (מעליו),
                          // כך שגלילת החיצים נקלטת גם כש-SelectableRegion הוא
                          // ה-primaryFocus — האירוע מתפשט כלפי מעלה דרכו.
                          return ProgressiveScroll(
                            focusNode: _focusNode,
                            autofocus: widget.autofocus,
                            scrollController: _itemScrollController,
                            onNavigationStart: _cancelPendingNavigation,
                            maxSpeed: 10000.0,
                            curve: 10.0,
                            accelerationFactor: 312.5,
                            onKeyEvent: (_, event) =>
                                ContextMenuUtils.reportCommentaryErrorShortcut(
                                  context,
                                  event,
                                  link:
                                      _lastSelectedLink.value ??
                                      _singleSelectedLink(),
                                  selectedText: _savedSelectedText.value,
                                  fontSize: widget.fontSize,
                                ),
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
                                  itemCount: flatItems.length,
                                  onNavigationStart: _cancelPendingNavigation,
                                  child: SmoothWheelScroll(
                                    child: constrainToContentWidth(
                                      _trackHeaderScroll(listView),
                                      widget.contentMaxWidth,
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
              children: [Flexible(fit: FlexFit.loose, child: buildList())],
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
              Flexible(fit: FlexFit.loose, child: buildList()),
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
                      onPressed: toggleAllExpanded,
                    ),
                  ),
                ),
              // הרשימה
              Flexible(child: buildList()),
            ],
          );
        }
      }),
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
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Row(
          children: [
            AnimatedRotation(
              turns: isExpanded ? -0.25 : 0,
              duration: const Duration(milliseconds: 200),
              child: RtlIcon(
                FluentIcons.chevron_left_24_regular,
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
                      fontFamily: AppFonts.renderFontFamily(
                        settingsState.commentatorsFontFamily,
                      ),
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
  final Future<CommentaryCopyGuard?> Function() multiItemCopyGuard;
  final ValueListenable<String?> savedSelectedTextListenable;
  final ValueListenable<Link?> lastSelectedLinkListenable;

  /// הערות ספר המפרש. אותו Future משותף לכל קטעי המפרש בקבוצה.
  final Future<List<PersonalNote>> personalNotes;

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
    required this.multiItemCopyGuard,
    required this.savedSelectedTextListenable,
    required this.lastSelectedLinkListenable,
    required this.personalNotes,
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
  Future<void> _copySelection(
    BuildContext menuContext,
    String? savedText,
    Link link, {
    bool removeNikud = false,
  }) async {
    final guard = await widget.multiItemCopyGuard();
    if (!menuContext.mounted) return;
    await ContextMenuUtils.copyFormattedText(
      context: menuContext,
      savedSelectedText: _restoreLineBreaks(savedText),
      fontSize: widget.fontSize,
      link: link,
      removeNikud: removeNikud,
      protection: guard?.protection,
      segmentCount: guard?.segmentCount,
    );
  }

  /// פריטי התוספים בהקשרי המפרש. עם סימון — על המפרש המסומן, כמו בהעתקה.
  List<AppContextMenuEntry> _pluginEntries(
    BuildContext menuContext,
    String? selectedText,
  ) {
    if (!hasPluginContextMenuItems) return const [];
    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded) return const [];
    final text = _restoreLineBreaks(selectedText) ?? '';
    final link = text.trim().isEmpty
        ? widget.link
        : widget.lastSelectedLinkListenable.value ?? widget.link;
    return buildCommentaryPluginMenuEntries(
      target: commentaryTargetForLink(link),
      mainBook: (
        book: state.book,
        currentRef: state.currentTitle,
        sectionIndex: link.index1 - 1,
        pageNumber: null,
      ),
      selectedText: text,
      // בחירה החוצה כמה מפרשים כפופה למגבלה המחמירה שביניהם, כמו בהעתקה.
      copyGuard: () async =>
          await widget.multiItemCopyGuard() ??
          (
            protection: await BookProtectionRepository.instance.forLink(link),
            segmentCount: countTextSegments(text),
          ),
      menuContext: menuContext,
    );
  }

  String? _restoreLineBreaks(String? text) =>
      (widget.restoreLineBreaks ?? (s) => s)(text);

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
                    final markerText = link.anchorStart != null
                        ? anchorMarkerText(link)
                        : null;
                    if (!showTitle && markerText == null) {
                      // דיווח ריק דורס כותרת שדווחה קודם — לשחזור העתקה נכון.
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        widget.onLinkTitleRendered?.call(link, '');
                      });
                      return const SizedBox.shrink();
                    }
                    if (!showTitle) {
                      displayTitle = markerText!;
                    } else if (markerText != null) {
                      displayTitle = '$markerText $displayTitle';
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
                      widget.onLinkTitleRendered?.call(link, reportedTitle);
                    });
                    return Text(
                      displayTitle,
                      style: TextStyle(
                        fontSize: widget.fontSize * 0.75,
                        fontWeight: FontWeight.normal,
                        fontFamily: AppFonts.renderFontFamily(
                          settingsState.commentatorsFontFamily,
                        ),
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
                      onCopySelected: () => _copySelection(
                        menuCtx,
                        savedTextAtBuild,
                        // במצב הפאנל/כרטיסייה אין מעקב פר-פריט אחר
                        // המפרש הנבחר (אין SelectionArea פר-פריט), לכן
                        // נופלים חזרה ל-link של הפריט שעליו נפתח התפריט.
                        widget.lastSelectedLinkListenable.value ?? link,
                      ),
                      onCopySelectedWithoutNikud: () => _copySelection(
                        menuCtx,
                        savedTextAtBuild,
                        widget.lastSelectedLinkListenable.value ?? link,
                        removeNikud: true,
                      ),
                    )..addAll(_pluginEntries(menuCtx, savedTextAtBuild));
                  },
                  child: CommentaryContent(
                    key: ValueKey(widget.getLinkKey(link)),
                    link: link,
                    fontSize: widget.fontSize,
                    openBookCallback: widget.openBookCallback,
                    displayProfile: widget.displayProfile,
                    searchQuery: searchQuery,
                    currentSearchIndex: currentSearchIndex,
                    onSearchResultsCountChanged:
                        (widget.showSearch ||
                            widget.highlightQueryListenable != null)
                        ? (count) =>
                              widget.updateSearchResultsCount(link, count)
                        : null,
                    onSearchSnippetsChanged:
                        widget.showSearch && widget.updateSearchSnippets != null
                        ? (snippets) =>
                              widget.updateSearchSnippets!(link, snippets)
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

/// עוגני הקישורים של שורה [lineIndex] בספר, בסדר שה-href של הסמנים מפנה אליו.
List<Link> _bookAnchorLinksAt(TextBookLoaded state, int lineIndex) =>
    (state.linksByLine[lineIndex + 1] ?? const <Link>[])
        .where((link) => link.anchorStart != null)
        .toList();

/// גוף ההערה [note] של שורה [lineIndex] עם חלקי עוגני השורה שבו, כמו בגוף הספר.
@visibleForTesting
String noteBodyWithAnchors(
  TextBookLoaded state,
  int lineIndex,
  int note,
  String body,
) {
  if (!state.bodyDisplayProfile.showAnchorMarkers ||
      state.book.versionTitle != null) {
    return body;
  }
  final anchorLinks = _bookAnchorLinksAt(state, lineIndex);
  if (anchorLinks.isEmpty) return body;
  return injectLinkAnchorMarkers(
    rawLine: body,
    anchorLinks: anchorLinks,
    styleIndexByCommentator: anchorStyleIndexByCommentator(anchorLinks),
    lineIndex: lineIndex,
    notes: state.bookNotes.notesAt(lineIndex),
    note: note,
  );
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
  // onExit של ספאן מגיע גם אחרי שהווידג'ט הוסר מהעץ, וכבר אין context.
  late final AppWindowKeys _previewWindow;

  @override
  void initState() {
    super.initState();
    _previewWindow = AppWindowKeys.of(context);
  }

  void _onNotesSelectionChanged(String? text) {
    _selectedText = text;
    if (text != null && text.trim().isNotEmpty) {
      widget.selectionSyncController?.activate(
        _selectionOwner,
        selectionText: text,
        copyGuard: () async => (
          protection: widget.state.protection,
          segmentCount: countTextSegments(text),
        ),
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

  /// הקישור של סמן `otzaria://anchor?ref=<line>_<i>` שבגוף הערה.
  Link? _anchorLink(String url) {
    final parts = Uri.tryParse(url)?.queryParameters['ref']?.split('_');
    if (parts == null || parts.length != 2) return null;
    final line = int.tryParse(parts[0]);
    final index = int.tryParse(parts[1]);
    if (line == null || index == null || index < 0) return null;
    final links = _bookAnchorLinksAt(widget.state, line);
    return index < links.length ? links[index] : null;
  }

  void _openAnchor(String url) {
    final link = _anchorLink(url);
    if (link == null) return;
    LinkPreviewOverlay.dismiss(window: _previewWindow);
    openLinkTarget(link, (tab) => widget.openBookCallback(tab));
  }

  void _previewAnchor(String url, Offset globalPosition) {
    final link = _anchorLink(url);
    if (link == null) return;
    LinkPreviewOverlay.cancelScheduledHide(AppWindowKeys.of(context));
    LinkPreviewOverlay.show(
      context,
      link: link,
      globalPosition: globalPosition,
      hoverMode: true,
      displayProfile: widget.displayProfile,
      onOpen: () => _openAnchor(url),
    );
  }

  /// ההערות הן טקסט הספר עצמו: בספר מוגן Ctrl+C עובר דרך מגבלת ההעתקה.
  Widget _notesCopyWrapper({required Widget child}) {
    final protection = widget.state.protection;
    if (!protection.isProtected) return SelectionCutFallthrough(child: child);
    return SelectionCopyShortcuts(
      onCopy: () => ContextMenuUtils.copyFormattedText(
        context: context,
        savedSelectedText: _selectedText,
        fontSize: widget.fontSize,
        protection: protection,
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, settingsState) {
        // SelectionArea משלו: הרשימה הזו מוחזרת *מחוץ* ל-SelectionArea של
        // רשימת המפרשים (שנבנה רק סביב ה-ListView), ולכן בלעדיו לא ניתן
        // לבחור טקסט בהערות כלל.
        return _notesCopyWrapper(
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
                      protection: widget.state.protection,
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
                        protection: widget.state.protection,
                      ),
                    ),
                  if (widget.state.book.isOfficialLibraryBook) ...[
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
                            fontFamily: AppFonts.renderFontFamily(
                              settingsState.commentatorsFontFamily,
                            ),
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
                            onAnchorTap: _openAnchor,
                            onAnchorHover: _previewAnchor,
                            onAnchorHoverExit: (_) =>
                                LinkPreviewOverlay.scheduleHide(_previewWindow),
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
