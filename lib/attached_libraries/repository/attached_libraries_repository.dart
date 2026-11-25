import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:otzaria/models/links.dart';
import 'package:otzaria/text_book/repository/book_notes_repository.dart';
import 'package:otzaria/divine_names/repository/divine_names_repository.dart';
import 'package:flutter/foundation.dart'
    show ValueNotifier, debugPrint, visibleForTesting;
import 'package:otzaria/attached_libraries/models/attached_library.dart';
import 'package:otzaria/attached_libraries/models/official_attached_library.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_probe.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_registry.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_store.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_file_swap.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/migration/database/journal_mode.dart';
import 'package:otzaria/utils/file/native_sha256.dart';
import 'package:path/path.dart' as p;

typedef AttachedLibraryProbeFn =
    Future<AttachedLibraryProbeResult> Function(String path);

/// The new database did not pass the post-install checks.
class AttachedUpdateVerificationFailed implements Exception {
  const AttachedUpdateVerificationFailed();
}

/// בקשת התקנה לגרסה ישנה מהעותק הקיים.
class AttachedOfficialOlderVersion implements Exception {
  const AttachedOfficialOlderVersion();
}

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
  Future<void> release(AttachedLibrary library) async {
    await _registry.close(library.slug);
    await _registry.syncEngineSources();
  }

  /// מתקין קובץ מסד מעודכן במקום הקובץ של [library] (עדכון במקום, גם בקישור).
  ///
  /// Releases the open handles, swaps [stagedPath] in with a backup, probes the
  /// new file and keeps it only if [accept] approves; otherwise the backup is
  /// restored and the error rethrown. Serialized with rescans.
  Future<AttachedLibrary> installUpdate(
    AttachedLibrary library,
    String stagedPath, {
    required bool Function(AttachedLibraryProbeResult result) accept,
    AttachedUpdateFileSwap swap = const AttachedUpdateFileSwap(),
    AttachedOfficialInstall? official,
  }) => _serial(() async {
    final current = _registry.libraries
        .where((l) => p.equals(l.path, library.path))
        .firstOrNull;
    if (current == null) {
      throw FileSystemException('library is no longer attached', library.path);
    }
    return _replaceAndCommit(
      target: current.path,
      stagedPath: stagedPath,
      slug: current.slug,
      previousAtTarget: current,
      accept: accept,
      official: official,
      swap: swap,
      commit: (result) async {
        final updated = _applyProbe(
          current.copyWith(clearUpdateSource: true, official: official),
          result,
        );
        await _commit(
          [
            for (final other in _registry.libraries)
              p.equals(other.path, current.path) ? updated : other,
          ],
          alsoChanged: {current.slug},
        );
        return updated;
      },
    );
  });

  /// מיקום העותק המנוהל של מסד רשמי — בתיקייה נפרדת, כדי שעותק ידני של קובץ
  /// עם אותו `library_id` לא יתנגש בו.
  Future<String> officialPathFor(String libraryId) async =>
      p.join(await _copyDirectory(), 'official', '$libraryId.db');

  /// מתקין עותק מנוהל מאומת, תוך שמירת העותק הקיים עד לסיום ההתקנה.
  /// [replacing] הוא העותק המקושר שאת העדפותיו מעבירים בלי לכתוב לקובץ שלו.
  Future<AttachedLibrary> installOfficial(
    String stagedPath, {
    required AttachedOfficialInstall official,
    required bool Function(AttachedLibraryProbeResult result) accept,
    AttachedLibrary? replacing,
    AttachedUpdateFileSwap swap = const AttachedUpdateFileSwap(),
  }) => _serial(() async {
    final libraries = [..._registry.libraries];
    final target = await officialPathFor(official.libraryId);
    final previous = replacing == null
        ? null
        : libraries.where((l) => p.equals(l.path, replacing.path)).firstOrNull;
    if (replacing != null && previous == null) {
      throw FileSystemException(
        'library is no longer attached',
        replacing.path,
      );
    }
    if (libraries.any(
      (l) =>
          l.official?.libraryId == official.libraryId &&
          !p.equals(l.path, target) &&
          !identical(l, previous),
    )) {
      throw FileSystemException('already installed', official.libraryId);
    }
    final stale = libraries.where((l) => p.equals(l.path, target)).firstOrNull;
    final preferred = previous ?? stale;
    return _replaceAndCommit(
      target: target,
      stagedPath: stagedPath,
      slug: stale?.slug ?? official.libraryId,
      previousAtTarget: stale,
      accept: accept,
      official: official,
      swap: swap,
      commit: (result) async {
        var library = _fromProbe(
          target,
          result,
          mode: AttachedLibraryMode.copy,
          priority: preferred?.priority ?? _nextPriority(libraries),
          official: official,
        );
        if (preferred != null) {
          library = library.copyWith(
            placement: preferred.placement,
            hidden: preferred.hidden,
          );
        }
        await _commit(
          [
            for (final other in libraries)
              if (!p.equals(other.path, target))
                identical(other, previous)
                    ? other.copyWith(clearOfficial: true)
                    : other,
            library,
          ],
          alsoChanged: {if (preferred != null) library.slug},
        );
        return library;
      },
    );
  });

  Future<AttachedLibrary> _replaceAndCommit({
    required String target,
    required String stagedPath,
    required String slug,
    required AttachedLibrary? previousAtTarget,
    required bool Function(AttachedLibraryProbeResult result) accept,
    required AttachedOfficialInstall? official,
    required AttachedUpdateFileSwap swap,
    required Future<AttachedLibrary> Function(AttachedLibraryProbeResult)
    commit,
  }) async {
    await _registry.close(slug);
    var installed = false;
    final bool hadFile;
    final AttachedLibrary updated;
    try {
      if (!await _discardCommittedOfficialBackup(previousAtTarget, swap)) {
        await swap.restore(target);
      }
      final file = File(target);
      hadFile = await file.exists();
      if (hadFile) {
        if (official != null) {
          final onDisk = await _probe(target);
          final version = int.tryParse(onDisk.fingerprint?.dbVersion ?? '');
          if (onDisk.slug == official.libraryId &&
              version != null &&
              version > official.dbVersion) {
            throw const AttachedOfficialOlderVersion();
          }
        }
        await swap.swapIn(target, stagedPath);
      } else if (official != null && !hasPendingJournalSync(target)) {
        await File(stagedPath).rename(target);
      } else {
        throw FileSystemException('previous database is missing', target);
      }
      installed = true;
      final result = await _probe(target);
      if (!result.isOk || !accept(result)) {
        throw const AttachedUpdateVerificationFailed();
      }
      updated = await commit(result);
    } catch (_) {
      if (installed) {
        await _registry.close(slug);
        if (await File(AttachedUpdateFileSwap.backupPathFor(target)).exists()) {
          await swap.restore(target);
        } else {
          await _deleteDatabaseFiles(target);
        }
      }
      rethrow;
    } finally {
      await _registry.syncEngineSources();
    }
    if (hadFile) {
      try {
        await swap.discardBackup(target);
      } on FileSystemException catch (e) {
        debugPrint(
          '[AttachedLibraries] could not discard backup for $target: $e',
        );
      }
    }
    return updated;
  }

  Future<bool> _discardCommittedOfficialBackup(
    AttachedLibrary? library,
    AttachedUpdateFileSwap swap,
  ) async {
    if (library == null || !library.isOfficial) return false;
    final path = library.path;
    if (!await File(AttachedUpdateFileSwap.backupPathFor(path)).exists() ||
        !await File(path).exists()) {
      return false;
    }
    final String sha256;
    try {
      sha256 = await Isolate.run(() => sha256OfFileFast(path));
    } on FileSystemException {
      return false;
    }
    if (sha256 != library.official!.sha256) return false;
    // הרשומה כבר נשמרה. שחזור כאן היה מחזיר מסד ישן במקום הקובץ המאומת.
    await swap.discardBackup(path);
    return true;
  }

  /// מסמן את הקובץ שב-[path] כעותק רשמי מאומת, בלי להחליף אותו ובלי לכתוב
  /// אליו. [accept] בודק את הקובץ במקומו; קובץ בלי רשומה מצורף רק בנתיב הרשמי.
  Future<AttachedLibrary?> adoptOfficial(
    String path, {
    required AttachedOfficialInstall official,
    required bool Function(AttachedLibraryProbeResult result) accept,
  }) => _serial(() async {
    final libraries = [..._registry.libraries];
    // עותק מאומת אחר כבר קיים; עותק רשמי שאינו מאומת אינו חוסם.
    if (libraries.any(
      (l) =>
          l.isOfficial &&
          l.official!.libraryId == official.libraryId &&
          !p.equals(l.path, path),
    )) {
      return null;
    }
    final result = await _probe(path);
    if (!result.isOk || !accept(result)) return null;
    final index = libraries.indexWhere((l) => p.equals(l.path, path));
    final AttachedLibrary adopted;
    if (index >= 0) {
      adopted = _applyProbe(
        libraries[index].copyWith(clearUpdateSource: true, official: official),
        result,
      );
      libraries[index] = adopted;
    } else if (p.equals(path, await officialPathFor(official.libraryId))) {
      adopted = _fromProbe(
        path,
        result,
        mode: AttachedLibraryMode.copy,
        priority: _nextPriority(libraries),
        official: official,
      );
      libraries.add(adopted);
    } else {
      return null;
    }
    await _commit(libraries);
    return adopted;
  });

  /// Restores databases left mid-swap by a crash. Runs before [rescan] at
  /// startup so the fingerprints are taken from the restored files.
  Future<void> recoverInterruptedUpdates({
    AttachedUpdateFileSwap swap = const AttachedUpdateFileSwap(),
  }) => _serial(() async {
    for (final library in _registry.libraries) {
      try {
        await _discardCommittedOfficialBackup(library, swap);
        if (await swap.recover(library.path)) {
          await _registry.close(library.slug);
        }
      } catch (e) {
        debugPrint('[AttachedLibraries] recovery of ${library.path}: $e');
      }
    }
  });

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
        library.updateSourceProbed &&
        library.rootFolderProbed &&
        library.status != AttachedLibraryStatus.unreachable &&
        library.status != AttachedLibraryStatus.invalid) {
      return library;
    }
    final refreshed = _applyProbe(library, await _probe(library.path));
    // קובץ רשמי שהשתנה שלא דרך ההתקנה אינו מאומת עוד.
    final official = refreshed.official;
    if (!unchanged && official != null) {
      return refreshed.copyWith(official: official.unverified);
    }
    return refreshed;
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
  /// אחד תקין ([_slugRank], ואז הראשון בסדר) והשאר מסומנים כפולים; כפול
  /// שבן-זוגו הוסר חוזר לתקין. [alsoChanged] — slugs שהקובץ שלהם הוחלף בנתיב אחר.
  Future<bool> _commit(
    List<AttachedLibrary> libraries, {
    Set<String> alsoChanged = const {},
  }) async {
    final sorted = [...libraries]
      ..sort((a, b) => a.priority.compareTo(b.priority));
    final winners = <String, AttachedLibrary>{};
    for (final library in sorted.where(_isSlugCandidate)) {
      final current = winners[library.slug];
      if (current == null || _slugRank(library) > _slugRank(current)) {
        winners[library.slug] = library;
      }
    }
    final resolved = [
      for (final library in sorted)
        if (!_isSlugCandidate(library))
          library
        else if (identical(winners[library.slug], library))
          _asResolved(library)
        else
          library.copyWith(
            status: AttachedLibraryStatus.duplicateSlug,
            problem: AttachedLibraryProblem.duplicateSlug,
          ),
    ];
    final before = _registry.libraries;
    final changed =
        alsoChanged.isNotEmpty ||
        before.length != resolved.length ||
        [
          for (var i = 0; i < resolved.length; i++) before[i] != resolved[i],
        ].any((differs) => differs);
    if (!changed) {
      // מסד שנסגר לפני פעולת קובץ חוזר למנוע גם כשהרשימה לא השתנתה.
      await _registry.syncEngineSources();
      return false;
    }
    final contentChanged = {
      ..._contentChangedSlugs(before, resolved),
      ...alsoChanged,
    };
    await _store.saveLibraries(resolved);
    _registry.update(resolved);
    _clearStoredLineCaches();
    _changes.add(contentChanged);
    return true;
  }

  static void _clearStoredLineCaches() {
    Link.clearContentCache();
    BookNotesRepository.instance.clear();
    DivineNamesRepository.instance.clear();
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

  static bool _isSlugCandidate(AttachedLibrary library) =>
      library.status == AttachedLibraryStatus.ok ||
      library.status == AttachedLibraryStatus.duplicateSlug;

  /// בין עותקים של אותו מסד: רשמי מאומת, אחר כך רשמי שאינו מאומת, ובכל
  /// אחד מהם העותק המנוהל קודם. שאר המסדים — לפי הסדר בלבד.
  static int _slugRank(AttachedLibrary library) => switch (library.official) {
    null => 0,
    final official =>
      (official.verified ? 4 : 2) +
          (library.mode == AttachedLibraryMode.copy ? 1 : 0),
  };

  static AttachedLibrary _asResolved(AttachedLibrary library) =>
      library.status == AttachedLibraryStatus.duplicateSlug
      ? library.copyWith(status: AttachedLibraryStatus.ok, clearProblem: true)
      : library;

  /// מזהה של מסד רשמי אינו נדחה: העותק מצורף, ואחד העותקים מסומן כפול.
  static bool _slugTaken(List<AttachedLibrary> libraries, String slug) =>
      OfficialAttachedLibraries.byId(slug) == null &&
      libraries.any((l) => l.slug == slug && (l.isOk || l.official != null));

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
    AttachedOfficialInstall? official,
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
      official: official,
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
    final official = library.official?.libraryId == result.slug
        ? library.official
        : null;
    if (official != null) {
      // מקור העדכון של מסד רשמי בא מהקוד בלבד, לא מהקובץ.
      final entry = OfficialAttachedLibraries.byId(official.libraryId);
      final source = entry?.source;
      return _withProbe(library, result).copyWith(
        displayName: entry?.displayName,
        updateSource: source,
        clearUpdateSource: source == null,
        updateSourceMismatch: false,
      );
    }
    final declared = result.updateSource;
    // נעיצה (TOFU): לאותו slug הנעוץ נשמר, וסטייה רק מסומנת. slug אחר הוא
    // מסד אחר, ונעוץ מחדש כמו בצירוף.
    final pinned = library.slug == result.slug ? library.updateSource : null;
    return _withProbe(library, result).copyWith(
      updateSource: pinned ?? declared,
      clearUpdateSource: pinned == null && declared == null,
      updateSourceMismatch: pinned != null && pinned != declared,
    );
  }

  static AttachedLibrary _withProbe(
    AttachedLibrary library,
    AttachedLibraryProbeResult result,
  ) {
    final keepsOfficial = library.official?.libraryId == result.slug;
    return library.copyWith(
      clearOfficial: !keepsOfficial,
      slug: result.slug,
      displayName: result.displayName,
      rootFolder: result.rootFolder,
      clearRootFolder: result.rootFolder == null,
      updateSourceProbed: true,
      rootFolderProbed: true,
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
