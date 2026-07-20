import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/tools/calendar/utils/calendar_cubit.dart';
import 'package:otzaria/settings/search/settings_search_field.dart';
import 'package:otzaria/settings/search/settings_search_index.dart';
import 'package:otzaria/settings/search/settings_search_models.dart';
import 'package:otzaria/settings/search/settings_search_registry.dart';
import 'package:otzaria/settings/search/settings_search_results_view.dart';
import 'package:otzaria/settings/tabs/settings_tabs_exports.dart';
import 'package:otzaria/settings/services/safer_mode_guard.dart';
import 'package:otzaria/widgets/navigation/keyboard_navigator.dart';
import 'package:otzaria/settings/widgets/settings_card.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:otzaria/tour/models/live_tip.dart';
import 'package:otzaria/tour/tour_target_keys.dart';
import 'package:otzaria/widgets/misc/rtl_icon.dart';
import 'package:otzaria/widgets/navigation/sidebar_nav_item.dart';

/// רוחב מקסימלי לתוכן ההגדרות — מרכוז על מסכים רחבים
// kSettingsContentMaxWidth הוסר — משתמשים ב-LayoutConstraints.panelContentMaxWidth מ-layout_tokens.dart

/// מייצג את לשוניות מסך ההגדרות שניתן לנווט אליהן בקוד.
enum SettingsTab { design, text, library, tools, shortcuts, system, about }

/// בקר פשוט לפתיחת לשונית מסוימת במסך ההגדרות.
class SettingsScreenController extends ChangeNotifier {
  SettingsTab? _requestedTab;

  SettingsTab? get requestedTab => _requestedTab;

  void openTab(SettingsTab tab) {
    _requestedTab = tab;
    notifyListeners();
  }

  SettingsTab? takeRequestedTab() {
    final tab = _requestedTab;
    _requestedTab = null;
    return tab;
  }
}

class MySettingsScreen extends StatefulWidget {
  const MySettingsScreen({super.key, this.controller});

  final SettingsScreenController? controller;

  @override
  State<MySettingsScreen> createState() => _MySettingsScreenState();
}

class _MySettingsScreenState extends State<MySettingsScreen> {
  int _selectedIndex = 0;
  bool _showMobileMenu = true;

  // ── ניווט מקלדת + גלילה ───────────────────────────────────────────────────
  final _contentFocusNode = FocusNode();
  final _contentScrollController = ScrollController();

  // ── חיפוש בהגדרות ─────────────────────────────────────────────────────────
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  List<SettingsSearchEntry> _searchResults = const [];

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_handleRequestedTab);
    _applyRequestedTab(widget.controller?.takeRequestedTab());
    FocusRepository().registerSettingsFocusRequester(_requestSettingsFocus);
    SettingsSearchRegistry.instance.addListener(_handleSearchNavigation);
    _handleSearchNavigation(); // handle a request set before this screen mounted
  }

  @override
  void dispose() {
    FocusRepository().unregisterSettingsFocusRequester(_requestSettingsFocus);
    SettingsSearchRegistry.instance.removeListener(_handleSearchNavigation);
    widget.controller?.removeListener(_handleRequestedTab);
    _contentFocusNode.dispose();
    _contentScrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  // ── חיפוש: עדכון השאילתה ─────────────────────────────────────────────────
  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
      _searchResults = SettingsSearchIndex.search(query);
    });
  }

  // ── חיפוש: איפוס שדה החיפוש, השאילתה והתוצאות ────────────────────────────
  void _clearSearch() {
    _searchController.clear();
    _searchQuery = '';
    _searchResults = const [];
  }

  // ── מובייל: כפתור "חזור" — סוגר קודם את החיפוש הפעיל, אחרת חוזר לתפריט ────
  void _handleMobileBack() {
    setState(() {
      if (_searchQuery.trim().isNotEmpty) {
        _clearSearch();
      } else {
        _showMobileMenu = true;
      }
    });
  }

  // ── חיפוש: לחיצה על תוצאה — נווט לטאב + גלול והבזק ───────────────────────
  void _onSearchResultTap(SettingsSearchEntry entry) {
    SettingsSearchRegistry.instance.navigateToEntry(entry);
    setState(_clearSearch);
  }

  static int _tabToIndex(SettingsTab tab) => switch (tab) {
    SettingsTab.design => 0,
    SettingsTab.text => 1,
    SettingsTab.library => 2,
    SettingsTab.tools => 3,
    SettingsTab.shortcuts => 4,
    SettingsTab.system => 5,
    SettingsTab.about => 6,
  };

  /// מדווח ל-TourCubit על כניסה לטאב קיצורים/מערכת — פותר טיפי "הידעת".
  void _recordTabTourInteraction(int index) {
    final type = switch (index) {
      4 => TourInteractionType.shortcutsSettingsOpened,
      5 => TourInteractionType.systemSettingsOpened,
      _ => null,
    };
    if (type == null || !mounted) return;
    context.read<TourCubit>().recordInteraction(TourInteraction(type: type));
  }

  // ── חיפוש: עיבוד בקשת ניווט מה-registry ──────────────────────────────────
  void _handleSearchNavigation() {
    final request = SettingsSearchRegistry.instance.pendingRequest;
    if (request == null) return;
    SettingsSearchRegistry.instance.consumePendingRequest();
    if (!mounted) return;

    final tabIndex = _tabToIndex(request.tab);

    setState(() {
      _selectedIndex = tabIndex;
      _showMobileMenu = false;
    });
    _recordTabTourInteraction(tabIndex);

    // לאחר טעינת הטאב — גלילה והבזק על הכרטיס.
    final cardId = request.cardId;
    if (cardId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await Future.delayed(const Duration(milliseconds: 80));
        await SettingsSearchRegistry.instance.scrollAndHighlight(cardId);
      });
    }
  }

  @override
  void didUpdateWidget(covariant MySettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_handleRequestedTab);
      widget.controller?.addListener(_handleRequestedTab);
      _applyRequestedTab(widget.controller?.takeRequestedTab());
    }
  }

  void _changeTab(int index) {
    setState(() {
      _selectedIndex = index;
      _clearSearch();
    });
    _recordTabTourInteraction(index);
    // בטוח רק בdesktop layout — במוד mobile ה-node לא מחובר לעץ הפוקוס
    if (_contentFocusNode.enclosingScope != null) {
      _contentFocusNode.requestFocus();
    }
  }

  void _requestSettingsFocus() {
    if (!mounted) return;
    // מעדכן את ה-screen restorer עם canRestore תלוי-layout —
    // במוד mobile ה-contentFocusNode לא מחובר לעץ הפוקוס ולכן canRestore=false.
    FocusRepository().setScreenRestorer(
      restore: () {
        if (mounted && _contentFocusNode.enclosingScope != null) {
          _contentFocusNode.requestFocus();
        }
      },
      canRestore: () => mounted && _contentFocusNode.enclosingScope != null,
    );
    if (_contentFocusNode.enclosingScope != null) {
      _contentFocusNode.requestFocus();
    }
  }

  void _handleRequestedTab() {
    _applyRequestedTab(widget.controller?.takeRequestedTab());
  }

  void _applyRequestedTab(SettingsTab? tab) {
    if (tab == null) return;

    final tabIndex = _tabToIndex(tab);

    if (!mounted) {
      _selectedIndex = tabIndex;
      _showMobileMenu = false;
      return;
    }

    setState(() {
      _selectedIndex = tabIndex;
      _showMobileMenu = false;
    });
    // בטוח רק בdesktop layout — במוד mobile ה-node לא מחובר לעץ הפוקוס
    if (_contentFocusNode.enclosingScope != null) {
      _contentFocusNode.requestFocus();
    }
  }

  // ── הגדרת רשימת הטאבים ────────────────────────────────────────────────────
  late final List<
    ({
      String label,
      IconData icon,
      IconData iconFilled,
      Widget Function() pageBuilder,
    })
  >
  _tabsData = [
    (
      label: 'מראה',
      icon: FluentIcons.paint_brush_24_regular,
      iconFilled: FluentIcons.paint_brush_24_filled,
      pageBuilder: () => const DesignSettingsTab(),
    ),
    (
      label: 'כתב',
      icon: FluentIcons.book_24_regular,
      iconFilled: FluentIcons.book_24_filled,
      pageBuilder: () => const TextSettingsTab(),
    ),
    (
      label: 'ספריה',
      icon: FluentIcons.library_24_regular,
      iconFilled: FluentIcons.library_24_filled,
      pageBuilder: () => const LibrarySettingsTab(),
    ),
    (
      label: 'כלים',
      icon: FluentIcons.apps_24_regular,
      iconFilled: FluentIcons.apps_24_filled,
      pageBuilder: () => ToolsSettingsTab(
        calendarCubit: context.read<CalendarCubit>(),
      ),
    ),
    (
      label: 'קיצורי מקשים',
      icon: FluentIcons.keyboard_24_regular,
      iconFilled: FluentIcons.keyboard_24_filled,
      pageBuilder: () => const ShortcutsSettingsTab(),
    ),
    (
      label: 'מערכת',
      icon: FluentIcons.settings_24_regular,
      iconFilled: FluentIcons.settings_24_filled,
      pageBuilder: () => const SystemSettingsTab(),
    ),
    (
      label: 'אודות',
      icon: FluentIcons.people_team_24_regular,
      iconFilled: FluentIcons.people_team_24_filled,
      pageBuilder: () => const AboutSettingsTab(),
    ),
  ];

  // ── קבוצות למובייל ────────────────────────────────────────────────────────
  // כל קבוצה: (כותרת, רשימת אינדקסים מ-_tabsData)
  static const _mobileGroups = [
    (label: 'תצוגה ותוכן', indices: <int>[0, 1, 2]),
    (label: 'כלים', indices: <int>[3, 4]),
    (label: 'מערכת', indices: <int>[5, 6]),
  ];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // panelBackground מוגדר ב-AppSurfaces ומשמש גם ספריה, כלים, והגדרות
    final bgColor = AppSurfaces.panelBackground(context);
    // במצב חיפוש מציגים תוצאות חוצות-קטגוריות, ולכן הכותרת אינה שם
    // הלשונית האחרונה ואף לשונית בצד אינה "פעילה".
    final isSearching = _searchQuery.trim().isNotEmpty;

    return SaferModeGuard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < LayoutBreakpoints.compact;

          // ── מצב מובייל ────────────────────────────────────────────────
          if (isMobile) {
            if (_showMobileMenu) {
              final showResults = _searchQuery.trim().isNotEmpty;
              return KeyboardNavigator(
                currentTabIndex: _selectedIndex,
                totalTabs: _tabsData.length,
                onTabChange: (i) => setState(() => _selectedIndex = i),
                onBack: showResults ? _handleMobileBack : null,
                child: Scaffold(
                  backgroundColor: bgColor,
                  appBar: AppBar(
                    backgroundColor: bgColor,
                    elevation: 0,
                    title: Text(showResults ? 'תוצאות חיפוש' : 'הגדרות'),
                    leading: showResults
                        ? Tooltip(
                            message: 'חזור (Esc)',
                            child: IconButton(
                              icon: const RtlIcon(
                                FluentIcons.arrow_right_24_regular,
                              ),
                              onPressed: _handleMobileBack,
                            ),
                          )
                        : null,
                  ),
                  body: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                        child: SettingsSearchField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          onChanged: _onSearchChanged,
                        ),
                      ),
                      Expanded(
                        child: showResults
                            ? SettingsSearchResultsView(
                                query: _searchQuery,
                                results: _searchResults,
                                onResultTap: _onSearchResultTap,
                              )
                            : ListView(
                                padding: const EdgeInsets.all(12),
                                children: [
                                  for (final group in _mobileGroups) ...[
                                    SettingsCard(
                                      title: group.label,
                                      children: [
                                        for (final idx in group.indices)
                                          ListTile(
                                            key: tourSettingsTabTargetKeys[idx],
                                            leading: Icon(
                                              _tabsData[idx].icon,
                                              color: colorScheme.primary,
                                            ),
                                            title: Text(
                                              _tabsData[idx].label,
                                            ),
                                            trailing: const RtlIcon(
                                              FluentIcons
                                                  .chevron_left_24_regular,
                                            ),
                                            onTap: () {
                                              setState(() {
                                                _selectedIndex = idx;
                                                _showMobileMenu = false;
                                              });
                                              _recordTabTourInteraction(idx);
                                            },
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              );
            } else {
              final showResults = _searchQuery.trim().isNotEmpty;
              return KeyboardNavigator(
                currentTabIndex: _selectedIndex,
                totalTabs: _tabsData.length,
                onTabChange: _changeTab,
                onBack: _handleMobileBack,
                child: Scaffold(
                  backgroundColor: bgColor,
                  appBar: AppBar(
                    backgroundColor: bgColor,
                    elevation: 0,
                    title: Text(
                      isSearching
                          ? 'תוצאות חיפוש'
                          : _tabsData[_selectedIndex].label,
                    ),
                    leading: Tooltip(
                      message: 'חזור (Esc)',
                      child: IconButton(
                        icon: const RtlIcon(FluentIcons.arrow_right_24_regular),
                        onPressed: _handleMobileBack,
                      ),
                    ),
                  ),
                  body: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                        child: SettingsSearchField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          onChanged: _onSearchChanged,
                        ),
                      ),
                      Expanded(
                        child: showResults
                            ? SettingsSearchResultsView(
                                query: _searchQuery,
                                results: _searchResults,
                                onResultTap: _onSearchResultTap,
                              )
                            : _tabsData[_selectedIndex].pageBuilder(),
                      ),
                    ],
                  ),
                ),
              );
            }
          }

          // ── מצב דסקטופ: KeyboardNavigator + sidebar + תוכן ──────────
          return KeyboardNavigator(
            currentTabIndex: _selectedIndex,
            totalTabs: _tabsData.length,
            onTabChange: _changeTab,
            onBack: null,
            child: Scaffold(
              backgroundColor: bgColor,
              body: Listener(
                // [תיקון גלילה] גלגל עכבר מכל מקום (כולל sidebar) גולל את התוכן
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent &&
                      _contentScrollController.hasClients) {
                    final newOffset =
                        _contentScrollController.offset + event.scrollDelta.dy;
                    _contentScrollController.jumpTo(
                      newOffset.clamp(
                        0.0,
                        _contentScrollController.position.maxScrollExtent,
                      ),
                    );
                  }
                },
                child: Row(
                  children: [
                    // ── Sidebar ──────────────────────────────────────
                    SizedBox(
                      width: 210,
                      child: Container(
                        color: bgColor,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 28,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(
                                right: 12,
                                left: 12,
                                bottom: 20,
                              ),
                              child: Text(
                                'הגדרות',
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ),
                            Expanded(
                              child: ListView.builder(
                                itemCount: _tabsData.length,
                                itemBuilder: (context, index) => SidebarNavItem(
                                  key: tourSettingsTabTargetKeys[index],
                                  icon: _tabsData[index].icon,
                                  iconFilled: _tabsData[index].iconFilled,
                                  label: _tabsData[index].label,
                                  isSelected:
                                      !isSearching && _selectedIndex == index,
                                  onTap: () => _changeTab(index),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // ── אזור תוכן ────────────────────────────────────
                    Expanded(
                      child: _SettingsContentPane(
                        key: ValueKey(_selectedIndex),
                        label: isSearching
                            ? 'תוצאות חיפוש'
                            : _tabsData[_selectedIndex].label,
                        bgColor: bgColor,
                        focusNode: _contentFocusNode,
                        scrollController: _contentScrollController,
                        headerExtra: SettingsSearchField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          onChanged: _onSearchChanged,
                        ),
                        overrideContent: _searchQuery.trim().isEmpty
                            ? null
                            : SettingsSearchResultsView(
                                query: _searchQuery,
                                results: _searchResults,
                                onResultTap: _onSearchResultTap,
                              ),
                        child: _tabsData[_selectedIndex].pageBuilder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── _SettingsContentPane ───────────────────────────────────────────────────────
// [שינוי] StatefulWidget — בקשת focus בכניסה לטאב חדש
class _SettingsContentPane extends StatefulWidget {
  final String label;
  final Widget child;
  final Color bgColor;
  final FocusNode focusNode;
  final ScrollController scrollController;
  final Widget? headerExtra;
  final Widget? overrideContent;

  const _SettingsContentPane({
    required this.label,
    required this.child,
    required this.bgColor,
    required this.focusNode,
    required this.scrollController,
    this.headerExtra,
    this.overrideContent,
    super.key,
  });

  @override
  State<_SettingsContentPane> createState() => _SettingsContentPaneState();
}

class _SettingsContentPaneState extends State<_SettingsContentPane> {
  @override
  void initState() {
    super.initState();
    // בקשת focus כדי שניווט מקלדת יעבוד מיד
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.focusNode.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      child: ColoredBox(
        color: widget.bgColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: LayoutConstraints.panelContentMaxWidth,
                ),
                child: Padding(
                  padding: const EdgeInsets.only(
                    top: 28,
                    right: 16,
                    left: 16,
                    bottom: 4,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          widget.label,
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (widget.headerExtra != null)
                        SizedBox(
                          width: 260,
                          child: widget.headerExtra!,
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: ScrollbarTheme(
                data: ScrollbarTheme.of(context).copyWith(
                  crossAxisMargin: 6,
                  mainAxisMargin: 0,
                ),
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(
                    context,
                  ).copyWith(scrollbars: false),
                  child: Scrollbar(
                    controller: widget.scrollController,
                    thumbVisibility: true,
                    interactive: true,
                    child: PrimaryScrollController(
                      controller: widget.scrollController,
                      child: widget.overrideContent ?? widget.child,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
