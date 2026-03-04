import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart'
    hide SwitchSettingsTile;
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
                      title: const Text('מסך מלא', style: kSettingsTitleStyle),
                      subtitle: const Text('החלף מצב מסך מלא',
                          style: kSettingsSubtitleStyle),
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

              if (!(Platform.isAndroid || Platform.isIOS)) kSettingsCardSpacing,

              // מצב כהה וצבע בסיס
              SettingsCard(
                title: 'ערכת נושא',
                children: [
                  SwitchSettingsTile(
                    leading: const Icon(FluentIcons.settings_24_regular),
                    title: const Text('מעקב אחר צבע המערכת',
                        style: kSettingsTitleStyle),
                    subtitle: Text(
                        state.followSystemTheme ? 'מופעל' : 'לא מופעל',
                        style: kSettingsSubtitleStyle),
                    value: state.followSystemTheme,
                    onChanged: (value) {
                      context
                          .read<SettingsBloc>()
                          .add(UpdateFollowSystemTheme(value));
                    },
                  ),
                  SwitchSettingsTile(
                    leading: const Icon(FluentIcons.weather_moon_24_regular),
                    title: const Text('מצב כהה', style: kSettingsTitleStyle),
                    subtitle: Text(state.isDarkMode ? 'מופעל' : 'לא מופעל',
                        style: kSettingsSubtitleStyle),
                    value: state.isDarkMode,
                    enabled: !state.followSystemTheme,
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

              kSettingsCardSpacing,

              // הגדרות טאבים
              SettingsCard(
                title: 'הגדרות טאבים',
                children: [
                  SwitchSettingsTile(
                    leading: const Icon(FluentIcons.tab_24_regular),
                    title: const Text('יישור טאבים לימין',
                        style: kSettingsTitleStyle),
                    subtitle: Text(
                        state.alignTabsToRight
                            ? 'הטאבים יוצגו בצד ימין'
                            : 'הטאבים יוצגו במרכז',
                        style: kSettingsSubtitleStyle),
                    value: state.alignTabsToRight,
                    onChanged: (value) {
                      context
                          .read<SettingsBloc>()
                          .add(UpdateAlignTabsToRight(value));
                    },
                  ),
                ],
              ),

              kSettingsCardSpacing,

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
                  SwitchSettingsTile(
                    title: const Text('הערות אישיות מקופלות כברירת מחדל',
                        style: kSettingsTitleStyle),
                    subtitle: Text(
                        state.personalNotesCollapsedByDefault
                            ? 'רשימות ההערות ייפתחו במצב סגור'
                            : 'רשימות ההערות ייפתחו במצב פתוח',
                        style: kSettingsSubtitleStyle),
                    value: state.personalNotesCollapsedByDefault,
                    onChanged: (value) {
                      context
                          .read<SettingsBloc>()
                          .add(UpdatePersonalNotesCollapsedByDefault(value));
                    },
                  ),
                  StatefulBuilder(
                    builder: (context, setState) {
                      final splitedView =
                          Settings.getValue<bool>('key-splited-view') ?? false;
                      return SwitchSettingsTile(
                        title: const Text('ברירת המחדל להצגת המפרשים',
                            style: kSettingsTitleStyle),
                        subtitle: Text(
                            splitedView
                                ? 'המפרשים יוצגו לצד הטקסט'
                                : 'המפרשים יוצגו מתחת הטקסט',
                            style: kSettingsSubtitleStyle),
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
