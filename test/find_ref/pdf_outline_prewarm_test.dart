// Tests for [ReferenceBooksCache.prewarmAllPdfOutlines].
//
// המנגנון: לאחר ש-warmUp מסיים, ה-cache מפעיל ברקע parse של ה-outline לכל
// ה-FS PDFs ב-batches מוגבלות (ברירת מחדל 4). הטסטים בודקים את ההתנהגויות
// הקריטיות: throttle בפועל, דילוג על ערכים שכבר בקאש, וביטול לאחר clear().

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/find_ref/repository/reference_books_cache.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';

ReferenceBookHit _hit(String filePath) => ReferenceBookHit(
  bookId: -1,
  title: filePath,
  normalizedTitle: filePath,
  filePath: filePath,
  fileType: 'pdf',
  matchRank: 0,
  orderIndex: 999.0,
);

(String, ReferenceBookHit) _fakeBook(String path) => (path, _hit(path));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MyDatabase cacheDb;
  late SeforimRepository cacheRepo;

  setUp(() async {
    // persistent cache מבודד ב-DB in-memory — בלי override היה נפתח cache.db
    // אמיתי תחת AppData, מה שמזהם מצב בין הרצות וגורם לפרסר לא להיקרא בריצה
    // השנייה (הנתונים נטענים מהמטמון הקבוע).
    cacheDb = MyDatabase.withPath(':memory:');
    cacheRepo = SeforimRepository(cacheDb);
    await cacheRepo.ensureInitialized();

    // singleton — מבטיח מצב נקי בין טסטים.
    ReferenceBooksCache.instance.clear();
    ReferenceBooksCache.instance.pdfOutlineCacheRepositoryOverride = cacheRepo;
    ReferenceBooksCache.instance.pdfFileMetadataProviderOverride =
        (filePath) async {
          if (filePath.isEmpty) return null;
          return (
            fileSize: filePath.length,
            lastModified: filePath.hashCode,
          );
        };
    ReferenceBooksCache.instance.nowProviderOverride = null;
  });

  tearDown(() {
    ReferenceBooksCache.instance.clear();
    ReferenceBooksCache.instance.pdfOutlineCacheRepositoryOverride = null;
    cacheDb.close();
  });

  group('prewarmAllPdfOutlines', () {
    test('רשימת FS PDFs ריקה — אינו קורא לפרסר ומסיים מיד', () async {
      final cache = ReferenceBooksCache.instance;
      cache.setFsPdfBooksForTesting(const []);

      var called = false;
      cache.pdfOutlineParser = (_) async {
        called = true;
        return const [];
      };

      await cache.prewarmAllPdfOutlines();

      expect(called, isFalse);
    });

    test('קורא לפרסר עבור כל קובץ פעם אחת ומאכלס את הקאש', () async {
      final cache = ReferenceBooksCache.instance;
      final paths = ['/a.pdf', '/b.pdf', '/c.pdf'];
      cache.setFsPdfBooksForTesting(paths.map(_fakeBook).toList());

      final calls = <String>[];
      cache.pdfOutlineParser = (p) async {
        calls.add(p);
        return [(p, p, 1)];
      };

      await cache.prewarmAllPdfOutlines();

      expect(calls..sort(), equals(paths..sort()));
      expect(
        cache.pdfOutlineCacheForTesting.keys.toSet(),
        equals(paths.toSet()),
      );
      // הערכים בקאש זמינים — שליפה חוזרת לא מפעילה פרסר נוסף.
      final initialCount = calls.length;
      await cache.getPdfOutlineEntries('/a.pdf');
      expect(calls.length, equals(initialCount));
    });

    test('דילוג על קבצים שכבר בקאש — putIfAbsent מונע parse כפול', () async {
      final cache = ReferenceBooksCache.instance;
      cache.setFsPdfBooksForTesting([
        _fakeBook('/cached.pdf'),
        _fakeBook('/new.pdf'),
      ]);

      // ערך מוכן מראש ב-cache עבור '/cached.pdf'.
      cache.pdfOutlineCacheForTesting['/cached.pdf'] = Future.value(const [
        ('x', 'x', 1),
      ]);

      final calls = <String>[];
      cache.pdfOutlineParser = (p) async {
        calls.add(p);
        return const [];
      };

      await cache.prewarmAllPdfOutlines();

      expect(
        calls,
        equals(['/new.pdf']),
        reason: 'הפרסר נקרא רק על הקובץ שאינו בקאש',
      );
    });

    test('מכבד maxConcurrent — לא יותר מ-N פתיחות מקבילות', () async {
      final cache = ReferenceBooksCache.instance;
      cache.setFsPdfBooksForTesting(
        List.generate(10, (i) => _fakeBook('/p$i.pdf')),
      );

      var active = 0;
      var maxObserved = 0;
      cache.pdfOutlineParser = (_) async {
        active++;
        if (active > maxObserved) maxObserved = active;
        // שתי הנפות אירועים — מאפשרות לקריאות נוספות באותו batch להגיע ל-active++
        // לפני שתוצאה כלשהי מסתיימת.
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        active--;
        return const [];
      };

      await cache.prewarmAllPdfOutlines(maxConcurrent: 3);

      expect(maxObserved, equals(3));
    });

    test('clear() באמצע ה-prewarm עוצר את ה-batches הבאים', () async {
      final cache = ReferenceBooksCache.instance;
      cache.setFsPdfBooksForTesting(
        List.generate(10, (i) => _fakeBook('/p$i.pdf')),
      );

      final pending = <Completer<List<(String, String, int)>>>[];
      var callCount = 0;
      cache.pdfOutlineParser = (_) {
        callCount++;
        final c = Completer<List<(String, String, int)>>();
        pending.add(c);
        return c.future;
      };

      // batches של 2 — סך הכל 5 batches.
      final prewarm = cache.prewarmAllPdfOutlines(maxConcurrent: 2);

      // `getPdfOutlineEntries` ניגש קודם ל-metadata, לכן הקריאות לפרסר
      // מתחילות רק אחרי סבב microtask ראשון.
      await Future<void>.delayed(Duration.zero);
      expect(callCount, equals(2), reason: 'batch ראשון התחיל סינכרונית');

      // משלימים batch 1.
      pending[0].complete(const []);
      pending[1].complete(const []);
      await Future<void>.delayed(Duration.zero);

      // batch 2 התחיל.
      expect(callCount, equals(4));

      // clear() — generation עולה. batch 2 ימשיך עד הסוף, אבל batch 3 ייעצר.
      cache.clear();

      // משלימים את batch 2 כדי שהלולאה תמשיך לבדיקת הדור.
      pending[2].complete(const []);
      pending[3].complete(const []);

      await prewarm;

      expect(
        callCount,
        equals(4),
        reason: 'אין קריאות נוספות לאחר clear() (batches 3+4+5 נעצרו)',
      );
    });

    test('ערכי filePath ריקים נדלגים — אינם מוסיפים קריאה לפרסר', () async {
      final cache = ReferenceBooksCache.instance;
      cache.setFsPdfBooksForTesting([
        _fakeBook('/real.pdf'),
        _fakeBook(''), // אסור שיגיע לפרסר
        _fakeBook('/also.pdf'),
      ]);

      final calls = <String>[];
      cache.pdfOutlineParser = (p) async {
        calls.add(p);
        return const [];
      };

      await cache.prewarmAllPdfOutlines();

      expect(calls.toSet(), equals({'/real.pdf', '/also.pdf'}));
      expect(calls, isNot(contains('')));
    });

    test('maxConcurrent חייב להיות חיובי — נכשל גם ב-release', () {
      // ולידציה רצה תמיד (ולא רק assert), כי i += 0 ייצור לולאה אינסופית.
      final cache = ReferenceBooksCache.instance;
      cache.setFsPdfBooksForTesting([_fakeBook('/a.pdf')]);
      expect(
        () => cache.prewarmAllPdfOutlines(maxConcurrent: 0),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => cache.prewarmAllPdfOutlines(maxConcurrent: -1),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
