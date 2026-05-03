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
import 'dart:isolate';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/data/book_locator.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/widgets/buttons/action_buttons.dart';
import 'package:otzaria/widgets/commentary_pane_tooltip.dart';

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
  double? _bottomLeftWidth; // רוחב המפרש התחתון השמאלי (כאשר יש 2 מפרשים תחתונים)

  // הגדרות הצגת טורים
  Map<String, bool> _columnVisibility = {
    'left': true,
    'right': true,
    'bottom': true,
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
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
    _bottomLeftWidth = Settings.getValue<double>('page_shape_bottom_left_width') ??
        screenWidth * 0.5;

    setState(() {});
  }

  /// שמירת גדלים
  void _saveSizes() {
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
    if (_bottomLeftWidth != null) {
      Settings.setValue<double>('page_shape_bottom_left_width', _bottomLeftWidth!);
    }
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
    if (lineNumber < 1 || state.content.isEmpty) {
      return;
    }

    final targetIndex = (lineNumber - 1).clamp(0, state.content.length - 1);

    await state.scrollController.scrollTo(
      index: targetIndex,
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

  void _toggleLeftSidebar() {
    setState(() {
      _isLeftSidebarOpen = !_isLeftSidebarOpen;
      if (!_isLeftSidebarOpen) {
        _isHoveringSidebarHandle = false;
      }
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

  @override
  void initState() {
    super.initState();
    widget.sidebarTabNotifier?.addListener(_handleSidebarTabRequest);
  }

  @override
  void didUpdateWidget(covariant PageShapeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sidebarTabNotifier != widget.sidebarTabNotifier) {
      oldWidget.sidebarTabNotifier?.removeListener(_handleSidebarTabRequest);
      widget.sidebarTabNotifier?.addListener(_handleSidebarTabRequest);
    }
  }

  @override
  void dispose() {
    widget.sidebarTabNotifier?.removeListener(_handleSidebarTabRequest);
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
      ),
    );

    // אם היו שינויים, טען מחדש את ההגדרות
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
          listenWhen: (previous, current) =>
              previous.isCreatingNewNote != current.isCreatingNewNote,
          listener: (context, state) {
            if (state.isCreatingNewNote) {
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
                                                      _leftWidth =
                                                          ((_leftWidth ?? 
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
                                                      _rightWidth =
                                                          ((_rightWidth ?? 
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
                                                      SizedBox(
                                                        width: _bottomLeftWidth ??
                                                            MediaQuery.of(context)
                                                                    .size
                                                                    .width *
                                                                0.5,
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
                                                                    _bottomLeftWidth =
                                                                        ((_bottomLeftWidth ?? 
                                                                            MediaQuery.of(context)
                                                                                    .size
                                                                                    .width *
                                                                                0.5) -
                                                                                delta)
                                                                            .clamp(
                                                                      100.0,
                                                                      MediaQuery.of(context)
                                                                              .size
                                                                              .width *
                                                                          0.8,
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
                                categoryId: state.book.categoryId,
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

  int _resolveCurrentMainIndex(TextBookLoaded state) {
    if (state.selectedIndex != null) {
      return state.selectedIndex!;
    }

    if (state.visibleIndices.isNotEmpty) {
      return state.visibleIndices.first;
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

    final bestLink = CommentarySyncHelper.findBestLink(
      linksForCommentary: _relevantLinks,
      logicalMainIndex: logicalIndex,
    );

    return CommentarySyncHelper.getCommentaryTargetIndex(bestLink);
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

    final currentState = context.read<TextBookBloc>().state;
    if (currentState is TextBookLoaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _syncWithMainText(currentState);
        }
      });
    }
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

  Future<void> _loadCommentary() async {
    if (!mounted) return;
    if (widget.commentatorName == kNotesCommentatorTitle) return;
    setState(() => _isLoading = true);
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

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _syncWithMainText(currentState);
            }
          });
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
      // בסנכרון ראשוני (אחרי טעינה) — קפיצה מיידית ללא אנימציה
      // כדי למנוע בניית אלפי פריטים בזמן אנימציה (גורמת לתקיעה)
      if (_lastSyncedIndex == null) {
        _scrollController.jumpTo(
          index: targetIndex,
          alignment: 0.0,
        );
      } else {
        _scrollController.scrollTo(
          index: targetIndex,
          duration: const Duration(milliseconds: 300),
          alignment: 0.0,
        );
      }
      _lastSyncedIndex = targetIndex;
    }
  }

  @override
  Widget build(BuildContext context) {
    // הערות על הספר — virtual commentator, אין ספר לטעון
    if (widget.commentatorName == kNotesCommentatorTitle) {
      return CommentaryListBase(
        openBookCallback: (tab) => widget.openBookCallback(tab),
        fontSize: PageShapeSettingsManager.getCommentaryFontSize(),
        showSearch: true,
        shrinkWrap: false,
        selectedCommentatorsOverride: const [kNotesCommentatorTitle],
      );
    }

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
