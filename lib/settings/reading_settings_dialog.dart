import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/settings/settings_bloc.dart';
import 'package:otzaria/settings/settings_event.dart';
import 'package:otzaria/settings/settings_state.dart';

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

                  // גודל גופן והגופן בשורה אחת
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // גודל גופן - 3/4
                        Expanded(
                          flex: 3,
                          child: StatefulBuilder(
                            builder: (context, setState) {
                              double currentFontSize =
                                  settingsState.fontSize.clamp(15, 60);
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.format_size),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          'גודל גופן התחלתי',
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
                        const SizedBox(width: 24),
                        // גופן - 1/4
                        Expanded(
                          flex: 1,
                          child: StatefulBuilder(
                            builder: (context, setState) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.font_download_outlined),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'גופן',
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
                                    items: const [
                                      DropdownMenuItem(
                                          value: 'TaameyDavidCLM',
                                          child: Text('דוד')),
                                      DropdownMenuItem(
                                          value: 'FrankRuhlCLM',
                                          child: Text('פרנק-רוהל')),
                                      DropdownMenuItem(
                                          value: 'TaameyAshkenaz',
                                          child: Text('טעמי אשכנז')),
                                      DropdownMenuItem(
                                          value: 'KeterYG', child: Text('כתר')),
                                      DropdownMenuItem(
                                          value: 'Shofar', child: Text('שופר')),
                                      DropdownMenuItem(
                                          value: 'NotoSerifHebrew',
                                          child: Text('נוטו')),
                                      DropdownMenuItem(
                                          value: 'Tinos', child: Text('טינוס')),
                                      DropdownMenuItem(
                                          value: 'NotoRashiHebrew',
                                          child: Text('רש"י')),
                                      DropdownMenuItem(
                                          value: 'Candara',
                                          child: Text('קנדרה')),
                                      DropdownMenuItem(
                                          value: 'roboto',
                                          child: Text('רובוטו')),
                                      DropdownMenuItem(
                                          value: 'Calibri',
                                          child: Text('קליברי')),
                                      DropdownMenuItem(
                                          value: 'Arial', child: Text('אריאל')),
                                    ],
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
                  const Divider(),

                  // רוחב השוליים בצידי הטקסט
                  StatefulBuilder(
                    builder: (context, setState) {
                      double currentPadding = settingsState.paddingSize;
                      return Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.horizontal_distribute),
                            title: const Text('רוחב השוליים בצידי הטקסט'),
                            trailing: Text(
                              currentPadding.toStringAsFixed(0),
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
                              value: currentPadding,
                              min: 0,
                              max: 500,
                              divisions: 250,
                              label: currentPadding.toStringAsFixed(0),
                              onChanged: (value) {
                                setState(() {});
                                context
                                    .read<SettingsBloc>()
                                    .add(UpdatePaddingSize(value));
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
                                      const Icon(Icons.content_copy),
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
                                      const Icon(Icons.format_align_right),
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
                                    initialValue: settingsState.copyHeaderFormat,
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
                                    const Icon(Icons.timer_outlined),
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
                                    const Icon(Icons.delete_sweep_outlined),
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
                                    const Icon(Icons.storage_outlined),
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
