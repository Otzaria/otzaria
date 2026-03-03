import 'package:flutter/material.dart';
import 'package:otzaria/settings/panels/library_settings_panel.dart';

/// פונקציה גלובלית להצגת דיאלוג הגדרות ספרייה
/// ניתן לקרוא לה מכל מקום באפליקציה
void showLibrarySettingsDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text(
        'הגדרות ספרייה',
        style: TextStyle(fontWeight: FontWeight.bold),
        textAlign: TextAlign.center,
      ),
      content: SizedBox(
        width: 650,
        height: MediaQuery.of(dialogContext).size.height * 0.7,
        // עטפנו ב-SingleChildScrollView כדי שיהיה ניתן לגלול אם המסך קטן
        child: const SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 8.0),
            child: LibraryBasicSettingsPanel(),
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
