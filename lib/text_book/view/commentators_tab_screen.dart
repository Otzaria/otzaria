import 'package:flutter/material.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/text_book/utils/category_settings_utils.dart';
import 'package:otzaria/text_book/utils/commentary_type_filter.dart';
import 'package:otzaria/text_book/utils/commentator_group_builder.dart';
import 'package:otzaria/text_book/utils/toc_unit_label.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/bookmarks/view/bookmark_screen.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/core/messages/notes_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/models/commentators_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/commentary_list_base.dart';
import 'package:otzaria/widgets/commentary/commentary_search_results_list.dart';
// מיוצא כדי שטסטי הכרטיסייה יייבאו אותו מנקודה אחת.
export 'package:otzaria/widgets/commentary/commentary_search_results_list.dart'
    show resolveSelectedSnippetGlobalIndex;
import 'package:otzaria/utils/text/ref_helper.dart';
import 'package:otzaria/widgets/lists/commentators_selection_panel.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/widgets/layout/reading_area_width.dart';
import 'package:otzaria/widgets/lists/nav_tree_tile.dart';
import 'package:otzaria/widgets/navigation/nav_panel_search.dart';
import 'package:otzaria/widgets/navigation/nav_side_panel.dart';
import 'package:otzaria/widgets/navigation/responsive_action_bar.dart';
import 'package:otzaria/widgets/navigation/app_top_bar.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria/widgets/navigation/search_pane_base.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/widgets/navigation/reader_nav_center.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

const _kAllChapter = -1;

/// אינדקס השורה האחרונה של [chapter] ברשימת [chapters].
///
/// פרק שאינו האחרון נתחם ע"י תחילת הפרק העוקב פחות 1. לפרק האחרון אין פרק
/// עוקב לתחום אותו, ולכן הגבול הוא שורת התוכן האחרונה ([contentLength] - 1).
/// זה מקור-האמת היחיד לגבול הפרק — בלעדיו "כל הדף" בדף האחרון זוהה כשורה
/// בודדת (ללא מפרשים) ונוצרו פסקאות רפאים עד שורה 200.
@visibleForTesting
int chapterEndLineIndex(
  List<TocEntry> chapters,
  TocEntry chapter,
  int contentLength,
) {
  final ci = chapters.indexOf(chapter);
  if (ci >= 0 && ci + 1 < chapters.length) {
    return chapters[ci + 1].index - 1;
  }
  return contentLength - 1;
}

/// קובע אם ה-listener של מסך המפרשים צריך לפעול עבור מעבר state נתון.
///
/// חובה לפעול במעבר הראשון למצב טעון (`TextBookLoading → TextBookLoaded`)
/// כדי לפתור את הפרק ההתחלתי — אחרת `effectiveIndexes` נשאר null והמפרשים
/// לא נטענים על המיקום הנוכחי. בנוסף פועל בכל שינוי של [TextBookLoaded.selectedIndex].
@visibleForTesting
bool shouldNotifyCommentatorsTabListener(
  TextBookState prev,
  TextBookState curr,
) {
  if (curr is! TextBookLoaded) return false;
  if (prev is! TextBookLoaded) return true;
  return prev.selectedIndex != curr.selectedIndex;
}

/// מצב הניווט של [CommentatorsTabScreen] — חשוף ל-testing כיחידה טהורה
/// כדי שניתן יהיה לוודא שהטרנספורמציות שמופעלות מ-onTap callbacks ב-UI
/// אינן משנות שדות שלא היו אמורות לשנות.
@immutable
@visibleForTesting
class CommentatorsNavSelection {
  final TocEntry? selectedChapter;
  final int selectedVerseIdx;
  final TocEntry? navExpandedChapter;

  const CommentatorsNavSelection({
    this.selectedChapter,
    this.selectedVerseIdx = _kAllChapter,
    this.navExpandedChapter,
  });

  CommentatorsNavSelection copyWith({
    Object? selectedChapter = _sentinel,
    int? selectedVerseIdx,
    Object? navExpandedChapter = _sentinel,
  }) {
    return CommentatorsNavSelection(
      selectedChapter: identical(selectedChapter, _sentinel)
          ? this.selectedChapter
          : selectedChapter as TocEntry?,
      selectedVerseIdx: selectedVerseIdx ?? this.selectedVerseIdx,
      navExpandedChapter: identical(navExpandedChapter, _sentinel)
          ? this.navExpandedChapter
          : navExpandedChapter as TocEntry?,
    );
  }

  static const Object _sentinel = Object();
}

/// טרנספורמציה ללחיצה על גוף שורת פרק (האזור הראשי, לא חץ הכיווץ).
/// אם הפרק כבר נבחר — no-op (מונע אובדן בחירה ע"י לחיצה כפולה).
/// אחרת בוחר את הפרק, מאפס את האינדקס לפרק שלם ומרחיב בניווט.
@visibleForTesting
CommentatorsNavSelection reduceChapterBodyTap(
  CommentatorsNavSelection state,
  TocEntry chapter,
) {
  if (state.selectedChapter == chapter) return state;
  return CommentatorsNavSelection(
    selectedChapter: chapter,
    selectedVerseIdx: _kAllChapter,
    navExpandedChapter: chapter,
  );
}

/// טרנספורמציה ללחיצה על חץ הכיווץ/פתיחה של פרק.
/// אסור לה לגעת ב-[CommentatorsNavSelection.selectedChapter] או
/// ב-[CommentatorsNavSelection.selectedVerseIdx] — אחרת חוזרת הרגרסיה
/// שבה כיווץ הניווט גרם לאיבוד בחירת המפרשים ולהודעת 'לא נמצאו מפרשים'.
@visibleForTesting
CommentatorsNavSelection reduceChevronTap(
  CommentatorsNavSelection state,
  TocEntry chapter,
) {
  return state.copyWith(
    navExpandedChapter: state.navExpandedChapter == chapter ? null : chapter,
  );
}

/// טרנספורמציה ללחיצה על תת-פריט בפרק כלשהו (יכול להיות שונה מהפרק הנבחר
/// אם המשתמש פתח פרק אחר בניווט). הפרק והאינדקס הנבחרים מתעדכנים לפי הקלט.
@visibleForTesting
CommentatorsNavSelection reduceSubItemTap(
  CommentatorsNavSelection state,
  TocEntry chapter,
  int verseIdx,
) {
  return CommentatorsNavSelection(
    selectedChapter: chapter,
    selectedVerseIdx: verseIdx,
    navExpandedChapter: chapter,
  );
}

/// קובע את הקטע שייבחר בפתיחת טאב המפרשים על [lineIndex].
///
/// [posVerseIdx] — התוצאה של איתור המיקום (`_findPos`): אינדקס הפסוק בפרק,
/// או [_kAllChapter] כשלא זוהה קטע ספציפי (למשל בפרק ללא תת-פרקים).
/// [chapterIndex] — אינדקס תחילת הפרק בתוכן. [hasChildren] — האם לפרק
/// יש תת-פרקים. [selectableParagraphOffsets] — היסטי הפסקאות הניתנים לבחירה.
///
/// בפרק ללא תת-פרקים גוזר את היסט הפסקה שנפתחה, אך רק אם הוא ניתן לבחירה —
/// כך שניווט 'קטע קודם' יתחיל מהקטע הנוכחי ולא ייתקע על היסט מסונן.
@visibleForTesting
int resolveOpenedVerseIdx({
  required int posVerseIdx,
  required int lineIndex,
  required int chapterIndex,
  required bool hasChildren,
  required List<int> selectableParagraphOffsets,
}) {
  if (posVerseIdx != _kAllChapter || hasChildren) return posVerseIdx;
  final paraIdx = lineIndex - chapterIndex;
  return selectableParagraphOffsets.contains(paraIdx) ? paraIdx : _kAllChapter;
}

/// יעד ניווט 'קטע קודם/הבא': אינדקס הפרק ברשימת הפרקים והקטע בתוכו
/// ([verseIdx] = [_kAllChapter] כשהפרק השכן ריק מקטעים ניתנים לבחירה).
@immutable
@visibleForTesting
class CommentatorsVerseStep {
  final int chapterIndex;
  final int verseIdx;
  const CommentatorsVerseStep(this.chapterIndex, this.verseIdx);

  @override
  bool operator ==(Object other) =>
      other is CommentatorsVerseStep &&
      other.chapterIndex == chapterIndex &&
      other.verseIdx == verseIdx;

  @override
  int get hashCode => Object.hash(chapterIndex, verseIdx);
}

/// חישוב טהור של יעד 'קטע קודם' (forward=false) או 'קטע הבא' (forward=true).
///
/// [selectablePerChapter] — הקטעים הניתנים לבחירה בכל פרק (לפי סדר הפרקים).
/// [chapterIndex]/[verseIdx] — המיקום הנוכחי. הניווט חוצה גבולות פרקים:
/// מתחילת פרק ל'קטע האחרון' של הפרק הקודם, ומסופו ל'קטע הראשון' של הבא.
/// מחזיר null כשאין יעד (קצה הספר).
@visibleForTesting
CommentatorsVerseStep? computeVerseStep(
  List<List<int>> selectablePerChapter,
  int chapterIndex,
  int verseIdx, {
  required bool forward,
}) {
  if (chapterIndex < 0 || chapterIndex >= selectablePerChapter.length) {
    return null;
  }
  final selectable = selectablePerChapter[chapterIndex];
  // "כל הפרק" ממוקם לפני הקטע הראשון (קדימה) ואחרי האחרון (אחורה).
  final pos = verseIdx == _kAllChapter
      ? (forward ? -1 : selectable.length)
      : selectable.indexOf(verseIdx);
  if (verseIdx != _kAllChapter && pos < 0) return null;

  final target = forward ? pos + 1 : pos - 1;
  if (target >= 0 && target < selectable.length) {
    return CommentatorsVerseStep(chapterIndex, selectable[target]);
  }

  // חצייה לפרק השכן.
  final neighborIndex = forward ? chapterIndex + 1 : chapterIndex - 1;
  if (neighborIndex < 0 || neighborIndex >= selectablePerChapter.length) {
    return null;
  }
  final neighbor = selectablePerChapter[neighborIndex];
  if (neighbor.isEmpty) {
    return CommentatorsVerseStep(neighborIndex, _kAllChapter);
  }
  return CommentatorsVerseStep(
    neighborIndex,
    forward ? neighbor.first : neighbor.last,
  );
}

/// רוחב חלונית הניווט בכרטיסיית המפרשים.
const double _kNavPaneWidth = 320;

class CommentatorsTabScreen extends StatefulWidget {
  final CommentatorsTab tab;
  final Function(OpenedTab) openBookCallback;

  const CommentatorsTabScreen({
    super.key,
    required this.tab,
    required this.openBookCallback,
  });

  @override
  State<CommentatorsTabScreen> createState() => _CommentatorsTabScreenState();
}

class _CommentatorsTabScreenState extends State<CommentatorsTabScreen>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  // שומר את ה-State חי כשהטאב יוצא מתחום ה-PageView, כדי שבחירת הפרק/קטע
  // (_selectedChapter / _selectedVerseIdx) לא תאבד במעבר לטאב אחר וחזרה.
  @override
  bool get wantKeepAlive => true;

  TocEntry? _selectedChapter;
  int _selectedVerseIdx = _kAllChapter;
  // הפרק שתתי-הפריטים שלו פרושים בניווט. עצמאי מ-_selectedChapter כדי
  // שניתן יהיה לעיין בניווט בפרק אחר מבלי לבטל את בחירת המפרשים הנוכחית.
  TocEntry? _navExpandedChapter;

  // ריבוי-בחירה ב'ניווט' (Ctrl+לחיצה): אינדקסי שורות נוספים להצגת מפרשים מעבר
  // לבחירה הראשית. ריק = בחירה יחידה רגילה. מתאפס בכל ניווט רגיל.
  final Set<int> _extraIndexes = <int>{};

  @visibleForTesting
  CommentatorsNavSelection get debugNavSelection => CommentatorsNavSelection(
    selectedChapter: _selectedChapter,
    selectedVerseIdx: _selectedVerseIdx,
    navExpandedChapter: _navExpandedChapter,
  );

  /// הכפתורים שולטים במצב המפרשים. הבחירה אינה נשמרת פר-ספר — קובץ ההגדרות
  /// משותף עם כרטיסיית הטקסט, ושמירה כאן הייתה דורסת את הטקסט הראשי שם.
  void _toggleCommentaryNikud(BuildContext context, TextBookLoaded state) {
    context.read<TextBookBloc>().add(
      ToggleNikud(!state.commentaryRemoveNikud, applyToCommentaries: true),
    );
  }

  void _toggleCommentaryPunctuation(
    BuildContext context,
    TextBookLoaded state,
  ) {
    context.read<TextBookBloc>().add(
      TogglePunctuation(
        !state.commentaryRemovePunctuation,
        applyToCommentaries: true,
      ),
    );
  }

  /// מחיל מצב חדש שחושב ע"י אחד הרדוסרים הטהורים (ראה [reduceChevronTap]
  /// וחבריו). מבטיח שכל הנתיבים שמשנים את מצב הניווט עוברים דרך אותו צינור.
  void _applyNavSelection(
    CommentatorsNavSelection next, {
    bool clearMulti = true,
  }) {
    setState(() {
      _selectedChapter = next.selectedChapter;
      _selectedVerseIdx = next.selectedVerseIdx;
      _navExpandedChapter = next.navExpandedChapter;
      // ניווט רגיל מאפס את ריבוי-הבחירה (לחיצת chevron מעבירה clearMulti: false).
      if (clearMulti) _extraIndexes.clear();
    });
  }

  /// האינדקסים האפקטיביים להצגת מפרשים: איחוד הבחירה הראשית עם ריבוי-הבחירה
  /// (Ctrl+לחיצה ב'ניווט'). כשאין ריבוי-בחירה — הבחירה הראשית בלבד.
  List<int>? _effectiveIndexes(List<TocEntry> chapters, int contentLength) {
    final primary = _computeIndexes(
      chapters,
      _selectedChapter,
      _selectedVerseIdx,
      contentLength,
    );
    if (_extraIndexes.isEmpty) return primary;
    return <int>{...?primary, ..._extraIndexes}.toList()..sort();
  }

  /// Ctrl+לחיצה על תת-פריט: מוסיף/מסיר את שורותיו מריבוי-הבחירה (toggle).
  void _ctrlToggleSubItem(
    int verseIdx,
    TocEntry chapter,
    List<TocEntry> chapters,
  ) {
    final state = widget.tab.bloc.state;
    final contentLength = state is TextBookLoaded ? state.content.length : 0;
    final idxs = _computeIndexes(chapters, chapter, verseIdx, contentLength);
    if (idxs == null || idxs.isEmpty) return;
    setState(() {
      if (idxs.every(_extraIndexes.contains)) {
        _extraIndexes.removeAll(idxs);
      } else {
        // שמירת הבחירה הראשית הנוכחית כחלק מהאיחוד לפני הוספת הקטע החדש.
        final primary = _computeIndexes(
          chapters,
          _selectedChapter,
          _selectedVerseIdx,
          contentLength,
        );
        if (primary != null) _extraIndexes.addAll(primary);
        _extraIndexes.addAll(idxs);
      }
    });
    _triggerLinkLoad(idxs);
  }

  /// האם שורותיו של תת-פריט נמצאות בריבוי-הבחירה (להדגשה ב'ניווט').
  bool _isSubItemInMulti(
    int verseIdx,
    TocEntry chapter,
    List<TocEntry> chapters,
  ) {
    if (_extraIndexes.isEmpty) return false;
    final state = widget.tab.bloc.state;
    final contentLength = state is TextBookLoaded ? state.content.length : 0;
    final idxs = _computeIndexes(chapters, chapter, verseIdx, contentLength);
    if (idxs == null || idxs.isEmpty) return false;
    return idxs.any(_extraIndexes.contains);
  }

  // גלילת רשימת הניווט לפרק הנבחר בעת פתיחת הפאנל/מעבר ללשונית הניווט.
  final ItemScrollController _navScrollController = ItemScrollController();
  // ה-items האחרונים שנבנו ברשימת הניווט, לאיתור מיקום הפרק הנבחר.
  List<_TocListItem> _navItems = const [];

  final _commentaryKey = GlobalKey<CommentaryListBaseState>();
  // מצב פתיחה/כיווץ של כל המפרשים, מסונכרן עם CommentaryListBase
  final _allExpandedInChild = ValueNotifier<bool>(true);
  // בחירת סוגי המפרשים. חיה כאן ולא ב-CommentaryListBase, כי הצ׳יפים מוצגים
  // בלשונית הצדדית שמסך זה בונה בעוד הרשימה מסוננת ברכיב הבן.
  final _typeSelection = CommentaryTypeSelection();
  bool _navPaneOpen = false;
  bool _pinLeftPane = false;
  // רשימת המפרשים הנבחרים (עצמאית לחלונית זו, מסונכרנת פעם אחת עם מקור הפתיחה)
  List<String>? _selectedCommentatorsOverride;
  bool _navPaneAutoCloseQueued = false;
  final _commentarySearchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _tocSearchController = TextEditingController();
  final _externalCurrentIndex = ValueNotifier<int>(0);
  final _externalTotalResults = ValueNotifier<int>(0);
  final _externalSearchResultsByPath = ValueNotifier<Map<String, int>>({});
  final _externalSearchSnippets = ValueNotifier<List<CommentarySearchSnippet>>(
    [],
  );
  bool _initialChapterResolved = false;

  late final TabController _navTabController;

  /// פעולות החיפוש של לשוניות החלונית — מוזנות לסרגל שבסרגל העליון.
  final NavPanelSearchHost _searchHost = NavPanelSearchHost();

  // אינדקסי טאבים בסרגל הניווט הצדדי
  static const int _commentatorsTabIndex = 1;
  static const int _searchTabIndex = 2;

  @override
  void initState() {
    super.initState();
    _navTabController = TabController(length: 3, vsync: this);
    _navTabController.addListener(() {
      _searchHost.activeTab = _navTabController.index;
      if (_navTabController.index == _searchTabIndex) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _searchFocusNode.requestFocus();
        });
      } else if (_navTabController.index == 0) {
        // לשונית הניווט: גלילה לפרק הנבחר.
        _scrollNavToSelectedChapter();
      }
    });
    // בקשות לפתיחת בחירת מפרשים מ-CommentaryListBase מועברות ישירות אל
    // _openCommentatorsSelectionPane דרך onFilterOpenRequested (ראה build).
    // הבחירה חיה על הטאב עצמו כדי שתישמר לדיסק ותשוחזר אחרי הפעלה מחדש.
    final savedCommentators = widget.tab.selectedCommentators;
    if (savedCommentators != null) {
      _selectedCommentatorsOverride = List<String>.from(savedCommentators);
    }
    // טעינת הספר והמפרשים ב-BLoC העצמאי
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final settings = context.read<SettingsBloc>().state;
      widget.tab.bloc.add(
        LoadContent(
          fontSize: settings.fontSize,
          showSplitView: false,
          removeNikud: settings.defaultRemoveNikud,
          loadCommentators: true,
        ),
      );
    });

    // ממקד את חלונית המפרשים כשהטאב הופך פעיל (מעבר טאב) כדי שגלילה עם
    // החיצים תעבוד מיד בלי לחיצה.
    FocusRepository().registerTabContentFocusRequester(
      widget.tab,
      () => _commentaryKey.currentState?.requestScrollFocus(),
    );
  }

  @override
  void dispose() {
    if (!widget.tab.bloc.isClosed) {
      widget.tab.bloc.add(const ResetCommentaryDisplayOverrides());
    }
    FocusRepository().unregisterTabContentFocusRequester(widget.tab);
    _navTabController.dispose();
    _searchHost.dispose();
    _typeSelection.dispose();
    _commentarySearchController.dispose();
    _searchFocusNode.dispose();
    _tocSearchController.dispose();
    _externalCurrentIndex.dispose();
    _externalTotalResults.dispose();
    _externalSearchResultsByPath.dispose();
    _externalSearchSnippets.dispose();
    _allExpandedInChild.dispose();
    super.dispose();
  }

  List<TocEntry> _getChapters(List<TocEntry> toc) {
    final children = toc.expand((e) => e.children).toList();
    return children.isNotEmpty ? children : toc;
  }

  ({TocEntry? chapter, int verseIdx}) _findPos(
    List<TocEntry> chapters,
    int lineIndex,
  ) {
    final currentState = widget.tab.bloc.state;
    final content = currentState is TextBookLoaded
        ? currentState.content
        : const <String>[];
    TocEntry? bestChapter;
    int bestVerseIdx = _kAllChapter;
    for (final ch in chapters) {
      if (ch.index <= lineIndex) {
        bestChapter = ch;
        bestVerseIdx = _kAllChapter;
        for (int i = 0; i < ch.children.length; i++) {
          if (_isDuplicateChapterChild(
            ch,
            ch.children[i],
            _previewForChild(ch, ch.children[i], content),
          )) {
            continue;
          }
          if (ch.children[i].index <= lineIndex) {
            bestVerseIdx = i;
          } else {
            break;
          }
        }
        if (bestVerseIdx == _kAllChapter &&
            _isHeadingOnlyParagraphOffset(ch, 0, chapters, content) &&
            lineIndex == ch.index) {
          bestVerseIdx = _kAllChapter;
        }
      } else {
        break;
      }
    }
    return (chapter: bestChapter, verseIdx: bestVerseIdx);
  }

  List<int>? _computeIndexes(
    List<TocEntry> chapters,
    TocEntry? chapter,
    int verseIdx,
    int contentLength,
  ) {
    if (chapter == null) return null;

    if (verseIdx != _kAllChapter) {
      if (chapter.children.isNotEmpty) {
        // בחירת פסוק לפי TOC
        if (verseIdx < chapter.children.length) {
          final verse = chapter.children[verseIdx];
          if (verseIdx + 1 < chapter.children.length) {
            final nextIdx = chapter.children[verseIdx + 1].index;
            final count = nextIdx - verse.index;
            if (count > 1 && count <= 200) {
              return List.generate(count, (j) => verse.index + j);
            }
          }
          return [verse.index];
        }
      } else {
        // בחירת שורה/פסקה (ספרים ללא מבנה פסוק ב-TOC)
        // verseIdx = offset מתחילת הפרק
        return [chapter.index + verseIdx];
      }
    }

    // כל הפרק — מתחילת הפרק ועד שורתו האחרונה.
    final end = chapterEndLineIndex(chapters, chapter, contentLength);
    final count = end - chapter.index + 1;
    if (count > 0) {
      return List.generate(count.clamp(1, 3000), (j) => chapter.index + j);
    }
    return [chapter.index];
  }

  /// מחשב כמה שורות יש בפרק (לספרים ללא TOC ברמת פסוק)
  int _chapterLineCount(
    List<TocEntry> chapters,
    TocEntry chapter,
    int contentLength,
  ) {
    final end = chapterEndLineIndex(chapters, chapter, contentLength);
    return (end - chapter.index + 1).clamp(0, 200);
  }

  /// טוען את כל ה-links עבור הטווח הנוכחי דרך ה-BLoC העצמאי
  void _triggerLinkLoad(List<int> indices) {
    if (indices.isEmpty) return;
    widget.tab.bloc.add(LoadAllLinksForIndices(indices));
  }

  void _onChapterSelected(TocEntry ch, List<TocEntry> chapters) {
    _applyNavSelection(reduceSubItemTap(debugNavSelection, ch, _kAllChapter));
    _loadLinksForChapter(ch, chapters);
  }

  /// טעינת כל ה-links של הפרק (ללא שינוי state). מופרד מ-[_onChapterSelected]
  /// כדי שתת-פריט "כל הפרק" יוכל להפעיל את עדכון ה-state ע"י [reduceSubItemTap]
  /// ואז לטעון את ה-links בלי setState כפול.
  void _loadLinksForChapter(TocEntry ch, List<TocEntry> chapters) {
    final state = widget.tab.bloc.state;
    final contentLength = state is TextBookLoaded ? state.content.length : 0;
    final endIdx = chapterEndLineIndex(chapters, ch, contentLength);
    final count = (endIdx - ch.index + 1).clamp(1, 3000);
    _triggerLinkLoad(List.generate(count, (j) => ch.index + j));
  }

  void _resolveInitialChapter(TextBookLoaded state) {
    if (_initialChapterResolved) return;

    final chapters = _getChapters(state.tableOfContents);
    final lineIndex =
        state.selectedIndex ??
        (state.visibleIndices.isNotEmpty ? state.visibleIndices.first : 0);

    if (chapters.isEmpty) {
      _initialChapterResolved = true;
      _triggerLinkLoad([lineIndex]);
      return;
    }

    final pos = _findPos(chapters, lineIndex);
    if (pos.chapter == null) return;

    _initialChapterResolved = true;
    final chapter = pos.chapter!;
    final verseIdx = resolveOpenedVerseIdx(
      posVerseIdx: pos.verseIdx,
      lineIndex: lineIndex,
      chapterIndex: chapter.index,
      hasChildren: chapter.children.isNotEmpty,
      selectableParagraphOffsets: chapter.children.isEmpty
          ? _selectableParagraphOffsets(chapters, chapter, state.content)
          : const [],
    );
    if (verseIdx == _kAllChapter) {
      _onChapterSelected(chapter, chapters);
    } else {
      _selectInChapter(verseIdx, chapter, chapters);
    }
  }

  /// גוללת את רשימת הניווט לפרק הנבחר. נקראת בעת פתיחת הפאנל ומעבר
  /// ללשונית הניווט, שכן אין מי שיגרום לכך אחרת.
  void _scrollNavToSelectedChapter() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_navScrollController.isAttached) return;
      final chapter = _selectedChapter;
      if (chapter == null) return;
      final idx = _navItems.indexWhere(
        (it) => it.isChapter && it.chapter == chapter,
      );
      if (idx < 0) return;
      _navScrollController.scrollTo(
        index: idx,
        alignment: 0.4,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // נדרש ע"י AutomaticKeepAliveClientMixin
    return BlocProvider<TextBookBloc>.value(
      value: widget.tab.bloc,
      child: Builder(
        builder: (context) {
          return BlocConsumer<TextBookBloc, TextBookState>(
            listenWhen: shouldNotifyCommentatorsTabListener,
            listener: (context, state) {
              if (state is! TextBookLoaded) return;
              _resolveInitialChapter(state);
              final idx = state.selectedIndex;
              if (idx == null) return;
              final chapters = _getChapters(state.tableOfContents);
              final pos = _findPos(chapters, idx);
              if (pos.chapter != null) {
                _onChapterSelected(pos.chapter!, chapters);
              }
            },
            buildWhen: (prev, curr) {
              if (prev is TextBookLoaded && curr is TextBookLoaded) {
                return prev.fontSize != curr.fontSize ||
                    prev.tableOfContents != curr.tableOfContents ||
                    prev.links != curr.links ||
                    prev.availableCommentators != curr.availableCommentators ||
                    prev.removeNikud != curr.removeNikud ||
                    prev.commentaryRemoveNikud != curr.commentaryRemoveNikud ||
                    prev.removePunctuation != curr.removePunctuation ||
                    prev.commentaryRemovePunctuation !=
                        curr.commentaryRemovePunctuation;
              }
              return true;
            },
            builder: (context, state) {
              if (state is! TextBookLoaded) {
                return Scaffold(
                  body: Column(
                    children: [
                      AppTopBar(
                        leadingItems: [
                          AppTopBarItem(
                            widget: NavPanelToggleButton(
                              isOpen: false,
                              onToggle: () {},
                            ),
                          ),
                        ],
                        center: Text(
                          'מפרשים על ${widget.tab.sourceTab.book.title}',
                          style: AppTopBar.titleStyle(context),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Expanded(
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ],
                  ),
                );
              }

              final chapters = _getChapters(state.tableOfContents);

              final effectiveIndexes = _effectiveIndexes(
                chapters,
                state.content.length,
              );

              return Focus(
                autofocus: true,
                onKeyEvent: _handlePrintShortcut,
                child: Scaffold(
                  body: Column(
                    children: [
                      _buildAppBar(context, state, chapters),
                      Expanded(
                        child: Stack(
                          children: [
                            NavSidePanel(
                              isOpen: _navPaneOpen || _pinLeftPane,
                              onClose: () {
                                if (!_pinLeftPane) {
                                  setState(() => _navPaneOpen = false);
                                }
                              },
                              alignment: AlignmentDirectional.centerEnd,
                              paneWidth: _kNavPaneWidth,
                              minMainContentWidth: 400,
                              mainContent: _buildCommentaryMainContent(
                                context,
                                state,
                                effectiveIndexes,
                              ),
                              paneContent: NavPanelSearchScope(
                                host: _searchHost,
                                child: _buildNavPanel(
                                  context,
                                  state: state,
                                  chapters: chapters,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  /// בונה את תוכן המפרשים הראשי: עטוף ב-[SelectionArea] לאפשור בחירת טקסט
  /// בכל הרשימה הנגללת (בלעדיו מחוות הגרירה נבלעת ע"י הגלילה, כמו בפאנל
  /// המפוצל וב-PdfCommentaryPanel), וממורכז לפי הגדרת רוחב הטקסט.
  Widget _buildCommentaryMainContent(
    BuildContext context,
    TextBookLoaded state,
    List<int>? effectiveIndexes,
  ) {
    Widget listContentWithWidth(
      double? contentMaxWidth,
    ) => NotificationListener<UserScrollNotification>(
      onNotification: (notification) {
        if (notification.direction != ScrollDirection.idle &&
            _navPaneOpen &&
            !_pinLeftPane &&
            !_navPaneAutoCloseQueued) {
          _navPaneAutoCloseQueued = true;
          Future.microtask(() {
            if (!mounted) {
              _navPaneAutoCloseQueued = false;
              return;
            }
            if (_navPaneOpen && !_pinLeftPane) {
              setState(() {
                _navPaneOpen = false;
                _navPaneAutoCloseQueued = false;
              });
            } else {
              _navPaneAutoCloseQueued = false;
            }
          });
        }
        return false;
      },
      // אין SelectionArea חיצוני כאן: CommentaryListBase עוטף את הרשימה כולה
      // ב-SelectionArea יחיד משלו. קינון היה הופך את תוכן המפרשים ל"בלוק אטום"
      // שבחירת מקלדת (Shift+חץ) מדלגת עליו (עברה רק על שמות המפרשים).
      child: BlocBuilder<SettingsBloc, SettingsState>(
        builder: (context, settingsState) => CommentaryListBase(
          key: _commentaryKey,
          openBookCallback: widget.openBookCallback,
          fontSize: settingsState.commentatorsFontSize,
          indexes: effectiveIndexes,
          showSearch: true,
          autofocus: true,
          // shrinkWrap היה כופה layout של כל המפרשים בפריים אחד — פתיחה
          // איטית מאוד על קטע עם הרבה מפרשים (issue #844).
          shrinkWrap: false,
          useAvailableCommentators: _selectedCommentatorsOverride == null,
          selectedCommentatorsOverride: _selectedCommentatorsOverride,
          onSelectedCommentatorsOverrideChanged: _updateSelectedCommentators,
          onFilterOpenRequested: _openCommentatorsSelectionPane,
          externalSearchController: _commentarySearchController,
          externalCurrentIndexNotifier: _externalCurrentIndex,
          externalTotalResultsNotifier: _externalTotalResults,
          externalSearchResultsByPathNotifier: _externalSearchResultsByPath,
          externalSearchSnippetsNotifier: _externalSearchSnippets,
          externalAllExpandedNotifier: _allExpandedInChild,
          typeSelection: _typeSelection,
          personalNotesLoader: loadStoredPersonalNotes,
          contentMaxWidth: contentMaxWidth,
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        return BlocBuilder<SettingsBloc, SettingsState>(
          builder: (context, settingsState) {
            final textMaxWidth = textColumnMaxWidthOf(
              context,
              setting: settingsState.textMaxWidth,
              availableWidth: constraints.maxWidth,
            );

            // הרוחב עובר לתוך הרשימה ולא עוטף אותה מבחוץ, כדי שפס הגלילה
            // יישאר צמוד לדופן החלון.
            return listContentWithWidth(textMaxWidth > 0 ? textMaxWidth : null);
          },
        );
      },
    );
  }

  // ── ניווט בין פרקים ────────────────────────────────────────────────────────

  void _navigateToPrevChapter(List<TocEntry> chapters) {
    if (_selectedChapter == null) return;
    final ci = chapters.indexOf(_selectedChapter!);
    if (ci > 0) _onChapterSelected(chapters[ci - 1], chapters);
  }

  void _navigateToNextChapter(List<TocEntry> chapters) {
    if (_selectedChapter == null) return;
    final ci = chapters.indexOf(_selectedChapter!);
    if (ci >= 0 && ci + 1 < chapters.length) {
      _onChapterSelected(chapters[ci + 1], chapters);
    }
  }

  /// הקטעים הניתנים לבחירה בפרק (פסוקים אם יש children, אחרת היסטי פסקאות).
  List<int> _selectableForChapter(
    TocEntry chapter,
    List<TocEntry> chapters,
    List<String> content,
  ) {
    return chapter.children.isNotEmpty
        ? _selectableVerseIndices(chapter, content)
        : _selectableParagraphOffsets(chapters, chapter, content);
  }

  /// בוחר קטע (פסוק/פסקה) בפרק כלשהו, בהתאם לסוג הפרק.
  void _selectInChapter(int idx, TocEntry chapter, List<TocEntry> chapters) {
    if (chapter.children.isNotEmpty) {
      _selectVerseInChapter(idx, chapter, chapters);
    } else {
      _selectParaInChapter(idx, chapter, chapters);
    }
  }

  void _navigateVerse(List<TocEntry> chapters, {required bool forward}) {
    final chapter = _selectedChapter;
    if (chapter == null) return;
    final ci = chapters.indexOf(chapter);
    if (ci < 0) return;
    final currentState = widget.tab.bloc.state;
    final content = currentState is TextBookLoaded
        ? currentState.content
        : const <String>[];
    // computeVerseStep נוגע רק בפרק הנוכחי ובשכן בכיוון — שאר הפרקים ריקים
    // כדי לא לחשב selectable לכל הספר בכל לחיצה (חוסך O(N) בספרים גדולים).
    final neighborIndex = forward ? ci + 1 : ci - 1;
    final selectablePerChapter = List<List<int>>.generate(
      chapters.length,
      (i) => (i == ci || i == neighborIndex)
          ? _selectableForChapter(chapters[i], chapters, content)
          : const [],
    );
    final step = computeVerseStep(
      selectablePerChapter,
      ci,
      _selectedVerseIdx,
      forward: forward,
    );
    if (step == null) return;
    final target = chapters[step.chapterIndex];
    if (step.verseIdx == _kAllChapter) {
      _onChapterSelected(target, chapters);
    } else {
      _selectInChapter(step.verseIdx, target, chapters);
    }
  }

  void _navigateToPrevVerse(List<TocEntry> chapters) =>
      _navigateVerse(chapters, forward: false);

  void _navigateToNextVerse(List<TocEntry> chapters) =>
      _navigateVerse(chapters, forward: true);

  void _openSearchPane() {
    setState(() => _navPaneOpen = true);
    _navTabController.animateTo(_searchTabIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  void _openCommentatorsSelectionPane() {
    setState(() => _navPaneOpen = true);
    _navTabController.animateTo(_commentatorsTabIndex);
  }

  void _updateSelectedCommentators(List<String> list) {
    widget.tab.selectedCommentators = List<String>.from(list);
    setState(() => _selectedCommentatorsOverride = list);
  }

  /// מטפל בקיצור ההדפסה המוגדר — פעיל רק בכרטיסיית המפרשים.
  KeyEventResult _handlePrintShortcut(FocusNode node, KeyEvent event) {
    final printShortcut =
        Settings.getValue<String>('key-shortcut-print') ?? 'ctrl+p';
    if (ShortcutHelper.matchesShortcut(event, printShortcut)) {
      _commentaryKey.currentState?.printDisplayedCommentaries();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _addBookmark(
    BuildContext context,
    TextBookLoaded state,
    List<int>? effectiveIndexes,
  ) async {
    final fallbackIndex =
        state.selectedIndex ??
        (state.visibleIndices.isNotEmpty ? state.visibleIndices.first : 0);
    final index = effectiveIndexes?.isNotEmpty == true
        ? effectiveIndexes!.first
        : fallbackIndex;
    final ref = addBookTitleToRef(
      await refFromIndex(index, state.book.tableOfContents),
      state.book.title,
    );
    if (!mounted || !context.mounted) return;

    final commentatorsToShow =
        _selectedCommentatorsOverride ?? state.activeCommentators;
    final added = context.read<BookmarkBloc>().addBookmark(
      ref: 'מפרשים | $ref',
      book: state.book,
      index: index,
      commentatorsToShow: commentatorsToShow,
      targetKind: BookmarkTargetKind.commentators,
    );
    UiSnack.showQuick(
      added ? NotesMessages.bookmarkAdded : NotesMessages.bookmarkAlreadyExists,
    );
  }

  void _showBookmarksForCurrentBook(BuildContext context, Book book) {
    showDialog(
      context: context,
      builder: (_) => BookmarksDialog(bookFilter: book),
    );
  }

  // ── AppBar ─────────────────────────────────────────────────────────────────

  Widget _buildAppBar(
    BuildContext context,
    TextBookLoaded state,
    List<TocEntry> chapters,
  ) {
    return AppTopBar(
      minCenterWidth: ReaderNavCenter.minTitleWidth,
      leadingItems: [
        AppTopBarItem(
          flexible: true,
          widget: NavPanelSearchBar(
            host: _searchHost,
            isOpen: _navPaneOpen || _pinLeftPane,
            paneWidth: _kNavPaneWidth,
            isPinned: _pinLeftPane,
            onTogglePin: () => setState(() => _pinLeftPane = !_pinLeftPane),
          ),
        ),
        AppTopBarItem(
          widget: NavPanelToggleButton(
            isOpen: _navPaneOpen,
            onToggle: () {
              setState(() => _navPaneOpen = !_navPaneOpen);
              if (_navPaneOpen && _navTabController.index == 0) {
                _scrollNavToSelectedChapter();
              }
            },
          ),
        ),
      ],
      center: ReaderNavCenter(
        title: Text(
          'מפרשים על ${state.book.title}',
          style: AppTopBar.titleStyle(context),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
        ),
        prevMajorTooltip: 'הפרק הקודם',
        prevMinorTooltip: 'הקטע הקודם',
        nextMinorTooltip: 'הקטע הבא',
        nextMajorTooltip: 'הפרק הבא',
        onPrevMajor: () => _navigateToPrevChapter(chapters),
        onPrevMinor: () => _navigateToPrevVerse(chapters),
        onNextMinor: () => _navigateToNextVerse(chapters),
        onNextMajor: () => _navigateToNextChapter(chapters),
      ),
      trailingItems: [
        AppTopBarItem(
          flexible: true,
          widget: ResponsiveActionBar(
            overflowMenuOffset: const Offset(0, 8),
            actions: [
              // ניקוד
              ActionButtonData(
                widget: BarButton.icon(
                  tooltip: state.commentaryRemoveNikud
                      ? 'הצג ניקוד'
                      : 'הסתר ניקוד',
                  icon: state.commentaryRemoveNikud
                      ? OtzariaIcons.alef_with_score_24_regular
                      : OtzariaIcons.alef_deletion_24_regular,
                  compact: context.read<SettingsBloc>().state.compactMenuMode,
                  onPressed: () => _toggleCommentaryNikud(context, state),
                ),
                icon: state.commentaryRemoveNikud
                    ? OtzariaIcons.alef_with_score_24_regular
                    : OtzariaIcons.alef_deletion_24_regular,
                tooltip: state.commentaryRemoveNikud
                    ? 'הצג ניקוד'
                    : 'הסתר ניקוד',
                actionId: ToolbarActionId.nikud,
                onPressed: () => _toggleCommentaryNikud(context, state),
              ),
              // פיסוק — מוצג גם בתנ"ך, כי התוכן כאן הוא מפרשים
              ActionButtonData(
                widget: BarButton.icon(
                  tooltip: state.commentaryRemovePunctuation
                      ? 'הצג פיסוק'
                      : 'הסתר פיסוק',
                  icon: state.commentaryRemovePunctuation
                      ? OtzariaIcons.alef_with_punctuation_24_regular
                      : OtzariaIcons.alef_with_eraser_24_regular,
                  compact: context.read<SettingsBloc>().state.compactMenuMode,
                  onPressed: () => _toggleCommentaryPunctuation(context, state),
                ),
                icon: state.commentaryRemovePunctuation
                    ? OtzariaIcons.alef_with_punctuation_24_regular
                    : OtzariaIcons.alef_with_eraser_24_regular,
                tooltip: state.commentaryRemovePunctuation
                    ? 'הצג פיסוק'
                    : 'הסתר פיסוק',
                actionId: ToolbarActionId.punctuation,
                onPressed: () => _toggleCommentaryPunctuation(context, state),
              ),
              // הדפסת המפרשים המוצגים
              ActionButtonData(
                widget: BarButton.icon(
                  icon: FluentIcons.print_24_regular,
                  tooltip: 'הדפסה',
                  compact: context.read<SettingsBloc>().state.compactMenuMode,
                  onPressed: () =>
                      _commentaryKey.currentState?.printDisplayedCommentaries(),
                ),
                icon: FluentIcons.print_24_regular,
                tooltip: 'הדפסה',
                actionId: ToolbarActionId.print,
                onPressed: () =>
                    _commentaryKey.currentState?.printDisplayedCommentaries(),
              ),
              // חיפוש
              ActionButtonData(
                widget: BarButton.icon(
                  tooltip: 'חיפוש',
                  icon: OtzariaIcons.search_24_regular,
                  compact: context.read<SettingsBloc>().state.compactMenuMode,
                  onPressed: _openSearchPane,
                ),
                icon: OtzariaIcons.search_24_regular,
                tooltip: 'חיפוש',
                actionId: ToolbarActionId.search,
                onPressed: _openSearchPane,
              ),
              // כיווץ/הרחבת כל המפרשים — שולט במצב הגלובלי בתוך CommentaryListBase
              ActionButtonData(
                widget: ValueListenableBuilder<bool>(
                  valueListenable: _allExpandedInChild,
                  builder: (context, allExpanded, _) {
                    return BarButton.icon(
                      tooltip: allExpanded
                          ? 'כווץ את כל המפרשים'
                          : 'הרחב את כל המפרשים',
                      icon: allExpanded
                          ? FluentIcons.arrow_collapse_all_24_regular
                          : FluentIcons.arrow_expand_all_24_regular,
                      compact: context
                          .read<SettingsBloc>()
                          .state
                          .compactMenuMode,
                      onPressed: () =>
                          _commentaryKey.currentState?.toggleAllExpanded(),
                    );
                  },
                ),
                icon: _allExpandedInChild.value
                    ? FluentIcons.arrow_collapse_all_24_regular
                    : FluentIcons.arrow_expand_all_24_regular,
                tooltip: _allExpandedInChild.value
                    ? 'כווץ את כל המפרשים'
                    : 'הרחב את כל המפרשים',
                actionId: ToolbarActionId.expandAll,
                onPressed: () =>
                    _commentaryKey.currentState?.toggleAllExpanded(),
              ),
              ActionButtonData(
                widget: BarButton.icon(
                  tooltip: 'הוסף סימניה',
                  icon: FluentIcons.bookmark_add_24_regular,
                  compact: context.read<SettingsBloc>().state.compactMenuMode,
                  onPressed: () => _addBookmark(
                    context,
                    state,
                    _computeIndexes(
                      chapters,
                      _selectedChapter,
                      _selectedVerseIdx,
                      state.content.length,
                    ),
                  ),
                ),
                icon: FluentIcons.bookmark_add_24_regular,
                tooltip: 'הוסף סימניה',
                actionId: ToolbarActionId.bookmarkAdd,
                onPressed: () => _addBookmark(
                  context,
                  state,
                  _computeIndexes(
                    chapters,
                    _selectedChapter,
                    _selectedVerseIdx,
                    state.content.length,
                  ),
                ),
              ),
              // הגדל טקסט
              ActionButtonData(
                widget: BarButton.icon(
                  tooltip: 'הגדל את גודל הטקסט',
                  icon: FluentIcons.zoom_in_24_regular,
                  compact: context.read<SettingsBloc>().state.compactMenuMode,
                  onPressed: () => context.read<TextBookBloc>().add(
                    UpdateFontSize((state.fontSize + 3).clamp(15, 50)),
                  ),
                ),
                icon: FluentIcons.zoom_in_24_regular,
                tooltip: 'הגדל את גודל הטקסט',
                actionId: ToolbarActionId.zoomIn,
                onPressed: () => context.read<TextBookBloc>().add(
                  UpdateFontSize((state.fontSize + 3).clamp(15, 50)),
                ),
              ),
              // הקטן טקסט
              ActionButtonData(
                widget: BarButton.icon(
                  tooltip: 'הקטן את גודל הטקסט',
                  icon: FluentIcons.zoom_out_24_regular,
                  compact: context.read<SettingsBloc>().state.compactMenuMode,
                  onPressed: () => context.read<TextBookBloc>().add(
                    UpdateFontSize((state.fontSize - 3).clamp(15, 50)),
                  ),
                ),
                icon: FluentIcons.zoom_out_24_regular,
                tooltip: 'הקטן את גודל הטקסט',
                actionId: ToolbarActionId.zoomOut,
                onPressed: () => context.read<TextBookBloc>().add(
                  UpdateFontSize((state.fontSize - 3).clamp(15, 50)),
                ),
              ),
            ],
            alwaysInMenu: [
              ActionButtonData(
                widget: BarButton.icon(
                  tooltip: 'סימניות בספר זה',
                  icon: FluentIcons.bookmark_multiple_24_regular,
                  compact: context.read<SettingsBloc>().state.compactMenuMode,
                  onPressed: () =>
                      _showBookmarksForCurrentBook(context, state.book),
                ),
                icon: FluentIcons.bookmark_multiple_24_regular,
                tooltip: 'סימניות בספר זה',
                onPressed: () =>
                    _showBookmarksForCurrentBook(context, state.book),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── פאנל ניווט (paneContent) ───────────────────────────────────────────────

  Widget _buildNavPanel(
    BuildContext context, {
    required TextBookLoaded state,
    required List<TocEntry> chapters,
  }) {
    return Column(
      children: [
        NavPanelTabHeader(
          controller: _navTabController,
          tabs: const [
            (
              icon: OtzariaIcons.list_24_regular,
              iconFilled: OtzariaIcons.list_24_filled,
              label: 'ניווט',
            ),
            (
              icon: OtzariaIcons.apps_list_24_regular,
              iconFilled: OtzariaIcons.apps_list_24_filled,
              label: 'מפרשים',
            ),
            (
              icon: OtzariaIcons.search_24_regular,
              iconFilled: OtzariaIcons.search_24_filled,
              label: 'חיפוש',
            ),
          ],
        ),
        // ─── תוכן TabBarView ──────────────────────────────────────────
        Expanded(
          child: TabBarView(
            controller: _navTabController,
            children: [
              NavPanelSearchSlot(
                index: 0,
                child: _buildTocList(
                  context,
                  chapters: chapters,
                  content: state.content,
                  title: state.book.title,
                ),
              ),
              NavPanelSearchSlot(
                index: 1,
                child: _buildCommentatorsSelectionPanel(context, state),
              ),
              NavPanelSearchSlot(
                index: 2,
                child: _buildCommentarySearchPanel(context),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── פאנל בחירת מפרשים ─────────────────────────────────────────────────────

  Widget _buildCommentatorsSelectionPanel(
    BuildContext context,
    TextBookLoaded state,
  ) {
    final groups = state.commentatorGroups;
    final selected = _selectedCommentatorsOverride ?? state.activeCommentators;
    if (groups.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'טוען מפרשים...',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      );
    }
    final chapters = _getChapters(state.tableOfContents);
    final indexes =
        _effectiveIndexes(chapters, state.content.length) ?? const <int>[];
    final chipKeys = CommentaryTypeFilter.chipKeysForCommentators(
      links: state.links,
      selectedCommentators: selected,
    );
    final commentatorsByType = CommentaryTypeFilter.commentatorsByType(
      state.links,
    );
    return ValueListenableBuilder<Set<String>>(
      valueListenable: _typeSelection,
      builder: (context, selectedTypes, _) {
        final effectiveTypes = CommentaryTypeFilter.effectiveTypes(
          selectedTypes: selectedTypes,
          availableKeys: chipKeys,
        );
        return CommentatorsSelectionPanel(
          groups: groups,
          selectedCommentators: selected,
          bookTitle: state.book.title,
          rareCommentators: state.rareCommentators,
          lineRelevantCommentators: lineRelevantRareCommentators(
            rareCommentators: state.rareCommentators,
            currentIndexes: indexes,
            linksByLine: state.linksByLine,
          ),
          onSelectionChanged: _updateSelectedCommentators,
          typeChipKeys: CommentaryTypeFilter.visibleChipKeys(
            chipKeys: chipKeys,
            effectiveTypes: effectiveTypes,
          ),
          selectedTypeChips: effectiveTypes,
          typeChipLabelBuilder: LinkTypes.hebrewLabel,
          commentatorsByType: commentatorsByType,
          onTypeChipsChanged: (types) => _typeSelection.value = types,
          heCategories: bookCategoriesSource(state.book),
          onCategoryDefaultsSaved: () =>
              TextBookPerBookSettings.clearActiveCommentators(state.book),
        );
      },
    );
  }

  // ── פאנל חיפוש ────────────────────────────────────────────────────────────

  Widget _buildCommentarySearchPanel(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _commentarySearchController,
      builder: (_, val, _) {
        final hasQuery = val.text.isNotEmpty;
        return ValueListenableBuilder<int>(
          valueListenable: _externalTotalResults,
          builder: (_, total, _) => ValueListenableBuilder<int>(
            valueListenable: _externalCurrentIndex,
            builder: (_, current, _) =>
                ValueListenableBuilder<List<CommentarySearchSnippet>>(
                  valueListenable: _externalSearchSnippets,
                  builder: (context, snippets, _) {
                    return SearchPaneBase(
                      searchController: _commentarySearchController,
                      focusNode: _searchFocusNode,
                      hintText: 'חפש בתוך המפרשים המוצגים...',
                      isNoResults: hasQuery && total == 0,
                      resetSearchCallback: _commentarySearchController.clear,
                      resultCountString: hasQuery && total > 0
                          ? 'תוצאה ${current + 1} מתוך $total'
                          : null,
                      resultToolbar: hasQuery && total > 0
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                OtzariaSearchAction.prevResult(
                                  onPressed: current > 0
                                      ? () => _commentaryKey.currentState
                                            ?.navigateSearchPrev()
                                      : null,
                                ),
                                OtzariaSearchAction.nextResult(
                                  onPressed: current < total - 1
                                      ? () => _commentaryKey.currentState
                                            ?.navigateSearchNext()
                                      : null,
                                ),
                              ],
                            )
                          : null,
                      resultsWidget: _buildSearchResultsList(
                        context,
                        query: val.text,
                        snippets: snippets,
                        total: total,
                        currentIdx: current,
                      ),
                    );
                  },
                ),
          ),
        );
      },
    );
  }

  Widget _buildSearchResultsList(
    BuildContext context, {
    required String query,
    required List<CommentarySearchSnippet> snippets,
    required int total,
    required int currentIdx,
  }) {
    return CommentarySearchResultsList(
      query: query,
      snippets: snippets,
      currentIdx: currentIdx,
      onSnippetTap: (globalIndex) =>
          _commentaryKey.currentState?.navigateToGlobalIndex(globalIndex),
    );
  }

  // ── רשימת פרקים (לשונית ניווט) ────────────────────────────────────────────

  Widget _buildTocList(
    BuildContext context, {
    required List<TocEntry> chapters,
    required List<String> content,
    required String title,
  }) {
    if (chapters.isEmpty) {
      return const Center(child: Text('אין תוכן עניינים'));
    }

    final delegate = NavPanelSearchDelegate(
      controller: _tocSearchController,
      hintText: 'איתור כותרת...',
      onClear: () {},
    );

    return NavPanelSearchPublisher(
      delegate: delegate,
      child: Column(
        children: [
          if (!NavPanelSearch.isHoisted(context))
            NavPanelLocalSearchField(delegate: delegate),
          Expanded(
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _tocSearchController,
              builder: (context, val, _) {
                final query = val.text;
                final filteredChapters = query.isEmpty
                    ? chapters
                    : chapters.where((ch) => ch.text.contains(query)).toList();
                final items = [
                  _TocListItem.header(title),
                  ..._buildVisibleTocItems(filteredChapters, chapters, content),
                ];
                _navItems = items;
                return NavTreeFocusGroup(
                  child: ScrollablePositionedList.builder(
                    itemScrollController: _navScrollController,
                    itemCount: items.length,
                    padding: kNavTreeListPadding,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      if (item.isHeader) {
                        return NavTreeHeader(title: item.text!);
                      }
                      final isGroupStart = index == 1;
                      final isGroupEnd = index == items.length - 1;
                      if (item.isChapter) {
                        final ch = item.chapter!;
                        return NavTreeGroupCard(
                          isGroupStart: isGroupStart,
                          isGroupEnd: isGroupEnd,
                          child: NavTreeTile.category(
                            title: ch.text,
                            level: 0,
                            isSelected: ch == _selectedChapter,
                            isExpanded: ch == _navExpandedChapter,
                            hasChildren: true,
                            // לחיצה על גוף השורה בוחרת את הפרק (טעינת מפרשים);
                            // הצ'ברן משנה רק את תצוגת תתי-הפריטים בניווט.
                            onTap: () {
                              // no-op כשהפרק כבר נבחר — מונע טעינה כפולה של links.
                              final current = debugNavSelection;
                              if (identical(
                                reduceChapterBodyTap(current, ch),
                                current,
                              )) {
                                return;
                              }
                              _onChapterSelected(ch, chapters);
                            },
                            onToggleExpand: () => _applyNavSelection(
                              reduceChevronTap(debugNavSelection, ch),
                              clearMulti: false,
                            ),
                          ),
                        );
                      }

                      return NavTreeGroupCard(
                        isGroupStart: isGroupStart,
                        isGroupEnd: isGroupEnd,
                        child: _buildSubItem(
                          context,
                          text: item.text!,
                          isSelected: item.isSelected,
                          onTap: item.onTap!,
                          isAllChapter: item.isAllChapter,
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// מחזיר תצוגה מקדימה של ~4 מילים ראשונות של הפסקה
  String _getParaPreview(String rawText) {
    final plain = utils
        .stripHtmlIfNeeded(rawText)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (plain.isEmpty) return '';
    const maxChars = 40;
    if (plain.length <= maxChars) return plain;
    final lastSpace = plain.lastIndexOf(' ', maxChars);
    final cut = lastSpace > 0 ? lastSpace : maxChars;
    return '${plain.substring(0, cut)}...';
  }

  bool _isDuplicateChapterChild(
    TocEntry chapter,
    TocEntry child,
    String preview,
  ) {
    if (child.index != chapter.index) {
      return false;
    }
    final normalizedChapter = chapter.text.trim();
    final normalizedChild = child.text.trim();
    final normalizedPreview = preview.trim();
    return normalizedChild == normalizedChapter ||
        normalizedPreview == normalizedChapter ||
        normalizedPreview.startsWith(normalizedChapter);
  }

  String _previewForChild(
    TocEntry chapter,
    TocEntry child,
    List<String> content,
  ) {
    final textFromContent = child.index < content.length
        ? content[child.index]
        : '';
    return textFromContent.trim().isNotEmpty
        ? _getParaPreview(textFromContent)
        : child.text;
  }

  bool _isHeadingOnlyParagraphOffset(
    TocEntry chapter,
    int offset,
    List<TocEntry> chapters,
    List<String> content,
  ) {
    if (offset != 0) return false;
    final lineIndex = chapter.index + offset;
    final textFromContent = lineIndex < content.length
        ? content[lineIndex]
        : '';
    if (textFromContent.trim().isEmpty) return false;
    final preview = _getParaPreview(textFromContent);
    return preview.trim() == chapter.text.trim();
  }

  List<int> _selectableVerseIndices(TocEntry chapter, List<String> content) {
    return chapter.children
        .asMap()
        .entries
        .where(
          (entry) => !_isDuplicateChapterChild(
            chapter,
            entry.value,
            _previewForChild(chapter, entry.value, content),
          ),
        )
        .map((entry) => entry.key)
        .toList();
  }

  List<int> _selectableParagraphOffsets(
    List<TocEntry> chapters,
    TocEntry chapter,
    List<String> content,
  ) {
    final lineCount = _chapterLineCount(chapters, chapter, content.length);
    return List<int>.generate(lineCount, (i) => i)
        .where(
          (offset) => !_isHeadingOnlyParagraphOffset(
            chapter,
            offset,
            chapters,
            content,
          ),
        )
        .toList();
  }

  List<_TocListItem> _buildVisibleTocItems(
    List<TocEntry> visibleChapters,
    List<TocEntry> allChapters,
    List<String> content,
  ) {
    final items = <_TocListItem>[];
    for (final chapter in visibleChapters) {
      items.add(_TocListItem.chapter(chapter));
      if (chapter != _navExpandedChapter) {
        continue;
      }
      // הדגשת תת-פריט תופיע רק כאשר הפרק המורחב הוא גם הפרק הנבחר —
      // אחרת אנו רק מעיינים בניווט ואין כאן בחירה אקטיבית.
      final isSelectionContext = chapter == _selectedChapter;

      items.add(
        _TocListItem.subItem(
          text: allUnitLabel(chapter.text),
          isSelected: isSelectionContext && _selectedVerseIdx == _kAllChapter,
          isAllChapter: true,
          // _onChapterSelected מעדכן את ה-state במלואו דרך reduceSubItemTap
          // עם verseIdx=_kAllChapter — אין צורך ב-setState נוסף כאן.
          onTap: () => _onChapterSelected(chapter, allChapters),
        ),
      );

      if (chapter.children.isNotEmpty) {
        for (final i in _selectableVerseIndices(chapter, content)) {
          final child = chapter.children[i];
          final preview = _previewForChild(chapter, child, content);
          if (preview.isEmpty) continue;
          items.add(
            _TocListItem.subItem(
              text: preview,
              isSelected:
                  (isSelectionContext && _selectedVerseIdx == i) ||
                  _isSubItemInMulti(i, chapter, allChapters),
              onTap: () {
                if (_isCtrlPressed()) {
                  _ctrlToggleSubItem(i, chapter, allChapters);
                } else {
                  _selectVerseInChapter(i, chapter, allChapters);
                }
              },
            ),
          );
        }
        continue;
      }

      for (final i in _selectableParagraphOffsets(
        allChapters,
        chapter,
        content,
      )) {
        final lineIndex = chapter.index + i;
        final textFromContent = lineIndex < content.length
            ? content[lineIndex]
            : '';
        final preview = textFromContent.trim().isNotEmpty
            ? _getParaPreview(textFromContent)
            : 'פסקה ${i + 1}';
        if (preview.isEmpty) continue;
        items.add(
          _TocListItem.subItem(
            text: preview,
            isSelected:
                (isSelectionContext && _selectedVerseIdx == i) ||
                _isSubItemInMulti(i, chapter, allChapters),
            onTap: () {
              if (_isCtrlPressed()) {
                _ctrlToggleSubItem(i, chapter, allChapters);
              } else {
                _selectParaInChapter(i, chapter, allChapters);
              }
            },
          ),
        );
      }
    }
    return items;
  }

  /// Ctrl (או Cmd ב-macOS) לחוץ כרגע — לזיהוי ריבוי-בחירה בלחיצת ניווט.
  bool _isCtrlPressed() =>
      HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isMetaPressed;

  // הטיפול בלחיצה על תת-פריט (פסוק/פסקה) של פרק כלשהו. מעדכן את כל מצב
  // הניווט באטומיות ע"י [reduceSubItemTap] (setState בודד), ואז טוען את ה-links
  // לטווח הספציפי של הפסוק/פסקה הנלחץ. הפרק יכול להיות שונה מהפרק הנבחר כרגע
  // (תרחיש: המשתמש פתח פרק אחר בניווט ולחץ על פסוק בו).
  void _selectVerseInChapter(
    int verseIdx,
    TocEntry chapter,
    List<TocEntry> chapters,
  ) {
    _applyNavSelection(reduceSubItemTap(debugNavSelection, chapter, verseIdx));
    if (verseIdx == _kAllChapter) {
      _loadLinksForChapter(chapter, chapters);
    } else if (verseIdx < chapter.children.length) {
      final verse = chapter.children[verseIdx];
      final int endIdx = (verseIdx + 1 < chapter.children.length)
          ? chapter.children[verseIdx + 1].index - 1
          : verse.index + 50;
      final count = (endIdx - verse.index + 1).clamp(1, 200);
      _triggerLinkLoad(List.generate(count, (j) => verse.index + j));
    }
  }

  void _selectParaInChapter(
    int paraIdx,
    TocEntry chapter,
    List<TocEntry> chapters,
  ) {
    _applyNavSelection(reduceSubItemTap(debugNavSelection, chapter, paraIdx));
    if (paraIdx == _kAllChapter) {
      _loadLinksForChapter(chapter, chapters);
    } else {
      _triggerLinkLoad([chapter.index + paraIdx]);
    }
  }

  Widget _buildSubItem(
    BuildContext context, {
    required String text,
    required bool isSelected,
    required VoidCallback onTap,
    bool isAllChapter = false,
  }) {
    return NavTreeTile.book(
      title: text,
      level: 1,
      isSelected: isSelected,
      icon: isAllChapter
          ? OtzariaIcons.book_24_regular
          : OtzariaIcons.text_bullet_list_24_regular,
      onTap: onTap,
    );
  }
}

/// שורה ברשימת הניווט: פרק, תת-פריט או כפתור "כל הפרק".
class _TocListItem {
  final TocEntry? chapter;
  final String? text;
  final bool isSelected;
  final bool isAllChapter;
  final VoidCallback? onTap;

  /// הכותרת הראשית של הרשימה — פריט אמיתי, כדי שחישובי האינדקס לגלילה
  /// יישארו נכונים גם כשהכותרת נגללת עם הרשימה.
  final bool isHeader;

  const _TocListItem.header(this.text)
    : chapter = null,
      isSelected = false,
      isAllChapter = false,
      onTap = null,
      isHeader = true;

  const _TocListItem.chapter(this.chapter)
    : text = null,
      isSelected = false,
      isAllChapter = false,
      onTap = null,
      isHeader = false;

  const _TocListItem.subItem({
    required this.text,
    required this.isSelected,
    required this.onTap,
    this.isAllChapter = false,
  }) : chapter = null,
       isHeader = false;

  bool get isChapter => chapter != null;
}
