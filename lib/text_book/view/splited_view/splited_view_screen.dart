import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:multi_split_view/multi_split_view.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/combined_view/combined_book_screen.dart';
import 'package:otzaria/text_book/view/selection/selection_sync_controller.dart';
import 'package:otzaria/text_book/view/tabbed_commentary_panel.dart';
import 'package:otzaria/text_book/widgets/text_book_state_builder.dart';
import 'package:otzaria/utils/ui/commentary_pane_policy.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:otzaria/tour/models/live_tip.dart';
import 'package:otzaria/widgets/layout/adaptive_side_pane.dart';
import 'package:otzaria/widgets/navigation/panel_tab_header.dart';

class SplitedViewScreen extends StatefulWidget {
  const SplitedViewScreen({
    super.key,
    required this.content,
    required this.openBookCallback,
    required this.searchTextController,
    required this.openLeftPaneTab,
    this.onSelectedTextChanged,
    required this.tab,
    this.initialTabIndex,
    required this.showSplitView,
    this.onSidebarTabChanged,
  });

  final List<String> content;
  final void Function(OpenedTab) openBookCallback;
  final TextEditingValue searchTextController;
  final void Function(int, {String? searchText}) openLeftPaneTab;
  final void Function(String? text, int? lineIndex, int? column)?
      onSelectedTextChanged;
  final TextBookTab tab;
  final int? initialTabIndex;
  final bool showSplitView;
  final ValueChanged<int>? onSidebarTabChanged;

  @override
  State<SplitedViewScreen> createState() => _SplitedViewScreenState();
}

class _SplitedViewScreenState extends State<SplitedViewScreen> {
  // קבועים לאינדקסים של הטאבים
  static const int _commentaryTabIndex = 0;
  static const int _linksTabIndex = 1;
  static const int _notesTabIndex = 2;

  late final MultiSplitViewController _controller;
  bool _paneOpen = false;
  // פתיחה אוטומטית של פאנל המפרשים מתבצעת פעם אחת בלבד לכל טעינת מסך.
  bool _didAutoOpenCommentary = false;
  int? _currentTabIndex;
  late double _leftPaneWidth;
  final ValueNotifier<String?> _savedSelectedText =
      ValueNotifier<String?>(null); // טקסט נבחר לתפריט הקשר
  final SelectionSyncController _selectionSyncController =
      SelectionSyncController();
  final ValueNotifier<int> _openFilterRequest = ValueNotifier<int>(0);
  final ValueNotifier<int> _openCommentatorsFilterNotifier =
      ValueNotifier<int>(0);
  final ValueNotifier<int> _closeCommentatorsFilterNotifier =
      ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _controller = MultiSplitViewController();
    _currentTabIndex = _getInitialTabIndex();
    if (widget.initialTabIndex != null) {
      _paneOpen = true;
    }
    // טען את רוחב הפאנל מההגדרות
    _leftPaneWidth = context.read<SettingsBloc>().state.commentaryPaneWidth;
    widget.tab.toggleCommentatorsPaneNotifier
        .addListener(_onToggleCommentatorsPaneRequest);
    widget.tab.openNotesTabNotifier.addListener(_onOpenNotesTabRequest);
    // אם המפרשים כבר נטענו עד שהמסך נבנה — ה-BlocListener לא יראה מעבר,
    // לכן בודקים גם פעם אחת אחרי ה-frame הראשון.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeAutoOpenCommentaryPane();
    });
  }

  /// טוגל חכם של חלונית המפרשים מקיצור מקלדת:
  /// - רק במצב split view (מפרשים בצד); במצב מפרשים למטה — המפרשים מוצגים
  ///   inline ולכן הקיצור לא פועל.
  /// - פאנל סגור או פתוח על טאב אחר → פתח על המפרשים.
  /// - פאנל פתוח על המפרשים → סגור.
  void _onOpenNotesTabRequest() {
    if (!mounted) return;
    setState(() {
      _paneOpen = true;
      _currentTabIndex = _notesTabIndex;
    });
  }

  void _onToggleCommentatorsPaneRequest() {
    if (!mounted) return;
    // במצב מפרשים מתחת לטקסט הקיצור לא רלוונטי — המפרשים תמיד גלויים inline.
    if (!widget.showSplitView) return;
    final isOnCommentary = _paneOpen && _currentTabIndex == _commentaryTabIndex;
    if (isOnCommentary) {
      setState(() {
        _paneOpen = false;
      });
    } else {
      // רישום interaction של TourCubit לפני הפתיחה — בעקבי עם השאר
      // המסלולים שפותחים את חלונית המפרשים (ע' text_book_screen).
      context.read<TourCubit>().recordInteraction(
            TourInteraction(
              type: TourInteractionType.commentaryUsed,
              primaryValue: widget.tab.title,
            ),
          );
      setState(() {
        _paneOpen = true;
        _currentTabIndex = _commentaryTabIndex;
      });
    }
  }

  @override
  void didUpdateWidget(SplitedViewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tab != widget.tab) {
      oldWidget.tab.toggleCommentatorsPaneNotifier
          .removeListener(_onToggleCommentatorsPaneRequest);
      widget.tab.toggleCommentatorsPaneNotifier
          .addListener(_onToggleCommentatorsPaneRequest);
      oldWidget.tab.openNotesTabNotifier.removeListener(_onOpenNotesTabRequest);
      widget.tab.openNotesTabNotifier.addListener(_onOpenNotesTabRequest);
    }
    // אם showSplitView השתנה או initialTabIndex השתנה, מעדכן את הטאב
    if (oldWidget.showSplitView != widget.showSplitView ||
        oldWidget.initialTabIndex != widget.initialTabIndex) {
      setState(() {
        _currentTabIndex = _getInitialTabIndex();
        // אם עוברים למצב split view או initialTabIndex השתנה, פותחים את הטור השמאלי אוטומטית
        if ((widget.showSplitView || widget.initialTabIndex != null) &&
            !_paneOpen) {
          _paneOpen = true;
        }
        // אם המצב באמת עבר ל'מפרשים מתחת' (showSplitView true→false),
        // סוגרים את החלונית הצדית. חשוב לבדוק שהמצב השתנה — אחרת
        // שינוי טאב פנימי (initialTabIndex) ב-'מפרשים מתחת' היה גורם
        // לסגירת החלונית בכל מעבר בין הלשוניות.
        if (oldWidget.showSplitView && !widget.showSplitView && _paneOpen) {
          _paneOpen = false;
        }
      });
    }
  }

  int _getInitialTabIndex() {
    // קביעת הטאב הראשוני
    // הטאבים בטור השמאלי: 0=מפרשים, 1=קישורים, 2=הערות אישיות
    if (widget.initialTabIndex != null) {
      debugPrint('DEBUG: Using initialTabIndex: ${widget.initialTabIndex}');
      // וידוא שהאינדקס תקף (0-2)
      return widget.initialTabIndex!.clamp(0, 2);
    } else {
      // ברירת מחדל - מפרשים (0)
      final saved = Settings.getValue<int>('key-sidebar-tab-index-combined');
      debugPrint('DEBUG: saved: $saved, returning: ${saved ?? 0}');
      // וידוא שהערך השמור תקף (0-2)
      return (saved ?? 0).clamp(0, 2);
    }
  }

  ({double paneWidth, double minPaneWidth, double maxPaneWidth})
      _calculatePaneWidths(double availableWidth) {
    const minPaneWidth = 280.0;
    const minTextWidth = 300.0;
    final maxPaneWidth =
        (availableWidth * 0.75).clamp(minPaneWidth, double.infinity);
    // נדחס אם אין מספיק מקום לטקסט, אבל לא עולה על 75%
    final effectiveMax =
        ((availableWidth - minTextWidth).clamp(minPaneWidth, maxPaneWidth));
    final paneWidth = _leftPaneWidth.clamp(minPaneWidth, effectiveMax);

    return (
      paneWidth: paneWidth,
      minPaneWidth: minPaneWidth,
      maxPaneWidth: maxPaneWidth,
    );
  }

  void _togglePane() {
    if (!_paneOpen) {
      // פתיחת הטור - בחר את הטאב הנכון
      _openPaneWithSmartTab();
    } else {
      // סגירת הטור
      setState(() {
        _paneOpen = false;
      });
    }
  }

  // פונקציה ציבורית לפתיחה/סגירה מבחוץ
  void togglePane() {
    _togglePane();
  }

  void _openPaneWithSmartTab() {
    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded) {
      _openPane();
      return;
    }

    int targetTab;

    if (widget.showSplitView) {
      // מצב "מפרשים בצד" - תמיד פתח על מפרשים
      targetTab = _commentaryTabIndex;
    } else {
      // מצב "מפרשים מתחת הטקסט" - פתח קישורים (אם יש)
      final hasLinks = state.visibleLinks.isNotEmpty;
      if (hasLinks) {
        targetTab = _linksTabIndex;
      } else {
        targetTab = _notesTabIndex;
      }
    }

    setState(() {
      _paneOpen = true;
      _currentTabIndex = targetTab;
    });
  }

  void _openPane() {
    if (!_paneOpen) {
      setState(() {
        _paneOpen = true;
      });
    }
  }

  /// פותח אוטומטית את פאנל המפרשים בפתיחת ספר, אם ההגדרה דולקת, אנחנו במצב
  /// "מפרשים בצד" (showSplitView) ויש מפרשים נבחרים. פעם אחת בלבד, כדי לא
  /// להיאבק עם סגירה ידנית של המשתמש. במצב "מפרשים מתחת"/"צורת הדף" לא רלוונטי.
  void _maybeAutoOpenCommentaryPane() {
    if (!mounted) return;
    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded) return;
    if (!shouldAutoOpenCommentaryPane(
      settingEnabled: context.read<SettingsBloc>().state.defaultCommentaryOpen,
      isSupportedMode: widget.showSplitView,
      hasSelectedCommentators: state.activeCommentators.isNotEmpty,
      alreadyAutoOpened: _didAutoOpenCommentary,
      paneAlreadyOpen: _paneOpen,
    )) {
      return;
    }
    _didAutoOpenCommentary = true;
    setState(() {
      _paneOpen = true;
      _currentTabIndex = _commentaryTabIndex;
    });
    // פתיחה אוטומטית נחשבת כ"שימוש במפרשים" — מדכאת את טיפ "כדאי לפתוח מפרשים".
    context.read<TourCubit>().recordInteraction(
          TourInteraction(
            type: TourInteractionType.commentaryUsed,
            primaryValue: widget.tab.title,
          ),
        );
  }

  @override
  void dispose() {
    widget.tab.toggleCommentatorsPaneNotifier
        .removeListener(_onToggleCommentatorsPaneRequest);
    widget.tab.openNotesTabNotifier.removeListener(_onOpenNotesTabRequest);
    _controller.dispose();
    _savedSelectedText.dispose();
    _selectionSyncController.dispose();
    _openFilterRequest.dispose();
    _openCommentatorsFilterNotifier.dispose();
    _closeCommentatorsFilterNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<TextBookBloc, TextBookState>(
      listenWhen: (previous, current) {
        // האזן רק אם הוספנו מפרשים (לא אם הסרנו)
        if (previous is TextBookLoaded && current is TextBookLoaded) {
          return current.activeCommentators.length >
              previous.activeCommentators.length;
        }
        return false;
      },
      listener: (context, state) {
        // כשמפרשים נטענים בפתיחה (ברירת מחדל/שמורים) — פתח את הפאנל אוטומטית
        // אם ההגדרה דולקת.
        _maybeAutoOpenCommentaryPane();
      },
      child: TextBookStateBuilder(
        buildWhen: (previous, current) {
          if (previous is TextBookLoaded && current is TextBookLoaded) {
            return previous.fontSize != current.fontSize ||
                previous.showSplitView != current.showSplitView;
          }
          return true;
        },
        builder: (context, state) {
          return LayoutBuilder(
            builder: (context, constraints) {
              final availableWidth = constraints.maxWidth;
              final paneWidths = _calculatePaneWidths(availableWidth);

              return AdaptiveSidePane(
                isOpen: _paneOpen,
                alignment: AlignmentDirectional.centerStart,
                paneWidth: paneWidths.paneWidth,
                minMainContentWidth: 200,
                onClose: () {
                  setState(() {
                    _paneOpen = false;
                  });
                },
                paneContent: ValueListenableBuilder<String?>(
                  valueListenable: _savedSelectedText,
                  // אין SelectionArea חיצוני כאן: CommentaryListBase (בתוך
                  // TabbedCommentaryPanel) עוטף את הרשימה ב-SelectionArea יחיד
                  // משלו. קינון היה הופך את תוכן המפרשים ל"בלוק אטום" שבחירת
                  // מקלדת (Shift+חץ) מדלגת עליו.
                  child: TabbedCommentaryPanel(
                    fontSize: state.fontSize,
                    openBookCallback: widget.openBookCallback,
                    showSearch: true,
                    selectionSyncController: _selectionSyncController,
                    openFilterRequest: _openFilterRequest,
                    onClosePane: _togglePane,
                    initialTabIndex: _currentTabIndex,
                    showSplitView: widget.showSplitView,
                    tab: widget.tab,
                    openCommentatorsFilterNotifier:
                        _openCommentatorsFilterNotifier,
                    closeCommentatorsFilterNotifier:
                        _closeCommentatorsFilterNotifier,
                    onTabChanged: (index) {
                      debugPrint(
                          'DEBUG: Tab changed to $index, showSplitView: ${widget.showSplitView}');
                      setState(() {
                        _currentTabIndex = index;
                      });
                      widget.onSidebarTabChanged?.call(index);
                      if (!widget.showSplitView) {
                        debugPrint(
                            'DEBUG: Saving tab $index to combined settings');
                        Settings.setValue<int>(
                            'key-sidebar-tab-index-combined', index);
                      } else {
                        debugPrint('DEBUG: NOT saving tab (split view mode)');
                      }
                    },
                  ),
                  builder: (context, selectedText, child) => child!,
                ),
                mainContent: Stack(
                  children: [
                    CombinedView(
                      data: widget.content,
                      textSize: state.fontSize,
                      openBookCallback: widget.openBookCallback,
                      openLeftPaneTab: widget.openLeftPaneTab,
                      onSelectedTextChanged: widget.onSelectedTextChanged,
                      selectionSyncController: _selectionSyncController,
                      showCommentaryAsExpansionTiles: !widget.showSplitView,
                      tab: widget.tab,
                      onOpenPersonalNotes: () {
                        setState(() {
                          _paneOpen = true;
                          _currentTabIndex = 2;
                        });
                      },
                      onOpenCommentatorsPane: () {
                        setState(() {
                          _paneOpen = true;
                        });
                        Future.delayed(const Duration(milliseconds: 280), () {
                          if (!mounted) return;
                          _closeCommentatorsFilterNotifier.value++;
                          setState(() {
                            _currentTabIndex = 0;
                          });
                        });
                      },
                      onOpenCommentatorsPaneWithFilter: () {
                        setState(() {
                          _paneOpen = true;
                          _currentTabIndex = 0;
                        });
                        _openCommentatorsFilterNotifier.value++;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          _openFilterRequest.value++;
                        });
                      },
                      onOpenLinksPane: () {
                        setState(() {
                          _paneOpen = true;
                          _currentTabIndex = _linksTabIndex;
                        });
                      },
                      isCommentatorsTabActive: () =>
                          _paneOpen && _currentTabIndex == 0,
                      isLinksTabActive: () =>
                          _paneOpen && _currentTabIndex == _linksTabIndex,
                    ),
                    if (!_paneOpen)
                      Positioned(
                        left: 0,
                        top: MediaQuery.of(context).size.height * 0.10,
                        child: PanelOpenHandle(onTap: _togglePane),
                      ),
                  ],
                ),
                isResizable: true,
                minPaneWidth: paneWidths.minPaneWidth,
                maxPaneWidth: paneWidths.maxPaneWidth,
                onPaneWidthChanged: (nextWidth) {
                  _leftPaneWidth = nextWidth;
                },
                onPaneResizeEnd: () {
                  context
                      .read<SettingsBloc>()
                      .add(UpdateCommentaryPaneWidth(_leftPaneWidth));
                },
                autoHandleResponsiveVisibility: false,
                scrollbarTopMargin: 0,
              );
            },
          );
        },
      ),
    );
  }
}
