import 'dart:async';
import 'dart:io';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/attached_libraries/models/attached_library.dart';
import 'package:otzaria/attached_libraries/repository/attached_libraries_repository.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_probe.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_registry.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_store.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../helpers/seforim_fixture_db.dart';
import '../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory copyDir;
  late AttachedLibraryRegistry registry;
  late List<String> probed;
  late int changes;
  late StreamSubscription<void> subscription;

  AttachedLibrariesRepository build({bool copy = false}) {
    final repository = AttachedLibrariesRepository(
      registry: registry,
      probe: (path) async {
        probed.add(path);
        return AttachedLibraryProbe.probeSync(path);
      },
      copyDirectory: () async => copyDir.path,
      copyByDefault: copy,
    );
    subscription = repository.changes.listen((_) => changes++);
    addTearDown(() => subscription.cancel());
    return repository;
  }

  /// מסד מלא בשם [name] תחת [dir], ובו `library_id` = [libraryId] כשניתן.
  String fixture(Directory dir, String name, {String? libraryId}) {
    dir.createSync(recursive: true);
    final created = SeforimFixtureDb.create(dir, SeforimFixtureVariant.full);
    final path = p.join(dir.path, '$name.db');
    File(created).renameSync(path);
    if (libraryId != null) {
      final db = sqlite3.sqlite3.open(path);
      db.execute("INSERT INTO schema_meta VALUES ('library_id', ?)", [
        libraryId,
      ]);
      db.close();
    }
    return path;
  }

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    tempDir = await Directory.systemTemp.createTemp('otzaria_attached_repo');
    copyDir = Directory(p.join(tempDir.path, 'מסדים אישיים'));
    registry = AttachedLibraryRegistry(idleTimeout: null);
    probed = [];
    changes = 0;
  });

  tearDown(() async {
    await registry.closeAll();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('צירוף קובץ', () {
    test('קישור: נשמר בהגדרות, ב-registry, ומשודר', () async {
      final path = fixture(Directory(p.join(tempDir.path, 'src')), 'ספרים');
      final repository = build();

      final result = await repository.importFile(path);

      expect(result.isOk, isTrue);
      final library = result.library!;
      expect(library.mode, AttachedLibraryMode.link);
      expect(library.path, path);
      expect(library.slug, 'ספרים');
      expect(library.bookCount, 2);
      expect(library.isImported, isTrue);
      expect(registry.libraries, [library]);
      expect(const AttachedLibraryStore().loadLibraries(), [library]);
      await pumpEventQueue();
      expect(changes, 1);
    });

    test('אותו קובץ פעמיים — כבר מצורף', () async {
      final path = fixture(Directory(p.join(tempDir.path, 'src')), 'a');
      final repository = build();
      await repository.importFile(path);
      final again = await repository.importFile(path);
      expect(again.problem, AttachedLibraryProblem.alreadyAttached);
    });

    test('slug זהה מקובץ אחר נדחה', () async {
      final first = fixture(
        Directory(p.join(tempDir.path, 'one')),
        'a',
        libraryId: 'shared',
      );
      final second = fixture(
        Directory(p.join(tempDir.path, 'two')),
        'b',
        libraryId: 'shared',
      );
      final repository = build();
      expect((await repository.importFile(first)).isOk, isTrue);

      final result = await repository.importFile(second);

      expect(result.problem, AttachedLibraryProblem.duplicateSlug);
      expect(registry.libraries, hasLength(1));
    });

    test('מסד WAL עם יומן תלוי נדחה במצב קישור, והקובץ לא נגע', () async {
      final path = fixture(Directory(p.join(tempDir.path, 'src')), 'wal');
      final writer = sqlite3.sqlite3.open(path);
      addTearDown(writer.close);
      writer.execute('PRAGMA journal_mode=WAL');
      writer.execute('PRAGMA wal_autocheckpoint=0');
      writer.execute("INSERT INTO source VALUES (99, 'pending')");
      final walLength = File('$path-wal').lengthSync();

      final result = await build().importFile(path);

      expect(result.problem, AttachedLibraryProblem.pendingJournal);
      expect(File('$path-wal').lengthSync(), walLength);
    });

    test('העתקה: היומן מוחל על העותק, והמקור אינו משתנה', () async {
      final source = fixture(Directory(p.join(tempDir.path, 'src')), 'copy');
      final writer = sqlite3.sqlite3.open(source);
      writer.execute('PRAGMA journal_mode=WAL');
      writer.execute('PRAGMA wal_autocheckpoint=0');
      writer.execute("INSERT INTO source VALUES (99, 'pending')");
      // העתקה בזמן שהכותב פתוח — כמו קובץ שמגיע מכונן עם -wal לצידו.
      final repository = build(copy: true);

      final result = await repository.importFile(source);
      writer.close();

      expect(result.isOk, isTrue, reason: '${result.problem}');
      final library = result.library!;
      expect(library.mode, AttachedLibraryMode.copy);
      expect(p.isWithin(copyDir.path, library.path), isTrue);
      expect(File('${library.path}-wal').existsSync(), isFalse);
      expect(library.immutable, isFalse);
      expect(
        copyDir.listSync().map((e) => p.basename(e.path)),
        ['copy.db'],
      );
    });

    test('הסרת עותק מוחקת אותו; הסרת קישור לעולם לא מוחקת', () async {
      final linked = fixture(Directory(p.join(tempDir.path, 'src')), 'linked');
      final copied = fixture(Directory(p.join(tempDir.path, 'src2')), 'copied');
      final repository = build();
      final link = (await repository.importFile(linked)).library!;
      final copy = (await repository.importFile(
        copied,
        mode: AttachedLibraryMode.copy,
      )).library!;
      await registry.repositoryFor(link.slug);

      await repository.remove(link);
      await repository.remove(copy);

      expect(File(linked).existsSync(), isTrue);
      expect(File(copied).existsSync(), isTrue);
      expect(File(copy.path).existsSync(), isFalse);
      expect(registry.libraries, isEmpty);
      expect(registry.isOpen(link.slug), isFalse);
    });
  });

  group('תיקיות מסדים וסריקה', () {
    test('קובצי db בתיקייה מצורפים; קובץ שנמחק מהתיקייה יוצא', () async {
      final folder = Directory(p.join(tempDir.path, 'dbs'));
      final a = fixture(folder, 'a');
      final b = fixture(folder, 'b');
      File(p.join(folder.path, 'notes.txt')).writeAsStringSync('x');
      final repository = build();

      await repository.addFolder(folder.path);

      expect(repository.folders, [folder.path]);
      expect([for (final l in registry.libraries) l.path], [a, b]);
      expect(
        registry.libraries.every((l) => l.folderPath == folder.path),
        isTrue,
      );

      File(b).deleteSync();
      await repository.rescan();
      expect([for (final l in registry.libraries) l.path], [a]);

      await repository.removeFolder(folder.path);
      expect(registry.libraries, isEmpty);
      expect(File(a).existsSync(), isTrue);
    });

    test(
      'slug כפול בתיקייה — השני מסומן כפול, וחוזר לתקין כשהראשון הוסר',
      () async {
        final folder = Directory(p.join(tempDir.path, 'dbs'));
        fixture(folder, 'a', libraryId: 'same');
        final b = fixture(folder, 'b', libraryId: 'same');
        final repository = build();

        await repository.addFolder(folder.path);

        final statuses = [for (final l in registry.libraries) l.status];
        expect(statuses, [
          AttachedLibraryStatus.ok,
          AttachedLibraryStatus.duplicateSlug,
        ]);
        expect(registry.libraryFor('same')?.path, isNot(b));

        File(p.join(folder.path, 'a.db')).deleteSync();
        await repository.rescan();
        expect(registry.libraries.single.path, b);
        expect(registry.libraries.single.status, AttachedLibraryStatus.ok);
      },
    );

    test('קובץ שיובא ונעלם — לא זמין, וההגדרות נשמרות', () async {
      final dir = Directory(p.join(tempDir.path, 'removable'));
      final path = fixture(dir, 'usb');
      final repository = build();
      final library = (await repository.importFile(path)).library!;
      await repository.setHidden(library, true);
      final moved = '${dir.path}_away';
      dir.renameSync(moved);

      await repository.rescan();

      final current = registry.libraries.single;
      expect(current.status, AttachedLibraryStatus.unreachable);
      expect(current.hidden, isTrue);
      expect(registry.visibleLibraries, isEmpty);

      Directory(moved).renameSync(dir.path);
      await repository.rescan();
      expect(registry.libraries.single.status, AttachedLibraryStatus.ok);
    });

    test('טביעת אצבע זהה — אין בדיקה חוזרת; קובץ שהשתנה נבדק מחדש', () async {
      final path = fixture(Directory(p.join(tempDir.path, 'src')), 'fp');
      final repository = build();
      final emitted = <Set<String>>[];
      final sub = repository.changes.listen(emitted.add);
      addTearDown(sub.cancel);
      await repository.importFile(path);
      probed.clear();
      // צירוף ראשון אינו "שינוי תוכן" — ספריו נכנסים לאינדקס כספרים חדשים.
      await Future<void>.delayed(Duration.zero);
      expect(emitted.last, isEmpty);

      expect(await repository.rescan(), isFalse);
      expect(probed, isEmpty);

      final db = sqlite3.sqlite3.open(path);
      db.execute(
        "INSERT INTO book (id, categoryId, sourceId, title) VALUES (9, 2, 1, 'חדש')",
      );
      db.close();
      File(path).setLastModifiedSync(DateTime(2030));

      expect(await repository.rescan(), isTrue);
      expect(probed, [path]);
      expect(registry.libraries.single.bookCount, 3);
      // ספרי המסד שהשתנה — ורק הם — מאונדקסים מחדש.
      await Future<void>.delayed(Duration.zero);
      expect(emitted.last, {registry.libraries.single.slug});
    });
  });

  test('סדר, מיקום והסתרה נשמרים', () async {
    final a = fixture(Directory(p.join(tempDir.path, 'x')), 'a');
    final b = fixture(Directory(p.join(tempDir.path, 'y')), 'b');
    final repository = build();
    await repository.importFile(a);
    final second = (await repository.importFile(b)).library!;

    await repository.move(second, -1);
    await repository.setPlacement(
      registry.libraries.first,
      AttachedLibraryPlacement.mergeIntoLibrary,
    );

    final stored = const AttachedLibraryStore().loadLibraries()
      ..sort((x, y) => x.priority.compareTo(y.priority));
    expect([for (final l in stored) l.slug], ['b', 'a']);
    expect(stored.first.placement, AttachedLibraryPlacement.mergeIntoLibrary);
    expect(stored.last.placement, AttachedLibraryPlacement.separateRoot);
  });
}
