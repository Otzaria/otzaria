import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/services/orphan_library_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('orphan_library_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// יוצר עותק ספרייה בנתיב [root]: תיקיית books עם קובץ DB בגודל [dbBytes].
  Future<String> createLibraryCopy(String root, {int dbBytes = 100}) async {
    final books = Directory(p.join(root, 'books'));
    await books.create(recursive: true);
    await File(
      p.join(books.path, 'seforim.db'),
    ).writeAsBytes(List.filled(dbBytes, 0));
    return root;
  }

  group('evaluateCandidate', () {
    test('מזהה עותק יתום עם תיקיית books לא-ריקה ומחשב נפח', () async {
      final root = await createLibraryCopy(
        p.join(tempDir.path, 'otzaria'),
        dbBytes: 250,
      );
      await File(p.join(root, 'index', 'meta.json')).create(recursive: true);

      final info = await OrphanLibraryService.evaluateCandidate(
        candidateRoot: root,
        activePaths: [p.join(tempDir.path, 'active', 'books')],
      );

      expect(info, isNotNull);
      expect(p.equals(info!.path, root), isTrue);
      expect(info.sizeBytes, 250);
    });

    test('מחזיר null כשהתיקייה לא קיימת', () async {
      final info = await OrphanLibraryService.evaluateCandidate(
        candidateRoot: p.join(tempDir.path, 'missing'),
        activePaths: const [],
      );
      expect(info, isNull);
    });

    test('מחזיר null כשאין תיקיית books או כשהיא ריקה', () async {
      final noBooks = Directory(p.join(tempDir.path, 'no_books'));
      await noBooks.create(recursive: true);
      expect(
        await OrphanLibraryService.evaluateCandidate(
          candidateRoot: noBooks.path,
          activePaths: const [],
        ),
        isNull,
      );

      final emptyBooks = Directory(p.join(tempDir.path, 'empty', 'books'));
      await emptyBooks.create(recursive: true);
      expect(
        await OrphanLibraryService.evaluateCandidate(
          candidateRoot: p.join(tempDir.path, 'empty'),
          activePaths: const [],
        ),
        isNull,
      );
    });

    test('מחזיר null כשנתיב פעיל יושב בתוך התיקייה או שווה לה', () async {
      final root = await createLibraryCopy(p.join(tempDir.path, 'otzaria'));

      expect(
        await OrphanLibraryService.evaluateCandidate(
          candidateRoot: root,
          activePaths: [p.join(root, 'books')],
        ),
        isNull,
      );
      expect(
        await OrphanLibraryService.evaluateCandidate(
          candidateRoot: root,
          activePaths: [root],
        ),
        isNull,
      );
    });

    test('נתיב פעיל ריק אינו חוסם את הזיהוי', () async {
      final root = await createLibraryCopy(p.join(tempDir.path, 'otzaria'));
      final info = await OrphanLibraryService.evaluateCandidate(
        candidateRoot: root,
        activePaths: const [''],
      );
      expect(info, isNotNull);
    });
  });

  group('delete', () {
    test('מוחק את העותק כשהאימות החוזר עדיין מזהה אותו', () async {
      final root = await createLibraryCopy(p.join(tempDir.path, 'otzaria'));
      final info = (await OrphanLibraryService.evaluateCandidate(
        candidateRoot: root,
        activePaths: const [],
      ))!;

      await OrphanLibraryService.delete(
        info,
        redetect: () => OrphanLibraryService.evaluateCandidate(
          candidateRoot: root,
          activePaths: const [],
        ),
      );

      expect(await Directory(root).exists(), isFalse);
    });

    test('זורק ולא מוחק כשהאימות החוזר כבר לא מזהה עותק יתום', () async {
      final root = await createLibraryCopy(p.join(tempDir.path, 'otzaria'));
      final info = (await OrphanLibraryService.evaluateCandidate(
        candidateRoot: root,
        activePaths: const [],
      ))!;

      await expectLater(
        OrphanLibraryService.delete(
          info,
          redetect: () => OrphanLibraryService.evaluateCandidate(
            candidateRoot: root,
            activePaths: [p.join(root, 'books')],
          ),
        ),
        throwsStateError,
      );
      expect(await Directory(root).exists(), isTrue);
    });
  });

  test('בדיקת רישום ההסרה רצה ב-isolate עזר ומחזירה תשובה', () async {
    expect(
      await OrphanLibraryService.machineWideInstallRegistered(),
      isA<bool>(),
    );
  }, skip: Platform.isWindows ? false : 'רישום Windows בלבד');

  group('formatBytes', () {
    test('מציג GB מעל ג\'יגה ו-MB מתחת', () {
      expect(
        OrphanLibraryService.formatBytes(3 * 1024 * 1024 * 1024),
        '3.0 GB',
      );
      expect(OrphanLibraryService.formatBytes(512 * 1024 * 1024), '512.0 MB');
    });
  });
}
