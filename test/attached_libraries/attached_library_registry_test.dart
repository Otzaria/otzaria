import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/attached_libraries/models/attached_library.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_registry.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_store.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as p;

import '../helpers/seforim_fixture_db.dart';
import '../test_helpers/memory_cache_provider.dart';

AttachedLibrary _library(
  String slug,
  String path, {
  int priority = 0,
  bool hidden = false,
  AttachedLibraryStatus status = AttachedLibraryStatus.ok,
}) => AttachedLibrary(
  slug: slug,
  displayName: slug,
  path: path,
  priority: priority,
  hidden: hidden,
  status: status,
  addedAt: DateTime(2026),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  const store = AttachedLibraryStore();

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    tempDir = await Directory.systemTemp.createTemp('otzaria_registry');
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('AttachedLibraryStore', () {
    test('שמירה וקריאה חוזרת של מסדים ותיקיות', () async {
      final library = _library('a', r'C:\db\a.db', priority: 2).copyWith(
        fingerprint: const AttachedLibraryFingerprint(
          size: 10,
          modifiedMs: 20,
          dbVersion: '3',
        ),
        capabilities: {AttachedLibraryCapability.toc},
        bookCount: 4,
      );
      await store.saveLibraries([library]);
      await store.saveFolders([r'C:\dbs']);

      expect(store.loadLibraries(), [library]);
      expect(store.loadFolders(), [r'C:\dbs']);
    });

    test('רשומה פגומה אינה מאבדת את שאר המסדים', () async {
      final good = _library('good', r'C:\db\good.db');
      await Settings.setValue<String>(
        SettingsRepository.keyAttachedLibraries,
        '[{"displayName": "בלי slug"}, ${jsonEncode(good.toJson())}]',
      );
      expect(store.loadLibraries(), [good]);
    });

    test('JSON שבור — רשימה ריקה', () async {
      await Settings.setValue<String>(
        SettingsRepository.keyAttachedLibraries,
        '{not json',
      );
      await Settings.setValue<String>(
        SettingsRepository.keyAttachedLibraryFolders,
        '[1, "", "C:/ok"]',
      );
      expect(store.loadLibraries(), isEmpty);
      expect(store.loadLibrariesOrNull(), isNull);
      expect(store.loadFolders(), ['C:/ok']);
    });

    test('JSON שבור — הרשימה "לא ידועה" ברישום עד update', () async {
      await Settings.setValue<String>(
        SettingsRepository.keyAttachedLibraries,
        '{"not": "a list"}',
      );
      final registry = AttachedLibraryRegistry(store: store, idleTimeout: null);
      expect(registry.libraries, isEmpty);
      expect(registry.librariesIfKnown, isNull);

      registry.update(const []);
      expect(registry.librariesIfKnown, isEmpty);
    });

    test('ערך חסר — רשימה ריקה וידועה', () {
      final registry = AttachedLibraryRegistry(store: store, idleTimeout: null);
      expect(registry.librariesIfKnown, isEmpty);
    });

    test('תיקייה נשמרת ב-origin ומשוחזרת', () {
      final json = _library('f', '/x/f.db').toJson()..['origin'] = 'folder:/x';
      final restored = AttachedLibrary.fromJson(json);
      expect(restored.folderPath, '/x');
      expect(restored.isImported, isFalse);
    });
  });

  group('AttachedLibraryRegistry', () {
    late String pathA;
    late String pathB;

    setUp(() {
      final dirA = Directory(p.join(tempDir.path, 'a'))..createSync();
      final dirB = Directory(p.join(tempDir.path, 'b'))..createSync();
      pathA = SeforimFixtureDb.create(dirA, SeforimFixtureVariant.full);
      pathB = SeforimFixtureDb.create(dirB, SeforimFixtureVariant.minimal);
    });

    test('הרשימה נטענת מההגדרות וממוינת לפי עדיפות', () async {
      await store.saveLibraries([
        _library('b', pathB, priority: 1),
        _library('a', pathA),
        _library('h', pathA, priority: 2, hidden: true),
      ]);
      final registry = AttachedLibraryRegistry(idleTimeout: null);

      expect([for (final l in registry.libraries) l.slug], ['a', 'b', 'h']);
      expect([for (final l in registry.visibleLibraries) l.slug], ['a', 'b']);
      expect(registry.pathFor(BookSource.attached('b')), pathB);
      expect(registry.pathFor(BookSource.official), isNull);
    });

    test('פתיחה עצלה, מאגר משותף, ושחרור הקובץ', () async {
      final registry = AttachedLibraryRegistry(idleTimeout: null)
        ..update([_library('a', pathA)]);
      expect(registry.isOpen('a'), isFalse);

      final first = await registry.repositoryFor('a');
      final second = await registry.repositoryForSource(
        BookSource.attached('a'),
      );
      expect(first, isNotNull);
      expect(second, same(first));
      expect(registry.isOpen('a'), isTrue);
      expect(await first!.getBook(SeforimFixtureIds.bereshitId), isNotNull);

      await registry.close('a');
      expect(registry.isOpen('a'), isFalse);
      // ללא נעילה — מחיקה מצליחה גם ב-Windows.
      File(pathA).deleteSync();
      expect(await registry.repositoryFor('a'), isNull);
    });

    test('מאגר שהוחזק אחרי שחרור אינו פותח את הקובץ מחדש', () async {
      final registry = AttachedLibraryRegistry(idleTimeout: null)
        ..update([_library('a', pathA)]);
      final stale = (await registry.repositoryFor('a'))!;
      await registry.close('a');

      await expectLater(stale.database.database, throwsStateError);
      expect(stale.database.isOpen, isFalse);
      // דרך ה-registry נפתח חיבור חדש.
      final fresh = await registry.repositoryFor('a');
      expect(fresh, isNot(same(stale)));
      expect(await fresh!.getBook(SeforimFixtureIds.bereshitId), isNotNull);
      await registry.closeAll();
    });

    test('הפתיחה הראשונה ממתינה לשער העלייה', () async {
      final gate = Completer<void>();
      final previous = AttachedLibraryRegistry.startupGate;
      AttachedLibraryRegistry.startupGate = () => gate.future;
      addTearDown(() => AttachedLibraryRegistry.startupGate = previous);
      final registry = AttachedLibraryRegistry(idleTimeout: null)
        ..update([_library('a', pathA)]);

      var opened = false;
      final pending = registry.repositoryFor('a').then((r) => opened = true);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(opened, isFalse);
      expect(registry.isOpen('a'), isFalse);

      gate.complete();
      await pending;
      expect(registry.isOpen('a'), isTrue);
      await registry.closeAll();
    });

    test('בדיקת פתיחה שלא הסתיימה בזמן — אין מאגר', () async {
      final previous = AttachedLibraryRegistry.openTimeout;
      AttachedLibraryRegistry.openTimeout = Duration.zero;
      addTearDown(() => AttachedLibraryRegistry.openTimeout = previous);
      final registry = AttachedLibraryRegistry(idleTimeout: null)
        ..update([_library('a', pathA)]);
      expect(await registry.repositoryFor('a'), isNull);
      expect(registry.isOpen('a'), isFalse);
    });

    test('מסד לא תקין, לא נגיש או לא רשום — אין מאגר', () async {
      final registry = AttachedLibraryRegistry(idleTimeout: null)
        ..update([
          _library(
            'dup',
            pathA,
            status: AttachedLibraryStatus.duplicateSlug,
          ),
          _library('gone', p.join(tempDir.path, 'gone.db')),
        ]);
      expect(await registry.repositoryFor('dup'), isNull);
      expect(await registry.repositoryFor('gone'), isNull);
      expect(await registry.repositoryFor('nope'), isNull);
    });

    test('סגירה אחרי זמן סרק; הגישה הבאה פותחת מחדש', () async {
      final registry = AttachedLibraryRegistry(
        idleTimeout: const Duration(minutes: 5),
      )..update([_library('a', pathA)]);
      addTearDown(registry.closeAll);
      final repository = await registry.repositoryFor('a');
      expect(registry.isOpen('a'), isTrue);

      registry.closeIdle(now: DateTime.now());
      expect(registry.isOpen('a'), isTrue);

      registry.closeIdle(now: DateTime.now().add(const Duration(minutes: 6)));
      expect(registry.isOpen('a'), isFalse);

      expect(await registry.repositoryFor('a'), same(repository));
      expect(
        await repository!.getBook(SeforimFixtureIds.bereshitId),
        isNotNull,
      );
    });

    test('שינוי נתיב ב-update סוגר את החיבור הישן', () async {
      final registry = AttachedLibraryRegistry(idleTimeout: null)
        ..update([_library('a', pathA)]);
      final before = await registry.repositoryFor('a');
      registry.update([_library('a', pathB)]);
      expect(registry.isOpen('a'), isFalse);
      final after = await registry.repositoryFor('a');
      expect(after, isNot(same(before)));
      expect(registry.pathFor(BookSource.attached('a')), pathB);
      await registry.closeAll();
    });

    test('reset שוכח את הרשימה וקורא אותה שוב מההגדרות', () async {
      final registry = AttachedLibraryRegistry(idleTimeout: null)
        ..update([_library('a', pathA)]);
      await registry.repositoryFor('a');
      await registry.reset();
      expect(registry.isOpen('a'), isFalse);
      expect(registry.libraries, isEmpty);
    });
  });
}
