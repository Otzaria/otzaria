import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/settings_engine_exports.dart';
import 'package:otzaria/settings/search/settings_search_models.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/settings/view/settings_screen.dart';
import 'package:otzaria/settings/widgets/settings_widgets_exports.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/layout/adaptive_row.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/widgets/misc/rtl_icon.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria/core/messages/settings_messages.dart';
import 'package:otzaria/core/ui_snack.dart';

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
      id: 'text.font.continuous_reading',
      title: 'מצב קריאה בתנ"ך ובתלמוד',
      subtitle: 'הצגת השורות ברצף או בנפרד',
      tab: SettingsTab.text,
      cardId: 'text.font',
      keywords: [
        'רצף',
        'רציף',
        'שורות בודדות',
        'קריאה',
        'תנך',
        'תלמוד',
      ],
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
      id: 'text.nikud.punctuation',
      title: 'הצגת סימני פיסוק',
      subtitle: 'הצג / הסתר סימני פיסוק בכל הספרים',
      tab: SettingsTab.text,
      cardId: 'text.nikud',
      keywords: [
        'פיסוק',
        'פסיק',
        'נקודה',
        'הצג',
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
                _buildFontSection(context, settingsState),
                kSettingsCardSpacing,
                _buildNikudSection(context, settingsState),
                kSettingsCardSpacing,
                _buildCopySection(context, settingsState),
                kSettingsCardSpacing,
                _buildPerBookSection(context, settingsState),
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
      cardId: 'text.font',
      title: 'הגדרות גופן ועיצוב',
      children: [
        // שורה 1: גודל גופן הספר + גופן טקסט
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: AdaptiveRow(
            children: [
              _FontSizeSlider(
                icon: OtzariaIcons.alef_near_alef_24_regular,
                label: 'גודל גופן הספר',
                value: state.fontSize.clamp(15, 60),
                min: 15,
                max: 60,
                onChanged: (value) {
                  context.read<SettingsBloc>().add(UpdateFontSize(value));
                },
              ),
              _FontDropdown(
                icon: OtzariaIcons.alef_near_alef_24_regular,
                label: 'גופן טקסט',
                value: state.fontFamily,
                onChanged: (value) {
                  if (value != null) {
                    context.read<SettingsBloc>().add(UpdateFontFamily(value));
                  }
                },
                bold: state.fontBold,
                onBoldChanged: (value) {
                  context.read<SettingsBloc>().add(UpdateFontBold(value));
                },
              ),
            ],
          ),
        ),

        // שורה 2: גודל גופן מפרשים + גופן מפרשים
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: AdaptiveRow(
            children: [
              if (!hideCommentaryFontSize)
                _FontSizeSlider(
                  icon: OtzariaIcons.beit_near_alef_24_regular,
                  label: 'גודל גופן מפרשים',
                  value: state.commentatorsFontSize.clamp(10, 40),
                  min: 10,
                  max: 40,
                  onChanged: (value) {
                    context.read<SettingsBloc>().add(
                      UpdateCommentatorsFontSize(value),
                    );
                  },
                ),
              _FontDropdown(
                icon: OtzariaIcons.beit_near_alef_24_regular,
                label: 'גופן מפרשים',
                value: state.commentatorsFontFamily,
                onChanged: (value) {
                  if (value != null) {
                    context.read<SettingsBloc>().add(
                      UpdateCommentatorsFontFamily(value),
                    );
                  }
                },
                bold: state.commentatorsFontBold,
                onBoldChanged: (value) {
                  context.read<SettingsBloc>().add(
                    UpdateCommentatorsFontBold(value),
                  );
                },
              ),
            ],
          ),
        ),

        // שורה 3: מרווח בין שורות
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < LayoutBreakpoints.compact;
            return Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
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
                        context.read<SettingsBloc>().add(
                          UpdateLineHeight(value),
                        );
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
                              context.read<SettingsBloc>().add(
                                UpdateLineHeight(value),
                              );
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
        SettingsActionTile.segmentedTile<bool>(
          icon: FluentIcons.text_align_justify_24_regular,
          title: 'מצב קריאה בתנ"ך ובתלמוד',
          subtitle: state.defaultContinuousReadingMode
              ? 'השורות יוצגו ברצף עד הכותרת הבאה'
              : 'כל שורה תוצג בנפרד',
          options: const [
            SegmentOption(value: false, label: 'שורות בודדות'),
            SegmentOption(value: true, label: 'רצף'),
          ],
          currentValue: state.defaultContinuousReadingMode,
          onChanged: (value) {
            context.read<SettingsBloc>().add(
              UpdateDefaultContinuousReadingMode(value),
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

    return SettingsCard(
      cardId: 'text.nikud',
      title: 'כתרי אותיות',
      children: [
        SettingsActionTile.segmentedTile<String>(
          icon: OtzariaIcons.alef_with_score_24_regular,
          title: 'הצגת הניקוד',
          options: const [
            SegmentOption(
              value: 'show_always',
              label: 'הצג תמיד',
              subtitle: 'הניקוד יוצג בכל הספרים',
            ),
            SegmentOption(
              value: 'show_tanach_only',
              label: 'הצג בתנ"ך',
              subtitle: 'הניקוד יוצג בספרי התנ"ך בלבד',
            ),
            SegmentOption(
              value: 'hide_all',
              label: 'אל תציג',
              subtitle: 'הניקוד לא יוצג בכלל',
            ),
          ],
          currentValue: nikudValue,
          onChanged: (value) {
            switch (value) {
              case 'show_always':
                context.read<SettingsBloc>().add(
                  const UpdateDefaultRemoveNikud(false),
                );
                break;
              case 'show_tanach_only':
                context.read<SettingsBloc>().add(
                  const UpdateDefaultRemoveNikud(true),
                );
                context.read<SettingsBloc>().add(
                  const UpdateRemoveNikudFromTanach(false),
                );
                break;
              case 'hide_all':
                context.read<SettingsBloc>().add(
                  const UpdateDefaultRemoveNikud(true),
                );
                context.read<SettingsBloc>().add(
                  const UpdateRemoveNikudFromTanach(true),
                );
                break;
            }
          },
        ),
        SettingsActionTile.switchTile(
          icon: OtzariaIcons.alef_with_punctuation_24_regular,
          title: 'הצגת סימני פיסוק',
          subtitle: state.defaultRemovePunctuation
              ? 'סימני הפיסוק לא יוצגו (למעט בתנ"ך)'
              : 'סימני הפיסוק יוצגו בכל הספרים',
          value: !state.defaultRemovePunctuation,
          onChanged: (value) {
            context.read<SettingsBloc>().add(
              UpdateDefaultRemovePunctuation(!value),
            );
          },
        ),
        SettingsActionTile.switchTile(
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
        SettingsActionTile.switchTile(
          icon: OtzariaIcons.alef_with_flavors_24_regular,
          title: 'הצגת טעמי המקרא',
          subtitle: state.showTeamim
              ? 'המקרא יוצג עם טעמים'
              : 'המקרא יוצג ללא טעמים',
          value: state.showTeamim,
          onChanged: (value) {
            context.read<SettingsBloc>().add(UpdateShowTeamim(value));
          },
        ),
      ],
    );
  }

  Widget _buildCopySection(BuildContext context, SettingsState state) {
    return SettingsCard(
      cardId: 'text.copy',
      title: 'העתקת כותרות ופרקים',
      children: [
        SettingsActionTile.segmentedTile<String>(
          icon: FluentIcons.copy_24_regular,
          title: 'העתקת הכותרת',
          options: const [
            SegmentOption(
              value: 'none',
              label: 'ללא',
              subtitle: 'הטקסט יועתק ללא כותרות',
            ),
            SegmentOption(
              value: 'book_name',
              label: 'שם הספר',
              subtitle: 'הטקסט יועתק עם שם הספר בלבד',
            ),
            SegmentOption(
              value: 'book_and_path',
              label: 'שם וכותרת',
              subtitle: 'הטקסט יועתק עם שם הספר ונתיב הטקסט',
            ),
          ],
          currentValue: state.copyWithHeaders,
          onChanged: (value) {
            context.read<SettingsBloc>().add(UpdateCopyWithHeaders(value));
          },
        ),
        if (state.copyWithHeaders != 'none')
          SettingsActionTile.dropdownTile<String>(
            rtlIcon: FluentIcons.text_align_right_24_regular,
            title: 'עיצוב כותרות',
            value: state.copyHeaderFormat,
            entries: const [
              AppMenuEntry(
                value: 'same_line_after_brackets',
                label: 'אותה שורה אחרי (עם סוגריים)',
                subtitle: 'הכותרת תופיע באותה שורה אחרי הטקסט (עם סוגריים)',
              ),
              AppMenuEntry(
                value: 'same_line_after_no_brackets',
                label: 'אותה שורה אחרי (בלי סוגריים)',
                subtitle: 'הכותרת תופיע באותה שורה אחרי הטקסט (בלי סוגריים)',
              ),
              AppMenuEntry(
                value: 'same_line_before_brackets',
                label: 'אותה שורה לפני (עם סוגריים)',
                subtitle: 'הכותרת תופיע באותה שורה לפני הטקסט (עם סוגריים)',
              ),
              AppMenuEntry(
                value: 'same_line_before_no_brackets',
                label: 'אותה שורה לפני (בלי סוגריים)',
                subtitle: 'הכותרת תופיע באותה שורה לפני הטקסט (בלי סוגריים)',
              ),
              AppMenuEntry(
                value: 'separate_line_after',
                label: 'פסקה נפרדת אחרי',
                subtitle: 'הכותרת תופיע בפסקה נפרדת אחרי הטקסט',
              ),
              AppMenuEntry(
                value: 'separate_line_before',
                label: 'פסקה נפרדת לפני',
                subtitle: 'הכותרת תופיע בפסקה נפרדת לפני הטקסט',
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
      cardId: 'text.per_book',
      title: 'הגדרות לפי ספר',
      children: [
        SettingsActionTile.switchTile(
          icon: FluentIcons.book_open_24_regular,
          title: 'שמירת התאמות לכל ספר בנפרד',
          subtitle: state.enablePerBookSettings
              ? 'שינויים בסרגל הלחצנים יישמרו לכל ספר בנפרד'
              : 'כל הספרים ישתמשו בהגדרות הכלליות',
          value: state.enablePerBookSettings,
          onChanged: (value) {
            context.read<SettingsBloc>().add(
              UpdateEnablePerBookSettings(value),
            );
          },
        ),
        if (state.enablePerBookSettings)
          SettingsActionTile.text(
            icon: FluentIcons.delete_24_regular,
            title: 'איפוס הגדרות לפי ספר',
            subtitle: 'מחיקת כל ההתאמות שנשמרו לכל ספר בנפרד',
            actions: [
              ActionButton.ghost(
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
      subtitle: 'פעולה זו אינה ניתנת לביטול!',
      cancelText: 'ביטול',
      confirmText: 'איפוס',
    );

    if (confirm == true && context.mounted) {
      if (await PerBookSettings.deleteAllSettings()) {
        UiSnack.show(SettingsMessages.perBookSettingsReset);
      } else {
        UiSnack.showError(SettingsMessages.perBookSettingsResetFailed);
      }
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
      return OtzariaIcons.alef_behind_alef_24_regular;
    case FontCategory.sansSerif:
      return OtzariaIcons.alef_behind_alef_24_regular;
    case FontCategory.unknown:
      return null;
  }
}

// Widget עזר לדרופדאון גופן
class _FontDropdown extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final ValueChanged<String?> onChanged;

  /// האם הגופן מוצג כעת במשקל מודגש (בולד).
  final bool bold;
  final ValueChanged<bool> onBoldChanged;

  const _FontDropdown({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.bold,
    required this.onBoldChanged,
  });

  @override
  Widget build(BuildContext context) {
    final all = AppFonts.availableFonts;

    // O(n) lookup במקום O(n²) — מחושב פעם אחת לכל build.
    final serifValues = {
      for (final f in all)
        if (f.category == FontCategory.serif) f.value,
    };
    final sansValues = {
      for (final f in all)
        if (f.category == FontCategory.sansSerif) f.value,
    };

    final fontEntries = all
        .map(
          (font) => AppMenuEntry<String>(
            value: font.value,
            label: font.label,
            icon: _fontCategoryIcon(font.category),
            reserveTrailingGap: true,
            trailingReservedWidth: 72,
            labelWidget: _FontPreviewText(
              fontFamily: font.value,
              name: font.label,
              isBundled: AppFonts.fontPaths.containsKey(font.value),
            ),
            trailing: SizedBox(
              width: 72,
              child: Opacity(
                opacity: 0.6,
                child: _FontPreviewText(
                  fontFamily: font.value,
                  name: _kFontSampleText,
                  isBundled: AppFonts.fontPaths.containsKey(font.value),
                ),
              ),
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
            filterLabels: const ['הכל', 'Serif', 'Sans'],
            filterPredicates: [
              null,
              (e) => serifValues.contains(e.value),
              (e) => sansValues.contains(e.value),
            ],
            menuMinWidth: 260,
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
        const SizedBox(width: 8),
        IconButton(
          tooltip: bold ? 'הצגה במשקל רגיל' : 'הדגשת הגופן (בולד)',
          isSelected: bold,
          onPressed: () => onBoldChanged(!bold),
          icon: const Icon(FluentIcons.text_bold_24_regular),
          selectedIcon: const Icon(FluentIcons.text_bold_24_filled),
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
  final bool isBundled;

  const _FontPreviewText({
    required this.fontFamily,
    required this.name,
    required this.isBundled,
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
    return Text(
      widget.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontFamily: family),
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
    final currentMaxWidth = widget.state.textMaxWidth;

    // ערך חיובי (פיקסלים) הוא פורמט ישן — מומר לרמה לפי רוחב המסך הנוכחי
    int currentLevel;
    if (currentMaxWidth < 0) {
      currentLevel = (-currentMaxWidth).toInt();
    } else if (currentMaxWidth == 0) {
      currentLevel = 0;
    } else {
      final ratio = currentMaxWidth / MediaQuery.of(context).size.width;
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
              // נשמר כרמה שלילית (-level) כדי שהאחוז יחושב מרוחב
              // עמודת הטקסט בפועל, לא מרוחב המסך בזמן השמירה
              final level = value.toInt();
              context.read<SettingsBloc>().add(
                UpdateTextMaxWidth(level == 0 ? 0 : -level.toDouble()),
              );
            },
          ),
        ),
      ],
    );
  }
}
