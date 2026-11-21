import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show ValueListenable, ValueNotifier, debugPrint, visibleForTesting;
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/attached_libraries/models/attached_library.dart';
import 'package:otzaria/attached_libraries/models/attached_library_update_source.dart';
import 'package:otzaria/attached_libraries/models/attached_library_update_status.dart';
import 'package:otzaria/attached_libraries/models/attached_update_manifest.dart';
import 'package:otzaria/attached_libraries/models/official_attached_library.dart';
import 'package:otzaria/attached_libraries/repository/attached_libraries_repository.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_probe.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_store.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_artifact_builder.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_artifact_planner.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_downloader.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_fetcher.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_file_swap.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_host_policy.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_signature.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/update_check_frequency.dart';
import 'package:otzaria/empty_library/services/library_space_estimate.dart'
    show isSameVolume;
import 'package:otzaria/migration/database/journal_mode.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/utils/file/disk_free_space.dart';
import 'package:path/path.dart' as p;

class _BadSignature implements Exception {
  const _BadSignature();
}

class _NotEnoughSpace implements Exception {
  final int requiredBytes;
  const _NotEnoughSpace(this.requiredBytes);
}

class _UpdateFailure implements Exception {
  final AttachedUpdateError error;
  const _UpdateFailure(this.error);
}

/// בדיקה, הורדה והתקנה של עדכונים למסדים מצורפים.
///
/// Holds the per-database status (keyed by file path) that the settings card
/// shows. Nothing is fetched for a database without a pinned source, with a
/// changed source, in offline mode, or with software/book updates disabled.
class AttachedLibraryUpdateService {
  AttachedLibraryUpdateService({
    AttachedLibrariesRepository? repository,
    AttachedUpdateFetcher? fetcher,
    this.downloader = const AttachedUpdateDownloader(),
    this.planner = const AttachedUpdateArtifactPlanner(),
    Future<AttachedLibraryProbeResult> Function(String path)? probe,
    this.swap = const AttachedUpdateFileSwap(),
    Future<DiskSpaceInfo> Function(String path)? diskSpace,
    Future<String> Function()? workDirectory,
    bool Function()? isOfflineMode,
    bool Function()? areUpdatesEnabled,
    bool Function()? isAutoCheckDue,
    Future<void> Function()? recordCheck,
    bool? isAndroid,
    this._store = const AttachedLibraryStore(),
  }) : _repositoryOverride = repository,
       _fetcher = fetcher ?? AttachedUpdateFetcher(),
       _probe = probe ?? AttachedLibraryProbe.probe,
       _diskSpace = diskSpace ?? getDiskSpaceInfo,
       _workDirectory = workDirectory ?? _defaultWorkDirectory,
       _isOfflineMode = isOfflineMode ?? _readOfflineMode,
       _areUpdatesEnabled = areUpdatesEnabled ?? _readUpdatesEnabled,
       _isAutoCheckDue = isAutoCheckDue ?? _readAutoCheckDue,
       _recordCheck = recordCheck ?? _writeLastCheck,
       _isAndroid = isAndroid ?? Platform.isAndroid;

  static AttachedLibraryUpdateService instance = AttachedLibraryUpdateService();

  final AttachedLibrariesRepository? _repositoryOverride;
  final AttachedUpdateFetcher _fetcher;
  final AttachedUpdateDownloader downloader;
  final AttachedUpdateArtifactPlanner planner;
  final Future<AttachedLibraryProbeResult> Function(String path) _probe;
  final AttachedUpdateFileSwap swap;
  final Future<DiskSpaceInfo> Function(String path) _diskSpace;
  final Future<String> Function() _workDirectory;
  final bool Function() _isOfflineMode;
  final bool Function() _areUpdatesEnabled;
  final bool Function() _isAutoCheckDue;
  final Future<void> Function() _recordCheck;
  final bool _isAndroid;
  final AttachedLibraryStore _store;

  /// Free-space headroom kept on each volume beyond the artifact itself.
  static const spaceMargin = 32 * 1024 * 1024;

  final _statuses = ValueNotifier<Map<String, AttachedUpdateStatus>>(const {});
  final _cancelTokens = <String, AttachedUpdateCancelToken>{};
  bool _pendingRestored = false;

  AttachedLibrariesRepository get _repository =>
      _repositoryOverride ?? AttachedLibrariesRepository.instance;

  ValueListenable<Map<String, AttachedUpdateStatus>> get statuses => _statuses;

  AttachedUpdateStatus statusOf(AttachedLibrary library) =>
      _statuses.value[library.path] ?? const AttachedUpdateIdle();

  static Future<String> _defaultWorkDirectory() async =>
      p.join(await AppPaths.getAttachedLibrariesCopyPath(), '.updates');

  static bool _readOfflineMode() =>
      Settings.getValue<bool>(SettingsRepository.keyOfflineMode) ?? false;

  static bool _readUpdatesEnabled() =>
      Settings.getValue<bool>(
        SettingsRepository.keySoftwareAndBookUpdatesEnabled,
      ) ??
      true;

  /// The official library check also requires auto-sync and its cadence.
  static bool _readAutoCheckDue() =>
      (Settings.getValue<bool>(SettingsRepository.keyAutoSync) ?? true) &&
      isAutoUpdateCheckDue(
        SettingsRepository.keyLastAttachedLibraryUpdateCheck,
      );

  static Future<void> _writeLastCheck() => recordSuccessfulUpdateCheck(
    SettingsRepository.keyLastAttachedLibraryUpdateCheck,
  );

  /// מקור העדכון: של מסד רשמי — מהקטלוג שבקוד בלבד; של מסד אחר — הנעוץ.
  static AttachedLibraryUpdateSource? sourceOf(AttachedLibrary library) =>
      switch (library.official) {
        final official? => OfficialAttachedLibraries.byId(
          official.libraryId,
        )?.source,
        null => library.updateSource,
      };

  static bool isEligible(AttachedLibrary library) =>
      library.isOk &&
      sourceOf(library) != null &&
      (library.official != null || !library.updateSourceMismatch);

  /// הבדיקה האוטומטית (אחרי חשיפת החלון). Same gates as the official library
  /// check: not offline, updates enabled, auto-sync on, and due by cadence.
  /// A verified official copy is then updated without asking.
  Future<void> runScheduledCheck() async {
    if (_isOfflineMode() || !_areUpdatesEnabled() || !_isAutoCheckDue()) {
      return;
    }
    await restorePending();
    var reachedAll = true;
    for (final library in _repository.libraries.where(isEligible)) {
      final status = await check(library);
      if (status case AttachedUpdateFailed(
        error: AttachedUpdateError.network || AttachedUpdateError.hostRejected,
      )) {
        reachedAll = false;
      }
      if (library.isOfficial && status is AttachedUpdateAvailable) {
        await install(library);
      }
    }
    if (reachedAll) await _recordCheck();
  }

  /// בדיקה ידנית או אוטומטית של מסד אחד.
  Future<AttachedUpdateStatus> check(AttachedLibrary library) async {
    final current = statusOf(library);
    if (current.isRunning) return current;
    final blocked = _blockedReason(library);
    if (blocked != null) {
      return _set(library.path, AttachedUpdateFailed(blocked));
    }
    final source = sourceOf(library)!;
    _set(library.path, const AttachedUpdateChecking());
    try {
      final signed = await _fetcher.fetchSignedManifest(source.manifestUrl);
      final offer = await _verify(signed.manifest, signed.signature, source);
      final installed = int.tryParse(library.fingerprint?.dbVersion ?? '');
      if (offer.manifest.libraryId != source.libraryId || installed == null) {
        throw const _UpdateFailure(AttachedUpdateError.notApplicable);
      }
      // עותק רשמי שהשתנה מחוץ לתוכנה: מאומץ רק אם הוא בדיוק הקובץ המלא החתום.
      if (library.official case final official?
          when official.dbVersion != installed || !official.verified) {
        await _savePending(library.path, null);
        if (await adoptIfSignedMatch(library.path, offer) != null) {
          return _set(library.path, const AttachedUpdateUpToDate());
        }
        return _set(
          library.path,
          AttachedUpdateFailed(
            AttachedUpdateError.integrityMismatch,
            offer: offer,
          ),
        );
      }
      if (offer.dbVersion <= installed) {
        await _savePending(library.path, null);
        return _set(library.path, const AttachedUpdateUpToDate());
      }
      await _savePending(library.path, offer);
      return _set(
        library.path,
        AttachedUpdateAvailable(await _planned(offer, library.path, installed)),
      );
    } catch (e, st) {
      _log('check ${library.slug}', e, st);
      return _set(library.path, AttachedUpdateFailed(errorOf(e)));
    }
  }

  /// מתקין את העדכון שהמשתמש אישר, או עדכון של עותק רשמי (בלי אישור).
  /// [forceFull] — עותק רשמי שאינו תואם לגרסתו מוחלף בקובץ המלא.
  Future<void> install(
    AttachedLibrary requested, {
    bool forceFull = false,
  }) async {
    final path = requested.path;
    final offer = statusOf(requested).offer;
    if (offer == null || statusOf(requested).isRunning) return;
    final library = _repository.libraries
        .where((l) => p.equals(l.path, path))
        .firstOrNull;
    final blocked = library == null
        ? AttachedUpdateError.fileMissing
        : _blockedReason(library);
    if (blocked != null) {
      _set(path, AttachedUpdateFailed(blocked, offer: offer));
      return;
    }
    final source = sourceOf(library!)!;
    final official = library.official;
    final manifest = offer.manifest;
    final cancel = AttachedUpdateCancelToken();
    _cancelTokens[path] = cancel;
    _set(
      path,
      AttachedUpdateInProgress(offer, phase: AttachedUpdatePhase.download),
    );
    final staged = AttachedUpdateFileSwap.stagedPathFor(path);
    String? combined;
    var keepPartial = false;
    try {
      // The approved offer is re-verified against the pinned key.
      final verified = await _verify(
        offer.manifestBytes,
        offer.signature,
        source,
      );
      await _repository.recoverInterruptedUpdates(swap: swap);
      if (!await File(path).exists()) {
        throw const _UpdateFailure(AttachedUpdateError.fileMissing);
      }
      // The version on disk, not the cached fingerprint: a stale cache
      // would let an older signed manifest replace a newer file.
      final onDisk = await _probe(path);
      final installed = int.tryParse(onDisk.fingerprint?.dbVersion ?? '');
      if (installed == null) {
        throw const _UpdateFailure(AttachedUpdateError.notApplicable);
      }
      if (forceFull) {
        // מניפסט ישן מהגרסה שהותקנה אינו מוריד אותה לאחור.
        if (official == null ||
            verified.manifest.libraryId != official.libraryId ||
            verified.manifest.dbVersion < official.dbVersion) {
          throw const _UpdateFailure(AttachedUpdateError.notApplicable);
        }
        if (await adoptIfSignedMatch(path, verified) != null) {
          await _savePending(path, null);
          _set(path, AttachedUpdateInstalled(manifest.dbVersion));
          return;
        }
      } else {
        // Already installed (e.g. the file was replaced by hand): nothing to offer.
        if (installed >= verified.manifest.dbVersion) {
          await _savePending(path, null);
          _set(path, const AttachedUpdateIdle());
          return;
        }
        verified.manifest.checkApplicable(
          pinned: source,
          installedDbVersion: '$installed',
        );
        if (official != null) {
          _set(
            path,
            AttachedUpdateInProgress(
              offer,
              phase: AttachedUpdatePhase.assemble,
            ),
          );
          await _checkOfficialIntegrity(path, official, installed);
        }
      }
      await _ensureWritable(staged);
      final reporters = _reporters(path, offer);
      final plan = forceFull
          ? AttachedUpdatePlan(manifest.full)
          : await planner.plan(
              verified.manifest,
              installedPath: path,
              installedDbVersion: installed,
            );
      var installedArtifact = plan.artifact;
      combined = await _combinedPathFor(
        library.path,
        library.slug,
        manifest,
        plan,
      );
      await ensureSpace(plan.artifact, staged: staged, combined: combined);
      try {
        await downloader.download(
          plan.artifact,
          combinedPath: combined,
          outputPath: staged,
          basePath: plan.isDelta ? path : null,
          cancel: cancel,
          onProgress: reporters.onProgress,
          onExtractionProgress: reporters.onExtraction,
          onWaitingForWifi: reporters.onWaitingForWifi,
        );
      } catch (e, st) {
        // דלתא חסרה או פגומה חוזרת למלא; ניתוק ושגיאת מדיניות אינם חוזרים.
        final canFallBack = switch (e) {
          AttachedUpdateHttpException(statusCode: HttpStatus.notFound) => true,
          AttachedUpdateCancelled() => false,
          _ =>
            errorOf(e) != AttachedUpdateError.network &&
                errorOf(e) != AttachedUpdateError.hostRejected,
        };
        if (!plan.isDelta || cancel.isCancelled || !canFallBack) rethrow;
        _log('delta ${library.slug}', e, st);
        await _deleteQuietly(combined);
        final fallback = AttachedUpdatePlan(manifest.full);
        combined = await _combinedPathFor(
          library.path,
          library.slug,
          manifest,
          fallback,
        );
        await ensureSpace(manifest.full, staged: staged, combined: combined);
        await downloader.download(
          manifest.full,
          combinedPath: combined,
          outputPath: staged,
          cancel: cancel,
          onProgress: reporters.onProgress,
          onExtractionProgress: reporters.onExtraction,
          onWaitingForWifi: reporters.onWaitingForWifi,
        );
        installedArtifact = manifest.full;
      }
      if (cancel.isCancelled) throw const AttachedUpdateCancelled();
      _cancelTokens.remove(path);
      _set(
        path,
        AttachedUpdateInProgress(offer, phase: AttachedUpdatePhase.install),
      );

      await _normalizeJournal(staged);
      bool accept(AttachedLibraryProbeResult result) => official != null
          ? acceptsOfficial(
              result,
              libraryId: official.libraryId,
              dbVersion: manifest.dbVersion,
            )
          : acceptsInstalled(
              result,
              pinned: source,
              dbVersion: manifest.dbVersion,
            );
      // Rejecting here leaves the old file untouched.
      if (!accept(await _probe(staged))) {
        throw const AttachedUpdateVerificationFailed();
      }
      await _repository.installUpdate(
        library,
        staged,
        accept: accept,
        swap: swap,
        official: official == null
            ? null
            : AttachedOfficialInstall(
                libraryId: official.libraryId,
                dbVersion: manifest.dbVersion,
                sha256: installedArtifact.sha256,
              ),
      );
      await _savePending(path, null);
      _set(path, AttachedUpdateInstalled(manifest.dbVersion));
    } on AttachedUpdateCancelled {
      _settle(path, AttachedUpdateAvailable(offer));
    } catch (e, st) {
      _log('install ${library.slug}', e, st);
      final error = errorOf(e);
      keepPartial = error == AttachedUpdateError.network;
      final stillValid =
          error != AttachedUpdateError.notApplicable &&
          error != AttachedUpdateError.badSignature;
      if (!stillValid) await _savePending(path, null);
      _settle(
        path,
        AttachedUpdateFailed(
          error,
          offer: stillValid ? offer : null,
          requiredBytes: e is _NotEnoughSpace ? e.requiredBytes : null,
        ),
      );
    } finally {
      _cancelTokens.remove(path);
      await _deleteQuietly(staged);
      if (combined != null && !keepPartial) await _deleteQuietly(combined);
    }
  }

  /// Stops a running download; the offer stays available.
  void cancel(AttachedLibrary library) => _cancelTokens[library.path]?.cancel();

  /// מסד שהוסר: עוצר עדכון או הורדה רשמית לאותו נתיב ומוחק את מצבם.
  Future<void> forget(AttachedLibrary library) async {
    final path = library.path;
    _cancelTokens[path]?.cancel();
    for (final entry in OfficialAttachedLibraries.catalog) {
      if (p.equals(await _repository.officialPathFor(entry.libraryId), path)) {
        cancelOfficial(entry.libraryId);
      }
    }
    _statuses.value = {..._statuses.value}..remove(path);
    await _savePending(path, null);
  }

  /// עדכון שהסתיים אחרי שהמסד הוסר אינו משאיר מצב.
  void _settle(String path, AttachedUpdateStatus status) {
    if (_repository.libraries.any((l) => p.equals(l.path, path))) {
      _set(path, status);
    } else {
      _statuses.value = {..._statuses.value}..remove(path);
    }
  }

  /// מפתח המצב של הצעת הורדה למסד רשמי שאינו מותקן; אינו מתנגש בנתיב.
  static String officialKey(String libraryId) => 'official:$libraryId';

  AttachedUpdateStatus officialStatusOf(String libraryId) =>
      _statuses.value[officialKey(libraryId)] ?? const AttachedUpdateIdle();

  /// מסדים רשמיים פעילים שאין להם עותק רשמי מותקן.
  static List<OfficialAttachedLibrary> notInstalledOfficial(
    List<AttachedLibrary> libraries,
  ) => [
    for (final entry in OfficialAttachedLibraries.catalog)
      if (entry.isActive &&
          !libraries.any((l) => l.official?.libraryId == entry.libraryId))
        entry,
  ];

  /// מביא את המניפסט החתום של כל מסד רשמי שאינו מותקן ולא נדחה, כדי להציג
  /// את גודלו. רץ רק כשכרטיס ההגדרות נפתח.
  Future<void> checkOfficialOffers() async {
    final declined = _store.loadDeclinedOfficial();
    for (final entry in notInstalledOfficial(_repository.libraries)) {
      if (declined.contains(entry.libraryId)) continue;
      final key = officialKey(entry.libraryId);
      final current = officialStatusOf(entry.libraryId);
      if (current.isRunning || current is AttachedUpdateAvailable) continue;
      final blocked = _networkBlockedReason();
      if (blocked != null) {
        _set(key, AttachedUpdateFailed(blocked));
        continue;
      }
      _set(key, const AttachedUpdateChecking());
      try {
        final source = entry.source!;
        final signed = await _fetcher.fetchSignedManifest(source.manifestUrl);
        final offer = await _verify(signed.manifest, signed.signature, source);
        if (offer.manifest.libraryId != entry.libraryId) {
          throw const _UpdateFailure(AttachedUpdateError.notApplicable);
        }
        _set(key, AttachedUpdateAvailable(offer));
      } catch (e, st) {
        _log('official offer ${entry.libraryId}', e, st);
        _set(key, AttachedUpdateFailed(errorOf(e)));
      }
    }
  }

  /// מוריד את המסד הרשמי ומתקין אותו כעותק מנוהל, אחרי אימות החתימה
  /// במפתח שבקוד וה-sha256 שבמניפסט.
  Future<void> installOfficial(OfficialAttachedLibrary entry) async {
    final key = officialKey(entry.libraryId);
    final status = officialStatusOf(entry.libraryId);
    final offer = status.offer;
    final source = entry.source;
    if (offer == null || status.isRunning || source == null) return;
    final blocked = _networkBlockedReason();
    if (blocked != null) {
      _set(key, AttachedUpdateFailed(blocked, offer: offer));
      return;
    }
    final cancel = AttachedUpdateCancelToken();
    _cancelTokens[key] = cancel;
    _set(
      key,
      AttachedUpdateInProgress(offer, phase: AttachedUpdatePhase.download),
    );
    String? staged;
    String? combined;
    var keepPartial = false;
    try {
      final manifest = (await _verify(
        offer.manifestBytes,
        offer.signature,
        source,
      )).manifest;
      if (manifest.libraryId != entry.libraryId) {
        throw const _UpdateFailure(AttachedUpdateError.notApplicable);
      }
      final target = await _repository.officialPathFor(entry.libraryId);
      if (await File(target).exists() &&
          await adoptIfSignedMatch(target, offer) != null) {
        await _store.setOfficialDeclined(entry.libraryId, declined: false);
        _set(key, AttachedUpdateInstalled(manifest.dbVersion));
        return;
      }
      await Directory(p.dirname(target)).create(recursive: true);
      staged = AttachedUpdateFileSwap.stagedPathFor(target);
      await _ensureWritable(staged);
      final plan = AttachedUpdatePlan(manifest.full);
      combined = await _combinedPathFor(
        target,
        entry.libraryId,
        manifest,
        plan,
      );
      await ensureSpace(manifest.full, staged: staged, combined: combined);
      final reporters = _reporters(key, offer);
      await downloader.download(
        manifest.full,
        combinedPath: combined,
        outputPath: staged,
        cancel: cancel,
        onProgress: reporters.onProgress,
        onExtractionProgress: reporters.onExtraction,
        onWaitingForWifi: reporters.onWaitingForWifi,
      );
      if (cancel.isCancelled) throw const AttachedUpdateCancelled();
      _cancelTokens.remove(key);
      _set(
        key,
        AttachedUpdateInProgress(offer, phase: AttachedUpdatePhase.install),
      );
      await _normalizeJournal(staged);
      bool accept(AttachedLibraryProbeResult result) => acceptsOfficial(
        result,
        libraryId: entry.libraryId,
        dbVersion: manifest.dbVersion,
      );
      if (!accept(await _probe(staged))) {
        throw const AttachedUpdateVerificationFailed();
      }
      await _repository.installOfficial(
        staged,
        official: AttachedOfficialInstall(
          libraryId: entry.libraryId,
          dbVersion: manifest.dbVersion,
          sha256: manifest.full.sha256,
        ),
        accept: accept,
      );
      await _store.setOfficialDeclined(entry.libraryId, declined: false);
      _set(key, AttachedUpdateInstalled(manifest.dbVersion));
    } on AttachedUpdateCancelled {
      _set(key, AttachedUpdateAvailable(offer));
    } catch (e, st) {
      _log('install official ${entry.libraryId}', e, st);
      final error = errorOf(e);
      keepPartial = error == AttachedUpdateError.network;
      final stillValid =
          error != AttachedUpdateError.notApplicable &&
          error != AttachedUpdateError.badSignature;
      _set(
        key,
        AttachedUpdateFailed(
          error,
          offer: stillValid ? offer : null,
          requiredBytes: e is _NotEnoughSpace ? e.requiredBytes : null,
        ),
      );
    } finally {
      _cancelTokens.remove(key);
      if (staged != null) await _deleteQuietly(staged);
      if (combined != null && !keepPartial) await _deleteQuietly(combined);
    }
  }

  /// מאמץ את הקובץ שב-[path] כעותק רשמי בגרסת [offer] בלי להוריד אותו: רק
  /// כשהמניפסט חתום במפתח שבקוד למזהה שלו, הקובץ מצהיר על אותו מזהה ואותה
  /// גרסה, וה-sha256 שלו (מחושב ב-isolate) שווה ל-`full.sha256`.
  Future<AttachedLibrary?> adoptIfSignedMatch(
    String path,
    AttachedUpdateOffer offer,
  ) async {
    final source = OfficialAttachedLibraries.byId(
      offer.manifest.libraryId,
    )?.source;
    if (source == null) return null;
    try {
      final manifest = (await _verify(
        offer.manifestBytes,
        offer.signature,
        source,
      )).manifest;
      if (manifest.libraryId != source.libraryId) return null;
      bool accept(AttachedLibraryProbeResult result) => acceptsOfficial(
        result,
        libraryId: manifest.libraryId,
        dbVersion: manifest.dbVersion,
      );
      final before = await _probe(path);
      if (!accept(before) ||
          await planner.installedSha256(path) != manifest.full.sha256) {
        return null;
      }
      return await _repository.adoptOfficial(
        path,
        official: AttachedOfficialInstall(
          libraryId: manifest.libraryId,
          dbVersion: manifest.dbVersion,
          sha256: manifest.full.sha256,
        ),
        // קובץ שהשתנה אחרי החישוב אינו מאומץ.
        accept: (result) =>
            accept(result) && result.fingerprint == before.fingerprint,
      );
    } catch (e, st) {
      _log('adopt $path', e, st);
      return null;
    }
  }

  void cancelOfficial(String libraryId) =>
      _cancelTokens[officialKey(libraryId)]?.cancel();

  Set<String> declinedOfficial() => _store.loadDeclinedOfficial();

  /// סירוב או הסרה: ההצעה אינה מוצגת עוד מעצמה, ונשארת זמינה בהגדרות.
  Future<void> setOfficialDeclined(
    String libraryId, {
    required bool declined,
  }) async {
    await _store.setOfficialDeclined(libraryId, declined: declined);
    if (declined && !officialStatusOf(libraryId).isRunning) {
      _set(officialKey(libraryId), const AttachedUpdateIdle());
    }
  }

  AttachedUpdateError? _networkBlockedReason() {
    if (_isOfflineMode()) return AttachedUpdateError.offline;
    if (!_areUpdatesEnabled()) return AttachedUpdateError.updatesDisabled;
    return null;
  }

  /// עותק רשמי: אותו `library_id` ובדיוק גרסת המניפסט. המפתח שבקובץ אינו
  /// נבדק — האמון בא מהחתימה וה-sha256 שכבר אומתו.
  static bool acceptsOfficial(
    AttachedLibraryProbeResult result, {
    required String libraryId,
    required int dbVersion,
  }) =>
      result.isOk &&
      result.slug == libraryId &&
      int.tryParse(result.fingerprint?.dbVersion ?? '') == dbVersion;

  /// The new file must be the same library, signed by the same key, at
  /// exactly the version of the manifest the user approved.
  static bool acceptsInstalled(
    AttachedLibraryProbeResult result, {
    required AttachedLibraryUpdateSource pinned,
    required int dbVersion,
  }) {
    final declared = result.updateSource;
    return result.isOk &&
        declared != null &&
        declared.libraryId == pinned.libraryId &&
        declared.publicKey == pinned.publicKey &&
        int.tryParse(result.fingerprint?.dbVersion ?? '') == dbVersion;
  }

  /// Shows offers found in an earlier session, after re-verifying each with
  /// the pinned key and the installed version.
  Future<void> restorePending() async {
    if (_pendingRestored) return;
    _pendingRestored = true;
    final stored = _loadPending();
    for (final library in _repository.libraries) {
      final json = stored[library.path];
      if (json is! Map || !isEligible(library)) continue;
      if (statusOf(library) is! AttachedUpdateIdle) continue;
      try {
        final source = sourceOf(library)!;
        final offer = await _verify(
          base64.decode(json['manifest'] as String),
          base64.decode(json['signature'] as String),
          source,
        );
        final installedDbVersion = library.fingerprint?.dbVersion;
        offer.manifest.checkApplicable(
          pinned: source,
          installedDbVersion: installedDbVersion,
        );
        final installed = int.parse(installedDbVersion!.trim());
        _set(
          library.path,
          AttachedUpdateAvailable(
            await _planned(offer, library.path, installed),
          ),
        );
      } catch (e) {
        await _savePending(library.path, null);
      }
    }
  }

  AttachedUpdateError? _blockedReason(AttachedLibrary library) {
    if (sourceOf(library) == null) return AttachedUpdateError.noSource;
    if (library.official == null && library.updateSourceMismatch) {
      return AttachedUpdateError.sourceMismatch;
    }
    if (!library.isOk) return AttachedUpdateError.fileMissing;
    return _networkBlockedReason();
  }

  // Static: an isolate closure must not capture the service's context.
  static Future<void> _normalizeJournal(String path) =>
      Isolate.run(() => normalizeJournalModeForReadOnly(path, untrusted: true));

  /// Signature first, with the pinned key only; unsigned bytes are never
  /// parsed. Runs off the UI isolate (ed25519 over up to 1 MB).
  static Future<AttachedUpdateOffer> _verify(
    Uint8List manifestBytes,
    Uint8List signature,
    AttachedLibraryUpdateSource source,
  ) async {
    final manifest = await Isolate.run(() {
      if (!AttachedUpdateSignature.verify(
        message: manifestBytes,
        signatureText: signature,
        publicKey: source.publicKey,
      )) {
        throw const _BadSignature();
      }
      return AttachedUpdateManifest.parse(manifestBytes);
    });
    return AttachedUpdateOffer(
      manifest: manifest,
      manifestBytes: manifestBytes,
      signature: signature,
      domain: source.host,
    );
  }

  /// הדיאלוג מציג את גודל ההורדה של הארטיפקט שייבחר, לא של הקובץ המלא.
  Future<AttachedUpdateOffer> _planned(
    AttachedUpdateOffer offer,
    String installedPath,
    int installedDbVersion,
  ) async {
    final plan = await planner.plan(
      offer.manifest,
      installedPath: installedPath,
      installedDbVersion: installedDbVersion,
    );
    return offer.withPlannedDownloadSize(plan.artifact.compressedSize);
  }

  Future<String> _combinedPathFor(
    String targetPath,
    String slug,
    AttachedUpdateManifest manifest,
    AttachedUpdatePlan plan,
  ) async {
    if (plan.artifact.compression == AttachedUpdateCompression.none) {
      return AttachedUpdateFileSwap.localDownloadPathFor(targetPath);
    }
    final directory = await _workDirectory();
    await Directory(directory).create(recursive: true);
    // שם נפרד לכל מקור דלתא: הורדה חלקית של תיקון אינה קלט תקף לאחר.
    final suffix = plan.delta == null
        ? ''
        : '-from${plan.delta!.fromDbVersion}';
    return p.join(
      directory,
      '$slug-${manifest.dbVersion}$suffix.download',
    );
  }

  ({
    AttachedUpdateProgress onProgress,
    AttachedUpdateProgress onExtraction,
    void Function() onWaitingForWifi,
  })
  _reporters(String key, AttachedUpdateOffer offer) => (
    onProgress: (received, total) => _set(
      key,
      AttachedUpdateInProgress(
        offer,
        phase: total == 0
            ? AttachedUpdatePhase.assemble
            : AttachedUpdatePhase.download,
        received: received,
        total: total,
      ),
    ),
    onExtraction: (written, total) => _set(
      key,
      AttachedUpdateInProgress(
        offer,
        phase: AttachedUpdatePhase.assemble,
        received: written,
        total: total,
      ),
    ),
    onWaitingForWifi: () => _set(
      key,
      AttachedUpdateInProgress(
        offer,
        phase: AttachedUpdatePhase.waitingForWifi,
      ),
    ),
  );

  /// עדכון (גם דלתא) מוחל רק על הקובץ שהותקן בפועל: גרסה ו-sha256 כפי שנרשמו.
  Future<void> _checkOfficialIntegrity(
    String path,
    AttachedOfficialInstall official,
    int installedDbVersion,
  ) async {
    if (installedDbVersion != official.dbVersion ||
        await planner.installedSha256(path) != official.sha256) {
      throw const _UpdateFailure(AttachedUpdateError.integrityMismatch);
    }
  }

  /// A read-only folder or a missing drive fails here, before any download.
  static Future<void> _ensureWritable(String staged) async {
    final file = File(staged);
    await file.writeAsBytes(const [], flush: true);
    await file.delete();
  }

  @visibleForTesting
  Future<void> ensureSpace(
    AttachedUpdateArtifact artifact, {
    required String staged,
    required String combined,
  }) async {
    final partial = await File(combined).exists()
        ? await File(combined).length()
        : 0;
    final download = (artifact.compressedSize - partial).clamp(
      0,
      artifact.compressedSize,
    );
    final uncompressed = artifact.compression == AttachedUpdateCompression.none;
    final targetInfo = await _diskSpace(p.dirname(staged));
    final workInfo = await _diskSpace(p.dirname(combined));
    final sameVolume =
        uncompressed ||
        isSameVolume(
          p.dirname(staged),
          targetInfo,
          p.dirname(combined),
          workInfo,
          isAndroid: _isAndroid,
        );
    final needs = <(DiskSpaceInfo, int)>[
      if (sameVolume)
        (targetInfo, (uncompressed ? download : artifact.size + download))
      else ...[
        (targetInfo, artifact.size),
        (workInfo, download),
      ],
    ];
    for (final (info, bytes) in needs) {
      final required = bytes + spaceMargin;
      if (info.freeBytes >= 0 && info.freeBytes < required) {
        throw _NotEnoughSpace(required);
      }
    }
  }

  /// Maps any failure to what the card can say about it.
  static AttachedUpdateError errorOf(Object e) => switch (e) {
    _UpdateFailure(:final error) => error,
    _NotEnoughSpace() => AttachedUpdateError.noSpace,
    _BadSignature() => AttachedUpdateError.badSignature,
    AttachedUpdateHostRejected() => AttachedUpdateError.hostRejected,
    AttachedUpdateNetworkException() => AttachedUpdateError.network,
    AttachedUpdatePartMismatch() ||
    AttachedUpdateArtifactMismatch() => AttachedUpdateError.downloadCorrupt,
    AttachedUpdateManifestException() => AttachedUpdateError.badManifest,
    AttachedUpdateVerificationFailed() => AttachedUpdateError.verifyFailed,
    AttachedUpdateFileLocked() => AttachedUpdateError.fileLocked,
    FileSystemException(:final osError) => _fileError(osError?.errorCode),
    _ => AttachedUpdateError.unknown,
  };

  // Win32 and errno numbers overlap (21 is ERROR_NOT_READY but EISDIR), so
  // each table applies only on its own platform.
  static AttachedUpdateError _fileError(int? code) => Platform.isWindows
      ? switch (code) {
          // ERROR_DISK_FULL, ERROR_HANDLE_DISK_FULL
          112 || 39 => AttachedUpdateError.noSpace,
          // ERROR_FILE/PATH_NOT_FOUND, ERROR_NOT_READY (drive removed)
          2 || 3 || 21 => AttachedUpdateError.fileMissing,
          // ERROR_ACCESS_DENIED, ERROR_WRITE_PROTECT
          5 || 19 => AttachedUpdateError.readOnly,
          32 || 33 => AttachedUpdateError.fileLocked,
          _ => AttachedUpdateError.unknown,
        }
      : switch (code) {
          28 => AttachedUpdateError.noSpace, // ENOSPC
          2 => AttachedUpdateError.fileMissing, // ENOENT
          1 || 13 || 30 => AttachedUpdateError.readOnly, // EPERM, EACCES, EROFS
          _ => AttachedUpdateError.unknown,
        };

  AttachedUpdateStatus _set(String path, AttachedUpdateStatus status) {
    _statuses.value = {..._statuses.value, path: status};
    return status;
  }

  static Map<String, Object?> _loadPending() {
    final raw = Settings.getValue<String>(
      SettingsRepository.keyAttachedLibraryPendingUpdates,
    );
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, Object?>.from(decoded) : {};
    } on FormatException {
      return {};
    }
  }

  static Future<void> _savePending(
    String path,
    AttachedUpdateOffer? offer,
  ) async {
    final pending = _loadPending();
    if (offer == null) {
      if (!pending.containsKey(path)) return;
      pending.remove(path);
    } else {
      pending[path] = offer.toJson();
    }
    await Settings.setValue<String>(
      SettingsRepository.keyAttachedLibraryPendingUpdates,
      jsonEncode(pending),
    );
  }

  static Future<void> _deleteQuietly(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('[AttachedUpdates] could not delete $path: $e');
    }
  }

  static void _log(String what, Object error, StackTrace stackTrace) {
    if (error is AttachedUpdateCancelled) return;
    debugPrint('[AttachedUpdates] $what failed: $error');
  }
}
