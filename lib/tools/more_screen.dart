// lib/tools/more_screen.dart
//
// שינויים:
//  • מסך צר: תפריט סגנון הגדרות (SettingsCard קבוצות + ListTile) → tap → תוכן + חזרה
//  • מסך רחב: Sidebar M3 (כמו settings_screen) — SidebarNavItem, רוחב 210, pill עגול
//  • IndexedStack שומר מצב כל הכלים (ללא TabController)
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
import 'package:otzaria/tools/calendar/view/calendar_screen.dart';
import 'package:otzaria/personal_notes/view/personal_notes_screen.dart';
import 'package:otzaria/widgets/keyboard_navigator.dart';
import 'package:otzaria/widgets/rtl_icon.dart';
import 'package:otzaria/widgets/sidebar_nav_item.dart';
import 'package:otzaria/core/focus_repository.dart';

final GlobalKey<MoreScreenState> moreScreenKey = GlobalKey<MoreScreenState>();

class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  @override
  State<MoreScreen> createState() => MoreScreenState();
}

class MoreScreenState extends State<MoreScreen>
    with AutomaticKeepAliveClientMixin {
  final GlobalKey<GematriaSearchScreenState> _gematriaKey =
      GlobalKey<GematriaSearchScreenState>();
  late final List<Widget> _pages;

  // ── מצב ─────────────────────────────────────────────────────────────────
  int _selectedIndex = 0;
  bool _showMobileMenu = true;

  // ── FocusNode לאזור התוכן ────────────────────────────────────────────────
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _contentFocusNode.requestFocus();
    });
  }

  /// Reset to calendar page — public method for external access
  void resetToCalendar() {
    setState(() {
      _selectedIndex = 0;
      _showMobileMenu = true;
    });
  }

  void _onMoreFocusChange() {
    if (FocusRepository().moreScreenFocusNode.hasFocus && mounted) {
      _contentFocusNode.requestFocus();
    }
  }

  @override
  void dispose() {
    FocusRepository().moreScreenFocusNode.removeListener(_onMoreFocusChange);
    _contentFocusNode.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

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

  // ── Desktop layout — Sidebar + content ────────────────────────────────────
  Widget _buildDesktop(Color bgColor) {
    return KeyboardNavigator(
      currentTabIndex: _selectedIndex,
      totalTabs: _tabs.length,
      onTabChange: _changeTab,
      child: Scaffold(
        backgroundColor: bgColor,
        body: Row(
          children: [
            // ── Sidebar ────────────────────────────────────────────────────
            SizedBox(
              width: 210,
              child: Container(
                color: bgColor,
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(
                          right: 12, left: 12, bottom: 20),
                      child: Text(
                        'כלים',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _tabs.length,
                        itemBuilder: (context, index) => SidebarNavItem(
                          icon: _tabs[index].icon,
                          iconFilled: _tabs[index].iconFilled,
                          imageAsset: _tabs[index].imageIcon,
                          label: _tabs[index].label,
                          isSelected: _selectedIndex == index,
                          onTap: () => _changeTab(index),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── אזור תוכן — IndexedStack שומר מצב כל הכלים ───────────────
            Expanded(
              child: Focus(
                focusNode: _contentFocusNode,
                child: Container(
                  color: bgColor,
                  child: IndexedStack(
                    index: _selectedIndex,
                    children: _pages,
                  ),
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
    final toolsTheme = Theme.of(context).copyWith(
      scaffoldBackgroundColor: bgColor,
      canvasColor: bgColor,
    );

    return Theme(
      data: toolsTheme,
      child: LayoutBuilder(
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
      ),
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
