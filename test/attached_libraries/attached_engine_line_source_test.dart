import 'dart:io';

import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/attached_libraries/models/attached_library.dart';
import 'package:otzaria/attached_libraries/repository/attached_libraries_repository.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_probe.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_registry.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_store.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_file_swap.dart';
import 'package:path/path.dart' as p;

import '../helpers/seforim_fixture_db.dart';
import '../test_helpers/memory_cache_provider.dart';

/// המנוע מחזיק את קובץ המסד המצורף פתוח: הוא משחרר אותו לפני כל פעולת קובץ
/// ומקבל אותו בחזרה אחריה.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AttachedLibraryRegistry registry;
  late List<String> calls;

  AttachedLibrariesRepository build() => AttachedLibrariesRepository(
    registry: registry,
    probe: (path) async => AttachedLibraryProbe.probeSync(path),
    copyDirectory: () async => p.join(tempDir.path, 'copies'),
  );

  String fixture(String name) {
    final dir = Directory(p.join(tempDir.path, name))..createSync();
    final created = SeforimFixtureDb.create(dir, SeforimFixtureVariant.full);
    final path = p.join(dir.path, '$name.db');
    File(created).renameSync(path);
    return path;
  }

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    tempDir = await Directory.systemTemp.createTemp('otzaria_attached_engine');
    registry = AttachedLibraryRegistry(idleTimeout: null);
    calls = [];
    AttachedLibraryRegistry.configureEngineSource =
        ({required slug, dbPath, required immutable}) async {
          calls.add(
            dbPath == null ? '$slug=null' : '$slug=${p.basename(dbPath)}',
          );
        };
  });

  tearDown(() async {
    await registry.closeAll();
    AttachedLibraryRegistry.configureEngineSource =
        (({required slug, dbPath, required immutable}) async {});
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('לפני שהמנוע נטען — אין קריאות למנוע', () async {
    await build().importFile(fixture('a'));
    await registry.syncEngineSources();
    expect(calls, isEmpty);
    expect(registry.isEngineSourceConfigured('a'), isFalse);
  });

  test('טעינת המנוע מגדירה כל מסד תקין, וצירוף חדש מוגדר מיד', () async {
    final repository = build();
    await repository.importFile(fixture('a'));
    await registry.enableEngineSources();
    expect(calls, ['a=a.db']);
    expect(registry.isEngineSourceConfigured('a'), isTrue);

    await repository.importFile(fixture('b'));
    await registry.syncEngineSources();
    expect(calls, ['a=a.db', 'b=b.db']);
  });

  test('הסרה משחררת את הקובץ במנוע ואינה מגדירה אותו שוב', () async {
    final repository = build();
    final library = (await repository.importFile(fixture('a'))).library!;
    await registry.enableEngineSources();

    await repository.remove(library);
    await registry.syncEngineSources();

    expect(calls, ['a=a.db', 'a=null']);
    expect(registry.isEngineSourceConfigured('a'), isFalse);
  });

  test('שחרור הנעילה: המנוע משחרר ומוגדר שוב לפתיחה עצלה', () async {
    final repository = build();
    final library = (await repository.importFile(fixture('a'))).library!;
    await registry.enableEngineSources();

    await repository.release(library);

    expect(calls, ['a=a.db', 'a=null', 'a=a.db']);
  });

  test('מסד שאינו זמין יוצא מהמנוע, וחוזר כשהוא זמין', () async {
    final repository = build();
    final library = (await repository.importFile(fixture('a'))).library!;
    await registry.enableEngineSources();

    await repository.setReachable(library.path, reachable: false);
    await registry.syncEngineSources();
    await repository.setReachable(library.path, reachable: true);
    await registry.syncEngineSources();

    expect(calls, ['a=a.db', 'a=null', 'a=a.db']);
  });

  test(
    'איפוס runtime: המסדים מוגדרים במנוע מחדש מיד, בלי שינוי ברשימה',
    () async {
      final repository = build();
      await repository.importFile(fixture('a'));
      await registry.enableEngineSources();

      await registry.reset();

      expect(calls, ['a=a.db', 'a=null', 'a=a.db']);
      expect(registry.isEngineSourceConfigured('a'), isTrue);
    },
  );

  group('עדכון קובץ המסד', () {
    test('כשל נעילה בהחלפה מחזיר את מקור השורות של המסד הקיים', () async {
      final repository = build();
      final library = (await repository.importFile(fixture('a'))).library!;
      await registry.enableEngineSources();
      final original = await File(library.path).readAsBytes();

      await expectLater(
        repository.installUpdate(
          library,
          fixture('staged'),
          accept: (_) => true,
          swap: const _LockedSwap(),
        ),
        throwsA(isA<AttachedUpdateFileLocked>()),
      );

      expect(await File(library.path).readAsBytes(), original);
      expect(registry.isEngineSourceConfigured(library.slug), isTrue);
      expect(calls, ['a=a.db', 'a=null', 'a=a.db']);
    });

    test('כשל אחרי הזזת המסד משחזר את הקובץ ואת מקור השורות', () async {
      final repository = build();
      final library = (await repository.importFile(fixture('a'))).library!;
      await registry.enableEngineSources();
      final original = await File(library.path).readAsBytes();

      await expectLater(
        repository.installUpdate(
          library,
          p.join(tempDir.path, 'missing.db'),
          accept: (_) => true,
          swap: const AttachedUpdateFileSwap(lockRetries: 0),
        ),
        throwsA(isA<FileSystemException>()),
      );

      expect(await File(library.path).readAsBytes(), original);
      expect(
        File(AttachedUpdateFileSwap.backupPathFor(library.path)).existsSync(),
        isFalse,
      );
      expect(registry.isEngineSourceConfigured(library.slug), isTrue);
      expect(calls, ['a=a.db', 'a=null', 'a=a.db']);
    });

    test('המנוע משחרר לפני ההחלפה ומוגדר מחדש אחריה', () async {
      final repository = build();
      final library = (await repository.importFile(fixture('a'))).library!;
      await registry.enableEngineSources();
      final staged = fixture('staged');
      final swap = _RecordingSwap(calls);

      await repository.installUpdate(
        library,
        staged,
        accept: (_) => true,
        swap: swap,
      );
      await registry.syncEngineSources();

      expect(calls, ['a=a.db', 'a=null', 'swap', 'a=a.db']);
    });

    test('עדכון שנדחה משחזר את הקובץ ומגדיר אותו שוב', () async {
      final repository = build();
      final library = (await repository.importFile(fixture('a'))).library!;
      await registry.enableEngineSources();
      final staged = fixture('staged');
      final swap = _RecordingSwap(calls);

      await expectLater(
        repository.installUpdate(
          library,
          staged,
          accept: (_) => false,
          swap: swap,
        ),
        throwsA(isA<AttachedUpdateVerificationFailed>()),
      );

      expect(calls, ['a=a.db', 'a=null', 'swap', 'restore', 'a=a.db']);
    });
  });

  test('פעולה שנכשלה בתור המנוע אינה חוסמת את הפעולות שאחריה', () async {
    registry = AttachedLibraryRegistry(
      store: _FailOnceStore(),
      idleTimeout: null,
    );
    await expectLater(registry.enableEngineSources(), throwsStateError);

    await build().importFile(fixture('a'));
    await registry.syncEngineSources();

    expect(calls, ['a=a.db']);
  });

  group('סרק', () {
    test('מסד שהמנוע לא נגע בו משתחרר בו ונשאר מוגדר', () async {
      registry = AttachedLibraryRegistry();
      await build().importFile(fixture('a'));
      await registry.enableEngineSources();
      registry.noteEngineUse();

      await registry.closeIdle(
        now: DateTime.now().add(const Duration(minutes: 1)),
      );
      await registry.engineSourcesSettled;
      expect(calls, ['a=a.db']);

      await registry.closeIdle(
        now: DateTime.now().add(const Duration(minutes: 6)),
      );
      await registry.engineSourcesSettled;
      expect(calls, ['a=a.db', 'a=null', 'a=a.db']);
      expect(registry.isEngineSourceConfigured('a'), isTrue);

      await registry.closeIdle(
        now: DateTime.now().add(const Duration(minutes: 12)),
      );
      await registry.engineSourcesSettled;
      expect(calls, hasLength(3), reason: 'בלי שימוש חדש אין מה לשחרר');
    });
  });

  test('מסד immutable מוגדר כ-immutable', () async {
    final immutables = <bool>[];
    AttachedLibraryRegistry.configureEngineSource =
        ({required slug, dbPath, required immutable}) async {
          immutables.add(immutable);
        };
    registry.update([
      AttachedLibrary(
        slug: 'ro',
        displayName: 'ro',
        path: fixture('ro'),
        mode: AttachedLibraryMode.link,
        placement: AttachedLibraryPlacement.separateRoot,
        hidden: false,
        priority: 0,
        immutable: true,
        status: AttachedLibraryStatus.ok,
        capabilities: const {},
        bookCount: 1,
        addedAt: DateTime(2026),
      ),
    ]);

    await registry.enableEngineSources();

    expect(immutables, [true]);
  });
}

class _FailOnceStore extends AttachedLibraryStore {
  var _failed = false;

  @override
  List<AttachedLibrary>? loadLibrariesOrNull() {
    if (!_failed) {
      _failed = true;
      throw StateError('settings unavailable');
    }
    return super.loadLibrariesOrNull();
  }
}

class _RecordingSwap extends AttachedUpdateFileSwap {
  _RecordingSwap(this.calls);

  final List<String> calls;

  @override
  Future<void> swapIn(String target, String staged) async => calls.add('swap');

  @override
  Future<void> restore(String target) async => calls.add('restore');

  @override
  Future<void> discardBackup(String target) async {}
}

class _LockedSwap extends AttachedUpdateFileSwap {
  const _LockedSwap();

  @override
  Future<void> swapIn(String target, String staged) async =>
      throw AttachedUpdateFileLocked(target);
}
