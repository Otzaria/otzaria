// lib/tools/more_screen.dart
//
// שינויים:
//  • מסך צר: תפריט סגנון הגדרות (SettingsCard קבוצות + ListTile) → tap → תוכן + חזרה
//  • מסך רחב: TabBar M3 ראשי — ללא קו מתחת, אינדיקטור ריבוע מעוגל שקוף
//  • AnimatedSwitcher: מעבר חלק בין wide ↔ narrow
//  • Ctrl+Tab / Ctrl+Shift+Tab: KeyboardNavigator מכל מקום
//  • רקע: AppSurfaces.panelBackground

import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/settings_card.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/tools/measurement_converter/measurement_converter_screen.dart';
import 'package:otzaria/tools/gematria/gematria_search_screen.dart';
import 'package:otzaria/tools/aramaic_dictionary/aramaic_dictionary_screen.dart';
import 'package:otzaria/tools/acronyms_dictionary/acronyms_dictionary_screen.dart';
import 'package:otzaria/tools/shamor_zachor/shamor_zachor.dart';
import 'package:otzaria/tools/calendar/ulits/calendar_widget.dart';
import 'package:otzaria/tools/calendar/ulits/calendar_cubit.dart';
import 'package:otzaria/personal_notes/view/personal_notes_screen.dart';
import 'package:otzaria/widgets/keyboard_navigator.dart';
import 'package:otzaria/widgets/rtl_icon.dart';
import 'package:otzaria/core/focus_repository.dart';

final GlobalKey<MoreScreenState> moreScreenKey = GlobalKey<MoreScreenState>();

class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  @override
  State<MoreScreen> createState() => MoreScreenState();
}

class MoreScreenState extends State<MoreScreen>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late final TabController _tabController;
  final GlobalKey<GematriaSearchScreenState> _gematriaKey =
      GlobalKey<GematriaSearchScreenState>();
  late final List<Widget> _pages;

  // ── מצב מובייל ───────────────────────────────────────────────────────────
  bool _showMobileMenu = true;
  int _selectedIndex = 0;

  // ── FocusNode לאזור התוכן (מיקוד אוטומטי בעת מעבר טאב) ─────────────────
  final FocusNode _contentFocusNode = FocusNode();

  // ── הגדרת טאבים ──────────────────────────────────────────────────────────
  final List<_TabInfo> _tabs = [
    const _TabInfo(
      label: 'לוח שנה',
      icon: FluentIcons.calendar_24_regular,
      iconFilled: FluentIcons.calendar_24_filled,
    ),
    const _TabInfo(
      label: 'שמור וזכור',
      icon: null,
      imageIcon: 'assets/icon/שמור וזכור שחור ריק.png',
    ),
    const _TabInfo(
      label: 'הערות אישיות',
      icon: FluentIcons.note_24_regular,
      iconFilled: FluentIcons.note_24_filled,
    ),
    const _TabInfo(
      label: 'מדות ושיעורים',
      icon: FluentIcons.ruler_24_regular,
      iconFilled: FluentIcons.ruler_24_filled,
    ),
    const _TabInfo(
      label: 'גימטריה',
      icon: FluentIcons.calculator_24_regular,
      iconFilled: FluentIcons.calculator_24_filled,
    ),
    const _TabInfo(
      label: 'מילון ארמי-עברי',
      icon: FluentIcons.translate_24_regular,
      iconFilled: FluentIcons.translate_24_filled,
    ),
    const _TabInfo(
      label: 'ראשי תיבות',
      icon: FluentIcons.text_quote_24_regular,
      iconFilled: FluentIcons.text_quote_24_filled,
    ),
  ];

  // ── קבוצות תפריט מובייל ───────────────────────────────────────────────────
  static const _mobileGroups = [
    (label: 'לוח שנה', indices: <int>[0]),
    (label: 'תורה שלמדתי', indices: <int>[1, 2]),
    (label: 'דקדוקי סופרים', indices: <int>[3, 4, 5, 6]),
  ];

  @override
  void initState() {
    super.initState();
    FocusRepository().moreScreenFocusNode.addListener(_onMoreFocusChange);
    _tabController = TabController(length: _tabs.length, vsync: this)
      ..addListener(() {
        if (!_tabController.indexIsChanging) {
          setState(() => _selectedIndex = _tabController.index);
          _contentFocusNode.requestFocus();
        }
      });

    _pages = [
      BlocBuilder<CalendarCubit, CalendarState>(
        builder: (context, _) => const CalendarWidget(),
      ),
      ShamorZachorWidget(onTitleChanged: (_) {}),
      const PersonalNotesManagerScreen(),
      const MeasurementConverterScreen(),
      GematriaSearchScreen(key: _gematriaKey),
      const AramaicDictionaryScreen(),
      const AcronymsDictionaryScreen(),
    ];
  }

  void _changeTab(int index) {
    setState(() {
      _selectedIndex = index;
      _showMobileMenu = false;
    });
    _tabController.animateTo(index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _contentFocusNode.requestFocus();
    });
  }

  /// Reset to calendar page — public method for external access
  void resetToCalendar() {
    if (_tabController.index != 0) {
      _tabController.animateTo(0);
      setState(() {
        _selectedIndex = 0;
        _showMobileMenu = true;
      });
    }
  }

  void _onMoreFocusChange() {
    if (FocusRepository().moreScreenFocusNode.hasFocus && mounted) {
      _contentFocusNode.requestFocus();
    }
  }

  @override
  void dispose() {
    FocusRepository().moreScreenFocusNode.removeListener(_onMoreFocusChange);
    _tabController.dispose();
    _contentFocusNode.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  // ── Tab widget builder ─────────────────────────────────────────────────────
  Widget _buildTabWidget(_TabInfo tab) {
    final isSelected = _tabs.indexOf(tab) == _selectedIndex;
    // אנימציית Active Indicator: scale + fade בין regular ל-filled (M3)
    final iconWidget = tab.imageIcon != null
        ? ImageIcon(AssetImage(tab.imageIcon!), size: 20)
        : AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            switchInCurve: Curves.easeInOutCubicEmphasized,
            switchOutCurve: Curves.easeInOutCubicEmphasized,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(scale: animation, child: child),
            ),
            child: Icon(
              isSelected && tab.iconFilled != null ? tab.iconFilled : tab.icon,
              size: 20,
              key: ValueKey<bool>(isSelected),
            ),
          );
    return Tab(text: tab.label, icon: iconWidget);
  }

  // ── Mobile menu ────────────────────────────────────────────────────────────
  Widget _buildMobileMenu(Color bgColor) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('כלים'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppTokens.spaceMD),
        children: [
          for (final group in _mobileGroups) ...[
            SettingsCard(
              title: group.label,
              children: [
                for (final idx in group.indices)
                  ListTile(
                    leading: _tabs[idx].imageIcon != null
                        ? ImageIcon(
                            AssetImage(_tabs[idx].imageIcon!),
                            size: 22,
                            color: cs.primary,
                          )
                        : Icon(_tabs[idx].icon, color: cs.primary),
                    title: Text(_tabs[idx].label),
                    trailing: const RtlIcon(Icons.chevron_left),
                    onTap: () => _changeTab(idx),
                  ),
              ],
            ),
            const SizedBox(height: AppTokens.spaceSM),
          ],
        ],
      ),
    );
  }

  // ── Mobile content page ────────────────────────────────────────────────────
  Widget _buildMobileContent(Color bgColor) {
    return KeyboardNavigator(
      currentTabIndex: _selectedIndex,
      totalTabs: _tabs.length,
      onTabChange: _changeTab,
      onBack: () => setState(() => _showMobileMenu = true),
      child: Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(
          backgroundColor: bgColor,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          title: Text(_tabs[_selectedIndex].label),
          leading: Tooltip(
            message: 'חזור (Backspace)',
            child: IconButton(
              icon: const RtlIcon(Icons.arrow_forward),
              onPressed: () => setState(() => _showMobileMenu = true),
            ),
          ),
        ),
        body: Focus(
          focusNode: _contentFocusNode,
          child: _pages[_selectedIndex],
        ),
      ),
    );
  }

  // ── Desktop layout ─────────────────────────────────────────────────────────
  Widget _buildDesktop(Color bgColor) {
    final cs = Theme.of(context).colorScheme;

    return KeyboardNavigator(
      currentTabIndex: _selectedIndex,
      totalTabs: _tabs.length,
      onTabChange: _changeTab,
      child: Scaffold(
        backgroundColor: bgColor,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── שורת טאבים M3 ─────────────────────────────────────────────
            ColoredBox(
              color: bgColor,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.spaceMD,
                  vertical: AppTokens.spaceXS,
                ),
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.center,
                  dividerColor: Colors.transparent,
                  dividerHeight: 0,
                  labelColor: cs.onSecondaryContainer,
                  unselectedLabelColor: cs.onSurfaceVariant,
                  indicator: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppTokens.radiusMD),
                    color: cs.secondaryContainer,
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  splashBorderRadius: BorderRadius.circular(AppTokens.radiusMD),
                  tabs: _tabs.map(_buildTabWidget).toList(),
                ),
              ),
            ),
            // ── תוכן טאבים ───────────────────────────────────────────────
            Expanded(
              child: Focus(
                focusNode: _contentFocusNode,
                child: TabBarView(
                  controller: _tabController,
                  children: _pages,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final bgColor = AppSurfaces.panelBackground(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < LayoutBreakpoints.compact;

        Widget content;
        if (isMobile) {
          content = _showMobileMenu
              ? _buildMobileMenu(bgColor)
              : _buildMobileContent(bgColor);
        } else {
          content = _buildDesktop(bgColor);
        }

        // ── אנימציה בין wide ↔ narrow ──────────────────────────────────────
        return AnimatedSwitcher(
          duration: AppTokens.animNormal,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeInOut,
            ),
            child: child,
          ),
          child: KeyedSubtree(
            key: ValueKey(isMobile
                ? 'mobile-${_showMobileMenu ? "menu" : "content-$_selectedIndex"}'
                : 'desktop'),
            child: content,
          ),
        );
      },
    );
  }
}

// ── _TabInfo ───────────────────────────────────────────────────────────────────

class _TabInfo {
  final String label;
  final IconData? icon;
  final IconData? iconFilled;
  final String? imageIcon;

  const _TabInfo({
    required this.label,
    this.icon,
    this.iconFilled,
    this.imageIcon,
  });
}
