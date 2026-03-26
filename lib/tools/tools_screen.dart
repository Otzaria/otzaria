import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/services/safer_mode/protected_settings_wrapper.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/tools/measurement_converter/measurement_converter_screen.dart';
import 'package:otzaria/tools/gematria/gematria_search_screen.dart';
import 'package:otzaria/tools/aramaic_dictionary/aramaic_dictionary_screen.dart';
import 'package:otzaria/tools/acronyms_dictionary/acronyms_dictionary_screen.dart';
import 'package:otzaria/tools/shamor_zachor/shamor_zachor.dart';
import 'package:otzaria/tools/calendar/calendar_screen.dart';
import 'package:otzaria/personal_notes/view/personal_notes_screen.dart';
import 'package:otzaria/widgets/keyboard_navigator.dart';
import 'package:otzaria/widgets/rtl_icon.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/widgets/sidebar_nav_item.dart';

final GlobalKey<MoreScreenState> moreScreenKey = GlobalKey<MoreScreenState>();

class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  @override
  State<MoreScreen> createState() => MoreScreenState();
}

class MoreScreenState extends State<MoreScreen>
    with AutomaticKeepAliveClientMixin {
  final GlobalKey _calendarWidgetKey = GlobalKey();
  final GlobalKey _measurementConverterKey = GlobalKey();
  final GlobalKey _gematriaKey = GlobalKey();
  final GlobalKey _aramaicDictionaryKey = GlobalKey();
  final GlobalKey _acronymsDictionaryKey = GlobalKey();
  late final List<Widget> _pages;

  // ── מצב ─────────────────────────────────────────────────────────────────
  int _selectedIndex = 0;
  bool _showMobileMenu = true;

  // ── FocusNode לאזור התוכן ────────────────────────────────────────────────
  final FocusNode _contentFocusNode = FocusNode();
  final ScrollController _contentScrollController = ScrollController();

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
        builder: (context, _) => CalendarWidget(key: _calendarWidgetKey),
      ),
      ShamorZachorWidget(onTitleChanged: (_) {}),
      const PersonalNotesManagerScreen(),
      MeasurementConverterScreen(key: _measurementConverterKey),
      GematriaSearchScreen(key: _gematriaKey),
      AramaicDictionaryScreen(key: _aramaicDictionaryKey),
      AcronymsDictionaryScreen(key: _acronymsDictionaryKey),
    ];
  }

  Widget _buildDesktopPage(int index) {
    // pages 4–6 have their own AppTopBar and handle internal centering themselves
    return _pages[index];
  }

  void _changeTab(int index) {
    if (_selectedIndex == index && !_showMobileMenu) {
      _requestFocusForSelectedTab();
      return;
    }

    setState(() {
      _selectedIndex = index;
      _showMobileMenu = false;
    });
    _requestFocusForSelectedTab();
  }

  /// Reset to calendar page — public method for external access
  void resetToCalendar() {
    setState(() {
      _selectedIndex = 0;
      _showMobileMenu = true;
    });
    _requestFocusForSelectedTab();
  }

  void _onMoreFocusChange() {
    if (FocusRepository().moreScreenFocusNode.hasFocus && mounted) {
      _requestFocusForSelectedTab();
    }
  }

  void _requestFocusForSelectedTab() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      FocusManager.instance.primaryFocus?.unfocus();
      _contentFocusNode.requestFocus();
      switch (_selectedIndex) {
        case 0:
          final calendarState = _calendarWidgetKey.currentState;
          if (calendarState != null) {
            (calendarState as dynamic).requestKeyboardFocus();
          }
          break;
        case 3:
          final measurementState = _measurementConverterKey.currentState;
          if (measurementState != null) {
            (measurementState as dynamic).requestKeyboardFocus();
          }
          break;
        case 4:
          final gematriaState = _gematriaKey.currentState;
          if (gematriaState != null) {
            (gematriaState as dynamic).requestKeyboardFocus();
          }
          break;
        case 5:
          final aramaicState = _aramaicDictionaryKey.currentState;
          if (aramaicState != null) {
            (aramaicState as dynamic).requestKeyboardFocus();
          }
          break;
        case 6:
          final acronymsState = _acronymsDictionaryKey.currentState;
          if (acronymsState != null) {
            (acronymsState as dynamic).requestKeyboardFocus();
          }
          break;
      }
    });
  }

  @override
  void dispose() {
    FocusRepository().moreScreenFocusNode.removeListener(_onMoreFocusChange);
    _contentFocusNode.dispose();
    _contentScrollController.dispose();
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
            _MobileGroupCard(
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
          child: ColoredBox(
            color: bgColor,
            child: _pages[_selectedIndex],
          ),
        ),
      ),
    );
  }

  // ── Desktop layout — Top tabs + content ───────────────────────────────────
  Widget _buildDesktop(Color bgColor) {
    return KeyboardNavigator(
      currentTabIndex: _selectedIndex,
      totalTabs: _tabs.length,
      onTabChange: _changeTab,
      onBack: null,
      child: Scaffold(
        backgroundColor: bgColor,
        body: Listener(
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
          child: Column(
            children: [
              ColoredBox(
                color: bgColor,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: LayoutConstraints.panelContentMaxWidth,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(
                        top: AppTokens.spaceXS,
                        bottom: AppTokens.spaceXS,
                        right: AppTokens.spaceMD,
                        left: AppTokens.spaceMD,
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: BlocBuilder<SettingsBloc, SettingsState>(
                          builder: (context, settingsState) => Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (int index = 0;
                                index < _tabs.length;
                                index++) ...[
                              TopNavItem(
                                icon: _tabs[index].icon,
                                iconFilled: _tabs[index].iconFilled,
                                imageAsset: _tabs[index].imageIcon,
                                label: _tabs[index].label,
                                isSelected: _selectedIndex == index,
                                onTap: () => _changeTab(index),
                                compact: settingsState.compactMenuMode,
                              ),
                              if (index < _tabs.length - 1)
                                const SizedBox(width: AppTokens.spaceXS),
                            ],
                          ],
                        ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: PrimaryScrollController(
                  controller: _contentScrollController,
                  child: Focus(
                    focusNode: _contentFocusNode,
                    child: ColoredBox(
                      color: bgColor,
                      child: IndexedStack(
                        index: _selectedIndex,
                        children: [
                          for (int index = 0; index < _pages.length; index++)
                            _buildDesktopPage(index),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final bgColor = AppSurfaces.panelBackground(context);

    return ProtectedSettingsWrapper(
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Theme(
          data: Theme.of(context).copyWith(
            scaffoldBackgroundColor: bgColor,
            canvasColor: bgColor,
          ),
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
        ),
      ),
    );
  }
}

class _MobileGroupCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _MobileGroupCard({
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              title,
              textDirection: TextDirection.rtl,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
          ),
          ...children,
        ],
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
