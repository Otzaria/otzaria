// lib/tools/more_screen.dart
//
// שינויים:
//  • מסך צר: תפריט סגנון הגדרות (SettingsCard קבוצות + ListTile) → tap → תוכן + חזרה
//  • מסך רחב: TabBar רגיל (ללא שינוי)
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

class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen>
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
    const _TabInfo(label: 'לוח שנה', icon: FluentIcons.calendar_24_regular),
    const _TabInfo(
        label: 'שמור וזכור',
        icon: null,
        imageIcon: 'assets/icon/שמור וזכור שחור ריק.png'),
    const _TabInfo(label: 'מדות ושיעורים', icon: FluentIcons.ruler_24_regular),
    const _TabInfo(label: 'הערות אישיות', icon: FluentIcons.note_24_regular),
    const _TabInfo(label: 'גימטריה', icon: FluentIcons.calculator_24_regular),
    const _TabInfo(
        label: 'מילון ארמי-עברי', icon: FluentIcons.translate_24_regular),
    const _TabInfo(
        label: 'ראשי תיבות', icon: FluentIcons.text_quote_24_regular),
  ];

  // ── קבוצות תפריט מובייל ───────────────────────────────────────────────────
  static const _mobileGroups = [
    (label: 'יומן וזמן', indices: <int>[0, 1]),
    (label: 'כלים', indices: <int>[2, 4]),
    (label: 'מילונים', indices: <int>[5, 6]),
    (label: 'אישי', indices: <int>[3]),
  ];

  @override
  void initState() {
    super.initState();
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
      const MeasurementConverterScreen(),
      const PersonalNotesManagerScreen(),
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

  @override
  void dispose() {
    _tabController.dispose();
    _contentFocusNode.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  // ── Tab widget builder ─────────────────────────────────────────────────────
  Widget _buildTabWidget(_TabInfo tab) {
    final icon = tab.imageIcon != null
        ? ImageIcon(AssetImage(tab.imageIcon!), size: 20)
        : Icon(tab.icon, size: 20);
    return SizedBox(
      width: 100,
      child: Tab(text: tab.label, icon: icon),
    );
  }

  // ── Mobile menu ────────────────────────────────────────────────────────────
  Widget _buildMobileMenu(Color bgColor) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
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
                    trailing: const Icon(Icons.chevron_left),
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
          elevation: 0,
          title: Text(_tabs[_selectedIndex].label),
          leading: Tooltip(
            message: 'חזור (Backspace)',
            child: IconButton(
              icon: const Icon(Icons.arrow_forward),
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
    return KeyboardNavigator(
      currentTabIndex: _selectedIndex,
      totalTabs: _tabs.length,
      onTabChange: _changeTab,
      child: Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(
          backgroundColor: bgColor,
          toolbarHeight: 72,
          title: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.center,
            tabs: _tabs.map(_buildTabWidget).toList(),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1.0),
            child: Container(
              color: Theme.of(context).dividerColor,
              height: 1.0,
            ),
          ),
        ),
        body: Focus(
          focusNode: _contentFocusNode,
          child: TabBarView(
            controller: _tabController,
            children: _pages,
          ),
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

        if (isMobile) {
          return _showMobileMenu
              ? _buildMobileMenu(bgColor)
              : _buildMobileContent(bgColor);
        }

        return _buildDesktop(bgColor);
      },
    );
  }
}

// ── _TabInfo ───────────────────────────────────────────────────────────────────

class _TabInfo {
  final String label;
  final IconData? icon;
  final String? imageIcon;

  const _TabInfo({
    required this.label,
    this.icon,
    this.imageIcon,
  });
}
