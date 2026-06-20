import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/theme/app_fonts.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_settings_manager.dart';
import 'package:otzaria/text_book/view/page_shape/utils/default_commentators.dart';
import 'package:otzaria/text_book/view/page_shape/links_notes_sidebar.dart';
import 'package:otzaria/text_book/models/commentator_group.dart';
import 'package:otzaria/text_book/view/page_shape/simple_text_viewer.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_commentary_selection.dart';
import 'package:otzaria/text_book/view/page_shape/utils/commentary_sync_helper.dart';
import 'package:otzaria/text_book/view/page_shape/page_shape_settings_dialog.dart';
import 'package:otzaria/text_book/view/commentary_list_base.dart';
import 'package:otzaria/text_book/widgets/text_book_state_builder.dart';
import 'package:otzaria/widgets/feedback/loading_indicator.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/commentators_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/utils/text/ref_helper.dart';
import 'package:otzaria/widgets/layout/resizable_drag_handle.dart';
import 'package:otzaria/widgets/layout/adaptive_side_pane.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:collection/collection.dart';
import 'dart:async';
import 'dart:isolate';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/data/book_locator.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/text_book/utils/reading_segment_navigation.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/text_book/view/selection/selection_sync_controller.dart';
import 'package:otzaria/widgets/navigation/panel_tab_header.dart';

/// קבועים לחישוב רוחב חלוניות המפרשים
const double _kCommentaryPaneWidthFactor = 0.17;

/// רוחב הכותרת האנכית + רווחים + מפריד (20 לכותרת + 4 לרווח + 8 למפריד)
const double _kCommentaryLabelAndSpacingWidth = 32.0;

/// אינדקס לשונית "קישורים" ב-[LinksNotesSidebar] (0 = קישורים, 1 = הערות)
const int _kLinksTabIndex = 0;

/// מסך תצוגת צורת הדף - מציג את הטקסט המרכזי עם מפרשים מסביב
class PageShapeScreen extends StatefulWidget {
  final Function(OpenedTab) openBookCallback;
  final ValueNotifier<int?>? sidebarTabNotifier;

  /// בקשה לפתיחת דיאלוג הגדרות צורת הדף (מכפתור גלגל השיניים בסרגל העליון).
  /// המסך פותח את הדיאלוג בעצמו כדי שהשינויים יוחלו עליו בעדכון חי.
  final ValueNotifier<int>? openSettingsNotifier;
  final ValueChanged<String?>? onOpenSearch;
  final ScrollOffsetController? scrollOffsetController;
  final TextBookTab? tab;

  const PageShapeScreen({
    super.key,
    required this.openBookCallback,
    this.sidebarTabNotifier,
    this.openSettingsNotifier,
    this.onOpenSearch,
    this.scrollOffsetController,
    this.tab,
  });

  @override
  State<PageShapeScreen> createState() => _PageShapeScreenState();
}

class _PageShapeScreenState extends State<PageShapeScreen> {
  String? _leftCommentator;
  String? _rightCommentator;
  String? _bottomCommentator;
  String? _bottomRightCommentator;
  bool _isLoadingConfig = true;
  bool _isLeftSidebarOpen = false;
  int _leftSidebarTabIndex = 0;
  final SelectionSyncController _selectionSyncController =
      SelectionSyncController();

  // גדלים לחלוניות - יחושבו לפי גודל המסך
  double? _leftSidebarWidth;
  double? _leftWidth;
  double? _rightWidth;
  double? _bottomHeight;
  double?
      _bottomLeftWidth; // רוחב המפרש התחתון השמאלי (כאשר יש 2 מפרשים תחתונים)

  // הגדרות הצגת טורים
  Map<String, bool> _columnVisibility = {
    'left': true,
    'right': true,
    'bottom': true,
    'bottomRight': true,
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadConfiguration();
    _loadSizes();
  }

  /// טעינת גדלים שמורים או חישוב ברירות מחדל
  void _loadSizes() {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    _leftSidebarWidth =
        Settings.getValue<double>('page_shape_left_sidebar_width') ??
            screenWidth * 0.22;
    _leftWidth = Settings.getValue<double>('page_shape_left_width') ??
        screenWidth * 0.17;
    _rightWidth = Settings.getValue<double>('page_shape_right_width') ??
        screenWidth * 0.17;
    _bottomHeight = Settings.getValue<double>('page_shape_bottom_height') ??
        screenHeight * 0.27;
    _bottomLeftWidth =
        Settings.getValue<double>('page_shape_bottom_left_width') ??
            screenWidth * 0.5;

    setState(() {});

    // אם הופעלה שמירת הגדרות פר-ספר, טען את רוחבי הטורים השמורים לספר זה
    // (סרגל הצד נשאר גלובלי).
    if (context.read<SettingsBloc>().state.enablePerBookSettings) {
      _loadPerBookSizes();
    }
  }

  /// טעינת רוחבי הטורים השמורים לספר הנוכחי (אסינכרוני).
  /// דורס את הערכים הגלובליים שנטענו ב-[_loadSizes] רק עבור שדות שנשמרו לספר.
  Future<void> _loadPerBookSizes() async {
    final bookTitle = widget.tab?.book.title;
    if (bookTitle == null) return;

    final settings = await TextBookPerBookSettings.load(bookTitle);
    if (settings == null || !mounted) return;

    setState(() {
      if (settings.pageShapeLeftWidth != null) {
        _leftWidth = settings.pageShapeLeftWidth;
      }
      if (settings.pageShapeRightWidth != null) {
        _rightWidth = settings.pageShapeRightWidth;
      }
      if (settings.pageShapeBottomHeight != null) {
        _bottomHeight = settings.pageShapeBottomHeight;
      }
      if (settings.pageShapeBottomLeftWidth != null) {
        _bottomLeftWidth = settings.pageShapeBottomLeftWidth;
      }
    });
  }

  /// שמירת גדלים
  void _saveSizes() {
    // סרגל הצד נשמר תמיד גלובלית (אינו חלק מרוחב הטורים).
    if (_leftSidebarWidth != null) {
      Settings.setValue<double>(
          'page_shape_left_sidebar_width', _leftSidebarWidth!);
    }

    // אם הופעלה שמירת הגדרות פר-ספר, רוחבי הטורים נשמרים לספר הנוכחי בלבד.
    if (context.read<SettingsBloc>().state.enablePerBookSettings) {
      _savePerBookSizes();
      return;
    }

    // אחרת - שמירה גלובלית כמו קודם.
    if (_leftWidth != null) {
      Settings.setValue<double>('page_shape_left_width', _leftWidth!);
    }
    if (_rightWidth != null) {
      Settings.setValue<double>('page_shape_right_width', _rightWidth!);
    }
    if (_bottomHeight != null) {
      Settings.setValue<double>('page_shape_bottom_height', _bottomHeight!);
    }
    if (_bottomLeftWidth != null) {
      Settings.setValue<double>(
          'page_shape_bottom_left_width', _bottomLeftWidth!);
    }
  }

  /// שמירת רוחבי הטורים לספר הנוכחי, תוך שימור שאר ההגדרות הפר-ספריות.
  /// השמירה אטומית (דרך [TextBookPerBookSettings.mutate]) כדי שלא תדרוס
  /// שמירה מקבילה של גופן/ניקוד וכו' על אותו ספר.
  Future<void> _savePerBookSizes() async {
    final bookTitle = widget.tab?.book.title;
    if (bookTitle == null) return;

    final leftWidth = _leftWidth;
    final rightWidth = _rightWidth;
    final bottomHeight = _bottomHeight;
    final bottomLeftWidth = _bottomLeftWidth;

    await TextBookPerBookSettings.mutate(
      bookTitle,
      (existing) => (existing ?? TextBookPerBookSettings()).copyWith(
        pageShapeLeftWidth: leftWidth,
        pageShapeRightWidth: rightWidth,
        pageShapeBottomHeight: bottomHeight,
        pageShapeBottomLeftWidth: bottomLeftWidth,
      ),
    );
  }

  void _refreshLinksForCurrentConfiguration(String reason) {
    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded) {
      return;
    }

    context.read<TextBookBloc>().add(
          RefreshLinksForCurrentWindow(reason: reason),
        );
  }

  Future<void> _loadConfiguration() async {
    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded) {
      return;
    }

    final config = PageShapeSettingsManager.loadConfiguration(
      state.book.title,
      heCategories: state.book.heCategories,
    );

    _columnVisibility =
        PageShapeSettingsManager.getColumnVisibility(state.book.title);

    final Map<String, String?> commentators;
    if (config != null) {
      // יש הגדרה שמורה - צריך להתאים שמות בסיסיים לשמות מלאים
      // (כי הגדרות קטגוריה שומרות רק שמות בסיסיים כמו "רמב"ן")
      commentators =
          _resolveCommentatorNames(config, state.availableCommentators);
    } else {
      // אין הגדרה שמורה בכלל - השתמש בברירות מחדל
      commentators = await DefaultCommentators.getDefaults(
        state.book,
        availableCommentators: state.availableCommentators,
      );
    }

    if (mounted) {
      setState(() {
        _leftCommentator = commentators['left'];
        _rightCommentator = commentators['right'];
        _bottomCommentator = commentators['bottom'];
        _bottomRightCommentator = commentators['bottomRight'];
        _isLoadingConfig = false;
      });
      _refreshLinksForCurrentConfiguration('page-shape configuration loaded');
    }
  }

  /// התאמת שמות מפרשים בסיסיים לשמות מלאים מתוך הקישורים הזמינים
  /// למשל: "רמב"ן" → "רמב"ן על בבא מציעא"
  Map<String, String?> _resolveCommentatorNames(
      Map<String, String?> config, List<String> availableCommentators) {
    return Map.fromEntries(config.entries.map((entry) {
      final resolved = resolvePageShapeCommentatorSelection(
        selection: entry.value,
        availableCommentators: availableCommentators,
      );
      return MapEntry(entry.key, resolved);
    }));
  }

  List<String> _availableCommentators(TextBookLoaded state) {
    return state.availableCommentators;
  }

  List<String> _selectedRightPaneCommentators(TextBookLoaded state) {
    return resolvePageShapeSelectedCommentators(
      selection: _rightCommentator,
      availableCommentators: _rightPaneSelectableCommentators(state),
      excludedCommentators: [
        _leftCommentator,
        _bottomCommentator,
        _bottomRightCommentator,
      ],
    );
  }

  bool _isRightPaneMultipleMode() {
    return isPageShapeMultipleCommentatorsMode(_rightCommentator);
  }

  List<String> _rightPaneSelectableCommentators(TextBookLoaded state) {
    final excludedCommentators = {
      if (_leftCommentator != null) _leftCommentator!,
      if (_bottomCommentator != null) _bottomCommentator!,
      if (_bottomRightCommentator != null) _bottomRightCommentator!,
    };

    return _availableCommentators(state)
        .where((commentator) => !excludedCommentators.contains(commentator))
        .toList();
  }

  List<CommentatorGroup> _rightPaneCommentatorGroups(TextBookLoaded state) {
    final selectableCommentators =
        _rightPaneSelectableCommentators(state).toSet();

    return state.commentatorGroups
        .map(
          (group) => CommentatorGroup(
            title: group.title,
            commentators: group.commentators
                .where(selectableCommentators.contains)
                .toList(),
          ),
        )
        .where((group) => group.commentators.isNotEmpty)
        .toList();
  }

  Future<void> _saveRightPaneCommentators(
    TextBookLoaded state,
    List<String> commentators,
  ) async {
    final updatedConfig = {
      'left': _leftCommentator,
      'right': encodePageShapeCommentatorsSelection(
        commentators,
        forceMultipleMode: true,
      ),
      'bottom': _bottomCommentator,
      'bottomRight': _bottomRightCommentator,
    };

    final hasActualBookConfig =
        PageShapeSettingsManager.loadConfiguration(state.book.title) != null;

    final categoryToSave = !hasActualBookConfig &&
            state.book.heCategories != null &&
            state.book.heCategories!.isNotEmpty
        ? PageShapeSettingsManager.getActiveCategory(state.book.heCategories) ??
            PageShapeSettingsManager.getParentCategory(state.book.heCategories)
        : null;

    await PageShapeSettingsManager.saveConfiguration(
      state.book.title,
      updatedConfig,
      saveToCategory: categoryToSave,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _rightCommentator = encodePageShapeCommentatorsSelection(
        commentators,
        forceMultipleMode: true,
      );
    });
    _refreshLinksForCurrentConfiguration('right pane selection changed');
  }

  String? _rightPaneLabel(TextBookLoaded state) {
    final commentators = _selectedRightPaneCommentators(state);
    if (commentators.isEmpty) {
      return null;
    }

    return formatPageShapeCommentatorSelection(
      encodePageShapeCommentatorsSelection(commentators),
    );
  }

  Widget _buildRightPane(TextBookLoaded state) {
    if (!_isRightPaneMultipleMode()) {
      final selectableCommentators = _rightPaneSelectableCommentators(state);
      final resolvedSingle = resolvePageShapeCommentatorSelection(
        selection: _rightCommentator,
        availableCommentators: selectableCommentators,
      );
      if (resolvedSingle == null) {
        return _buildEmptyColumnContent(
          columnName: 'right',
          onSelectCommentator: () {
            setState(() {
              _columnVisibility['right'] = true;
            });
            final blocState = context.read<TextBookBloc>().state;
            if (blocState is TextBookLoaded) {
              PageShapeSettingsManager.saveColumnVisibility(
                blocState.book.title,
                _columnVisibility,
                saveAsGlobal: false,
              );
            }
            _openCommentatorSelector('right');
          },
          onHideColumn: () => _hideColumn('right'),
        );
      }
      if (!isPageShapeRemainingCommentatorsValue(resolvedSingle) &&
          !isPageShapeMultiCommentatorsValue(resolvedSingle) &&
          resolvedSingle != pageShapeMultipleCommentatorsModeValue) {
        return _CommentaryPane(
          commentatorName: resolvedSingle,
          openBookCallback: widget.openBookCallback,
          selectionSyncController: _selectionSyncController,
          onLoadFailed: () => _hideColumn(
            'right',
            global: false,
            showSnack: false,
            persist: false,
          ),
        );
      }
    }

    final commentators = _selectedRightPaneCommentators(state);

    return CommentaryListBase(
      // מפתח יציב כדי שלא נאבד את מצב מסך בחירת המפרשים בכל סימון
      key: const ValueKey('page_shape_commentary_list'),
      openBookCallback: (tab) => widget.openBookCallback(tab),
      fontSize: PageShapeSettingsManager.getCommentaryFontSize(),
      showSearch: true,
      selectionSyncController: _selectionSyncController,
      shrinkWrap: false,
      selectedCommentatorsOverride: commentators,
      commentatorGroupsOverride: _rightPaneCommentatorGroups(state),
      bookTitleOverride: state.book.title,
      onSelectedCommentatorsOverrideChanged: (selected) =>
          _saveRightPaneCommentators(state, selected),
      onOpenInNewTab: widget.tab == null
          ? null
          : () => context.read<TabsBloc>().add(
                AddTab(
                  CommentatorsTab(sourceTab: widget.tab!),
                  insertAdjacent: true,
                ),
              ),
    );
  }

  /// הסתרת טור - ניתן לבחור אם לשמור גלובלית או רק לספר הנוכחי
  void _hideColumn(
    String column, {
    bool global = true,
    bool showSnack = true,
    bool persist = true,
  }) {
    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded) return;

    setState(() {
      _columnVisibility[column] = false;
    });

    if (persist) {
      PageShapeSettingsManager.saveColumnVisibility(
          state.book.title, _columnVisibility,
          saveAsGlobal: global);
    }

    if (showSnack && global && persist) {
      UiSnack.show('הטור הוסתר בכל הספרים. ניתן לשנות בהגדרות צורת הדף.');
    }

    _refreshLinksForCurrentConfiguration(
        'page-shape column visibility changed');
  }

  /// בניית widget למצב ריק של טור
  Widget _buildEmptyColumnContent({
    required String columnName,
    required VoidCallback onSelectCommentator,
    required VoidCallback onHideColumn,
  }) {
    return Container(
      color: Theme.of(context)
          .colorScheme
          .surfaceContainerHighest
          .withValues(alpha: 0.5),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            RecommendedActionButton(
              onPressed: onSelectCommentator,
              icon: FluentIcons.book_24_regular,
              text: 'בחר מפרש',
            ),
            const SizedBox(height: 12),
            NeutralActionButton(
              onPressed: onHideColumn,
              icon: FluentIcons.eye_off_24_regular,
              text: 'הסתר טור זה',
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _navigateToLine(TextBookLoaded state, int lineNumber) async {
    if (lineNumber < 1 || state.content.isEmpty) {
      return;
    }

    final targetIndex =
        (lineNumber - 1).clamp(0, state.content.length - 1).toInt();

    await scrollToSourceLine(
      scrollController: state.scrollController,
      scrollOffsetController: widget.scrollOffsetController,
      positionsListener: state.positionsListener,
      segments: state.readingSegments,
      lineIndex: targetIndex,
      viewportExtent: context.size?.height ?? MediaQuery.sizeOf(context).height,
      alignment: 0.05,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );

    if (!mounted || !context.mounted) {
      return;
    }

    final bloc = context.read<TextBookBloc>();
    bloc.add(UpdateSelectedIndex(targetIndex));
    bloc.add(HighlightLine(targetIndex));
  }

  void _openLeftSidebarTab(int index) {
    final validIndex = index.clamp(0, 1);
    if (_isLeftSidebarOpen && _leftSidebarTabIndex == validIndex) {
      return;
    }

    setState(() {
      _isLeftSidebarOpen = true;
      _leftSidebarTabIndex = validIndex;
    });
  }

  /// כתובת היעד לתווית הריחוף על סרגל הטקסט הראשי. ממיר אינדקס סגמנט
  /// (במצב קריאה רציף) לשורת המקור כדי שמיפוי ה-TOC יהיה נכון.
  String _mainTextLabelForIndex(int index, TextBookLoaded state) {
    final segments = state.readingSegments;
    final lineIndex = segments.isNotEmpty
        ? (index >= 0 && index < segments.length
            ? segments[index].startLineIndex
            : index)
        : index;
    final ref = refFromTocList(lineIndex, state.tableOfContents);
    return addBookTitleToRef(ref, state.book.title);
  }

  void _toggleLeftSidebar() {
    setState(() {
      _isLeftSidebarOpen = !_isLeftSidebarOpen;
    });
  }

  void _handleSidebarTabRequest() {
    final requestedTab = widget.sidebarTabNotifier?.value;
    if (requestedTab == null) {
      return;
    }

    _openLeftSidebarTab(requestedTab);
    widget.sidebarTabNotifier?.value = null;
  }

  /// טוגל חלונית הצד (קישורים/הערות) מקיצור Ctrl+Shift+C:
  /// סגורה או פתוחה על "הערות" → פתח על "קישורים".
  /// פתוחה על "קישורים" → סגור.
  void _onToggleCommentatorsPaneRequest() {
    if (!mounted) return;
    setState(() {
      if (_isLeftSidebarOpen && _leftSidebarTabIndex == _kLinksTabIndex) {
        _isLeftSidebarOpen = false;
      } else {
        _isLeftSidebarOpen = true;
        _leftSidebarTabIndex = _kLinksTabIndex;
      }
    });
  }

  /// בקשה מכפתור גלגל השיניים בסרגל העליון לפתוח את דיאלוג ההגדרות
  void _handleOpenSettingsRequest() {
    if (!mounted) return;
    _openCommentatorSelector('settings');
  }

  @override
  void initState() {
    super.initState();
    widget.sidebarTabNotifier?.addListener(_handleSidebarTabRequest);
    widget.openSettingsNotifier?.addListener(_handleOpenSettingsRequest);
    widget.tab?.toggleCommentatorsPaneNotifier
        .addListener(_onToggleCommentatorsPaneRequest);
  }

  @override
  void didUpdateWidget(covariant PageShapeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sidebarTabNotifier != widget.sidebarTabNotifier) {
      oldWidget.sidebarTabNotifier?.removeListener(_handleSidebarTabRequest);
      widget.sidebarTabNotifier?.addListener(_handleSidebarTabRequest);
    }
    if (oldWidget.openSettingsNotifier != widget.openSettingsNotifier) {
      oldWidget.openSettingsNotifier
          ?.removeListener(_handleOpenSettingsRequest);
      widget.openSettingsNotifier?.addListener(_handleOpenSettingsRequest);
    }
    if (oldWidget.tab != widget.tab) {
      oldWidget.tab?.toggleCommentatorsPaneNotifier
          .removeListener(_onToggleCommentatorsPaneRequest);
      widget.tab?.toggleCommentatorsPaneNotifier
          .addListener(_onToggleCommentatorsPaneRequest);
    }
  }

  @override
  void dispose() {
    widget.sidebarTabNotifier?.removeListener(_handleSidebarTabRequest);
    widget.openSettingsNotifier?.removeListener(_handleOpenSettingsRequest);
    widget.tab?.toggleCommentatorsPaneNotifier
        .removeListener(_onToggleCommentatorsPaneRequest);
    _selectionSyncController.dispose();
    super.dispose();
  }

  /// פתיחת דיאלוג בחירת מפרש לטור ספציפי
  Future<void> _openCommentatorSelector(String column) async {
    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded) {
      return;
    }

    // קבלת רשימת המפרשים הזמינים
    final availableCommentators = state.availableCommentators;

    if (availableCommentators.isEmpty) {
      return;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => PageShapeSettingsDialog(
        availableCommentators: availableCommentators,
        bookTitle: state.book.title,
        heCategories: state.book.heCategories,
        currentLeft: _leftCommentator,
        currentRight: _rightCommentator,
        currentBottom: _bottomCommentator,
        currentBottomRight: _bottomRightCommentator,
        // עדכון חי: כל שינוי בדיאלוג נטען מיד למסך שמאחוריו
        onSettingsChanged: () => _loadConfiguration(),
      ),
    );

    // טעינה מחדש גם בסגירה - נדרש לאיפוס מפרשים (שמדלג על העדכון החי)
    if (result == true) {
      _loadConfiguration();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<TextBookBloc, TextBookState>(
          listenWhen: (previous, current) {
            if (previous is TextBookLoaded && current is TextBookLoaded) {
              return previous.availableCommentators.length !=
                  current.availableCommentators.length;
            }
            return previous is! TextBookLoaded && current is TextBookLoaded;
          },
          listener: (context, state) {
            if (state is TextBookLoaded &&
                state.availableCommentators.isNotEmpty) {
              _loadConfiguration();
            }
          },
        ),
        BlocListener<PersonalNotesBloc, PersonalNotesState>(
          // מאזינים גם לשינוי newNoteBookId, כדי לתפוס מעבר ישיר מטיוטה
          // של ספר אחד לטיוטה של ספר אחר (isCreatingNewNote נשאר true).
          // וגם לשינוי newNoteLineNumber, כדי לתפוס מעבר ישיר מטיוטה של
          // שורה לטיוטה של שורה אחרת באותו ספר — אחרת הקלקה על "הוסף
          // הערה" בתפריט הימני בזמן שיש כבר טיוטה פתוחה לא היתה פותחת
          // את הסיידבר אם הוא היה סגור.
          listenWhen: (previous, current) =>
              previous.isCreatingNewNote != current.isCreatingNewNote ||
              previous.newNoteBookId != current.newNoteBookId ||
              previous.newNoteLineNumber != current.newNoteLineNumber,
          listener: (context, state) {
            // פותחים את חלונית ההערות רק אם הטיוטה שייכת לספר של מסך זה.
            // אחרת — בטאבים אחרים (keepAlive) היה נפתח sidebar של ספר זר.
            if (!state.isCreatingNewNote) return;
            final textBookState = context.read<TextBookBloc>().state;
            if (textBookState is! TextBookLoaded) return;
            if (state.newNoteBookId != textBookState.book.title) return;
            _openLeftSidebarTab(1);
          },
        ),
      ],
      child: _isLoadingConfig
          ? const Scaffold(
              body: LoadingIndicator(),
            )
          : TextBookStateBuilder(
              loadingWidget: const Scaffold(
                body: LoadingIndicator(),
              ),
              builder: (context, state) {
                // נראות כל פאנל תחתון נשלטת בנפרד; האזור התחתון מוצג רק אם
                // לפחות אחד מהם גלוי ובעל מפרש.
                final showBottom = _columnVisibility['bottom'] == true &&
                    _bottomCommentator != null;
                final showBottomRight =
                    _columnVisibility['bottomRight'] == true &&
                        _bottomRightCommentator != null;
                return Scaffold(
                  body: AdaptiveSidePane(
                    isOpen: _isLeftSidebarOpen,
                    alignment: AlignmentDirectional.centerStart,
                    paneWidth: _leftSidebarWidth ??
                        MediaQuery.of(context).size.width * 0.22,
                    minPaneWidth: 220,
                    maxPaneWidth: MediaQuery.of(context).size.width * 0.35,
                    minMainContentWidth: 300,
                    isResizable: true,
                    scrollbarTopMargin: 0,
                    autoHandleResponsiveVisibility: false,
                    onClose: _toggleLeftSidebar,
                    onPaneWidthChanged: (width) {
                      _leftSidebarWidth = width;
                    },
                    onPaneResizeEnd: _saveSizes,
                    paneContent: LinksNotesSidebar(
                      bookId: state.book.title,
                      categoryId: state.book.categoryId,
                      openBookCallback: widget.openBookCallback,
                      fontSize: state.fontSize,
                      selectionSyncController: _selectionSyncController,
                      onNavigateToLine: (lineNumber) =>
                          _navigateToLine(state, lineNumber),
                      onClosePane: _toggleLeftSidebar,
                      initialTabIndex: _leftSidebarTabIndex,
                      onTabChanged: (index) {
                        setState(() {
                          _leftSidebarTabIndex = index;
                        });
                      },
                    ),
                    mainContent: Stack(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                children: [
                                  Expanded(
                                    child: Row(
                                      children: [
                                        if (_columnVisibility['left'] ==
                                            true) ...[
                                          if (_leftCommentator != null) ...[
                                            SizedBox(
                                              width: 20,
                                              child: Center(
                                                child: RotatedBox(
                                                  quarterTurns: 1,
                                                  child: Text(
                                                    _leftCommentator!,
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            SizedBox(
                                              width: _leftWidth ??
                                                  MediaQuery.of(context)
                                                          .size
                                                          .width *
                                                      _kCommentaryPaneWidthFactor,
                                              child: _CommentaryPane(
                                                commentatorName:
                                                    _leftCommentator!,
                                                openBookCallback:
                                                    widget.openBookCallback,
                                                selectionSyncController:
                                                    _selectionSyncController,
                                                onLoadFailed: () => _hideColumn(
                                                  'left',
                                                  global: false,
                                                  showSnack: false,
                                                  persist: false,
                                                ),
                                              ),
                                            ),
                                          ] else ...[
                                            SizedBox(
                                              width: _leftWidth ??
                                                  MediaQuery.of(context)
                                                          .size
                                                          .width *
                                                      _kCommentaryPaneWidthFactor,
                                              child: _buildEmptyColumnContent(
                                                columnName: 'left',
                                                onSelectCommentator: () {
                                                  setState(() {
                                                    _columnVisibility['left'] =
                                                        true;
                                                  });
                                                  final state = context
                                                      .read<TextBookBloc>()
                                                      .state;
                                                  if (state is TextBookLoaded) {
                                                    PageShapeSettingsManager
                                                        .saveColumnVisibility(
                                                      state.book.title,
                                                      _columnVisibility,
                                                      saveAsGlobal: false,
                                                    );
                                                  }
                                                  _openCommentatorSelector(
                                                      'left');
                                                },
                                                onHideColumn: () =>
                                                    _hideColumn('left'),
                                              ),
                                            ),
                                          ],
                                          SizedBox(
                                            width: 8,
                                            child: Stack(
                                              children: [
                                                Positioned(
                                                  top: 0,
                                                  bottom: 0,
                                                  child: ResizableDragHandle(
                                                    isVertical: true,
                                                    showDivider: false,
                                                    onDragDelta: (delta) {
                                                      setState(() {
                                                        _leftWidth = ((_leftWidth ??
                                                                    MediaQuery.of(context)
                                                                            .size
                                                                            .width *
                                                                        _kCommentaryPaneWidthFactor) -
                                                                delta)
                                                            .clamp(
                                                          80.0,
                                                          MediaQuery.of(context)
                                                                  .size
                                                                  .width *
                                                              0.4,
                                                        );
                                                      });
                                                    },
                                                    onDragEnd: _saveSizes,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                        Expanded(
                                          child: SimpleTextViewer(
                                            content: state.content,
                                            fontSize: state.fontSize,
                                            selectionSyncController:
                                                _selectionSyncController,
                                            openBookCallback:
                                                widget.openBookCallback,
                                            scrollController:
                                                state.scrollController,
                                            positionsListener:
                                                state.positionsListener,
                                            isMainText: true,
                                            tab: widget.tab,
                                            labelForIndex:
                                                state.tableOfContents.isEmpty
                                                    ? null
                                                    : (index) =>
                                                        _mainTextLabelForIndex(
                                                            index, state),
                                            onOpenSidebarTab:
                                                _openLeftSidebarTab,
                                            onOpenSearch: widget.onOpenSearch,
                                          ),
                                        ),
                                        if (_columnVisibility['right'] ==
                                            true) ...[
                                          SizedBox(
                                            width: 8,
                                            child: Stack(
                                              children: [
                                                Positioned(
                                                  top: 0,
                                                  bottom: 0,
                                                  child: ResizableDragHandle(
                                                    isVertical: true,
                                                    showDivider: false,
                                                    onDragDelta: (delta) {
                                                      setState(() {
                                                        _rightWidth = ((_rightWidth ??
                                                                    MediaQuery.of(context)
                                                                            .size
                                                                            .width *
                                                                        _kCommentaryPaneWidthFactor) +
                                                                delta)
                                                            .clamp(
                                                          80.0,
                                                          MediaQuery.of(context)
                                                                  .size
                                                                  .width *
                                                              0.4,
                                                        );
                                                      });
                                                    },
                                                    onDragEnd: _saveSizes,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (_rightPaneSelectableCommentators(
                                                  state)
                                              .isNotEmpty) ...[
                                            SizedBox(
                                              width: _rightWidth ??
                                                  MediaQuery.of(context)
                                                          .size
                                                          .width *
                                                      _kCommentaryPaneWidthFactor,
                                              child: _buildRightPane(state),
                                            ),
                                            if (_rightPaneLabel(state) !=
                                                null) ...[
                                              const SizedBox(width: 4),
                                              SizedBox(
                                                width: 20,
                                                child: Center(
                                                  child: RotatedBox(
                                                    quarterTurns: 3,
                                                    child: Text(
                                                      _rightPaneLabel(state)!,
                                                      style: const TextStyle(
                                                        fontSize: 14,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ] else ...[
                                            SizedBox(
                                              width: _rightWidth ??
                                                  MediaQuery.of(context)
                                                          .size
                                                          .width *
                                                      _kCommentaryPaneWidthFactor,
                                              child: _buildEmptyColumnContent(
                                                columnName: 'right',
                                                onSelectCommentator: () {
                                                  setState(() {
                                                    _columnVisibility['right'] =
                                                        true;
                                                  });
                                                  final state = context
                                                      .read<TextBookBloc>()
                                                      .state;
                                                  if (state is TextBookLoaded) {
                                                    PageShapeSettingsManager
                                                        .saveColumnVisibility(
                                                      state.book.title,
                                                      _columnVisibility,
                                                      saveAsGlobal: false,
                                                    );
                                                  }
                                                  _openCommentatorSelector(
                                                      'right');
                                                },
                                                onHideColumn: () =>
                                                    _hideColumn('right'),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ],
                                    ),
                                  ),
                                  if (showBottom || showBottomRight) ...[
                                    _HorizontalDragHandle(
                                      leftWidth: _leftWidth,
                                      rightWidth: _rightWidth,
                                      leftCommentator: _leftCommentator,
                                      rightCommentator: _rightPaneLabel(state),
                                      onPanUpdate: (details) {
                                        setState(() {
                                          _bottomHeight =
                                              ((_bottomHeight ?? 0) -
                                                      details.delta.dy)
                                                  .clamp(
                                            80.0,
                                            MediaQuery.of(context).size.height *
                                                0.5,
                                          );
                                        });
                                      },
                                      onPanEnd: _saveSizes,
                                    ),
                                    SizedBox(
                                      height: _bottomHeight ??
                                          MediaQuery.of(context).size.height *
                                              0.27,
                                      child: Column(
                                        children: [
                                          Expanded(
                                            child: showBottomRight
                                                ? Row(
                                                    children: [
                                                      if (showBottom) ...[
                                                        SizedBox(
                                                          width: 20,
                                                          child: Center(
                                                            child: RotatedBox(
                                                              quarterTurns: 1,
                                                              child: Text(
                                                                _bottomCommentator!,
                                                                style:
                                                                    const TextStyle(
                                                                  fontSize: 14,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                            width: 4),
                                                        SizedBox(
                                                          width: _bottomLeftWidth ??
                                                              MediaQuery.of(
                                                                          context)
                                                                      .size
                                                                      .width *
                                                                  0.5,
                                                          child:
                                                              _CommentaryPane(
                                                            commentatorName:
                                                                _bottomCommentator!,
                                                            openBookCallback: widget
                                                                .openBookCallback,
                                                            isBottom: true,
                                                            selectionSyncController:
                                                                _selectionSyncController,
                                                            onLoadFailed: () =>
                                                                _hideColumn(
                                                              'bottom',
                                                              global: false,
                                                              showSnack: false,
                                                              persist: false,
                                                            ),
                                                          ),
                                                        ),
                                                        SizedBox(
                                                          width: 8,
                                                          child: Stack(
                                                            children: [
                                                              Positioned(
                                                                top: 0,
                                                                bottom: 0,
                                                                child:
                                                                    ResizableDragHandle(
                                                                  isVertical:
                                                                      true,
                                                                  showDivider:
                                                                      false,
                                                                  onDragDelta:
                                                                      (delta) {
                                                                    setState(
                                                                        () {
                                                                      _bottomLeftWidth =
                                                                          ((_bottomLeftWidth ?? MediaQuery.of(context).size.width * 0.5) - delta)
                                                                              .clamp(
                                                                        100.0,
                                                                        MediaQuery.of(context).size.width *
                                                                            0.8,
                                                                      );
                                                                    });
                                                                  },
                                                                  onDragEnd:
                                                                      _saveSizes,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ],
                                                      Expanded(
                                                        child: _CommentaryPane(
                                                          commentatorName:
                                                              _bottomRightCommentator!,
                                                          openBookCallback: widget
                                                              .openBookCallback,
                                                          isBottom: true,
                                                          selectionSyncController:
                                                              _selectionSyncController,
                                                          onLoadFailed: () =>
                                                              _hideColumn(
                                                            'bottomRight',
                                                            global: false,
                                                            showSnack: false,
                                                            persist: false,
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 4),
                                                      SizedBox(
                                                        width: 20,
                                                        child: Center(
                                                          child: RotatedBox(
                                                            quarterTurns: 3,
                                                            child: Text(
                                                              _bottomRightCommentator!,
                                                              style:
                                                                  const TextStyle(
                                                                fontSize: 14,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  )
                                                : Row(
                                                    children: [
                                                      SizedBox(
                                                        width: 20,
                                                        child: Center(
                                                          child: RotatedBox(
                                                            quarterTurns: 1,
                                                            child: Text(
                                                              _bottomCommentator!,
                                                              style:
                                                                  const TextStyle(
                                                                fontSize: 14,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Expanded(
                                                        child: _CommentaryPane(
                                                          commentatorName:
                                                              _bottomCommentator!,
                                                          openBookCallback: widget
                                                              .openBookCallback,
                                                          isBottom: true,
                                                          selectionSyncController:
                                                              _selectionSyncController,
                                                          onLoadFailed: () =>
                                                              _hideColumn(
                                                            'bottom',
                                                            global: false,
                                                            showSnack: false,
                                                            persist: false,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                        // כפתור צף לפתיחת הסיידבר
                        if (!_isLeftSidebarOpen)
                          Positioned(
                            left: 0,
                            top: MediaQuery.of(context).size.height * 0.10,
                            child: PanelOpenHandle(
                              onTap: () => _openLeftSidebarTab(0),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

/// חלונית מפרש - טוענת ומציגה את הספר של המפרש
class _CommentaryPane extends StatefulWidget {
  final String commentatorName;
  final Function(OpenedTab) openBookCallback;
  final bool isBottom; // האם זה מפרש תחתון (גופן ייעודי מדיאלוג ההגדרות)
  final VoidCallback? onLoadFailed;
  final SelectionSyncController? selectionSyncController;

  const _CommentaryPane({
    required this.commentatorName,
    required this.openBookCallback,
    this.isBottom = false,
    this.onLoadFailed,
    this.selectionSyncController,
  });

  @override
  State<_CommentaryPane> createState() => _CommentaryPaneState();
}

class _LoadedCommentaryData {
  final TextBook book;
  final List<String> content;

  const _LoadedCommentaryData({
    required this.book,
    required this.content,
  });
}

class _CommentaryPaneState extends State<_CommentaryPane> {
  static const int _quickPreviewPaddingLines = 10;
  static final Map<String, Future<_LoadedCommentaryData?>>
      _fullCommentaryCache = {};

  List<String>? _content;
  TextBook? _reportBook;
  // תוכן העניינים של ספר המפרש — לתווית היעד בריחוף על סרגל הגלילה. null
  // עד שנטען; אינדקסי התוכן של המפרש מתיישרים עם מספרי השורות שלו, ולכן
  // המיפוי ישיר (refFromTocList) בלי המרת סגמנטים.
  List<TocEntry>? _commentaryToc;
  bool _isLoading = true;
  final ItemScrollController _scrollController = ItemScrollController();
  final ItemPositionsListener _positionsListener =
      ItemPositionsListener.create();
  List<Link> _relevantLinks = [];
  int? _lastSyncedIndex; // האינדקס האחרון שסונכרן
  int _initialSyncAttempts = 0; // ניסיונות סנכרון ראשוני עד שה-controller מחובר
  List<Link>? _lastLinks; // לדידוב: מסנן מחדש רק כשהקישורים השתנו
  StreamSubscription<TextBookState>? _blocSubscription;
  Set<int> _highlightedIndices = {}; // אינדקסים להדגשה
  bool _highlightEnabled = false;

  @override
  void initState() {
    super.initState();
    // דוחה את הטעינה כדי לוודא שכל ה-providers מוכנים וה-bloc זמין
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadCommentary();
        _setupBlocListener();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // הסרנו את הקריאה מכאן כדי למנוע כפילות או בעיות context מוקדמות
  }

  @override
  void didUpdateWidget(_CommentaryPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    // אם שם המפרש השתנה, טען מחדש את התוכן
    if (oldWidget.commentatorName != widget.commentatorName) {
      _loadCommentary();
    } else {
      // אם המפרש לא השתנה, רק עדכן הדגשות
      _updateHighlightSettings();
    }
  }

  @override
  void dispose() {
    _blocSubscription?.cancel();
    super.dispose();
  }

  /// עדכון הגדרות הדגשה
  void _updateHighlightSettings() {
    final state = context.read<TextBookBloc>().state;
    if (state is TextBookLoaded) {
      final newHighlightEnabled =
          PageShapeSettingsManager.getHighlightSetting(state.book.title);
      final highlightChanged = newHighlightEnabled != _highlightEnabled;
      _highlightEnabled = newHighlightEnabled;
      // עדכון הדגשות - גם בטעינה ראשונית וגם כשההגדרה משתנה
      if (highlightChanged || _highlightedIndices.isEmpty) {
        _updateHighlights(state);
      }
    }
  }

  /// הגדרת מאזין לשינויים ב-Bloc
  void _setupBlocListener() {
    // טעינת הגדרת הדגשה ראשונית
    _updateHighlightSettings();

    _blocSubscription = context.read<TextBookBloc>().stream.listen((state) {
      if (state is TextBookLoaded && mounted) {
        // מסנן מחדש רק כשהקישורים עצמם השתנו (UpdateLinks),
        // ולא בכל גלילה (UpdateVisibleIndecies / UpdateSelectedIndex)
        if (!identical(_lastLinks, state.links)) {
          _lastLinks = state.links;
          _refreshRelevantLinks(state);
        }
        _syncWithMainText(state);
        _updateHighlights(state);
      }
    });
  }

  void _refreshRelevantLinks(TextBookLoaded state) {
    _relevantLinks = state.links.where((link) {
      final linkTitle = utils.getTitleFromPath(link.path2);
      return linkTitle == widget.commentatorName &&
          LinkTypes.isCommentaryOrTargum(link.connectionType);
    }).toList();
  }

  String _commentaryCacheKey(TextBook book, {required bool preferDatabase}) {
    return '${book.title}|${book.categoryId}|${book.categoryPath ?? ''}|$preferDatabase';
  }

  List<String> _buildPreviewLines(String previewContent, int previewStartLine) {
    final previewLines = previewContent.split('\n');
    if (previewStartLine <= 0) {
      return previewLines;
    }

    return List<String>.filled(previewStartLine, '', growable: true)
      ..addAll(previewLines);
  }

  /// נקודת הייחוס לסנכרון — כשליש מגובה ה-viewport מלמעלה (לא במרכז ולא
  /// בראש). אותו ערך משמש גם לבחירת שורת המקור וגם ליישור המפרש, כדי
  /// ששניהם יהיו באותו מיקום אנכי.
  static const double _syncAlignment = 1 / 3;

  /// מחזיר את אינדקס השורה שבכשליש העליון של ה-viewport מתוך השורות
  /// הגלויות. הסנכרון מכוון לנקודה זו ולא לשורה העליונה, כדי שהמפרש
  /// יעקוב אחר מה שהמשתמש קורא בפועל. מניחים שהרשימה אינה ריקה.
  int _referenceVisibleIndex(List<int> visibleIndices) {
    final sorted = [...visibleIndices]..sort();
    return sorted[(sorted.length * _syncAlignment).floor()];
  }

  int _resolveCurrentMainIndex(TextBookLoaded state) {
    if (state.selectedIndex != null) {
      return state.selectedIndex!;
    }

    if (state.visibleIndices.isNotEmpty) {
      return _referenceVisibleIndex(state.visibleIndices);
    }

    return 0;
  }

  int? _resolveInitialCommentaryTargetIndex(TextBookLoaded state) {
    if (_relevantLinks.isEmpty) {
      return null;
    }

    final logicalIndex = CommentarySyncHelper.getLogicalIndex(
      _resolveCurrentMainIndex(state),
      state.content,
    );

    // חייב להשתמש באותו חישוב כמו _syncWithMainText, אחרת ה-preview ייטען
    // בחלון קטן סביב יעד אחר, והסנכרון השוטף לא יוכל לגלול ליעד כי הוא
    // מחוץ לחלון שנטען.
    return CommentarySyncHelper.getCommentaryTargetIndex(
      linksForCommentary: _relevantLinks,
      logicalMainIndex: logicalIndex,
    );
  }

  Future<_LoadedCommentaryData?> _fetchFullCommentaryData(
    TextBook book, {
    required bool preferDatabase,
  }) async {
    final String bookContent;
    if (preferDatabase && book.categoryId != null) {
      final dbProvider = LibraryProviderManager.instance.databaseProvider;
      final text = await dbProvider.getBookText(
        book.title,
        book.categoryId!,
        'txt',
      );
      bookContent = text ?? '';
    } else {
      bookContent = await book.text;
    }

    if (bookContent.isEmpty) {
      return null;
    }

    final lines = await Isolate.run(() => bookContent.split('\n'));
    return _LoadedCommentaryData(
      book: book,
      content: lines,
    );
  }

  Future<void> _applyFullCommentaryData(
    Future<_LoadedCommentaryData?> dataFuture,
    String requestedCommentatorName,
  ) async {
    final data = await dataFuture;
    if (!mounted || widget.commentatorName != requestedCommentatorName) {
      return;
    }

    if (data == null) {
      if (_content == null || _content!.isEmpty) {
        _notifyCommentaryLoadFailed();
        setState(() {
          _reportBook = null;
          _content = null;
          _isLoading = false;
        });
      }
      return;
    }

    setState(() {
      _reportBook = data.book;
      _content = data.content;
      _isLoading = false;
      _lastSyncedIndex = null;
    });

    _scheduleInitialSync();
  }

  void _notifyCommentaryLoadFailed() {
    if (widget.onLoadFailed != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onLoadFailed!();
        }
      });
    }
  }

  void _updateHighlights(TextBookLoaded state) {
    if (!_highlightEnabled || state.selectedIndex == null) {
      if (_highlightedIndices.isNotEmpty) {
        setState(() {
          _highlightedIndices = {};
        });
      }
      return;
    }

    // חישוב האינדקס הלוגי
    final logicalIndex = CommentarySyncHelper.getLogicalIndex(
      state.selectedIndex!,
      state.content,
    );
    final mainLineNumber = logicalIndex + 1;

    // מציאת כל הקישורים לשורה זו והמרה ישירה ל-Set
    final newHighlights = _relevantLinks
        .where((link) => link.index1 == mainLineNumber)
        .map((link) => link.index2 - 1)
        .toSet();

    if (!const SetEquality().equals(newHighlights, _highlightedIndices)) {
      setState(() {
        _highlightedIndices = newHighlights;
      });
    }
  }

  /// טוען את תוכן העניינים של ספר המפרש (אם קיים) ושומר אותו לתווית היעד.
  /// כישלון אינו קריטי — פשוט לא תוצג תווית.
  Future<void> _loadCommentaryToc(TextBook book) async {
    final requested = widget.commentatorName;
    try {
      final toc = await LibraryProviderManager.instance.getBookToc(
        book.title,
        categoryId: book.categoryId,
        fileType: book.fileType,
      );
      if (!mounted || widget.commentatorName != requested) return;
      setState(() => _commentaryToc = toc ?? const <TocEntry>[]);
    } catch (_) {
      // ללא תווית — לא מפילים את טעינת המפרש בגלל זה.
    }
  }

  /// כתובת היעד לתווית הריחוף על סרגל המפרש. אינדקס התוכן של המפרש מתיישר
  /// עם מספרי השורות שלו, ולכן המיפוי ישיר.
  String _commentaryLabelForIndex(int index) {
    final toc = _commentaryToc;
    if (toc == null) return '';
    final ref = refFromTocList(index, toc);
    return addBookTitleToRef(ref, widget.commentatorName);
  }

  Future<void> _loadCommentary() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _commentaryToc = null;
    });
    _lastLinks = null;

    try {
      // המתנה לכך שה-state יהיה TextBookLoaded
      final bloc = context.read<TextBookBloc>();
      var state = bloc.state;

      // אם ה-state עדיין לא TextBookLoaded, נחכה לו
      if (state is! TextBookLoaded) {
        try {
          state = await bloc.stream
              .firstWhere(
                (s) => s is TextBookLoaded,
                orElse: () => state,
              )
              .timeout(const Duration(seconds: 5));
        } catch (e) {
          // Timeout בהמתנה ל־TextBookLoaded
        }
      }

      if (!mounted) return;

      if (state is TextBookLoaded) {
        // סינון קישורים לפי שם המפרש ולפי סוג הקישור (COMMENTARY/TARGUM)
        _refreshRelevantLinks(state);
      }

      // מציאת הספר המלא של המפרש עם categoryId
      TextBook book;
      final bookLocation = await BookLocator.locateBook(widget.commentatorName);

      if (bookLocation != null &&
          bookLocation.book != null &&
          bookLocation.categoryId != null) {
        // נמצא ספר ב-DB - נשתמש בנתונים שלו
        book = TextBook(
          title: widget.commentatorName,
          categoryId: bookLocation.categoryId,
        );
      } else {
        // ננסה למצוא את ה-categoryPath מהקישורים הקיימים
        String? categoryPath;
        if (_relevantLinks.isNotEmpty) {
          // נחלץ את ה-categoryPath מהקישור הראשון
          final firstLinkPath = _relevantLinks.first.path2;
          var normalizedPath = firstLinkPath;
          if (normalizedPath.startsWith('/') ||
              normalizedPath.startsWith('\\')) {
            normalizedPath = normalizedPath.substring(1);
          }

          final lastSeparatorIndex = normalizedPath.lastIndexOf('/');
          if (lastSeparatorIndex != -1) {
            final directoryPath =
                normalizedPath.substring(0, lastSeparatorIndex);
            categoryPath =
                directoryPath.replaceAll('/', ', ').replaceAll('\\', ', ');
          }
        }

        // יצירת ספר עם categoryPath (שיומר ל-categoryId באמצעות hashCode)
        if (categoryPath != null && categoryPath.isNotEmpty) {
          final categoryId = categoryPath.hashCode;
          book = TextBook(
            title: widget.commentatorName,
            categoryPath: categoryPath,
            categoryId: categoryId,
          );
        } else {
          // fallback - ספר ללא categoryId (לא יטען קישורים)
          book = TextBook(title: widget.commentatorName);
        }
      }

      // טעינת תוכן העניינים של המפרש ברקע — עבור תווית היעד בריחוף על הסרגל.
      unawaited(_loadCommentaryToc(book));

      // טעינת הטקסט ישירות מה-provider המתאים
      final useDatabaseSource = bookLocation != null &&
          bookLocation.book != null &&
          bookLocation.categoryId != null;
      final requestedCommentatorName = widget.commentatorName;
      final fullCommentaryFuture = _fullCommentaryCache.putIfAbsent(
        _commentaryCacheKey(book, preferDatabase: useDatabaseSource),
        () => _fetchFullCommentaryData(
          book,
          preferDatabase: useDatabaseSource,
        ),
      );

      var previewLoaded = false;
      final currentState = state;
      if (useDatabaseSource && currentState is TextBookLoaded) {
        final previewTargetIndex =
            _resolveInitialCommentaryTargetIndex(currentState) ?? 0;
        final previewContent =
            await SqliteDataProvider.instance.getBookQuickPreview(
          widget.commentatorName,
          previewTargetIndex,
          categoryId: book.categoryId,
          fileType: book.fileType,
        );

        if (!mounted || widget.commentatorName != requestedCommentatorName) {
          return;
        }

        if (previewContent != null && previewContent.isNotEmpty) {
          final previewStartLine =
              (previewTargetIndex - _quickPreviewPaddingLines).clamp(
            0,
            previewTargetIndex,
          );
          setState(() {
            _reportBook = book;
            _content = _buildPreviewLines(previewContent, previewStartLine);
            _isLoading = false;
            _lastSyncedIndex = null;
          });
          previewLoaded = true;

          _scheduleInitialSync();
        }
      }

      if (previewLoaded) {
        unawaited(
          _applyFullCommentaryData(
            fullCommentaryFuture,
            requestedCommentatorName,
          ),
        );
        return;
      }

      await _applyFullCommentaryData(
        fullCommentaryFuture,
        requestedCommentatorName,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '⚠️ CommentaryPane::loadCommentary failed '
          'for ${widget.commentatorName}: $e',
        );
      }
      _notifyCommentaryLoadFailed();
      if (mounted) {
        setState(() {
          _reportBook = null;
          _content = null;
          _isLoading = false;
        });
      }
    }
  }

  /// מתזמן סנכרון ראשוני של המפרש עם הטקסט הראשי.
  ///
  /// רשימת המפרש נבנית תמיד מאינדקס 0, ולכן הסנכרון הראשוני חייב להצליח
  /// כדי להקפיץ אותה למיקום הנכון. אם ה-ScrollController עדיין לא מחובר
  /// בפריים הראשון (מירוץ שכיח בפתיחת ספר באמצעו) — מנסים שוב עד שהוא
  /// מחובר, כמו ב-_scheduleInitialScrollRestore של הטקסט הראשי. אחרת
  /// המפרש היה נשאר תקוע בהתחלה.
  void _scheduleInitialSync() {
    _initialSyncAttempts = 0;
    _runInitialSyncAttempt();
  }

  void _runInitialSyncAttempt() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      if (_scrollController.isAttached) {
        final state = context.read<TextBookBloc>().state;
        if (state is TextBookLoaded) {
          _syncWithMainText(state);
        }
        return;
      }

      if (_initialSyncAttempts >= 10) {
        return;
      }
      _initialSyncAttempts++;
      Future.delayed(
        const Duration(milliseconds: 50),
        _runInitialSyncAttempt,
      );
    });
  }

  /// סנכרון המפרש עם הטקסט הראשי
  void _syncWithMainText(TextBookLoaded state) {
    // אם אין תוכן או אין קישורים - אין מה לסנכרן
    if (_content == null || _content!.isEmpty || _relevantLinks.isEmpty) {
      return;
    }

    // אם ה-ScrollController עדיין לא מחובר, נדחה את הסנכרון
    if (!_scrollController.isAttached) {
      return;
    }

    // קביעת האינדקס הנוכחי בטקסט הראשי
    // אם המשתמש לחץ על שורה ספציפית, נסנכרן אליה; אחרת לפי visibleIndices
    int currentMainIndex;
    if (state.selectedIndex != null) {
      currentMainIndex = state.selectedIndex!;
    } else if (state.visibleIndices.isNotEmpty) {
      // היעד לסנכרון הוא מרכז המסך, לא השורה העליונה
      currentMainIndex = _referenceVisibleIndex(state.visibleIndices);
    } else {
      return; // אין מידע על מיקום נוכחי
    }

    // חישוב האינדקס הלוגי (עם טיפול בכותרות)
    final logicalIndex = CommentarySyncHelper.getLogicalIndex(
      currentMainIndex,
      state.content,
    );

    // חישוב האינדקס היעד במפרש — היצמדות לקישור הקודם הקרוב ביותר
    final targetIndex = CommentarySyncHelper.getCommentaryTargetIndex(
      linksForCommentary: _relevantLinks,
      logicalMainIndex: logicalIndex,
    );

    // אם אין קישור - לא מזיזים את המפרש
    if (targetIndex == null) {
      return;
    }

    // אם כבר סונכרנו לאינדקס הזה ואין לחיצה מפורשת - לא צריך לגלול שוב
    if (targetIndex == _lastSyncedIndex && state.selectedIndex == null) {
      return;
    }

    // גלילה למיקום הנכון במפרש
    if (targetIndex >= 0 &&
        targetIndex < _content!.length &&
        _scrollController.isAttached) {
      // סנכרון מגלילה רציפה (או ראשוני) — קפיצה מיידית כדי שהמפרש יעקוב
      // צמוד אחר הטקסט הראשי. אנימציה כאן הייתה יוצרת פיגור והתנגשות בין
      // אנימציות עוקבות, וגם בונה אלפי פריטים בזמן אנימציה (תקיעה).
      // רק לחיצה מפורשת על שורה מקבלת גלילה מונפשת.
      // מציב את שורת היעד בכשליש העליון של חלון המפרש (_syncAlignment),
      // מקביל לשורת המקור שנבחרה מאותה נקודה ב-viewport של הטקסט הראשי,
      // ולא בראש החלון.
      if (_lastSyncedIndex == null || state.selectedIndex == null) {
        _scrollController.jumpTo(
          index: targetIndex,
          alignment: _syncAlignment,
        );
      } else {
        _scrollController.scrollTo(
          index: targetIndex,
          duration: const Duration(milliseconds: 300),
          alignment: _syncAlignment,
        );
      }
      _lastSyncedIndex = targetIndex;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_content == null || _content!.isEmpty) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Center(
          child: Text(
            'לא ניתן לטעון את ${widget.commentatorName}',
            style: const TextStyle(fontSize: 14),
          ),
        ),
      );
    }

    return TextBookStateBuilder(
      loadingWidget: const SizedBox(),
      builder: (context, state) {
        return BlocBuilder<SettingsBloc, SettingsState>(
          builder: (context, settingsState) {
            // רק המפרשים התחתונים משתמשים בגופן שנבחר בדיאלוג צורת הדף;
            // המפרשים הצדדיים נשארים עם גופן המפרשים הגלובלי מההגדרות.
            final bottomFont =
                Settings.getValue<String>('page_shape_bottom_font') ??
                    AppFonts.defaultFont;
            final fontFamily = widget.isBottom
                ? bottomFont
                : settingsState.commentatorsFontFamily;
            final commentaryFontSize =
                PageShapeSettingsManager.getCommentaryFontSize();
            return SimpleTextViewer(
              content: _content!,
              fontSize: commentaryFontSize,
              fontFamily: fontFamily,
              selectionSyncController: widget.selectionSyncController,
              openBookCallback: widget.openBookCallback,
              scrollController: _scrollController,
              positionsListener: _positionsListener,
              isMainText: false,
              bookTitle: widget.commentatorName, // לפתיחה בטאב נפרד
              labelForIndex:
                  _commentaryToc == null ? null : _commentaryLabelForIndex,
              reportBook: _reportBook,
              highlightedIndices: _highlightedIndices, // הדגשות מקומיות
              onCommentatorChanged: _reloadCommentary, // callback לרענון
            );
          },
        );
      },
    );
  }

  /// טעינה מחדש של המפרש (אחרי החלפה)
  void _reloadCommentary() {
    // נטען מחדש את ההגדרות מה-parent
    if (mounted) {
      // נאלץ את ה-parent לטעון מחדש את ההגדרות
      final parentState =
          context.findAncestorStateOfType<_PageShapeScreenState>();
      if (parentState != null) {
        parentState._loadConfiguration();
      }
    }
  }
}

/// ידית גרירה אופקית מותאמת אישית עם קווים מתחת למפרשים העליונים
class _HorizontalDragHandle extends StatelessWidget {
  final double? leftWidth;
  final double? rightWidth;
  final String? leftCommentator;
  final String? rightCommentator;
  final ValueChanged<DragUpdateDetails> onPanUpdate;
  final VoidCallback onPanEnd;

  const _HorizontalDragHandle({
    this.leftWidth,
    this.rightWidth,
    this.leftCommentator,
    this.rightCommentator,
    required this.onPanUpdate,
    required this.onPanEnd,
  });

  @override
  Widget build(BuildContext context) {
    Widget buildDividerLine(double? width) {
      return SizedBox(
        width: (width ??
                MediaQuery.of(context).size.width *
                    _kCommentaryPaneWidthFactor) +
            _kCommentaryLabelAndSpacingWidth,
        child: Center(
          child: FractionallySizedBox(
            widthFactor: 0.5,
            child: Container(
              height: 1,
              color: Theme.of(context).dividerColor,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 16,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // קווים מתחת למפרשים העליונים - באמצע הרווח
          Row(
            children: [
              if (leftCommentator != null) buildDividerLine(leftWidth),
              const Spacer(),
              if (rightCommentator != null) buildDividerLine(rightWidth),
            ],
          ),
          // אזור גרירה שקוף על כל הרוחב
          Positioned.fill(
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeRow,
              child: GestureDetector(
                onPanUpdate: onPanUpdate,
                onPanEnd: (_) => onPanEnd(),
                child: Container(color: Colors.transparent),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
