import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/settings_engine_exports.dart';
import 'package:otzaria/settings/search/settings_anchor.dart';
import 'package:otzaria/settings/search/settings_search_models.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/settings/widgets/settings_widgets_exports.dart';
import 'package:otzaria/settings/view/settings_screen.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/widgets/misc/rtl_icon.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria/core/ui_snack.dart';

/// סינון תצוגת רשימת הגופנים לפי סגנון.
enum _FontStyleFilter { all, serif, sansSerif }

/// מצב הסינון משותף לשני בוחרי הגופן ונשמר בין כניסות להגדרות.
final ValueNotifier<_FontStyleFilter> _fontStyleFilter =
    ValueNotifier(_FontStyleFilter.all);

/// טאב הגדרות תצוגת ספרים
/// ניתן להשתמש בו גם כתוכן בתוך דיאלוג וגם כטאב במסך הגדרות
class TextSettingsTab extends StatelessWidget {
  /// האם להציג כדיאלוג (עם כפתור סגירה) או כטאב (ללא)
  final bool isDialog;

  /// כאשר true, מוסתר סליידר "גודל גופן מפרשים". משמש במצב צורת הדף, שבו
  /// גודל גופן המפרשים נשלט על-ידי הגדרה ייעודית נפרדת בדיאלוג צורת הדף.
  final bool hideCommentaryFontSize;

  const TextSettingsTab({
    super.key,
    this.isDialog = false,
    this.hideCommentaryFontSize = false,
  });

  /// פריטי חיפוש בהגדרות. נסרק על-ידי tool/generate_search_index.dart.
  static const List<SettingsSearchEntry> searchEntries = [
    SettingsSearchEntry(
      id: 'text.font.book_size',
      title: 'גודל גופן הספר',
      subtitle: 'גודל הטקסט בספרים',
      tab: SettingsTab.text,
      cardId: 'text.font',
      keywords: ['גודל אות', 'פונט'],
    ),
    SettingsSearchEntry(
      id: 'text.font.book_family',
      title: 'גופן טקסט',
      subtitle: 'בחירת סוג הגופן לספרים',
      tab: SettingsTab.text,
      cardId: 'text.font',
      keywords: ['פונט', 'אות'],
    ),
    SettingsSearchEntry(
      id: 'text.font.commentators_size',
      title: 'גודל גופן מפרשים',
      subtitle: 'גודל הטקסט במפרשים',
      tab: SettingsTab.text,
      cardId: 'text.font',
      keywords: ['פרשנים', 'מפרשים'],
    ),
    SettingsSearchEntry(
      id: 'text.font.commentators_family',
      title: 'גופן מפרשים',
      subtitle: 'בחירת סוג הגופן למפרשים',
      tab: SettingsTab.text,
      cardId: 'text.font',
      keywords: ['פונט', 'פרשנים'],
    ),
    SettingsSearchEntry(
      id: 'text.font.line_height',
      title: 'מרווח בין שורות',
      subtitle: 'גובה השורות בספרים',
      tab: SettingsTab.text,
      cardId: 'text.font',
      keywords: ['רווח', 'גובה שורה'],
    ),
    SettingsSearchEntry(
      id: 'text.font.text_width',
      title: 'רוחב הטקסט',
      subtitle: 'רוחב מקסימלי של עמודת הטקסט',
      tab: SettingsTab.text,
      cardId: 'text.font',
      keywords: ['רוחב', 'עמודה'],
    ),
    SettingsSearchEntry(
      id: 'text.nikud.display_mode',
      title: 'הצגת הניקוד',
      subtitle: 'הצג / הסתר ניקוד בתנ"ך ובכל הספרים',
      tab: SettingsTab.text,
      cardId: 'text.nikud',
      keywords: [
        'ניקוד',
        'תנך',
        'הצג תמיד',
        'הצג בתנך',
        'אל תציג',
        'הסתר',
      ],
    ),
    SettingsSearchEntry(
      id: 'text.nikud.holy_names',
      title: 'הצגת שם הקודש',
      subtitle: 'הסתרת שם השם משיקולי קדושה',
      tab: SettingsTab.text,
      cardId: 'text.nikud',
      keywords: [
        'שם השם',
        'קדושה',
        'יוצג',
        'לא יוצג',
        'מופעל',
        'לא מופעל',
      ],
    ),
    SettingsSearchEntry(
      id: 'text.nikud.teamim',
      title: 'הצגת טעמי המקרא',
      subtitle: 'הצג טעמים בתנ"ך',
      tab: SettingsTab.text,
      cardId: 'text.nikud',
      keywords: [
        'טעמים',
        'מקרא',
        'עם טעמים',
        'ללא טעמים',
        'מופעל',
        'לא מופעל',
      ],
    ),
    SettingsSearchEntry(
      id: 'text.copy.with_headers',
      title: 'העתקת הכותרת',
      subtitle: 'העתקת הטקסט עם שם הספר וכותרות',
      tab: SettingsTab.text,
      cardId: 'text.copy',
      keywords: [
        'העתק',
        'כותרת',
        'ללא',
        'שם הספר',
        'שם וכותרת',
        'נתיב',
      ],
    ),
    SettingsSearchEntry(
      id: 'text.copy.format',
      title: 'עיצוב כותרות',
      subtitle: 'עיצוב כותרות בעת העתקה',
      tab: SettingsTab.text,
      cardId: 'text.copy',
      keywords: [
        'העתק',
        'כותרת',
        'פורמט',
        'אותה שורה',
        'פסקה נפרדת',
        'סוגריים',
      ],
    ),
    SettingsSearchEntry(
      id: 'text.per_book.enable',
      title: 'שמירת התאמות לכל ספר בנפרד',
      subtitle: 'שינויי תצוגה ייחודיים לכל ספר',
      tab: SettingsTab.text,
      cardId: 'text.per_book',
      keywords: [
        'ספר נפרד',
        'התאמה אישית',
        'מופעל',
        'לא מופעל',
      ],
    ),
    SettingsSearchEntry(
      id: 'text.per_book.reset',
      title: 'אפס את כל הגדרות אלו, בכל הספרים',
      subtitle: 'מחיקת כל ההתאמות שנשמרו לספרים',
      tab: SettingsTab.text,
      cardId: 'text.per_book',
      keywords: ['איפוס', 'מחיקה'],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, settingsState) {
        final content = SingleChildScrollView(
          primary: true,
          padding: const EdgeInsets.all(16.0),
          child: ToolPanelWrapper(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingsAnchor(
                  cardId: 'text.font',
                  child: _buildFontSection(context, settingsState),
                ),
                kSettingsCardSpacing,
                SettingsAnchor(
                  cardId: 'text.nikud',
                  child: _buildNikudSection(context, settingsState),
                ),
                kSettingsCardSpacing,
                SettingsAnchor(
                  cardId: 'text.copy',
                  child: _buildCopySection(context, settingsState),
                ),
                kSettingsCardSpacing,
                SettingsAnchor(
                  cardId: 'text.per_book',
                  child: _buildPerBookSection(context, settingsState),
                ),
              ],
            ),
          ),
        );

        return content;
      },
    );
  }

  Widget _buildFontSection(BuildContext context, SettingsState state) {
    return ValueListenableBuilder<_FontStyleFilter>(
      valueListenable: _fontStyleFilter,
      builder: (context, styleFilter, _) {
        final categoryFilter = switch (styleFilter) {
          _FontStyleFilter.all => null,
          _FontStyleFilter.serif => FontCategory.serif,
          _FontStyleFilter.sansSerif => FontCategory.sansSerif,
        };
        return SettingsCard(
          title: 'הגדרות גופן ועיצוב',
          children: [
            // מסנן סגנון: עם תגיות (serif) / חלק (sans-serif)
            SegmentedSettingsTile<_FontStyleFilter>(
              icon: const RtlIcon(FluentIcons.text_font_size_24_regular),
              title: 'סגנון הגופן',
              subtitle: 'סינון רשימת הגופנים לפי סגנון',
              options: const [
                SegmentOption(value: _FontStyleFilter.all, label: 'הכל'),
                SegmentOption(value: _FontStyleFilter.serif, label: 'Serif'),
                SegmentOption(value: _FontStyleFilter.sansSerif, label: 'Sans'),
              ],
              currentValue: styleFilter,
              onChanged: (value) => _fontStyleFilter.value = value,
            ),
            // שורה 1: גודל גופן הספר + גופן טקסט
            LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow =
                    constraints.maxWidth < LayoutBreakpoints.compact;
                if (isNarrow) {
                  return Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _FontSizeSlider(
                          icon: FluentIcons.text_font_size_24_regular,
                          label: 'גודל גופן הספר',
                          value: state.fontSize.clamp(15, 60),
                          min: 15,
                          max: 60,
                          onChanged: (value) {
                            context
                                .read<SettingsBloc>()
                                .add(UpdateFontSize(value));
                          },
                        ),
                        const SizedBox(height: 16),
                        _FontDropdown(
                          icon: FluentIcons.text_font_24_regular,
                          label: 'גופן טקסט',
                          categoryFilter: categoryFilter,
                          value: state.fontFamily,
                          onChanged: (value) {
                            if (value != null) {
                              context
                                  .read<SettingsBloc>()
                                  .add(UpdateFontFamily(value));
                            }
                          },
                        ),
                      ],
                    ),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _FontSizeSlider(
                          icon: FluentIcons.text_font_size_24_regular,
                          label: 'גודל גופן הספר',
                          value: state.fontSize.clamp(15, 60),
                          min: 15,
                          max: 60,
                          onChanged: (value) {
                            context
                                .read<SettingsBloc>()
                                .add(UpdateFontSize(value));
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _FontDropdown(
                          icon: FluentIcons.text_font_24_regular,
                          label: 'גופן טקסט',
                          categoryFilter: categoryFilter,
                          value: state.fontFamily,
                          onChanged: (value) {
                            if (value != null) {
                              context
                                  .read<SettingsBloc>()
                                  .add(UpdateFontFamily(value));
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            // שורה 2: גודל גופן מפרשים + גופן מפרשים
            LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow =
                    constraints.maxWidth < LayoutBreakpoints.compact;
                if (isNarrow) {
                  return Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!hideCommentaryFontSize) ...[
                          _FontSizeSlider(
                            icon: FluentIcons.text_font_size_24_regular,
                            label: 'גודל גופן מפרשים',
                            value: state.commentatorsFontSize.clamp(10, 40),
                            min: 10,
                            max: 40,
                            onChanged: (value) {
                              context
                                  .read<SettingsBloc>()
                                  .add(UpdateCommentatorsFontSize(value));
                            },
                          ),
                          const SizedBox(height: 16),
                        ],
                        _FontDropdown(
                          icon: FluentIcons.book_24_regular,
                          label: 'גופן מפרשים',
                          categoryFilter: categoryFilter,
                          value: state.commentatorsFontFamily,
                          onChanged: (value) {
                            if (value != null) {
                              context
                                  .read<SettingsBloc>()
                                  .add(UpdateCommentatorsFontFamily(value));
                            }
                          },
                        ),
                      ],
                    ),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!hideCommentaryFontSize) ...[
                        Expanded(
                          child: _FontSizeSlider(
                            icon: FluentIcons.text_font_size_24_regular,
                            label: 'גודל גופן מפרשים',
                            value: state.commentatorsFontSize.clamp(10, 40),
                            min: 10,
                            max: 40,
                            onChanged: (value) {
                              context
                                  .read<SettingsBloc>()
                                  .add(UpdateCommentatorsFontSize(value));
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                      ],
                      Expanded(
                        child: _FontDropdown(
                          icon: FluentIcons.book_24_regular,
                          label: 'גופן מפרשים',
                          categoryFilter: categoryFilter,
                          value: state.commentatorsFontFamily,
                          onChanged: (value) {
                            if (value != null) {
                              context
                                  .read<SettingsBloc>()
                                  .add(UpdateCommentatorsFontFamily(value));
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            // שורה 3: מרווח בין שורות
            LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow =
                    constraints.maxWidth < LayoutBreakpoints.compact;
                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: isNarrow
                      ? _FontSizeSlider(
                          icon: FluentIcons
                              .text_align_distributed_vertical_24_regular,
                          label: 'מרווח בין שורות',
                          value: state.lineHeight.clamp(1.0, 3.0),
                          min: 1.0,
                          max: 3.0,
                          divisions: 20,
                          onChanged: (value) {
                            context
                                .read<SettingsBloc>()
                                .add(UpdateLineHeight(value));
                          },
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _FontSizeSlider(
                                icon: FluentIcons
                                    .text_align_distributed_vertical_24_regular,
                                label: 'מרווח בין שורות',
                                value: state.lineHeight.clamp(1.0, 3.0),
                                min: 1.0,
                                max: 3.0,
                                divisions: 20,
                                onChanged: (value) {
                                  context
                                      .read<SettingsBloc>()
                                      .add(UpdateLineHeight(value));
                                },
                              ),
                            ),
                            const SizedBox(width: 16),
                            const Expanded(child: SizedBox()),
                          ],
                        ),
                );
              },
            ),

            _TextWidthSlider(state: state),
          ],
        );
      },
    );
  }

  Widget _buildNikudSection(BuildContext context, SettingsState state) {
    // קביעת הערך הנוכחי של הניקוד
    String nikudValue;
    if (!state.defaultRemoveNikud) {
      nikudValue = 'show_always';
    } else if (state.removeNikudFromTanach) {
      nikudValue = 'hide_all';
    } else {
      nikudValue = 'show_tanach_only';
    }

    // קביעת ה-subtitle בהתאם למצב
    String nikudSubtitle;
    switch (nikudValue) {
      case 'show_always':
        nikudSubtitle = 'הניקוד יוצג בכל הספרים';
        break;
      case 'show_tanach_only':
        nikudSubtitle = 'הניקוד יוצג בספרי התנ"ך בלבד';
        break;
      case 'hide_all':
        nikudSubtitle = 'הניקוד לא יוצג בכלל';
        break;
      default:
        nikudSubtitle = '';
    }

    return SettingsCard(
      title: 'כתרי אותיות',
      children: [
        SegmentedSettingsTile<String>(
          icon: Icon(FluentIcons.text_font_info_24_regular),
          title: 'הצגת הניקוד',
          subtitle: nikudSubtitle,
          options: const [
            SegmentOption(value: 'show_always', label: 'הצג תמיד'),
            SegmentOption(value: 'show_tanach_only', label: 'הצג בתנ"ך'),
            SegmentOption(value: 'hide_all', label: 'אל תציג'),
          ],
          currentValue: nikudValue,
          onChanged: (value) {
            switch (value) {
              case 'show_always':
                context
                    .read<SettingsBloc>()
                    .add(const UpdateDefaultRemoveNikud(false));
                break;
              case 'show_tanach_only':
                context
                    .read<SettingsBloc>()
                    .add(const UpdateDefaultRemoveNikud(true));
                context
                    .read<SettingsBloc>()
                    .add(const UpdateRemoveNikudFromTanach(false));
                break;
              case 'hide_all':
                context
                    .read<SettingsBloc>()
                    .add(const UpdateDefaultRemoveNikud(true));
                context
                    .read<SettingsBloc>()
                    .add(const UpdateRemoveNikudFromTanach(true));
                break;
            }
          },
        ),
        SwitchSettingsTile.text(
          icon: FluentIcons.shield_keyhole_24_regular,
          title: 'הצגת שם הקודש',
          subtitle: !state.replaceHolyNames
              ? 'השם הקדוש יוצג'
              : 'השם הקדוש לא יוצג מפני קדושתו',
          value: !state.replaceHolyNames,
          onChanged: (value) {
            context.read<SettingsBloc>().add(UpdateReplaceHolyNames(!value));
          },
        ),
        SwitchSettingsTile.text(
          icon: FluentIcons.text_more_24_regular,
          title: 'הצגת טעמי המקרא',
          subtitle:
              state.showTeamim ? 'המקרא יוצג עם טעמים' : 'המקרא יוצג ללא טעמים',
          value: state.showTeamim,
          onChanged: (value) {
            context.read<SettingsBloc>().add(UpdateShowTeamim(value));
          },
        ),
      ],
    );
  }

  Widget _buildCopySection(BuildContext context, SettingsState state) {
    // קביעת ה-subtitle בהתאם למצב העתקת הכותרת
    String copySubtitle;
    switch (state.copyWithHeaders) {
      case 'none':
        copySubtitle = 'הטקסט יועתק ללא כותרות';
        break;
      case 'book_name':
        copySubtitle = 'הטקסט יועתק עם שם הספר בלבד';
        break;
      case 'book_and_path':
        copySubtitle = 'הטקסט יועתק עם שם הספר ונתיב הטקסט';
        break;
      default:
        copySubtitle = '';
    }

    // קביעת ה-subtitle בהתאם לעיצוב ההעתקה
    String formatSubtitle;
    switch (state.copyHeaderFormat) {
      case 'same_line_after_brackets':
        formatSubtitle = 'הכותרת תופיע באותה שורה אחרי הטקסט (עם סוגריים)';
        break;
      case 'same_line_after_no_brackets':
        formatSubtitle = 'הכותרת תופיע באותה שורה אחרי הטקסט (בלי סוגריים)';
        break;
      case 'same_line_before_brackets':
        formatSubtitle = 'הכותרת תופיע באותה שורה לפני הטקסט (עם סוגריים)';
        break;
      case 'same_line_before_no_brackets':
        formatSubtitle = 'הכותרת תופיע באותה שורה לפני הטקסט (בלי סוגריים)';
        break;
      case 'separate_line_after':
        formatSubtitle = 'הכותרת תופיע בפסקה נפרדת אחרי הטקסט';
        break;
      case 'separate_line_before':
        formatSubtitle = 'הכותרת תופיע בפסקה נפרדת לפני הטקסט';
        break;
      default:
        formatSubtitle = '';
    }

    return SettingsCard(
      title: 'העתקת כותרות ופרקים',
      children: [
        SegmentedSettingsTile<String>(
          icon: Icon(FluentIcons.copy_24_regular),
          title: 'העתקת הכותרת',
          subtitle: copySubtitle,
          options: const [
            SegmentOption(value: 'none', label: 'ללא'),
            SegmentOption(value: 'book_name', label: 'שם הספר'),
            SegmentOption(value: 'book_and_path', label: 'שם וכותרת'),
          ],
          currentValue: state.copyWithHeaders,
          onChanged: (value) {
            context.read<SettingsBloc>().add(UpdateCopyWithHeaders(value));
          },
        ),
        if (state.copyWithHeaders != 'none')
          DropdownSettingsTile<String>(
            icon: RtlIcon(FluentIcons.text_align_right_24_regular),
            title: 'עיצוב כותרות',
            subtitle: formatSubtitle,
            value: state.copyHeaderFormat,
            minFieldWidth: 220,
            maxFieldWidth: 320,
            entries: const [
              AppMenuEntry(
                value: 'same_line_after_brackets',
                label: 'אותה שורה אחרי (עם סוגריים)',
              ),
              AppMenuEntry(
                value: 'same_line_after_no_brackets',
                label: 'אותה שורה אחרי (בלי סוגריים)',
              ),
              AppMenuEntry(
                value: 'same_line_before_brackets',
                label: 'אותה שורה לפני (עם סוגריים)',
              ),
              AppMenuEntry(
                value: 'same_line_before_no_brackets',
                label: 'אותה שורה לפני (בלי סוגריים)',
              ),
              AppMenuEntry(
                value: 'separate_line_after',
                label: 'פסקה נפרדת אחרי',
              ),
              AppMenuEntry(
                value: 'separate_line_before',
                label: 'פסקה נפרדת לפני',
              ),
            ],
            onSelected: (value) {
              if (value != null) {
                context.read<SettingsBloc>().add(UpdateCopyHeaderFormat(value));
              }
            },
          ),
      ],
    );
  }

  Widget _buildPerBookSection(BuildContext context, SettingsState state) {
    return SettingsCard(
      title: 'הגדרות לפי ספר',
      children: [
        SwitchSettingsTile.text(
          icon: FluentIcons.book_open_24_regular,
          title: 'שמירת התאמות לכל ספר בנפרד',
          subtitle: state.enablePerBookSettings
              ? 'שינויים בסרגל הלחצנים יישמרו לכל ספר בנפרד'
              : 'כל הספרים ישתמשו בהגדרות הכלליות',
          value: state.enablePerBookSettings,
          onChanged: (value) {
            context
                .read<SettingsBloc>()
                .add(UpdateEnablePerBookSettings(value));
          },
        ),
        if (state.enablePerBookSettings)
          SettingsActionTile.text(
            icon: FluentIcons.delete_24_regular,
            title: 'איפוס הגדרות לפי ספר',
            subtitle: 'מחיקת כל ההתאמות שנשמרו לכל ספר בנפרד',
            actions: [
              NeutralActionButton(
                onPressed: () => _resetPerBookSettings(context),
                text: 'איפוס',
              ),
            ],
          ),
      ],
    );
  }

  Future<void> _resetPerBookSettings(BuildContext context) async {
    final confirm = await showWarningDialog(
      context: context,
      title: 'אישור איפוס הגדרות לפי ספר',
      content: 'האם אתה בטוח שברצונך לאפס ולמחוק את כל ההגדרות לפי ספר?',
      subtitle: 'פעולה זו אינה ניתנת לביטול.',
      cancelText: 'ביטול',
      confirmText: 'איפוס',
    );

    if (confirm == true && context.mounted) {
      await PerBookSettings.deleteAllSettings();
      UiSnack.show('כל ההגדרות המיוחדות אופסו בהצלחה');
    }
  }
}

// Widget עזר לסליידר גודל גופן
class _FontSizeSlider extends StatefulWidget {
  final IconData icon;
  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;

  const _FontSizeSlider({
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    required this.onChanged,
  });

  @override
  State<_FontSizeSlider> createState() => _FontSizeSliderState();
}

class _FontSizeSliderState extends State<_FontSizeSlider> {
  late double _currentValue;

  @override
  void initState() {
    super.initState();
    _currentValue = widget.value;
  }

  @override
  void didUpdateWidget(_FontSizeSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _currentValue = widget.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            RtlIcon(widget.icon),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.label,
                style: kSettingsTitleStyle,
              ),
            ),
            Text(
              widget.divisions != null
                  ? _currentValue.toStringAsFixed(1)
                  : _currentValue.toStringAsFixed(0),
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        Slider(
          value: _currentValue,
          min: widget.min,
          max: widget.max,
          divisions: widget.divisions ?? (widget.max - widget.min).toInt(),
          label: widget.divisions != null
              ? _currentValue.toStringAsFixed(1)
              : _currentValue.toStringAsFixed(0),
          onChanged: (value) {
            setState(() => _currentValue = value);
            widget.onChanged(value);
          },
        ),
      ],
    );
  }
}

/// מחרוזת הדוגמה המוצגת בכל גופן ברשימה (כמו תצוגת גופנים בוורד).
const String _kFontSampleText = 'אבגד הוזח';

/// אייקון המבחין בין גופן עם תגיות (serif) לגופן חלק (sans-serif).
IconData? _fontCategoryIcon(FontCategory category) {
  switch (category) {
    case FontCategory.serif:
      return FluentIcons.text_font_24_regular;
    case FontCategory.sansSerif:
      return FluentIcons.text_t_24_regular;
    case FontCategory.unknown:
      return null;
  }
}

// Widget עזר לדרופדאון גופן
class _FontDropdown extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  /// כשמוגדר, מציג רק גופנים מהקטגוריה הזו (פרט לגופן הנבחר, שתמיד מוצג).
  final FontCategory? categoryFilter;
  final ValueChanged<String?> onChanged;

  const _FontDropdown({
    required this.icon,
    required this.label,
    required this.value,
    required this.categoryFilter,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final all = AppFonts.availableFonts;
    final filtered = categoryFilter == null
        ? List<FontInfo>.from(all)
        : all.where((f) => f.category == categoryFilter).toList();

    // הגופן הנבחר תמיד מוצג, גם אם סונן החוצה לפי הסגנון.
    if (value.isNotEmpty && !filtered.any((f) => f.value == value)) {
      final selected = all.where((f) => f.value == value);
      if (selected.isNotEmpty) filtered.insert(0, selected.first);
    }

    final fontEntries = filtered
        .map(
          (font) => AppMenuEntry<String>(
            value: font.value,
            label: font.label,
            icon: _fontCategoryIcon(font.category),
            labelWidget: _FontPreviewText(
              fontFamily: font.value,
              name: font.label,
              sample: _kFontSampleText,
              isBundled: AppFonts.fontPaths.containsKey(font.value),
            ),
          ),
        )
        .toList();

    // גופן נבחר שאינו מותקן כלל במחשב — מסומן בתווית מיוחדת.
    final hasSelectedFont =
        value.isEmpty || fontEntries.any((entry) => entry.value == value);
    if (!hasSelectedFont) {
      fontEntries.insert(
        0,
        AppMenuEntry(value: value, label: '$value (לא זמין במחשב זה)'),
      );
    }

    return Row(
      children: [
        RtlIcon(icon),
        const SizedBox(width: 8),
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: kSettingsTitleStyle,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: AppDropdownField<String>(
            value: value,
            enableSearch: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
            ),
            entries: fontEntries,
            selectedBuilder: (context, selectedValue) {
              final v = selectedValue ?? '';
              final matchingFont = all.firstWhere(
                (font) => font.value == v,
                orElse: () => FontInfo(value: v, label: v),
              );
              // בשדה הסגור מציגים את שם הגופן (מרונדר בגופן עצמו לזיהוי).
              return _FontPreviewText(
                fontFamily: v,
                name: matchingFont.label,
                isBundled: AppFonts.fontPaths.containsKey(v),
              );
            },
            onSelected: onChanged,
          ),
        ),
      ],
    );
  }
}

/// מציג את שם הגופן (ובאופן אופציונלי מחרוזת דוגמה) מרונדרים בגופן עצמו.
/// עבור גופני מערכת טוען את הגופן ל-engine ברקע, ומציג ברירת-מחדל עד הטעינה.
class _FontPreviewText extends StatefulWidget {
  final String fontFamily;
  final String name;
  final String? sample;
  final bool isBundled;

  const _FontPreviewText({
    required this.fontFamily,
    required this.name,
    required this.isBundled,
    this.sample,
  });

  @override
  State<_FontPreviewText> createState() => _FontPreviewTextState();
}

class _FontPreviewTextState extends State<_FontPreviewText> {
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _resolveFont();
  }

  @override
  void didUpdateWidget(covariant _FontPreviewText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fontFamily != widget.fontFamily ||
        oldWidget.isBundled != widget.isBundled) {
      _resolveFont();
    }
  }

  void _resolveFont() {
    if (widget.isBundled) {
      _loaded = true;
      return;
    }
    _loaded = false;
    final family = widget.fontFamily;
    AppFonts.ensureFontLoaded(family).then((_) {
      if (mounted && widget.fontFamily == family) {
        setState(() => _loaded = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final family = _loaded ? widget.fontFamily : null;
    final nameText = Text(
      widget.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontFamily: family),
    );
    if (widget.sample == null) return nameText;

    // ללא color מפורש — הדוגמה יורשת את צבע השורה (נבחר / מושבת) מהתפריט.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: nameText),
        const SizedBox(width: 12),
        Opacity(
          opacity: 0.6,
          child: Text(
            widget.sample!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontFamily: family),
          ),
        ),
      ],
    );
  }
}

// Widget עזר לסליידר רוחב טקסט
class _TextWidthSlider extends StatefulWidget {
  final SettingsState state;

  const _TextWidthSlider({required this.state});

  @override
  State<_TextWidthSlider> createState() => _TextWidthSliderState();
}

class _TextWidthSliderState extends State<_TextWidthSlider> {
  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final currentMaxWidth = widget.state.textMaxWidth;

    int currentLevel;
    if (currentMaxWidth < 0) {
      currentLevel = (-currentMaxWidth).toInt();
    } else if (currentMaxWidth == 0) {
      currentLevel = 0;
    } else {
      final ratio = currentMaxWidth / screenWidth;
      currentLevel = ((1.0 - ratio) / 0.05).round().clamp(0, 14);
    }

    String getLevelDescription(int level) {
      if (level == 0) return 'מלא';
      final percent = 100 - (level * 5);
      return '$percent%';
    }

    return Column(
      children: [
        ListTile(
          leading: const RtlIcon(FluentIcons.text_align_distributed_24_regular),
          title: const Text(
            'רוחב הטקסט',
            style: kSettingsTitleStyle,
          ),
          subtitle: Text(
            currentLevel == 0
                ? 'הטקסט ימלא את כל הרוחב הזמין'
                : 'הטקסט יהיה צר יותר ומרוכז במסך',
            style: kSettingsSubtitleStyle,
          ),
          trailing: Text(
            getLevelDescription(currentLevel),
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Slider(
            value: currentLevel.toDouble(),
            min: 0,
            max: 14,
            divisions: 14,
            label: getLevelDescription(currentLevel),
            onChanged: (value) {
              setState(() {});
              final level = value.toInt();
              double newMaxWidth;
              if (level == 0) {
                newMaxWidth = 0;
              } else {
                final widthPercent = 1.0 - (level * 0.05);
                newMaxWidth = screenWidth * widthPercent;
              }
              context.read<SettingsBloc>().add(UpdateTextMaxWidth(newMaxWidth));
            },
          ),
        ),
      ],
    );
  }
}
