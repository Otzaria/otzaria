import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'managed_paths.dart';
import 'swap_plan.dart';
import 'tree_fs.dart';
import 'update_package.dart';
import 'zstd_runner.dart';

/// מה ייעשה עם ערך אחד של החבילה.
enum UpdateFileAction {
  /// הקובץ המקומי כבר בתוכן החדש — לא יורד, לא נפרס, לא מוחלף.
  alreadyUpToDate,

  /// הקובץ המקומי זהה-בית לבסיס ה-patch — ה-patch יוחל עליו.
  applyPatch,

  /// ייכתב הקובץ המלא הדחוס. אינו תלוי כלל בתוכן המקומי.
  writeFull,

  /// ה-patch אינו ישים כאן — הקובץ יושלם מחבילת הקבצים המלאים.
  fromFallbackPackage,
}

/// מביא את חבילת הקבצים המלאים. נקרא **רק** כשערך אחד לפחות נכשל, כדי
/// שעדכון שכל ה-patch שלו הוחל לא יוריד אותה כלל.
typedef FallbackPackageResolver = Future<File> Function();

/// החלטה לערך אחד.
class UpdateStep {
  UpdateStep(this.entry, this.action);

  final UpdatePackageEntry entry;
  final UpdateFileAction action;
}

/// תכנית העדכון: מה לעשות בכל ערך, ואילו קבצים להסיר.
class UpdatePlan {
  UpdatePlan({
    required this.manifest,
    required this.steps,
    required this.removals,
  });

  final UpdatePackageManifest manifest;
  final List<UpdateStep> steps;
  final List<ManagedRemoval> removals;

  Iterable<UpdateStep> get work =>
      steps.where((step) => step.action != UpdateFileAction.alreadyUpToDate);
}

/// עדכון שנבנה במלואו ב-staging ואומת מול המניפסט. ההתקנה החיה עדיין
/// לא נגעה — ההחלפה היא תפקידו של המעדכן העצמאי.
class StagedUpdate {
  StagedUpdate({
    required this.manifest,
    required this.installRoot,
    required this.stagingRoot,
    required this.backupRoot,
    required this.workRoot,
    required this.files,
    required this.removals,
    this.isTree = false,
  });

  /// עדכון עץ: [stagingRoot] הוא עותק מלא ומאומת של ההתקנה החדשה, לצד
  /// ההתקנה, וההחלפה היא שינוי שם של תיקייה.
  final bool isTree;

  final UpdatePackageManifest manifest;
  final Directory installRoot;
  final Directory stagingRoot;
  final Directory backupRoot;
  final Directory workRoot;
  final List<SwapFile> files;
  final List<SwapRemoval> removals;

  /// כותב את תוכנית ההחלפה שהמעדכן העצמאי מקבל כארגומנט.
  Future<File> writeSwapPlan({
    String? relaunchExecutable,
    int? waitForPid,
    Duration waitTimeout = const Duration(minutes: 2),
  }) async {
    final plan = SwapPlan(
      platform: manifest.platform,
      architecture: manifest.architecture,
      fromReleaseTag: manifest.fromReleaseTag,
      toReleaseTag: manifest.toReleaseTag,
      installRoot: installRoot.absolute.path,
      stagingRoot: stagingRoot.absolute.path,
      backupRoot: backupRoot.absolute.path,
      files: files,
      removals: removals,
      relaunchExecutable: relaunchExecutable,
      waitForPid: waitForPid,
      waitTimeout: waitTimeout,
    );
    return writeSwapPlanFile(plan, workRoot);
  }

  /// מוחק את כל תוצרי ההכנה. בטוח לקרוא גם אחרי החלפה מוצלחת.
  Future<void> discard() async {
    if (await workRoot.exists()) await workRoot.delete(recursive: true);
    if (isTree && await stagingRoot.exists()) {
      await stagingRoot.delete(recursive: true);
    }
  }
}

/// כותב את תוכנית ההחלפה לשורש תיקיית העבודה, שם המעדכן והשחזור בעלייה
/// מחפשים אותה.
Future<File> writeSwapPlanFile(SwapPlan plan, Directory workRoot) async {
  final file = File(p.join(workRoot.path, kSwapPlanFileName));
  await file.parent.create(recursive: true);
  // סימן מוויתור קודם היה מחזיר את הממשק ל"מוכן" מיד עם השיגור החדש.
  final gaveUp = File(p.join(workRoot.path, kSwapGaveUpFileName));
  if (await gaveUp.exists()) await gaveUp.delete();
  await file.writeAsString(plan.encode());
  return file;
}

/// תוכנית החלפה מחבילה מלאה שחולצה ל-[stagingRoot]: כל קובץ שהשתנה נכתב
/// על ההתקנה חוץ מנתוני משתמש, ושום קובץ אינו נמחק.
Future<SwapPlan> fullPackageSwapPlan({
  required Directory installRoot,
  required Directory stagingRoot,
  required Directory backupRoot,
  required String platform,
  required String architecture,
  required String fromReleaseTag,
  required String toReleaseTag,
  String? relaunchExecutable,
  int? waitForPid,
}) async {
  final install = installRoot.path;
  final staging = stagingRoot.path;
  // מאות מגה-בתים: הגיבוב מחוץ ל-isolate הראשי כדי שהממשק לא ייתקע.
  final files = await Isolate.run(() => _changedFiles(install, staging));
  return SwapPlan(
    platform: platform,
    architecture: architecture,
    fromReleaseTag: fromReleaseTag,
    toReleaseTag: toReleaseTag,
    installRoot: installRoot.absolute.path,
    stagingRoot: stagingRoot.absolute.path,
    backupRoot: backupRoot.absolute.path,
    files: files,
    removals: const [],
    relaunchExecutable: relaunchExecutable,
    waitForPid: waitForPid,
  );
}

Future<List<SwapFile>> _changedFiles(
  String installRoot,
  String stagingRoot,
) async {
  final listing = await const LocalTreeFileSystem().list(stagingRoot);
  final files = <SwapFile>[];
  for (final path in listing.files.keys.toList()..sort()) {
    if (isUserDataPath(path)) continue;
    final file = File(p.join(stagingRoot, path));
    final size = await file.length();
    final hash = await sha256OfFile(file);
    // קובץ זהה נשאר בחוץ: crashpad_handler.exe עלול עוד לרוץ ולחסום את ההחלפה.
    final installed = File(p.join(installRoot, path));
    if (await installed.exists() &&
        await installed.length() == size &&
        await sha256OfFile(installed) == hash) {
      continue;
    }
    files.add(SwapFile(path: path, sha256: hash, size: size));
  }
  return files;
}

/// מחשב את sha256 של קובץ בזרימה, בלי להחזיק אותו בזיכרון.
Future<String> sha256OfFile(File file) async {
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString();
}

/// בונה מחבילה את קבוצת הקבצים החדשה בתיקיית עבודה נפרדת — לעולם לא
/// בהתקנה החיה. כל כשל הוא [DifferentialUpdateUnavailable].
class DifferentialUpdateEngine {
  DifferentialUpdateEngine({
    required this.installRoot,
    required this.workRoot,
    required this.platform,
    required this.architecture,
    required this.installedReleaseTag,
    this.zstd = const ZstdRunner.bundled(),
    this.preparedRoot,
    this.treeFs = const LocalTreeFileSystem(),
    this.allowUnmanagedFiles = false,
  });

  /// לחבילת עץ בלבד: היעד של עותק ההתקנה. חייב לשבת באותו כרך כמו
  /// ההתקנה, כדי שההחלפה תהיה שינוי שם ולא העתקה.
  final Directory? preparedRoot;

  final TreeFileSystem treeFs;

  /// האם קובץ שאינו בעץ החדש נסבל בעותק. ב-bundle של macOS הוא שובר את
  /// החותם, ולכן שם הוא כשל.
  final bool allowUnmanagedFiles;

  final Directory installRoot;

  /// תיקיית העבודה (staging + backup). חייבת להיות מחוץ להתקנה.
  final Directory workRoot;

  final String platform;
  final String architecture;
  final String installedReleaseTag;
  final ZstdRunner zstd;

  Directory get stagingRoot =>
      preparedRoot ?? Directory(p.join(workRoot.path, kSwapStagingDirName));
  Directory get backupRoot =>
      Directory(p.join(workRoot.path, kSwapBackupDirName));

  /// המסלול המלא. [fallbackPackage] מביא את חבילת הקבצים המלאים, ונקרא
  /// רק אם ערך כלשהו בחבילת ה-patch לא ניתן להחלה.
  Future<StagedUpdate> prepare(
    File packageFile, {
    FallbackPackageResolver? fallbackPackage,
  }) async {
    final package = await UpdatePackage.open(packageFile);
    return stage(
      package,
      await planFor(package),
      fallbackPackage: fallbackPackage,
    );
  }

  /// בודק התאמת יעד וגרסת בסיס, ומסווג כל ערך לפי הקובץ המקומי.
  Future<UpdatePlan> planFor(UpdatePackage package) async {
    final manifest = package.manifest;
    if (manifest.platform != platform ||
        manifest.architecture != architecture) {
      throw DifferentialUpdateUnavailable(
        UpdateAbortReason.targetMismatch,
        'the package targets ${manifest.platform}/${manifest.architecture} '
        'but the install is $platform/$architecture',
      );
    }
    if (manifest.fromReleaseTag != installedReleaseTag) {
      throw DifferentialUpdateUnavailable(
        UpdateAbortReason.baseVersionMismatch,
        'the package upgrades from ${manifest.fromReleaseTag} '
        'but the install is $installedReleaseTag',
      );
    }
    if (!await installRoot.exists()) {
      throw DifferentialUpdateUnavailable(
        UpdateAbortReason.environment,
        'the install directory does not exist: ${installRoot.path}',
      );
    }
    _requireSeparateWorkRoot();

    final steps = <UpdateStep>[];
    for (final entry in manifest.entries) {
      final local = File(p.join(installRoot.path, entry.path));
      final localHash = await local.exists() ? await sha256OfFile(local) : null;

      if (localHash == entry.newSha256) {
        steps.add(UpdateStep(entry, UpdateFileAction.alreadyUpToDate));
        continue;
      }
      if (!entry.isPatch) {
        steps.add(UpdateStep(entry, UpdateFileAction.writeFull));
        continue;
      }
      if (localHash == entry.oldSha256) {
        steps.add(UpdateStep(entry, UpdateFileAction.applyPatch));
        continue;
      }
      // ה-patch הוא אופטימיזציה: קובץ מקומי שאינו הבסיס שלו אינו מפיל את
      // העדכון אלא מושלם מחבילת הקבצים המלאים.
      steps.add(UpdateStep(entry, UpdateFileAction.fromFallbackPackage));
    }
    return UpdatePlan(
      manifest: manifest,
      steps: steps,
      removals: manifest.removals,
    );
  }

  /// בונה ומאמת כל קובץ ב-staging. ערך שאי אפשר להחיל נדחה לחבילת
  /// הקבצים המלאים, שנטענת רק אם נדרשה בפועל.
  Future<StagedUpdate> stage(
    UpdatePackage package,
    UpdatePlan plan, {
    FallbackPackageResolver? fallbackPackage,
  }) async {
    _requireSeparateWorkRoot();
    if (!await zstd.isAvailable) {
      throw DifferentialUpdateUnavailable(
        UpdateAbortReason.environment,
        'zstd is not available, so the package cannot be unpacked',
      );
    }
    final tree = plan.manifest.isTree;
    if (tree) _requireSeparatePreparedRoot();

    final staging = stagingRoot;
    if (await staging.exists()) await staging.delete(recursive: true);
    if (tree) {
      await _copyInstallTree(staging);
    } else {
      await staging.create(recursive: true);
    }
    final scratch = Directory(p.join(workRoot.path, 'scratch'));
    if (await scratch.exists()) await scratch.delete(recursive: true);
    await scratch.create(recursive: true);

    final payloadFile = File(p.join(scratch.path, 'payload.bin'));
    final files = <SwapFile>[];
    final deferred = <UpdatePackageEntry>[];
    try {
      if (tree) await _removeFromTree(staging, plan.manifest);
      for (final step in plan.work) {
        final entry = step.entry;
        if (step.action == UpdateFileAction.fromFallbackPackage) {
          deferred.add(entry);
          continue;
        }
        try {
          await _writeEntry(
            package: package,
            entry: entry,
            action: step.action,
            payloadFile: payloadFile,
            staging: staging,
          );
        } on DifferentialUpdateUnavailable catch (error) {
          if (!_isRecoverableEntryFailure(error.reason)) rethrow;
          // חצי קובץ ב-staging היה עובר את סריקת הסיום כאילו נכתב.
          final partial = File(p.join(staging.path, entry.path));
          if (await partial.exists()) await partial.delete();
          deferred.add(entry);
          continue;
        }
        files.add(
          SwapFile(
            path: entry.path,
            sha256: entry.newSha256,
            size: entry.newSize,
          ),
        );
      }

      if (deferred.isNotEmpty) {
        files.addAll(
          await _completeFromFallback(
            deferred: deferred,
            manifest: plan.manifest,
            fallbackPackage: fallbackPackage,
            payloadFile: payloadFile,
            staging: staging,
          ),
        );
      }

      if (tree) {
        await _completeAndVerifyTree(staging, plan.manifest);
      } else {
        await _verifyStaging(staging, files);
      }
    } catch (_) {
      if (await staging.exists()) await staging.delete(recursive: true);
      rethrow;
    } finally {
      if (await scratch.exists()) await scratch.delete(recursive: true);
    }

    return StagedUpdate(
      manifest: plan.manifest,
      installRoot: installRoot,
      stagingRoot: staging,
      backupRoot: backupRoot,
      workRoot: workRoot,
      files: files,
      removals: [
        for (final removal in plan.removals)
          SwapRemoval(path: removal.path, sha256: removal.oldSha256),
      ],
      isTree: tree,
    );
  }

  Future<void> _copyInstallTree(Directory staging) async {
    try {
      await staging.parent.create(recursive: true);
      await treeFs.copyTree(installRoot.path, staging.path);
    } on FileSystemException catch (error) {
      throw DifferentialUpdateUnavailable(
        UpdateAbortReason.environment,
        'the install could not be copied for the update: $error',
      );
    }
  }

  Future<void> _removeFromTree(
    Directory staging,
    UpdatePackageManifest manifest,
  ) => _treeStep(
    () => removeFromTree(
      fs: treeFs,
      root: staging.path,
      linkRemovals: manifest.linkRemovals,
      fileRemovals: [for (final removal in manifest.removals) removal.path],
    ),
  );

  /// symlinks, הרשאות, ואז השוואת העותק כולו לעץ החדש — קובץ נוסף, חסר או
  /// שונה אחד מספיק כדי לחזור למסלול המלא.
  Future<void> _completeAndVerifyTree(
    Directory staging,
    UpdatePackageManifest manifest,
  ) async {
    final newTree = manifest.newTree!;
    await _treeStep(
      () => completeTree(
        fs: treeFs,
        root: staging.path,
        links: manifest.links,
        newTree: newTree,
      ),
    );
    final errors = await verifyTree(
      fs: treeFs,
      root: staging.path,
      newTree: newTree,
      allowUnmanaged: allowUnmanagedFiles,
    );
    if (errors.isNotEmpty) {
      throw DifferentialUpdateUnavailable(
        UpdateAbortReason.stagingVerificationFailed,
        'the prepared install does not match the new release: '
        '${errors.take(5).join('; ')}',
      );
    }
  }

  Future<void> _treeStep(Future<void> Function() step) async {
    try {
      await step();
    } on TreeUpdateException catch (error) {
      throw DifferentialUpdateUnavailable(
        UpdateAbortReason.localFileUnusable,
        error.message,
      );
    } on FileSystemException catch (error) {
      throw DifferentialUpdateUnavailable(
        UpdateAbortReason.environment,
        '$error',
      );
    }
  }

  void _requireSeparatePreparedRoot() {
    final prepared = preparedRoot;
    if (prepared == null) {
      throw DifferentialUpdateUnavailable(
        UpdateAbortReason.environment,
        'a tree package needs a directory to prepare the new install in',
      );
    }
    final install = p.canonicalize(installRoot.absolute.path);
    final target = p.canonicalize(prepared.absolute.path);
    if (p.equals(install, target) ||
        p.isWithin(install, target) ||
        p.isWithin(target, install)) {
      throw DifferentialUpdateUnavailable(
        UpdateAbortReason.environment,
        'the prepared directory must be beside the install, not inside it',
      );
    }
  }

  /// כותב ערך אחד ל-staging ומאמת אותו מיד מול המניפסט. האימות המיידי הוא
  /// מה שמאפשר לדחות דווקא את הערך שנכשל לחבילת הקבצים המלאים.
  Future<void> _writeEntry({
    required UpdatePackage package,
    required UpdatePackageEntry entry,
    required UpdateFileAction action,
    required File payloadFile,
    required Directory staging,
  }) async {
    await payloadFile.writeAsBytes(package.payloadOf(entry), flush: true);
    final target = File(p.join(staging.path, entry.path));
    await target.parent.create(recursive: true);

    if (action == UpdateFileAction.applyPatch) {
      await zstd.applyPatch(
        base: File(p.join(installRoot.path, entry.path)),
        patch: payloadFile,
        output: target,
      );
    } else {
      await zstd.decompress(input: payloadFile, output: target);
    }
    await _verifyStagedFile(
      target,
      path: entry.path,
      sha256: entry.newSha256,
      size: entry.newSize,
    );
  }

  /// כשל בערך בודד שראוי להשלמה מחבילת הקבצים המלאים. כשל סביבה
  /// (zstd חסר, דיסק מלא) אינו כזה — הורדה נוספת רק תיכשל גם היא.
  bool _isRecoverableEntryFailure(UpdateAbortReason reason) =>
      reason == UpdateAbortReason.packageCorrupt ||
      reason == UpdateAbortReason.localFileUnusable ||
      reason == UpdateAbortReason.stagingVerificationFailed;

  /// משלים את הערכים שנדחו מתוך חבילת הקבצים המלאים. כשל כאן הוא סוף
  /// המסלול הדיפרנציאלי — אין נסיגה שנייה.
  Future<List<SwapFile>> _completeFromFallback({
    required List<UpdatePackageEntry> deferred,
    required UpdatePackageManifest manifest,
    required FallbackPackageResolver? fallbackPackage,
    required File payloadFile,
    required Directory staging,
  }) async {
    if (fallbackPackage == null) {
      throw DifferentialUpdateUnavailable(
        UpdateAbortReason.fallbackUnavailable,
        '${deferred.length} file(s) need the full-files package, which was '
        'not offered',
      );
    }
    final File file;
    try {
      file = await fallbackPackage();
    } catch (error) {
      throw DifferentialUpdateUnavailable(
        UpdateAbortReason.fallbackUnavailable,
        'the full-files package could not be fetched: $error',
      );
    }

    final fallback = await UpdatePackage.open(file);
    final fallbackManifest = fallback.manifest;
    if (fallbackManifest.kind != UpdatePackageKind.full ||
        fallbackManifest.platform != manifest.platform ||
        fallbackManifest.architecture != manifest.architecture ||
        fallbackManifest.fromReleaseTag != manifest.fromReleaseTag ||
        fallbackManifest.toReleaseTag != manifest.toReleaseTag) {
      throw DifferentialUpdateUnavailable(
        UpdateAbortReason.fallbackUnavailable,
        'the full-files package does not match the patch package',
      );
    }

    final byPath = {
      for (final entry in fallbackManifest.entries) entry.path: entry,
    };
    final files = <SwapFile>[];
    for (final wanted in deferred) {
      final entry = byPath[wanted.path];
      if (entry == null || entry.newSha256 != wanted.newSha256) {
        throw DifferentialUpdateUnavailable(
          UpdateAbortReason.fallbackUnavailable,
          '${wanted.path}: the full-files package has no matching copy',
        );
      }
      await _writeEntry(
        package: fallback,
        entry: entry,
        action: UpdateFileAction.writeFull,
        payloadFile: payloadFile,
        staging: staging,
      );
      files.add(
        SwapFile(
          path: entry.path,
          sha256: entry.newSha256,
          size: entry.newSize,
        ),
      );
    }
    return files;
  }

  Future<void> _verifyStagedFile(
    File staged, {
    required String path,
    required String sha256,
    required int size,
  }) async {
    if (!await staged.exists()) {
      throw DifferentialUpdateUnavailable(
        UpdateAbortReason.stagingVerificationFailed,
        '$path: the staged file is missing',
      );
    }
    if (await staged.length() != size || await sha256OfFile(staged) != sha256) {
      throw DifferentialUpdateUnavailable(
        UpdateAbortReason.stagingVerificationFailed,
        '$path: the staged file does not match the manifest',
      );
    }
  }

  /// סריקה סופית: כל קובץ ב-staging קיים, בגודל ובתוכן שהמניפסט מתאר.
  Future<void> _verifyStaging(Directory staging, List<SwapFile> files) async {
    for (final file in files) {
      await _verifyStagedFile(
        File(p.join(staging.path, file.path)),
        path: file.path,
        sha256: file.sha256,
        size: file.size,
      );
    }
  }

  /// תיקיית העבודה בתוך ההתקנה הייתה הופכת את גיבוי ההחלפה לחלק ממה
  /// שמוחלף. שתי התיקיות חייבות להיות נפרדות לחלוטין.
  void _requireSeparateWorkRoot() {
    final install = p.canonicalize(installRoot.absolute.path);
    final work = p.canonicalize(workRoot.absolute.path);
    if (p.equals(install, work) ||
        p.isWithin(install, work) ||
        p.isWithin(work, install)) {
      throw DifferentialUpdateUnavailable(
        UpdateAbortReason.environment,
        'the work directory must be outside the install directory',
      );
    }
  }
}
