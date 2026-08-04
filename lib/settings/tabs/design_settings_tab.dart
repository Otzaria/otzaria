import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart'
    hide SwitchSettingsTile;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/dialogs/settings_dialogs_exports.dart';
import 'package:otzaria/settings/engine/settings_engine_exports.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/settings/search/settings_search_models.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/settings/view/settings_screen.dart';
import 'package:otzaria/settings/widgets/settings_widgets_exports.dart';
import 'package:otzaria/theme/theme_exports.dart';
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
      id: 'design.language.settings_language',
      title: 'שפת ההגדרות',
      subtitle: 'שפת התצוגה של מסך ההגדרות בלבד',
      tab: SettingsTab.design,
      cardId: 'design.language',
      keywords: ['שפה', 'אנגלית', 'עברית', 'language', 'english', 'hebrew'],
    ),
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
      id: 'design.display.compact',
      title: 'צפיפות ממשק',
      subtitle: 'הצגת פריטים קומפקטית או מרווחת',
      tab: SettingsTab.design,
      cardId: 'design.display',
      keywords: [
        'קומפקטי',
        'צפוף',
        'נוח',
        'מרווח',
        'מופעל',
        'לא מופעל',
      ],
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
      id: 'design.pdf.talmud_bavli_format',
      title: 'פורמט פתיחת תלמוד בבלי',
      subtitle:
          'פתיחת מסכתות הבבלי בטקסט או ב-PDF, '
          'מהספרייה ומכל מקום אחר',
      tab: SettingsTab.design,
      cardId: 'design.pdf',
      keywords: [
        'תלמוד',
        'בבלי',
        'גמרא',
        'צורת הדף',
        'pdf',
        'טקסט',
        'מסכת',
        'ספרייה',
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
                SettingsCard(
                  cardId: 'design.language',
                  title: context.settingsText('שפת ההגדרות'),
                  children: [
                    SettingsActionTile.dropdownTile<String>(
                      icon: FluentIcons.local_language_24_regular,
                      title: context.settingsText('שפת ההגדרות'),
                      subtitle: context.settingsText(
                        'שפת התצוגה של מסך ההגדרות בלבד; '
                        'שאר התוכנה נשארת בעברית',
                      ),
                      value: state.settingsLanguageCode,
                      entries: [
                        AppMenuEntry(
                          value: kSettingsLanguageSystemCode,
                          label: context.settingsText('אוטומטי'),
                          subtitle: context.settingsText(
                            'לפי שפת מערכת ההפעלה',
                          ),
                        ),
                        // נבנה מהרשימה עצמה, כך ששפה חדשה מופיעה מאליה.
                        for (final language in SettingsLanguage.values)
                          AppMenuEntry(
                            value: language.code,
                            label: language.label,
                          ),
                      ],
                      onSelected: (code) {
                        if (code == null) return;
                        context.read<SettingsBloc>().add(
                          UpdateSettingsLanguageCode(code),
                        );
                      },
                    ),
                  ],
                ),

                kSettingsCardSpacing,

                // מצב כהה וצבע בסיס
                SettingsCard(
                  cardId: 'design.theme',
                  title: context.settingsText('ערכת נושא'),
                  children: [
                    SettingsActionTile.segmentedTile<_ThemeMode>(
                      icon: FluentIcons.weather_sunny_24_regular,
                      title: context.settingsText('מצב ערכת נושא'),
                      options: [
                        SegmentOption(
                          value: _ThemeMode.light,
                          label: context.settingsText('בהיר'),
                          subtitle: context.settingsText(
                            'התוכנה תשתמש בצבעים בהירים',
                          ),
                        ),
                        SegmentOption(
                          value: _ThemeMode.system,
                          label: context.settingsText('מערכת'),
                          subtitle: context.settingsText(
                            'התוכנה תתאים את המראה באופן אוטומטי להגדרות מערכת ההפעלה',
                          ),
                        ),
                        SegmentOption(
                          value: _ThemeMode.dark,
                          label: context.settingsText('כהה'),
                          subtitle: context.settingsText(
                            'התוכנה תשתמש בצבעים כהים',
                          ),
                        ),
                      ],
                      currentValue: state.followSystemTheme
                          ? _ThemeMode.system
                          : state.isDarkMode
                          ? _ThemeMode.dark
                          : _ThemeMode.light,
                      onChanged: (mode) {
                        if (mode == _ThemeMode.system) {
                          context.read<SettingsBloc>().add(
                            UpdateFollowSystemTheme(true),
                          );
                        } else {
                          context.read<SettingsBloc>().add(
                            UpdateFollowSystemTheme(false),
                          );
                          context.read<SettingsBloc>().add(
                            UpdateDarkMode(mode == _ThemeMode.dark),
                          );
                        }
                      },
                    ),
                    ColorPickerTile(
                      key: ValueKey(
                        'color-picker-${Theme.of(context).brightness == Brightness.dark ? 'dark' : 'light'}',
                      ),
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
                          context.read<SettingsBloc>().add(
                            UpdateDarkSeedColor(color),
                          );
                        } else {
                          context.read<SettingsBloc>().add(
                            UpdateSeedColor(color),
                          );
                        }
                      },
                    ),
                  ],
                ),

                kSettingsCardSpacing,

                // צפיפות תצוגה (רק בדסקטופ)
                if (!Platform.isAndroid && !Platform.isIOS) ...[
                  SettingsCard(
                    cardId: 'design.display',
                    title: context.settingsText('תצוגה'),
                    children: [
                      SettingsActionTile.segmentedTile<bool>(
                        icon: FluentIcons.column_triple_24_regular,
                        title: context.settingsText('צפיפות ממשק'),
                        options: [
                          SegmentOption(
                            value: false,
                            label: context.settingsText('רגיל'),
                            subtitle: context.settingsText(
                              'הצג פריטים במרווחים נוחים ללחיצה',
                            ),
                          ),
                          SegmentOption(
                            value: true,
                            label: context.settingsText('מצומצם'),
                            subtitle: context.settingsText(
                              'הצג יותר תוכן על ידי הקטנת המרווחים',
                            ),
                          ),
                        ],
                        currentValue: state.compactMenuMode,
                        onChanged: (value) {
                          context.read<SettingsBloc>().add(
                            UpdateCompactMenuMode(value),
                          );
                        },
                      ),
                    ],
                  ),
                  kSettingsCardSpacing,
                ],

                SettingsCard(
                  cardId: 'design.pdf',
                  title: context.settingsText('תצוגת PDF'),
                  children: [
                    SettingsActionTile.switchTile(
                      icon: FluentIcons.book_open_24_regular,
                      title: context.settingsText('תצוגת ספר בPDF'),
                      subtitle: context.settingsText(
                        state.enablePerBookSettings
                            ? state.pdfBookViewByDefault
                                  ? 'ספרי PDF ייפתחו בתצוגת ספר'
                                  : 'ספרי PDF ייפתחו בתצוגה רגילה'
                            : state.pdfBookViewByDefault
                            ? 'כל ספרי ה-PDF ייפתחו בתצוגת ספר'
                            : 'כל ספרי ה-PDF ייפתחו בתצוגה רגילה',
                      ),
                      value: state.pdfBookViewByDefault,
                      onChanged: (value) {
                        context.read<SettingsBloc>().add(
                          UpdatePdfBookViewByDefault(value),
                        );
                      },
                    ),
                    SettingsActionTile.segmentedTile<String>(
                      icon: FluentIcons.book_number_24_regular,
                      title: context.settingsText('פורמט פתיחת תלמוד בבלי'),
                      options: [
                        SegmentOption(
                          value: 'text',
                          label: context.settingsText('טקסט'),
                          icon: OtzariaIcons.book_alef_24_regular,
                          subtitle: context.settingsText(
                            'מסכתות הבבלי ייפתחו במהדורת הטקסט '
                            '(מהספרייה, מתוצאות חיפוש, מאיתור מקורות '
                            'ומקישורים)',
                          ),
                        ),
                        SegmentOption(
                          value: 'pdf',
                          label: 'PDF',
                          icon: OtzariaIcons.book_pdf_24_regular,
                          subtitle: context.settingsText(
                            'מסכתות הבבלי ייפתחו במהדורת ה-PDF '
                            'בדף המתאים, גם בפתיחה מהספרייה',
                          ),
                        ),
                      ],
                      currentValue: state.talmudBavliOpenFormat,
                      onChanged: (value) {
                        context.read<SettingsBloc>().add(
                          UpdateTalmudBavliOpenFormat(value),
                        );
                      },
                    ),
                  ],
                ),

                kSettingsCardSpacing,

                // התנהגות סרגל צד
                SettingsCard(
                  cardId: 'design.layout',
                  title: context.settingsText('חלוניות עזר'),
                  children: [
                    SettingsActionTile.segmentedTile<_SidebarMode>(
                      title: context.settingsText('חלונית ניווט בין כותרות'),
                      rtlIcon: FluentIcons.panel_left_24_regular,
                      options: [
                        SegmentOption(
                          value: _SidebarMode.pinned,
                          label: context.settingsText('הצגה'),
                          subtitle: context.settingsText(
                            'החלונית תוצג באופן קבוע',
                          ),
                        ),
                        SegmentOption(
                          value: _SidebarMode.openOnBook,
                          label: context.settingsText('אוטומטי'),
                          subtitle: context.settingsText(
                            'החלונית תוצג בפתיחת ספר ותיסגר בעת גלילה',
                          ),
                        ),
                        SegmentOption(
                          value: _SidebarMode.closed,
                          label: context.settingsText('הסתרה'),
                          subtitle: context.settingsText(
                            'החלונית לא תוצג אוטומטית עם פתיחת הספר',
                          ),
                        ),
                      ],
                      currentValue: state.pinSidebar
                          ? _SidebarMode.pinned
                          : state.defaultSidebarOpen
                          ? _SidebarMode.openOnBook
                          : _SidebarMode.closed,
                      onChanged: (mode) {
                        if (mode == _SidebarMode.pinned) {
                          context.read<SettingsBloc>().add(
                            UpdatePinSidebar(true),
                          );
                          context.read<SettingsBloc>().add(
                            const UpdateDefaultSidebarOpen(true),
                          );
                        } else if (mode == _SidebarMode.openOnBook) {
                          context.read<SettingsBloc>().add(
                            UpdatePinSidebar(false),
                          );
                          context.read<SettingsBloc>().add(
                            const UpdateDefaultSidebarOpen(true),
                          );
                        } else {
                          context.read<SettingsBloc>().add(
                            UpdatePinSidebar(false),
                          );
                          context.read<SettingsBloc>().add(
                            const UpdateDefaultSidebarOpen(false),
                          );
                        }
                      },
                    ),
                    SettingsActionTile.switchTile(
                      rtlIcon: FluentIcons.panel_right_24_regular,
                      title: context.settingsText(
                        'פתיחת פאנל המפרשים בפתיחת ספר',
                      ),
                      subtitle: context.settingsText(
                        state.defaultCommentaryOpen
                            ? 'פאנל המפרשים ייפתח אוטומטית כשיש מפרשים נבחרים '
                                  '(מפרשים בצד ו-PDF בלבד)'
                            : 'פאנל המפרשים לא ייפתח אוטומטית בפתיחת ספר',
                      ),
                      value: state.defaultCommentaryOpen,
                      onChanged: (value) {
                        context.read<SettingsBloc>().add(
                          UpdateDefaultCommentaryOpen(value),
                        );
                      },
                    ),
                    SettingsActionTile.switchTile(
                      title: context.settingsText(
                        'פתיחת הערות אישיות במצב סגור',
                      ),
                      subtitle: context.settingsText(
                        state.personalNotesCollapsedByDefault
                            ? 'רשימות ההערות יוצגו כשהן סגורות'
                            : 'רשימות ההערות יוצגו כשהן פתוחות',
                      ),
                      value: state.personalNotesCollapsedByDefault,
                      onChanged: (value) {
                        context.read<SettingsBloc>().add(
                          UpdatePersonalNotesCollapsedByDefault(value),
                        );
                      },
                    ),
                    StatefulBuilder(
                      builder: (context, setState) {
                        final splitedView =
                            Settings.getValue<bool>('key-splited-view') ?? true;
                        return SettingsActionTile.switchTile(
                          title: context.settingsText(
                            'הצגת המפרשים בחלונית בצד',
                          ),
                          subtitle: context.settingsText(
                            splitedView
                                ? 'המפרשים יוצגו בחלונית מפוצלת'
                                : 'המפרשים יוצגו בתוך הטקסט',
                          ),
                          value: splitedView,
                          onChanged: (value) {
                            setState(() {
                              Settings.setValue<bool>(
                                'key-splited-view',
                                value,
                              );
                              final settingsBloc = context.read<SettingsBloc>();
                              PerBookSettings.cleanupRedundantSettings(
                                defaultFontSize: settingsBloc.state.fontSize,
                                defaultRemoveNikud:
                                    settingsBloc.state.defaultRemoveNikud,
                                defaultRemovePunctuation:
                                    settingsBloc.state.defaultRemovePunctuation,
                                defaultShowSplitView: value,
                                defaultContinuousReadingMode: settingsBloc
                                    .state
                                    .defaultContinuousReadingMode,
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
          ),
        );
      },
    );
  }
}
