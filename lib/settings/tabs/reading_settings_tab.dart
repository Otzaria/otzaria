import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/constants/fonts.dart';
import 'package:otzaria/settings/settings_bloc.dart';
import 'package:otzaria/settings/settings_event.dart';
import 'package:otzaria/settings/settings_state.dart';
import 'package:otzaria/settings/per_book_settings.dart';

/// טאב הגדרות תצוגת ספרים
/// ניתן להשתמש בו גם כתוכן בתוך דיאלוג וגם כטאב במסך הגדרות
class ReadingSettingsTab extends StatelessWidget {
  /// האם להציג כדיאלוג (עם כפתור סגירה) או כטאב (ללא)
  final bool isDialog;

  const ReadingSettingsTab({super.key, this.isDialog = false});

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
              _buildNikudSection(context, settingsState),
              const SizedBox(height: 16),
              _buildTabsSection(context, settingsState),
              const SizedBox(height: 16),
              _buildSidebarSection(context, settingsState),
              const SizedBox(height: 16),
              _buildCopySection(context, settingsState),
              const SizedBox(height: 16),
              _buildPerBookSection(context, settingsState),
              const SizedBox(height: 16),
              _buildEditorSection(context),
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

  Widget _buildSectionCard({
    required BuildContext context,
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(11)),
            ),
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _buildFontSection(BuildContext context, SettingsState state) {
    return _buildSectionCard(
      context: context,
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
        const Divider(height: 1),
        _TextWidthSlider(state: state),
      ],
    );
  }

  Widget _buildNikudSection(BuildContext context, SettingsState state) {
    return _buildSectionCard(
      context: context,
      title: 'הסרת ניקוד וטעמים',
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

  Widget _buildTabsSection(BuildContext context, SettingsState state) {
    return _buildSectionCard(
      context: context,
      title: 'הגדרות טאבים',
      children: [
        SwitchListTile(
          title:
              const Text('יישור טאבים לימין', style: TextStyle(fontSize: 16)),
          subtitle: Text(
              state.alignTabsToRight
                  ? 'הטאבים יוצגו בצד ימין'
                  : 'הטאבים יוצגו במרכז',
              style: const TextStyle(fontSize: 13)),
          value: state.alignTabsToRight,
          onChanged: (value) {
            context.read<SettingsBloc>().add(UpdateAlignTabsToRight(value));
          },
        ),
      ],
    );
  }

  Widget _buildSidebarSection(BuildContext context, SettingsState state) {
    return _buildSectionCard(
      context: context,
      title: 'התנהגות סרגל צד',
      children: [
        SwitchListTile(
          title: const Text('הצמדת סרגל צד', style: TextStyle(fontSize: 16)),
          subtitle: Text(
              state.pinSidebar ? 'סרגל הצד יוצמד תמיד' : 'סרגל הצד יפעל כרגיל',
              style: const TextStyle(fontSize: 13)),
          value: state.pinSidebar,
          onChanged: (value) {
            context.read<SettingsBloc>().add(UpdatePinSidebar(value));
            if (value) {
              context
                  .read<SettingsBloc>()
                  .add(const UpdateDefaultSidebarOpen(true));
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
        SwitchListTile(
          title: const Text('פתיחת סרגל צד כברירת מחדל',
              style: TextStyle(fontSize: 16)),
          subtitle: Text(
              state.defaultSidebarOpen
                  ? 'סרגל הצד יפתח אוטומטית'
                  : 'סרגל הצד ישאר סגור',
              style: const TextStyle(fontSize: 13)),
          value: state.defaultSidebarOpen,
          onChanged: state.pinSidebar
              ? null
              : (value) {
                  context
                      .read<SettingsBloc>()
                      .add(UpdateDefaultSidebarOpen(value));
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
                    defaultRemoveNikud: settingsBloc.state.defaultRemoveNikud,
                    defaultShowSplitView: value,
                  );
                });
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildCopySection(BuildContext context, SettingsState state) {
    return _buildSectionCard(
      context: context,
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
    return _buildSectionCard(
      context: context,
      title: 'הגדרות פר-ספר',
      children: [
        SwitchListTile(
          title:
              const Text('שמירת התאמות פר-ספר', style: TextStyle(fontSize: 16)),
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

  Widget _buildEditorSection(BuildContext context) {
    return _buildSectionCard(
      context: context,
      title: 'הגדרות עורך טקסטים',
      children: [
        _EditorSettings(),
      ],
    );
  }

  Future<void> _resetPerBookSettings(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('אישור מחיקה'),
        content: const Text(
            'האם אתה בטוח שברצונך למחוק את כל ההגדרות הפר-ספריות?\nפעולה זו אינה ניתנת לביטול.'),
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
  final ValueChanged<double> onChanged;

  const _FontSizeSlider({
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
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
              _currentValue.toStringAsFixed(0),
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
          divisions: (widget.max - widget.min).toInt(),
          label: _currentValue.toStringAsFixed(0),
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

// Widget עזר להגדרות עורך
class _EditorSettings extends StatefulWidget {
  @override
  State<_EditorSettings> createState() => _EditorSettingsState();
}

class _EditorSettingsState extends State<_EditorSettings> {
  late double previewDebounce;
  late double cleanupDays;
  late double draftsQuota;

  @override
  void initState() {
    super.initState();
    previewDebounce =
        Settings.getValue<double>('key-editor-preview-debounce') ?? 150.0;
    cleanupDays =
        Settings.getValue<double>('key-editor-draft-cleanup-days') ?? 30.0;
    draftsQuota = Settings.getValue<double>('key-editor-drafts-quota') ?? 100.0;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSlider(
            icon: FluentIcons.timer_24_regular,
            label: 'זמן עיכוב במילישניות',
            value: previewDebounce,
            min: 50,
            max: 300,
            divisions: 5,
            onChanged: (value) {
              setState(() => previewDebounce = value);
              Settings.setValue<double>('key-editor-preview-debounce', value);
            },
          ),
          const Divider(),
          _buildSlider(
            icon: FluentIcons.delete_dismiss_24_regular,
            label: 'ניקוי טיוטות ישנות (ימים)',
            value: cleanupDays,
            min: 7,
            max: 90,
            divisions: 12,
            onChanged: (value) {
              setState(() => cleanupDays = value);
              Settings.setValue<double>('key-editor-draft-cleanup-days', value);
            },
          ),
          const Divider(),
          _buildSlider(
            icon: FluentIcons.database_24_regular,
            label: 'מכסת טיוטות (MB)',
            value: draftsQuota,
            min: 50,
            max: 100,
            divisions: 5,
            onChanged: (value) {
              setState(() => draftsQuota = value);
              Settings.setValue<double>('key-editor-drafts-quota', value);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSlider({
    required IconData icon,
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon),
            const SizedBox(width: 12),
            Expanded(
              child:
                  Text(label, style: Theme.of(context).textTheme.titleMedium),
            ),
            Text(
              '${value.toInt()}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          label: value.toInt().toString(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}
