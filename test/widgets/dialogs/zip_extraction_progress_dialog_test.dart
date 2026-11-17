import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_frame.dart';
import 'package:otzaria/widgets/dialogs/zip_extraction_progress_dialog.dart';
import 'package:otzaria/widgets/feedback/loading_indicator.dart';

/// DD-07: דיאלוג ההתקדמות של חילוץ ZIP על המסגרת המשותפת, ואי אפשר לסגור
/// אותו ב-Escape בזמן הבדיקה.
void main() {
  testWidgets('הבדיקה מוצגת ב-AppDialogFrame עם ספינר והודעה', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => ZipExtractionProgressDialog.showAndExtract(
              context: context,
              path: Directory.systemTemp.path,
              onSuccess: (_) {},
              onError: (_) {},
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(AppDialogFrame), findsOneWidget);
    expect(find.text('מעבד תיקייה'), findsOneWidget);
    expect(find.byType(LoadingIndicator), findsOneWidget);
    expect(find.text('בודק תיקייה...'), findsOneWidget);
  });
}
