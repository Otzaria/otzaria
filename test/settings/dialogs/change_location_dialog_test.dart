import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/migration/models/book.dart' as migration_models;
import 'package:otzaria/migration/models/category.dart' as migration_models;
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/dialogs/change_location_dialog.dart';
import 'package:path/path.dart' as p;

Widget _openButton(void Function(BuildContext) onOpen) => MaterialApp(
  home: Scaffold(
    body: Builder(
      builder: (ctx) => TextButton(
        onPressed: () => onOpen(ctx),
        child: const Text('פתח'),
      ),
    ),
  ),
);

Future<void> _openDialog(
  WidgetTester tester, {
  String currentPath = '/some/path',
  String folderName = 'ספרייה',
  bool canMoveContents = true,
  String? defaultPath,
  String? moveContentsWarning,
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    _openButton(
      (ctx) => showChangeLocationDialog(
        context: ctx,
        currentPath: currentPath,
        folderName: folderName,
        canMoveContents: canMoveContents,
        defaultPath: defaultPath,
        moveContentsWarning: moveContentsWarning,
      ),
    ),
  );
  await tester.tap(find.text('פתח'));
  await tester.pumpAndSettle();
}

void main() {
  group('ChangeLocationResult', () {
    test('שומר newPath ו-moveContents=true', () {
      const r = ChangeLocationResult('/new/path', moveContents: true);
      expect(r.newPath, '/new/path');
      expect(r.moveContents, isTrue);
    });

    test('שומר newPath ו-moveContents=false', () {
      const r = ChangeLocationResult('/p', moveContents: false);
      expect(r.moveContents, isFalse);
    });
  });

  group('showChangeLocationDialog — מבנה', () {
    testWidgets('מציג כותרת עם שם התיקייה', (tester) async {
      await _openDialog(tester, folderName: 'ספריית אוצריא');
      expect(find.text('שינוי מיקום ספריית אוצריא'), findsOneWidget);
    });

    testWidgets('canMoveContents=true — שתי האפשרויות מוצגות', (tester) async {
      await _openDialog(tester, canMoveContents: true);
      expect(find.text('העבר תוכן תיקייה'), findsOneWidget);
      expect(find.text('שנה מיקום בלבד'), findsOneWidget);
    });

    testWidgets('currentPath ריק — רק "הגדרת מיקום" מוצג', (tester) async {
      await _openDialog(tester, currentPath: '', canMoveContents: false);
      expect(find.text('העבר תוכן תיקייה'), findsNothing);
      expect(find.text('שנה מיקום בלבד'), findsNothing);
      expect(find.text('הגדרת מיקום'), findsOneWidget);
    });

    // הבחירה נבדקת דרך אזהרת ההעברה (מוצגת רק כש"העבר תוכן" נבחר) — ברדיו
    // המותאם אין ערך פנימי לבדיקה, לכן בודקים את ההתנהגות הנצפית.
    testWidgets('canMoveContents=true — "העבר תוכן" נבחר כברירת מחדל', (
      tester,
    ) async {
      await _openDialog(
        tester,
        canMoveContents: true,
        moveContentsWarning: 'אזהרת בדיקה',
      );
      expect(find.text('אזהרת בדיקה'), findsOneWidget);
    });

    testWidgets('לחיצה על "שנה מיקום בלבד" מחליפה את הבחירה', (tester) async {
      await _openDialog(
        tester,
        canMoveContents: true,
        moveContentsWarning: 'אזהרת בדיקה',
      );

      await tester.tap(find.text('שנה מיקום בלבד'));
      await tester.pump();
      expect(find.text('אזהרת בדיקה'), findsNothing);
    });

    testWidgets('לחיצה חזרה על "העבר תוכן" משחזרת בחירה', (tester) async {
      await _openDialog(
        tester,
        canMoveContents: true,
        moveContentsWarning: 'אזהרת בדיקה',
      );
      await tester.tap(find.text('שנה מיקום בלבד'));
      await tester.pump();
      await tester.tap(find.text('העבר תוכן תיקייה'));
      await tester.pump();
      expect(find.text('אזהרת בדיקה'), findsOneWidget);
    });

    testWidgets('defaultPath קיים — כרטיס ברירת מחדל מוצג', (tester) async {
      await _openDialog(tester, defaultPath: '/default/path');
      expect(find.text('מיקום ברירת מחדל'), findsOneWidget);
    });

    testWidgets('defaultPath=null — כרטיס ברירת מחדל לא מוצג', (tester) async {
      await _openDialog(tester, defaultPath: null);
      expect(find.text('מיקום ברירת מחדל'), findsNothing);
    });

    testWidgets('כשcurrentPath==defaultPath כפתור "השתמש בברירת מחדל" מושבת', (
      tester,
    ) async {
      const path = '/default/path';
      await _openDialog(tester, currentPath: path, defaultPath: path);

      final btnFinder = find.ancestor(
        of: find.text('השתמש בברירת מחדל'),
        matching: find.byType(FilledButton),
      );
      expect(btnFinder, findsOneWidget);
      expect((tester.widget(btnFinder) as FilledButton).onPressed, isNull);
    });

    testWidgets('כשcurrentPath!=defaultPath כפתור "השתמש בברירת מחדל" פעיל', (
      tester,
    ) async {
      await _openDialog(
        tester,
        currentPath: '/other/path',
        defaultPath: '/default/path',
      );

      final btnFinder = find.ancestor(
        of: find.text('השתמש בברירת מחדל'),
        matching: find.byType(FilledButton),
      );
      expect((tester.widget(btnFinder) as FilledButton).onPressed, isNotNull);
    });

    testWidgets('לחיצת ביטול סוגרת את הדיאלוג', (tester) async {
      await _openDialog(tester, folderName: 'ספרייה');
      await tester.tap(find.text('ביטול'));
      await tester.pumpAndSettle();
      expect(find.text('שינוי מיקום ספרייה'), findsNothing);
    });

    testWidgets('אזהרת העברה מוצגת כש"העבר תוכן" נבחר', (tester) async {
      await _openDialog(tester, moveContentsWarning: 'התוכנה תיטען מחדש');
      expect(find.text('התוכנה תיטען מחדש'), findsOneWidget);
    });

    testWidgets('אזהרת העברה נעלמת כשעוברים ל"שנה מיקום בלבד"', (tester) async {
      await _openDialog(tester, moveContentsWarning: 'התוכנה תיטען מחדש');
      await tester.tap(find.text('שנה מיקום בלבד'));
      await tester.pump();
      expect(find.text('התוכנה תיטען מחדש'), findsNothing);
    });

    testWidgets('ללא moveContentsWarning — אין אזהרה', (tester) async {
      await _openDialog(tester);
      expect(find.byIcon(FluentIcons.info_24_regular), findsNothing);
    });
  });

  group('makeChangeLocationCallback — גזירת canMoveContents', () {
    Future<void> openCallback(
      WidgetTester tester,
      Future<void> Function(BuildContext) cb,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_openButton((ctx) => cb(ctx)));
      await tester.tap(find.text('פתח'));
      await tester.pumpAndSettle();
    }

    testWidgets('onAfterMove=null → אפשרות "העבר תוכן" לא מוצגת', (
      tester,
    ) async {
      final cb = makeChangeLocationCallback(
        currentPath: '/some/path',
        folderName: 'ספרייה',
        onPathChanged: (_) async {},
        onAfterMove: null,
      );
      await openCallback(tester, cb);
      expect(find.text('העבר תוכן תיקייה'), findsNothing);
    });

    testWidgets(
      'currentPath ריק → "העבר תוכן" לא מוצג גם כשonAfterMove מוגדר',
      (tester) async {
        final cb = makeChangeLocationCallback(
          currentPath: '',
          folderName: 'ספרייה',
          onPathChanged: (_) async {},
          onAfterMove: (_) async {},
        );
        await openCallback(tester, cb);
        expect(find.text('העבר תוכן תיקייה'), findsNothing);
      },
    );

    testWidgets('onAfterMove מוגדר + currentPath לא ריק → "העבר תוכן" מוצג', (
      tester,
    ) async {
      final cb = makeChangeLocationCallback(
        currentPath: '/some/path',
        folderName: 'ספרייה',
        onPathChanged: (_) async {},
        onAfterMove: (_) async {},
      );
      await openCallback(tester, cb);
      expect(find.text('העבר תוכן תיקייה'), findsOneWidget);
    });

    testWidgets('defaultPath מועבר לדיאלוג', (tester) async {
      final cb = makeChangeLocationCallback(
        currentPath: '/some/path',
        folderName: 'ספרייה',
        onPathChanged: (_) async {},
        defaultPath: '/default',
      );
      await openCallback(tester, cb);
      expect(find.text('מיקום ברירת מחדל'), findsOneWidget);
    });
  });

  group('remapMovedFileBookPaths', () {
    test('מדלג על PDF רשמי כי seforim.db לא מחזיק עמודות נתיב', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'otzaria-move-official-pdf-',
      );
      final from = p.join(tempDir.path, 'old', 'books');
      final to = p.join(tempDir.path, 'new', 'books');
      final oldPath = p.join(from, 'תלמוד בבלי', 'ברכות.pdf');

      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      await expectLater(
        remapMovedFileBookPaths(
          [
            PdfBook(
              id: 1,
              title: 'ברכות',
              path: oldPath,
            ),
          ],
          from,
          to,
        ),
        completes,
      );
    });

    test('מעדכן נתיב PDF אישי שהועבר יחד עם הספרייה', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'otzaria-move-user-pdf-',
      );
      final previousDataRoot = AppPaths.cachedDataRootPath;
      final dataRoot = p.join(tempDir.path, 'data-root');
      final from = p.join(tempDir.path, 'old', 'books');
      final to = p.join(tempDir.path, 'new', 'books');
      final oldPath = p.join(from, 'אישי', 'ספר.pdf');
      final newPath = p.join(to, 'אישי', 'ספר.pdf');

      addTearDown(() async {
        await UserBooksDatabaseHolder.instance.close();
        AppPaths.debugOverrideDataRootPath(previousDataRoot);
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      await Settings.init(cacheProvider: _MemoryCacheProvider());
      AppPaths.debugOverrideDataRootPath(dataRoot);
      await UserBooksDatabaseHolder.instance.close();

      await Directory(p.dirname(oldPath)).create(recursive: true);
      await Directory(p.dirname(newPath)).create(recursive: true);
      await File(oldPath).writeAsBytes([1, 2]);
      await File(newPath).writeAsBytes([1, 2, 3]);

      final repository = await UserBooksDatabaseHolder.instance.repository;
      final sourceId = await repository.insertSource('user-test', -20);
      final categoryId = await repository.insertCategory(
        const migration_models.Category(title: 'אישי'),
      );
      final bookId = await repository.insertBook(
        migration_models.Book(
          categoryId: categoryId,
          sourceId: sourceId,
          title: 'ספר',
          filePath: oldPath,
          fileType: 'pdf',
          isPersonal: true,
        ),
      );

      await remapMovedFileBookPaths(
        [
          PdfBook(
            id: bookId,
            title: 'ספר',
            path: oldPath,
            isUserBook: true,
          ),
        ],
        from,
        to,
      );

      expect(await repository.getExternalBookByFilePath(oldPath), isNull);

      final updated = await repository.getExternalBookByFilePath(newPath);
      expect(updated, isNotNull);
      expect(updated!.fileSize, 3);
    });
  });

  group('shouldCopyIndexDuringLibraryMove', () {
    test('מדלג על העתקת אינדקס בזמן אינדוקס פעיל', () {
      expect(
        shouldCopyIndexDuringLibraryMove(
          indexNeedsMove: true,
          indexingActive: true,
        ),
        isFalse,
      );
    });

    test('מעתיק אינדקס רק כשצריך ואין אינדוקס פעיל', () {
      expect(
        shouldCopyIndexDuringLibraryMove(
          indexNeedsMove: true,
          indexingActive: false,
        ),
        isTrue,
      );
      expect(
        shouldCopyIndexDuringLibraryMove(
          indexNeedsMove: false,
          indexingActive: false,
        ),
        isFalse,
      );
    });
  });

  group('library move rollback helpers', () {
    test('חוסם העברה כשיעד הספרייה כבר קיים', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'otzaria-move-target-',
      );
      final target = p.join(tempDir.path, 'books');

      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      await Directory(target).create(recursive: true);

      await expectLater(
        ensureLibraryMoveTargetAvailableForTesting(target),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('מנקה staging ויעדים שנוצרו אחרי כשל בהעברה', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'otzaria-move-cleanup-',
      );
      final stagingRoot = p.join(tempDir.path, '.otzaria_move_test');
      final newLibrary = p.join(tempDir.path, 'books');
      final newIndex = p.join(tempDir.path, 'index');
      final newDatabases = p.join(tempDir.path, 'databases');

      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      await Directory(stagingRoot).create(recursive: true);
      await Directory(newLibrary).create(recursive: true);
      await Directory(newIndex).create(recursive: true);
      await Directory(newDatabases).create(recursive: true);
      await File(p.join(stagingRoot, 'tmp')).writeAsString('tmp');
      await File(p.join(newLibrary, 'book')).writeAsString('book');
      await File(p.join(newIndex, 'idx')).writeAsString('idx');
      await File(p.join(newDatabases, 'user_books.db')).writeAsString('db');

      await cleanupCreatedMoveTargetsForTesting(
        stagingRoot: stagingRoot,
        newLibrary: newLibrary,
        newIndex: newIndex,
        newDatabases: newDatabases,
        finalLibraryCreated: true,
        finalIndexCreated: true,
        finalDatabasesCreated: true,
      );

      expect(await Directory(stagingRoot).exists(), isFalse);
      expect(await Directory(newLibrary).exists(), isFalse);
      expect(await Directory(newIndex).exists(), isFalse);
      expect(await Directory(newDatabases).exists(), isFalse);
    });
  });
}

class _MemoryCacheProvider extends CacheProvider {
  final Map<String, Object?> _values = {};

  @override
  Future<void> init() async {}

  @override
  bool containsKey(String key) => _values.containsKey(key);

  @override
  Set getKeys() => _values.keys.toSet();

  @override
  bool? getBool(String key, {bool? defaultValue}) =>
      _values[key] as bool? ?? defaultValue;

  @override
  double? getDouble(String key, {double? defaultValue}) =>
      _values[key] as double? ?? defaultValue;

  @override
  int? getInt(String key, {int? defaultValue}) =>
      _values[key] as int? ?? defaultValue;

  @override
  String? getString(String key, {String? defaultValue}) =>
      _values[key] as String? ?? defaultValue;

  @override
  T? getValue<T>(String key, {T? defaultValue}) {
    final value = _values[key];
    if (value is T) {
      return value;
    }
    return defaultValue;
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> removeAll() async {
    _values.clear();
  }

  @override
  Future<void> setBool(String key, bool? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setDouble(String key, double? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setInt(String key, int? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setObject<T>(String key, T? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setString(String key, String? value) async {
    _values[key] = value;
  }
}
