import 'package:flutter/material.dart';
import 'package:otzaria/library/view/library_panel_controller.dart';
import 'package:otzaria/settings/panels/library_settings_panel.dart';

/// פותחת את פאנל הגדרות הספרייה כאשר המסך תומך בכך.
///
/// אם הספרייה אינה נטענת כרגע, נשמרת האפשרות ליפול חזרה לדיאלוג הישן.
void showLibrarySettingsDialog(BuildContext context) {
  final opened = LibraryPanelController.openSettingsPanel();
  if (opened) {
    return;
  }

  showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: Theme.of(dialogContext).colorScheme.surfaceContainerHigh,
      title: const Text(
        'הגדרות ספרייה',
        style: TextStyle(fontWeight: FontWeight.bold),
        textAlign: TextAlign.center,
      ),
      content: SizedBox(
        width: 650,
        height: MediaQuery.of(dialogContext).size.height * 0.7,
        child: const SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 8.0),
            child: LibrarySettingsPanel(),
          ),
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
