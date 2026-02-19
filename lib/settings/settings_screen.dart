import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/settings/tabs/settings_tabs.dart';
import 'package:otzaria/settings/protected_settings_wrapper.dart';

/// רוחב מקסימלי לתוכן ההגדרות — מרכוז על מסכים רחבים
const double kSettingsContentMaxWidth = 860.0;

class MySettingsScreen extends StatefulWidget {
  const MySettingsScreen({super.key});

  @override
  State<MySettingsScreen> createState() => _MySettingsScreenState();
}

class _MySettingsScreenState extends State<MySettingsScreen> {
  int _selectedIndex = 0;

  // ── הגדרת רשימת הטאבים ────────────────────────────────────────────────────
  late final List<
          ({String label, IconData icon, Widget Function() pageBuilder})>
      _tabsData = [
    (
      label: 'עיצוב',
      icon: FluentIcons.paint_brush_24_regular,
      pageBuilder: () => const AppearanceSettingsTab(),
    ),
    (
      label: 'תצוגת הספרים',
      icon: FluentIcons.book_24_regular,
      pageBuilder: () => const ReadingSettingsTab(),
    ),
    (
      label: 'ספריה',
      icon: FluentIcons.library_24_regular,
      pageBuilder: () => const LibrarySettingsTab(),
    ),
    (
      label: 'לוח שנה',
      icon: FluentIcons.calendar_24_regular,
      pageBuilder: () => const CalendarSettingsTab(),
    ),
    (
      label: 'גימטריות',
      icon: FluentIcons.calculator_24_regular,
      pageBuilder: () => const GematriaSettingsTab(),
    ),
    (
      label: 'גיבוי',
      icon: FluentIcons.arrow_sync_24_regular,
      pageBuilder: () => const BackupSettingsTab(),
    ),
    (
      label: 'מתקדם',
      icon: FluentIcons.settings_24_regular,
      pageBuilder: () => const AdvancedSettingsTab(),
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
                          color:
                              colorScheme.outlineVariant.withValues(alpha: 0.4),
                        ),
                      ),
                      child: ListTile(
                        leading: Icon(_tabsData[index].icon,
                            color: colorScheme.primary),
                        title: Text(_tabsData[index].label),
                        trailing: const Icon(Icons.chevron_left),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => Scaffold(
                              backgroundColor: bgColor,
                              appBar: AppBar(
                                backgroundColor: bgColor,
                                elevation: 0,
                                title: Text(_tabsData[index].label),
                              ),
                              body: _tabsData[index].pageBuilder(),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              );
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
