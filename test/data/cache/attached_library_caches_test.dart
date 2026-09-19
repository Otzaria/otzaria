import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/attached_libraries/models/attached_library.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_registry.dart';
import 'package:otzaria/data/cache/acronyms_cache.dart';
import 'package:otzaria/data/cache/generation_cache.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

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

  test('דורות המסד המצורף נקראים ב-isolate לפי נתיב', () {
    final path = createDb(
      (db) => db.execute('UPDATE generation SET name = ?', [
        CommentaryEra.rishonim.hebrewName,
      ]),
    );
    expect(GenerationCache.readAttachedGenerations(path), {
      bookId: CommentaryEra.rishonim.order,
    });
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
}
