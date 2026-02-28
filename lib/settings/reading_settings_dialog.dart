import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/bloc/settings_bloc.dart';
import 'package:otzaria/settings/bloc/settings_state.dart';
import 'package:otzaria/settings/tabs/reading_settings_tab.dart';

/// פונקציה גלובלית להצגת דיאלוג הגדרות תצוגת הספרים
/// ניתן לקרוא לה מכל מקום באפליקציה (למשל ממסך העיון)
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
            height: MediaQuery.of(context).size.height * 0.7,
            child: const ReadingSettingsTab(isDialog: true),
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
