import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart'
    hide SwitchSettingsTile;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:window_manager/window_manager.dart';
import 'package:otzaria/settings/engine/settings_engine_exports.dart';
import 'package:otzaria/settings/search/settings_anchor.dart';
import 'package:otzaria/settings/search/settings_search_models.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/settings/settings_card.dart';
import 'package:otzaria/settings/view/settings_screen.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

enum _SidebarMode { pinned, openOnBook, closed }

/// טאב הגדרות עיצוב
class DesignSettingsTab extends StatelessWidget {
  const DesignSettingsTab({super.key});

  /// פריטים בעלי הגדרות לחיפוש בהגדרות. נסרק על-ידי
  /// tool/generate_search_index.dart בעת בנייה ומשולב באינדקס המאוחד.
  static const List<SettingsSearchEntry> searchEntries = [
    SettingsSearchEntry(
      id: 'design.display.fullscreen',
      title: 'מסך מלא',
      subtitle: 'החלף מצב מסך מלא',
      tab: SettingsTab.design,
      cardId: 'design.display',
      keywords: ['מסך מלא', 'fullscreen'],
    ),
    SettingsSearchEntry(
      id: 'design.theme.follow_system',
      title: 'מעקב אחר צבע המערכת',
      subtitle: 'התאמת ערכת הנושא לצבע מערכת ההפעלה',
      tab: SettingsTab.design,
      cardId: 'design.theme',
      keywords: ['ערכת נושא', 'מערכת'],
    ),
    SettingsSearchEntry(
      id: 'design.theme.dark_mode',
      title: 'מצב כהה',
      subtitle: 'מעבר בין מצב בהיר למצב כהה',
      tab: SettingsTab.design,
      cardId: 'design.theme',
      keywords: ['ערכת נושא', 'בהיר', 'אפל', 'dark mode'],
    ),
    SettingsSearchEntry(
      id: 'design.theme.seed_color',
      title: 'צבע בסיס',
      subtitle: 'צבע ראשי של ערכת הנושא',
      tab: SettingsTab.design,
      cardId: 'design.theme',
      keywords: ['צבע', 'ערכת נושא'],
    ),
    SettingsSearchEntry(
      id: 'design.pdf.book_view',
      title: 'תצוגת ספר בPDF',
      subtitle: 'פתיחת ספרי PDF בתצוגת ספר או רגילה',
      tab: SettingsTab.design,
      cardId: 'design.pdf',
      keywords: ['pdf', 'תצוגה'],
    ),
    SettingsSearchEntry(
      id: 'design.tabs.compact',
      title: 'תפריטים קומפקטיים',
      subtitle: 'צפיפות תפריטים בסגנון Chrome',
      tab: SettingsTab.design,
      cardId: 'design.tabs',
      keywords: ['קומפקטי', 'צפוף'],
    ),
    SettingsSearchEntry(
      id: 'design.tabs.align_right',
      title: 'הצגת כרטיסיות בימין',
      subtitle: 'הצגת כרטיסיות הספרים בימין החלון',
      tab: SettingsTab.design,
      cardId: 'design.tabs',
      keywords: ['ימין', 'מרכז', 'כרטיסיות'],
    ),
    SettingsSearchEntry(
      id: 'design.layout.sidebar_mode',
      title: 'חלונית ניווט בין כותרות',
      subtitle: 'הצגה / אוטומטי / הסתרה של חלונית הניווט',
      tab: SettingsTab.design,
      cardId: 'design.layout',
      keywords: ['סייד-בר', 'תפריט'],
    ),
    SettingsSearchEntry(
      id: 'design.layout.notes_collapsed',
      title: 'פתיחת הערות אישיות במצב סגור',
      subtitle: 'תצוגת רשימות הערות בפתיחה',
      tab: SettingsTab.design,
      cardId: 'design.layout',
      keywords: ['הערות', 'אישיות'],
    ),
    SettingsSearchEntry(
      id: 'design.layout.split_view',
      title: 'הצגת המפרשים בחלונית בצד',
      subtitle: 'מפרשים בחלונית מפוצלת או בתוך הטקסט',
      tab: SettingsTab.design,
      cardId: 'design.layout',
      keywords: ['מפרשים', 'מפוצל'],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, state) {
        return SingleChildScrollView(
          primary: true,
          padding: const EdgeInsets.all(16.0),
          child: ToolPanelWrapper(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // מסך מלא (רק בדסקטופ)
                if (!(Platform.isAndroid || Platform.isIOS))
                  SettingsAnchor(
                    cardId: 'design.display',
                    child: SettingsCard(
                      title: 'תצוגה',
                      children: [
                        ListTile(
                          leading: Icon(state.isFullscreen
                              ? FluentIcons.full_screen_minimize_24_regular
                              : FluentIcons.full_screen_maximize_24_regular),
                          title: const Text('מסך מלא',
                              style: kSettingsTitleStyle),
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
                  ),

                if (!(Platform.isAndroid || Platform.isIOS))
                  kSettingsCardSpacing,

                // מצב כהה וצבע בסיס
                SettingsAnchor(
                  cardId: 'design.theme',
                  child: SettingsCard(
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
                ),

                kSettingsCardSpacing,

                SettingsAnchor(
                  cardId: 'design.pdf',
                  child: SettingsCard(
                    title: 'תצוגת PDF',
                    children: [
                      SwitchSettingsTile(
                        leading: const Icon(FluentIcons.book_open_24_regular),
                        title: const Text('תצוגת ספר בPDF',
                            style: kSettingsTitleStyle),
                        subtitle: Text(
                          state.enablePerBookSettings
                              ? state.pdfBookViewByDefault
                                  ? 'ספרי PDF ייפתחו בתצוגת ספר'
                                  : 'ספרי PDF ייפתחו בתצוגה רגילה'
                              : state.pdfBookViewByDefault
                                  ? 'כל ספרי ה-PDF ייפתחו בתצוגת ספר'
                                  : 'כל ספרי ה-PDF ייפתחו בתצוגה רגילה',
                          style: kSettingsSubtitleStyle,
                        ),
                        value: state.pdfBookViewByDefault,
                        onChanged: (value) {
                          context
                              .read<SettingsBloc>()
                              .add(UpdatePdfBookViewByDefault(value));
                        },
                      ),
                    ],
                  ),
                ),

                kSettingsCardSpacing,

                // הגדרות טאבים
                SettingsAnchor(
                  cardId: 'design.tabs',
                  child: SettingsCard(
                    title: 'כרטיסיות הספרים',
                  children: [
                    if (!(Platform.isAndroid || Platform.isIOS))
                      SwitchSettingsTile(
                        leading: const Icon(FluentIcons.list_24_regular),
                        title: const Text(
                          'תפריטים קומפקטיים',
                          style: kSettingsTitleStyle,
                        ),
                        subtitle: Text(
                          state.compactMenuMode
                              ? 'התפריטים יוצגו בצפיפות עבודה בסגנון Chrome'
                              : 'התפריטים יוצגו במרווח נוח ובגרסה הרגילה',
                          style: kSettingsSubtitleStyle,
                        ),
                        value: state.compactMenuMode,
                        onChanged: (value) {
                          context
                              .read<SettingsBloc>()
                              .add(UpdateCompactMenuMode(value));
                        },
                      ),
                    SwitchSettingsTile(
                      leading: const Icon(FluentIcons.tab_24_regular),
                      title: const Text('הצגת כרטיסיות בימין',
                          style: kSettingsTitleStyle),
                      subtitle: Text(
                          state.alignTabsToRight
                              ? 'הכרטיסיות יהיו בצד ימין'
                              : 'הכרטיסיות יהיו במרכז החלון',
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
                ),

                kSettingsCardSpacing,

                // התנהגות סרגל צד
                SettingsAnchor(
                  cardId: 'design.layout',
                  child: SettingsCard(
                    title: 'חלוניות עזר',
                  children: [
                    SegmentedSettingsTile<_SidebarMode>(
                      title: 'חלונית ניווט בין כותרות',
                      subtitle: state.pinSidebar
                          ? 'החלונית תוצג באופן קבוע'
                          : state.defaultSidebarOpen
                              ? 'החלונית תוצג בפתיחת ספר ותיסגר בעת גלילה'
                              : 'החלונית לא תוצג אוטומטית עם פתיחת הספר',
                      icon: FluentIcons.panel_left_24_regular,
                      options: const [
                        SegmentOption(
                            value: _SidebarMode.pinned, label: 'הצגה'),
                        SegmentOption(
                            value: _SidebarMode.openOnBook, label: 'אוטומטי'),
                        SegmentOption(
                            value: _SidebarMode.closed, label: 'הסתרה'),
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
                      title: const Text('פתיחת הערות אישיות במצב סגור',
                          style: kSettingsTitleStyle),
                      subtitle: Text(
                          state.personalNotesCollapsedByDefault
                              ? 'רשימות ההערות יוצגו כשהן סגורות'
                              : 'רשימות ההערות יוצגו כשהן פתוחות',
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
                            Settings.getValue<bool>('key-splited-view') ??
                                false;
                        return SwitchSettingsTile(
                          title: const Text('הצגת המפרשים בחלונית בצד',
                              style: kSettingsTitleStyle),
                          subtitle: Text(
                              splitedView
                                  ? 'המפרשים יוצגו בחלונית מפוצלת'
                                  : 'המפרשים יוצגו בתוך הטקסט',
                              style: kSettingsSubtitleStyle),
                          value: splitedView,
                          onChanged: (value) {
                            setState(() {
                              Settings.setValue<bool>(
                                  'key-splited-view', value);
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
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
