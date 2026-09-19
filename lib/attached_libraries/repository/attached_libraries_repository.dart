import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart'
    show ValueNotifier, debugPrint, visibleForTesting;
import 'package:otzaria/attached_libraries/models/attached_library.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_probe.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_registry.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_store.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/migration/database/journal_mode.dart';
import 'package:path/path.dart' as p;

typedef AttachedLibraryProbeFn =
    Future<AttachedLibraryProbeResult> Function(String path);

/// תוצאת צירוף קובץ: [library] בהצלחה, אחרת [problem].
class AttachResult {
  final AttachedLibrary? library;
  final AttachedLibraryProblem? problem;

  const AttachResult.success(AttachedLibrary this.library) : problem = null;
  const AttachResult.failure(AttachedLibraryProblem this.problem)
    : library = null;

  bool get isOk => library != null;
}

/// הפעולות על המסדים המצורפים: צירוף, תיקיות מסדים, סריקה, סדר והסרה.
///
/// כל שינוי נשמר ב-[AttachedLibraryStore], מעודכן ב-[AttachedLibraryRegistry]
/// ומשודר ב-[changes] — המאזין בונה מחדש את עץ הספרייה.
class AttachedLibrariesRepository {
  AttachedLibrariesRepository({
    this._store = const AttachedLibraryStore(),
    AttachedLibraryRegistry? registry,
    AttachedLibraryProbeFn? probe,
    Future<String> Function()? copyDirectory,
    bool? copyByDefault,
    this.probeTimeout = const Duration(seconds: 15),
  }) : _registryOverride = registry,
       _probeFn = probe ?? AttachedLibraryProbe.probe,
       _copyDirectory = copyDirectory ?? AppPaths.getAttachedLibrariesCopyPath,
       copyByDefault = copyByDefault ?? (Platform.isAndroid || Platform.isIOS);

  /// ניתן להחלפה בבדיקות.
  static AttachedLibrariesRepository instance = AttachedLibrariesRepository();

  final AttachedLibraryStore _store;
  final AttachedLibraryRegistry? _registryOverride;
  final AttachedLibraryProbeFn _probeFn;

  /// מסד שבדיקתו לא הסתיימה בזמן (כונן רשת מת) נחשב לא-זמין, כדי שהתור
  /// הסריאלי לא ייתקע מאחוריו.
  final Duration probeTimeout;

  Future<AttachedLibraryProbeResult> _probe(String path) =>
      _probeFn(path).timeout(
        probeTimeout,
        onTimeout: () => const AttachedLibraryProbeResult.failure(
          AttachedLibraryProblem.notFound,
        ),
      );
  final Future<String> Function() _copyDirectory;

  /// במובייל SQLite אינו פותח קבצים מחוץ לאחסון האפליקציה, ולכן מעתיקים.
  final bool copyByDefault;

  final _changes = StreamController<Set<String>>.broadcast();
  Future<void> _tail = Future.value();

  AttachedLibraryRegistry get _registry =>
      _registryOverride ?? AttachedLibraryRegistry.instance;

  /// משודר אחרי כל שינוי ברשימה שמשפיע על עץ הספרייה, עם ה-slug של כל מסד
  /// שהקובץ שלו השתנה (טביעת האצבע) — ספריו דורשים אינדוקס מחדש.
  Stream<Set<String>> get changes => _changes.stream;

  /// נתיבי המסדים שקריאת הקטלוג שלהם עדיין רצה. לתצוגה בכרטיס בלבד — אינו
  /// משודר ב-[changes] ואינו משנה את עץ הספרייה.
  final ValueNotifier<Set<String>> loadingPaths = ValueNotifier(const {});

  void setLoading(String path, {required bool loading}) {
    final current = loadingPaths.value;
    if (current.contains(path) == loading) return;
    loadingPaths.value = {
      for (final other in current)
        if (other != path) other,
      if (loading) path,
    };
  }

  /// האם המסד מוצג "נטען": קריאתו עדיין רצה והוא טרם סומן זמין.
  bool isLoading(AttachedLibrary library) =>
      library.status == AttachedLibraryStatus.unreachable &&
      loadingPaths.value.contains(library.path);

  List<AttachedLibrary> get libraries => _registry.libraries;
  List<String> get folders => _store.loadFolders();

  AttachedLibraryMode get defaultMode =>
      copyByDefault ? AttachedLibraryMode.copy : AttachedLibraryMode.link;

  /// פעולות רצות בזו אחר זו — סריקה ברקע וצירוף מהממשק כותבים לאותה רשימה.
  Future<T> _serial<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  /// מצרף את קובץ המסד [sourcePath]. במצב העתקה הקובץ מועתק לתיקייה
  /// שהתוכנה מנהלת; במצב קישור הוא נקרא במקומו ולעולם אינו נכתב.
  Future<AttachResult> importFile(
    String sourcePath, {
    AttachedLibraryMode? mode,
  }) => _serial(() async {
    final libraries = [..._registry.libraries];
    if (libraries.any((l) => p.equals(l.path, sourcePath))) {
      return const AttachResult.failure(AttachedLibraryProblem.alreadyAttached);
    }
    final effectiveMode = mode ?? defaultMode;
    if (effectiveMode == AttachedLibraryMode.copy) {
      return _importCopy(sourcePath, libraries);
    }

    final result = await _probe(sourcePath);
    if (!result.isOk) return AttachResult.failure(result.problem!);
    if (_slugTaken(libraries, result.slug)) {
      return const AttachResult.failure(AttachedLibraryProblem.duplicateSlug);
    }
    final library = _fromProbe(
      sourcePath,
      result,
      mode: AttachedLibraryMode.link,
      priority: _nextPriority(libraries),
    );
    await _commit([...libraries, library]);
    return AttachResult.success(library);
  });

  Future<AttachResult> _importCopy(
    String sourcePath,
    List<AttachedLibrary> libraries,
  ) async {
    final directory = await _copyDirectory();
    // שם הקובץ נשמר בעותק הזמני: ממנו נגזרים ה-slug ושם התצוגה.
    final tempDirectory = p.join(
      directory,
      '.import-${DateTime.now().microsecondsSinceEpoch}',
    );
    final temp = p.join(tempDirectory, p.basename(sourcePath));
    try {
      await Directory(tempDirectory).create(recursive: true);
      await _copyWithSideFiles(sourcePath, temp);
      // העותק שלנו: מותר להחיל עליו יומן תלוי ולהעבירו ל-DELETE.
      await Isolate.run(
        () => normalizeJournalModeForReadOnly(temp, untrusted: true),
      );
    } catch (e) {
      debugPrint('[AttachedLibraries] copy of $sourcePath failed: $e');
      await _deleteDirectory(tempDirectory);
      return const AttachResult.failure(AttachedLibraryProblem.copyFailed);
    }

    final result = await _probe(temp);
    final target = result.isOk ? p.join(directory, '${result.slug}.db') : '';
    final problem = !result.isOk
        ? result.problem!
        : _slugTaken(libraries, result.slug) ||
              libraries.any((l) => p.equals(l.path, target))
        ? AttachedLibraryProblem.duplicateSlug
        : null;
    if (problem != null) {
      await _deleteDirectory(tempDirectory);
      return AttachResult.failure(problem);
    }

    try {
      // קובץ יתום באותו שם (עותק שהוסר מהרשימה) אינו שייך לאף מסד.
      await _deleteDatabaseFiles(target);
      await File(temp).rename(target);
    } catch (e) {
      debugPrint('[AttachedLibraries] rename to $target failed: $e');
      return const AttachResult.failure(AttachedLibraryProblem.copyFailed);
    } finally {
      await _deleteDirectory(tempDirectory);
    }
    final library = _fromProbe(
      target,
      result,
      mode: AttachedLibraryMode.copy,
      priority: _nextPriority(libraries),
    );
    await _commit([...libraries, library]);
    return AttachResult.success(library);
  }

  /// מוסיף תיקיית מסדים וסורק אותה. קובצי `*.db` שבה (לא בתתי-תיקיות)
  /// מצורפים במצב קישור.
  Future<bool> addFolder(String folderPath) async {
    await _serial(() async {
      final folders = _store.loadFolders();
      if (folders.any((f) => p.equals(f, folderPath))) return;
      await _store.saveFolders([...folders, folderPath]);
    });
    return rescan();
  }

  /// מסיר תיקיית מסדים ואת כל המסדים שצורפו ממנה. הקבצים עצמם לא נמחקים.
  Future<void> removeFolder(String folderPath) => _serial(() async {
    final folders = _store.loadFolders();
    await _store.saveFolders([
      for (final folder in folders)
        if (!p.equals(folder, folderPath)) folder,
    ]);
    final libraries = _registry.libraries;
    for (final library in libraries) {
      if (_inFolder(library, folderPath)) await _registry.close(library.slug);
    }
    await _commit([
      for (final library in libraries)
        if (!_inFolder(library, folderPath)) library,
    ]);
  });

  /// מסיר מסד מהרשימה. קובץ מקושר לעולם אינו נמחק; עותק שהתוכנה מנהלת נמחק
  /// כש-[deleteCopy].
  Future<void> remove(AttachedLibrary library, {bool deleteCopy = true}) =>
      _serial(() async {
        await _registry.close(library.slug);
        if (library.mode == AttachedLibraryMode.copy && deleteCopy) {
          final directory = await _copyDirectory();
          if (p.isWithin(directory, library.path)) {
            await _deleteDatabaseFiles(library.path);
          }
        }
        await _commit([
          for (final other in _registry.libraries)
            if (!p.equals(other.path, library.path)) other,
        ]);
      });

  Future<void> setPlacement(
    AttachedLibrary library,
    AttachedLibraryPlacement placement,
  ) => _update(library, (l) => l.copyWith(placement: placement));

  Future<void> setHidden(AttachedLibrary library, bool hidden) =>
      _update(library, (l) => l.copyWith(hidden: hidden));

  /// מזיז את המסד [delta] מקומות בסדר ההצגה.
  Future<void> move(AttachedLibrary library, int delta) => _serial(() async {
    final libraries = [..._registry.libraries];
    final index = libraries.indexWhere((l) => p.equals(l.path, library.path));
    if (index < 0) return;
    final target = (index + delta).clamp(0, libraries.length - 1);
    if (target == index) return;
    libraries.insert(target, libraries.removeAt(index));
    await _commit([
      for (var i = 0; i < libraries.length; i++)
        libraries[i].copyWith(priority: i),
    ]);
  });

  /// מסמן את המסד שב-[path] לא-זמין (קריאתו נכשלה או לא הסתיימה), או זמין
  /// שוב. מסד במצב אחר (פגום, כפול) אינו משתנה.
  Future<void> setReachable(String path, {required bool reachable}) =>
      _serial(() async {
        final from = reachable
            ? AttachedLibraryStatus.unreachable
            : AttachedLibraryStatus.ok;
        final to = reachable
            ? AttachedLibraryStatus.ok
            : AttachedLibraryStatus.unreachable;
        await _commit([
          for (final library in _registry.libraries)
            p.equals(library.path, path) && library.status == from
                ? library.copyWith(status: to)
                : library,
        ]);
      });

  /// משחרר את נעילת הקובץ. הוא ייפתח שוב בגישה הבאה לספר ממנו.
  Future<void> release(AttachedLibrary library) =>
      _registry.close(library.slug);

  /// סורק את תיקיות המסדים ובודק כל מסד רשום: קובץ שנעלם מסומן "לא זמין",
  /// וקובץ שטביעת האצבע שלו השתנתה נבדק מחדש. מחזיר האם משהו השתנה.
  Future<bool> rescan() => _serial(() async {
    final libraries = [..._registry.libraries];
    final probed = <String>{};

    for (final folder in _store.loadFolders()) {
      final List<String> files;
      try {
        files = await _listDatabaseFiles(folder);
      } on FileSystemException {
        // תיקייה לא נגישה: המסדים נשארים ומסומנים לא-זמינים למטה.
        continue;
      }
      libraries.removeWhere(
        (l) => _inFolder(l, folder) && !files.any((f) => p.equals(f, l.path)),
      );
      for (final file in files) {
        if (libraries.any((l) => p.equals(l.path, file))) continue;
        final result = await _probe(file);
        probed.add(file);
        libraries.add(
          _fromProbe(
            file,
            result,
            folderPath: folder,
            mode: AttachedLibraryMode.link,
            priority: _nextPriority(libraries),
          ),
        );
      }
    }

    for (var i = 0; i < libraries.length; i++) {
      final library = libraries[i];
      if (probed.contains(library.path)) continue;
      final refreshed = await _refresh(library).timeout(
        probeTimeout,
        onTimeout: () =>
            library.copyWith(status: AttachedLibraryStatus.unreachable),
      );
      if (refreshed != library) {
        await _registry.close(library.slug);
        libraries[i] = refreshed;
      }
    }
    return _commit(libraries);
  });

  Future<AttachedLibrary> _refresh(AttachedLibrary library) async {
    final file = File(library.path);
    if (!await file.exists()) {
      return library.copyWith(status: AttachedLibraryStatus.unreachable);
    }
    final stat = await file.stat();
    final fingerprint = library.fingerprint;
    final unchanged =
        fingerprint != null &&
        !fingerprint.fileDiffers(
          size: stat.size,
          modifiedMs: stat.modified.millisecondsSinceEpoch,
        );
    if (unchanged &&
        library.status != AttachedLibraryStatus.unreachable &&
        library.status != AttachedLibraryStatus.invalid) {
      return library;
    }
    return _applyProbe(library, await _probe(library.path));
  }

  Future<void> _update(
    AttachedLibrary library,
    AttachedLibrary Function(AttachedLibrary) change,
  ) => _serial(() async {
    await _commit([
      for (final other in _registry.libraries)
        p.equals(other.path, library.path) ? change(other) : other,
    ]);
  });

  /// שומר, מעדכן את ה-registry ומשדר כשהרשימה השתנתה. מסדים עם slug זהה —
  /// הראשון בסדר תקין והשאר מסומנים כפולים; כפול שבן-זוגו הוסר חוזר לתקין.
  Future<bool> _commit(List<AttachedLibrary> libraries) async {
    final sorted = [...libraries]
      ..sort((a, b) => a.priority.compareTo(b.priority));
    final seen = <String>{};
    final resolved = [
      for (final library in sorted) _resolveDuplicate(library, seen),
    ];
    final before = _registry.libraries;
    final changed =
        before.length != resolved.length ||
        [
          for (var i = 0; i < resolved.length; i++) before[i] != resolved[i],
        ].any((differs) => differs);
    if (!changed) return false;
    final contentChanged = _contentChangedSlugs(before, resolved);
    await _store.saveLibraries(resolved);
    _registry.update(resolved);
    _changes.add(contentChanged);
    return true;
  }

  static Set<String> _contentChangedSlugs(
    List<AttachedLibrary> before,
    List<AttachedLibrary> after,
  ) => {
    for (final library in after)
      if (library.isOk && library.fingerprint != null)
        for (final old in before)
          if (p.equals(old.path, library.path) &&
              old.slug == library.slug &&
              old.fingerprint != null &&
              old.fingerprint != library.fingerprint)
            library.slug,
  };

  static AttachedLibrary _resolveDuplicate(
    AttachedLibrary library,
    Set<String> seen,
  ) {
    final candidate =
        library.status == AttachedLibraryStatus.ok ||
        library.status == AttachedLibraryStatus.duplicateSlug;
    if (!candidate) return library;
    if (!seen.add(library.slug)) {
      return library.copyWith(
        status: AttachedLibraryStatus.duplicateSlug,
        problem: AttachedLibraryProblem.duplicateSlug,
      );
    }
    return library.status == AttachedLibraryStatus.ok
        ? library
        : library.copyWith(
            status: AttachedLibraryStatus.ok,
            clearProblem: true,
          );
  }

  static bool _slugTaken(List<AttachedLibrary> libraries, String slug) =>
      libraries.any((l) => l.isOk && l.slug == slug);

  static bool _inFolder(AttachedLibrary library, String folder) =>
      library.folderPath != null && p.equals(library.folderPath!, folder);

  static int _nextPriority(List<AttachedLibrary> libraries) =>
      libraries.fold(-1, (max, l) => l.priority > max ? l.priority : max) + 1;

  static AttachedLibrary _fromProbe(
    String path,
    AttachedLibraryProbeResult result, {
    String? folderPath,
    required AttachedLibraryMode mode,
    required int priority,
  }) {
    final baseName = p.basenameWithoutExtension(path);
    final placeholder = AttachedLibrary(
      slug: AttachedLibraryProbe.slugFor(fileName: baseName),
      displayName: baseName,
      path: path,
      folderPath: folderPath,
      mode: mode,
      priority: priority,
      addedAt: DateTime.now(),
    );
    return _applyProbe(placeholder, result);
  }

  static AttachedLibrary _applyProbe(
    AttachedLibrary library,
    AttachedLibraryProbeResult result,
  ) {
    if (!result.isOk) {
      return library.copyWith(
        status: result.problem == AttachedLibraryProblem.notFound
            ? AttachedLibraryStatus.unreachable
            : AttachedLibraryStatus.invalid,
        problem: result.problem,
      );
    }
    return library.copyWith(
      slug: result.slug,
      displayName: result.displayName,
      status: AttachedLibraryStatus.ok,
      clearProblem: true,
      capabilities: result.capabilities,
      bookCount: result.bookCount,
      fingerprint: result.fingerprint,
      immutable: result.immutable,
    );
  }

  /// קובצי `*.db` שבתיקייה עצמה — לא ברקורסיה: תיקיית מסדים היא רשימה
  /// שטוחה, וסריקה עמוקה של תיקייה גדולה הייתה מאיטה כל רענון.
  static Future<List<String>> _listDatabaseFiles(String folder) async {
    final files = <String>[];
    await for (final entity in Directory(folder).list(followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (name.startsWith('.')) continue;
      if (p.extension(name).toLowerCase() != '.db') continue;
      files.add(entity.path);
    }
    files.sort();
    return files;
  }

  static Future<void> _copyWithSideFiles(String source, String target) async {
    await File(source).copy(target);
    for (final suffix in const ['-wal', '-journal']) {
      final side = File('$source$suffix');
      if (await side.exists()) await side.copy('$target$suffix');
    }
  }

  static Future<void> _deleteDirectory(String path) async {
    try {
      final directory = Directory(path);
      if (await directory.exists()) await directory.delete(recursive: true);
    } catch (e) {
      debugPrint('[AttachedLibraries] could not delete $path: $e');
    }
  }

  static Future<void> _deleteDatabaseFiles(String path) async {
    for (final suffix in const ['', '-wal', '-shm', '-journal']) {
      try {
        final file = File('$path$suffix');
        if (await file.exists()) await file.delete();
      } catch (e) {
        debugPrint('[AttachedLibraries] could not delete $path$suffix: $e');
      }
    }
  }

  @visibleForTesting
  Future<void> dispose() => _changes.close();
}
