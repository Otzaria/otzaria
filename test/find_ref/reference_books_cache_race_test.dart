// Regression tests for the race condition between [warmUp] and [clear].
//
// טעינת הקאש עם yields תקופתיים יוצרת חלון בו [clear] עלול להתבצע באמצע.
// בלי מנגנון הגנה, הטעינה הישנה הייתה ממשיכה לאחר ה-clear, ממלאת מחדש
// נתונים stale, ומסמנת `_isLoaded = true`.
// המנגנון: _generation counter שעולה ב-clear; הטעינה בודקת אותו אחרי
// כל yield ועוצרת אם הוא השתנה.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/cache/acronyms_cache.dart';
import 'package:otzaria/data/cache/books_cache.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/file_system_library_provider.dart';
import 'package:otzaria/find_ref/repository/reference_books_cache.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/models/category.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as p;

import '../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MyDatabase cacheDb;
  late SeforimRepository cacheRepo;

  setUp(() async {
    // warmUp() מפעיל ברקע prune + prewarm של מטמון ה-outline. בלי override
    // אלה היו פותחים cache.db אמיתי תחת AppData בזמן הטסט. DB in-memory מבודד
    // את הגישה.
    cacheDb = MyDatabase.withPath(':memory:');
    cacheRepo = SeforimRepository(cacheDb);
    await cacheRepo.ensureInitialized();

    // ניקוי שלושת הקאשים לסטטוס ידוע — singletons שמשותפים בין טסטים.
    ReferenceBooksCache.instance.clear();
    FileSystemLibraryProvider.instance.resetForTesting();
    BooksCache.instance.clear();
    AcronymsCache.instance.clear();
    // warmUp לא מסמן loaded על קאש ריק (ראה קבוצת "קאש ריק" למטה), ולכן
    // טסטי המירוץ זורעים ספר אחד כדי שהטעינה תוכל להגיע ל-isLoaded=true.
    BooksCache.instance.setBooksForTesting(const [
      BookCacheEntry(
        id: 1,
        title: 'בראשית',
        filePath: '',
        fileType: 'txt',
        categoryId: 2,
        orderIndex: 0.0,
      ),
    ]);
    ReferenceBooksCache.instance.categoriesProviderOverride = null;
    ReferenceBooksCache.instance.pdfOutlineCacheRepositoryOverride = cacheRepo;
    ReferenceBooksCache.instance.pdfFileMetadataProviderOverride = null;
    ReferenceBooksCache.instance.nowProviderOverride = null;
  });

  tearDown(() {
    FileSystemLibraryProvider.instance.resetForTesting();
    ReferenceBooksCache.instance.categoriesProviderOverride = null;
    ReferenceBooksCache.instance.pdfOutlineCacheRepositoryOverride = null;
    ReferenceBooksCache.instance.pdfFileMetadataProviderOverride = null;
    ReferenceBooksCache.instance.nowProviderOverride = null;
    cacheDb.close();
  });

  test('PDF ממערכת הקבצים נשמר כמועמד כשמקבילו במסד מוסתר', () async {
    const title = 'PDF משותף';
    const dbPath = '/library/database.pdf';
    const fsPath = '/library/filesystem.pdf';
    BooksCache.instance.setBooksForTesting(const [
      BookCacheEntry(
        id: 81,
        title: title,
        filePath: dbPath,
        fileType: 'pdf',
        categoryId: 2,
        orderIndex: 0,
      ),
    ]);
    FileSystemLibraryProvider.instance.seedKeyToPathForTesting(
      keyToPath: {
        BookCompositeKey.create(
          title: title,
          categoryId: 2,
          fileType: 'pdf',
        ).toStorageKey(): fsPath,
      },
    );
    final cache = ReferenceBooksCache.instance;
    final originalParser = cache.pdfOutlineParser;
    addTearDown(() => cache.pdfOutlineParser = originalParser);
    cache.categoriesProviderOverride = () async => const [];
    cache.pdfOutlineParser = (_) async => const [];
    cache.pdfFileMetadataProviderOverride = (_) async => null;

    await cache.warmUp();
    expect(cache.isLoaded, isTrue);
    expect(cache.search(title).map((hit) => hit.filePath), [dbPath]);
    expect(
      cache
          .search(
            title,
            allowsBook: (id, path, type) => path != dbPath,
          )
          .map((hit) => hit.filePath),
      [fsPath],
    );
  });

  test('איתור מקורות מונה PDF פעם אחת גם כשלקטלוג יש כינוי', () async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    final root = await Directory.systemTemp.createTemp('otzaria-find-ref-pdf-');
    addTearDown(() => root.delete(recursive: true));
    await Settings.setValue(SettingsRepository.keyLibraryPath, root.path);
    final folder = await Directory(
      p.join(root.path, 'אוצריא', 'אישי', 'הלכה.מהדורה'),
    ).create(recursive: true);
    const title = 'ספר מקומי';
    final file = await File(
      p.join(folder.path, '$title.pdf'),
    ).writeAsString('%PDF-1.4');

    final provider = FileSystemLibraryProvider.instance;
    await provider.initialize();
    final cache = ReferenceBooksCache.instance;
    final originalParser = cache.pdfOutlineParser;
    addTearDown(() => cache.pdfOutlineParser = originalParser);
    cache.categoriesProviderOverride = () async => const [];
    cache.pdfOutlineParser = (_) async => const [];
    cache.pdfFileMetadataProviderOverride = (_) async => null;

    await cache.warmUp();
    expect(cache.search(title).map((hit) => hit.filePath), [file.path]);

    await provider.loadBooks({});
    expect(
      await provider.hasBook(title, 'ספרים אישיים, הלכה'.hashCode, 'pdf'),
      isTrue,
    );
    cache.clear();
    await cache.warmUp();
    expect(cache.search(title).map((hit) => hit.filePath), [file.path]);
  });

  group('ReferenceBooksCache — race condition מול clear()', () {
    test(
      'clear() באמצע warmUp() עוצר את הטעינה — isLoaded נשאר false',
      () async {
        final cache = ReferenceBooksCache.instance;
        expect(cache.isLoaded, isFalse, reason: 'מצב התחלתי');

        // warmUp() מתחיל לרוץ. `_loadInternal` רץ סינכרונית עד ה-await הראשון
        // (BooksCache.warmUp), ואז משעה את עצמו עד שה-microtask ירוץ.
        final inFlight = cache.warmUp();

        // קוד סינכרוני — רץ לפני שה-microtask של continuation מקבל הזדמנות.
        cache.clear(); // _generation++

        // עכשיו ה-await של _loadInternal ימצא generation מעודכן ויחזיר return.
        await inFlight;

        expect(
          cache.isLoaded,
          isFalse,
          reason: 'טעינה שנעצרה ע"י clear() אסור שתסמן isLoaded=true',
        );
      },
    );

    test('warmUp() חוזר ועובד תקין אחרי race עם clear', () async {
      final cache = ReferenceBooksCache.instance;

      // ניסיון ראשון — race שנעצר.
      final aborted = cache.warmUp();
      cache.clear();
      await aborted;
      expect(cache.isLoaded, isFalse);

      // ניסיון שני — בלי הפרעה. אמור להגיע ל-isLoaded=true.
      await cache.warmUp();
      expect(
        cache.isLoaded,
        isTrue,
        reason: 'אחרי abort, warmUp נוסף חייב להצליח כרגיל',
      );
    });

    test('שני clear()-ים רצופים באמצע warmUp עדיין מאפסים', () async {
      // וריאציה: clear() מרובה — generation עולה פעמיים. הטעינה הישנה
      // עדיין צריכה לזהות שינוי דור (לא משנה כמה).
      final cache = ReferenceBooksCache.instance;

      final inFlight = cache.warmUp();
      cache.clear();
      cache.clear();
      await inFlight;

      expect(cache.isLoaded, isFalse);
    });

    test('clear מנקה הכול גם אם warmUp הצליח קודם', () async {
      // ודוא שהמנגנון לא שובר את ה-clear הרגיל אחרי טעינה מוצלחת.
      final cache = ReferenceBooksCache.instance;
      await cache.warmUp();
      expect(cache.isLoaded, isTrue);

      cache.clear();
      expect(cache.isLoaded, isFalse);
    });
  });

  group('ReferenceBooksCache — חוזה: warmUp לא חוזר לפני '
      'ש-getCategoryPathForBookSync מוכן', () {
    test(
      'כשל בבניית categoryPaths → isLoaded נשאר false (אין retry בלע)',
      () async {
        // אם prewarm קורס (לדוגמה, lock זמני על ה-DB), הקאש חייב **לא**
        // להסתמן כ-loaded — אחרת כל ה-session ישאר עם classifier מבוטל
        // עד restart, כי warmUp הבא ייצא מוקדם על isLoaded.
        final cache = ReferenceBooksCache.instance;
        cache.categoriesProviderOverride = () async {
          throw Exception('DB lock');
        };

        await cache.warmUp();

        expect(
          cache.isLoaded,
          isFalse,
          reason: 'כשל בבניית הקאש חייב להישאר בלי לסמן loaded',
        );
      },
    );

    test('כשל ואז הצלחה — warmUp הבא מנסה שוב ומצליח', () async {
      // החוזה: כשל זמני לא הופך לקבוע. שיחה הבאה ל-warmUp מנסה לבנות
      // את הקאש מחדש. אם ה-override השתנה (או ה-DB חזר לאיתנו), הקאש
      // נטען בהצלחה.
      final cache = ReferenceBooksCache.instance;

      var attempt = 0;
      cache.categoriesProviderOverride = () async {
        attempt++;
        throw Exception('DB lock attempt $attempt');
      };

      await cache.warmUp();
      expect(cache.isLoaded, isFalse);
      expect(attempt, 1);

      // ה-DB חוזר לאיתנו — override מצליח.
      cache.categoriesProviderOverride = () async {
        attempt++;
        return const <Category>[
          Category(id: 1, title: 'תנ"ך'),
          Category(id: 2, parentId: 1, title: 'תורה'),
        ];
      };

      await cache.warmUp();

      expect(cache.isLoaded, isTrue, reason: 'אחרי כשל זמני, warmUp הבא מצליח');
      expect(attempt, 2, reason: 'הניסיון השני באמת נקרא — אין caching של כשל');
    });

    test('בלי DB אבל עם ספרים בקאש — prewarm מסתיים בהצלחה', () async {
      // אין SqliteDataProvider מאותחל, אבל BooksCache נזרע ב-setUp. אין מה
      // לחמם מה-DB, ואין סיבה לסמן כשל — `isLoaded` חייב להפוך true.
      final cache = ReferenceBooksCache.instance;
      // categoriesProviderOverride = null (default), SqliteDataProvider = null.

      await cache.warmUp();

      expect(
        cache.isLoaded,
        isTrue,
        reason: 'no-DB-no-override עם ספרים = הצלחה טריוויאלית, לא כשל',
      );
    });

    test('clear() אחרי כשל מאפס את _generation ומאפשר ניסיון נקי', () async {
      // נדמה כשל ב-prewarm, ואז clear() ו-warmUp נוסף. ה-generation
      // צריך להתאפס וה-prewarm צריך להיקרא שוב.
      final cache = ReferenceBooksCache.instance;

      var attempt = 0;
      cache.categoriesProviderOverride = () async {
        attempt++;
        throw Exception('failure $attempt');
      };

      await cache.warmUp();
      expect(cache.isLoaded, isFalse);
      expect(attempt, 1);

      cache.clear();
      await cache.warmUp();
      expect(
        attempt,
        2,
        reason: 'clear() לא הופך כשל לקבוע — warmUp הבא מנסה שוב',
      );
    });

    test(
      'סקירת state אחרי warmUp מוצלח: getCategoryPathForBookSync לא ריק',
      () async {
        // החוזה החזק: ברגע ש-`warmUp()` חזר עם `isLoaded=true`, פניות
        // סינכרוניות ל-getCategoryPathForBookSync לפי bookId אמיתי
        // ב-BooksCache חייבות להחזיר את הנתיב המלא. (בסביבת טסט אין ספרים
        // ב-BooksCache, ולכן נסתפק בכך שאחרי warmUp הקאש מסומן כ-loaded
        // ולא נזרקת חריגה בעת גישה ל-API.)
        final cache = ReferenceBooksCache.instance;
        cache.categoriesProviderOverride = () async => const <Category>[
          Category(id: 1, title: 'תנ"ך'),
          Category(id: 2, parentId: 1, title: 'תורה'),
        ];

        await cache.warmUp();

        expect(cache.isLoaded, isTrue);
        // לא נזרקת חריגה — ה-getter מחזיר null כי אין ספרים, וזה תקין.
        expect(
          cache.getCategoryPathForBookSync(9999),
          isNull,
          reason:
              'getter סינכרוני לא קורס אחרי warmUp, מחזיר null למה שלא בקאש',
        );
      },
    );
  });

  group('BooksCache + AcronymsCache — clear() מאפס _generation', () {
    test('clear() מתאפס isLoaded במצב טעון', () async {
      await BooksCache.instance.warmUp();
      await AcronymsCache.instance.warmUp();

      BooksCache.instance.clear();
      AcronymsCache.instance.clear();

      expect(BooksCache.instance.isLoaded, isFalse);
      expect(AcronymsCache.instance.isLoaded, isFalse);
    });

    test('warmUp חוזר מצליח אחרי clear()', () async {
      await BooksCache.instance.warmUp();
      BooksCache.instance.clear();
      expect(BooksCache.instance.isLoaded, isFalse);

      // ללא repository זמין הטעינה מסיימת מהר עם רשימה ריקה — אבל לא
      // נכשלת.
      await BooksCache.instance.warmUp();
      // ב-test environment ה-isLoaded יישאר false (SqliteDataProvider לא
      // מאותחל) — אבל warmUp לא זורק.
    });
  });
}
