import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/bookmarks/view/bookmark_screen.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/tabs/models/pdf_commentators_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/pdf_book/view/pdf_commentary_panel.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/utils/navigation/open_book.dart';
import 'package:otzaria/utils/file/page_converter.dart';
import 'package:otzaria/pdf_book/utils/pdf_spread_layout.dart';
import 'package:otzaria/models/pdf_headings.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:otzaria/text_book/models/commentator_group.dart';
import 'package:otzaria/text_book/view/page_shape/utils/default_commentators.dart';
import 'package:otzaria/widgets/lists/commentators_selection_panel.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/widgets/layout/adaptive_side_pane.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/navigation/app_top_bar.dart';
import 'package:otzaria/widgets/navigation/responsive_action_bar.dart';
import 'package:otzaria/widgets/navigation/search_pane_base.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';
import 'package:otzaria/widgets/navigation/reader_nav_center.dart';

/// ערך מיוחד ל-_selectedParagraphIdx שמשמעו "כל הכותרת" (כל המפרשים בקטע),
/// במקביל ל-_kAllChapter בכרטסיית הטקסט.
const int _kAllPara = -1;

/// מסך כרטסיית המפרשים של PDF — עצמאי לחלוטין, כמו CommentatorsTabScreen.
class PdfCommentatorsTabScreen extends StatefulWidget {
  final PdfCommentatorsTab tab;

  const PdfCommentatorsTabScreen({super.key, required this.tab});

  @override
  State<PdfCommentatorsTabScreen> createState() =>
      _PdfCommentatorsTabScreenState();
}

class _PdfCommentatorsTabScreenState extends State<PdfCommentatorsTabScreen>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  // שומר את ה-State חי כשהטאב יוצא מתחום ה-PageView, כדי שבחירת הכותרת/פסקה
  // לא תאבד במעבר לטאב אחר וחזרה.
  @override
  bool get wantKeepAlive => true;

  List<MapEntry<String, int>>? _sortedHeadings;
  int _selectedHeadingIdx = 0;
  int _selectedParagraphIdx = 0;
  List<String>? _textLines;

  // ריבוי-בחירה ב'ניווט' (Ctrl+לחיצה): מספרי שורות נוספים להצגת מפרשים מעבר
  // לטווח הראשי. ריק = בחירה יחידה רגילה. מתאפס בכל ניווט רגיל.
  final Set<int> _extraLines = <int>{};

  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _navSearchController = TextEditingController();
  final _totalResultsNotifier = ValueNotifier<int>(0);
  final _currentIdxNotifier = ValueNotifier<int>(0);
  final _panelKey = GlobalKey<PdfCommentaryPanelState>();
  final Set<int> _expandedHeadings = {};

  // גלילת רשימת הניווט לכותרת הנבחרת בעת פתיחת הפאנל/מעבר ללשונית הניווט.
  final ItemScrollController _navScrollController = ItemScrollController();

  /// סרגל 3 הלשוניות בפאנל הצד (זהה לכרטיסיית הטקסט): ניווט / מפרשים / חיפוש
  late final TabController _navTabController;
  static const int _commentatorsTabIndex = 1;
  static const int _searchTabIndex = 2;

  /// האם פאנל הצד פתוח, והאם הוא נעוץ (לא נסגר אוטומטית)
  bool _navPaneOpen = false;
  bool _pinLeftPane = false;

  /// קבוצות המפרשים ללשונית הבחירה (נטענות מתוך links של ה-sourceTab)
  List<CommentatorGroup> _commentatorGroups = [];

  /// משקף את מצב "הכל מורחב" מתוך PdfCommentaryPanel (לכפתור כיווץ/הרחבה בסרגל).
  final _allExpandedInChild = ValueNotifier<bool>(true);

  /// הסרת ניקוד/פיסוק מהמפרשים (כמו בכרטיסיית הטקסט).
  bool _removeNikud = false;
  bool _removePunctuation = false;

  bool get _isNavigationReady =>
      _sortedHeadings != null && _sortedHeadings!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _navTabController = TabController(length: 3, vsync: this);
    _navTabController.addListener(_handleTabChanged);
    _initHeadings();
    widget.tab.sourceTab.currentTitle.addListener(_syncWithSourceTab);
    _ensureDataLoaded();
    _loadTextContent();
    _loadCommentatorGroups();

    // ממקד את חלונית המפרשים כשהטאב הופך פעיל (מעבר טאב) כדי שגלילה עם
    // החיצים תעבוד מיד בלי לחיצה.
    FocusRepository().registerTabContentFocusRequester(
      widget.tab,
      () => _panelKey.currentState?.requestScrollFocus(),
    );
  }

  /// מרענן את הדגשת כפתורי הסרגל בעת מעבר לשונית, וממקד את שדה החיפוש.
  void _handleTabChanged() {
    if (!mounted) return;
    setState(() {});
    if (_navTabController.index == _searchTabIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocusNode.requestFocus();
      });
    } else if (_navTabController.index == 0) {
      // לשונית הניווט: גלילה לכותרת הנבחרת.
      _scrollNavToSelectedHeading();
    }
  }

  /// אינדקסי הכותרות המוצגות בלשונית הניווט, מסוננים לפי שאילתת החיפוש.
  List<int> _navFilteredIndices(String query) {
    final headings = _sortedHeadings;
    if (headings == null) return const [];
    final q = query.trim();
    final all = List<int>.generate(headings.length, (i) => i);
    if (q.isEmpty) return all;
    return all.where((i) => headings[i].key.contains(q)).toList();
  }

  /// גוללת את רשימת הניווט לכותרת הנבחרת. ה-BlocListener/פתיחת הפאנל לא
  /// מבצעים זאת לבדם, ולכן יש לקרוא לכך בעת פתיחה ומעבר ללשונית.
  void _scrollNavToSelectedHeading() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_navScrollController.isAttached) return;
      final listIdx = _navFilteredIndices(_navSearchController.text)
          .indexOf(_selectedHeadingIdx);
      if (listIdx < 0) return;
      _navScrollController.scrollTo(
        index: listIdx,
        alignment: 0.4,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void didUpdateWidget(covariant PdfCommentatorsTabScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tab.sourceTab != widget.tab.sourceTab) {
      oldWidget.tab.sourceTab.currentTitle.removeListener(_syncWithSourceTab);
      widget.tab.sourceTab.currentTitle.addListener(_syncWithSourceTab);
      _syncWithSourceTab();
    }
  }

  void _initHeadings() {
    final headings = widget.tab.sourceTab.pdfHeadings?.getSortedHeadings();
    if (headings == null || headings.isEmpty) return;
    _sortedHeadings = headings;
    final currentTitle = widget.tab.sourceTab.currentTitle.value;
    final selection = _resolveTitleSelection(headings, currentTitle);
    _selectedHeadingIdx = selection.firstIdx >= 0 ? selection.firstIdx : 0;
    _selectedParagraphIdx = _kAllPara;
    _extraLines
      ..clear()
      ..addAll(_spreadExtraLines(selection));
  }

  void _syncWithSourceTab() {
    if (!mounted) return;

    final headings = widget.tab.sourceTab.pdfHeadings?.getSortedHeadings();
    final currentTitle = widget.tab.sourceTab.currentTitle.value;
    var nextSelectedHeadingIdx = _selectedHeadingIdx;
    var selection = (firstIdx: nextSelectedHeadingIdx, secondIdx: -1);

    if (headings != null && headings.isNotEmpty) {
      _sortedHeadings = headings;
      selection = _resolveTitleSelection(headings, currentTitle);
      if (selection.firstIdx >= 0) {
        nextSelectedHeadingIdx = selection.firstIdx;
      }
    }

    setState(() {
      _selectedHeadingIdx = nextSelectedHeadingIdx;
      _selectedParagraphIdx = _kAllPara;
      _extraLines
        ..clear()
        ..addAll(_spreadExtraLines(selection));
    });
  }

  /// מזהה את בחירת הכותרת עבור [title]. מנסה תחילה התאמה מלאה (כדי לא לפצל
  /// בטעות כותרת חוקית שמכילה מקף ארוך), ורק אחריה מזהה ספירייד — פיצול לשתי
  /// כותרות קיימות. [secondIdx] >= 0 רק בספירייד אמיתי. [firstIdx] = -1 כשאין
  /// התאמה כלל.
  ({int firstIdx, int secondIdx}) _resolveTitleSelection(
      List<MapEntry<String, int>> headings, String title) {
    final full = headings.indexWhere((e) => e.key == title);
    if (full >= 0) return (firstIdx: full, secondIdx: -1);
    final known = headings.map((e) => e.key).toSet();
    final split = pdfSplitSpreadTitleByKnown(title, known);
    if (split == null) return (firstIdx: -1, secondIdx: -1);
    return (
      firstIdx: headings.indexWhere((e) => e.key == split.first),
      secondIdx: headings.indexWhere((e) => e.key == split.second),
    );
  }

  /// בתצוגת ספר — שורות העמוד השני בספירייד (עד [secondIdx]), כדי שמפרשי שני
  /// העמודים יוצגו יחד עם הטווח הראשי. בעמוד יחיד מחזיר רשימה ריקה.
  List<int> _spreadExtraLines(({int firstIdx, int secondIdx}) selection) {
    if (selection.firstIdx < 0 || selection.secondIdx <= selection.firstIdx) {
      return const [];
    }
    final lines = <int>[];
    for (int i = selection.firstIdx; i <= selection.secondIdx; i++) {
      lines.addAll(_linesForNavItem(i, _kAllPara));
    }
    return lines;
  }

  void _openSearchPanel() {
    setState(() => _navPaneOpen = true);
    _navTabController.animateTo(_searchTabIndex);
  }

  void _openCommentatorsTab() {
    setState(() => _navPaneOpen = true);
    _navTabController.animateTo(_commentatorsTabIndex);
  }

  void _zoomIn(BuildContext context) {
    final bloc = context.read<SettingsBloc>();
    final next = (bloc.state.commentatorsFontSize + 2).clamp(10.0, 40.0);
    bloc.add(UpdateCommentatorsFontSize(next));
  }

  void _zoomOut(BuildContext context) {
    final bloc = context.read<SettingsBloc>();
    final next = (bloc.state.commentatorsFontSize - 2).clamp(10.0, 40.0);
    bloc.add(UpdateCommentatorsFontSize(next));
  }

  /// ניווט לכותרת הקודמת (כל הכותרת) — מקביל ל"הפרק הקודם" בכרטיסיית הטקסט.
  void _navigateToPrevHeading() {
    if (!_isNavigationReady || _selectedHeadingIdx <= 0) return;
    setState(() {
      _selectedHeadingIdx--;
      _selectedParagraphIdx = _kAllPara;
      _expandedHeadings.add(_selectedHeadingIdx);
      _extraLines.clear();
    });
  }

  /// ניווט לכותרת הבאה (כל הכותרת) — מקביל ל"הפרק הבא" בכרטיסיית הטקסט.
  void _navigateToNextHeading() {
    final headings = _sortedHeadings;
    if (!_isNavigationReady ||
        headings == null ||
        _selectedHeadingIdx + 1 >= headings.length) {
      return;
    }
    setState(() {
      _selectedHeadingIdx++;
      _selectedParagraphIdx = _kAllPara;
      _expandedHeadings.add(_selectedHeadingIdx);
      _extraLines.clear();
    });
  }

  Future<void> _loadTextContent() async {
    final tab = widget.tab.sourceTab;
    try {
      final library = await DataRepository.instance.library;
      TextBook? textBook =
          library.findBookByTitle(tab.book.title, TextBook) as TextBook?;
      textBook ??= library.findBookByTitleFlexible(tab.book.title, TextBook)
          as TextBook?;
      if (textBook == null || !mounted) return;
      final text = await textBook.text;
      if (!mounted) return;
      setState(() {
        _textLines = text.split('\n');
      });
    } catch (e) {
      debugPrint('שגיאה בטעינת תוכן טקסט: $e');
    }
  }

  /// בשחזור מהפעלה קודמת ה-sourceTab נבנה מחדש וריק — אין מסך PDF חי שמילא
  /// אותו. כאן נטענים ה-headings וה-links בעצמנו אם הם חסרים, כדי שהכרטיסייה
  /// תהיה עצמאית לחלוטין (כמו כרטיסיית הטקסט). בפתיחה רגילה הנתונים כבר קיימים
  /// ולכן זה no-op.
  Future<void> _ensureDataLoaded() async {
    final tab = widget.tab.sourceTab;

    if (tab.pdfHeadings == null) {
      final headings = await PdfHeadings.loadFromDatabase(
        tab.book.title,
        categoryId: tab.book.categoryId,
        filePath: tab.book.filePath,
        preferUserBooks: tab.book.isUserBook,
      );
      if (!mounted) return;
      if (headings != null) {
        tab.pdfHeadings = headings;
        _initHeadings();
        setState(() {});
      }
    }

    if (tab.links.isEmpty) {
      try {
        final library = await DataRepository.instance.library;
        TextBook? textBook =
            library.findBookByTitle(tab.book.title, TextBook) as TextBook?;
        textBook ??= library.findBookByTitleFlexible(tab.book.title, TextBook)
            as TextBook?;
        if (textBook != null) {
          final loaded = await textBook.links
            ..sort((a, b) => a.index1.compareTo(b.index1));
          if (!mounted) return;
          tab.links = loaded;
        }
      } catch (e) {
        debugPrint('שגיאה בטעינת links לכרטיסיית מפרשים: $e');
      }
      if (!mounted) return;
      tab.linksLoadingNotifier.value = false;
      _loadCommentatorGroups();
      setState(() {});
    }

    // פתיחה מסימניה/שחזור: ה-sourceTab נבנה מחדש ללא currentTitle — נמקם את
    // הכותרת לפי עמוד ה-PDF השמור (אחרת תמיד נפתחת הכותרת הראשונה).
    if (tab.currentTitle.value.isEmpty && tab.pageNumber > 1) {
      await _resolveHeadingForPage(tab.pageNumber);
    }
  }

  /// ממקם את הכותרת הנבחרת לפי עמוד PDF נתון (פתיחה מסימניה/שחזור): ממיר את
  /// שורת כל כותרת לעמוד ומבצע חיפוש בינארי לכותרת בעלת העמוד הגבוה ביותר
  /// שאינו עולה על עמוד היעד (הכותרות ממוינות לפי שורה → העמודים מונוטוניים).
  Future<void> _resolveHeadingForPage(int targetPage) async {
    final headings = _sortedHeadings;
    if (headings == null || headings.isEmpty) return;
    try {
      final library = await DataRepository.instance.library;
      var textBook = library.findBookByTitle(
          widget.tab.sourceTab.book.title, TextBook) as TextBook?;
      textBook ??= library.findBookByTitleFlexible(
          widget.tab.sourceTab.book.title, TextBook) as TextBook?;
      if (textBook == null) return;

      int lo = 0;
      int hi = headings.length - 1;
      int best = 0;
      while (lo <= hi) {
        final mid = (lo + hi) ~/ 2;
        final page = await textToPdfPage(textBook, headings[mid].value);
        if (page == null) return; // אין מיפוי אמין — נשארים בברירת המחדל
        if (page <= targetPage) {
          best = mid;
          lo = mid + 1;
        } else {
          hi = mid - 1;
        }
      }
      if (!mounted) return;
      setState(() {
        _selectedHeadingIdx = best;
        _selectedParagraphIdx = _kAllPara;
      });
    } catch (e) {
      debugPrint('שגיאה במיפוי עמוד לכותרת בכרטיסיית מפרשים: $e');
    }
  }

  /// טוען את קבוצות המפרשים (לפי תקופות) מתוך links של ה-sourceTab — זהה
  /// לחישוב שב-[PdfCommentaryPanel], לצורך לשונית "מפרשים".
  Future<void> _loadCommentatorGroups() async {
    final commentatorsSet = <String>{};
    for (final link in widget.tab.sourceTab.links) {
      if (link.connectionType == 'COMMENTARY' ||
          link.connectionType == 'TARGUM') {
        commentatorsSet.add(utils.getTitleFromPath(link.path2));
      }
    }
    final available = commentatorsSet.toList();
    await _applyDefaultCommentatorsIfNeeded(available);
    final eras = await utils.splitByEra(available);
    final known = <String>{
      ...?eras['תורה שבכתב'],
      ...?eras['חז"ל'],
      ...?eras['ראשונים'],
      ...?eras['אחרונים'],
      ...?eras['מחברי זמננו'],
    };
    final others = (eras['מפרשים נוספים'] ?? [])
        .toSet()
        .union(available.where((c) => !known.contains(c)).toSet())
        .toList();
    if (!mounted) return;
    setState(() {
      _commentatorGroups = [
        CommentatorGroup(
            title: 'תורה שבכתב', commentators: eras['תורה שבכתב'] ?? const []),
        CommentatorGroup(title: 'חז"ל', commentators: eras['חז"ל'] ?? const []),
        CommentatorGroup(
            title: 'ראשונים', commentators: eras['ראשונים'] ?? const []),
        CommentatorGroup(
            title: 'אחרונים', commentators: eras['אחרונים'] ?? const []),
        CommentatorGroup(
            title: 'מחברי זמננו',
            commentators: eras['מחברי זמננו'] ?? const []),
        CommentatorGroup(title: 'שאר מפרשים', commentators: others),
      ];
    });
  }

  /// בוחר אוטומטית את מפרשי ברירת המחדל של הספר (כמו בכרטיסיית הטקסט), כל עוד
  /// אין בחירה פר-ספר שמורה ואין מפרשים פעילים. [available] = המפרשים הזמינים
  /// מתוך ה-links של הספר.
  Future<void> _applyDefaultCommentatorsIfNeeded(List<String> available) async {
    final sourceTab = widget.tab.sourceTab;
    if (available.isEmpty || sourceTab.activeCommentators.isNotEmpty) return;

    final saved = await PdfBookPerBookSettings.load(sourceTab.book.title);
    final selection = await DefaultCommentators.resolveAutoSelection(
      sourceTab.book,
      availableCommentators: available,
      savedSelection: saved?.activeCommentators,
    );
    if (!mounted ||
        selection == null ||
        sourceTab.activeCommentators.isNotEmpty) {
      return;
    }
    setState(() => sourceTab.activeCommentators.addAll(selection));
  }

  @override
  void dispose() {
    FocusRepository().unregisterTabContentFocusRequester(widget.tab);
    widget.tab.sourceTab.currentTitle.removeListener(_syncWithSourceTab);
    _navTabController.removeListener(_handleTabChanged);
    _navTabController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _navSearchController.dispose();
    _totalResultsNotifier.dispose();
    _currentIdxNotifier.dispose();
    _allExpandedInChild.dispose();
    super.dispose();
  }

  /// פסקאות (שורות טקסט לא-ריקות) בתוך heading נבחר
  List<({int lineIdx, String text})> _getParagraphs(int headingIdx) {
    final lines = _textLines;
    if (lines == null) return const [];
    final headings = _sortedHeadings;
    if (headings == null || headingIdx >= headings.length) return const [];
    final start = headings[headingIdx].value;
    final headingText = headings[headingIdx].key.trim();
    final end = headingIdx + 1 < headings.length
        ? headings[headingIdx + 1].value - 1
        : lines.length - 1;
    final result = <({int lineIdx, String text})>[];
    for (int i = start; i <= end && i < lines.length; i++) {
      final clean = utils.stripHtmlIfNeeded(lines[i]).trim();
      if (i == start && clean == headingText) {
        continue;
      }
      if (clean.isNotEmpty) result.add((lineIdx: i, text: clean));
    }
    return result;
  }

  /// טווח שורות לחלונית המפרשים
  ({int start, int end}) _getLineRangeForPara(
    int headingIdx,
    List<({int lineIdx, String text})> paragraphs,
    int paraIdx,
  ) {
    if (paraIdx != _kAllPara &&
        paragraphs.isNotEmpty &&
        paraIdx < paragraphs.length) {
      final lineIdx = paragraphs[paraIdx].lineIdx;
      final nextLineIdx = paraIdx + 1 < paragraphs.length
          ? paragraphs[paraIdx + 1].lineIdx - 1
          : lineIdx + 1;
      return (start: lineIdx, end: nextLineIdx);
    }
    final headings = _sortedHeadings;
    if (headings == null || headingIdx >= headings.length) {
      final fallback = widget.tab.sourceTab.currentTextLineNumber ?? 0;
      return (
        start: fallback,
        end: widget.tab.sourceTab.currentTextLineNumberEnd ?? fallback + 50,
      );
    }
    final start = headings[headingIdx].value;
    final lastLineIndex = (_textLines?.length ?? 0) - 1;
    final end = headingIdx + 1 < headings.length
        ? headings[headingIdx + 1].value - 1
        : (lastLineIndex >= start ? lastLineIndex : start);
    return (start: start, end: end);
  }

  /// Ctrl (או Cmd ב-macOS) לחוץ כרגע — לזיהוי ריבוי-בחירה בלחיצת ניווט.
  bool _isCtrlPressed() =>
      HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isMetaPressed;

  /// מספרי השורות של טווח כותרת/פסקה (מוגבל למניעת קבוצות ענק).
  List<int> _linesForNavItem(int headingIdx, int paraIdx) {
    final paras = _getParagraphs(headingIdx);
    final safe = paraIdx == _kAllPara || paras.isEmpty
        ? _kAllPara
        : paraIdx.clamp(0, paras.length - 1);
    final range = _getLineRangeForPara(headingIdx, paras, safe);
    if (range.end < range.start || range.end - range.start > 3000) {
      return [range.start];
    }
    return [for (int l = range.start; l <= range.end; l++) l];
  }

  /// Ctrl+לחיצה על פריט ניווט: מוסיף/מסיר את שורותיו מריבוי-הבחירה (toggle).
  void _ctrlToggleNavItem(int headingIdx, int paraIdx) {
    final lines = _linesForNavItem(headingIdx, paraIdx);
    if (lines.isEmpty) return;
    setState(() {
      if (lines.every(_extraLines.contains)) {
        _extraLines.removeAll(lines);
      } else {
        // שמירת הטווח הראשי הנוכחי כחלק מהאיחוד לפני הוספת הקטע החדש.
        _extraLines.addAll(
            _linesForNavItem(_selectedHeadingIdx, _selectedParagraphIdx));
        _extraLines.addAll(lines);
      }
    });
  }

  /// האם שורות פריט הניווט נמצאות בריבוי-הבחירה (להדגשה).
  bool _isNavItemInMulti(int headingIdx, int paraIdx) {
    if (_extraLines.isEmpty) return false;
    return _linesForNavItem(headingIdx, paraIdx).any(_extraLines.contains);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // נדרש ע"י AutomaticKeepAliveClientMixin
    if (_sortedHeadings == null) _initHeadings();
    final paragraphs = _getParagraphs(_selectedHeadingIdx);
    final safeParaIdx = _selectedParagraphIdx == _kAllPara || paragraphs.isEmpty
        ? _kAllPara
        : _selectedParagraphIdx.clamp(0, paragraphs.length - 1);
    final range =
        _getLineRangeForPara(_selectedHeadingIdx, paragraphs, safeParaIdx);

    return Focus(
      autofocus: true,
      onKeyEvent: _handlePrintShortcut,
      child: Scaffold(
        body: Column(
          children: [
            _buildAppTopBar(context),
            Expanded(
              child: AdaptiveSidePane(
                isOpen: _navPaneOpen || _pinLeftPane,
                alignment: AlignmentDirectional.centerEnd,
                paneWidth: 320,
                onClose: () {
                  if (!_pinLeftPane) setState(() => _navPaneOpen = false);
                },
                paneContent: _buildSidePane(context),
                mainContent: ValueListenableBuilder<bool>(
                  valueListenable: widget.tab.sourceTab.linksLoadingNotifier,
                  builder: (context, linksLoading, _) => PdfCommentaryPanel(
                    key: _panelKey,
                    tab: widget.tab.sourceTab,
                    linksCount: widget.tab.sourceTab.links.length,
                    linksLoading: linksLoading,
                    isFullScreen: true,
                    enableInternalFilter: false,
                    onSelectCommentatorsRequested: _openCommentatorsTab,
                    lineStartOverride: range.start,
                    lineEndOverride: range.end,
                    extraLineIndices: _extraLines.isEmpty ? null : _extraLines,
                    removeNikud: _removeNikud,
                    removePunctuation: _removePunctuation,
                    openBookCallback: (tab) {
                      if (tab is TextBookTab) {
                        openBook(context, tab.book, tab.index, '',
                            ignoreHistory: false);
                      }
                    },
                    fontSize: 16.0,
                    externalSearchController: _searchController,
                    externalTotalResultsNotifier: _totalResultsNotifier,
                    externalCurrentIndexNotifier: _currentIdxNotifier,
                    externalAllExpandedNotifier: _allExpandedInChild,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// מטפל בקיצור ההדפסה המוגדר — פעיל רק בכרטיסיית המפרשים.
  KeyEventResult _handlePrintShortcut(FocusNode node, KeyEvent event) {
    final printShortcut =
        Settings.getValue<String>('key-shortcut-print') ?? 'ctrl+p';
    if (ShortcutHelper.matchesShortcut(event, printShortcut)) {
      _panelKey.currentState?.printDisplayedCommentaries();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _navigateToPrevParagraph() {
    if (!_isNavigationReady) return;
    _extraLines.clear();
    final paragraphs = _getParagraphs(_selectedHeadingIdx);
    if (_selectedParagraphIdx > 0 && paragraphs.isNotEmpty) {
      setState(() => _selectedParagraphIdx--);
      return;
    }
    // מפסקה הראשונה → חזרה ל"כל הכותרת"
    if (_selectedParagraphIdx == 0) {
      setState(() => _selectedParagraphIdx = _kAllPara);
      return;
    }
    // מ"כל הכותרת" → הכותרת הקודמת (כולה)
    if (_selectedHeadingIdx <= 0) return;
    final prevHeadingIdx = _selectedHeadingIdx - 1;
    setState(() {
      _selectedHeadingIdx = prevHeadingIdx;
      _selectedParagraphIdx = _kAllPara;
      _expandedHeadings.add(prevHeadingIdx);
    });
  }

  void _navigateToNextParagraph() {
    if (!_isNavigationReady) return;
    _extraLines.clear();
    final paragraphs = _getParagraphs(_selectedHeadingIdx);
    // מ"כל הכותרת" (-1) → פסקה ראשונה (0); אחרת לפסקה הבאה
    if (_selectedParagraphIdx + 1 < paragraphs.length) {
      setState(() => _selectedParagraphIdx++);
      return;
    }
    if (_sortedHeadings == null ||
        _selectedHeadingIdx + 1 >= _sortedHeadings!.length) {
      return;
    }
    final nextHeadingIdx = _selectedHeadingIdx + 1;
    setState(() {
      _selectedHeadingIdx = nextHeadingIdx;
      _selectedParagraphIdx = _kAllPara;
      _expandedHeadings.add(nextHeadingIdx);
    });
  }

  void _showBookmarksForCurrentBook(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => BookmarksDialog(bookFilter: widget.tab.sourceTab.book),
    );
  }

  Future<void> _addBookmark(BuildContext context) async {
    final sourceTab = widget.tab.sourceTab;
    final bookmarkBloc = context.read<BookmarkBloc>();
    final headings = _sortedHeadings;
    final hasSelectedHeading = headings != null &&
        _selectedHeadingIdx >= 0 &&
        _selectedHeadingIdx < headings.length;

    // הכותרת הנבחרת בכרטיסייה (כפי שמוצג בסרגל), ולא מצב הספר המקורי
    final heading = hasSelectedHeading
        ? headings[_selectedHeadingIdx].key.trim()
        : sourceTab.currentTitle.value.trim();

    // עמוד ברירת מחדל — מצב הספר המקורי אם אין כותרת נבחרת
    int page = sourceTab.pdfViewerController.isReady
        ? (sourceTab.pdfViewerController.pageNumber ?? sourceTab.pageNumber)
        : sourceTab.pageNumber;

    // המרת שורת הכותרת הנבחרת לעמוד PDF מדויק; אם לא ניתן — נשארים על ברירת המחדל
    if (hasSelectedHeading) {
      try {
        final library = await DataRepository.instance.library;
        var textBook = library.findBookByTitle(sourceTab.book.title, TextBook)
            as TextBook?;
        textBook ??= library.findBookByTitleFlexible(
            sourceTab.book.title, TextBook) as TextBook?;
        if (textBook != null) {
          final mapped = await textToPdfPage(
              textBook, headings[_selectedHeadingIdx].value);
          if (mapped != null) page = mapped;
        }
      } catch (e) {
        debugPrint('שגיאה במיפוי כותרת לעמוד עבור סימניה: $e');
      }
    }

    final ref = heading.isNotEmpty
        ? '${sourceTab.book.title} $heading'
        : '${sourceTab.book.title} עמוד $page';

    final added = bookmarkBloc.addBookmark(
      ref: 'מפרשים | $ref',
      book: sourceTab.book,
      index: page,
      commentatorsToShow: sourceTab.activeCommentators.toList(),
      targetKind: BookmarkTargetKind.commentators,
    );
    UiSnack.show(added ? 'הסימניה נוספה בהצלחה' : 'הסימניה כבר קיימת');
  }

  Widget _buildAppTopBar(BuildContext context) {
    final isCompact = context.read<SettingsBloc>().state.compactMenuMode;
    return AppTopBar(
      leadingItems: [
        AppTopBarItem(
          widget: ToolbarActionButton(
            tooltip: 'ניווט',
            icon: FluentIcons.navigation_24_regular,
            compact: isCompact,
            onPressed: () {
              setState(() => _navPaneOpen = !_navPaneOpen);
              if (_navPaneOpen && _navTabController.index == 0) {
                _scrollNavToSelectedHeading();
              }
            },
          ),
        ),
      ],
      center: ReaderNavCenter(
        title: Text(
          'מפרשים על ${widget.tab.sourceTab.book.title}',
          style: AppTopBar.titleStyle(context),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
        prevMajorTooltip: 'הכותרת הקודמת',
        prevMinorTooltip: 'הקטע הקודם',
        nextMinorTooltip: 'הקטע הבא',
        nextMajorTooltip: 'הכותרת הבאה',
        onPrevMajor: _navigateToPrevHeading,
        onPrevMinor: _navigateToPrevParagraph,
        onNextMinor: _navigateToNextParagraph,
        onNextMajor: _navigateToNextHeading,
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
                  tooltip: _removeNikud ? 'הצג ניקוד' : 'הסתר ניקוד',
                  icon: _removeNikud
                      ? FluentIcons.text_font_24_regular
                      : FluentIcons.text_font_info_24_regular,
                  compact: isCompact,
                  onPressed: () => setState(() => _removeNikud = !_removeNikud),
                ),
                icon: _removeNikud
                    ? FluentIcons.text_font_24_regular
                    : FluentIcons.text_font_info_24_regular,
                tooltip: _removeNikud ? 'הצג ניקוד' : 'הסתר ניקוד',
                onPressed: () => setState(() => _removeNikud = !_removeNikud),
              ),
              // פיסוק
              ActionButtonData(
                widget: ToolbarActionButton(
                  tooltip: _removePunctuation ? 'הצג פיסוק' : 'הסתר פיסוק',
                  icon: _removePunctuation
                      ? FluentIcons.text_quote_24_regular
                      : FluentIcons.text_clear_formatting_24_regular,
                  compact: isCompact,
                  onPressed: () =>
                      setState(() => _removePunctuation = !_removePunctuation),
                ),
                icon: _removePunctuation
                    ? FluentIcons.text_quote_24_regular
                    : FluentIcons.text_clear_formatting_24_regular,
                tooltip: _removePunctuation ? 'הצג פיסוק' : 'הסתר פיסוק',
                onPressed: () =>
                    setState(() => _removePunctuation = !_removePunctuation),
              ),
              // הדפסת המפרשים המוצגים
              ActionButtonData(
                widget: ToolbarActionButton(
                  tooltip: 'הדפסה',
                  icon: FluentIcons.print_24_regular,
                  compact: isCompact,
                  onPressed: () =>
                      _panelKey.currentState?.printDisplayedCommentaries(),
                ),
                icon: FluentIcons.print_24_regular,
                tooltip: 'הדפסה',
                onPressed: () =>
                    _panelKey.currentState?.printDisplayedCommentaries(),
              ),
              // חיפוש
              ActionButtonData(
                widget: ToolbarActionButton(
                  tooltip: 'חיפוש',
                  icon: FluentIcons.search_24_regular,
                  compact: isCompact,
                  onPressed: _openSearchPanel,
                ),
                icon: FluentIcons.search_24_regular,
                tooltip: 'חיפוש',
                onPressed: _openSearchPanel,
              ),
              // כיווץ/הרחבת כל המפרשים
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
                      compact: isCompact,
                      onPressed: () =>
                          _panelKey.currentState?.toggleAllExpanded(),
                    );
                  },
                ),
                icon: _allExpandedInChild.value
                    ? FluentIcons.arrow_collapse_all_24_regular
                    : FluentIcons.arrow_expand_all_24_regular,
                tooltip: _allExpandedInChild.value
                    ? 'כווץ את כל המפרשים'
                    : 'הרחב את כל המפרשים',
                onPressed: () => _panelKey.currentState?.toggleAllExpanded(),
              ),
              // הוסף סימניה
              ActionButtonData(
                widget: ToolbarActionButton(
                  tooltip: 'הוסף סימניה',
                  icon: FluentIcons.bookmark_add_24_regular,
                  compact: isCompact,
                  onPressed: () => _addBookmark(context),
                ),
                icon: FluentIcons.bookmark_add_24_regular,
                tooltip: 'הוסף סימניה',
                onPressed: () => _addBookmark(context),
              ),
              // הגדל גופן
              ActionButtonData(
                widget: ToolbarActionButton(
                  tooltip: 'הגדל את גודל הטקסט',
                  icon: FluentIcons.zoom_in_24_regular,
                  compact: isCompact,
                  onPressed: () => _zoomIn(context),
                ),
                icon: FluentIcons.zoom_in_24_regular,
                tooltip: 'הגדל את גודל הטקסט',
                onPressed: () => _zoomIn(context),
              ),
              // הקטן גופן
              ActionButtonData(
                widget: ToolbarActionButton(
                  tooltip: 'הקטן את גודל הטקסט',
                  icon: FluentIcons.zoom_out_24_regular,
                  compact: isCompact,
                  onPressed: () => _zoomOut(context),
                ),
                icon: FluentIcons.zoom_out_24_regular,
                tooltip: 'הקטן את גודל הטקסט',
                onPressed: () => _zoomOut(context),
              ),
            ],
            alwaysInMenu: [
              ActionButtonData(
                widget: ToolbarActionButton(
                  tooltip: 'סימניות בספר זה',
                  icon: FluentIcons.bookmark_multiple_24_regular,
                  compact: isCompact,
                  onPressed: () => _showBookmarksForCurrentBook(context),
                ),
                icon: FluentIcons.bookmark_multiple_24_regular,
                tooltip: 'סימניות בספר זה',
                onPressed: () => _showBookmarksForCurrentBook(context),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// פאנל הצד — סרגל 3 לשוניות זהה לכרטיסיית הטקסט (ניווט / מפרשים / חיפוש)
  /// עם כפתור נעיצה בפינה.
  Widget _buildSidePane(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
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
        Expanded(
          child: TabBarView(
            controller: _navTabController,
            children: [
              _buildNavPanel(),
              _buildCommentatorsSelectionTab(),
              _buildSearchPanel(),
            ],
          ),
        ),
      ],
    );
  }

  /// לשונית "מפרשים" — בחירת המפרשים להצגה (זהה לכרטיסיית הטקסט).
  Widget _buildCommentatorsSelectionTab() {
    if (_commentatorGroups.isEmpty) {
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
      groups: _commentatorGroups,
      selectedCommentators: widget.tab.sourceTab.activeCommentators.toList(),
      bookTitle: widget.tab.sourceTab.book.title,
      onSelectionChanged: (list) async {
        setState(() {
          widget.tab.sourceTab.activeCommentators
            ..clear()
            ..addAll(list);
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
        // שמירה פר-ספר תמיד (לא תלוי ב-enablePerBookSettings) כדי שהבחירה
        // תיטען בכל פתיחה.
        final settings = PdfBookPerBookSettings(
          activeCommentators:
              List.from(widget.tab.sourceTab.activeCommentators),
        );
        await settings.save(widget.tab.sourceTab.book.title);
      },
    );
  }

  Widget _buildNavPanel() {
    final headings = _sortedHeadings;
    if (headings == null || headings.isEmpty) {
      return const Center(
        child: Text('אין ניווט'),
      );
    }

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _navSearchController,
      builder: (context, val, _) {
        final filteredIdx = _navFilteredIndices(val.text);

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: RtlTextField(
                controller: _navSearchController,
                decoration: InputDecoration(
                  hintText: 'איתור כותרת...',
                  prefixIcon: const Icon(FluentIcons.search_24_regular),
                  suffixIcon: val.text.trim().isNotEmpty
                      ? IconButton(
                          icon: const Icon(FluentIcons.dismiss_24_regular),
                          onPressed: () => _navSearchController.clear(),
                        )
                      : null,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ScrollablePositionedList.builder(
                itemScrollController: _navScrollController,
                itemCount: filteredIdx.length,
                itemBuilder: (context, listIdx) {
                  final idx = filteredIdx[listIdx];
                  final isActiveHeading = idx == _selectedHeadingIdx;
                  final isExpanded = _expandedHeadings.contains(idx);
                  final paras = _getParagraphs(idx);

                  final headingRow = _buildHeadingRow(
                    context: context,
                    headingText: headings[idx].key,
                    // מודגש כשנבחרה "כל הכותרת", או כשהיא בריבוי-הבחירה.
                    isSelected: (isActiveHeading &&
                            _selectedParagraphIdx == _kAllPara) ||
                        _isNavItemInMulti(idx, _kAllPara),
                    isExpanded: isExpanded,
                    hasChildren: paras.isNotEmpty,
                    // לחיצה על גוף הכותרת = בחירת כל הכותרת (כל המפרשים) + הרחבה
                    onTap: () {
                      if (_isCtrlPressed()) {
                        _ctrlToggleNavItem(idx, _kAllPara);
                        return;
                      }
                      setState(() {
                        _selectedHeadingIdx = idx;
                        _selectedParagraphIdx = _kAllPara;
                        if (paras.isNotEmpty) _expandedHeadings.add(idx);
                        _searchController.clear();
                        _extraLines.clear();
                      });
                    },
                    // לחיצה על החץ = הרחבה/כיווץ בלבד, בלי לשנות את הבחירה
                    onToggleExpand: paras.isNotEmpty
                        ? () {
                            setState(() {
                              if (isExpanded) {
                                _expandedHeadings.remove(idx);
                              } else {
                                _expandedHeadings.add(idx);
                              }
                            });
                          }
                        : null,
                  );

                  if (paras.isEmpty || !isExpanded) {
                    return headingRow;
                  }

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      headingRow,
                      ...List.generate(paras.length, (pi) {
                        final words = paras[pi]
                            .text
                            .split(RegExp(r'\s+'))
                            .where((w) => w.isNotEmpty)
                            .take(4)
                            .join(' ');
                        final isParaSelected =
                            (isActiveHeading && _selectedParagraphIdx == pi) ||
                                _isNavItemInMulti(idx, pi);
                        return _buildParagraphRow(
                          context: context,
                          text: words,
                          isSelected: isParaSelected,
                          onTap: () {
                            if (_isCtrlPressed()) {
                              _ctrlToggleNavItem(idx, pi);
                              return;
                            }
                            setState(() {
                              _selectedHeadingIdx = idx;
                              _selectedParagraphIdx = pi;
                              _searchController.clear();
                              _extraLines.clear();
                            });
                          },
                        );
                      }),
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeadingRow({
    required BuildContext context,
    required String headingText,
    required bool isSelected,
    required bool isExpanded,
    required bool hasChildren,
    required VoidCallback onTap,
    VoidCallback? onToggleExpand,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? AppSurfaces.selectedItem(colorScheme) : null,
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).dividerColor,
              width: 0.5,
            ),
          ),
        ),
        padding: const EdgeInsets.only(right: 16, left: 8, top: 12, bottom: 12),
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
                headingText,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: colorScheme.primary,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
            if (hasChildren)
              IconButton(
                icon: Icon(
                  isExpanded
                      ? FluentIcons.chevron_up_24_regular
                      : FluentIcons.chevron_down_24_regular,
                  color: colorScheme.onSurfaceVariant,
                  size: 20,
                ),
                onPressed: onToggleExpand,
                tooltip: isExpanded ? 'כווץ' : 'הרחב',
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildParagraphRow({
    required BuildContext context,
    required String text,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
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
              FluentIcons.text_bullet_list_24_regular,
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

  Widget _buildSearchPanel() {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _searchController,
      builder: (context, val, __) {
        final hasQuery = val.text.isNotEmpty;
        return ValueListenableBuilder<int>(
          valueListenable: _totalResultsNotifier,
          builder: (context, total, _) => ValueListenableBuilder<int>(
            valueListenable: _currentIdxNotifier,
            builder: (context, currentIdx, _) => SearchPaneBase(
              searchController: _searchController,
              focusNode: _searchFocusNode,
              hintText: 'חיפוש במפרשים...',
              isNoResults: hasQuery && total == 0,
              resetSearchCallback: _searchController.clear,
              resultCountString: hasQuery && total > 0
                  ? 'תוצאה ${currentIdx + 1} מתוך $total'
                  : null,
              resultToolbar: hasQuery && total > 0
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OtzariaSearchAction.prevResult(
                          onPressed: currentIdx > 0
                              ? () =>
                                  _panelKey.currentState?.navigateSearchPrev()
                              : null,
                        ),
                        OtzariaSearchAction.nextResult(
                          onPressed: currentIdx < total - 1
                              ? () =>
                                  _panelKey.currentState?.navigateSearchNext()
                              : null,
                        ),
                      ],
                    )
                  : null,
              resultsWidget: const SizedBox.shrink(),
            ),
          ),
        );
      },
    );
  }
}
