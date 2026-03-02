import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/theme/fonts.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/settings/settings_card.dart';
import 'package:otzaria/widgets/custom_ui_components.dart';

/// טאב הגדרות תצוגת ספרים
/// ניתן להשתמש בו גם כתוכן בתוך דיאלוג וגם כטאב במסך הגדרות
class TextSettingsTab extends StatelessWidget {
  /// האם להציג כדיאלוג (עם כפתור סגירה) או כטאב (ללא)
  final bool isDialog;

  const TextSettingsTab({super.key, this.isDialog = false});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, settingsState) {
        final content = SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildFontSection(context, settingsState),
              const SizedBox(height: 16),
              _buildHolyNamesSection(context, settingsState),
              const SizedBox(height: 16),
              _buildNikudSection(context, settingsState),
              const SizedBox(height: 16),
              _buildCopySection(context, settingsState),
              const SizedBox(height: 16),
              _buildPerBookSection(context, settingsState),
            ],
          ),
        );

        if (isDialog) {
          return content;
        }
        return content;
      },
    );
  }

  Widget _buildFontSection(BuildContext context, SettingsState state) {
    return SettingsCard(
      title: 'הגדרות גופן ועיצוב',
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // גודל גופן הספר
              Expanded(
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
              const SizedBox(width: 16),
              // גופן טקסט
              Expanded(
                child: _FontDropdown(
                  icon: FluentIcons.text_font_24_regular,
                  label: 'גופן טקסט',
                  value: state.fontFamily,
                  onChanged: (value) {
                    if (value != null) {
                      context.read<SettingsBloc>().add(UpdateFontFamily(value));
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 16.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // גודל גופן מפרשים
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
              // גופן מפרשים
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
        Padding(
          padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 16.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // מרווח בין שורות
              Expanded(
                child: _FontSizeSlider(
                  icon: FluentIcons.text_align_distributed_vertical_24_regular,
                  label: 'מרווח בין שורות',
                  value: state.lineHeight.clamp(1.0, 3.0),
                  min: 1.0,
                  max: 3.0,
                  divisions: 20,
                  onChanged: (value) {
                    context.read<SettingsBloc>().add(UpdateLineHeight(value));
                  },
                ),
              ),
              const SizedBox(width: 16),
              // מקום ריק לאיזון
              const Expanded(child: SizedBox()),
            ],
          ),
        ),
        const Divider(height: 1),
        _TextWidthSlider(state: state),
      ],
    );
  }

  Widget _buildNikudSection(BuildContext context, SettingsState state) {
    return SettingsCard(
      title: 'טעמים ונקודות',
      children: [
        SwitchListTile(
          title: const Text('הצגת טעמי המקרא', style: TextStyle(fontSize: 16)),
          subtitle: Text(
              state.showTeamim ? 'המקרא יוצג עם טעמים' : 'המקרא יוצג ללא טעמים',
              style: const TextStyle(fontSize: 13)),
          value: state.showTeamim,
          onChanged: (value) {
            context.read<SettingsBloc>().add(UpdateShowTeamim(value));
          },
        ),
        const Divider(height: 1),
        SwitchListTile(
          title: const Text('הסרת ניקוד כברירת מחדל',
              style: TextStyle(fontSize: 16)),
          subtitle: Text(
              state.defaultRemoveNikud
                  ? 'הניקוד יוסר כברירת מחדל'
                  : 'הניקוד יוצג כברירת מחדל',
              style: const TextStyle(fontSize: 13)),
          value: state.defaultRemoveNikud,
          onChanged: (value) {
            context.read<SettingsBloc>().add(UpdateDefaultRemoveNikud(value));
          },
        ),
        if (state.defaultRemoveNikud)
          Padding(
            padding: const EdgeInsets.only(right: 32.0),
            child: CheckboxListTile(
              title: const Text('הסרת ניקוד מספרי התנ"ך',
                  style: TextStyle(fontSize: 16)),
              subtitle: const Text('גם ספרי התנ"ך יוצגו ללא ניקוד',
                  style: TextStyle(fontSize: 13)),
              value: state.removeNikudFromTanach,
              onChanged: (value) {
                if (value != null) {
                  context
                      .read<SettingsBloc>()
                      .add(UpdateRemoveNikudFromTanach(value));
                }
              },
            ),
          ),
      ],
    );
  }

  Widget _buildHolyNamesSection(BuildContext context, SettingsState state) {
    return SettingsCard(
      title: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          children: [
            TextSpan(
              text: 'שבח מגדל עוז ',
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
            TextSpan(
              text: 'שם הגדול',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ),
      ),
      children: [
        SegmentedSettingsTile<bool>(
          icon: FluentIcons.shield_keyhole_24_regular,
          title: 'בישראל גדול שמו',
          subtitle: '',
          options: const [
            SegmentOption(value: false, label: 'זה שמי לעלם'),
            SegmentOption(value: true, label: 'לא כשאני נכתב'),
          ],
          currentValue: state.replaceHolyNames,
          onChanged: (value) {
            context.read<SettingsBloc>().add(UpdateReplaceHolyNames(value));
          },
        ),
      ],
    );
  }

  Widget _buildCopySection(BuildContext context, SettingsState state) {
    return SettingsCard(
      title: 'הגדרות העתקה',
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(FluentIcons.copy_24_regular),
                    const SizedBox(width: 8),
                    Text('העתקה עם כותרות',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: state.copyWithHeaders,
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        isExpanded: true,
                        items: const [
                          DropdownMenuItem(value: 'none', child: Text('ללא')),
                          DropdownMenuItem(
                              value: 'book_name', child: Text('שם הספר בלבד')),
                          DropdownMenuItem(
                              value: 'book_and_path',
                              child: Text('שם הספר+נתיב')),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            context
                                .read<SettingsBloc>()
                                .add(UpdateCopyWithHeaders(value));
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Row(
                  children: [
                    const Icon(FluentIcons.text_align_right_24_regular),
                    const SizedBox(width: 8),
                    Text('עיצוב העתקה',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: state.copyHeaderFormat,
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        isExpanded: true,
                        items: const [
                          DropdownMenuItem(
                              value: 'same_line_after_brackets',
                              child: Text('אותה שורה אחרי (עם סוגריים)')),
                          DropdownMenuItem(
                              value: 'same_line_after_no_brackets',
                              child: Text('אותה שורה אחרי (בלי סוגריים)')),
                          DropdownMenuItem(
                              value: 'same_line_before_brackets',
                              child: Text('אותה שורה לפני (עם סוגריים)')),
                          DropdownMenuItem(
                              value: 'same_line_before_no_brackets',
                              child: Text('אותה שורה לפני (בלי סוגריים)')),
                          DropdownMenuItem(
                              value: 'separate_line_after',
                              child: Text('פסקה נפרדת אחרי')),
                          DropdownMenuItem(
                              value: 'separate_line_before',
                              child: Text('פסקה נפרדת לפני')),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            context
                                .read<SettingsBloc>()
                                .add(UpdateCopyHeaderFormat(value));
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPerBookSection(BuildContext context, SettingsState state) {
    return SettingsCard(
      title: 'הגדרות לפי ספר',
      children: [
        SwitchListTile(
          title: const Text('שמירת התאמות לכל ספר בנפרד',
              style: TextStyle(fontSize: 16)),
          subtitle: Text(
              state.enablePerBookSettings
                  ? 'שינויים בסרגל הלחצנים יישמרו לכל ספר בנפרד'
                  : 'כל הספרים ישתמשו בהגדרות הכלליות',
              style: const TextStyle(fontSize: 13)),
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
            child: ElevatedButton.icon(
              onPressed: () => _resetPerBookSettings(context),
              icon: const Icon(FluentIcons.delete_24_regular),
              label: const Text('אפס את כל הגדרות אלו, בכל הספרים'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.errorContainer,
                foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _resetPerBookSettings(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('אישור מחיקה'),
        content: const Text(
            'האם אתה בטוח שברצונך למחוק את כל ההגדרות לפי ספר?\nפעולה זו אינה ניתנת לביטול.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('מחק הכל'),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      await PerBookSettings.deleteAllSettings();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('כל ההגדרות הפר-ספריות נמחקו בהצלחה')),
        );
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
            Icon(widget.icon),
            const SizedBox(width: 12),
            Expanded(
              child: Text(widget.label,
                  style: Theme.of(context).textTheme.titleMedium),
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
    return Row(
      children: [
        Icon(icon),
        const SizedBox(width: 8),
        SizedBox(
          width: 100,
          child: Text(label, style: Theme.of(context).textTheme.titleMedium),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: value,
            decoration: InputDecoration(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            dropdownColor: Theme.of(context).colorScheme.surface,
            isExpanded: true,
            items: AppFonts.buildDropdownItems(),
            onChanged: onChanged,
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
          title: const Text('רוחב הטקסט', style: TextStyle(fontSize: 16)),
          subtitle: Text(
            currentLevel == 0
                ? 'הטקסט ימלא את כל הרוחב הזמין'
                : 'הטקסט יהיה צר יותר ומרוכז במסך',
            style: const TextStyle(fontSize: 13),
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
