import 'dart:collection';
import 'dart:math' as math;

import 'package:otzaria/text_book/view/page_shape/utils/page_shape_default_commentators.dart';
import 'package:otzaria/book_common/utils/commentator_name_matching.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/theme/app_fonts.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/utils/reader_build_policy.dart';
import 'package:otzaria/text_book/utils/section_search_utils.dart'
    show noteAnchorFractionInLine;
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_settings_manager.dart';
import 'package:otzaria/text_book/view/tabbed_commentary_panel.dart';
import 'package:otzaria/book_common/models/commentator_group.dart';
import 'package:otzaria/text_book/view/page_shape/simple_text_viewer.dart';
import 'package:otzaria/text_book/view/page_shape/utils/commentary_anchor_links.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_commentary_selection.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_plugin_api.dart';
import 'package:otzaria/text_book/view/page_shape/utils/commentary_sync_helper.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_workspace_scope.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_pane_sizes.dart';
import 'package:otzaria/text_book/view/page_shape/page_shape_settings_panel.dart';
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
import 'package:otzaria/widgets/layout/reading_area_width.dart';
import 'package:otzaria/widgets/layout/resizable_drag_handle.dart';
import 'package:otzaria/widgets/layout/adaptive_side_pane.dart';
import 'package:otzaria/widgets/layout/context_overlay_panel.dart';
import 'package:positioned_sliver_list/positioned_list.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:collection/collection.dart';

import 'dart:async';
import 'dart:isolate';

import 'package:otzaria/core/messages/text_book_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/data/book_locator.dart';
import 'package:otzaria/library/hidden/hidden_titles.dart';
import 'package:otzaria/library/hidden/hidden_library_store.dart';
import 'package:otzaria/data/data_providers/book_database_resolver.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/text_book/models/book_notes.dart';
import 'package:otzaria/text_book/repository/book_notes_repository.dart';
import 'package:otzaria/personal_notes/widgets/commentary_notes_section.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/text_book/view/reading_viewport/reading_scrollbar_label.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/text_book/view/selection/selection_sync_controller.dart';
import 'package:otzaria/widgets/navigation/panel_tab_header.dart';

/// ברירות מחדל לגודל הטורים, כחלק מהדף
const double _kCommentaryPaneWidthFactor = 0.17;
const double _kBottomPaneHeightFactor = 0.27;
const double _kBottomLeftPaneWidthFactor = 0.5;

/// רוחב הכותרת האנכית + רווחים + מפריד (20 לכותרת + 4 לרווח + 8 למפריד)
const double _kCommentaryLabelAndSpacingWidth = 32.0;

/// מסך תצוגת צורת הדף - מציג את הטקסט המרכזי עם מפרשים מסביב
typedef PageShapeDefaultsLoader =
    Future<({Map<String, String?> commentators, Map<String, bool> visibility})>
    Function(TextBook book, List<String> availableCommentators);

class PageShapeScreen extends StatefulWidget {
  final Function(OpenedTab) openBookCallback;
  final ValueNotifier<int?>? sidebarTabNotifier;

  /// בקשה לפתיחת חלונית הגדרות צורת הדף (מכפתור גלגל השיניים בסרגל העליון).
  /// המסך פותח את החלונית בעצמו כדי שהשינויים יוחלו עליו בעדכון חי.
  final ValueNotifier<int>? openSettingsNotifier;
  final ValueChanged<String?>? onOpenSearch;
  final TextBookTab? tab;
  @visibleForTesting
  final PageShapeDefaultsLoader? defaultsLoader;

  const PageShapeScreen({
    super.key,
    required this.openBookCallback,
    this.sidebarTabNotifier,
    this.openSettingsNotifier,
    this.onOpenSearch,
    this.tab,
    this.defaultsLoader,
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
  int _loadConfigurationGeneration = 0;
  StreamSubscription<void>? _hiddenSelectionSubscription;
  bool _applyTextMaxWidth = PageShapeSettingsManager.getApplyTextMaxWidth();
  bool _isLeftSidebarOpen = false;
  int _leftSidebarTabIndex = 0;
  String? _notesBookIdOverride;
  int? _notesCategoryIdOverride;
  int? _notesFocusLineNumber;

  // פאנל הגדרות צורת הדף (overlay צף בצד הימני). המפתח מאולץ מחדש בכל פתיחה
  // כדי שהפאנל ייטען עם הערכים העדכניים גם אחרי שינויים במסך.
  bool _isSettingsPaneOpen = false;
  int _settingsPaneKey = 0;
  final SelectionSyncController _selectionSyncController =
      SelectionSyncController();
  final ValueNotifier<int> _openCommentatorsFilterNotifier = ValueNotifier<int>(
    0,
  );
  final ValueNotifier<int> _closeCommentatorsFilterNotifier =
      ValueNotifier<int>(0);
  final GlobalKey _mainTextViewerKey = GlobalKey();

  // סרגל הצד בפיקסלים; הטורים כחלק יחסי מהדף כדי לשמור על היחס בשינוי גודל.
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
  final Map<String, bool> _pluginVisibilityOverrides = {};

  String? get _activeWorkspaceId => activePageShapeWorkspaceId(context);

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

    // סרגל הצד נשמר בפיקסלים — יש לחתוך לגבולות החלון הנוכחי.
    _leftSidebarWidth =
        (Settings.getValue<double>('page_shape_left_sidebar_width') ??
                screenWidth * 0.22)
            .clamp(0.0, screenWidth * 0.35);
    _leftWidth = _loadFraction('page_shape_left_width', screenWidth);
    _rightWidth = _loadFraction('page_shape_right_width', screenWidth);
    _bottomHeight = _loadFraction('page_shape_bottom_height', screenHeight);
    _bottomLeftWidth = _loadFraction(
      'page_shape_bottom_left_width',
      screenWidth,
    );

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
    final book = widget.tab?.book;
    if (book == null) return;

    final settings = await TextBookPerBookSettings.load(book);
    if (settings == null || !mounted) return;

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final left = _storedFraction(settings.pageShapeLeftWidth, screenWidth);
    final right = _storedFraction(settings.pageShapeRightWidth, screenWidth);
    final bottom = _storedFraction(
      settings.pageShapeBottomHeight,
      screenHeight,
    );
    final bottomLeft = _storedFraction(
      settings.pageShapeBottomLeftWidth,
      screenWidth,
    );
    setState(() {
      _leftWidth = left ?? _leftWidth;
      _rightWidth = right ?? _rightWidth;
      _bottomHeight = bottom ?? _bottomHeight;
      _bottomLeftWidth = bottomLeft ?? _bottomLeftWidth;
    });

    final hasLegacy = [
      settings.pageShapeLeftWidth,
      settings.pageShapeRightWidth,
      settings.pageShapeBottomHeight,
      settings.pageShapeBottomLeftWidth,
    ].any((value) => value != null && value > 1);
    if (hasLegacy) {
      // ממירים מתוך הערך העדכני, כדי לא לדרוס שמירה מגרירה שקדמה לנו.
      await TextBookPerBookSettings.mutate(book, (existing) {
        final current = existing ?? TextBookPerBookSettings();
        return current.copyWith(
          pageShapeLeftWidth: _storedFraction(
            current.pageShapeLeftWidth,
            screenWidth,
          ),
          pageShapeRightWidth: _storedFraction(
            current.pageShapeRightWidth,
            screenWidth,
          ),
          pageShapeBottomHeight: _storedFraction(
            current.pageShapeBottomHeight,
            screenHeight,
          ),
          pageShapeBottomLeftWidth: _storedFraction(
            current.pageShapeBottomLeftWidth,
            screenWidth,
          ),
        );
      });
    }
  }

  static double? _storedFraction(double? stored, double legacyExtent) =>
      stored == null ? null : pageShapeStoredFraction(stored, legacyExtent);

  /// פיקסלים מגרסה קודמת מומרים פעם אחת ונשמרים כיחס, אחרת כל שינוי
  /// גודל חלון היה ממיר אותם מחדש ביחס לגודל אחר.
  static double? _loadFraction(String key, double legacyExtent) {
    final stored = Settings.getValue<double>(key);
    final fraction = _storedFraction(stored, legacyExtent);
    if (fraction != null && fraction != stored) {
      Settings.setValue<double>(key, fraction);
    }
    return fraction;
  }

  void _reanchorMainText() => widget.tab?.lines.keepViewAcrossRelayout();

  /// שמירת גדלים
  void _saveSizes() {
    _reanchorMainText();
    // סרגל הצד נשמר תמיד גלובלית (אינו חלק מרוחב הטורים).
    if (_leftSidebarWidth != null) {
      Settings.setValue<double>(
        'page_shape_left_sidebar_width',
        _leftSidebarWidth!,
      );
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
        'page_shape_bottom_left_width',
        _bottomLeftWidth!,
      );
    }
  }

  /// שמירת רוחבי הטורים לספר הנוכחי, תוך שימור שאר ההגדרות הפר-ספריות.
  /// השמירה אטומית (דרך [TextBookPerBookSettings.mutate]) כדי שלא תדרוס
  /// שמירה מקבילה של גופן/ניקוד וכו' על אותו ספר.
  Future<void> _savePerBookSizes() async {
    final book = widget.tab?.book;
    if (book == null) return;

    final leftWidth = _leftWidth;
    final rightWidth = _rightWidth;
    final bottomHeight = _bottomHeight;
    final bottomLeftWidth = _bottomLeftWidth;

    await TextBookPerBookSettings.mutate(
      book,
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
      RefreshLinksForCurrentWindow(
        reason: reason,
        workspaceId: _activeWorkspaceId,
      ),
    );
  }

  Future<void> _loadConfiguration() async {
    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded) {
      return;
    }

    final generation = ++_loadConfigurationGeneration;
    final hiddenTitlesFuture = currentHiddenBookTitles();

    final config = PageShapeSettingsManager.loadConfiguration(
      state.book.title,
      heCategories: state.book.heCategories,
      workspaceId: _activeWorkspaceId,
    );

    _columnVisibility = PageShapeSettingsManager.getColumnVisibility(
      state.book.title,
      heCategories: state.book.heCategories,
      workspaceId: _activeWorkspaceId,
    );

    final Map<String, String?> commentators;
    if (config != null) {
      final hiddenTitles = await hiddenTitlesFuture;
      if (!mounted || generation != _loadConfigurationGeneration) return;
      // יש הגדרה שמורה - צריך להתאים שמות בסיסיים לשמות מלאים
      // (כי הגדרות קטגוריה שומרות רק שמות בסיסיים כמו "רמב"ן")
      commentators = _resolveCommentatorNames(
        config,
        state.availableCommentators,
        state.book.title,
        hiddenTitles,
      );
    } else {
      // אין הגדרה שמורה בכלל - השתמש בברירות מחדל
      final defaultsFuture =
          widget.defaultsLoader?.call(
            state.book,
            state.availableCommentators,
          ) ??
          PageShapeDefaultCommentators.getPageShapeDefaults(
            state.book,
            availableCommentators: state.availableCommentators,
          );
      final hiddenTitles = await hiddenTitlesFuture;
      final defaults = await defaultsFuture;
      // טעינה חדשה יותר (למשל אחרי העשרת heCategories) כבר רצה — לא לדרוס.
      if (generation != _loadConfigurationGeneration) return;
      commentators = _resolveCommentatorNames(
        defaults.commentators,
        state.availableCommentators,
        state.book.title,
        hiddenTitles,
      );
      for (final entry in defaults.visibility.entries) {
        if (!entry.value) _columnVisibility[entry.key] = false;
      }
    }

    if (mounted) {
      setState(() {
        _leftCommentator = commentators['left'];
        _rightCommentator = commentators['right'];
        _bottomCommentator = commentators['bottom'];
        _bottomRightCommentator = commentators['bottomRight'];
        _applyTextMaxWidth = PageShapeSettingsManager.getApplyTextMaxWidth();
        _isLoadingConfig = false;
      });
      _refreshLinksForCurrentConfiguration('page-shape configuration loaded');
    }
  }

  /// התאמת שמות מפרשים בסיסיים לשמות מלאים מתוך הקישורים הזמינים
  /// למשל: "רמב"ן" → "רמב"ן על בבא מציעא"
  Map<String, String?> _resolveCommentatorNames(
    Map<String, String?> config,
    List<String> availableCommentators,
    String bookTitle,
    Set<String> hiddenTitles,
  ) {
    final hiddenList = hiddenTitles.toList();
    return Map.fromEntries(
      config.entries.map((entry) {
        final resolved = resolvePageShapeCommentatorSelection(
          selection: entry.value,
          availableCommentators: availableCommentators,
          commentedBookTitle: bookTitle,
        );
        if (resolved != null &&
            !availableCommentators.contains(resolved) &&
            findMatchingCommentator(
                  entry.value ?? resolved,
                  hiddenList,
                  commentedBookTitle: bookTitle,
                ) !=
                null) {
          return MapEntry(entry.key, null);
        }
        return MapEntry(entry.key, resolved);
      }),
    );
  }

  /// "הערות" הוא מפרש וירטואלי בלי קישורים (הטור היה נפתח ונעלם), ומפרש
  /// "נדיר" הוא בדרך כלל קישור בודד שסווג בטעות — שניהם לא מוצעים בטורים.
  List<String> _availableCommentators(TextBookLoaded state) {
    return state.availableCommentators
        .where(
          (title) =>
              title != kNotesCommentatorTitle &&
              !state.rareCommentators.contains(title),
        )
        .toList();
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
      commentedBookTitle: state.book.title,
    );
  }

  List<String> _displayedCommentators(TextBookLoaded state) => [
    for (final (column, commentator) in [
      ('left', _leftCommentator),
      ('bottom', _bottomCommentator),
      ('bottomRight', _bottomRightCommentator),
    ])
      if (commentator != null && _isCommentatorVisible(column, commentator))
        commentator,
    ..._selectedRightPaneCommentators(
      state,
    ).where((commentator) => _isCommentatorVisible('right', commentator)),
  ];

  bool _isCommentatorVisible(String column, String? commentator) {
    if (commentator == null) return _columnVisibility[column] == true;
    return _pluginVisibilityOverrides[commentator] ??
        (_columnVisibility[column] == true);
  }

  bool _shouldShowRightPane(TextBookLoaded state) {
    final commentators = _selectedRightPaneCommentators(state);
    if (commentators.isEmpty) return _columnVisibility['right'] == true;
    return commentators.any(
      (commentator) => _isCommentatorVisible('right', commentator),
    );
  }

  Set<String> _hiddenRightPaneCommentators(TextBookLoaded state) {
    return _selectedRightPaneCommentators(state)
        .where((commentator) => !_isCommentatorVisible('right', commentator))
        .toSet();
  }

  PageShapeLayoutSnapshot? _pluginLayout() {
    final state = context.read<TextBookBloc>().state;
    if (_isLoadingConfig || state is! TextBookLoaded) return null;

    PageShapeCommentatorState? entry(String column, String? commentator) {
      if (commentator == null) return null;
      return PageShapeCommentatorState(
        commentator: commentator,
        visible: _isCommentatorVisible(column, commentator),
      );
    }

    return PageShapeLayoutSnapshot(
      available: List<String>.from(state.availableCommentators),
      left: entry('left', _leftCommentator),
      right: _selectedRightPaneCommentators(state)
          .map(
            (commentator) => PageShapeCommentatorState(
              commentator: commentator,
              visible: _isCommentatorVisible('right', commentator),
            ),
          )
          .toList(),
      bottom: entry('bottom', _bottomCommentator),
      bottomRight: entry('bottomRight', _bottomRightCommentator),
    );
  }

  String? _columnForCommentator(String commentator, TextBookLoaded state) {
    if (_leftCommentator == commentator) return 'left';
    if (_bottomCommentator == commentator) return 'bottom';
    if (_bottomRightCommentator == commentator) return 'bottomRight';
    if (_selectedRightPaneCommentators(state).contains(commentator)) {
      return 'right';
    }
    return null;
  }

  PageShapeLayoutSnapshot? _setPluginCommentatorVisibility(
    String commentator,
    bool visible,
  ) {
    final state = context.read<TextBookBloc>().state;
    if (_isLoadingConfig || state is! TextBookLoaded) return null;
    final column = _columnForCommentator(commentator, state);
    if (column == null) return _pluginLayout();

    setState(() {
      if (visible == (_columnVisibility[column] == true)) {
        _pluginVisibilityOverrides.remove(commentator);
      } else {
        _pluginVisibilityOverrides[commentator] = visible;
      }
    });
    return _pluginLayout();
  }

  void _attachPluginController() {
    widget.tab?.pageShapePluginController.attach(
      readLayout: _pluginLayout,
      setVisibility: _setPluginCommentatorVisibility,
    );
  }

  bool _isRightPaneMultipleMode() {
    return isPageShapeMultipleCommentatorsMode(_rightCommentator);
  }

  List<String> _rightPaneSelectableCommentators(TextBookLoaded state) {
    final excludedCommentators = {
      ?_leftCommentator,
      ?_bottomCommentator,
      ?_bottomRightCommentator,
    };

    return _availableCommentators(state)
        .where((commentator) => !excludedCommentators.contains(commentator))
        .toList();
  }

  List<CommentatorGroup> _rightPaneCommentatorGroups(TextBookLoaded state) {
    final selectableCommentators = _rightPaneSelectableCommentators(
      state,
    ).toSet();

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
    await _saveCommentatorConfiguration(
      state,
      right: encodePageShapeCommentatorsSelection(
        commentators,
        forceMultipleMode: true,
      ),
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
        commentedBookTitle: state.book.title,
      );
      if (resolvedSingle == null) {
        return _buildEmptyColumnContent(
          columnName: 'right',
          onSelectCommentator: () => _showColumnAndOpenSettings('right'),
          onHideColumn: () => _hideColumn('right'),
        );
      }
      if (!isPageShapeRemainingCommentatorsValue(resolvedSingle) &&
          !isPageShapeMultiCommentatorsValue(resolvedSingle) &&
          resolvedSingle != pageShapeMultipleCommentatorsModeValue) {
        return _CommentaryPane(
          commentatorName: resolvedSingle,
          openBookCallback: widget.openBookCallback,
          workspaceId: _activeWorkspaceId,
          selectionSyncController: _selectionSyncController,
          onLoadFailed: () => _hideColumn(
            'right',
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
      hiddenCommentators: _hiddenRightPaneCommentators(state),
      commentatorGroupsOverride: _rightPaneCommentatorGroups(state),
      bookTitleOverride: state.book.title,
      personalNotesLoader: loadStoredPersonalNotes,
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

  /// שמירת המפרשים והטורים המוסתרים ליעד שממנו נטענו: שולחן העבודה, הספר
  /// או הקטגוריה. מחזיר את היעד שנבחר.
  Future<({String? workspaceId, String? category})>
  _saveCommentatorConfiguration(TextBookLoaded state, {String? right}) async {
    // כששולחן העבודה מחזיק בחירה משלו לספר, שינוי חי חייב להיכתב אליה -
    // אחרת הוא נשמר לספר/לקטגוריה ונדרס מיד בטעינה הבאה.
    final workspaceToSave = PageShapeSettingsManager.commentatorWorkspaceTarget(
      _activeWorkspaceId,
      state.book.title,
    );

    final hasActualBookConfig =
        PageShapeSettingsManager.loadConfiguration(state.book.title) != null;

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

    await PageShapeSettingsManager.saveConfiguration(
      state.book.title,
      {
        'left': _leftCommentator,
        'right': right ?? _rightCommentator,
        'bottom': _bottomCommentator,
        'bottomRight': _bottomRightCommentator,
      },
      saveToCategory: categoryToSave,
      saveToWorkspaceId: workspaceToSave,
      columnVisibility: Map.of(_columnVisibility),
    );
    return (workspaceId: workspaceToSave, category: categoryToSave);
  }

  void _showColumnAndOpenSettings(String column) {
    setState(() {
      _columnVisibility[column] = true;
    });
    final state = context.read<TextBookBloc>().state;
    if (state is TextBookLoaded) {
      _saveCommentatorConfiguration(state);
    }
    _openSettingsPane();
  }

  /// הסתרת טור. [persist] שומר את ההסתרה יחד עם בחירת המפרשים.
  Future<void> _hideColumn(
    String column, {
    bool showSnack = true,
    bool persist = true,
  }) async {
    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded) return;

    setState(() {
      _columnVisibility[column] = false;
    });
    _refreshLinksForCurrentConfiguration(
      'page-shape column visibility changed',
    );
    if (!persist) return;

    final target = await _saveCommentatorConfiguration(state);
    if (!showSnack) return;
    UiSnack.show(
      target.workspaceId != null
          ? TextBookMessages.columnHiddenInWorkspace
          : target.category != null
          ? TextBookMessages.columnHiddenInCategory(target.category!)
          : TextBookMessages.columnHiddenInBook,
    );
  }

  /// בניית widget למצב ריק של טור
  Widget _buildEmptyColumnContent({
    required String columnName,
    required VoidCallback onSelectCommentator,
    required VoidCallback onHideColumn,
  }) {
    return Container(
      color: Theme.of(
        context,
      ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ActionButton.recommended(
              onPressed: onSelectCommentator,
              icon: OtzariaIcons.book_24_regular,
              text: 'בחר מפרש',
            ),
            const SizedBox(height: 12),
            ActionButton.neutral(
              onPressed: onHideColumn,
              icon: FluentIcons.eye_off_24_regular,
              text: 'הסתר טור זה',
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _navigateToLine(
    TextBookLoaded state,
    int lineNumber,
    PersonalNote? note,
  ) async {
    if (lineNumber < 1 || state.content.isEmpty) {
      return;
    }

    final targetIndex = (lineNumber - 1)
        .clamp(0, state.content.length - 1)
        .toInt();

    await widget.tab?.lines.scrollToLine(
      targetIndex,
      intraLineFraction: noteAnchorFractionInLine(
        state.content[targetIndex],
        note,
      ),
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
    final validIndex = index.clamp(0, kSidebarTabCount - 1);
    // פתיחה מחדש של לשונית ההערות חייבת לעבור גם כשהיא כבר פתוחה, כדי לאפס
    // יעד הערה של מפרש ולחזור להערות הספר הראשי.
    final shouldResetNotesTarget =
        validIndex == kNotesTabIndex && _notesBookIdOverride != null;
    if (_isLeftSidebarOpen &&
        _leftSidebarTabIndex == validIndex &&
        !shouldResetNotesTarget) {
      return;
    }

    if (!_isLeftSidebarOpen) _reanchorMainText();
    setState(() {
      _isLeftSidebarOpen = true;
      _leftSidebarTabIndex = validIndex;
      if (validIndex == kNotesTabIndex) {
        _notesBookIdOverride = null;
        _notesCategoryIdOverride = null;
        _notesFocusLineNumber = null;
      }
    });
  }

  void _openCommentaryPersonalNote(
    String bookId,
    int? categoryId,
    int lineNumber,
  ) {
    if (!_isLeftSidebarOpen) _reanchorMainText();
    setState(() {
      _notesBookIdOverride = bookId;
      _notesCategoryIdOverride = categoryId;
      _notesFocusLineNumber = lineNumber;
      _isLeftSidebarOpen = true;
      _leftSidebarTabIndex = kNotesTabIndex;
    });
  }

  void _focusMainBookNotes() {
    if (_notesBookIdOverride == null ||
        !_isLeftSidebarOpen ||
        _leftSidebarTabIndex != kNotesTabIndex) {
      return;
    }
    setState(() {
      _notesBookIdOverride = null;
      _notesCategoryIdOverride = null;
      _notesFocusLineNumber = null;
    });
  }

  void _toggleLeftSidebar() {
    _reanchorMainText();
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

  /// טוגל חלונית הצד מקיצור Ctrl+Shift+C:
  /// סגורה או פתוחה על לשונית אחרת → פתח על "מפרשים".
  /// פתוחה על "מפרשים" → סגור.
  void _onToggleCommentatorsPaneRequest() {
    if (!mounted) return;
    _reanchorMainText();
    setState(() {
      if (_isLeftSidebarOpen && _leftSidebarTabIndex == kCommentaryTabIndex) {
        _isLeftSidebarOpen = false;
      } else {
        _isLeftSidebarOpen = true;
        _leftSidebarTabIndex = kCommentaryTabIndex;
      }
    });
  }

  /// פתיחת חלונית הצד על לשונית המפרשים (מתפריט ההקשר של גוף הספר).
  /// מקפלת מסך בחירה שנשאר פרוש מפעם קודמת — תוכן החלונית נשמר ב-tree.
  void _openCommentatorsPane() {
    _openLeftSidebarTab(kCommentaryTabIndex);
    _notifyCommentatorsFilter(_closeCommentatorsFilterNotifier);
  }

  /// פתיחת לשונית המפרשים עם חלונית בחירת המפרשים פרושה.
  void _openCommentatorsPaneWithFilter() {
    _openLeftSidebarTab(kCommentaryTabIndex);
    _notifyCommentatorsFilter(_openCommentatorsFilterNotifier);
  }

  /// המעבר ללשונית המפרשים מרכיב מחדש את CommentaryListBase תוך כדי אנימציית
  /// הלשוניות; יריה לפני שהמאזין שלו נרשם נבלעת בשקט, ולכן ממתינים לסופה.
  void _notifyCommentatorsFilter(ValueNotifier<int> notifier) {
    Future.delayed(kTabScrollDuration, () {
      if (!mounted) return;
      notifier.value++;
    });
  }

  /// בקשה מכפתור גלגל השיניים בסרגל העליון — טוגל פאנל ההגדרות.
  void _handleOpenSettingsRequest() {
    if (!mounted) return;
    setState(() {
      _isSettingsPaneOpen = !_isSettingsPaneOpen;
      if (_isSettingsPaneOpen) _settingsPaneKey++;
    });
  }

  /// פתיחת פאנל ההגדרות (למשל מכפתור "בחר מפרש" בטור ריק).
  void _openSettingsPane() {
    if (!mounted || _isSettingsPaneOpen) return;
    setState(() {
      _isSettingsPaneOpen = true;
      _settingsPaneKey++;
    });
  }

  void _closeSettingsPane() {
    if (!_isSettingsPaneOpen) return;
    setState(() {
      _isSettingsPaneOpen = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _hiddenSelectionSubscription = const HiddenLibraryStore().visibilityChanges
        .listen((_) => unawaited(_loadConfiguration()));
    widget.sidebarTabNotifier?.addListener(_handleSidebarTabRequest);
    widget.openSettingsNotifier?.addListener(_handleOpenSettingsRequest);
    widget.tab?.toggleCommentatorsPaneNotifier.addListener(
      _onToggleCommentatorsPaneRequest,
    );
    _attachPluginController();
  }

  @override
  void didUpdateWidget(covariant PageShapeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sidebarTabNotifier != widget.sidebarTabNotifier) {
      oldWidget.sidebarTabNotifier?.removeListener(_handleSidebarTabRequest);
      widget.sidebarTabNotifier?.addListener(_handleSidebarTabRequest);
    }
    if (oldWidget.openSettingsNotifier != widget.openSettingsNotifier) {
      oldWidget.openSettingsNotifier?.removeListener(
        _handleOpenSettingsRequest,
      );
      widget.openSettingsNotifier?.addListener(_handleOpenSettingsRequest);
    }
    if (oldWidget.tab != widget.tab) {
      oldWidget.tab?.toggleCommentatorsPaneNotifier.removeListener(
        _onToggleCommentatorsPaneRequest,
      );
      widget.tab?.toggleCommentatorsPaneNotifier.addListener(
        _onToggleCommentatorsPaneRequest,
      );
      oldWidget.tab?.pageShapePluginController.detach();
      _attachPluginController();
    }
  }

  @override
  void dispose() {
    unawaited(_hiddenSelectionSubscription?.cancel() ?? Future.value());
    widget.sidebarTabNotifier?.removeListener(_handleSidebarTabRequest);
    widget.openSettingsNotifier?.removeListener(_handleOpenSettingsRequest);
    widget.tab?.toggleCommentatorsPaneNotifier.removeListener(
      _onToggleCommentatorsPaneRequest,
    );
    widget.tab?.pageShapePluginController.detach();
    _selectionSyncController.dispose();
    _openCommentatorsFilterNotifier.dispose();
    _closeCommentatorsFilterNotifier.dispose();
    super.dispose();
  }

  /// איפוס בחירת המפרשים — טעינה מחדש של ברירות המחדל וריענון החלונית.
  Future<void> _handleSettingsReset() async {
    await _loadConfiguration();
    if (mounted) setState(() => _settingsPaneKey++);
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<TextBookBloc, TextBookState>(
          listenWhen: (previous, current) {
            if (previous is TextBookLoaded && current is TextBookLoaded) {
              // heCategories מועשר ברקע אחרי הטעינה; בלעדיו הגדרות הקטגוריה
              // לא נמצאות וברירות המחדל נשארות על המסך (issue #770).
              return !listEquals(
                    previous.availableCommentators,
                    current.availableCommentators,
                  ) ||
                  previous.book.heCategories != current.book.heCategories;
            }
            return previous is! TextBookLoaded && current is TextBookLoaded;
          },
          listener: (context, state) {
            if (state is TextBookLoaded) {
              _loadConfiguration();
            }
          },
        ),
        BlocListener<TextBookBloc, TextBookState>(
          // שינוי גודל גופן משנה את גובה כל הפריטים; בלי עיגון-מחדש ההיסט
          // בפיקסלים נוחת על מקום אחר (issue #915).
          listenWhen: (previous, current) =>
              previous is TextBookLoaded &&
              current is TextBookLoaded &&
              previous.fontSize != current.fontSize,
          listener: (context, state) => _reanchorMainText(),
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
            _openLeftSidebarTab(kNotesTabIndex);
          },
        ),
      ],
      child: _isLoadingConfig
          ? const Scaffold(body: LoadingIndicator())
          : TextBookStateBuilder(
              // הטקסט הראשי מאזין לבחירה בעצמו; בלי זה כל בחירה בונה את כל הטורים.
              buildWhen: shouldRebuildIgnoringSelection,
              loadingWidget: const Scaffold(body: LoadingIndicator()),
              builder: (context, state) {
                // נראות כל פאנל תחתון נשלטת בנפרד; האזור התחתון מוצג רק אם
                // לפחות אחד מהם גלוי ובעל מפרש.
                final showBottom =
                    _isCommentatorVisible('bottom', _bottomCommentator) &&
                    _bottomCommentator != null;
                final showBottomRight =
                    _isCommentatorVisible(
                      'bottomRight',
                      _bottomRightCommentator,
                    ) &&
                    _bottomRightCommentator != null;
                return Scaffold(
                  body: Stack(
                    children: [
                      AdaptiveSidePane(
                        isOpen: _isLeftSidebarOpen,
                        alignment: AlignmentDirectional.centerStart,
                        paneWidth:
                            _leftSidebarWidth ??
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
                        paneContent: TabbedCommentaryPanel(
                          openBookCallback: widget.openBookCallback,
                          fontSize: state.fontSize,
                          showSearch: true,
                          selectionSyncController: _selectionSyncController,
                          openCommentatorsFilterNotifier:
                              _openCommentatorsFilterNotifier,
                          closeCommentatorsFilterNotifier:
                              _closeCommentatorsFilterNotifier,
                          tab: widget.tab,
                          notesBookIdOverride: _notesBookIdOverride,
                          notesCategoryIdOverride: _notesCategoryIdOverride,
                          notesFocusLineNumber: _notesFocusLineNumber,
                          notesFooter: CommentaryNotesSection(
                            bookIds: _displayedCommentators(state),
                            onOpenNote: (bookId, lineNumber) =>
                                _openCommentaryPersonalNote(
                                  bookId,
                                  null,
                                  lineNumber,
                                ),
                          ),
                          onNavigateToLine: (lineNumber, {note}) =>
                              _navigateToLine(state, lineNumber, note),
                          onClosePane: _toggleLeftSidebar,
                          isPaneOpen: _isLeftSidebarOpen,
                          initialTabIndex: _leftSidebarTabIndex,
                          onTabChanged: (index) {
                            setState(() {
                              _leftSidebarTabIndex = index;
                            });
                          },
                        ),
                        mainContent: Stack(
                          children: [
                            // הגדרת "רוחב הטקסט" מגבילה כאן את כל תוכן הדף
                            // (טקסט + מפרשים) עם שוליים בצדדים.
                            LayoutBuilder(
                              builder: (context, pageConstraints) {
                                final pageMaxWidth = _applyTextMaxWidth
                                    ? textColumnMaxWidthOf(
                                        context,
                                        setting: context
                                            .select<SettingsBloc, double>(
                                              (bloc) => bloc.state.textMaxWidth,
                                            ),
                                        availableWidth:
                                            pageConstraints.maxWidth,
                                      )
                                    : 0.0;
                                final constrainPage =
                                    pageMaxWidth > 0 &&
                                    pageMaxWidth < pageConstraints.maxWidth;
                                final pageWidth = constrainPage
                                    ? pageMaxWidth
                                    : pageConstraints.maxWidth;
                                final freeWidth = math.max(
                                  1.0,
                                  pageWidth -
                                      2 * _kCommentaryLabelAndSpacingWidth,
                                );
                                final pageHeight = math.max(
                                  1.0,
                                  pageConstraints.maxHeight,
                                );
                                final sideMax = math.max(
                                  kPageShapeSideMinWidth,
                                  freeWidth * kPageShapeSideMaxFraction,
                                );
                                final hasLeftPane = _isCommentatorVisible(
                                  'left',
                                  _leftCommentator,
                                );
                                final hasRightPane = _shouldShowRightPane(
                                  state,
                                );
                                final sideWidths = resolvePageShapeSideWidths(
                                  freeWidth: freeWidth,
                                  leftFraction:
                                      _leftWidth ?? _kCommentaryPaneWidthFactor,
                                  rightFraction:
                                      _rightWidth ??
                                      _kCommentaryPaneWidthFactor,
                                  hasLeft: hasLeftPane,
                                  hasRight: hasRightPane,
                                );
                                final leftWidth = sideWidths.left;
                                final rightWidth = sideWidths.right;
                                // גרירה מקבעת טור שני גלוי לרוחבו המוצג וחוסמת את
                                // הנגרר, כדי שההקטנה המשותפת לא תזיז את הידית.
                                final sidesMax =
                                    freeWidth * (1 - kPageShapeMainMinFraction);
                                void dragSide({
                                  required bool isLeft,
                                  required double width,
                                }) {
                                  final other = isLeft ? rightWidth : leftWidth;
                                  final hasOther = isLeft
                                      ? hasRightPane
                                      : hasLeftPane;
                                  final max = math.min(
                                    sideMax,
                                    sidesMax - (hasOther ? other : 0),
                                  );
                                  final fraction = pageShapeFraction(
                                    width.clamp(
                                      kPageShapeSideMinWidth,
                                      math.max(kPageShapeSideMinWidth, max),
                                    ),
                                    freeWidth,
                                  );
                                  final otherFraction = pageShapeFraction(
                                    other,
                                    freeWidth,
                                  );
                                  setState(() {
                                    _leftWidth = isLeft
                                        ? fraction
                                        : hasOther
                                        ? otherFraction
                                        : _leftWidth;
                                    _rightWidth = isLeft
                                        ? hasOther
                                              ? otherFraction
                                              : _rightWidth
                                        : fraction;
                                  });
                                }

                                final bottomLeftMax = math.max(
                                  100.0,
                                  freeWidth * 0.8,
                                );
                                final bottomLeftWidth = math.min(
                                  (_bottomLeftWidth ??
                                          _kBottomLeftPaneWidthFactor) *
                                      freeWidth,
                                  bottomLeftMax,
                                );
                                final bottomHeight =
                                    math.min(
                                      _bottomHeight ?? _kBottomPaneHeightFactor,
                                      0.5,
                                    ) *
                                    pageHeight;
                                final page = Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        children: [
                                          Expanded(
                                            child: Row(
                                              children: [
                                                if (_isCommentatorVisible(
                                                  'left',
                                                  _leftCommentator,
                                                )) ...[
                                                  if (_leftCommentator !=
                                                      null) ...[
                                                    SizedBox(
                                                      width: 20,
                                                      child: Center(
                                                        child: RotatedBox(
                                                          quarterTurns: 1,
                                                          child: Text(
                                                            _leftCommentator!,
                                                            style:
                                                                const TextStyle(
                                                                  fontSize: 14,
                                                                ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 4),
                                                    SizedBox(
                                                      width: leftWidth,
                                                      child: _CommentaryPane(
                                                        commentatorName:
                                                            _leftCommentator!,
                                                        openBookCallback: widget
                                                            .openBookCallback,
                                                        workspaceId:
                                                            _activeWorkspaceId,
                                                        selectionSyncController:
                                                            _selectionSyncController,
                                                        onOpenPersonalNote:
                                                            _openCommentaryPersonalNote,
                                                        onLoadFailed: () =>
                                                            _hideColumn(
                                                              'left',
                                                              showSnack: false,
                                                              persist: false,
                                                            ),
                                                      ),
                                                    ),
                                                  ] else ...[
                                                    SizedBox(
                                                      width: leftWidth,
                                                      child: _buildEmptyColumnContent(
                                                        columnName: 'left',
                                                        onSelectCommentator: () =>
                                                            _showColumnAndOpenSettings(
                                                              'left',
                                                            ),
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
                                                            onDragDelta:
                                                                (
                                                                  delta,
                                                                ) => dragSide(
                                                                  isLeft: true,
                                                                  width:
                                                                      leftWidth -
                                                                      delta,
                                                                ),
                                                            onDragEnd:
                                                                _saveSizes,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                                Expanded(
                                                  child: Listener(
                                                    onPointerDown: (_) =>
                                                        _focusMainBookNotes(),
                                                    child: SimpleTextViewer(
                                                      key: _mainTextViewerKey,
                                                      content: state.content,
                                                      fontSize: state.fontSize,
                                                      selectionSyncController:
                                                          _selectionSyncController,
                                                      openBookCallback: widget
                                                          .openBookCallback,
                                                      lines: widget.tab?.lines,
                                                      isMainText: true,
                                                      isPersonalNotesTabActive:
                                                          _isLeftSidebarOpen &&
                                                          _leftSidebarTabIndex ==
                                                              kNotesTabIndex,
                                                      isCommentatorsTabActive:
                                                          _isLeftSidebarOpen &&
                                                          _leftSidebarTabIndex ==
                                                              kCommentaryTabIndex,
                                                      isLinksTabActive:
                                                          _isLeftSidebarOpen &&
                                                          _leftSidebarTabIndex ==
                                                              kLinksTabIndex,
                                                      onOpenCommentatorsPane:
                                                          _openCommentatorsPane,
                                                      onOpenCommentatorsPaneWithFilter:
                                                          _openCommentatorsPaneWithFilter,
                                                      tab: widget.tab,
                                                      labelForIndex:
                                                          state
                                                              .tableOfContents
                                                              .isEmpty
                                                          ? null
                                                          : (index) =>
                                                                readingScrollbarLabel(
                                                                  state,
                                                                  index,
                                                                ),
                                                      onOpenSidebarTab:
                                                          _openLeftSidebarTab,
                                                      onOpenSearch:
                                                          widget.onOpenSearch,
                                                    ),
                                                  ),
                                                ),
                                                if (_shouldShowRightPane(
                                                  state,
                                                )) ...[
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
                                                            onDragDelta:
                                                                (
                                                                  delta,
                                                                ) => dragSide(
                                                                  isLeft: false,
                                                                  width:
                                                                      rightWidth +
                                                                      delta,
                                                                ),
                                                            onDragEnd:
                                                                _saveSizes,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  if (_rightPaneSelectableCommentators(
                                                    state,
                                                  ).isNotEmpty) ...[
                                                    SizedBox(
                                                      width: rightWidth,
                                                      child: _buildRightPane(
                                                        state,
                                                      ),
                                                    ),
                                                    if (_rightPaneLabel(
                                                          state,
                                                        ) !=
                                                        null) ...[
                                                      const SizedBox(width: 4),
                                                      SizedBox(
                                                        width: 20,
                                                        child: Center(
                                                          child: RotatedBox(
                                                            quarterTurns: 3,
                                                            child: Text(
                                                              _rightPaneLabel(
                                                                state,
                                                              )!,
                                                              style:
                                                                  const TextStyle(
                                                                    fontSize:
                                                                        14,
                                                                  ),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ] else ...[
                                                    SizedBox(
                                                      width: rightWidth,
                                                      child: _buildEmptyColumnContent(
                                                        columnName: 'right',
                                                        onSelectCommentator: () =>
                                                            _showColumnAndOpenSettings(
                                                              'right',
                                                            ),
                                                        onHideColumn: () =>
                                                            _hideColumn(
                                                              'right',
                                                            ),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ],
                                            ),
                                          ),
                                          if (showBottom ||
                                              showBottomRight) ...[
                                            _HorizontalDragHandle(
                                              leftWidth: leftWidth,
                                              rightWidth: rightWidth,
                                              leftCommentator: _leftCommentator,
                                              rightCommentator: _rightPaneLabel(
                                                state,
                                              ),
                                              onPanUpdate: (details) {
                                                setState(() {
                                                  _bottomHeight =
                                                      pageShapeFraction(
                                                        (bottomHeight -
                                                                details
                                                                    .delta
                                                                    .dy)
                                                            .clamp(
                                                              80.0,
                                                              math.max(
                                                                80.0,
                                                                pageHeight *
                                                                    0.5,
                                                              ),
                                                            ),
                                                        pageHeight,
                                                      );
                                                });
                                              },
                                              onPanEnd: _saveSizes,
                                            ),
                                            SizedBox(
                                              height: bottomHeight,
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
                                                                      quarterTurns:
                                                                          1,
                                                                      child: Text(
                                                                        _bottomCommentator!,
                                                                        style: const TextStyle(
                                                                          fontSize:
                                                                              14,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ),
                                                                const SizedBox(
                                                                  width: 4,
                                                                ),
                                                                SizedBox(
                                                                  width:
                                                                      bottomLeftWidth,
                                                                  child: _CommentaryPane(
                                                                    commentatorName:
                                                                        _bottomCommentator!,
                                                                    openBookCallback:
                                                                        widget
                                                                            .openBookCallback,
                                                                    workspaceId:
                                                                        _activeWorkspaceId,
                                                                    isBottom:
                                                                        true,
                                                                    selectionSyncController:
                                                                        _selectionSyncController,
                                                                    onOpenPersonalNote:
                                                                        _openCommentaryPersonalNote,
                                                                    onLoadFailed: () => _hideColumn(
                                                                      'bottom',
                                                                      showSnack:
                                                                          false,
                                                                      persist:
                                                                          false,
                                                                    ),
                                                                  ),
                                                                ),
                                                                SizedBox(
                                                                  width: 8,
                                                                  child: Stack(
                                                                    children: [
                                                                      Positioned(
                                                                        top: 0,
                                                                        bottom:
                                                                            0,
                                                                        child: ResizableDragHandle(
                                                                          isVertical:
                                                                              true,
                                                                          showDivider:
                                                                              false,
                                                                          onDragDelta:
                                                                              (
                                                                                delta,
                                                                              ) {
                                                                                setState(() {
                                                                                  _bottomLeftWidth = pageShapeFraction(
                                                                                    (bottomLeftWidth -
                                                                                            delta)
                                                                                        .clamp(
                                                                                          100.0,
                                                                                          bottomLeftMax,
                                                                                        ),
                                                                                    freeWidth,
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
                                                                  openBookCallback:
                                                                      widget
                                                                          .openBookCallback,
                                                                  workspaceId:
                                                                      _activeWorkspaceId,
                                                                  isBottom:
                                                                      true,
                                                                  selectionSyncController:
                                                                      _selectionSyncController,
                                                                  onOpenPersonalNote:
                                                                      _openCommentaryPersonalNote,
                                                                  onLoadFailed: () =>
                                                                      _hideColumn(
                                                                        'bottomRight',
                                                                        showSnack:
                                                                            false,
                                                                        persist:
                                                                            false,
                                                                      ),
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                width: 4,
                                                              ),
                                                              SizedBox(
                                                                width: 20,
                                                                child: Center(
                                                                  child: RotatedBox(
                                                                    quarterTurns:
                                                                        3,
                                                                    child: Text(
                                                                      _bottomRightCommentator!,
                                                                      style: const TextStyle(
                                                                        fontSize:
                                                                            14,
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
                                                                    quarterTurns:
                                                                        1,
                                                                    child: Text(
                                                                      _bottomCommentator!,
                                                                      style: const TextStyle(
                                                                        fontSize:
                                                                            14,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                width: 4,
                                                              ),
                                                              Expanded(
                                                                child: _CommentaryPane(
                                                                  commentatorName:
                                                                      _bottomCommentator!,
                                                                  openBookCallback:
                                                                      widget
                                                                          .openBookCallback,
                                                                  workspaceId:
                                                                      _activeWorkspaceId,
                                                                  isBottom:
                                                                      true,
                                                                  selectionSyncController:
                                                                      _selectionSyncController,
                                                                  onOpenPersonalNote:
                                                                      _openCommentaryPersonalNote,
                                                                  onLoadFailed: () =>
                                                                      _hideColumn(
                                                                        'bottom',
                                                                        showSnack:
                                                                            false,
                                                                        persist:
                                                                            false,
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
                                );
                                if (!constrainPage) return page;
                                return Center(
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: pageMaxWidth,
                                    ),
                                    child: page,
                                  ),
                                );
                              },
                            ),
                            // כפתור צף לפתיחת הסיידבר
                            if (!_isLeftSidebarOpen)
                              Positioned(
                                left: 0,
                                top: MediaQuery.of(context).size.height * 0.10,
                                child: PanelOpenHandle(
                                  onTap: _openCommentatorsPane,
                                ),
                              ),
                          ],
                        ),
                      ),
                      // פאנל הגדרות צורת הדף — overlay צף בצד הימני הויזואלי
                      ContextOverlayPanel(
                        isOpen: _isSettingsPaneOpen,
                        onClose: _closeSettingsPane,
                        alignment: AlignmentDirectional.centerStart,
                        width: 400,
                        title: 'הגדרות צורת הדף',
                        scrollable: true,
                        child: PageShapeSettingsPanel(
                          key: ValueKey(_settingsPaneKey),
                          availableCommentators: _availableCommentators(state),
                          bookTitle: state.book.title,
                          heCategories: state.book.heCategories,
                          bookSource: state.book.source,
                          currentLeft: _leftCommentator,
                          currentRight: _rightCommentator,
                          currentBottom: _bottomCommentator,
                          currentBottomRight: _bottomRightCommentator,
                          currentWorkspaceId: _activeWorkspaceId,
                          onSettingsChanged: _loadConfiguration,
                          onReset: _handleSettingsReset,
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
  final String? workspaceId;
  final bool isBottom; // האם זה מפרש תחתון (גופן ייעודי מדיאלוג ההגדרות)
  final VoidCallback? onLoadFailed;
  final SelectionSyncController? selectionSyncController;
  final void Function(String bookId, int? categoryId, int lineNumber)?
  onOpenPersonalNote;

  const _CommentaryPane({
    required this.commentatorName,
    required this.openBookCallback,
    this.workspaceId,
    this.isBottom = false,
    this.onLoadFailed,
    this.selectionSyncController,
    this.onOpenPersonalNote,
  });

  @override
  State<_CommentaryPane> createState() => _CommentaryPaneState();
}

class _LoadedCommentaryData {
  final TextBook book;
  final List<String> content;

  const _LoadedCommentaryData({required this.book, required this.content});
}

class _CommentaryPaneState extends State<_CommentaryPane> {
  static const int _windowLookBehindLines = 120;
  static const int _windowLookAheadLines = 260;
  static const int _windowReloadThresholdLines = 60;

  // המטמון מחזיק ספרי מפרשים שלמים — בלי חסם LRU כל מפרש שהוצג אי-פעם
  // בצורת הדף היה נשאר ב-RAM עד סגירת האפליקציה. LinkedHashMap במפורש:
  // פינוי ה-LRU מסתמך על סדר ההכנסה.
  static final LinkedHashMap<String, Future<_LoadedCommentaryData?>>
  _fullCommentaryCache =
      LinkedHashMap<String, Future<_LoadedCommentaryData?>>();
  static const int _maxFullCommentaryCacheEntries = 8;

  /// שליפה/יצירה עם התנהגות LRU: גישה מקדמת את הרשומה לסוף, וחריגה מהחסם
  /// מפנה את הישנה ביותר. עתיד שפונה מהמטמון נשאר חי אצל חלונית שכבר
  /// מחזיקה בו — רק הכניסה במטמון נמחקת.
  static Future<_LoadedCommentaryData?> _getOrLoadFullCommentary(
    String cacheKey,
    Future<_LoadedCommentaryData?> Function() load,
  ) {
    final cached = _fullCommentaryCache.remove(cacheKey);
    final future = cached ?? load();
    _fullCommentaryCache[cacheKey] = future;
    while (_fullCommentaryCache.length > _maxFullCommentaryCacheEntries) {
      _fullCommentaryCache.remove(_fullCommentaryCache.keys.first);
    }
    return future;
  }

  List<String>? _content;
  TextBook? _reportBook;

  /// ה-id של ספר המפרש, כשנמצא. הספר שנטען נשאר בלעדיו, כדי לא לשנות את
  /// הטעינה; ספר הדיווח נושא אותו, לקישור ישיר ולסימונים בעמודה.
  int? _reportBookId;

  TextBook _withReportId(TextBook book) =>
      book.id != null || _reportBookId == null
      ? book
      : book.copyWith(id: _reportBookId);

  // טעינת-חלונות לספרי DB: _content באורך הספר המלא עם placeholders ריקים,
  // ורק חלונות סביב יעד הסנכרון/הגלילה נטענים בפועל.
  bool _useWindowedLoading = false;
  TextBook? _rangeBook;
  List<({int startLine, int endLine})> _loadedRanges = const [];
  bool _isLoadingRange = false;
  bool _pendingRangeReload = false;
  // תוכן העניינים של ספר המפרש — לתווית היעד בריחוף על סרגל הגלילה. null
  // עד שנטען; אינדקסי התוכן של המפרש מתיישרים עם מספרי השורות שלו, ולכן
  // המיפוי ישיר (refFromTocList) בלי המרת סגמנטים.
  List<TocEntry>? _commentaryToc;
  bool _isLoading = true;
  final ItemScrollController _scrollController = ItemScrollController();
  final ItemPositionsListener _positionsListener =
      ItemPositionsListener.create();
  final ScrollOffsetController _scrollOffsetController =
      ScrollOffsetController();
  List<Link> _relevantLinks = [];

  // עוגני מפרשי-המפרש (שער הציון וכד') בתוך טקסט המפרש — נטענים פר-חלון
  // שורות רק לספרי DB שיש להם מפרשים משלהם. null עד שהסיכום נבדק.
  Set<String>? _commentaryAnchorTargets;
  Map<int, List<Link>> _anchorLinksByLine = const {};
  // הערות ספר המפרש: עוגניו נמדדים על השורה המלאה, עם גופי ההערות.
  BookNotes _anchorBookNotes = BookNotes.empty;
  List<({int startLine, int endLine})> _anchorLoadedRanges = const [];
  int? _lastSyncedIndex; // האינדקס האחרון שסונכרן
  int? _lastSyncedMainIndex; // השורה הנבחרת שממנה נגזר הסנכרון האחרון
  int _initialSyncAttempts = 0; // ניסיונות סנכרון ראשוני עד שה-controller מחובר
  List<Link>? _lastLinks; // לדידוב: מסנן מחדש רק כשהקישורים השתנו
  StreamSubscription<TextBookState>? _blocSubscription;
  Set<int> _highlightedIndices = {}; // אינדקסים להדגשה
  bool _highlightEnabled = false;

  @override
  void initState() {
    super.initState();
    _positionsListener.itemPositions.addListener(_onPanePositionsChanged);
    // דוחה את הטעינה כדי לוודא שכל ה-providers מוכנים וה-bloc זמין
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadCommentary();
        _setupBlocListener();
      }
    });
  }

  /// גלילה בתוך חלונית המפרש — טוען חלון חדש כשמתקרבים לקצה הטעון.
  void _onPanePositionsChanged() {
    if (!_useWindowedLoading || _content == null || !mounted) {
      return;
    }
    final positions = _positionsListener.itemPositions.value;
    if (positions.isEmpty) {
      return;
    }
    var first = positions.first.index;
    var last = first;
    for (final position in positions) {
      if (position.index < first) first = position.index;
      if (position.index > last) last = position.index;
    }
    unawaited(_ensureWindowLoaded(first, last));
  }

  /// האם ה-viewport [first]..[last] בתוך טווח טעון עם שולי ביטחון —
  /// בקצות הספר אין מה לטעון מעבר, ולכן השוליים שם מוותרים.
  bool _isWindowLoaded(int first, int last) {
    final content = _content;
    if (content == null) {
      return false;
    }
    final lastBookLine = content.length - 1;
    for (final range in _loadedRanges) {
      final startOk = range.startLine == 0
          ? first >= range.startLine
          : first >= range.startLine + _windowReloadThresholdLines;
      final endOk = range.endLine >= lastBookLine
          ? last <= range.endLine
          : last <= range.endLine - _windowReloadThresholdLines;
      if (startOk && endOk) {
        return true;
      }
    }
    return false;
  }

  /// מוודא שחלון סביב [first]..[last] טעון; טוען את החסר מה-DB.
  Future<void> _ensureWindowLoaded(int first, int last) async {
    if (_isWindowLoaded(first, last)) {
      return;
    }

    if (_isLoadingRange) {
      _pendingRangeReload = true;
      return;
    }
    _isLoadingRange = true;
    try {
      final book = _rangeBook;
      final content = _content;
      if (book == null || content == null) {
        return;
      }
      final range = await SqliteDataProvider.instance.getBookTextRangeFromDb(
        book.title,
        startLine: first - _windowLookBehindLines,
        endLine: last + _windowLookAheadLines,
        categoryId: book.categoryId,
        fileType: book.fileType,
      );
      if (!mounted ||
          range == null ||
          !_useWindowedLoading ||
          !identical(content, _content) ||
          range.totalLines != content.length) {
        return;
      }

      _loadedRanges = TextBookBloc.mergeLoadedContentRanges(
        _loadedRanges,
        startLine: range.startLine,
        endLine: range.endLine,
      );
      unawaited(_ensureAnchorLinksLoaded(range.startLine, range.endLine, book));

      final lines = range.text.split('\n');
      var changed = false;
      for (var offset = 0; offset < lines.length; offset++) {
        final target = range.startLine + offset;
        if (target < content.length && content[target] != lines[offset]) {
          content[target] = lines[offset];
          changed = true;
        }
      }
      if (changed) {
        setState(() {});
      }
    } finally {
      _isLoadingRange = false;
      if (_pendingRangeReload && mounted) {
        _pendingRangeReload = false;
        _onPanePositionsChanged();
      }
    }
  }

  /// טוען חלון ראשוני סביב [targetIndex] ומפעיל מצב טעינת-חלונות.
  /// מחזיר false כשאין לספר טעינת-טווחים — הקורא נופל לטעינה מלאה.
  Future<bool> _loadInitialWindow(
    TextBook book,
    int targetIndex,
    String requestedCommentatorName,
  ) async {
    final range = await SqliteDataProvider.instance.getBookTextRangeFromDb(
      book.title,
      startLine: targetIndex - _windowLookBehindLines,
      endLine: targetIndex + _windowLookAheadLines,
      categoryId: book.categoryId,
      fileType: book.fileType,
    );
    if (!mounted || widget.commentatorName != requestedCommentatorName) {
      return true; // הבקשה התיישנה — אין טעם גם בטעינה מלאה
    }
    if (range == null || range.totalLines <= 0) {
      return false;
    }

    final lines = range.text.split('\n');
    final content = List<String>.filled(range.totalLines, '');
    for (var offset = 0; offset < lines.length; offset++) {
      final target = range.startLine + offset;
      if (target < content.length) {
        content[target] = lines[offset];
      }
    }

    _useWindowedLoading = true;
    _rangeBook = book;
    _loadedRanges = TextBookBloc.mergeLoadedContentRanges(
      const [],
      startLine: range.startLine,
      endLine: range.endLine,
    );
    setState(() {
      _reportBook = _withReportId(book);
      _content = content;
      _isLoading = false;
      _lastSyncedIndex = null;
      _lastSyncedMainIndex = null;
    });
    _scheduleInitialSync();
    return true;
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
    if (oldWidget.workspaceId != widget.workspaceId) {
      _updateHighlightSettings();
    }
  }

  @override
  void dispose() {
    _positionsListener.itemPositions.removeListener(_onPanePositionsChanged);
    _blocSubscription?.cancel();
    super.dispose();
  }

  /// עדכון הגדרות הדגשה
  void _updateHighlightSettings() {
    final state = context.read<TextBookBloc>().state;
    if (state is TextBookLoaded) {
      final newHighlightEnabled = PageShapeSettingsManager.getHighlightSetting(
        state.book.title,
        workspaceId: widget.workspaceId,
      );
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
          LinkTypes.isDependentTextLink(link.connectionType);
    }).toList();
  }

  String _commentaryCacheKey(TextBook book, {required bool preferDatabase}) {
    return '${book.title}|${book.categoryId}|${book.categoryPath ?? ''}|$preferDatabase';
  }

  /// בודק אם לספר המפרש יש מפרשים משלו (שער הציון על המשנה ברורה וכד'), ואם
  /// כן טוען את עוגניהם לטווחים שכבר בזיכרון. בלי יעדים כאלה — אין עוד שליפות.
  Future<void> _initCommentaryAnchors(TextBook book) async {
    final requested = widget.commentatorName;
    final categoryId = book.categoryId;
    if (categoryId == null) return;
    final provider = LibraryProviderManager.instance.databaseProvider;
    final summary = await provider.getBookLinkTargetsSummary(
      book.title,
      categoryId,
      source: book.source,
    );
    if (!mounted || widget.commentatorName != requested) return;
    final targets = commentaryAnchorTargetTitles(
      summary?.targets ?? const <LinkTargetSummary>[],
    );
    _commentaryAnchorTargets = targets;
    final content = _content;
    if (targets.isEmpty || content == null || content.isEmpty) return;
    if (_useWindowedLoading) {
      for (final range in _loadedRanges) {
        unawaited(
          _ensureAnchorLinksLoaded(range.startLine, range.endLine, book),
        );
      }
    } else {
      unawaited(_ensureAnchorLinksLoaded(0, content.length - 1, book));
    }
  }

  /// טוען את עוגני מפרשי-העל לטווח שורות, אם עוד לא נטענו. השאילתה מסוננת
  /// בצד המסד לספרי היעד בלבד, ולכן זולה גם במפרשים עתירי קישורים.
  Future<void> _ensureAnchorLinksLoaded(
    int startLine,
    int endLine,
    TextBook book,
  ) async {
    final targets = _commentaryAnchorTargets;
    final categoryId = book.categoryId;
    if (targets == null || targets.isEmpty || categoryId == null) return;
    final start = startLine < 0 ? 0 : startLine;
    if (endLine < start || _isAnchorRangeLoaded(start, endLine)) return;
    final requested = widget.commentatorName;
    final provider = LibraryProviderManager.instance.databaseProvider;
    late final List<Link> links;
    try {
      links = await provider.getLinksForBookRange(
        book.title,
        categoryId,
        'txt',
        startLineIndex: start,
        endLineIndex: endLine,
        targetBookTitles: targets,
        source: book.source,
      );
    } catch (e, stackTrace) {
      debugPrint('Failed to load commentary anchors: $e\n$stackTrace');
      return;
    }
    if (!mounted || widget.commentatorName != requested) return;
    final anchorLinks = filterCommentaryAnchorLinks(links);
    // העוגנים נמדדים על השורה המלאה: בלי ההערות אין להם מקום בטור.
    final BookNotes notes;
    try {
      notes = anchorLinks.isEmpty
          ? BookNotes.empty
          : await BookNotesRepository.instance.notesFor(
              book.title,
              categoryId: categoryId,
              source: book.source,
              fileType: 'txt',
            );
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'otzaria',
          context: ErrorDescription(
            'while loading the footnotes of "${book.title}"; its anchors are not shown',
          ),
        ),
      );
      return;
    }
    if (!mounted || widget.commentatorName != requested) return;
    _anchorLoadedRanges = TextBookBloc.mergeLoadedContentRanges(
      _anchorLoadedRanges,
      startLine: start,
      endLine: endLine,
    );
    if (anchorLinks.isEmpty) return;
    setState(() {
      _anchorBookNotes = notes;
      _anchorLinksByLine = mergeAnchorLinksByLine(
        _anchorLinksByLine,
        anchorLinks,
      );
    });
  }

  bool _isAnchorRangeLoaded(int start, int end) {
    for (final range in _anchorLoadedRanges) {
      if (start >= range.startLine && end <= range.endLine) return true;
    }
    return false;
  }

  /// נקודת הייחוס לסנכרון — כשליש מגובה ה-viewport מלמעלה (לא במרכז ולא
  /// בראש). אותו ערך משמש גם לבחירת שורת המקור וגם ליישור המפרש, כדי
  /// ששניהם יהיו באותו מיקום אנכי.
  static const double _syncAlignment = 1 / 3;

  /// סף בפיקסלים שמתחתיו היעד נחשב כבר במקומו. בלעדיו תזוזה של שבר פיקסל
  /// הייתה יורה אנימציה חדשה שמבטלת את הקודמת.
  static const double _glideEpsilonPixels = 2;

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
    return _LoadedCommentaryData(book: book, content: lines);
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
      _reportBook = _withReportId(data.book);
      _content = data.content;
      _isLoading = false;
      _lastSyncedIndex = null;
      _lastSyncedMainIndex = null;
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
        .where(
          (link) => link.overlapsSourceLines(mainLineNumber, mainLineNumber),
        )
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
    final commentator = widget.commentatorName;
    _reportBookId = null;
    setState(() {
      _isLoading = true;
      _commentaryToc = null;
    });
    _lastLinks = null;
    _useWindowedLoading = false;
    _rangeBook = null;
    _loadedRanges = const [];
    _commentaryAnchorTargets = null;
    _anchorLinksByLine = const {};
    _anchorBookNotes = BookNotes.empty;
    _anchorLoadedRanges = const [];

    try {
      // המתנה לכך שה-state יהיה TextBookLoaded
      final bloc = context.read<TextBookBloc>();
      var state = bloc.state;

      // אם ה-state עדיין לא TextBookLoaded, נחכה לו
      if (state is! TextBookLoaded) {
        try {
          state = await bloc.stream
              .firstWhere((s) => s is TextBookLoaded, orElse: () => state)
              .timeout(const Duration(seconds: 5));
        } catch (e) {
          // הספר לא נטען תוך 5 שניות — ממשיכים בלי רענון קישורים
          debugPrint('[PageShape] timeout waiting for TextBookLoaded: $e');
        }
      }

      if (!mounted) return;

      // מפרש שאינו מקושר לספר הנוכחי שייך לספר אחר, ו-BookLocator היה טוען
      // אותו לפי שמו ומציג את הספר הזר. ההגדרה השמורה נשארת על כנה.
      if (state is TextBookLoaded &&
          state.availableCommentators.isNotEmpty &&
          !state.availableCommentators.contains(widget.commentatorName)) {
        _notifyCommentaryLoadFailed();
        setState(() {
          _reportBook = null;
          _content = null;
          _isLoading = false;
        });
        return;
      }

      if (state is TextBookLoaded) {
        // סינון קישורים לפי שם המפרש ולפי סוג הקישור (COMMENTARY/TARGUM)
        _refreshRelevantLinks(state);
      }

      // מציאת הספר המלא של המפרש עם categoryId
      TextBook book;
      final attachedSource = _relevantLinks
          .map((link) => link.targetSource)
          .where((source) => source.isAttached)
          .firstOrNull;
      // מפרש ממסד מצורף יושב באותו מסד — לא ספר רשמי בשם זהה.
      final attachedRecord = attachedSource == null
          ? null
          : await BookDatabaseResolver.resolveBook(
              title: widget.commentatorName,
              preferSource: attachedSource,
            );
      final bookLocation = attachedSource != null
          ? null
          : await BookLocator.locateBook(widget.commentatorName);
      // מפרש שהוחלף בזמן החיפוש אינו מעביר את ה-id שלו למפרש הבא.
      if (widget.commentatorName != commentator) return;
      _reportBookId = attachedRecord?.book.id ?? bookLocation?.book?.id;

      if (attachedRecord != null) {
        book = TextBook(
          title: widget.commentatorName,
          categoryId: attachedRecord.book.categoryId,
          source: attachedRecord.source,
        );
      } else if (bookLocation != null &&
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
            final directoryPath = normalizedPath.substring(
              0,
              lastSeparatorIndex,
            );
            categoryPath = directoryPath
                .replaceAll('/', ', ')
                .replaceAll('\\', ', ');
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

      final useDatabaseSource =
          bookLocation != null &&
          bookLocation.book != null &&
          bookLocation.categoryId != null;
      final requestedCommentatorName = widget.commentatorName;

      // ספרי DB נטענים בחלונות סביב יעד הסנכרון — לא כל ספר המפרש לזיכרון.
      final currentState = state;
      if (useDatabaseSource && currentState is TextBookLoaded) {
        final targetIndex =
            _resolveInitialCommentaryTargetIndex(currentState) ?? 0;
        if (await _loadInitialWindow(
          book,
          targetIndex,
          requestedCommentatorName,
        )) {
          unawaited(_initCommentaryAnchors(book));
          return;
        }
        if (!mounted || widget.commentatorName != requestedCommentatorName) {
          return;
        }
      }

      final fullCommentaryFuture = _getOrLoadFullCommentary(
        _commentaryCacheKey(book, preferDatabase: useDatabaseSource),
        () => _fetchFullCommentaryData(book, preferDatabase: useDatabaseSource),
      );
      await _applyFullCommentaryData(
        fullCommentaryFuture,
        requestedCommentatorName,
      );
      if (useDatabaseSource &&
          mounted &&
          widget.commentatorName == requestedCommentatorName) {
        unawaited(_initCommentaryAnchors(book));
      }
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
      Future.delayed(const Duration(milliseconds: 50), _runInitialSyncAttempt);
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

    // יעד שכבר סונכרנו אליו אינו נוגע במפרש שוב: בלעדי זה כל emission של
    // ה-bloc (חימום תוכן ברקע, בחירת טקסט) גורר את המפרש בחזרה מעוגן גלילה
    // ידנית שהמשתמש עשה בחלונית.
    if (!CommentarySyncHelper.shouldMoveCommentary(
      targetIndex: targetIndex,
      selectedMainIndex: state.selectedIndex,
      lastSyncedIndex: _lastSyncedIndex,
      lastSyncedMainIndex: _lastSyncedMainIndex,
    )) {
      return;
    }

    if (targetIndex >= 0 &&
        targetIndex < _content!.length &&
        _scrollController.isAttached) {
      // במצב טעינת-חלונות: מזניק טעינה סביב היעד כדי שהשורות ימולאו
      // מיד אחרי הקפיצה (מאזין המיקומים ישלים חלונות בהמשך הגלילה).
      if (_useWindowedLoading) {
        unawaited(_ensureWindowLoaded(targetIndex, targetIndex));
      }
      if (_lastSyncedIndex == null) {
        // סנכרון ראשוני: הרשימה נבנתה מאינדקס 0 וחייבת להגיע למקומה מיד.
        _scrollController.jumpTo(index: targetIndex, alignment: _syncAlignment);
      } else if (state.selectedIndex != null) {
        _scrollController.scrollTo(
          index: targetIndex,
          duration: const Duration(milliseconds: 300),
          alignment: _syncAlignment,
        );
      } else {
        _glideToTarget(targetIndex);
      }
      _lastSyncedIndex = targetIndex;
      _lastSyncedMainIndex = state.selectedIndex;
    }
  }

  /// מזיז את המפרש ליעד בגלילה רציפה במקום בקפיצה.
  ///
  /// `jumpTo` מחליף את פריט העוגן ומרכיב מחדש את החלונית כולה; כשהיעד כבר
  /// גלוי די בהזזת ההיסט בפיקסלים, בלי בנייה מחדש.
  void _glideToTarget(int targetIndex) {
    final position = _visiblePositionFor(targetIndex);
    final viewportHeight =
        context.size?.height ?? MediaQuery.sizeOf(context).height;

    // יעד שלא נפרש — המרחק בפיקסלים אינו ידוע, ורק קפיצה תגיע אליו.
    if (position == null || viewportHeight <= 0) {
      _scrollController.jumpTo(index: targetIndex, alignment: _syncAlignment);
      return;
    }

    final delta = CommentarySyncHelper.glideDelta(
      leadingEdge: position.itemLeadingEdge,
      viewportHeight: viewportHeight,
      alignment: _syncAlignment,
      epsilon: _glideEpsilonPixels,
    );
    if (delta == null) {
      return;
    }

    unawaited(
      _scrollOffsetController.animateScroll(
        offset: delta,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      ),
    );
  }

  /// המיקום הנוכחי של [index] אם הוא בין הפריטים שנפרשו, אחרת null.
  ItemPosition? _visiblePositionFor(int index) {
    for (final position in _positionsListener.itemPositions.value) {
      if (position.index == index) {
        return position;
      }
    }
    return null;
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
      buildWhen: shouldRebuildIgnoringSelection,
      loadingWidget: const SizedBox(),
      builder: (context, state) {
        return BlocBuilder<SettingsBloc, SettingsState>(
          builder: (context, settingsState) {
            // רק המפרשים התחתונים משתמשים בגופן שנבחר בדיאלוג צורת הדף;
            // המפרשים הצדדיים נשארים עם גופן המפרשים הגלובלי מההגדרות.
            final bottomFont =
                Settings.getValue<String>(
                  SettingsRepository.keyPageShapeBottomFont,
                ) ??
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
              scrollOffsetController: _scrollOffsetController,
              isMainText: false,
              bookTitle: widget.commentatorName, // לפתיחה בטאב נפרד
              labelForIndex: _commentaryToc == null
                  ? null
                  : _commentaryLabelForIndex,
              reportBook: _reportBook,
              highlightedIndices: _highlightedIndices, // הדגשות מקומיות
              onCommentatorChanged: _reloadCommentary, // callback לרענון
              onOpenCommentaryPersonalNote: widget.onOpenPersonalNote,
              anchorLinksByLine: _anchorLinksByLine.isEmpty
                  ? null
                  : _anchorLinksByLine,
              anchorBookNotes: _anchorBookNotes,
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
      final parentState = context
          .findAncestorStateOfType<_PageShapeScreenState>();
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
        width:
            (width ??
                MediaQuery.of(context).size.width *
                    _kCommentaryPaneWidthFactor) +
            _kCommentaryLabelAndSpacingWidth,
        child: Center(
          child: FractionallySizedBox(
            widthFactor: 0.5,
            child: Container(height: 1, color: Theme.of(context).dividerColor),
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
