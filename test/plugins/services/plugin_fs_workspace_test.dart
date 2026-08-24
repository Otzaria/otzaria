import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_fs_service.dart';
import 'package:otzaria/plugins/services/plugin_path_safety.dart';
import 'package:path/path.dart' as p;

/// יוצר symlink, או מסמן דילוג כשהסביבה אינה מתירה זאת (Windows ללא הרשאה).
bool _tryLink(String link, String target) {
  try {
    Link(link).createSync(target);
    return true;
  } catch (_) {
    markTestSkipped('יצירת symlink אינה נתמכת בסביבה זו');
    return false;
  }
}

/// המרחב הפרטי של תוסף: אכיפת הגבול (`..`, מוחלט, UNC, symlink), המכסה
/// ותקרת ההעברה. הגבול הוא ההרשאה כאן — פעולות אלו אינן דורשות הרשאת manifest.
void main() {
  late Directory tempDir;
  late String root;
  late PluginFsService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('plugin_ws_test_');
    root = p.join(tempDir.path, 'plugins', 'data', 'my.plugin', 'files');
    service = PluginFsService(
      maxWorkspaceBytes: 1024,
      maxTransferBytes: 512,
    );
    await service.ensureWorkspace(root);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<int> write(String path, String content, {bool append = false}) =>
      service.writeWorkspaceFile(
        root: root,
        relativePath: path,
        bytes: utf8.encode(content),
        append: append,
      );

  group('resolveWithinRoot — גבול המרחב', () {
    test('נתיב יחסי רגיל נפתר בתוך השורש', () {
      final resolved = resolveWithinRoot(root, 'cache/a.json');
      expect(resolved, isNotNull);
      expect(
        p.isWithin(Directory(root).resolveSymbolicLinksSync(), resolved!),
        isTrue,
      );
    });

    test('ריק / נקודה מוחזרים כשורש עצמו', () {
      expect(
        resolveWithinRoot(root, ''),
        Directory(root).resolveSymbolicLinksSync(),
      );
      expect(
        resolveWithinRoot(root, '.'),
        Directory(root).resolveSymbolicLinksSync(),
      );
    });

    test('".." נדחה — גם כשהוא באמצע הנתיב', () {
      expect(resolveWithinRoot(root, '..'), isNull);
      expect(resolveWithinRoot(root, '../../secret.txt'), isNull);
      expect(resolveWithinRoot(root, 'cache/../../secret.txt'), isNull);
    });

    test('נתיב מוחלט נדחה', () {
      expect(resolveWithinRoot(root, p.join(tempDir.path, 'x.txt')), isNull);
      expect(resolveWithinRoot(root, '/etc/passwd'), isNull);
    });

    test('נתיב UNC נדחה', () {
      expect(resolveWithinRoot(root, r'\\localhost\c$\Windows\x.txt'), isNull);
      expect(resolveWithinRoot(root, '//localhost/share/x.txt'), isNull);
    });

    test('נתיב תלוי-כונן / זרם נתונים חלופי נדחה ב-Windows', () {
      if (!Platform.isWindows) return;
      expect(resolveWithinRoot(root, r'C:x.txt'), isNull);
      expect(resolveWithinRoot(root, 'a.txt:stream'), isNull);
    });

    test('symlink-תיקייה ליעד קיים מחוץ לשורש נדחה', () {
      final outside = Directory(p.join(tempDir.path, 'outside'))
        ..createSync(recursive: true);
      File(p.join(outside.path, 'secret.txt')).writeAsStringSync('סוד');
      if (!_tryLink(p.join(root, 'escape'), outside.path)) return;
      expect(resolveWithinRoot(root, 'escape/secret.txt'), isNull);
      expect(resolveWithinRoot(root, 'escape/new.txt'), isNull);
    });

    // קישור תלוי מוחזר notFound כשעוקבים אחריו, והבדיקה הייתה מתייחסת אליו
    // כשם שטרם נוצר — הצורה הקנונית נשארה בתוך השורש והכתיבה הלכה ליעד.
    test('symlink תלוי (היעד אינו קיים) נדחה, והיעד אינו נוצר', () async {
      final outside = Directory(p.join(tempDir.path, 'outside'))
        ..createSync(recursive: true);
      final victim = File(p.join(outside.path, 'new.txt'));
      if (!_tryLink(p.join(root, 'dangling'), victim.path)) return;

      expect(resolveWithinRoot(root, 'dangling'), isNull);
      await expectLater(
        write('dangling', 'PWNED'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('error.forbidden'),
          ),
        ),
      );
      expect(victim.existsSync(), isFalse);
    });

    // symlink-תיקייה שנוצר לפני שהיעד היה קיים אינו נפתר ע"י
    // resolveSymbolicLinksSync ב-Windows, ולכן הצורה הקנונית לבדה אינה גבול.
    test('symlink-תיקייה שנוצר לפני היעד נדחה, גם אחרי שהיעד נוצר', () async {
      final later = Directory(p.join(tempDir.path, 'later'));
      if (!_tryLink(p.join(root, 'dlink'), later.path)) return;

      expect(resolveWithinRoot(root, 'dlink/pwn.txt'), isNull);
      later.createSync(recursive: true);
      expect(resolveWithinRoot(root, 'dlink/pwn2.txt'), isNull);
      await expectLater(
        write('dlink/pwn2.txt', 'PWNED'),
        throwsA(isA<Exception>()),
      );
      expect(File(p.join(later.path, 'pwn2.txt')).existsSync(), isFalse);
    });

    // canonicalizeNearestExisting משמש גם את extractZip ואת pickFolder, שאין
    // בהם בדיקת רכיבים — קישור תלוי חייב להיפסל בפונקציה עצמה.
    test('canonicalizeNearestExisting מחזיר null לקישור תלוי', () {
      final target = p.join(tempDir.path, 'outside', 'nope.txt');
      final link = p.join(root, 'dangling2');
      if (!_tryLink(link, target)) return;
      expect(canonicalizeNearestExisting(link), isNull);
      expect(canonicalizeNearestExisting(p.join(link, 'deeper.txt')), isNull);
    });

    test('symlink שיעדו בתוך השורש נדחה גם הוא', () {
      Directory(p.join(root, 'real')).createSync(recursive: true);
      if (!_tryLink(p.join(root, 'inner'), p.join(root, 'real'))) return;
      expect(resolveWithinRoot(root, 'inner/a.txt'), isNull);
    });
  });

  group('כתיבה וקריאה', () {
    test('כתיבה יוצרת תיקיות אב, וקריאה מחזירה את התוכן', () async {
      final size = await write('cache/a.json', 'שלום');
      expect(size, utf8.encode('שלום').length);

      final bytes = await service.readWorkspaceFile(
        root: root,
        relativePath: 'cache/a.json',
      );
      expect(utf8.decode(bytes), 'שלום');
    });

    test('append מוסיף לסוף הקובץ', () async {
      await write('log.txt', 'א');
      await write('log.txt', 'ב', append: true);
      final bytes = await service.readWorkspaceFile(
        root: root,
        relativePath: 'log.txt',
      );
      expect(utf8.decode(bytes), 'אב');
    });

    test('כתיבה מחוץ לשורש נדחית ולא נוצר קובץ', () async {
      await expectLater(
        write('../../escaped.txt', 'x'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('error.forbidden'),
          ),
        ),
      );
      expect(
        File(p.join(tempDir.path, 'plugins', 'escaped.txt')).existsSync(),
        isFalse,
      );
    });

    test('קריאה מקובץ שאינו קיים — error.not_found', () async {
      await expectLater(
        service.readWorkspaceFile(root: root, relativePath: 'nope.txt'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('error.not_found'),
          ),
        ),
      );
    });

    test('כתיבה על נתיב שהוא תיקייה נדחית', () async {
      await service.makeWorkspaceDir(root: root, relativePath: 'adir');
      await expectLater(
        write('adir', 'x'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('error.invalid_params'),
          ),
        ),
      );
    });
  });

  group('תקרות ומכסה', () {
    test('כתיבה מעל תקרת ההעברה נדחית ב-error.too_large', () async {
      await expectLater(
        write('big.bin', 'a' * 600),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('error.too_large'),
          ),
        ),
      );
    });

    test('קריאה של קובץ מעל תקרת ההעברה נדחית', () async {
      File(p.join(root, 'big.bin')).writeAsBytesSync(List.filled(600, 65));
      await expectLater(
        service.readWorkspaceFile(root: root, relativePath: 'big.bin'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('error.too_large'),
          ),
        ),
      );
    });

    test('חריגה מהמכסה נחסמת, גם כשכל כתיבה בנפרד חוקית', () async {
      await write('a.bin', 'a' * 500);
      await write('b.bin', 'b' * 500);
      expect(await service.workspaceUsedBytes(root), 1000);

      await expectLater(
        write('c.bin', 'c' * 100),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('error.too_large'),
          ),
        ),
      );
      expect(File(p.join(root, 'c.bin')).existsSync(), isFalse);
    });

    test('append מצטבר אינו עוקף את המכסה', () async {
      await write('log.txt', 'a' * 500);
      await write('log.txt', 'b' * 500, append: true);
      await expectLater(
        write('log.txt', 'c' * 100, append: true),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('error.too_large'),
          ),
        ),
      );
      expect(await service.workspaceUsedBytes(root), 1000);
    });

    // חישוב התפוסה והכתיבה שאחריו לא היו אטומיים: מטח כתיבות מקבילות קרא
    // את אותה תפוסה ועבר את המכסה כאילו כל אחת מהן היחידה.
    test('מטח כתיבות מקבילות אינו עוקף את המכסה', () async {
      final results = await Future.wait(
        List.generate(
          10,
          (i) => write('c$i.bin', 'x' * 200).then<Object?>(
            (v) => v,
            onError: (Object e) => e,
          ),
        ),
      );
      final succeeded = results.whereType<int>().length;
      expect(succeeded, lessThanOrEqualTo(5)); // 1024 / 200
      expect(
        await service.workspaceUsedBytes(root),
        lessThanOrEqualTo(1024),
      );
    });

    test('תקרת מספר הרשומות חוסמת קבצים ריקים', () async {
      final small = PluginFsService(
        maxWorkspaceBytes: 1024,
        maxWorkspaceEntries: 3,
      );
      final r = p.join(tempDir.path, 'entries', 'files');
      await small.ensureWorkspace(r);
      for (var i = 0; i < 3; i++) {
        await small.writeWorkspaceFile(
          root: r,
          relativePath: 'e$i.txt',
          bytes: const [],
        );
      }
      expect(await small.workspaceEntryCount(r), 3);
      await expectLater(
        small.writeWorkspaceFile(
          root: r,
          relativePath: 'e3.txt',
          bytes: const [],
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('error.too_large'),
          ),
        ),
      );
      // makeDir נספר באותה תקרה.
      await expectLater(
        small.makeWorkspaceDir(root: r, relativePath: 'd'),
        throwsA(isA<Exception>()),
      );
    });

    test('תקרת העומק חוסמת נתיב מקונן מדי', () async {
      final shallow = PluginFsService(maxWorkspaceDepth: 3);
      final r = p.join(tempDir.path, 'depth', 'files');
      await shallow.ensureWorkspace(r);
      await shallow.writeWorkspaceFile(
        root: r,
        relativePath: 'a/b/c.txt',
        bytes: const [1],
      );
      await expectLater(
        shallow.writeWorkspaceFile(
          root: r,
          relativePath: 'a/b/c/d.txt',
          bytes: const [1],
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('error.too_large'),
          ),
        ),
      );
    });

    test('מחיקה מחזירה מקום למכסה', () async {
      await write('a.bin', 'a' * 500);
      await write('b.bin', 'b' * 500);
      await service.deleteWorkspaceEntry(root: root, relativePath: 'a.bin');
      expect(await service.workspaceUsedBytes(root), 500);
      await write('c.bin', 'c' * 400);
      expect(await service.workspaceUsedBytes(root), 900);
    });

    test('מחיקת תיקייה רקורסיבית מעדכנת בתים ורשומות', () async {
      await write('sub/x.bin', 'x' * 300);
      await write('sub/y.bin', 'y' * 300);
      final before = await service.workspaceEntryCount(root);
      await service.deleteWorkspaceEntry(
        root: root,
        relativePath: 'sub',
        recursive: true,
      );
      expect(await service.workspaceUsedBytes(root), 0);
      expect(await service.workspaceEntryCount(root), before - 3);
    });

    test('דריסת קובץ קיים אינה נספרת פעמיים במכסה', () async {
      await write('a.bin', 'a' * 500);
      await write('b.bin', 'b' * 500);
      // דריסת a.bin באותו גודל — התפוסה נשארת 1000 ולכן הכתיבה חוקית.
      await write('a.bin', 'x' * 500);
      expect(await service.workspaceUsedBytes(root), 1000);
    });
  });

  group('listDir / makeDir / deleteEntry / stat', () {
    test('listDir מפרט תיקיות לפני קבצים, עם נתיבים יחסיים', () async {
      await write('b.txt', 'x');
      await service.makeWorkspaceDir(root: root, relativePath: 'adir');
      final entries = await service.listWorkspaceDir(
        root: root,
        relativePath: '',
      );
      expect(entries.map((e) => e.path), ['adir', 'b.txt']);
      expect(entries.first.isDirectory, isTrue);
      expect(entries.last.size, 1);
    });

    test('listDir אינו חושף נתיב מוחלט', () async {
      await write('sub/x.txt', 'y');
      final entries = await service.listWorkspaceDir(
        root: root,
        relativePath: 'sub',
      );
      expect(entries.single.path, 'sub/x.txt');
      expect(entries.single.toJson()['path'], isNot(contains(tempDir.path)));
    });

    test('listDir מחוץ לשורש נדחה', () async {
      await expectLater(
        service.listWorkspaceDir(root: root, relativePath: '..'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('error.forbidden'),
          ),
        ),
      );
    });

    test(
      'deleteEntry מוחק קובץ, idempotent, ותיקייה רק עם recursive',
      () async {
        await write('sub/x.txt', 'y');
        expect(
          await service.deleteWorkspaceEntry(
            root: root,
            relativePath: 'sub/x.txt',
          ),
          isTrue,
        );
        expect(
          await service.deleteWorkspaceEntry(
            root: root,
            relativePath: 'sub/x.txt',
          ),
          isFalse,
        );

        await write('sub/y.txt', 'y');
        await expectLater(
          service.deleteWorkspaceEntry(root: root, relativePath: 'sub'),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('error.invalid_params'),
            ),
          ),
        );
        expect(
          await service.deleteWorkspaceEntry(
            root: root,
            relativePath: 'sub',
            recursive: true,
          ),
          isTrue,
        );
      },
    );

    test('מחיקת השורש עצמו נדחית', () async {
      await expectLater(
        service.deleteWorkspaceEntry(root: root, relativePath: ''),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('error.invalid_params'),
          ),
        ),
      );
      expect(Directory(root).existsSync(), isTrue);
    });

    test('מחיקה מחוץ לשורש נדחית והקובץ נשאר', () async {
      final victim = File(p.join(tempDir.path, 'victim.txt'))
        ..writeAsStringSync('חשוב');
      await expectLater(
        service.deleteWorkspaceEntry(
          root: root,
          relativePath: '../../../victim.txt',
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('error.forbidden'),
          ),
        ),
      );
      expect(victim.existsSync(), isTrue);
    });

    test('stat מחזיר null לרשומה שאינה קיימת, ופרטים לקובץ', () async {
      expect(
        await service.statWorkspaceEntry(root: root, relativePath: 'nope'),
        isNull,
      );
      await write('a.txt', 'abc');
      final entry = await service.statWorkspaceEntry(
        root: root,
        relativePath: 'a.txt',
      );
      expect(entry!.size, 3);
      expect(entry.isDirectory, isFalse);
      expect(entry.path, 'a.txt');
    });

    test('stat על השורש מחזיר תיקייה', () async {
      final entry = await service.statWorkspaceEntry(
        root: root,
        relativePath: '',
      );
      expect(entry!.isDirectory, isTrue);
      expect(entry.path, '');
    });
  });
}
