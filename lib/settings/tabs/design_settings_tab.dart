import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart'
    hide SwitchSettingsTile;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/dialogs/settings_dialogs_exports.dart';
import 'package:otzaria/settings/engine/settings_engine_exports.dart';
import 'package:otzaria/settings/search/settings_anchor.dart';
import 'package:otzaria/settings/search/settings_search_models.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/settings/widgets/settings_widgets_exports.dart';
import 'package:otzaria/settings/view/settings_screen.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/misc/rtl_icon.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

enum _SidebarMode { pinned, openOnBook, closed }

enum _ThemeMode { light, system, dark }

/// טאב הגדרות עיצוב
class DesignSettingsTab extends StatelessWidget {
  const DesignSettingsTab({super.key});

  /// פריטים בעלי הגדרות לחיפוש בהגדרות. נסרק על-ידי
  /// tool/generate_search_index.dart בעת בנייה ומשולב באינדקס המאוחד.
  static const List<SettingsSearchEntry> searchEntries = [
    SettingsSearchEntry(
      id: 'design.theme.follow_system',
      title: 'מעקב אחר צבע המערכת',
      subtitle: 'התאמת ערכת הנושא לצבע מערכת ההפעלה',
      tab: SettingsTab.design,
      cardId: 'design.theme',
      keywords: ['ערכת נושא', 'מערכת', 'מופעל', 'לא מופעל'],
    ),
    SettingsSearchEntry(
      id: 'design.theme.dark_mode',
      title: 'מצב כהה',
      subtitle: 'מעבר בין מצב בהיר למצב כהה',
      tab: SettingsTab.design,
      cardId: 'design.theme',
      keywords: [
        'ערכת נושא',
        'בהיר',
        'אפל',
        'dark mode',
        'מופעל',
        'לא מופעל',
      ],
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
      keywords: ['pdf', 'תצוגה', 'תצוגת ספר', 'רגילה', 'מופעל', 'לא מופעל'],
    ),
    SettingsSearchEntry(
      id: 'design.tabs.compact',
      title: 'תפריטים קומפקטיים',
      subtitle: 'צפיפות תפריטים בסגנון Chrome',
      tab: SettingsTab.design,
      cardId: 'design.tabs',
      keywords: [
        'קומפקטי',
        'צפוף',
        'chrome',
        'נוח',
        'מרווח',
        'מופעל',
        'לא מופעל',
      ],
    ),
    SettingsSearchEntry(
      id: 'design.layout.sidebar_mode',
      title: 'חלונית ניווט בין כותרות',
      subtitle: 'הצגה / אוטומטי / הסתרה של חלונית הניווט',
      tab: SettingsTab.design,
      cardId: 'design.layout',
      keywords: [
        'סייד-בר',
        'תפריט',
        'הצגה',
        'אוטומטי',
        'הסתרה',
        'קבוע',
        'גלילה',
      ],
    ),
    SettingsSearchEntry(
      id: 'design.layout.notes_collapsed',
      title: 'פתיחת הערות אישיות במצב סגור',
      subtitle: 'תצוגת רשימות הערות בפתיחה',
      tab: SettingsTab.design,
      cardId: 'design.layout',
      keywords: [
        'הערות',
        'אישיות',
        'סגורות',
        'פתוחות',
        'מופעל',
        'לא מופעל',
      ],
    ),
    SettingsSearchEntry(
      id: 'design.layout.split_view',
      title: 'הצגת המפרשים בחלונית בצד',
      subtitle: 'מפרשים בחלונית מפוצלת או בתוך הטקסט',
      tab: SettingsTab.design,
      cardId: 'design.layout',
      keywords: [
        'מפרשים',
        'מפוצל',
        'מפוצלת',
        'בתוך הטקסט',
        'מופעל',
        'לא מופעל',
      ],
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
                // מצב כהה וצבע בסיס
                SettingsAnchor(
                  cardId: 'design.theme',
                  child: SettingsCard(
                    title: 'ערכת נושא',
                    children: [
                      SegmentedSettingsTile<_ThemeMode>(
                        icon: Icon(FluentIcons.weather_sunny_24_regular),
                        title: 'מצב ערכת נושא',
                        subtitle: state.followSystemTheme
                            ? 'התוכנה תתאים את המראה באופן אוטומטי להגדרות מערכת ההפעלה'
                            : state.isDarkMode
                                ? 'התוכנה תשתמש בצבעים כהים'
                                : 'התוכנה תשתמש בצבעים בהירים',
                        options: const [
                          SegmentOption(value: _ThemeMode.light, label: 'בהיר'),
                          SegmentOption(
                              value: _ThemeMode.system, label: 'מערכת'),
                          SegmentOption(value: _ThemeMode.dark, label: 'כהה'),
                        ],
                        currentValue: state.followSystemTheme
                            ? _ThemeMode.system
                            : state.isDarkMode
                                ? _ThemeMode.dark
                                : _ThemeMode.light,
                        onChanged: (mode) {
                          if (mode == _ThemeMode.system) {
                            context
                                .read<SettingsBloc>()
                                .add(UpdateFollowSystemTheme(true));
                          } else {
                            context
                                .read<SettingsBloc>()
                                .add(UpdateFollowSystemTheme(false));
                            context
                                .read<SettingsBloc>()
                                .add(UpdateDarkMode(mode == _ThemeMode.dark));
                          }
                        },
                      ),
                      ColorPickerTile(
                        key: ValueKey(
                            'color-picker-${Theme.of(context).brightness == Brightness.dark ? 'dark' : 'light'}'),
                        currentColor:
                            Theme.of(context).brightness == Brightness.dark
                                ? state.darkSeedColor
                                : state.seedColor,
                        defaultColor:
                            Theme.of(context).brightness == Brightness.dark
                                ? AppSeedColors.defaultDark
                                : AppSeedColors.defaultLight,
                        onChanged: (color) {
                          if (Theme.of(context).brightness == Brightness.dark) {
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
                    ],
                  ),
                ),

                kSettingsCardSpacing,

                SettingsAnchor(
                  cardId: 'design.pdf',
                  child: SettingsCard(
                    title: 'תצוגת PDF',
                    children: [
                      SwitchSettingsTile.text(
                        icon: FluentIcons.book_open_24_regular,
                        title: 'תצוגת ספר בPDF',
                        subtitle: state.enablePerBookSettings
                            ? state.pdfBookViewByDefault
                                ? 'ספרי PDF ייפתחו בתצוגת ספר'
                                : 'ספרי PDF ייפתחו בתצוגה רגילה'
                            : state.pdfBookViewByDefault
                                ? 'כל ספרי ה-PDF ייפתחו בתצוגת ספר'
                                : 'כל ספרי ה-PDF ייפתחו בתצוגה רגילה',
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
                    title: 'התאמת ממשק',
                    children: [
                      if (!(Platform.isAndroid || Platform.isIOS))
                        SegmentedSettingsTile<bool>(
                          icon: Icon(FluentIcons.column_triple_24_regular),
                          title: 'צפיפות ממשק',
                          subtitle: state.compactMenuMode
                              ? 'הצג יותר תוכן על ידי הקטנת המרווחים'
                              : 'הצג פריטים במרווחים נוחים ללחיצה',
                          options: const [
                            SegmentOption(value: false, label: 'רחב'),
                            SegmentOption(value: true, label: 'קומפקטי'),
                          ],
                          currentValue: state.compactMenuMode,
                          onChanged: (value) {
                            context
                                .read<SettingsBloc>()
                                .add(UpdateCompactMenuMode(value));
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
                        icon: RtlIcon(FluentIcons.panel_left_24_regular),
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
                      SwitchSettingsTile.text(
                        title: 'פתיחת הערות אישיות במצב סגור',
                        subtitle: state.personalNotesCollapsedByDefault
                            ? 'רשימות ההערות יוצגו כשהן סגורות'
                            : 'רשימות ההערות יוצגו כשהן פתוחות',
                        value: state.personalNotesCollapsedByDefault,
                        onChanged: (value) {
                          context.read<SettingsBloc>().add(
                              UpdatePersonalNotesCollapsedByDefault(value));
                        },
                      ),
                      StatefulBuilder(
                        builder: (context, setState) {
                          final splitedView =
                              Settings.getValue<bool>('key-splited-view') ??
                                  true;
                          return SwitchSettingsTile.text(
                            title: 'הצגת המפרשים בחלונית בצד',
                            subtitle: splitedView
                                ? 'המפרשים יוצגו בחלונית מפוצלת'
                                : 'המפרשים יוצגו בתוך הטקסט',
                            value: splitedView,
                            onChanged: (value) {
                              setState(() {
                                Settings.setValue<bool>(
                                    'key-splited-view', value);
                                final settingsBloc =
                                    context.read<SettingsBloc>();
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
