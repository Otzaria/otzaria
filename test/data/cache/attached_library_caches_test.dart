import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/attached_libraries/models/attached_library.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_registry.dart';
import 'package:otzaria/data/cache/acronyms_cache.dart';
import 'package:otzaria/data/cache/generation_cache.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/migration/database/untrusted_database.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../../helpers/memory_settings_cache.dart';
import '../../helpers/seforim_fixture_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AttachedLibraryRegistry previousRegistry;
  late AttachedLibraryRegistry registry;
  final source = BookSource.attached('lib-a');
  const bookId = SeforimFixtureIds.rashiId;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('otzaria_attached_caches');
    previousRegistry = AttachedLibraryRegistry.instance;
    registry = AttachedLibraryRegistry(idleTimeout: null);
    AttachedLibraryRegistry.instance = registry;
    GenerationCache.instance.clear();
    AcronymsCache.instance.clear();
  });

  tearDown(() async {
    await registry.closeAll();
    AttachedLibraryRegistry.instance = previousRegistry;
    GenerationCache.instance.clear();
    AcronymsCache.instance.clear();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  String createDb(void Function(sqlite3.Database db) edit) {
    final path = SeforimFixtureDb.create(tempDir, SeforimFixtureVariant.full);
    final db = sqlite3.sqlite3.open(path);
    edit(db);
    db.close();
    registry.update([
      AttachedLibrary(
        slug: 'lib-a',
        displayName: 'Lib A',
        path: path,
        addedAt: DateTime(2026),
      ),
    ]);
    return path;
  }

  test('דור של ספר ממסד מצורף נקרא מהמסד שלו בלבד', () async {
    createDb(
      (db) => db.execute('UPDATE generation SET name = ?', [
        CommentaryEra.rishonim.hebrewName,
      ]),
    );

    await GenerationCache.instance.reloadAttached();

    expect(
      GenerationCache.instance.getOrderForBook(bookId, source),
      CommentaryEra.rishonim.order,
    );
    expect(
      GenerationCache.instance.getOrderForBook(bookId, BookSource.official),
      CommentaryEra.other.order,
    );
    expect(
      GenerationCache.instance.getOrderForBook(
        bookId,
        BookSource.attached('other'),
      ),
      CommentaryEra.other.order,
    );
  });

  test('כינויים לפי מקור; מסד בלי book_acronym — בלי כינויים', () async {
    final path = createDb(
      (db) => db.execute('INSERT INTO book_acronym VALUES (?, ?)', [
        bookId,
        'abc',
      ]),
    );
    await AcronymsCache.instance.warmUpAttached();
    expect(AcronymsCache.instance.acronymsFor(source, bookId), isNotEmpty);
    expect(AcronymsCache.instance.acronymsFor(BookSource.user, bookId), isNull);

    final db = sqlite3.sqlite3.open(path);
    db.execute('DROP TABLE book_acronym');
    db.close();
    expect(AcronymsCache.readAttachedAcronyms(path), isEmpty);

    AcronymsCache.instance.clearAttached();
    expect(AcronymsCache.instance.acronymsFor(source, bookId), isNull);
  });

  test(
    'מטמון החיפוש מתעדכן כשמטא־דאטה מצורפת נטענת אחרי החיפוש הראשון',
    () async {
      await Settings.init(cacheProvider: MemorySettingsCache());
      final repository = DataRepository();
      addTearDown(repository.bookSearchWorkerForTesting.dispose);
      final ranked = TextBook(id: bookId, title: 'דף מבחן', source: source);
      final unranked = TextBook(
        id: bookId + 1000,
        title: 'דף מבחן',
        source: source,
      );
      final root = Library(categories: [])..books.addAll([unranked, ranked]);
      Future<List<Book>> search(String query) async =>
          (await repository.findBooksAndCategories(
            query,
            root,
            includeLocalHebrewBooks: false,
            reuseCatalog: true,
          )).books;

      expect(await search('דף מבחן'), [same(unranked), same(ranked)]);
      expect(await search('abcdxyz'), isEmpty);

      createDb((db) {
        db.execute('INSERT INTO book_acronym VALUES (?, ?)', [
          bookId,
          'abcdxyz',
        ]);
        db.execute('UPDATE generation SET name = ?', [
          CommentaryEra.rishonim.hebrewName,
        ]);
      });
      await AcronymsCache.instance.warmUpAttached();
      expect(await search('abcdxyz'), [same(ranked)]);

      await GenerationCache.instance.reloadAttached();
      expect(await search('דף מבחן'), [same(ranked), same(unranked)]);

      registry.update([]);
      AcronymsCache.instance.clearAttached();
      await GenerationCache.instance.reloadAttached();
      expect(await search('abcdxyz'), isEmpty);
      expect(await search('דף מבחן'), [same(unranked), same(ranked)]);
    },
  );

  test('דורות המסד המצורף נקראים ב-isolate לפי נתיב', () {
    final path = createDb(
      (db) => db.execute('UPDATE generation SET name = ?', [
        CommentaryEra.rishonim.hebrewName,
      ]),
    );
    expect(
      GenerationCache.readGenerations((
        path: path,
        untrusted: true,
        immutable: false,
      )),
      {bookId: CommentaryEra.rishonim.order},
    );
  });

  test('דורות seforim.db נקראים ב-isolate בפתיחה מהימנה לפי נתיב', () async {
    final path = createDb(
      (db) => db.execute('UPDATE generation SET name = ?', [
        CommentaryEra.rishonim.hebrewName,
      ]),
    );
    final target = trustedDbTarget(path);
    expect(
      await GenerationCache.readGenerationsInIsolate(target),
      {bookId: CommentaryEra.rishonim.order},
    );

    final db = sqlite3.sqlite3.open(path);
    db.execute('DROP TABLE book_generation');
    db.close();
    expect(GenerationCache.readGenerations(target), isEmpty);
  });

  test('warmUp ממתין לטעינה מחדש של דורות המסדים שבדרך', () async {
    createDb(
      (db) => db.execute('UPDATE generation SET name = ?', [
        CommentaryEra.rishonim.hebrewName,
      ]),
    );
    unawaited(GenerationCache.instance.reloadAttached());
    await GenerationCache.instance.warmUp();
    expect(
      GenerationCache.instance.getOrderForBook(bookId, source),
      CommentaryEra.rishonim.order,
    );
  });

  test('חימום שממתין לרענון מקבל את רשימת המסדים העדכנית', () async {
    final cache = GenerationCache.instance;
    registry.update([]);
    final firstReload = cache.reloadAttached();
    final warming = cache.warmUp();

    final intermediateReload = cache.reloadAttached();
    createDb(
      (db) => db.execute('UPDATE generation SET name = ?', [
        CommentaryEra.rishonim.hebrewName,
      ]),
    );
    final latestReload = cache.reloadAttached();

    await warming;
    final orderAtWarmUp = cache.getOrderForBook(bookId, source);
    await Future.wait([firstReload, intermediateReload, latestReload]);
    expect(orderAtWarmUp, CommentaryEra.rishonim.order);
    expect(cache.getOrderForBook(bookId, source), CommentaryEra.rishonim.order);
  });

  test('איפוס מבטל רענון ישן כחסם לחימום ומשאיר את המטמון ריק', () async {
    final cache = GenerationCache.instance;
    createDb(
      (db) => db.execute('UPDATE generation SET name = ?', [
        CommentaryEra.rishonim.hebrewName,
      ]),
    );
    final obsolete = cache.reloadAttached().then((_) => 'רענון ישן');

    cache.clear();
    registry.update([]);
    final warming = cache.warmUp().then((_) => 'חימום חדש');
    final first = await Future.any([obsolete, warming]);

    await Future.wait([obsolete, warming]);
    expect(first, 'חימום חדש');
    expect(cache.getOrderForBook(bookId, source), CommentaryEra.other.order);
  });

  test('הסרת מסד באמצע רענון משאירה רק את הקריאה המשותפת', () async {
    final cache = GenerationCache.instance;
    final slow = Completer<Map<int, int>>();
    final kept = Completer<Map<int, int>>();
    final reads = <String>[];
    final previousReader = GenerationCache.readAttachedGenerations;
    GenerationCache.readAttachedGenerations = (target) {
      reads.add(target.path);
      return target.path == 'slow' ? slow.future : kept.future;
    };
    addTearDown(() {
      GenerationCache.readAttachedGenerations = previousReader;
      if (!slow.isCompleted) slow.complete({});
      if (!kept.isCompleted) kept.complete({});
    });
    final keptLibrary = AttachedLibrary(
      slug: 'lib-a',
      displayName: 'Kept',
      path: 'kept',
      fingerprint: const AttachedLibraryFingerprint(size: 10, modifiedMs: 1),
      addedAt: DateTime(2026),
    );
    registry.update([
      keptLibrary,
      keptLibrary.copyWith(slug: 'slow', path: 'slow'),
    ]);
    final stale = cache.reloadAttached(changedSlugs: const {});
    final warming = cache.warmUp();
    registry.update([keptLibrary]);
    final latest = cache.reloadAttached(changedSlugs: const {});
    expect(reads, unorderedEquals(['kept', 'slow']));

    kept.complete({bookId: CommentaryEra.rishonim.order});
    await Future.wait([latest, warming]).timeout(const Duration(seconds: 2));
    expect(cache.getOrderForBook(bookId, source), CommentaryEra.rishonim.order);
    slow.complete({bookId: CommentaryEra.chazal.order});
    await stale;
    expect(
      cache.getOrderForBook(bookId, BookSource.attached('slow')),
      CommentaryEra.other.order,
    );
  });

  test('שינוי תוכן מצריך קריאה חדשה גם לאותה טביעת אצבע', () async {
    final cache = GenerationCache.instance;
    final first = Completer<Map<int, int>>();
    final second = Completer<Map<int, int>>();
    final reads = [first, second].iterator;
    final previousReader = GenerationCache.readAttachedGenerations;
    GenerationCache.readAttachedGenerations = (_) {
      expect(reads.moveNext(), isTrue);
      return reads.current.future;
    };
    addTearDown(() {
      GenerationCache.readAttachedGenerations = previousReader;
      if (!first.isCompleted) first.complete({});
      if (!second.isCompleted) second.complete({});
    });
    registry.update([
      AttachedLibrary(
        slug: 'lib-a',
        displayName: 'Library',
        path: 'library',
        fingerprint: const AttachedLibraryFingerprint(size: 10, modifiedMs: 1),
        addedAt: DateTime(2026),
      ),
    ]);
    final stale = cache.reloadAttached(changedSlugs: const {});
    final latest = cache.reloadAttached(changedSlugs: const {'lib-a'});
    second.complete({bookId: CommentaryEra.rishonim.order});
    await latest.timeout(const Duration(seconds: 2));
    first.complete({bookId: CommentaryEra.chazal.order});
    await stale;
    expect(cache.getOrderForBook(bookId, source), CommentaryEra.rishonim.order);
  });

  test('כשל קריאת כינויים אינו נשמר כ"אין כינויים" — ניסיון חוזר', () async {
    final previousDelay = AcronymsCache.attachedRetryDelay;
    addTearDown(() => AcronymsCache.attachedRetryDelay = previousDelay);
    AcronymsCache.attachedRetryDelay = Duration.zero;

    final path = createDb(
      (db) => db.execute('INSERT INTO book_acronym VALUES (?, ?)', [
        bookId,
        'abc',
      ]),
    );
    final bytes = File(path).readAsBytesSync();
    File(path).writeAsStringSync('not a database');
    await AcronymsCache.instance.warmUpAttached();
    expect(AcronymsCache.instance.acronymsFor(source, bookId), isNull);

    File(path).writeAsBytesSync(bytes);
    await AcronymsCache.instance.warmUpAttached();
    expect(AcronymsCache.instance.acronymsFor(source, bookId), isNotEmpty);
  });

  test('clearAttached באמצע טעינה אינו מוחק את הטעינה החדשה', () async {
    createDb(
      (db) => db.execute('INSERT INTO book_acronym VALUES (?, ?)', [
        bookId,
        'abc',
      ]),
    );
    final first = AcronymsCache.instance.warmUpAttached();
    AcronymsCache.instance.clearAttached();
    final second = AcronymsCache.instance.warmUpAttached();
    var secondDone = false;
    unawaited(second.whenComplete(() => secondDone = true));
    await first;
    if (!secondDone) {
      expect(
        identical(AcronymsCache.instance.warmUpAttached(), second),
        isTrue,
      );
    }
    await second;
    expect(AcronymsCache.instance.acronymsFor(source, bookId), isNotEmpty);
  });

  test('כינויים מנורמלים נשמרים לפי מסד ובסדר הקריאה', () async {
    const termsBySlug = {
      'lib-a': ['רש״י', 'רשב״ם', 'רַשִׁ״י', '', '!?'],
      'lib-b': ['ABC!'],
      'lib-c': ['ספר־המוסר'],
    };
    final libraries = <AttachedLibrary>[];
    for (final MapEntry(key: slug, value: terms) in termsBySlug.entries) {
      final path = '${tempDir.path}/$slug.db';
      final db = sqlite3.sqlite3.open(path);
      try {
        db.execute('CREATE TABLE book_acronym (bookId, term)');
        for (final term in terms) {
          db.execute('INSERT INTO book_acronym VALUES (?, ?)', [bookId, term]);
        }
        db.execute("INSERT INTO book_acronym VALUES ('invalid', 'כינוי')");
        db.execute('INSERT INTO book_acronym VALUES (?, NULL)', [bookId]);
      } finally {
        db.close();
      }
      libraries.add(
        AttachedLibrary(
          slug: slug,
          displayName: slug,
          path: path,
          addedAt: DateTime(2026),
        ),
      );
    }
    registry.update(libraries);

    await AcronymsCache.instance.warmUpAttached();
    final cache = AcronymsCache.instance;
    expect(cache.attachedAcronymsOf('lib-a'), {
      bookId: ['רשי', 'רשבם', 'רשי'],
    });
    expect(cache.attachedAcronymsOf('lib-b'), {
      bookId: ['abc'],
    });
    expect(cache.attachedAcronymsOf('lib-c'), {
      bookId: ['ספר המוסר'],
    });
  });
}
