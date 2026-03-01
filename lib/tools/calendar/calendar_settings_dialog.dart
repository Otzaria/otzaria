import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/tools/calendar/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/calendar_settings_tab.dart';

/// פונקציה גלובלית להצגת דיאלוג הגדרות לוח שנה
/// ניתן לקרוא לה מכל מקום באפליקציה
void showCalendarSettingsDialog(
  BuildContext context, {
  required CalendarCubit calendarCubit,
}) {
  showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text(
        'הגדרות לוח שנה',
        style: TextStyle(fontWeight: FontWeight.bold),
        textAlign: TextAlign.center,
      ),
      content: SizedBox(
        width: 650,
        height: MediaQuery.of(dialogContext).size.height * 0.7,
        child: BlocProvider.value(
          value: calendarCubit,
          child: const CalendarSettingsTab(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('סגור'),
        ),
      ],
    ),
  );
}
