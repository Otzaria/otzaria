import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/settings_engine_exports.dart';
import 'package:otzaria/settings/l10n/settings_text.dart';
import 'package:otzaria/settings/search/settings_search_models.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/settings/tabs/text_display_settings_section.dart';
import 'package:otzaria/settings/view/settings_screen.dart';
import 'package:otzaria/settings/widgets/settings_widgets_exports.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/layout/adaptive_row.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/widgets/misc/rtl_icon.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria/core/messages/settings_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/settings/widgets/settings_tab_scroll_view.dart';

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
      keywords: ['רוחב', 'עמודה', 'סנטימטר'],
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
      title: 'תצוגת הטקסט',
      subtitle:
          'ניקוד, טעמים, פיסוק, שם הוי"ה וציוני המפרשים — בתצוגה, בהעתקה ובייצוא',
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
        'יקוק',
        "ה'",
        'יי',
        'הוי"ה',
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
        final content = SettingsTabScrollView(
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
      title: context.settingsText('הגדרות גופן ועיצוב'),
      children: [
        // שורה 1: גודל גופן הספר + גופן טקסט
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: AdaptiveRow(
            children: [
              _FontSizeSlider(
                applyWhileDragging: isDialog,
                icon: OtzariaIcons.alef_near_alef_24_filled,
                label: context.settingsText('גודל גופן הספר'),
                value: state.fontSize.clamp(15, 60),
                min: 15,
                max: 60,
                onChanged: (value) {
                  context.read<SettingsBloc>().add(UpdateFontSize(value));
                },
              ),
              _FontDropdown(
                icon: OtzariaIcons.alef_alef_24_filled,
                label: context.settingsText('גופן טקסט'),
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
                  applyWhileDragging: isDialog,
                  icon: OtzariaIcons.beit_near_alef_24_filled,
                  label: context.settingsText('גודל גופן מפרשים'),
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
                icon: OtzariaIcons.beit_behind_alef_24_filled,
                label: context.settingsText('גופן מפרשים'),
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
                      applyWhileDragging: isDialog,
                      icon: FluentIcons
                          .text_align_distributed_vertical_24_regular,
                      label: context.settingsText('מרווח בין שורות'),
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
                            applyWhileDragging: isDialog,
                            icon: FluentIcons
                                .text_align_distributed_vertical_24_regular,
                            label: context.settingsText('מרווח בין שורות'),
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

        _TextWidthSlider(state: state, applyWhileDragging: isDialog),
        SettingsActionTile.segmentedTile<bool>(
          icon: FluentIcons.text_align_justify_24_regular,
          title: context.settingsText('מצב קריאה בתנ"ך ובתלמוד'),
          subtitle: context.settingsText(
            state.defaultContinuousReadingMode
                ? 'השורות יוצגו ברצף עד הכותרת הבאה'
                : 'כל שורה תוצג בנפרד',
          ),
          options: [
            SegmentOption(
              value: false,
              label: context.settingsText('שורות בודדות'),
            ),
            SegmentOption(value: true, label: context.settingsText('רצף')),
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

  Widget _buildNikudSection(BuildContext context, SettingsState state) =>
      const TextDisplaySettingsCard();

  Widget _buildCopySection(BuildContext context, SettingsState state) {
    return SettingsCard(
      cardId: 'text.copy',
      title: context.settingsText('העתקת כותרות ופרקים'),
      children: [
        SettingsActionTile.segmentedTile<String>(
          icon: FluentIcons.copy_24_regular,
          title: context.settingsText('העתקת הכותרת'),
          options: [
            SegmentOption(
              value: 'none',
              label: context.settingsText('ללא'),
              subtitle: context.settingsText('הטקסט יועתק ללא כותרות'),
            ),
            SegmentOption(
              value: 'book_name',
              label: context.settingsText('שם הספר'),
              subtitle: context.settingsText('הטקסט יועתק עם שם הספר בלבד'),
            ),
            SegmentOption(
              value: 'book_and_path',
              label: context.settingsText('שם וכותרת'),
              subtitle: context.settingsText(
                'הטקסט יועתק עם שם הספר ונתיב הטקסט',
              ),
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
            title: context.settingsText('עיצוב כותרות'),
            value: state.copyHeaderFormat,
            entries: [
              AppMenuEntry(
                value: 'same_line_after_brackets',
                label: context.settingsText('אותה שורה אחרי (עם סוגריים)'),
                subtitle: context.settingsText(
                  'הכותרת תופיע באותה שורה אחרי הטקסט (עם סוגריים)',
                ),
              ),
              AppMenuEntry(
                value: 'same_line_after_no_brackets',
                label: context.settingsText('אותה שורה אחרי (בלי סוגריים)'),
                subtitle: context.settingsText(
                  'הכותרת תופיע באותה שורה אחרי הטקסט (בלי סוגריים)',
                ),
              ),
              AppMenuEntry(
                value: 'same_line_before_brackets',
                label: context.settingsText('אותה שורה לפני (עם סוגריים)'),
                subtitle: context.settingsText(
                  'הכותרת תופיע באותה שורה לפני הטקסט (עם סוגריים)',
                ),
              ),
              AppMenuEntry(
                value: 'same_line_before_no_brackets',
                label: context.settingsText('אותה שורה לפני (בלי סוגריים)'),
                subtitle: context.settingsText(
                  'הכותרת תופיע באותה שורה לפני הטקסט (בלי סוגריים)',
                ),
              ),
              AppMenuEntry(
                value: 'separate_line_after',
                label: context.settingsText('פסקה נפרדת אחרי'),
                subtitle: context.settingsText(
                  'הכותרת תופיע בפסקה נפרדת אחרי הטקסט',
                ),
              ),
              AppMenuEntry(
                value: 'separate_line_before',
                label: context.settingsText('פסקה נפרדת לפני'),
                subtitle: context.settingsText(
                  'הכותרת תופיע בפסקה נפרדת לפני הטקסט',
                ),
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
      title: context.settingsText('הגדרות לפי ספר'),
      children: [
        SettingsActionTile.switchTile(
          icon: OtzariaIcons.otzaria_icon_2_page_24_regular,
          title: context.settingsText('שמירת התאמות לכל ספר בנפרד'),
          subtitle: context.settingsText(
            state.enablePerBookSettings
                ? 'גודל הגופן, הניקוד והמפרשים שנקבעו בספר יישמרו לו בנפרד. סוג הגופן נשאר כללי'
                : 'כל הספרים ישתמשו בהגדרות הכלליות',
          ),
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
            title: context.settingsText('איפוס הגדרות לפי ספר'),
            subtitle: context.settingsText(
              'מחיקת כל ההתאמות שנשמרו לכל ספר בנפרד',
            ),
            actions: [
              ActionButton.ghost(
                onPressed: () => _resetPerBookSettings(context),
                text: context.settingsText('איפוס'),
              ),
            ],
          ),
      ],
    );
  }

  Future<void> _resetPerBookSettings(BuildContext context) async {
    final confirm = await showWarningDialog(
      context: context,
      title: context.settingsText('אישור איפוס הגדרות לפי ספר'),
      content: context.settingsText(
        'האם אתה בטוח שברצונך לאפס ולמחוק את כל ההגדרות לפי ספר?',
      ),
      subtitle: context.settingsText('פעולה זו אינה ניתנת לביטול!'),
      cancelText: context.settingsText('ביטול'),
      confirmText: context.settingsText('איפוס'),
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

  /// במסך ההגדרות המלא הספרים מוסתרים, וכל צעד בונה מחדש את כל הכרטיסיות
  /// הפתוחות; לכן שם הערך מוחל רק בסוף הגרירה.
  final bool applyWhileDragging;

  const _FontSizeSlider({
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    required this.onChanged,
    required this.applyWhileDragging,
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
    final valueLabel = widget.divisions != null
        ? _currentValue.toStringAsFixed(1)
        : _currentValue.toStringAsFixed(0);
    return SettingsSliderTile(
      icon: widget.icon,
      title: widget.label,
      valueLabel: valueLabel,
      value: _currentValue,
      min: widget.min,
      max: widget.max,
      divisions: widget.divisions ?? (widget.max - widget.min).toInt(),
      onChanged: (value) {
        setState(() => _currentValue = value);
        if (widget.applyWhileDragging) widget.onChanged(value);
      },
      onChangeEnd: widget.applyWhileDragging ? null : widget.onChanged,
    );
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
          child: FontDropdownField(
            value: value,
            onChanged: onChanged,
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: context.settingsText(
            bold ? 'הצגה במשקל רגיל' : 'הדגשת הגופן (בולד)',
          ),
          isSelected: bold,
          onPressed: () => onBoldChanged(!bold),
          icon: const Icon(FluentIcons.text_bold_24_regular),
          selectedIcon: const Icon(FluentIcons.text_bold_24_filled),
        ),
      ],
    );
  }
}

// Widget עזר לסליידר רוחב טקסט
class _TextWidthSlider extends StatefulWidget {
  final SettingsState state;

  /// כמו ב-[_FontSizeSlider]: במסך המלא הערך מוחל רק בסוף הגרירה.
  final bool applyWhileDragging;

  const _TextWidthSlider({
    required this.state,
    required this.applyWhileDragging,
  });

  @override
  State<_TextWidthSlider> createState() => _TextWidthSliderState();
}

class _TextWidthSliderState extends State<_TextWidthSlider> {
  // תצוגה בס"מ משוערים לפי 96 DPI; נשמר בפיקסלים לוגיים.
  static const double _pxPerCm = 96 / 2.54;
  static const int _minCm = 10;
  static const int _maxCm = 40;
  static const int _fullStop = _maxCm + 1;

  int? _draggedStop;

  @override
  void didUpdateWidget(_TextWidthSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.textMaxWidth != widget.state.textMaxWidth) {
      _draggedStop = null;
    }
  }

  void _apply(double value) {
    final stop = value.round();
    context.read<SettingsBloc>().add(
      UpdateTextMaxWidth(stop >= _fullStop ? 0 : stop * _pxPerCm),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stored = widget.state.textMaxWidth;
    final storedStop = stored <= 0
        ? _fullStop
        : (stored / _pxPerCm).round().clamp(_minCm, _maxCm);
    final currentStop = _draggedStop ?? storedStop;
    final isFull = currentStop >= _fullStop;
    final description = isFull
        ? context.settingsText('מלא')
        : context.settingsText('{cm} ס"מ', args: {'cm': currentStop});

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: SettingsSliderTile(
        icon: FluentIcons.text_align_distributed_24_regular,
        title: context.settingsText('רוחב הטקסט'),
        subtitle: context.settingsText(
          isFull
              ? 'הטקסט ימלא את כל הרוחב הזמין'
              : 'רוחב קבוע, מצטמצם רק כשאין מקום',
        ),
        valueLabel: description,
        value: currentStop.toDouble(),
        min: _minCm.toDouble(),
        max: _fullStop.toDouble(),
        divisions: _fullStop - _minCm,
        onChanged: (value) {
          setState(() => _draggedStop = value.round());
          if (widget.applyWhileDragging) _apply(value);
        },
        onChangeEnd: widget.applyWhileDragging ? null : _apply,
      ),
    );
  }
}
