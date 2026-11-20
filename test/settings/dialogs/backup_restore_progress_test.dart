// שחזור מגיבוי רץ מאחורי דיאלוג התקדמות חוסם, ולא משאיר חלון "קפוא".
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/dialogs/backup_restore_flow.dart';
import 'package:otzaria/settings/services/backup/backup_import_merge.dart';
import 'package:otzaria/settings/services/backup_service.dart';

const BackupRestoreResult _result = (
  skippedSections: <String>[],
  missingCustomFolders: <String>[],
  hasLegacyPartialSettings: false,
  notesWithoutAnchor: 0,
  restoredPlugins: 0,
  userBooksNotReplaced: false,
  added: null,
);

void main() {
  tearDown(() => BackupRestoreFlow.debugRestoreFromBackup = null);

  Future<void> pumpOpener(
    WidgetTester tester,
    void Function(Future<BackupRestoreResult> result) onStarted, {
    BackupImportMode mode = BackupImportMode.replace,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => onStarted(
              BackupRestoreFlow.restoreWithProgress(
                context,
                'backup.json',
                mode: mode,
              ),
            ),
            child: const Text('שחזר'),
          ),
        ),
      ),
    );
  }

  testWidgets('בזמן השחזור מוצג דיאלוג התקדמות חוסם, ואחריו הוא נסגר', (
    tester,
  ) async {
    final restore = Completer<BackupRestoreResult>();
    BackupImportMode? seenMode;
    BackupRestoreFlow.debugRestoreFromBackup = (path, mode) {
      seenMode = mode;
      return restore.future;
    };
    Future<BackupRestoreResult>? started;
    await pumpOpener(
      tester,
      (result) => started = result,
      mode: BackupImportMode.merge,
    );

    await tester.tap(find.text('שחזר'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('שחזור הנתונים'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(seenMode, BackupImportMode.merge);
    // חוסם: לחיצה על המחסום לא סוגרת.
    await tester.tapAt(const Offset(5, 5));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('שחזור הנתונים'), findsOneWidget);

    restore.complete(_result);
    await tester.pumpAndSettle();

    expect(find.text('שחזור הנתונים'), findsNothing);
    expect(await started, _result);
  });

  testWidgets('שגיאת שחזור סוגרת את הדיאלוג ועוברת לקורא', (tester) async {
    BackupRestoreFlow.debugRestoreFromBackup = (path, mode) =>
        Future.error(Exception('נכשל'));
    Object? error;
    await pumpOpener(
      tester,
      (result) => unawaited(
        result.catchError((Object e) {
          error = e;
          return _result;
        }),
      ),
    );

    await tester.tap(find.text('שחזר'));
    await tester.pumpAndSettle();

    expect(error, isA<Exception>());
    expect(find.text('שחזור הנתונים'), findsNothing);
  });
}
