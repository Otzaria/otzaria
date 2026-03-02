import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:window_manager/window_manager.dart';
import 'package:otzaria/settings/engine/settings_engine_exports.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/settings/settings_card.dart';
import 'package:otzaria/widgets/custom_ui_components.dart';

enum _SidebarMode { pinned, openOnBook, closed }

/// טאב הגדרות עיצוב
class DesignSettingsTab extends StatelessWidget {
  const DesignSettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, state) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // מסך מלא (רק בדסקטופ)
              if (!(Platform.isAndroid || Platform.isIOS))
                SettingsCard(
                  title: 'תצוגה',
                  children: [
                    ListTile(
                      leading: Icon(state.isFullscreen
                          ? FluentIcons.full_screen_minimize_24_regular
                          : FluentIcons.full_screen_maximize_24_regular),
                      title:
                          const Text('מסך מלא', style: TextStyle(fontSize: 16)),
                      subtitle: const Text('החלף מצב מסך מלא',
                          style: TextStyle(fontSize: 13)),
                      trailing: Switch(
                        value: state.isFullscreen,
                        onChanged: (value) async {
                          context
                              .read<SettingsBloc>()
                              .add(UpdateIsFullscreen(value));
                          await windowManager.setFullScreen(value);
                        },
                      ),
                    ),
                  ],
                ),

              if (!(Platform.isAndroid || Platform.isIOS))
                const SizedBox(height: 16),

              // מצב כהה וצבע בסיס
              SettingsCard(
                title: 'ערכת נושא',
                children: [
                  SwitchListTile(
                    secondary: const Icon(FluentIcons.settings_24_regular),
                    title: const Text('מעקב אחר צבע המערכת',
                        style: TextStyle(fontSize: 16)),
                    subtitle: Text(
                        state.followSystemTheme ? 'מופעל' : 'לא מופעל',
                        style: const TextStyle(fontSize: 13)),
                    value: state.followSystemTheme,
                    onChanged: (value) {
                      context
                          .read<SettingsBloc>()
                          .add(UpdateFollowSystemTheme(value));
                    },
                  ),
                  SwitchListTile(
                    secondary: const Icon(FluentIcons.weather_moon_24_regular),
                    title:
                        const Text('מצב כהה', style: TextStyle(fontSize: 16)),
                    subtitle: Text(state.isDarkMode ? 'מופעל' : 'לא מופעל',
                        style: const TextStyle(fontSize: 13)),
                    value: state.isDarkMode,
                    onChanged: state.followSystemTheme
                        ? null
                        : (value) {
                            context
                                .read<SettingsBloc>()
                                .add(UpdateDarkMode(value));
                          },
                  ),
                  ClipRect(
                    child: Align(
                      alignment: Alignment.topCenter,
                      heightFactor: 0.92,
                      child: ColorPickerSettingsTile(
                        key: ValueKey(
                            'color-picker-${state.isDarkMode ? 'dark' : 'light'}'),
                        title: 'צבע בסיס',
                        leading: const Icon(FluentIcons.color_24_regular),
                        settingKey: state.isDarkMode
                            ? 'key-dark-swatch-color'
                            : 'key-swatch-color',
                        onChange: (color) {
                          if (state.isDarkMode) {
                            context
                                .read<SettingsBloc>()
                                .add(UpdateDarkSeedColor(color));
                          } else {
                            context
                                .read<SettingsBloc>()
                                .add(UpdateSeedColor(color));
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // הגדרות טאבים
              SettingsCard(
                title: 'הגדרות טאבים',
                children: [
                  SwitchListTile(
                    secondary: const Icon(FluentIcons.tab_24_regular),
                    title: const Text('יישור טאבים לימין',
                        style: TextStyle(fontSize: 16)),
                    subtitle: Text(
                        state.alignTabsToRight
                            ? 'הטאבים יוצגו בצד ימין'
                            : 'הטאבים יוצגו במרכז',
                        style: const TextStyle(fontSize: 13)),
                    value: state.alignTabsToRight,
                    onChanged: (value) {
                      context
                          .read<SettingsBloc>()
                          .add(UpdateAlignTabsToRight(value));
                    },
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // התנהגות סרגל צד
              SettingsCard(
                title: 'התנהגות סרגל צד',
                children: [
                  SegmentedSettingsTile<_SidebarMode>(
                    title: 'הצגת חלונית ניווט בכותרות ופרקים',
                    subtitle: state.pinSidebar
                        ? 'החלונית תוצג תמיד'
                        : state.defaultSidebarOpen
                            ? 'החלונית תוצג בפתיחת ספר ותיסגר בגלילה'
                            : 'החלונית לא תוצג אוטומטית',
                    icon: FluentIcons.panel_left_24_regular,
                    options: const [
                      SegmentOption(value: _SidebarMode.pinned, label: 'הצמדה'),
                      SegmentOption(
                          value: _SidebarMode.openOnBook, label: 'בפתיחת ספר'),
                      SegmentOption(
                          value: _SidebarMode.closed, label: 'סגור תמיד'),
                    ],
                    currentValue: state.pinSidebar
                        ? _SidebarMode.pinned
                        : state.defaultSidebarOpen
                            ? _SidebarMode.openOnBook
                            : _SidebarMode.closed,
                    onChanged: (mode) {
                      if (mode == _SidebarMode.pinned) {
                        context
                            .read<SettingsBloc>()
                            .add(UpdatePinSidebar(true));
                        context
                            .read<SettingsBloc>()
                            .add(const UpdateDefaultSidebarOpen(true));
                      } else if (mode == _SidebarMode.openOnBook) {
                        context
                            .read<SettingsBloc>()
                            .add(UpdatePinSidebar(false));
                        context
                            .read<SettingsBloc>()
                            .add(const UpdateDefaultSidebarOpen(true));
                      } else {
                        context
                            .read<SettingsBloc>()
                            .add(UpdatePinSidebar(false));
                        context
                            .read<SettingsBloc>()
                            .add(const UpdateDefaultSidebarOpen(false));
                      }
                    },
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: const Text('הערות אישיות מקופלות כברירת מחדל',
                        style: TextStyle(fontSize: 16)),
                    subtitle: Text(
                        state.personalNotesCollapsedByDefault
                            ? 'רשימות ההערות ייפתחו במצב סגור'
                            : 'רשימות ההערות ייפתחו במצב פתוח',
                        style: const TextStyle(fontSize: 13)),
                    value: state.personalNotesCollapsedByDefault,
                    onChanged: (value) {
                      context
                          .read<SettingsBloc>()
                          .add(UpdatePersonalNotesCollapsedByDefault(value));
                    },
                  ),
                  const Divider(height: 1),
                  StatefulBuilder(
                    builder: (context, setState) {
                      final splitedView =
                          Settings.getValue<bool>('key-splited-view') ?? false;
                      return SwitchListTile(
                        title: const Text('ברירת המחדל להצגת המפרשים',
                            style: TextStyle(fontSize: 16)),
                        subtitle: Text(
                            splitedView
                                ? 'המפרשים יוצגו לצד הטקסט'
                                : 'המפרשים יוצגו מתחת הטקסט',
                            style: const TextStyle(fontSize: 13)),
                        value: splitedView,
                        onChanged: (value) {
                          setState(() {
                            Settings.setValue<bool>('key-splited-view', value);
                            final settingsBloc = context.read<SettingsBloc>();
                            PerBookSettings.cleanupRedundantSettings(
                              defaultFontSize: settingsBloc.state.fontSize,
                              defaultRemoveNikud:
                                  settingsBloc.state.defaultRemoveNikud,
                              defaultShowSplitView: value,
                            );
                          });
                        },
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
