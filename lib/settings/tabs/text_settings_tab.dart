import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/settings_engine_exports.dart';
import 'package:otzaria/settings/search/settings_anchor.dart';
import 'package:otzaria/settings/search/settings_search_models.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/settings/settings_card.dart';
import 'package:otzaria/settings/view/settings_screen.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria/core/ui_snack.dart';

/// טאב הגדרות תצוגת ספרים
/// ניתן להשתמש בו גם כתוכן בתוך דיאלוג וגם כטאב במסך הגדרות
class TextSettingsTab extends StatelessWidget {
  /// האם להציג כדיאלוג (עם כפתור סגירה) או כטאב (ללא)
  final bool isDialog;

  const TextSettingsTab({super.key, this.isDialog = false});

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
      keywords: ['ניקוד', 'תנך'],
    ),
    SettingsSearchEntry(
      id: 'text.nikud.holy_names',
      title: 'הצגת שם הקודש',
      subtitle: 'הסתרת שם השם משיקולי קדושה',
      tab: SettingsTab.text,
      cardId: 'text.nikud',
      keywords: ['שם השם', 'קדושה'],
    ),
    SettingsSearchEntry(
      id: 'text.nikud.teamim',
      title: 'הצגת טעמי המקרא',
      subtitle: 'הצג טעמים בתנ"ך',
      tab: SettingsTab.text,
      cardId: 'text.nikud',
      keywords: ['טעמים', 'מקרא'],
    ),
    SettingsSearchEntry(
      id: 'text.copy.with_headers',
      title: 'העתקת הכותרת',
      subtitle: 'העתקת הטקסט עם שם הספר וכותרות',
      tab: SettingsTab.text,
      cardId: 'text.copy',
      keywords: ['העתק', 'כותרת'],
    ),
    SettingsSearchEntry(
      id: 'text.copy.format',
      title: 'עיצוב כותרות',
      subtitle: 'עיצוב כותרות בעת העתקה',
      tab: SettingsTab.text,
      cardId: 'text.copy',
      keywords: ['העתק', 'כותרת', 'פורמט'],
    ),
    SettingsSearchEntry(
      id: 'text.per_book.enable',
      title: 'שמירת התאמות לכל ספר בנפרד',
      subtitle: 'שינויי תצוגה ייחודיים לכל ספר',
      tab: SettingsTab.text,
      cardId: 'text.per_book',
      keywords: ['ספר נפרד', 'התאמה אישית'],
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
    return SettingsCard(
      title: 'הגדרות גופן ועיצוב',
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < LayoutBreakpoints.compact;
            final colorScheme = Theme.of(context).colorScheme;
            final divider = Divider(
              height: 1,
              thickness: 1.5,
              color: colorScheme.surfaceContainerHighest,
            );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // שורה 1: גודל גופן הספר + גופן טקסט
                if (isNarrow) ...[
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: _FontSizeSlider(
                      icon: FluentIcons.text_font_size_24_regular,
                      label: 'גודל גופן הספר',
                      value: state.fontSize.clamp(15, 60),
                      min: 15,
                      max: 60,
                      onChanged: (value) {
                        context.read<SettingsBloc>().add(UpdateFontSize(value));
                      },
                    ),
                  ),
                  divider,
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: _FontDropdown(
                      icon: FluentIcons.text_font_24_regular,
                      label: 'גופן טקסט',
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
                ] else
                  Padding(
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
                  ),

                divider,

                // שורה 2: גודל גופן מפרשים + גופן מפרשים
                if (isNarrow) ...[
                  Padding(
                    padding: const EdgeInsets.all(16.0),
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
                  divider,
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: _FontDropdown(
                      icon: FluentIcons.book_24_regular,
                      label: 'גופן מפרשים',
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
                ] else
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                        Expanded(
                          child: _FontDropdown(
                            icon: FluentIcons.book_24_regular,
                            label: 'גופן מפרשים',
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
                  ),

                divider,

                // שורה 3: מרווח בין שורות (תמיד חצי רוחב)
                Padding(
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
                ),
                divider,
                _TextWidthSlider(state: state),
              ],
            );
          },
        ),
      ],
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
          icon: FluentIcons.text_font_info_24_regular,
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
        SwitchSettingsTile(
          leading: const Icon(FluentIcons.shield_keyhole_24_regular),
          title: RichText(
            text: TextSpan(
              style: kSettingsTitleStyle.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
              ),
              children: const [
                TextSpan(text: 'הצגת שם הקודש'),
              ],
            ),
          ),
          subtitle: Text(
            !state.replaceHolyNames
                ? 'השם הקדוש יוצג'
                : 'השם הקדוש לא יוצג מפני קדושתו',
            style: kSettingsSubtitleStyle,
          ),
          value: !state.replaceHolyNames,
          onChanged: (value) {
            context.read<SettingsBloc>().add(UpdateReplaceHolyNames(!value));
          },
        ),
        SwitchSettingsTile(
          title: const Text('הצגת טעמי המקרא', style: kSettingsTitleStyle),
          subtitle: Text(
              state.showTeamim ? 'המקרא יוצג עם טעמים' : 'המקרא יוצג ללא טעמים',
              style: kSettingsSubtitleStyle),
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
          icon: FluentIcons.copy_24_regular,
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
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < LayoutBreakpoints.compact;

              const formatEntries = [
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
              ];

              void onFormatSelected(String? value) {
                if (value != null) {
                  context
                      .read<SettingsBloc>()
                      .add(UpdateCopyHeaderFormat(value));
                }
              }

              if (isNarrow) {
                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(FluentIcons.text_align_right_24_regular),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('עיצוב כותרות',
                                    style: kSettingsTitleStyle),
                                Text(formatSubtitle,
                                    style: kSettingsSubtitleStyle),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      AppDropdownField<String>(
                        value: state.copyHeaderFormat,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        entries: formatEntries,
                        onSelected: onFormatSelected,
                      ),
                    ],
                  ),
                );
              }

              return ListTile(
                leading: const Icon(FluentIcons.text_align_right_24_regular),
                title: const Text('עיצוב כותרות', style: kSettingsTitleStyle),
                subtitle: Text(formatSubtitle, style: kSettingsSubtitleStyle),
                trailing: SizedBox(
                  width: 220,
                  child: AppDropdownField<String>(
                    value: state.copyHeaderFormat,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    entries: formatEntries,
                    onSelected: onFormatSelected,
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildPerBookSection(BuildContext context, SettingsState state) {
    return SettingsCard(
      title: 'הגדרות לפי ספר',
      children: [
        SwitchSettingsTile(
          title: const Text('שמירת התאמות לכל ספר בנפרד',
              style: kSettingsTitleStyle),
          subtitle: Text(
              state.enablePerBookSettings
                  ? 'שינויים בסרגל הלחצנים יישמרו לכל ספר בנפרד'
                  : 'כל הספרים ישתמשו בהגדרות הכלליות',
              style: kSettingsSubtitleStyle),
          value: state.enablePerBookSettings,
          onChanged: (value) {
            context
                .read<SettingsBloc>()
                .add(UpdateEnablePerBookSettings(value));
          },
        ),
        if (state.enablePerBookSettings)
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: NeutralActionButton(
              onPressed: () => _resetPerBookSettings(context),
              icon: FluentIcons.delete_24_regular,
              text: 'אפס את כל הגדרות אלו, בכל הספרים',
            ),
          ),
      ],
    );
  }

  Future<void> _resetPerBookSettings(BuildContext context) async {
    final confirm = await showWarningDialog(
      context: context,
      title: 'אישור מחיקה',
      content: 'האם אתה בטוח שברצונך למחוק את כל ההגדרות לפי ספר?',
      subtitle: 'פעולה זו אינה ניתנת לביטול.',
      cancelText: 'ביטול',
      confirmText: 'מחק הכל',
    );

    if (confirm == true && context.mounted) {
      await PerBookSettings.deleteAllSettings();
      UiSnack.show('כל ההגדרות המיוחדות נמחקו בהצלחה');
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
            Icon(widget.icon),
            const SizedBox(width: 12),
            Expanded(
              child: Text(widget.label, style: kSettingsTitleStyle),
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

// Widget עזר לדרופדאון גופן
class _FontDropdown extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final ValueChanged<String?> onChanged;

  const _FontDropdown({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final fontEntries = AppFonts.availableFonts
        .map((font) => AppMenuEntry(value: font.value, label: font.label))
        .toList();
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
        Icon(icon),
        const SizedBox(width: 8),
        SizedBox(
          width: 100,
          child: Text(label, style: kSettingsTitleStyle),
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
              final matchingFont = AppFonts.availableFonts.firstWhere(
                (font) => font.value == selectedValue,
                orElse: () => FontInfo(
                  value: selectedValue ?? '',
                  label: selectedValue ?? '',
                ),
              );
              return Text(
                matchingFont.label,
                style: TextStyle(
                  fontFamily: AppFonts.fontPaths.containsKey(matchingFont.value)
                      ? matchingFont.value
                      : null,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              );
            },
            onSelected: onChanged,
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
          leading: const Icon(FluentIcons.text_align_justify_24_regular),
          title: const Text('רוחב הטקסט', style: kSettingsTitleStyle),
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
