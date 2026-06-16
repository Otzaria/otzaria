import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/text_book/utils/toc_unit_label.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/bookmarks/view/bookmark_screen.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/models/commentators_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/commentary_list_base.dart';
import 'package:otzaria/utils/text/ref_helper.dart';
import 'package:otzaria/widgets/lists/commentators_selection_panel.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/widgets/layout/adaptive_side_pane.dart';
import 'package:otzaria/widgets/navigation/responsive_action_bar.dart';
import 'package:otzaria/widgets/navigation/app_top_bar.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/navigation/search_pane_base.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/search/utils/snippet_builder.dart';
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

  /// מחיל מצב חדש שחושב ע"י אחד הרדוסרים הטהורים (ראה [reduceChevronTap]
  /// וחבריו). מבטיח שכל הנתיבים שמשנים את מצב הניווט עוברים דרך אותו צינור.
  void _applyNavSelection(CommentatorsNavSelection next,
      {bool clearMulti = true}) {
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
        chapters, _selectedChapter, _selectedVerseIdx, contentLength);
    if (_extraIndexes.isEmpty) return primary;
    return <int>{...?primary, ..._extraIndexes}.toList()..sort();
  }

  /// Ctrl+לחיצה על תת-פריט: מוסיף/מסיר את שורותיו מריבוי-הבחירה (toggle).
  void _ctrlToggleSubItem(
      int verseIdx, TocEntry chapter, List<TocEntry> chapters) {
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
            chapters, _selectedChapter, _selectedVerseIdx, contentLength);
        if (primary != null) _extraIndexes.addAll(primary);
        _extraIndexes.addAll(idxs);
      }
    });
    _triggerLinkLoad(idxs);
  }

  /// האם שורותיו של תת-פריט נמצאות בריבוי-הבחירה (להדגשה ב'ניווט').
  bool _isSubItemInMulti(
      int verseIdx, TocEntry chapter, List<TocEntry> chapters) {
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
  final _externalSearchSnippets =
      ValueNotifier<List<CommentarySearchSnippet>>([]);
  bool _initialChapterResolved = false;
  final Map<String, List<InlineSpan>> _snippetSpansCache = {};

  late final TabController _navTabController;

  // אינדקסי טאבים בסרגל הניווט הצדדי
  static const int _commentatorsTabIndex = 1;
  static const int _searchTabIndex = 2;

  @override
  void initState() {
    super.initState();
    _navTabController = TabController(length: 3, vsync: this);
    _navTabController.addListener(() {
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
    // סנכרון חד-פעמי של המפרשים הנבחרים עם חלונית המקור
    final sourceState = widget.tab.sourceTab.bloc.state;
    if (sourceState is TextBookLoaded &&
        sourceState.activeCommentators.isNotEmpty) {
      _selectedCommentatorsOverride =
          List<String>.from(sourceState.activeCommentators);
    }
    // טעינת הספר והמפרשים ב-BLoC העצמאי
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final settings = context.read<SettingsBloc>().state;
      widget.tab.bloc.add(LoadContent(
        fontSize: settings.fontSize,
        showSplitView: false,
        removeNikud: settings.defaultRemoveNikud,
        loadCommentators: true,
      ));
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
    FocusRepository().unregisterTabContentFocusRequester(widget.tab);
    _navTabController.dispose();
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
      List<TocEntry> chapters, int lineIndex) {
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

  List<InlineSpan> _buildSnippetHighlightSpans(
    BuildContext context,
    SettingsState settingsState, {
    required CommentarySearchSnippet snippet,
    required String query,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final cacheKey =
        '${settingsState.commentatorsFontFamily}|${colorScheme.onSurface.toARGB32()}|$query|${snippet.globalIndex}|${snippet.snippet}';
    final cached = _snippetSpansCache[cacheKey];
    if (cached != null) {
      return cached;
    }

    final spans = SnippetBuilder.highlightLiteral(
      plainText: snippet.snippet,
      query: query,
      defaultStyle: TextStyle(
        fontSize: 14,
        fontFamily: settingsState.commentatorsFontFamily,
        color: colorScheme.onSurface,
        height: 1.5,
      ),
      highlightStyle: TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 16,
        color: colorScheme.error,
      ),
    );

    if (_snippetSpansCache.length > 500) {
      _snippetSpansCache.clear();
    }
    _snippetSpansCache[cacheKey] = spans;
    return spans;
  }

  List<int>? _computeIndexes(List<TocEntry> chapters, TocEntry? chapter,
      int verseIdx, int contentLength) {
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
      List<TocEntry> chapters, TocEntry chapter, int contentLength) {
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
    final lineIndex = state.selectedIndex ??
        (state.visibleIndices.isNotEmpty ? state.visibleIndices.first : 0);

    if (chapters.isEmpty) {
      _initialChapterResolved = true;
      _triggerLinkLoad([lineIndex]);
      return;
    }

    final pos = _findPos(chapters, lineIndex);
    if (pos.chapter == null) return;

    _initialChapterResolved = true;
    _onChapterSelected(pos.chapter!, chapters);
  }

  /// גוללת את רשימת הניווט לפרק הנבחר. נקראת בעת פתיחת הפאנל ומעבר
  /// ללשונית הניווט, שכן אין מי שיגרום לכך אחרת.
  void _scrollNavToSelectedChapter() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_navScrollController.isAttached) return;
      final chapter = _selectedChapter;
      if (chapter == null) return;
      final idx =
          _navItems.indexWhere((it) => it.isChapter && it.chapter == chapter);
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
      child: Builder(builder: (context) {
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
                  prev.removePunctuation != curr.removePunctuation;
            }
            return true;
          },
          builder: (context, state) {
            final colorScheme = Theme.of(context).colorScheme;
            final appBarDecoration = Border(
              bottom: BorderSide(
                color: colorScheme.outlineVariant,
                width: 0.3,
              ),
            );

            if (state is! TextBookLoaded) {
              return Scaffold(
                appBar: AppBar(
                  backgroundColor: colorScheme.surfaceContainer,
                  shape: appBarDecoration,
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  centerTitle: false,
                  leading: const IconButton(
                    icon: Icon(FluentIcons.navigation_24_regular, size: 20),
                    tooltip: 'ניווט',
                    onPressed: null,
                  ),
                  title: Text(
                    'מפרשים על ${widget.tab.sourceTab.book.title}',
                    style: const TextStyle(fontSize: 16),
                    overflow: TextOverflow.ellipsis,
                  ),
                  actions: [
                    ResponsiveActionBar(
                      overflowMenuOffset: const Offset(0, 8),
                      maxVisibleButtons: 999,
                      originalOrder: const [],
                      actions: [
                        for (final action in const [
                          (
                            icon: FluentIcons.text_font_24_regular,
                            tooltip: 'ניקוד',
                          ),
                          (
                            icon: FluentIcons.search_24_regular,
                            tooltip: 'חיפוש',
                          ),
                          (
                            icon: FluentIcons.apps_list_24_regular,
                            tooltip: 'בחירת מפרשים',
                          ),
                          (
                            icon: FluentIcons.bookmark_add_24_regular,
                            tooltip: 'הוסף סימניה',
                          ),
                          (
                            icon: FluentIcons.zoom_in_24_regular,
                            tooltip: 'הגדל את גודל הטקסט',
                          ),
                          (
                            icon: FluentIcons.zoom_out_24_regular,
                            tooltip: 'הקטן את גודל הטקסט',
                          ),
                          (
                            icon: FluentIcons.chevron_left_24_regular,
                            tooltip: 'הקטע הקודם',
                          ),
                          (
                            icon: FluentIcons.chevron_right_24_regular,
                            tooltip: 'הקטע הבא',
                          ),
                        ])
                          ActionButtonData(
                            widget: IconButton(
                              icon: Icon(action.icon),
                              tooltip: action.tooltip,
                              onPressed: null,
                            ),
                            icon: action.icon,
                            tooltip: action.tooltip,
                            onPressed: null,
                          ),
                      ],
                    ),
                  ],
                ),
                body: const Center(child: CircularProgressIndicator()),
              );
            }

            final chapters = _getChapters(state.tableOfContents);

            final effectiveIndexes =
                _effectiveIndexes(chapters, state.content.length);

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
                          AdaptiveSidePane(
                            isOpen: _navPaneOpen || _pinLeftPane,
                            onClose: () {
                              if (!_pinLeftPane) {
                                setState(() => _navPaneOpen = false);
                              }
                            },
                            alignment: AlignmentDirectional.centerEnd,
                            paneWidth: 320,
                            minMainContentWidth: 400,
                            mainContent: _buildCommentaryMainContent(
                              context,
                              state,
                              effectiveIndexes,
                            ),
                            paneContent: _buildNavPanel(
                              context,
                              state: state,
                              chapters: chapters,
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
      }),
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
    final listContent = NotificationListener<UserScrollNotification>(
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
          useAvailableCommentators: _selectedCommentatorsOverride == null,
          selectedCommentatorsOverride: _selectedCommentatorsOverride,
          onSelectedCommentatorsOverrideChanged: (list) {
            setState(() => _selectedCommentatorsOverride = list);
          },
          onFilterOpenRequested: _openCommentatorsSelectionPane,
          externalSearchController: _commentarySearchController,
          externalCurrentIndexNotifier: _externalCurrentIndex,
          externalTotalResultsNotifier: _externalTotalResults,
          externalSearchResultsByPathNotifier: _externalSearchResultsByPath,
          externalSearchSnippetsNotifier: _externalSearchSnippets,
          externalAllExpandedNotifier: _allExpandedInChild,
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        return BlocBuilder<SettingsBloc, SettingsState>(
          builder: (context, settingsState) {
            // אותו חישוב כמו בתצוגת הטקסט הראשית (combined_book_screen):
            // ערך שלילי = רמה (95%/90%/...), ערך 0 = ללא הגבלה.
            var textMaxWidth = settingsState.textMaxWidth;
            if (textMaxWidth < 0) {
              final level = (-textMaxWidth).toInt();
              final widthPercent = 1.0 - (level * 0.05);
              textMaxWidth = constraints.maxWidth * widthPercent;
            }

            if (textMaxWidth > 0) {
              // יישור לראש (topCenter) ולא Center — אחרת כשהמפרשים מכווצים
              // הרשימה (shrinkWrap) נמוכה ומתמרכזת אנכית, ונוצר רווח למעלה.
              return Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: textMaxWidth),
                  child: listContent,
                ),
              );
            }
            return listContent;
          },
        );
      },
    );
  }

  void _selectVerseAndLoad(int verseIdx, List<TocEntry> chapters) {
    final chapter = _selectedChapter;
    if (chapter == null) return;
    _selectVerseInChapter(verseIdx, chapter, chapters);
  }

  void _selectParaAndLoad(int paraIdx, List<TocEntry> chapters) {
    final chapter = _selectedChapter;
    if (chapter == null) return;
    _selectParaInChapter(paraIdx, chapter, chapters);
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

  void _navigateToPrevVerse(List<TocEntry> chapters) {
    if (_selectedChapter == null) return;
    final currentState = widget.tab.bloc.state;
    final content = currentState is TextBookLoaded
        ? currentState.content
        : const <String>[];
    final hasVerses = _selectedChapter?.children.isNotEmpty ?? false;
    if (hasVerses) {
      final selectable = _selectableVerseIndices(_selectedChapter!, content);
      final currentPos = _selectedVerseIdx == _kAllChapter
          ? -1
          : selectable.indexOf(_selectedVerseIdx);
      if (currentPos <= -1) return;
      if (currentPos == 0) {
        _selectVerseAndLoad(_kAllChapter, chapters);
        return;
      }
      _selectVerseAndLoad(selectable[currentPos - 1], chapters);
    } else {
      final selectable =
          _selectableParagraphOffsets(chapters, _selectedChapter!, content);
      final currentPos = _selectedVerseIdx == _kAllChapter
          ? -1
          : selectable.indexOf(_selectedVerseIdx);
      if (currentPos <= -1) return;
      if (currentPos == 0) {
        _selectParaAndLoad(_kAllChapter, chapters);
        return;
      }
      _selectParaAndLoad(selectable[currentPos - 1], chapters);
    }
  }

  void _navigateToNextVerse(List<TocEntry> chapters) {
    if (_selectedChapter == null) return;
    final currentState = widget.tab.bloc.state;
    final content = currentState is TextBookLoaded
        ? currentState.content
        : const <String>[];
    final hasVerses = _selectedChapter?.children.isNotEmpty ?? false;
    if (hasVerses) {
      final selectable = _selectableVerseIndices(_selectedChapter!, content);
      if (selectable.isEmpty) return;
      if (_selectedVerseIdx == _kAllChapter) {
        _selectVerseAndLoad(selectable.first, chapters);
        return;
      }
      final currentPos = selectable.indexOf(_selectedVerseIdx);
      if (currentPos < 0 || currentPos + 1 >= selectable.length) return;
      _selectVerseAndLoad(selectable[currentPos + 1], chapters);
    } else {
      final selectable =
          _selectableParagraphOffsets(chapters, _selectedChapter!, content);
      if (selectable.isEmpty) return;
      if (_selectedVerseIdx == _kAllChapter) {
        _selectParaAndLoad(selectable.first, chapters);
        return;
      }
      final currentPos = selectable.indexOf(_selectedVerseIdx);
      if (currentPos < 0 || currentPos + 1 >= selectable.length) return;
      _selectParaAndLoad(selectable[currentPos + 1], chapters);
    }
  }

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
    final fallbackIndex = state.selectedIndex ??
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
    UiSnack.showQuick(added ? 'הסימניה נוספה בהצלחה' : 'הסימניה כבר קיימת');
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
      leadingItems: [
        AppTopBarItem(
          widget: ToolbarActionButton(
            tooltip: 'ניווט',
            icon: FluentIcons.navigation_24_regular,
            compact: context.read<SettingsBloc>().state.compactMenuMode,
            onPressed: () {
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
          widget: ResponsiveActionBar(
            overflowMenuOffset: const Offset(0, 8),
            maxVisibleButtons: 999,
            actions: [
              // ניקוד
              ActionButtonData(
                widget: ToolbarActionButton(
                  tooltip: state.removeNikud ? 'הצג ניקוד' : 'הסתר ניקוד',
                  icon: state.removeNikud
                      ? FluentIcons.text_font_24_regular
                      : FluentIcons.text_font_info_24_regular,
                  compact: context.read<SettingsBloc>().state.compactMenuMode,
                  onPressed: () => context
                      .read<TextBookBloc>()
                      .add(ToggleNikud(!state.removeNikud)),
                ),
                icon: state.removeNikud
                    ? FluentIcons.text_font_24_regular
                    : FluentIcons.text_font_info_24_regular,
                tooltip: state.removeNikud ? 'הצג ניקוד' : 'הסתר ניקוד',
                onPressed: () => context
                    .read<TextBookBloc>()
                    .add(ToggleNikud(!state.removeNikud)),
              ),
              // פיסוק (רק אם לא תנ"ך)
              if (!state.isTanach)
                ActionButtonData(
                  widget: ToolbarActionButton(
                    tooltip:
                        state.removePunctuation ? 'הצג פיסוק' : 'הסתר פיסוק',
                    icon: state.removePunctuation
                        ? FluentIcons.text_quote_24_regular
                        : FluentIcons.text_clear_formatting_24_regular,
                    compact: context.read<SettingsBloc>().state.compactMenuMode,
                    onPressed: () => context
                        .read<TextBookBloc>()
                        .add(TogglePunctuation(!state.removePunctuation)),
                  ),
                  icon: state.removePunctuation
                      ? FluentIcons.text_quote_24_regular
                      : FluentIcons.text_clear_formatting_24_regular,
                  tooltip: state.removePunctuation ? 'הצג פיסוק' : 'הסתר פיסוק',
                  onPressed: () => context
                      .read<TextBookBloc>()
                      .add(TogglePunctuation(!state.removePunctuation)),
                ),
              // הדפסת המפרשים המוצגים
              ActionButtonData(
                widget: ToolbarActionButton(
                  icon: FluentIcons.print_24_regular,
                  tooltip: 'הדפסה',
                  compact: context.read<SettingsBloc>().state.compactMenuMode,
                  onPressed: () =>
                      _commentaryKey.currentState?.printDisplayedCommentaries(),
                ),
                icon: FluentIcons.print_24_regular,
                tooltip: 'הדפסה',
                onPressed: () =>
                    _commentaryKey.currentState?.printDisplayedCommentaries(),
              ),
              // חיפוש
              ActionButtonData(
                widget: ToolbarActionButton(
                  tooltip: 'חיפוש',
                  icon: FluentIcons.search_24_regular,
                  compact: context.read<SettingsBloc>().state.compactMenuMode,
                  onPressed: _openSearchPane,
                ),
                icon: FluentIcons.search_24_regular,
                tooltip: 'חיפוש',
                onPressed: _openSearchPane,
              ),
              // כיווץ/הרחבת כל המפרשים — שולט במצב הגלובלי בתוך CommentaryListBase
              ActionButtonData(
                widget: ValueListenableBuilder<bool>(
                  valueListenable: _allExpandedInChild,
                  builder: (context, allExpanded, _) {
                    return ToolbarActionButton(
                      tooltip: allExpanded
                          ? 'כווץ את כל המפרשים'
                          : 'הרחב את כל המפרשים',
                      icon: allExpanded
                          ? FluentIcons.arrow_collapse_all_24_regular
                          : FluentIcons.arrow_expand_all_24_regular,
                      compact:
                          context.read<SettingsBloc>().state.compactMenuMode,
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
                onPressed: () =>
                    _commentaryKey.currentState?.toggleAllExpanded(),
              ),
              ActionButtonData(
                widget: ToolbarActionButton(
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
                      )),
                ),
                icon: FluentIcons.bookmark_add_24_regular,
                tooltip: 'הוסף סימניה',
                onPressed: () => _addBookmark(
                  context,
                  state,
                  _computeIndexes(chapters, _selectedChapter, _selectedVerseIdx,
                      state.content.length),
                ),
              ),
              // הגדל טקסט
              ActionButtonData(
                widget: ToolbarActionButton(
                  tooltip: 'הגדל את גודל הטקסט',
                  icon: FluentIcons.zoom_in_24_regular,
                  compact: context.read<SettingsBloc>().state.compactMenuMode,
                  onPressed: () => context
                      .read<TextBookBloc>()
                      .add(UpdateFontSize((state.fontSize + 3).clamp(15, 50))),
                ),
                icon: FluentIcons.zoom_in_24_regular,
                tooltip: 'הגדל את גודל הטקסט',
                onPressed: () => context
                    .read<TextBookBloc>()
                    .add(UpdateFontSize((state.fontSize + 3).clamp(15, 50))),
              ),
              // הקטן טקסט
              ActionButtonData(
                widget: ToolbarActionButton(
                  tooltip: 'הקטן את גודל הטקסט',
                  icon: FluentIcons.zoom_out_24_regular,
                  compact: context.read<SettingsBloc>().state.compactMenuMode,
                  onPressed: () => context
                      .read<TextBookBloc>()
                      .add(UpdateFontSize((state.fontSize - 3).clamp(15, 50))),
                ),
                icon: FluentIcons.zoom_out_24_regular,
                tooltip: 'הקטן את גודל הטקסט',
                onPressed: () => context
                    .read<TextBookBloc>()
                    .add(UpdateFontSize((state.fontSize - 3).clamp(15, 50))),
              ),
            ],
            alwaysInMenu: [
              ActionButtonData(
                widget: ToolbarActionButton(
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
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        // ─── כותרת TabBar (זהה לטאב הטקסט) ─────────────────────────
        SizedBox(
          height: 44,
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerColor,
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TabBar(
                    controller: _navTabController,
                    tabs: const [
                      Tab(
                        icon: Icon(FluentIcons.navigation_24_regular, size: 16),
                        iconMargin: EdgeInsets.only(bottom: 1),
                        height: 44,
                        child: Text(
                          'ניווט',
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                      Tab(
                        icon: Icon(FluentIcons.apps_list_24_regular, size: 16),
                        iconMargin: EdgeInsets.only(bottom: 1),
                        height: 44,
                        child: Text(
                          'מפרשים',
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                      Tab(
                        icon: Icon(FluentIcons.search_24_regular, size: 16),
                        iconMargin: EdgeInsets.only(bottom: 1),
                        height: 44,
                        child: Text(
                          'חיפוש',
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                    ],
                    labelColor: colorScheme.primary,
                    unselectedLabelColor: colorScheme.onSurfaceVariant,
                    indicatorColor: colorScheme.primary,
                    dividerColor: Colors.transparent,
                    splashBorderRadius: BorderRadius.circular(12),
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() => _pinLeftPane = !_pinLeftPane),
                  icon: AnimatedRotation(
                    turns: _pinLeftPane ? -0.125 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      _pinLeftPane
                          ? FluentIcons.pin_24_filled
                          : FluentIcons.pin_24_regular,
                    ),
                  ),
                  color: _pinLeftPane ? colorScheme.primary : null,
                  tooltip: _pinLeftPane ? 'בטל נעיצה' : 'נעץ את הפאנל',
                ),
              ],
            ),
          ),
        ),
        // ─── תוכן TabBarView ──────────────────────────────────────────
        Expanded(
          child: TabBarView(
            controller: _navTabController,
            children: [
              _buildTocList(context,
                  chapters: chapters, content: state.content),
              _buildCommentatorsSelectionPanel(context, state),
              _buildCommentarySearchPanel(context),
            ],
          ),
        ),
      ],
    );
  }

  // ── פאנל בחירת מפרשים ─────────────────────────────────────────────────────

  Widget _buildCommentatorsSelectionPanel(
      BuildContext context, TextBookLoaded state) {
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
    return CommentatorsSelectionPanel(
      groups: groups,
      selectedCommentators: selected,
      bookTitle: state.book.title,
      onSelectionChanged: (list) {
        setState(() => _selectedCommentatorsOverride = list);
      },
    );
  }

  // ── פאנל חיפוש ────────────────────────────────────────────────────────────

  Widget _buildCommentarySearchPanel(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _commentarySearchController,
      builder: (_, val, __) {
        final hasQuery = val.text.isNotEmpty;
        return ValueListenableBuilder<int>(
          valueListenable: _externalTotalResults,
          builder: (_, total, __) => ValueListenableBuilder<int>(
            valueListenable: _externalCurrentIndex,
            builder: (_, current, __) =>
                ValueListenableBuilder<List<CommentarySearchSnippet>>(
              valueListenable: _externalSearchSnippets,
              builder: (context, snippets, __) {
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
    if (query.isEmpty) {
      return const SizedBox.shrink();
    }
    if (snippets.isEmpty) {
      // total>0 בלבד מגיע לכאן (אם total==0 מוצג 'אין תוצאות' ע"י SearchPaneBase)
      return Center(
        child: Text(
          'טוען תוצאות...',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }

    // בניית רשימה מקובצת עם כותרות מפרשים
    final List<_SearchResultItem> items = [];
    String? lastPath;
    for (final snippet in snippets) {
      if (snippet.path != lastPath) {
        items.add(
            _SearchResultItem.header(utils.getTitleFromPath(snippet.path)));
        lastPath = snippet.path;
      }
      items.add(_SearchResultItem.result(snippet));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        if (item.isHeader) {
          return Padding(
            padding:
                const EdgeInsets.only(top: 8, bottom: 4, right: 4, left: 4),
            child: Row(
              children: [
                Icon(
                  FluentIcons.text_align_right_24_regular,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    item.header!,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          );
        }

        final snippet = item.snippet!;
        final isSelected = snippet.globalIndex == currentIdx;
        return BlocBuilder<SettingsBloc, SettingsState>(
          builder: (context, settingsState) {
            final highlightedSpans = _buildSnippetHighlightSpans(
              context,
              settingsState,
              snippet: snippet,
              query: query,
            );
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppSurfaces.selectedItem(Theme.of(context).colorScheme)
                    : null,
                border: Border.all(
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outlineVariant,
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: InkWell(
                onTap: () => _commentaryKey.currentState
                    ?.navigateToGlobalIndex(snippet.globalIndex),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text.rich(
                    TextSpan(children: highlightedSpans),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── רשימת פרקים (לשונית ניווט) ────────────────────────────────────────────

  Widget _buildTocList(
    BuildContext context, {
    required List<TocEntry> chapters,
    required List<String> content,
  }) {
    if (chapters.isEmpty) {
      return const Center(
        child: Text('אין תוכן עניינים'),
      );
    }
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _tocSearchController,
            builder: (_, val, __) => RtlTextField(
              controller: _tocSearchController,
              decoration: InputDecoration(
                hintText: 'איתור כותרת...',
                prefixIcon: const Icon(FluentIcons.search_24_regular),
                suffixIcon: val.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(FluentIcons.dismiss_24_regular),
                        onPressed: () => _tocSearchController.clear(),
                      )
                    : null,
                isDense: true,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              ),
            ),
          ),
        ),
        Expanded(
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _tocSearchController,
            builder: (context, val, _) {
              final query = val.text;
              final filteredChapters = query.isEmpty
                  ? chapters
                  : chapters.where((ch) => ch.text.contains(query)).toList();
              final items =
                  _buildVisibleTocItems(filteredChapters, chapters, content);
              _navItems = items;
              return ScrollablePositionedList.builder(
                itemScrollController: _navScrollController,
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  if (item.isChapter) {
                    final ch = item.chapter!;
                    final isSelected = ch == _selectedChapter;
                    final isExpandedInNav = ch == _navExpandedChapter;

                    return Container(
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppSurfaces.selectedItem(colorScheme)
                            : null,
                        border: Border(
                          bottom: BorderSide(
                            color: Theme.of(context).dividerColor,
                            width: 0.5,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          // אזור לחיצה ראשי — בחירת הפרק לטעינת מפרשים.
                          Expanded(
                            child: InkWell(
                              onTap: () {
                                // no-op כשהפרק כבר נבחר — מונע טעינה כפולה
                                // של links. _onChapterSelected יחיל את ה-state
                                // הסופי דרך הרדוסר reduceSubItemTap.
                                final current = debugNavSelection;
                                if (identical(
                                  reduceChapterBodyTap(current, ch),
                                  current,
                                )) {
                                  return;
                                }
                                _onChapterSelected(ch, chapters);
                              },
                              child: Padding(
                                padding: const EdgeInsets.only(
                                    right: 16, top: 12, bottom: 12),
                                child: Row(
                                  children: [
                                    Icon(
                                      FluentIcons.book_24_regular,
                                      color: colorScheme.primary,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        ch.text,
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: isSelected
                                              ? FontWeight.w600
                                              : FontWeight.normal,
                                          color: colorScheme.primary,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // חץ הכיווץ/פתיחה — אזור לחיצה נפרד שמשנה רק את
                          // תצוגת תתי-הפריטים בניווט, ללא ביטול בחירת הפרק.
                          IconButton(
                            onPressed: () => _applyNavSelection(
                              reduceChevronTap(debugNavSelection, ch),
                              clearMulti: false,
                            ),
                            icon: Icon(
                              isExpandedInNav
                                  ? FluentIcons.chevron_up_24_regular
                                  : FluentIcons.chevron_down_24_regular,
                              color: colorScheme.onSurfaceVariant,
                              size: 20,
                            ),
                            tooltip: isExpandedInNav
                                ? 'כווץ תתי-פריטים'
                                : 'הצג תתי-פריטים',
                          ),
                        ],
                      ),
                    );
                  }

                  return _buildSubItem(
                    context,
                    text: item.text!,
                    isSelected: item.isSelected,
                    onTap: item.onTap!,
                    colorScheme: colorScheme,
                    isAllChapter: item.isAllChapter,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  /// מחזיר תצוגה מקדימה של ~4 מילים ראשונות של הפסקה
  String _getParaPreview(String rawText) {
    final plain =
        utils.stripHtmlIfNeeded(rawText).replaceAll(RegExp(r'\s+'), ' ').trim();
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
    final textFromContent =
        child.index < content.length ? content[child.index] : '';
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
    final textFromContent =
        lineIndex < content.length ? content[lineIndex] : '';
    if (textFromContent.trim().isEmpty) return false;
    final preview = _getParaPreview(textFromContent);
    return preview.trim() == chapter.text.trim();
  }

  List<int> _selectableVerseIndices(TocEntry chapter, List<String> content) {
    return chapter.children
        .asMap()
        .entries
        .where((entry) => !_isDuplicateChapterChild(
              chapter,
              entry.value,
              _previewForChild(chapter, entry.value, content),
            ))
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
              isSelected: (isSelectionContext && _selectedVerseIdx == i) ||
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
        final textFromContent =
            lineIndex < content.length ? content[lineIndex] : '';
        final preview = textFromContent.trim().isNotEmpty
            ? _getParaPreview(textFromContent)
            : 'פסקה ${i + 1}';
        if (preview.isEmpty) continue;
        items.add(
          _TocListItem.subItem(
            text: preview,
            isSelected: (isSelectionContext && _selectedVerseIdx == i) ||
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
    required ColorScheme colorScheme,
    bool isAllChapter = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.only(
            right: 16.0 + 24.0, left: 16, top: 10, bottom: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppSurfaces.selectedItem(colorScheme) : null,
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).dividerColor,
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              isAllChapter
                  ? FluentIcons.book_24_regular
                  : FluentIcons.text_bullet_list_24_regular,
              color: colorScheme.secondary,
              size: 18,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// פריט עזר לרשימת תוצאות חיפוש מקובצת (כותרת או תוצאה)
class _SearchResultItem {
  final String? header;
  final CommentarySearchSnippet? snippet;

  const _SearchResultItem.header(this.header) : snippet = null;
  const _SearchResultItem.result(this.snippet) : header = null;

  bool get isHeader => header != null;
}

class _TocListItem {
  final TocEntry? chapter;
  final String? text;
  final bool isSelected;
  final bool isAllChapter;
  final VoidCallback? onTap;

  const _TocListItem.chapter(this.chapter)
      : text = null,
        isSelected = false,
        isAllChapter = false,
        onTap = null;

  const _TocListItem.subItem({
    required this.text,
    required this.isSelected,
    required this.onTap,
    this.isAllChapter = false,
  }) : chapter = null;

  bool get isChapter => chapter != null;
}
