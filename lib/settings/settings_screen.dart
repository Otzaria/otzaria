import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/settings/tabs/settings_tabs_exports.dart';
import 'package:otzaria/settings/services/safer_mode/protected_settings_wrapper.dart';
import 'package:otzaria/widgets/keyboard_navigator.dart';
import 'package:otzaria/settings/settings_card.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/rtl_icon.dart';
import 'package:otzaria/widgets/sidebar_nav_item.dart';

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

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_handleRequestedTab);
    _applyRequestedTab(widget.controller?.requestedTab);
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_handleRequestedTab);
    _contentFocusNode.dispose();
    _contentScrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MySettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_handleRequestedTab);
      widget.controller?.addListener(_handleRequestedTab);
      _applyRequestedTab(widget.controller?.requestedTab);
    }
  }

  void _changeTab(int index) {
    setState(() => _selectedIndex = index);
    _contentFocusNode.requestFocus();
  }

  void _handleRequestedTab() {
    _applyRequestedTab(widget.controller?.requestedTab);
  }

  void _applyRequestedTab(SettingsTab? tab) {
    if (tab == null) return;

    final tabIndex = switch (tab) {
      SettingsTab.design => 0,
      SettingsTab.text => 1,
      SettingsTab.library => 2,
      SettingsTab.tools => 3,
      SettingsTab.shortcuts => 4,
      SettingsTab.system => 5,
      SettingsTab.about => 6,
    };

    if (!mounted) {
      _selectedIndex = tabIndex;
      _showMobileMenu = false;
      return;
    }

    setState(() {
      _selectedIndex = tabIndex;
      _showMobileMenu = false;
    });
    _contentFocusNode.requestFocus();
  }

  // ── הגדרת רשימת הטאבים ────────────────────────────────────────────────────
  late final List<
      ({
        String label,
        IconData icon,
        IconData iconFilled,
        Widget Function() pageBuilder
      })> _tabsData = [
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
      label: 'קיצורים',
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
      pageBuilder: () => const AboutDevTab(),
    ),
  ];

  // ── קבוצות למובייל ────────────────────────────────────────────────────────
  static const _mobileGroups = [
    (label: 'תצוגה ותוכן', indices: <int>[0, 1, 2]),
    (label: 'כלים', indices: <int>[3, 4]),
    (label: 'מערכת', indices: <int>[5, 6]),
  ];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bgColor = AppSurfaces.panelBackground(context);

    return ProtectedSettingsWrapper(
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isMobile = constraints.maxWidth < LayoutBreakpoints.compact;

            // ── מצב מובייל ────────────────────────────────────────────────
            if (isMobile) {
              if (_showMobileMenu) {
                return KeyboardNavigator(
                  currentTabIndex: _selectedIndex,
                  totalTabs: _tabsData.length,
                  onTabChange: (i) => setState(() => _selectedIndex = i),
                  onBack: null,
                  child: Scaffold(
                    backgroundColor: bgColor,
                    appBar: AppBar(
                      backgroundColor: bgColor,
                      elevation: 0,
                      title: const Text('הגדרות'),
                    ),
                    body: ListView(
                      padding: const EdgeInsets.all(12),
                      children: [
                        for (final group in _mobileGroups) ...[
                          SettingsCard(
                            title: group.label,
                            children: [
                              for (final idx in group.indices)
                                ListTile(
                                  leading: Icon(_tabsData[idx].icon,
                                      color: colorScheme.primary),
                                  title: Text(_tabsData[idx].label),
                                  trailing: const RtlIcon(Icons.chevron_left),
                                  onTap: () {
                                    setState(() {
                                      _selectedIndex = idx;
                                      _showMobileMenu = false;
                                    });
                                  },
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ),
                  ),
                );
              } else {
                return KeyboardNavigator(
                  currentTabIndex: _selectedIndex,
                  totalTabs: _tabsData.length,
                  onTabChange: _changeTab,
                  onBack: () => setState(() => _showMobileMenu = true),
                  child: Scaffold(
                    backgroundColor: bgColor,
                    appBar: AppBar(
                      backgroundColor: bgColor,
                      elevation: 0,
                      title: Text(_tabsData[_selectedIndex].label),
                      leading: Tooltip(
                        message: 'חזור (Backspace)',
                        child: IconButton(
                          icon: const RtlIcon(Icons.arrow_forward),
                          onPressed: () =>
                              setState(() => _showMobileMenu = true),
                        ),
                      ),
                    ),
                    body: _tabsData[_selectedIndex].pageBuilder(),
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
                  // גלגל עכבר מכל מקום (כולל sidebar) גולל את התוכן
                  onPointerSignal: (event) {
                    if (event is PointerScrollEvent &&
                        _contentScrollController.hasClients) {
                      final newOffset = _contentScrollController.offset +
                          event.scrollDelta.dy;
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
                              horizontal: 10, vertical: 28),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(
                                    right: 12, left: 12, bottom: 20),
                                child: Text(
                                  'הגדרות',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                              ),
                              Expanded(
                                child: ListView.builder(
                                  itemCount: _tabsData.length,
                                  itemBuilder: (context, index) =>
                                      SidebarNavItem(
                                    icon: _tabsData[index].icon,
                                    iconFilled: _tabsData[index].iconFilled,
                                    label: _tabsData[index].label,
                                    isSelected: _selectedIndex == index,
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
                        child: PrimaryScrollController(
                          controller: _contentScrollController,
                          child: _SettingsContentPane(
                            key: ValueKey(_selectedIndex),
                            label: _tabsData[_selectedIndex].label,
                            bgColor: bgColor,
                            focusNode: _contentFocusNode,
                            child: _tabsData[_selectedIndex].pageBuilder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ── _SettingsContentPane ───────────────────────────────────────────────────────
class _SettingsContentPane extends StatefulWidget {
  final String label;
  final Widget child;
  final Color bgColor;
  final FocusNode focusNode;

  const _SettingsContentPane({
    required this.label,
    required this.child,
    required this.bgColor,
    required this.focusNode,
    super.key,
  });

  @override
  State<_SettingsContentPane> createState() => _SettingsContentPaneState();
}

class _SettingsContentPaneState extends State<_SettingsContentPane> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.focusNode.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      child: Container(
        color: widget.bgColor,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
                maxWidth: LayoutConstraints.panelContentMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(
                      top: 28, right: 16, left: 16, bottom: 4),
                  child: Text(
                    widget.label,
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(child: widget.child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
