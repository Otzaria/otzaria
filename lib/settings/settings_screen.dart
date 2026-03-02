import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/tools/calendar/ulits/calendar_cubit.dart';
import 'package:otzaria/settings/tabs/settings_tabs_exports.dart';
import 'package:otzaria/settings/services/safer_mode/protected_settings_wrapper.dart';

/// רוחב מקסימלי לתוכן ההגדרות — מרכוז על מסכים רחבים
const double kSettingsContentMaxWidth = 860.0;

class MySettingsScreen extends StatefulWidget {
  const MySettingsScreen({super.key});

  @override
  State<MySettingsScreen> createState() => _MySettingsScreenState();
}

class _MySettingsScreenState extends State<MySettingsScreen> {
  int _selectedIndex = 0;
  bool _showMobileMenu = true; // true = show menu, false = show content

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
      // תיקון באג: מעבירים את CalendarCubit מה-context הנוכחי לטאב כלים.
      // בלי זה, שינויים בהגדרות לוח שנה לא נשמרים כשההגדרות נפתחות
      // כ-route חדש שה-context שלו לא מכיל את CalendarCubit.
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // צבע רקע אחיד לסרגל הצדדי ולאזור התוכן — ללא קו גבול גלוי ביניהם
    final bgColor = colorScheme.surfaceContainerHighest.withValues(alpha: 0.28);

    return ProtectedSettingsWrapper(
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isMobile = constraints.maxWidth < 600;

            // ── מצב מובייל ────────────────────────────────────────────────
            if (isMobile) {
              // במובייל: אם _showMobileMenu = true, הצג רשימת טאבים
              // אחרת, הצג את התוכן של הטאב הנבחר
              if (_showMobileMenu) {
                return Scaffold(
                  backgroundColor: bgColor,
                  appBar: AppBar(
                    backgroundColor: bgColor,
                    elevation: 0,
                    title: const Text('הגדרות'),
                  ),
                  body: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _tabsData.length,
                    itemBuilder: (context, index) {
                      return Card(
                        color: colorScheme.surface,
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: colorScheme.outlineVariant
                                .withValues(alpha: 0.4),
                          ),
                        ),
                        child: ListTile(
                          leading: Icon(_tabsData[index].icon,
                              color: colorScheme.primary),
                          title: Text(_tabsData[index].label),
                          trailing: const Icon(Icons.chevron_left),
                          onTap: () {
                            setState(() {
                              _selectedIndex = index;
                              _showMobileMenu = false;
                            });
                          },
                        ),
                      );
                    },
                  ),
                );
              } else {
                // הצגת תוכן הטאב הנבחר
                return Scaffold(
                  backgroundColor: bgColor,
                  appBar: AppBar(
                    backgroundColor: bgColor,
                    elevation: 0,
                    title: Text(_tabsData[_selectedIndex].label),
                    leading: IconButton(
                      icon: const Icon(Icons.arrow_forward),
                      onPressed: () {
                        setState(() {
                          _showMobileMenu = true;
                        });
                      },
                    ),
                  ),
                  body: _tabsData[_selectedIndex].pageBuilder(),
                );
              }
            }

            // ── מצב דסקטופ: sidebar + תוכן ──────────────────────────────
            return Scaffold(
              backgroundColor: bgColor,
              body: Row(
                children: [
                  // ── Sidebar ────────────────────────────────────────────
                  SizedBox(
                    width: 210,
                    child: Container(
                      color: bgColor, // אותו צבע — ללא גבול גלוי
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
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 2),
                                  child: Material(
                                    color: isSelected
                                        ? colorScheme.primary
                                            .withValues(alpha: 0.14)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(28),
                                    child: InkWell(
                                      onTap: () => setState(
                                          () => _selectedIndex = index),
                                      borderRadius: BorderRadius.circular(28),
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

                  // ── אזור תוכן ─────────────────────────────────────────
                  Expanded(
                    child: _SettingsContentPane(
                      key: ValueKey(_selectedIndex),
                      label: _tabsData[_selectedIndex].label,
                      bgColor: bgColor,
                      child: _tabsData[_selectedIndex].pageBuilder(),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// אזור התוכן — רקע אחיד עם הסרגל הצדדי, מרכוז ב-[kSettingsContentMaxWidth]
class _SettingsContentPane extends StatelessWidget {
  final String label;
  final Widget child;
  final Color bgColor;

  const _SettingsContentPane({
    required this.label,
    required this.child,
    required this.bgColor,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: bgColor,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kSettingsContentMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(
                    top: 28, right: 16, left: 16, bottom: 4),
                child: Text(
                  label,
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}
