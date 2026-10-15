import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/pending_reboot_delete_warning.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';

import '../test_helpers/memory_cache_provider.dart';

const _dataRoot = r'C:\Users\u\AppData\Roaming\otzaria';
const _databases = r'D:\ספרייה\databases';
const _backups = r'C:\Users\u\Documents\אוצריא - גיבויים';
const _roots = [_dataRoot, _databases, _backups];

/// הפריסה של REG_MULTI_SZ: כל מחרוזת מסתיימת ב-NUL, ועוד NUL בסוף הרשימה.
String _multiSz(List<String> entries) => '${entries.join('\x00')}\x00\x00';

void main() {
  group('scheduledRemovals (issue #2611)', () {
    List<String> removals(List<String> operations) =>
        PendingRebootDeleteWarning.scheduledRemovals(
          _multiSz(operations),
          _roots,
        );

    test('מחיקה (יעד ריק) בתוך התיקיות נספרת, עם הקידומות של Windows', () {
      expect(
        removals([
          r'\??\C:\Users\u\AppData\Roaming\otzaria\app_preferences.hive',
          '',
          r'*1\??\D:\ספרייה\databases\personal_notes.db',
          '',
        ]),
        [
          r'C:\Users\u\AppData\Roaming\otzaria\app_preferences.hive',
          r'D:\ספרייה\databases\personal_notes.db',
        ],
      );
    });

    test('ההשוואה אינה תלויה ברישיות ובסוג המפריד', () {
      expect(
        removals([r'\??\c:/USERS/u/appdata/roaming/OTZARIA/plugins/x.zip', '']),
        hasLength(1),
      );
    });

    test('העברה אל מחוץ לתיקיות נספרת, העברה בתוכן אינה נספרת', () {
      expect(
        removals([
          r'\??\C:\Users\u\Documents\אוצריא - גיבויים\a.json',
          r'!\??\C:\Temp\a.json',
          r'\??\D:\ספרייה\databases\new.db',
          r'!\??\D:\ספרייה\databases\user_books.db',
          r'*1\??\C:\Windows\Temp\DELC478.tmp',
          '',
        ]),
        [r'C:\Users\u\Documents\אוצריא - גיבויים\a.json'],
      );
    });

    test('נתיבים מחוץ לתיקיות, גם תיקייה אחות עם אותה קידומת, אינם נספרים', () {
      expect(
        removals([
          r'*1\??\C:\Program Files (x86)\Microsoft\EdgeUpdate\1.3.275.13',
          '',
          r'\??\C:\Users\u\AppData\Roaming\otzaria2\x.db',
          '',
        ]),
        isEmpty,
      );
      expect(removals(const []), isEmpty);
    });
  });

  group('PendingRebootDeleteWarning.showIfNeeded (issue #2611)', () {
    setUpAll(() async {
      await Settings.init(cacheProvider: MemoryCacheProvider());
      await Settings.setValue<String>(
        SettingsRepository.keyDatabasesPath,
        _databases,
      );
      await Settings.setValue<String>(
        SettingsRepository.keyBackupPath,
        _backups,
      );
      AppPaths.debugOverrideDataRootPath(_dataRoot);
    });
    tearDownAll(() => AppPaths.debugOverrideDataRootPath(null));
    setUp(PendingRebootDeleteWarning.debugReset);

    Future<void> showWith(WidgetTester tester, List<String> operations) async {
      PendingRebootDeleteWarning.readOperations = () async =>
          _multiSz(operations);
      await tester.pumpWidget(
        MaterialApp(navigatorKey: navigatorKey, home: const SizedBox()),
      );
      unawaited(PendingRebootDeleteWarning.showIfNeeded());
      await tester.pumpAndSettle();
    }

    testWidgets('מחיקה מתוזמנת של מסד אישי וגיבוי מציגה אזהרה פעם אחת', (
      tester,
    ) async {
      await showWith(tester, [
        r'\??\D:\ספרייה\databases\personal_notes.db',
        '',
        r'\??\C:\Users\u\Documents\אוצריא - גיבויים\otzaria_backup.json',
        '',
      ]);

      expect(
        find.text('Windows ימחק את נתוני אוצריא בהפעלה הבאה של המחשב'),
        findsOneWidget,
      );
      expect(find.textContaining(_databases), findsOneWidget);
      expect(find.textContaining('גם תיקיית הגיבויים'), findsOneWidget);
      expect(find.text('גבה עכשיו'), findsOneWidget);

      await tester.tap(find.text('סגור'));
      await tester.pumpAndSettle();
      unawaited(PendingRebootDeleteWarning.showIfNeeded());
      await tester.pumpAndSettle();
      expect(find.text('גבה עכשיו'), findsNothing);
    });

    testWidgets('מחיקות מחוץ לנתוני אוצריא אינן מציגות אזהרה', (tester) async {
      await showWith(tester, [r'*1\??\C:\Windows\Temp\DELC478.tmp', '']);

      expect(find.text('גבה עכשיו'), findsNothing);
    });
  });
}
