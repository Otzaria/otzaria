import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/constants/fonts.dart';
import 'package:otzaria/settings/settings_bloc.dart';
import 'package:otzaria/settings/settings_event.dart';
import 'package:otzaria/settings/settings_state.dart';
import 'package:otzaria/settings/per_book_settings.dart';
import 'package:otzaria/core/scaffold_messenger.dart';

/// פונקציה גלובלית להצגת דיאלוג הגדרות תצוגת הספרים
/// ניתן לקרוא לה מכל מקום באפליקציה
void showReadingSettingsDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (context) => BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, settingsState) {
        return AlertDialog(
          title: const Text(
            'הגדרות תצוגת הספרים',
            style: TextStyle(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          content: SizedBox(
            width: 650,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // כותרת: הגדרות גופן ועיצוב
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        vertical: 10.0, horizontal: 16.0),
                    decoration: BoxDecoration(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                    child: const Text(
                      'הגדרות גופן ועיצוב',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      textAlign: TextAlign.start,
                    ),
                  ),

                  // שורה ראשונה: גודל גופן הספר וגופן טקסט
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // גודל גופן הספר - 1/2
                        Expanded(
                          flex: 1,
                          child: StatefulBuilder(
                            builder: (context, setState) {
                              double currentFontSize =
                                  settingsState.fontSize.clamp(15, 60);
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(FluentIcons
                                          .text_font_size_24_regular),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          'גודל גופן הספר',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium,
                                        ),
                                      ),
                                      Text(
                                        currentFontSize.toStringAsFixed(0),
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Slider(
                                    value: currentFontSize,
                                    min: 15,
                                    max: 60,
                                    divisions: 45,
                                    label: currentFontSize.toStringAsFixed(0),
                                    onChanged: (value) {
                                      setState(() {});
                                      context
                                          .read<SettingsBloc>()
                                          .add(UpdateFontSize(value));
                                    },
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        // גופן טקסט ראשי - 1/2
                        Expanded(
                          flex: 1,
                          child: StatefulBuilder(
                            builder: (context, setState) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(
                                          FluentIcons.text_font_24_regular),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'גופן טקסט',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  DropdownButtonFormField<String>(
                                    initialValue: settingsState.fontFamily,
                                    decoration: InputDecoration(
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    dropdownColor:
                                        Theme.of(context).colorScheme.surface,
                                    isExpanded: true,
                                    items: AppFonts.buildDropdownItems(),
                                    onChanged: (value) {
                                      if (value != null) {
                                        context
                                            .read<SettingsBloc>()
                                            .add(UpdateFontFamily(value));
                                        setState(() {});
                                      }
                                    },
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                  // שורה שנייה: גודל גופן מפרשים וגופן מפרשים
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 16.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // גודל גופן מפרשים - 1/2
                        Expanded(
                          flex: 1,
                          child: StatefulBuilder(
                            builder: (context, setState) {
                              double currentCommentatorsFontSize = settingsState
                                  .commentatorsFontSize
                                  .clamp(10, 40);
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(FluentIcons
                                          .text_font_size_24_regular),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          'גודל גופן מפרשים וקישורים',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium,
                                        ),
                                      ),
                                      Text(
                                        currentCommentatorsFontSize
                                            .toStringAsFixed(0),
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Slider(
                                    value: currentCommentatorsFontSize,
                                    min: 10,
                                    max: 40,
                                    divisions: 30,
                                    label: currentCommentatorsFontSize
                                        .toStringAsFixed(0),
                                    onChanged: (value) {
                                      setState(() {});
                                      context.read<SettingsBloc>().add(
                                          UpdateCommentatorsFontSize(value));
                                    },
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        // גופן מפרשים - 1/2
                        Expanded(
                          flex: 1,
                          child: StatefulBuilder(
                            builder: (context, setState) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(FluentIcons.book_24_regular),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'גופן מפרשים',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  DropdownButtonFormField<String>(
                                    initialValue:
                                        settingsState.commentatorsFontFamily,
                                    decoration: InputDecoration(
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    dropdownColor:
                                        Theme.of(context).colorScheme.surface,
                                    isExpanded: true,
                                    items: AppFonts.buildDropdownItems(),
                                    onChanged: (value) {
                                      if (value != null) {
                                        context.read<SettingsBloc>().add(
                                            UpdateCommentatorsFontFamily(
                                                value));
                                        setState(() {});
                                      }
                                    },
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(),

                  // רוחב הטקסט
                  StatefulBuilder(
                    builder: (context, setState) {
                      // רוחב המסך לחישוב פיקסלים
                      final screenWidth = MediaQuery.of(context).size.width;
                      final currentMaxWidth = settingsState.textMaxWidth;

                      // חישוב הרמה הנוכחית מהרוחב השמור
                      // ערך שלילי = רמה דינמית (ברירת מחדל)
                      // 0 = רוחב מלא
                      // ערך חיובי = פיקסלים קבועים
                      int currentLevel;
                      if (currentMaxWidth < 0) {
                        // ערך שלילי = רמה דינמית
                        currentLevel = (-currentMaxWidth).toInt();
                      } else if (currentMaxWidth == 0) {
                        currentLevel = 0;
                      } else {
                        // ערך חיובי = פיקסלים, נחשב את הרמה המקבילה
                        final ratio = currentMaxWidth / screenWidth;
                        currentLevel =
                            ((1.0 - ratio) / 0.05).round().clamp(0, 14);
                      }

                      // תיאור לפי אחוז הרוחב
                      String getLevelDescription(int level) {
                        if (level == 0) return 'מלא';
                        final percent = 100 - (level * 5);
                        return '$percent%';
                      }

                      return Column(
                        children: [
                          ListTile(
                            leading: const Icon(
                                FluentIcons.text_align_justify_24_regular),
                            title: const Text('רוחב הטקסט'),
                            subtitle: Text(
                              currentLevel == 0
                                  ? 'הטקסט ימלא את כל הרוחב הזמין'
                                  : 'הטקסט יהיה צר יותר ומרוכז במסך',
                              style: Theme.of(context).textTheme.bodySmall,
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
                            padding:
                                const EdgeInsets.symmetric(horizontal: 16.0),
                            child: Slider(
                              value: currentLevel.toDouble(),
                              min: 0,
                              max: 14,
                              divisions: 14,
                              label: getLevelDescription(currentLevel),
                              onChanged: (value) {
                                setState(() {});
                                // שומרים פיקסלים קבועים (לא רמה דינמית)
                                final level = value.toInt();
                                double newMaxWidth;
                                if (level == 0) {
                                  newMaxWidth = 0; // רוחב מלא
                                } else {
                                  // מחשבים פיקסלים לפי רוחב המסך הנוכחי
                                  final widthPercent = 1.0 - (level * 0.05);
                                  newMaxWidth = screenWidth * widthPercent;
                                }
                                context
                                    .read<SettingsBloc>()
                                    .add(UpdateTextMaxWidth(newMaxWidth));
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),

                  // כותרת: הסרת ניקוד וטעמים
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        vertical: 10.0, horizontal: 16.0),
                    decoration: BoxDecoration(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                    child: const Text(
                      'הסרת ניקוד וטעמים',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      textAlign: TextAlign.start,
                    ),
                  ),

                  // הצגת טעמי המקרא
                  SwitchListTile(
                    title: const Text('הצגת טעמי המקרא'),
                    subtitle: Text(settingsState.showTeamim
                        ? 'המקרא יוצג עם טעמים'
                        : 'המקרא יוצג ללא טעמים'),
                    value: settingsState.showTeamim,
                    onChanged: (value) {
                      context.read<SettingsBloc>().add(UpdateShowTeamim(value));
                    },
                  ),
                  const Divider(),

                  // הסרת ניקוד כברירת מחדל
                  SwitchListTile(
                    title: const Text('הסרת ניקוד כברירת מחדל'),
                    subtitle: Text(settingsState.defaultRemoveNikud
                        ? 'הניקוד יוסר כברירת מחדל'
                        : 'הניקוד יוצג כברירת מחדל'),
                    value: settingsState.defaultRemoveNikud,
                    onChanged: (value) {
                      context
                          .read<SettingsBloc>()
                          .add(UpdateDefaultRemoveNikud(value));
                    },
                  ),
                  if (settingsState.defaultRemoveNikud)
                    Padding(
                      padding: const EdgeInsets.only(right: 32.0),
                      child: CheckboxListTile(
                        title: const Text('הסרת ניקוד מספרי התנ"ך'),
                        subtitle: const Text('גם ספרי התנ"ך יוצגו ללא ניקוד'),
                        value: settingsState.removeNikudFromTanach,
                        onChanged: (bool? value) {
                          if (value != null) {
                            context.read<SettingsBloc>().add(
                                  UpdateRemoveNikudFromTanach(value),
                                );
                          }
                        },
                      ),
                    ),

                  // כותרת: הגדרות טאבים
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        vertical: 10.0, horizontal: 16.0),
                    decoration: BoxDecoration(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                    child: const Text(
                      'הגדרות טאבים',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      textAlign: TextAlign.start,
                    ),
                  ),

                  // יישור טאבים לימין
                  SwitchListTile(
                    title: const Text('יישור טאבים לימין'),
                    subtitle: Text(settingsState.alignTabsToRight
                        ? 'הטאבים יוצגו בצד ימין'
                        : 'הטאבים יוצגו במרכז'),
                    value: settingsState.alignTabsToRight,
                    onChanged: (value) {
                      context
                          .read<SettingsBloc>()
                          .add(UpdateAlignTabsToRight(value));
                    },
                  ),

                  // כותרת: התנהגות סרגל צד
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        vertical: 10.0, horizontal: 16.0),
                    decoration: BoxDecoration(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                    child: const Text(
                      'התנהגות סרגל צד',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      textAlign: TextAlign.start,
                    ),
                  ),

                  // הצמדת סרגל צד
                  SwitchListTile(
                    title: const Text('הצמדת סרגל צד'),
                    subtitle: Text(settingsState.pinSidebar
                        ? 'סרגל הצד יוצמד תמיד'
                        : 'סרגל הצד יפעל כרגיל'),
                    value: settingsState.pinSidebar,
                    onChanged: (value) {
                      context.read<SettingsBloc>().add(UpdatePinSidebar(value));
                      if (value) {
                        context
                            .read<SettingsBloc>()
                            .add(const UpdateDefaultSidebarOpen(true));
                      }
                    },
                  ),
                  const Divider(),

                  // פתיחת סרגל צד
                  SwitchListTile(
                    title: const Text('פתיחת סרגל צד כברירת מחדל'),
                    subtitle: Text(settingsState.defaultSidebarOpen
                        ? 'סרגל הצד יפתח אוטומטית'
                        : 'סרגל הצד ישאר סגור'),
                    value: settingsState.defaultSidebarOpen,
                    onChanged: settingsState.pinSidebar
                        ? null
                        : (value) {
                            context
                                .read<SettingsBloc>()
                                .add(UpdateDefaultSidebarOpen(value));
                          },
                  ),
                  const Divider(),

                  // ברירת מחדל להצגת מפרשים
                  StatefulBuilder(
                    builder: (context, setState) {
                      final splitedView =
                          Settings.getValue<bool>('key-splited-view') ?? false;
                      return SwitchListTile(
                        title: const Text('ברירת המחדל להצגת המפרשים'),
                        subtitle: Text(splitedView
                            ? 'המפרשים יוצגו לצד הטקסט'
                            : 'המפרשים יוצגו מתחת הטקסט'),
                        value: splitedView,
                        onChanged: (value) {
                          setState(() {
                            Settings.setValue<bool>('key-splited-view', value);
                            // ניקוי קבצי per_book_settings מיותרים
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

                  // הגדרות העתקה
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        vertical: 10.0, horizontal: 16.0),
                    decoration: BoxDecoration(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                    child: const Text(
                      'הגדרות העתקה',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      textAlign: TextAlign.start,
                    ),
                  ),

                  // העתקה עם כותרות ועיצוב בשורה אחת
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: StatefulBuilder(
                      builder: (context, setState) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // העתקה עם כותרות - 1/2
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(FluentIcons.copy_24_regular),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'העתקה עם כותרות',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  DropdownButtonFormField<String>(
                                    initialValue: settingsState.copyWithHeaders,
                                    decoration: InputDecoration(
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    dropdownColor:
                                        Theme.of(context).colorScheme.surface,
                                    isExpanded: true,
                                    items: const [
                                      DropdownMenuItem(
                                          value: 'none', child: Text('ללא')),
                                      DropdownMenuItem(
                                          value: 'book_name',
                                          child: Text('שם הספר בלבד')),
                                      DropdownMenuItem(
                                          value: 'book_and_path',
                                          child: Text('שם הספר+נתיב')),
                                    ],
                                    onChanged: (value) {
                                      if (value != null) {
                                        context
                                            .read<SettingsBloc>()
                                            .add(UpdateCopyWithHeaders(value));
                                        setState(() {});
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 24),
                            // עיצוב העתקה - 1/2
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(FluentIcons
                                          .text_align_right_24_regular),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'עיצוב העתקה',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  DropdownButtonFormField<String>(
                                    initialValue:
                                        settingsState.copyHeaderFormat,
                                    decoration: InputDecoration(
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    dropdownColor:
                                        Theme.of(context).colorScheme.surface,
                                    isExpanded: true,
                                    items: const [
                                      DropdownMenuItem(
                                          value: 'same_line_after_brackets',
                                          child: Text(
                                              'אותה שורה אחרי (עם סוגריים)')),
                                      DropdownMenuItem(
                                          value: 'same_line_after_no_brackets',
                                          child: Text(
                                              'אותה שורה אחרי (בלי סוגריים)')),
                                      DropdownMenuItem(
                                          value: 'same_line_before_brackets',
                                          child: Text(
                                              'אותה שורה לפני (עם סוגריים)')),
                                      DropdownMenuItem(
                                          value: 'same_line_before_no_brackets',
                                          child: Text(
                                              'אותה שורה לפני (בלי סוגריים)')),
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
                                        setState(() {});
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),

                  // הגדרות פר-ספר
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        vertical: 10.0, horizontal: 16.0),
                    decoration: BoxDecoration(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                    child: const Text(
                      'הגדרות פר-ספר',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      textAlign: TextAlign.start,
                    ),
                  ),

                  // הפעלת שמירת התאמות פר-ספר
                  SwitchListTile(
                    title: const Text('שמירת התאמות פר-ספר'),
                    subtitle: Text(settingsState.enablePerBookSettings
                        ? 'שינויים בסרגל הלחצנים יישמרו לכל ספר בנפרד'
                        : 'כל הספרים ישתמשו בהגדרות הכלליות'),
                    value: settingsState.enablePerBookSettings,
                    onChanged: (value) {
                      context
                          .read<SettingsBloc>()
                          .add(UpdateEnablePerBookSettings(value));
                    },
                  ),

                  // כפתור איפוס כל ההגדרות הפר-ספריות
                  if (settingsState.enablePerBookSettings)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16.0, vertical: 8.0),
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('אישור מחיקה'),
                              content: const Text(
                                  'האם אתה בטוח שברצונך למחוק את כל ההגדרות הפר-ספריות?\nפעולה זו אינה ניתנת לביטול.'),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(false),
                                  child: const Text('ביטול'),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(true),
                                  child: const Text('מחק הכל'),
                                ),
                              ],
                            ),
                          );

                          if (confirm == true && context.mounted) {
                            await PerBookSettings.deleteAllSettings();
                            if (context.mounted) {
                              UiSnack.show(
                                  'כל ההגדרות הפר-ספריות נמחקו בהצלחה');
                            }
                          }
                        },
                        icon: const Icon(FluentIcons.delete_24_regular),
                        label: const Text('אפס את כל הגדרות אלו, בכל הספרים'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              Theme.of(context).colorScheme.errorContainer,
                          foregroundColor:
                              Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),

                  const Divider(),

                  // הגדרות עורך טקסטים
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        vertical: 10.0, horizontal: 16.0),
                    decoration: BoxDecoration(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                    child: const Text(
                      'הגדרות עורך טקסטים',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      textAlign: TextAlign.start,
                    ),
                  ),

                  StatefulBuilder(
                    builder: (context, setState) {
                      double previewDebounce = Settings.getValue<double>(
                              'key-editor-preview-debounce') ??
                          150.0;
                      double cleanupDays = Settings.getValue<double>(
                              'key-editor-draft-cleanup-days') ??
                          30.0;
                      double draftsQuota = Settings.getValue<double>(
                              'key-editor-drafts-quota') ??
                          100.0;

                      return Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // עיכוב תצוגה מקדימה
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(FluentIcons.timer_24_regular),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'זמן עיכוב במילישניות',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium,
                                      ),
                                    ),
                                    Text(
                                      '${previewDebounce.toInt()}',
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                Slider(
                                  value: previewDebounce,
                                  min: 50,
                                  max: 300,
                                  divisions: 5,
                                  label: previewDebounce.toInt().toString(),
                                  onChanged: (value) {
                                    setState(() => previewDebounce = value);
                                    Settings.setValue<double>(
                                        'key-editor-preview-debounce', value);
                                  },
                                ),
                              ],
                            ),
                            const Divider(),

                            // ניקוי טיוטות ישנות
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                        FluentIcons.delete_dismiss_24_regular),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'ניקוי טיוטות ישנות (ימים)',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium,
                                      ),
                                    ),
                                    Text(
                                      '${cleanupDays.toInt()}',
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                Slider(
                                  value: cleanupDays,
                                  min: 7,
                                  max: 90,
                                  divisions: 12,
                                  label: cleanupDays.toInt().toString(),
                                  onChanged: (value) {
                                    setState(() => cleanupDays = value);
                                    Settings.setValue<double>(
                                        'key-editor-draft-cleanup-days', value);
                                  },
                                ),
                              ],
                            ),
                            const Divider(),

                            // מכסת טיוטות
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(FluentIcons.database_24_regular),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'מכסת טיוטות (MB)',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium,
                                      ),
                                    ),
                                    Text(
                                      '${draftsQuota.toInt()}',
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                Slider(
                                  value: draftsQuota,
                                  min: 50,
                                  max: 100,
                                  divisions: 5,
                                  label: draftsQuota.toInt().toString(),
                                  onChanged: (value) {
                                    setState(() => draftsQuota = value);
                                    Settings.setValue<double>(
                                        'key-editor-drafts-quota', value);
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('סגור'),
            ),
          ],
        );
      },
    ),
  );
}
