import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/tools/calendar/ulits/calendar_cubit.dart';
import 'package:otzaria/settings/tabs/settings_tabs_exports.dart';
import 'package:otzaria/settings/services/safer_mode/protected_settings_wrapper.dart';
import 'package:otzaria/widgets/keyboard_navigator.dart';
import 'package:otzaria/settings/settings_card.dart';
import 'package:otzaria/theme/layout_tokens.dart';

/// רוחב מקסימלי לתוכן ההגדרות — מרכוז על מסכים רחבים
const double kSettingsContentMaxWidth = 860.0;

class MySettingsScreen extends StatefulWidget {
  const MySettingsScreen({super.key});

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
  void dispose() {
    _contentFocusNode.dispose();
    _contentScrollController.dispose();
    super.dispose();
  }

  void _changeTab(int index) {
    setState(() => _selectedIndex = index);
    _contentFocusNode.requestFocus();
  }

  // ── הגדרת רשימת הטאבים ────────────────────────────────────────────────────
  late final List<
          ({String label, IconData icon, Widget Function() pageBuilder})>
      _tabsData = [
    (
      label: 'מראה',
      icon: FluentIcons.paint_brush_24_regular,
      pageBuilder: () => const DesignSettingsTab(),
    ),
    (
      label: 'כתב',
      icon: FluentIcons.book_24_regular,
      pageBuilder: () => const TextSettingsTab(),
    ),
    (
      label: 'ספריה',
      icon: FluentIcons.library_24_regular,
      pageBuilder: () => const LibrarySettingsTab(),
    ),
    (
      label: 'כלים',
      icon: FluentIcons.wrench_24_regular,
      pageBuilder: () => ToolsSettingsTab(
            calendarCubit: context.read<CalendarCubit>(),
          ),
    ),
    (
      label: 'קיצורים',
      icon: FluentIcons.keyboard_24_regular,
      pageBuilder: () => const ShortcutsSettingsTab(),
    ),
    (
      label: 'אוצריא',
      icon: FluentIcons.settings_24_regular,
      pageBuilder: () => const SystemSettingsTab(),
    ),
    (
      label: 'חכמי לב',
      icon: FluentIcons.people_team_24_regular,
      pageBuilder: () => const AboutDevTab(),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // [תיקון] רקע שחור במצב כהה — הכרטיסים בולטים מעל הרקע
    final bgColor = isDark
        ? Colors.black
        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.28);

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
                                  trailing: const Icon(Icons.chevron_left),
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
                          icon: const Icon(Icons.arrow_forward),
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
                  // [תיקון גלילה] גלגל עכבר מכל מקום (כולל sidebar) גולל את התוכן
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
                                  itemBuilder: (context, index) {
                                    final isSelected = _selectedIndex == index;
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 2),
                                      child: Material(
                                        color: isSelected
                                            ? colorScheme.primary
                                                .withValues(alpha: 0.14)
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(28),
                                        child: InkWell(
                                          onTap: () => _changeTab(index),
                                          borderRadius:
                                              BorderRadius.circular(28),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 14, vertical: 10),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  _tabsData[index].icon,
                                                  size: 20,
                                                  color: isSelected
                                                      ? colorScheme.primary
                                                      : colorScheme
                                                          .onSurfaceVariant,
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Text(
                                                    _tabsData[index].label,
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      fontWeight: isSelected
                                                          ? FontWeight.bold
                                                          : FontWeight.normal,
                                                      color: isSelected
                                                          ? colorScheme.primary
                                                          : colorScheme
                                                              .onSurfaceVariant,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
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
// [שינוי] StatefulWidget — בקשת focus בכניסה לטאב חדש
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
    // בקשת focus כדי שניווט מקלדת יעבוד מיד
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
            constraints:
                const BoxConstraints(maxWidth: kSettingsContentMaxWidth),
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
