import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/theme/theme_exports.dart';
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
import 'package:otzaria/widgets/loading_indicator.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/utils/text_manipulation.dart' as utils;
import 'package:otzaria/widgets/resizable_drag_handle.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:collection/collection.dart';
import 'dart:async';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/data/book_locator.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/widgets/custom_ui_components.dart';
import 'package:otzaria/widgets/commentary_pane_tooltip.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_debug_logger.dart';

/// קבועים לחישוב רוחב חלוניות המפרשים
const double _kCommentaryPaneWidthFactor = 0.17;

/// רוחב הכותרת האנכית + רווחים + מפריד (20 לכותרת + 4 לרווח + 8 למפריד)
const double _kCommentaryLabelAndSpacingWidth = 32.0;

/// מסך תצוגת צורת הדף - מציג את הטקסט המרכזי עם מפרשים מסביב
class PageShapeScreen extends StatefulWidget {
  final Function(OpenedTab) openBookCallback;
  final ValueNotifier<int?>? sidebarTabNotifier;
  final ValueChanged<String?>? onOpenSearch;

  const PageShapeScreen({
    super.key,
    required this.openBookCallback,
    this.sidebarTabNotifier,
    this.onOpenSearch,
  });

  @override
  State<PageShapeScreen> createState() => _PageShapeScreenState();
}

class _PageShapeScreenState extends State<PageShapeScreen> {
  late final String _debugScope;
  int _buildCount = 0;
  int _dependencyChangeCount = 0;
  String? _leftCommentator;
  String? _rightCommentator;
  String? _bottomCommentator;
  String? _bottomRightCommentator;
  bool _isLoadingConfig = true;
  bool _isLeftSidebarOpen = false;
  int _leftSidebarTabIndex = 0;
  bool _isHoveringSidebarHandle = false;

  // גדלים לחלוניות - יחושבו לפי גודל המסך
  double? _leftSidebarWidth;
  double? _leftWidth;
  double? _rightWidth;
  double? _bottomHeight;

  // הגדרות הצגת טורים
  Map<String, bool> _columnVisibility = {
    'left': true,
    'right': true,
    'bottom': true,
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dependencyChangeCount++;
    PageShapeDebugLogger.log(
      'PageShapeScreen',
      'didChangeDependencies',
      scope: _debugScope,
      data: {
        'count': _dependencyChangeCount,
      },
      level: 'LIFECYCLE',
    );
    _loadConfiguration();
    _loadSizes();
  }

  /// בדיקה האם מפרש ברירת המחדל קיים, ואם לא – הסתרת הטור כברירת מחדל
  void _hideColumnIfDefaultMissing(
      Map<String, String?> commentators, List<String> availableCommentators) {
    final newColumnVisibility = Map<String, bool>.from(_columnVisibility);
    for (final entry in commentators.entries) {
      final col = entry.key;
      final def = entry.value;
      // אם יש ברירת מחדל אך היא לא קיימת בספר – הסתר
      if (def != null && !availableCommentators.contains(def)) {
        newColumnVisibility[col] = false;
      }
    }
    if (!mounted) return;
    setState(() {
      _columnVisibility = newColumnVisibility;
    });
    PageShapeDebugLogger.log(
      'PageShapeScreen',
      'עודכנה נראות טורים בגלל מפרש ברירת מחדל חסר',
      scope: _debugScope,
      data: {
        'commentators': commentators,
        'availableCommentatorsCount': availableCommentators.length,
        'columnVisibility': _columnVisibility,
      },
    );
  }

  /// טעינת גדלים שמורים או חישוב ברירות מחדל
  void _loadSizes() {
    final trace = PageShapeDebugLogger.start(
      'PageShapeScreen',
      'טעינת גדלי חלוניות',
      scope: _debugScope,
      longTaskAfter: const Duration(milliseconds: 250),
      heartbeatEvery: const Duration(milliseconds: 250),
    );
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

    setState(() {});
    trace.end(
      data: {
        'screenWidth': screenWidth,
        'screenHeight': screenHeight,
        'leftSidebarWidth': _leftSidebarWidth,
        'leftWidth': _leftWidth,
        'rightWidth': _rightWidth,
        'bottomHeight': _bottomHeight,
      },
    );
  }

  /// שמירת גדלים
  void _saveSizes() {
    PageShapeDebugLogger.log(
      'PageShapeScreen',
      'שמירת גדלי חלוניות',
      scope: _debugScope,
      data: {
        'leftSidebarWidth': _leftSidebarWidth,
        'leftWidth': _leftWidth,
        'rightWidth': _rightWidth,
        'bottomHeight': _bottomHeight,
      },
    );
    if (_leftSidebarWidth != null) {
      Settings.setValue<double>(
          'page_shape_left_sidebar_width', _leftSidebarWidth!);
    }
    if (_leftWidth != null) {
      Settings.setValue<double>('page_shape_left_width', _leftWidth!);
    }
    if (_rightWidth != null) {
      Settings.setValue<double>('page_shape_right_width', _rightWidth!);
    }
    if (_bottomHeight != null) {
      Settings.setValue<double>('page_shape_bottom_height', _bottomHeight!);
    }
  }

  void _refreshLinksForCurrentConfiguration(String reason) {
    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded) {
      return;
    }

    PageShapeDebugLogger.log(
      'PageShapeScreen',
      'נשלחה בקשה לרענון קישורים לפי בחירת חלוניות צורת הדף',
      scope: _debugScope,
      data: {
        'reason': reason,
        'bookTitle': state.book.title,
      },
    );
    context.read<TextBookBloc>().add(
          RefreshLinksForCurrentWindow(reason: reason),
        );
  }

  Future<void> _loadConfiguration() async {
    final trace = PageShapeDebugLogger.start(
      'PageShapeScreen',
      'טעינת קונפיגורציית צורת הדף',
      scope: _debugScope,
      data: {
        'isLoadingConfigBefore': _isLoadingConfig,
      },
    );
    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded) {
      trace.warn(
        'הטעינה דולגה כי ה־state עדיין לא TextBookLoaded',
        data: {
          'stateType': state.runtimeType,
        },
      );
      trace.end(data: {'reason': 'state is not TextBookLoaded'});
      return;
    }

    trace.step(
      'נטענת קונפיגורציה עבור ספר',
      data: {
        'bookTitle': state.book.title,
        'heCategories': state.book.heCategories,
        'availableCommentatorsCount': state.availableCommentators.length,
      },
    );

    final config = PageShapeSettingsManager.loadConfiguration(
      state.book.title,
      heCategories: state.book.heCategories,
    );

    _columnVisibility =
        PageShapeSettingsManager.getColumnVisibility(state.book.title);

    final Map<String, String?> commentators;
    if (config != null) {
      trace.step(
        'נמצאה קונפיגורציה שמורה',
        data: {
          'config': config,
        },
      );
      // יש הגדרה שמורה - צריך להתאים שמות בסיסיים לשמות מלאים
      // (כי הגדרות קטגוריה שומרות רק שמות בסיסיים כמו "רמב"ן")
      commentators =
          _resolveCommentatorNames(config, state.availableCommentators);
      trace.step(
        'בוצעה התאמת שמות מפרשים לקונפיגורציה השמורה',
        data: {
          'resolvedCommentators': commentators,
        },
      );
    } else {
      trace.step('לא נמצאה קונפיגורציה שמורה, נטענות ברירות מחדל');
      // אין הגדרה שמורה בכלל - השתמש בברירות מחדל
      commentators = await DefaultCommentators.getDefaults(
        state.book,
        availableCommentators: state.availableCommentators,
      );
      trace.step(
        'נטענו מפרשי ברירת מחדל',
        data: {
          'defaultCommentators': commentators,
        },
      );
      // כאן נבדוק אם ברירת המחדל לא קיימת – נסיר את הטור
      _hideColumnIfDefaultMissing(commentators, state.availableCommentators);
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
      trace.end(
        data: {
          'leftCommentator': _leftCommentator,
          'rightCommentator': _rightCommentator,
          'bottomCommentator': _bottomCommentator,
          'bottomRightCommentator': _bottomRightCommentator,
          'columnVisibility': _columnVisibility,
        },
      );
    } else {
      trace.end(data: {'reason': 'widget unmounted before applying config'});
    }
  }

  /// התאמת שמות מפרשים בסיסיים לשמות מלאים מתוך הקישורים הזמינים
  /// למשל: "רמב"ן" → "רמב"ן על בבא מציעא"
  Map<String, String?> _resolveCommentatorNames(
      Map<String, String?> config, List<String> availableCommentators) {
    PageShapeDebugLogger.log(
      'PageShapeScreen',
      'התחלת resolve לשמות מפרשים',
      scope: _debugScope,
      data: {
        'config': config,
        'availableCommentatorsCount': availableCommentators.length,
      },
    );

    return Map.fromEntries(config.entries.map((entry) {
      final resolved = resolvePageShapeCommentatorSelection(
        selection: entry.value,
        availableCommentators: availableCommentators,
      );
      PageShapeDebugLogger.log(
        'PageShapeScreen',
        'resolve לשם מפרש בודד',
        scope: _debugScope,
        data: {
          'column': entry.key,
          'requestedSelection': entry.value,
          'resolvedSelection': resolved,
        },
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
    PageShapeDebugLogger.log(
      'PageShapeScreen',
      'בניית טור ימין',
      scope: _debugScope,
      data: {
        'isMultipleMode': _isRightPaneMultipleMode(),
        'rightCommentatorSelection': _rightCommentator,
        'selectableCommentatorsCount':
            _rightPaneSelectableCommentators(state).length,
      },
      level: 'BUILD',
    );
    if (!_isRightPaneMultipleMode()) {
      final resolvedSingle = resolvePageShapeCommentatorSelection(
        selection: _rightCommentator,
        availableCommentators: _availableCommentators(state),
      );
      if (resolvedSingle != null &&
          !isPageShapeRemainingCommentatorsValue(resolvedSingle) &&
          !isPageShapeMultiCommentatorsValue(resolvedSingle) &&
          resolvedSingle != pageShapeMultipleCommentatorsModeValue) {
        return _CommentaryPane(
          commentatorName: resolvedSingle,
          openBookCallback: widget.openBookCallback,
          onLoadFailed: () =>
              _hideColumn('right', global: false, showSnack: false),
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
      shrinkWrap: false,
      selectedCommentatorsOverride: commentators,
      commentatorGroupsOverride: _rightPaneCommentatorGroups(state),
      bookTitleOverride: state.book.title,
      onSelectedCommentatorsOverrideChanged: (selected) =>
          _saveRightPaneCommentators(state, selected),
    );
  }

  /// הסתרת טור - ניתן לבחור אם לשמור גלובלית או רק לספר הנוכחי
  void _hideColumn(String column, {bool global = true, bool showSnack = true}) {
    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded) return;

    setState(() {
      _columnVisibility[column] = false;
    });

    // שמירה גלובלית או פר-ספר
    PageShapeSettingsManager.saveColumnVisibility(
        state.book.title, _columnVisibility,
        saveAsGlobal: global);

    // הודעה למשתמש (רק אם יזום)
    if (showSnack && global) {
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
    final trace = PageShapeDebugLogger.start(
      'PageShapeScreen',
      'ניווט לשורה מחלונית קישורים/הערות',
      scope: _debugScope,
      data: {
        'lineNumber': lineNumber,
        'contentLength': state.content.length,
        'selectedIndexBefore': state.selectedIndex,
        ...PageShapeDebugLogger.summarizeIndices(state.visibleIndices),
      },
      longTaskAfter: const Duration(milliseconds: 300),
      heartbeatEvery: const Duration(milliseconds: 300),
    );
    if (lineNumber < 1 || state.content.isEmpty) {
      trace.warn('דילוג על ניווט לשורה כי lineNumber לא תקין או שהתוכן ריק');
      trace.end(data: {'reason': 'invalid line number or empty content'});
      return;
    }

    final targetIndex = (lineNumber - 1).clamp(0, state.content.length - 1);

    await state.scrollController.scrollTo(
      index: targetIndex,
      alignment: 0.05,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
    trace.step(
      'הושלמה גלילה ליעד בחלונית הראשית',
      data: {
        'targetIndex': targetIndex,
      },
    );

    if (!mounted || !context.mounted) {
      return;
    }

    final bloc = context.read<TextBookBloc>();
    bloc.add(UpdateSelectedIndex(targetIndex));
    bloc.add(HighlightLine(targetIndex));
    trace.end(
      data: {
        'targetIndex': targetIndex,
      },
    );
  }

  void _openLeftSidebarTab(int index) {
    final validIndex = index.clamp(0, 1);
    if (_isLeftSidebarOpen && _leftSidebarTabIndex == validIndex) {
      PageShapeDebugLogger.log(
        'PageShapeScreen',
        'בקשה לפתיחת סיידבר דולגה כי הוא כבר פתוח על אותו טאב',
        scope: _debugScope,
        data: {
          'requestedIndex': index,
          'validIndex': validIndex,
        },
      );
      return;
    }

    setState(() {
      _isLeftSidebarOpen = true;
      _leftSidebarTabIndex = validIndex;
    });
    PageShapeDebugLogger.log(
      'PageShapeScreen',
      'נפתח סיידבר שמאלי',
      scope: _debugScope,
      data: {
        'requestedIndex': index,
        'validIndex': validIndex,
      },
    );
  }

  void _toggleLeftSidebar() {
    setState(() {
      _isLeftSidebarOpen = !_isLeftSidebarOpen;
      if (!_isLeftSidebarOpen) {
        _isHoveringSidebarHandle = false;
      }
    });
    PageShapeDebugLogger.log(
      'PageShapeScreen',
      'הוחלף מצב פתיחת סיידבר שמאלי',
      scope: _debugScope,
      data: {
        'isLeftSidebarOpen': _isLeftSidebarOpen,
        'leftSidebarTabIndex': _leftSidebarTabIndex,
      },
    );
  }

  void _handleSidebarTabRequest() {
    final requestedTab = widget.sidebarTabNotifier?.value;
    if (requestedTab == null) {
      return;
    }

    PageShapeDebugLogger.log(
      'PageShapeScreen',
      'התקבלה בקשת טאב חיצונית לסיידבר',
      scope: _debugScope,
      data: {
        'requestedTab': requestedTab,
      },
    );

    _openLeftSidebarTab(requestedTab);
    widget.sidebarTabNotifier?.value = null;
  }

  @override
  void initState() {
    super.initState();
    _debugScope = PageShapeDebugLogger.newScope(
      'page-shape-screen',
      label: widget.key.toString(),
    );
    PageShapeDebugLogger.log(
      'PageShapeScreen',
      'initState',
      scope: _debugScope,
      data: {
        'widgetKey': widget.key.toString(),
      },
      level: 'LIFECYCLE',
    );
    widget.sidebarTabNotifier?.addListener(_handleSidebarTabRequest);
  }

  @override
  void didUpdateWidget(covariant PageShapeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    PageShapeDebugLogger.log(
      'PageShapeScreen',
      'didUpdateWidget',
      scope: _debugScope,
      data: {
        'oldSidebarNotifierChanged':
            oldWidget.sidebarTabNotifier != widget.sidebarTabNotifier,
      },
      level: 'LIFECYCLE',
    );
    if (oldWidget.sidebarTabNotifier != widget.sidebarTabNotifier) {
      oldWidget.sidebarTabNotifier?.removeListener(_handleSidebarTabRequest);
      widget.sidebarTabNotifier?.addListener(_handleSidebarTabRequest);
    }
  }

  @override
  void dispose() {
    PageShapeDebugLogger.log(
      'PageShapeScreen',
      'dispose',
      scope: _debugScope,
      data: {
        'buildCount': _buildCount,
      },
      level: 'END',
    );
    widget.sidebarTabNotifier?.removeListener(_handleSidebarTabRequest);
    super.dispose();
  }

  /// פתיחת דיאלוג בחירת מפרש לטור ספציפי
  Future<void> _openCommentatorSelector(String column) async {
    final trace = PageShapeDebugLogger.start(
      'PageShapeScreen',
      'פתיחת בורר מפרש',
      scope: _debugScope,
      data: {
        'column': column,
      },
    );
    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded) {
      trace.warn('לא ניתן לפתוח בורר מפרש כי ה־state אינו TextBookLoaded');
      trace.end(data: {'reason': 'state is not TextBookLoaded'});
      return;
    }

    // קבלת רשימת המפרשים הזמינים
    final availableCommentators = state.availableCommentators;

    if (availableCommentators.isEmpty) {
      trace.warn('לא נמצאו מפרשים זמינים לבחירה');
      trace.end(data: {'reason': 'no available commentators'});
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
      ),
    );

    // אם היו שינויים, טען מחדש את ההגדרות
    if (result == true) {
      _loadConfiguration();
      trace.step('דיאלוג המפרשים חזר עם שינויים; נטענת קונפיגורציה מחדש');
    }
    trace.end(
      data: {
        'result': result,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    _buildCount++;
    PageShapeDebugLogger.log(
      'PageShapeScreen',
      'build',
      scope: _debugScope,
      data: {
        'buildCount': _buildCount,
        'isLoadingConfig': _isLoadingConfig,
        'leftCommentator': _leftCommentator,
        'rightCommentator': _rightCommentator,
        'bottomCommentator': _bottomCommentator,
        'bottomRightCommentator': _bottomRightCommentator,
        'isLeftSidebarOpen': _isLeftSidebarOpen,
        'leftSidebarTabIndex': _leftSidebarTabIndex,
        'columnVisibility': _columnVisibility,
      },
      level: 'BUILD',
    );
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
              PageShapeDebugLogger.log(
                'PageShapeScreen',
                'התקבל עדכון מפרשים זמינים מה־bloc; נטענת קונפיגורציה מחדש',
                scope: _debugScope,
                data: {
                  'availableCommentatorsCount':
                      state.availableCommentators.length,
                },
              );
              _loadConfiguration();
            }
          },
        ),
        BlocListener<PersonalNotesBloc, PersonalNotesState>(
          listenWhen: (previous, current) =>
              previous.isCreatingNewNote != current.isCreatingNewNote,
          listener: (context, state) {
            if (state.isCreatingNewNote) {
              PageShapeDebugLogger.log(
                'PageShapeScreen',
                'PersonalNotesBloc נכנס למצב יצירת הערה; נפתח סיידבר הערות',
                scope: _debugScope,
              );
              _openLeftSidebarTab(1);
            }
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
                return Scaffold(
                  body: Stack(
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
                                              onLoadFailed: () => _hideColumn(
                                                  'left',
                                                  global: false,
                                                  showSnack: false),
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
                                        ResizableDragHandle(
                                          isVertical: true,
                                          showDivider: false,
                                          onDragDelta: (delta) {
                                            setState(() {
                                              _leftWidth =
                                                  ((_leftWidth ?? 0) - delta)
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
                                      ],
                                      Expanded(
                                        child: SimpleTextViewer(
                                          content: state.content,
                                          fontSize: state.fontSize,
                                          openBookCallback:
                                              widget.openBookCallback,
                                          scrollController:
                                              state.scrollController,
                                          positionsListener:
                                              state.positionsListener,
                                          isMainText: true,
                                          onOpenSidebarTab: _openLeftSidebarTab,
                                          onOpenSearch: widget.onOpenSearch,
                                        ),
                                      ),
                                      if (_columnVisibility['right'] ==
                                          true) ...[
                                        ResizableDragHandle(
                                          isVertical: true,
                                          showDivider: false,
                                          onDragDelta: (delta) {
                                            setState(() {
                                              _rightWidth =
                                                  ((_rightWidth ?? 0) + delta)
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
                                if (_bottomCommentator != null ||
                                    _bottomRightCommentator != null) ...[
                                  _HorizontalDragHandle(
                                    leftWidth: _leftWidth,
                                    rightWidth: _rightWidth,
                                    leftCommentator: _leftCommentator,
                                    rightCommentator: _rightPaneLabel(state),
                                    onPanUpdate: (details) {
                                      setState(() {
                                        _bottomHeight = ((_bottomHeight ?? 0) -
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
                                          child: _bottomRightCommentator != null
                                              ? Row(
                                                  children: [
                                                    if (_bottomCommentator !=
                                                        null) ...[
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
                                                          onLoadFailed: () =>
                                                              _hideColumn(
                                                                  'bottom',
                                                                  global: false,
                                                                  showSnack:
                                                                      false),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                    ],
                                                    Expanded(
                                                      child: _CommentaryPane(
                                                        commentatorName:
                                                            _bottomRightCommentator!,
                                                        openBookCallback: widget
                                                            .openBookCallback,
                                                        isBottom: true,
                                                        onLoadFailed: () =>
                                                            _hideColumn(
                                                                'bottomRight',
                                                                global: false,
                                                                showSnack:
                                                                    false),
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
                                                        onLoadFailed: () =>
                                                            _hideColumn(
                                                                'bottom'),
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
                          if (_isLeftSidebarOpen) ...[
                            ResizableDragHandle(
                              isVertical: true,
                              showDivider: false,
                              onDragDelta: (delta) {
                                setState(() {
                                  _leftSidebarWidth =
                                      ((_leftSidebarWidth ?? 0) + delta).clamp(
                                    220.0,
                                    MediaQuery.of(context).size.width * 0.35,
                                  );
                                });
                              },
                              onDragEnd: _saveSizes,
                            ),
                            SizedBox(
                              width: _leftSidebarWidth ??
                                  MediaQuery.of(context).size.width * 0.22,
                              child: LinksNotesSidebar(
                                bookId: state.book.title,
                                openBookCallback: widget.openBookCallback,
                                fontSize: state.fontSize,
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
                            ),
                          ],
                        ],
                      ),
                      // כפתור צף לפתיחת הסיידבר - מחקה את כפתור מפרשים בצד
                      if (!_isLeftSidebarOpen)
                        Positioned(
                          left: 0,
                          top: MediaQuery.of(context).size.height * 0.10,
                          child: CommentaryPaneTooltip(
                            child: MouseRegion(
                              onEnter: (_) => setState(
                                  () => _isHoveringSidebarHandle = true),
                              onExit: (_) => setState(
                                  () => _isHoveringSidebarHandle = false),
                              child: GestureDetector(
                                onTap: () => _openLeftSidebarTab(0),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  curve: Curves.easeOut,
                                  width: _isHoveringSidebarHandle ? 48 : 20,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest
                                        .withValues(
                                            alpha: _isHoveringSidebarHandle
                                                ? 0.95
                                                : 0.8),
                                    borderRadius: const BorderRadius.only(
                                      topRight: Radius.circular(40),
                                      bottomRight: Radius.circular(40),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black
                                            .withValues(alpha: 0.15),
                                        blurRadius:
                                            _isHoveringSidebarHandle ? 8 : 4,
                                        offset: const Offset(2, 0),
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: AnimatedOpacity(
                                      duration:
                                          const Duration(milliseconds: 150),
                                      opacity:
                                          _isHoveringSidebarHandle ? 1.0 : 0.6,
                                      child: Icon(
                                        FluentIcons.chevron_right_24_regular,
                                        size:
                                            _isHoveringSidebarHandle ? 24 : 18,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
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
  final bool isBottom; // האם זה מפרש תחתון
  final VoidCallback? onLoadFailed;

  const _CommentaryPane({
    required this.commentatorName,
    required this.openBookCallback,
    this.isBottom = false,
    this.onLoadFailed,
  });

  @override
  State<_CommentaryPane> createState() => _CommentaryPaneState();
}

class _CommentaryPaneState extends State<_CommentaryPane> {
  late final String _debugScope;
  int _buildCount = 0;
  int _syncAttemptCount = 0;
  List<String>? _content;
  TextBook? _reportBook;
  bool _isLoading = true;
  final ItemScrollController _scrollController = ItemScrollController();
  final ItemPositionsListener _positionsListener =
      ItemPositionsListener.create();
  List<Link> _relevantLinks = [];
  int? _lastSyncedIndex; // האינדקס האחרון שסונכרן
  int? _clickedVisibleFirst; // visibleIndices.first בעת הלחיצה האחרונה
  List<Link>? _lastLinks; // לדידוב: מסנן מחדש רק כשהקישורים השתנו
  StreamSubscription<TextBookState>? _blocSubscription;
  Set<int> _highlightedIndices = {}; // אינדקסים להדגשה
  bool _highlightEnabled = false;
  int _blocLoadedCallbackCount = 0;
  int _refreshRelevantLinksCount = 0;
  int _highlightUpdateCallCount = 0;

  @override
  void initState() {
    super.initState();
    _debugScope = PageShapeDebugLogger.newScope(
      'page-shape-commentary-pane',
      label: widget.commentatorName,
    );
    PageShapeDebugLogger.log(
      'CommentaryPane',
      'initState',
      scope: _debugScope,
      data: {
        'commentatorName': widget.commentatorName,
        'isBottom': widget.isBottom,
      },
      level: 'LIFECYCLE',
    );
    // דוחה את הטעינה כדי לוודא שכל ה-providers מוכנים וה-bloc זמין
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        PageShapeDebugLogger.log(
          'CommentaryPane',
          'PostFrame ראשון - מתחילים טעינה והאזנה ל־bloc',
          scope: _debugScope,
        );
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
    PageShapeDebugLogger.log(
      'CommentaryPane',
      'didUpdateWidget',
      scope: _debugScope,
      data: {
        'oldCommentatorName': oldWidget.commentatorName,
        'newCommentatorName': widget.commentatorName,
      },
      level: 'LIFECYCLE',
    );
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
    PageShapeDebugLogger.log(
      'CommentaryPane',
      'dispose',
      scope: _debugScope,
      data: {
        'buildCount': _buildCount,
        'syncAttemptCount': _syncAttemptCount,
        'lastSyncedIndex': _lastSyncedIndex,
      },
      level: 'END',
    );
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
      PageShapeDebugLogger.log(
        'CommentaryPane',
        'עודכנה הגדרת הדגשה',
        scope: _debugScope,
        data: {
          'newHighlightEnabled': newHighlightEnabled,
          'highlightChanged': highlightChanged,
          'selectedIndex': state.selectedIndex,
        },
      );
      // עדכון הדגשות - גם בטעינה ראשונית וגם כשההגדרה משתנה
      if (highlightChanged || _highlightedIndices.isEmpty) {
        _updateHighlights(state);
      }
    }
  }

  /// הגדרת מאזין לשינויים ב-Bloc
  void _setupBlocListener() {
    PageShapeDebugLogger.log(
      'CommentaryPane',
      'מתחילה הגדרת מאזין ל־TextBookBloc',
      scope: _debugScope,
    );
    // טעינת הגדרת הדגשה ראשונית
    _updateHighlightSettings();

    _blocSubscription = context.read<TextBookBloc>().stream.listen((state) {
      if (state is TextBookLoaded && mounted) {
        _blocLoadedCallbackCount++;
        final callbackStopwatch = Stopwatch()..start();
        PageShapeDebugLogger.log(
          'CommentaryPane',
          'התקבל עדכון TextBookLoaded מה־bloc',
          scope: _debugScope,
          data: {
            'blocLoadedCallbackCount': _blocLoadedCallbackCount,
            'selectedIndex': state.selectedIndex,
            ...PageShapeDebugLogger.summarizeIndices(state.visibleIndices),
            'linksCount': state.links.length,
          },
        );
        final refreshStopwatch = Stopwatch()..start();
        // מסנן מחדש רק כשהקישורים עצמם השתנו (UpdateLinks),
        // ולא בכל גלילה (UpdateVisibleIndecies / UpdateSelectedIndex)
        if (!identical(_lastLinks, state.links)) {
          _lastLinks = state.links;
          _refreshRelevantLinks(state);
        }
        final refreshElapsedMs = refreshStopwatch.elapsedMilliseconds;
        final syncStopwatch = Stopwatch()..start();
        _syncWithMainText(state);
        final syncElapsedMs = syncStopwatch.elapsedMilliseconds;
        final highlightStopwatch = Stopwatch()..start();
        _updateHighlights(state);
        final highlightElapsedMs = highlightStopwatch.elapsedMilliseconds;
        PageShapeDebugLogger.log(
          'CommentaryPane',
          'הסתיים callback של TextBookLoaded בחלונית מפרש',
          scope: _debugScope,
          data: {
            'blocLoadedCallbackCount': _blocLoadedCallbackCount,
            'refreshRelevantLinksElapsedMs': refreshElapsedMs,
            'syncWithMainTextElapsedMs': syncElapsedMs,
            'updateHighlightsElapsedMs': highlightElapsedMs,
            'totalElapsedMs': callbackStopwatch.elapsedMilliseconds,
          },
          level: 'STEP',
        );
      }
    });
  }

  void _refreshRelevantLinks(TextBookLoaded state) {
    _refreshRelevantLinksCount++;
    final stopwatch = Stopwatch()..start();
    _relevantLinks = state.links.where((link) {
      final linkTitle = utils.getTitleFromPath(link.path2);
      return linkTitle == widget.commentatorName &&
          LinkTypes.isCommentaryOrTargum(link.connectionType);
    }).toList();
    PageShapeDebugLogger.log(
      'CommentaryPane',
      'רועננו קישורים רלוונטיים למפרש',
      scope: _debugScope,
      data: {
        'refreshRelevantLinksCount': _refreshRelevantLinksCount,
        'relevantLinksCount': _relevantLinks.length,
        'totalLinksCount': state.links.length,
        'elapsedMs': stopwatch.elapsedMilliseconds,
      },
    );
  }

  void _updateHighlights(TextBookLoaded state) {
    _highlightUpdateCallCount++;
    final stopwatch = Stopwatch()..start();
    if (!_highlightEnabled || state.selectedIndex == null) {
      if (_highlightedIndices.isNotEmpty) {
        setState(() {
          _highlightedIndices = {};
        });
        PageShapeDebugLogger.log(
          'CommentaryPane',
          'אופסו הדגשות מקומיות',
          scope: _debugScope,
          data: {
            'highlightUpdateCallCount': _highlightUpdateCallCount,
            'highlightEnabled': _highlightEnabled,
            'selectedIndex': state.selectedIndex,
            'elapsedMs': stopwatch.elapsedMilliseconds,
          },
        );
      }
      PageShapeDebugLogger.log(
        'CommentaryPane',
        'חישוב הדגשות הסתיים ללא הדגשות פעילות',
        scope: _debugScope,
        data: {
          'highlightUpdateCallCount': _highlightUpdateCallCount,
          'highlightEnabled': _highlightEnabled,
          'selectedIndex': state.selectedIndex,
          'elapsedMs': stopwatch.elapsedMilliseconds,
        },
        level: 'STEP',
      );
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
      PageShapeDebugLogger.log(
        'CommentaryPane',
        'עודכנו הדגשות למפרש',
        scope: _debugScope,
        data: {
          'highlightUpdateCallCount': _highlightUpdateCallCount,
          'mainLineNumber': mainLineNumber,
          'highlightedIndices': _highlightedIndices,
          'elapsedMs': stopwatch.elapsedMilliseconds,
        },
      );
      return;
    }
    PageShapeDebugLogger.log(
      'CommentaryPane',
      'חישוב הדגשות הסתיים ללא שינוי',
      scope: _debugScope,
      data: {
        'highlightUpdateCallCount': _highlightUpdateCallCount,
        'mainLineNumber': mainLineNumber,
        'highlightedIndicesCount': _highlightedIndices.length,
        'elapsedMs': stopwatch.elapsedMilliseconds,
      },
      level: 'STEP',
    );
  }

  Future<void> _loadCommentary() async {
    final trace = PageShapeDebugLogger.start(
      'CommentaryPane',
      'טעינת מפרש',
      scope: _debugScope,
      data: {
        'commentatorName': widget.commentatorName,
        'isBottom': widget.isBottom,
      },
      longTaskAfter: const Duration(milliseconds: 400),
      heartbeatEvery: const Duration(milliseconds: 400),
    );
    if (!mounted) return;
    setState(() => _isLoading = true);
    trace.step('הוגדר _isLoading=true');

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
          trace.warn(
            'Timeout בהמתנה ל־TextBookLoaded',
            data: {
              'error': e,
            },
          );
        }
      }

      if (!mounted) return;

      if (state is TextBookLoaded) {
        // סינון קישורים לפי שם המפרש ולפי סוג הקישור (COMMENTARY/TARGUM)
        _refreshRelevantLinks(state);
        trace.step(
          'ה־state זמין ורועננו קישורים רלוונטיים',
          data: {
            'bookTitle': state.book.title,
            'relevantLinksCount': _relevantLinks.length,
          },
        );
      }

      // מציאת הספר המלא של המפרש עם categoryId
      TextBook book;
      final bookLocation = await BookLocator.locateBook(widget.commentatorName);
      trace.step(
        'בוצע איתור ספר המפרש',
        data: {
          'bookLocationFound': bookLocation != null,
          'bookLocationHasBook': bookLocation?.book != null,
          'bookLocationCategoryId': bookLocation?.categoryId,
        },
      );

      if (bookLocation != null &&
          bookLocation.book != null &&
          bookLocation.categoryId != null) {
        // נמצא ספר ב-DB - נשתמש בנתונים שלו
        final dbBook = bookLocation.book!;

        // נצטרך למצוא את ה-categoryPath מה-DB
        final repository = SqliteDataProvider.instance.repository;
        String? categoryPath;
        if (repository != null) {
          try {
            var category = await repository.getCategory(dbBook.categoryId);
            if (category != null) {
              // בניית נתיב הקטגוריה
              final pathParts = <String>[];
              while (category != null) {
                pathParts.insert(0, category.title);
                if (category.parentId != null) {
                  category = await repository.getCategory(category.parentId!);
                } else {
                  break;
                }
              }
              categoryPath = pathParts.join(', ');
            }
          } catch (e) {
            trace.warn(
              'שגיאה בקבלת category path עבור מפרש',
              data: {
                'error': e,
              },
            );
          }
        }

        book = TextBook(
          title: widget.commentatorName,
          categoryId: bookLocation.categoryId,
          categoryPath: categoryPath,
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
          trace.warn('לא נמצא categoryId עבור המפרש');
          book = TextBook(title: widget.commentatorName);
        }
      }
      trace.step(
        'נבנה אובייקט TextBook עבור המפרש',
        data: {
          'reportBookTitle': book.title,
          'reportBookCategoryId': book.categoryId,
          'reportBookCategoryPath': book.categoryPath,
        },
      );

      // טעינת הטקסט ישירות מה-provider המתאים
      String bookContent;
      if (bookLocation != null &&
          bookLocation.book != null &&
          bookLocation.categoryId != null) {
        // ספר מה-DB - נשתמש ב-DatabaseLibraryProvider
        final dbProvider = LibraryProviderManager.instance.databaseProvider;
        final text = await dbProvider.getBookText(
          widget.commentatorName,
          bookLocation.categoryId!,
          'txt',
        );
        bookContent = text ?? '';
      } else {
        // ספר ממערכת הקבצים - נשתמש ב-book.text
        bookContent = await book.text;
      }
      trace.step(
        'הוחזר תוכן טקסט למפרש',
        data: {
          'contentLength': bookContent.length,
          'usedDatabaseProvider': bookLocation != null &&
              bookLocation.book != null &&
              bookLocation.categoryId != null,
        },
      );

      if (bookContent.isEmpty) {
        trace.warn('תוכן המפרש חזר ריק');
        if (widget.onLoadFailed != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.onLoadFailed!();
          });
        }
        throw Exception('Book text is empty for "${widget.commentatorName}"');
      }

      final lines = bookContent.split('\n');

      if (!mounted) return;

      setState(() {
        _reportBook = book;
        _content = lines;
        _isLoading = false;
        _lastSyncedIndex = null; // איפוס לסנכרון ראשוני
      });
      trace.step(
        'התוכן הוחל על ה־widget',
        data: {
          'linesCount': lines.length,
        },
      );

      // סנכרון ראשוני - נדחה מעט כדי לוודא שה-ScrollController מוכן
      final currentState = state;
      if (currentState is TextBookLoaded) {
        // נחכה שה-widget יבנה ואז נסנכרן
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            PageShapeDebugLogger.log(
              'CommentaryPane',
              'PostFrame לסנכרון ראשוני אחרי טעינת תוכן',
              scope: _debugScope,
            );
            _syncWithMainText(currentState);
          }
        });
      }
      trace.end(
        data: {
          'linesCount': lines.length,
          'relevantLinksCount': _relevantLinks.length,
        },
      );
    } catch (e) {
      trace.fail(e, StackTrace.current);
      if (widget.onLoadFailed != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onLoadFailed!();
        });
      }
      if (mounted) {
        setState(() {
          _reportBook = null;
          _content = null;
          _isLoading = false;
        });
      }
    }
  }

  /// סנכרון המפרש עם הטקסט הראשי
  void _syncWithMainText(TextBookLoaded state) {
    _syncAttemptCount++;
    final stopwatch = Stopwatch()..start();
    PageShapeDebugLogger.log(
      'CommentaryPane',
      'ניסיון סנכרון מפרש מול הטקסט הראשי',
      scope: _debugScope,
      data: {
        'syncAttemptCount': _syncAttemptCount,
        'contentLoaded': _content != null,
        'contentLength': _content?.length ?? 0,
        'relevantLinksCount': _relevantLinks.length,
        'selectedIndex': state.selectedIndex,
        ...PageShapeDebugLogger.summarizeIndices(state.visibleIndices),
        'scrollControllerAttached': _scrollController.isAttached,
      },
      level: 'SYNC',
    );
    // אם אין תוכן או אין קישורים - אין מה לסנכרן
    if (_content == null || _content!.isEmpty || _relevantLinks.isEmpty) {
      PageShapeDebugLogger.log(
        'CommentaryPane',
        'סנכרון דולג כי חסר תוכן או חסרים קישורים רלוונטיים',
        scope: _debugScope,
        data: {
          'contentIsNull': _content == null,
          'contentIsEmpty': _content?.isEmpty ?? true,
          'relevantLinksCount': _relevantLinks.length,
          'elapsedMs': stopwatch.elapsedMilliseconds,
        },
        level: 'SYNC',
      );
      return;
    }

    // אם ה-ScrollController עדיין לא מחובר, נדחה את הסנכרון
    if (!_scrollController.isAttached) {
      PageShapeDebugLogger.log(
        'CommentaryPane',
        'סנכרון נדחה כי ScrollController עדיין לא מחובר',
        scope: _debugScope,
        data: {
          'elapsedMs': stopwatch.elapsedMilliseconds,
          'willRetryVia': 'next bloc update or post-load sync',
        },
        level: 'SYNC',
      );
      return;
    }

    // קביעת האינדקס הנוכחי בטקסט הראשי
    // אם המשתמש לחץ על שורה ספציפית, נסנכרן אליה; אחרת לפי visibleIndices
    int currentMainIndex;
    if (state.selectedIndex != null) {
      currentMainIndex = state.selectedIndex!;
      _clickedVisibleFirst =
          state.visibleIndices.isNotEmpty ? state.visibleIndices.first : null;
    } else if (state.visibleIndices.isNotEmpty) {
      final currentFirst = state.visibleIndices.first;
      // אם לא גללנו יותר מ-3 שורות מאז הלחיצה — לא לדרוס את מיקום הלחיצה
      // (מתואם עם הסף של ה-BLoC לאיפוס selectedIndex)
      if (_clickedVisibleFirst != null &&
          (currentFirst - _clickedVisibleFirst!).abs() <= 3) {
        return;
      }
      _clickedVisibleFirst = null; // גלילה משמעותית — מאפסים
      currentMainIndex = currentFirst;
    } else {
      PageShapeDebugLogger.log(
        'CommentaryPane',
        'סנכרון דולג כי אין selectedIndex ואין visibleIndices',
        scope: _debugScope,
        data: {
          'elapsedMs': stopwatch.elapsedMilliseconds,
        },
        level: 'SYNC',
      );
      return; // אין מידע על מיקום נוכחי
    }

    // חישוב האינדקס הלוגי (עם טיפול בכותרות)
    final logicalIndex = CommentarySyncHelper.getLogicalIndex(
      currentMainIndex,
      state.content,
    );

    // מציאת הקישור הטוב ביותר
    final bestLink = CommentarySyncHelper.findBestLink(
      linksForCommentary: _relevantLinks,
      logicalMainIndex: logicalIndex,
    );

    // חישוב האינדקס היעד במפרש
    final targetIndex = CommentarySyncHelper.getCommentaryTargetIndex(bestLink);

    // אם אין קישור - לא מזיזים את המפרש
    if (targetIndex == null) {
      PageShapeDebugLogger.log(
        'CommentaryPane',
        'לא נמצא targetIndex לסנכרון',
        scope: _debugScope,
        data: {
          'currentMainIndex': currentMainIndex,
          'logicalIndex': logicalIndex,
          'elapsedMs': stopwatch.elapsedMilliseconds,
        },
        level: 'SYNC',
      );
      return;
    }

    // אם כבר סונכרנו לאינדקס הזה ואין לחיצה מפורשת - לא צריך לגלול שוב
    if (targetIndex == _lastSyncedIndex && state.selectedIndex == null) {
      PageShapeDebugLogger.log(
        'CommentaryPane',
        'סנכרון דולג כי היעד זהה ליעד האחרון',
        scope: _debugScope,
        data: {
          'targetIndex': targetIndex,
          'elapsedMs': stopwatch.elapsedMilliseconds,
        },
        level: 'SYNC',
      );
      return;
    }

    // גלילה למיקום הנכון במפרש
    if (targetIndex >= 0 &&
        targetIndex < _content!.length &&
        _scrollController.isAttached) {
      PageShapeDebugLogger.log(
        'CommentaryPane',
        'מתבצעת גלילת סנכרון למפרש',
        scope: _debugScope,
        data: {
          'currentMainIndex': currentMainIndex,
          'logicalIndex': logicalIndex,
          'targetIndex': targetIndex,
          'bestLinkIndex1': bestLink?.index1,
          'bestLinkIndex2': bestLink?.index2,
          'distanceFromLastTarget':
              _lastSyncedIndex == null ? null : targetIndex - _lastSyncedIndex!,
          'elapsedMsBeforeScrollRequest': stopwatch.elapsedMilliseconds,
        },
        level: 'SYNC',
      );
      _scrollController.scrollTo(
        index: targetIndex,
        duration: const Duration(milliseconds: 300),
        alignment: 0.0, // בראש החלון
      );
      _lastSyncedIndex = targetIndex;
    } else {
      PageShapeDebugLogger.log(
        'CommentaryPane',
        'סנכרון דולג כי targetIndex מחוץ לטווח או שה־ScrollController מנותק',
        scope: _debugScope,
        data: {
          'targetIndex': targetIndex,
          'contentLength': _content!.length,
          'scrollControllerAttached': _scrollController.isAttached,
          'elapsedMs': stopwatch.elapsedMilliseconds,
        },
        level: 'SYNC',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    _buildCount++;
    PageShapeDebugLogger.log(
      'CommentaryPane',
      'build',
      scope: _debugScope,
      data: {
        'buildCount': _buildCount,
        'isLoading': _isLoading,
        'contentLength': _content?.length ?? 0,
        'relevantLinksCount': _relevantLinks.length,
        'highlightedIndicesCount': _highlightedIndices.length,
        'lastSyncedIndex': _lastSyncedIndex,
      },
      level: 'BUILD',
    );
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
            // מפרשים תחתונים משתמשים בגופן מההגדרות, עליונים בגופן הרגיל
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
              openBookCallback: widget.openBookCallback,
              scrollController: _scrollController,
              positionsListener: _positionsListener,
              isMainText: false,
              bookTitle: widget.commentatorName, // לפתיחה בטאב נפרד
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
      PageShapeDebugLogger.log(
        'CommentaryPane',
        'בקשת reload למפרש דרך ההורה',
        scope: _debugScope,
      );
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
