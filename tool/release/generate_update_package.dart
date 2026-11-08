// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:otzaria/update/differential/managed_paths.dart'
    show managedApplicationPathError;
import 'package:otzaria/update/differential/tree_fs.dart';

import 'generate_app_file_manifest.dart';

/// גרסת הסכמה של חבילת Windows. לקוח Windows קיים דוחה כל גרסה אחרת, ולכן
/// חבילות Windows נשארות בה.
const int kUpdatePackageSchemaVersion = 1;

/// גרסת הסכמה של חבילת עץ (macOS, Linux): `links`, `linkRemovals` ו-`newTree`
/// — העץ החדש המלא, שמולו הלקוח מאמת את העותק כולו.
const int kUpdatePackageTreeSchemaVersion = 2;

/// patch נבחר רק אם הוא קטן מ-90% מהקובץ המלא הדחוס.
///
/// נמדד על המעבר 0.9.97+769 → 0.9.97+789: היחס הגרוע ביותר היה 55%
/// (`data/app.so`), ולעומתו 27% (`search_engine.dll`) ו-1.3% (`sqlite3.dll`).
/// הסף אינו פוסל אף patch שנמדד, ופוסל רק patch שאינו מחזיר את מחירו בצד
/// הלקוח — תלות בקובץ ישן זהה-בית, טעינתו כמילון, ואימות hash שני.
const double kPatchBenefitThreshold = 0.90;

/// מספר השחרורים הקודמים שמולם נבנות חבילות. מעבר לזה — המתקין המלא.
const int kUpdateBaseReleaseCount = 2;

/// שם קובץ ה-entry של המניפסט בתוך החבילה.
const String kUpdateManifestEntryName = 'update-manifest.json';

final RegExp _unsafeTagCharacters = RegExp(r'[^A-Za-z0-9._-]');
final RegExp _entryNamePattern = RegExp(r'^files/[0-9]{4}\.bin$');
final RegExp _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');

/// שגיאה בבניית או בהחלת חבילת עדכון.
class UpdatePackageException implements Exception {
  UpdatePackageException(this.message);
  final String message;
  @override
  String toString() => 'UpdatePackageException: $message';
}

/// עטיפה ל-CLI של zstd. הכלי כבר בשימוש בפרויקט ואינו תלות חדשה.
class Zstd {
  const Zstd({this.executable = 'zstd', this.level = 19});

  final String executable;
  final int level;

  /// `--long=31` (חלון 2GB) חובה: בלעדיו patch על קובץ של 30MB מפספס
  /// הזזות גדולות, וגם הפענוח בצד הלקוח מסרב לפרוס חלון כזה.
  static const String longWindow = '--long=31';

  bool get isAvailable {
    try {
      final result = Process.runSync(executable, const ['--version']);
      return result.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  void compress(File input, File output) {
    _run([
      '-q',
      '-$level',
      '--force',
      '-o',
      output.path,
      input.path,
    ], 'compress ${input.path}');
  }

  void createPatch(File oldFile, File newFile, File output) {
    _run([
      '-q',
      '-$level',
      longWindow,
      '--patch-from=${oldFile.path}',
      '--force',
      '-o',
      output.path,
      newFile.path,
    ], 'patch ${newFile.path}');
  }

  void decompress(File input, File output) {
    _run([
      '-q',
      '-d',
      '--force',
      '-o',
      output.path,
      input.path,
    ], 'decompress ${input.path}');
  }

  void applyPatch(File oldFile, File patch, File output) {
    _run([
      '-q',
      '-d',
      longWindow,
      '--patch-from=${oldFile.path}',
      '--force',
      '-o',
      output.path,
      patch.path,
    ], 'apply patch ${patch.path}');
  }

  void _run(List<String> args, String what) {
    final result = Process.runSync(executable, args);
    if (result.exitCode != 0) {
      throw UpdatePackageException(
        'zstd failed to $what (exit ${result.exitCode}): ${result.stderr}',
      );
    }
  }
}

/// תוצאת בניית חבילה — לדיווח ב-CI ולבדיקות.
class UpdatePackageResult {
  UpdatePackageResult({
    required this.assetName,
    required this.manifest,
    required this.packageSize,
    required this.patchedFiles,
    required this.fullFiles,
    required this.removedFiles,
    required this.unchangedFiles,
    required this.patchBytesSaved,
  });

  final String assetName;
  final Map<String, Object?> manifest;
  final int packageSize;
  final int patchedFiles;
  final int fullFiles;
  final int removedFiles;
  final int unchangedFiles;

  /// כמה בתים חסך מסלול ה-patch לעומת דחיסה מלאה של אותם קבצים.
  final int patchBytesSaved;
}

/// שתי החבילות שמתפרסמות לכל מעבר גרסה.
///
/// ה-patch הוא אופטימיזציה בלבד: ערך שאי אפשר להחיל אצל המשתמש מושלם
/// מחבילת [UpdatePackageVariant.full], שאינה תלויה כלל בתוכן המקומי.
enum UpdatePackageVariant {
  patch,
  full;

  String get id => name;
}

/// שם נכס החבילה. הארכיטקטורה בשם כדי שחבילת x64 לא תגיע להתקנת ARM64.
String updatePackageAssetName({
  required String platform,
  required String architecture,
  required String fromReleaseTag,
  required String toReleaseTag,
  UpdatePackageVariant variant = UpdatePackageVariant.patch,
}) =>
    'otzaria-update-$platform-$architecture-'
    '${sanitizeReleaseTag(fromReleaseTag)}-to-'
    '${sanitizeReleaseTag(toReleaseTag)}'
    '${variant == UpdatePackageVariant.full ? '-files' : ''}.zip';

/// תג שחרור כשם קובץ בטוח (`0.9.97+789` → `0.9.97_789`).
String sanitizeReleaseTag(String tag) =>
    tag.trim().replaceAll(_unsafeTagCharacters, '_');

/// בוחר patch רק כשהוא חוסך מעל הסף. שוויון נופל לטובת הקובץ המלא, שאינו
/// תלוי בכלל בתוכן הישן.
bool shouldUsePatch({
  required int patchSize,
  required int fullSize,
  double threshold = kPatchBenefitThreshold,
}) => patchSize < fullSize * threshold;

/// בונה חבילת עדכון מ-[oldRoot] ל-[newRoot] לפי המניפסטים של שתי הגרסאות.
///
/// המניפסטים הם המקור היחיד לרשימת הקבצים המנוהלים: קובץ שאינו בהם אינו
/// נקרא, אינו נארז ולעולם אינו נמחק. כך מידע של המשתמש שיושב באותו עץ
/// אינו יכול להיכנס לחבילה.
UpdatePackageResult buildUpdatePackage({
  required Map<String, Object?> oldManifest,
  required Directory oldRoot,
  required Map<String, Object?> newManifest,
  required Directory newRoot,
  required File output,
  double threshold = kPatchBenefitThreshold,
  Zstd zstd = const Zstd(),
  Directory? workDirectory,
  UpdatePackageVariant variant = UpdatePackageVariant.patch,
}) {
  for (final manifest in [oldManifest, newManifest]) {
    final errors = validateAppFileManifest(manifest);
    if (errors.isNotEmpty) {
      throw UpdatePackageException(
        'invalid app file manifest:\n - ${errors.join('\n - ')}',
      );
    }
  }
  final platform = newManifest['platform'] as String;
  final architecture = newManifest['architecture'] as String;
  requireAppFileManifestTarget(
    oldManifest,
    platform: platform,
    architecture: architecture,
  );
  if (oldManifest['releaseTag'] == newManifest['releaseTag']) {
    throw UpdatePackageException(
      'the two manifests carry the same releaseTag '
      '(${newManifest['releaseTag']})',
    );
  }
  final tree = isTreeManifestPlatform(platform);
  if (!zstd.isAvailable) {
    throw UpdatePackageException('zstd is not available on PATH');
  }

  final work =
      workDirectory ?? Directory.systemTemp.createTempSync('otzaria-update');
  final ownsWork = workDirectory == null;
  try {
    final oldFiles = appFileManifestIndex(oldManifest);
    final newFiles = appFileManifestIndex(newManifest);

    final entries = <Map<String, Object?>>[];
    final archive = Archive();
    final patchFile = File('${work.path}/entry.patch');
    final fullFile = File('${work.path}/entry.full');

    var patched = 0;
    var full = 0;
    var unchanged = 0;
    var saved = 0;
    var index = 0;

    for (final path in newFiles.keys.toList()..sort()) {
      final newEntry = newFiles[path]!;
      final oldEntry = oldFiles[path];
      if (oldEntry != null && oldEntry['sha256'] == newEntry['sha256']) {
        unchanged++;
        continue;
      }

      final newSource = _managedFile(newRoot, path, newEntry, 'new');
      zstd.compress(newSource, fullFile);
      var payload = fullFile.readAsBytesSync();
      var method = 'full';
      Map<String, Object?>? base;

      if (oldEntry != null && variant == UpdatePackageVariant.patch) {
        final oldSource = _managedFile(oldRoot, path, oldEntry, 'old');
        zstd.createPatch(oldSource, newSource, patchFile);
        final patchBytes = patchFile.readAsBytesSync();
        if (shouldUsePatch(
          patchSize: patchBytes.length,
          fullSize: payload.length,
          threshold: threshold,
        )) {
          saved += payload.length - patchBytes.length;
          payload = patchBytes;
          method = 'patch';
          base = oldEntry;
        }
      }

      method == 'patch' ? patched++ : full++;
      final entryName = 'files/${index.toString().padLeft(4, '0')}.bin';
      index++;
      archive.addFile(
        ArchiveFile.noCompress(entryName, payload.length, payload),
      );
      entries.add({
        'path': path,
        'method': method,
        'compression': method == 'patch' ? 'zstd-patch-from' : 'zstd',
        'entry': entryName,
        'entrySize': payload.length,
        'entrySha256': sha256.convert(payload).toString(),
        if (base != null) 'oldSize': base['size'],
        if (base != null) 'oldSha256': base['sha256'],
        'newSize': newEntry['size'],
        'newSha256': newEntry['sha256'],
      });
    }

    final removals = <Map<String, Object?>>[];
    for (final path in oldFiles.keys.toList()..sort()) {
      if (newFiles.containsKey(path)) continue;
      final oldEntry = oldFiles[path]!;
      removals.add({
        'path': path,
        'oldSize': oldEntry['size'],
        'oldSha256': oldEntry['sha256'],
      });
    }

    final oldLinks = appFileManifestLinks(oldManifest);
    final newLinks = appFileManifestLinks(newManifest);
    final links = <Map<String, Object?>>[
      for (final path in newLinks.keys.toList()..sort())
        if (oldLinks[path] != newLinks[path])
          {'path': path, 'target': newLinks[path]},
    ];
    final linkRemovals = <Map<String, Object?>>[
      for (final path in oldLinks.keys.toList()..sort())
        if (!newLinks.containsKey(path))
          {'path': path, 'oldTarget': oldLinks[path]},
    ];

    var downloadSize = 0;
    for (final entry in entries) {
      downloadSize += entry['entrySize'] as int;
    }

    final assetName = updatePackageAssetName(
      platform: platform,
      architecture: architecture,
      fromReleaseTag: oldManifest['releaseTag'] as String,
      toReleaseTag: newManifest['releaseTag'] as String,
      variant: variant,
    );
    // חבילת ה-patch נושאת את שם החבילה שמשלימה ערך שנכשל אצל המשתמש,
    // כדי שהלקוח לא יצטרך להרכיב את השם בעצמו.
    final fallbackAssetName = variant == UpdatePackageVariant.patch
        ? updatePackageAssetName(
            platform: platform,
            architecture: architecture,
            fromReleaseTag: oldManifest['releaseTag'] as String,
            toReleaseTag: newManifest['releaseTag'] as String,
            variant: UpdatePackageVariant.full,
          )
        : null;

    final manifest = <String, Object?>{
      'schemaVersion': tree
          ? kUpdatePackageTreeSchemaVersion
          : kUpdatePackageSchemaVersion,
      'assetName': assetName,
      'variant': variant.id,
      'fallbackAssetName': ?fallbackAssetName,
      'platform': platform,
      'architecture': architecture,
      'fromReleaseTag': oldManifest['releaseTag'],
      'fromReleaseVersion': oldManifest['releaseVersion'],
      'toReleaseTag': newManifest['releaseTag'],
      'toReleaseVersion': newManifest['releaseVersion'],
      'patchBenefitThreshold': threshold,
      'payloadSize': downloadSize,
      'entries': entries,
      'removals': removals,
      if (tree) 'links': links,
      if (tree) 'linkRemovals': linkRemovals,
      if (tree)
        'newTree': {
          'files': [
            for (final file in (newManifest['files'] as List).cast<Map>())
              {
                'path': file['path'],
                'size': file['size'],
                'sha256': file['sha256'],
                'mode': file['mode'],
              },
          ],
          'links': [
            for (final path in newLinks.keys.toList()..sort())
              {'path': path, 'target': newLinks[path]},
          ],
        },
    };

    final errors = validateUpdatePackageManifest(manifest);
    if (errors.isNotEmpty) {
      throw UpdatePackageException(
        'generated update manifest is invalid:\n - ${errors.join('\n - ')}',
      );
    }
    for (final removal in removals) {
      if (!oldFiles.containsKey(removal['path'])) {
        throw UpdatePackageException(
          'removal ${removal['path']} is not a managed application file',
        );
      }
    }

    archive.addFile(
      ArchiveFile.string(
        kUpdateManifestEntryName,
        '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
      ),
    );
    output.parent.createSync(recursive: true);
    output.writeAsBytesSync(ZipEncoder().encodeBytes(archive));

    return UpdatePackageResult(
      assetName: assetName,
      manifest: manifest,
      packageSize: output.lengthSync(),
      patchedFiles: patched,
      fullFiles: full,
      removedFiles: removals.length,
      unchangedFiles: unchanged,
      patchBytesSaved: saved,
    );
  } finally {
    if (ownsWork && work.existsSync()) work.deleteSync(recursive: true);
  }
}

/// מאמת את מניפסט החבילה ומחזיר רשימת שגיאות (ריקה = תקין).
List<String> validateUpdatePackageManifest(Object? manifest) {
  final errors = <String>[];
  if (manifest is! Map) return ['update manifest is not a JSON object'];
  final schema = manifest['schemaVersion'];
  final tree = schema == kUpdatePackageTreeSchemaVersion;
  if (schema != kUpdatePackageSchemaVersion && !tree) {
    errors.add(
      'schemaVersion must be $kUpdatePackageSchemaVersion or '
      '$kUpdatePackageTreeSchemaVersion',
    );
  }
  final platform = manifest['platform'];
  if (platform is String && tree != isTreeManifestPlatform(platform)) {
    errors.add('schemaVersion does not match the platform $platform');
  }
  for (final key in const [
    'assetName',
    'platform',
    'architecture',
    'fromReleaseTag',
    'fromReleaseVersion',
    'toReleaseTag',
    'toReleaseVersion',
  ]) {
    final value = manifest[key];
    if (value is! String || value.trim().isEmpty) {
      errors.add('$key must be a non-empty string');
    }
  }
  if (manifest['fromReleaseTag'] == manifest['toReleaseTag']) {
    errors.add('fromReleaseTag and toReleaseTag must differ');
  }
  final threshold = manifest['patchBenefitThreshold'];
  if (threshold is! num || threshold <= 0 || threshold > 1) {
    errors.add('patchBenefitThreshold must be in (0, 1]');
  }

  final variant = manifest['variant'];
  final isFullVariant = variant == UpdatePackageVariant.full.id;
  if (variant != UpdatePackageVariant.patch.id && !isFullVariant) {
    errors.add('variant must be patch or full');
  }
  final fallbackAssetName = manifest['fallbackAssetName'];
  if (isFullVariant && fallbackAssetName != null) {
    errors.add('a full package has no fallback of its own');
  }
  if (fallbackAssetName != null &&
      (fallbackAssetName is! String || !fallbackAssetName.endsWith('.zip'))) {
    errors.add('fallbackAssetName must be a .zip asset name');
  }

  final entries = manifest['entries'];
  if (entries is! List) {
    errors.add('entries must be a list');
    return errors;
  }
  final removals = manifest['removals'];
  if (removals is! List) {
    errors.add('removals must be a list');
    return errors;
  }

  final paths = <String>{};
  final entryNames = <String>{};
  var payload = 0;
  for (final entry in entries) {
    if (entry is! Map) {
      errors.add('an entry is not a JSON object');
      continue;
    }
    final path = entry['path'];
    if (path is! String || managedApplicationPathError(path) != null) {
      errors.add('entry ${path ?? '<unnamed>'}: invalid target path');
      continue;
    }
    if (!paths.add(path)) errors.add('entry $path: duplicate target path');

    final name = entry['entry'];
    if (name is! String || !_entryNamePattern.hasMatch(name)) {
      errors.add('entry $path: entry name must be files/NNNN.bin');
    } else if (!entryNames.add(name)) {
      errors.add('entry $path: duplicate entry name $name');
    }

    final entrySize = entry['entrySize'];
    if (entrySize is! int || entrySize < 0) {
      errors.add('entry $path: entrySize must be a non-negative integer');
    } else {
      payload += entrySize;
    }
    for (final key in const ['entrySha256', 'newSha256']) {
      final value = entry[key];
      if (value is! String || !_sha256Pattern.hasMatch(value)) {
        errors.add('entry $path: $key must be 64 lowercase hex characters');
      }
    }
    final newSize = entry['newSize'];
    if (newSize is! int || newSize < 0) {
      errors.add('entry $path: newSize must be a non-negative integer');
    }

    final method = entry['method'];
    if (isFullVariant && method != 'full') {
      errors.add('entry $path: a full package carries full files only');
    }
    if (method == 'patch') {
      final oldSha = entry['oldSha256'];
      if (oldSha is! String || !_sha256Pattern.hasMatch(oldSha)) {
        errors.add('entry $path: a patch must record oldSha256');
      }
      if (entry['oldSize'] is! int) {
        errors.add('entry $path: a patch must record oldSize');
      }
      if (entry['compression'] != 'zstd-patch-from') {
        errors.add('entry $path: a patch must use zstd-patch-from');
      }
    } else if (method == 'full') {
      if (entry['oldSha256'] != null) {
        errors.add('entry $path: a full file must not record oldSha256');
      }
      if (entry['compression'] != 'zstd') {
        errors.add('entry $path: a full file must use zstd');
      }
    } else {
      errors.add('entry $path: method must be patch or full');
    }
  }

  for (final removal in removals) {
    if (removal is! Map) {
      errors.add('a removal is not a JSON object');
      continue;
    }
    final path = removal['path'];
    if (path is! String || managedApplicationPathError(path) != null) {
      errors.add('removal ${path ?? '<unnamed>'}: invalid target path');
      continue;
    }
    if (paths.contains(path)) {
      errors.add('removal $path: the same path is also written');
    }
    final oldSha = removal['oldSha256'];
    if (oldSha is! String || !_sha256Pattern.hasMatch(oldSha)) {
      errors.add('removal $path: oldSha256 must be 64 hex characters');
    }
  }

  final payloadSize = manifest['payloadSize'];
  if (payloadSize is! int || payloadSize != payload) {
    errors.add('payloadSize must equal the sum of the entry sizes');
  }
  if (tree) {
    errors.addAll(_treeErrors(manifest, entries, removals));
  } else {
    for (final key in const ['links', 'linkRemovals', 'newTree']) {
      if (manifest.containsKey(key)) {
        errors.add('$key belongs to a tree package only');
      }
    }
  }
  return errors;
}

/// אימות החלק של חבילת העץ. כל ערך, symlink והסרה חייבים להתיישב עם
/// `newTree` — הוא שמולו הלקוח מאמת את העותק כולו.
List<String> _treeErrors(Map manifest, List entries, List removals) {
  final errors = <String>[];
  final newTree = manifest['newTree'];
  if (newTree is! Map ||
      newTree['files'] is! List ||
      newTree['links'] is! List) {
    return ['newTree must hold files and links lists'];
  }
  final treeFiles = <String, Map>{};
  for (final file in newTree['files'] as List) {
    if (file is! Map || file['path'] is! String) {
      errors.add('newTree: a file entry has no path');
      continue;
    }
    final path = file['path'] as String;
    if (managedApplicationPathError(path) != null) {
      errors.add('newTree: invalid file path $path');
    }
    final mode = file['mode'];
    if (file['size'] is! int ||
        file['sha256'] is! String ||
        !_sha256Pattern.hasMatch(file['sha256'] as String) ||
        mode is! int ||
        mode < 0 ||
        mode > 0x1FF) {
      errors.add('newTree: $path needs size, sha256 and mode');
    }
    if (treeFiles.containsKey(path)) errors.add('newTree: duplicate $path');
    treeFiles[path] = file;
  }
  final treeLinks = <String, String>{};
  for (final link in newTree['links'] as List) {
    if (link is! Map || link['path'] is! String || link['target'] is! String) {
      errors.add('newTree: a link entry needs path and target');
      continue;
    }
    final path = link['path'] as String;
    final target = link['target'] as String;
    final error =
        managedApplicationPathError(path) ?? linkTargetError(path, target);
    if (error != null) errors.add('newTree: link $path: $error');
    if (treeFiles.containsKey(path) || treeLinks.containsKey(path)) {
      errors.add('newTree: duplicate $path');
    }
    treeLinks[path] = target;
  }
  errors.addAll(
    pathsThroughLinksErrors([
      ...treeFiles.keys,
      ...treeLinks.keys,
    ], treeLinks.keys.toSet()),
  );

  for (final entry in entries.whereType<Map>()) {
    final file = treeFiles[entry['path']];
    if (file == null ||
        file['sha256'] != entry['newSha256'] ||
        file['size'] != entry['newSize']) {
      errors.add('entry ${entry['path']}: does not match newTree');
    }
  }
  for (final removal in removals.whereType<Map>()) {
    if (treeFiles.containsKey(removal['path'])) {
      errors.add('removal ${removal['path']}: the path is in newTree');
    }
  }

  final links = manifest['links'];
  final linkRemovals = manifest['linkRemovals'];
  if (links is! List || linkRemovals is! List) {
    errors.add('links and linkRemovals must be lists');
    return errors;
  }
  for (final link in links) {
    if (link is! Map || link['path'] is! String) {
      errors.add('a link entry has no path');
      continue;
    }
    if (treeLinks[link['path']] != link['target']) {
      errors.add('link ${link['path']}: does not match newTree');
    }
  }
  for (final removal in linkRemovals) {
    if (removal is! Map || removal['path'] is! String) {
      errors.add('a link removal has no path');
      continue;
    }
    final path = removal['path'] as String;
    if (managedApplicationPathError(path) != null) {
      errors.add('link removal $path: invalid path');
    }
    if (treeLinks.containsKey(path)) {
      errors.add('link removal $path: the link is in newTree');
    }
  }
  return errors;
}

/// העץ החדש מתוך מניפסט של חבילת עץ שכבר אומת.
TreeManifest treeManifestOf(Map<String, Object?> manifest) {
  final newTree = manifest['newTree'] as Map;
  return TreeManifest(
    files: {
      for (final file in (newTree['files'] as List).cast<Map>())
        file['path'] as String: TreeFile(
          size: file['size'] as int,
          sha256: file['sha256'] as String,
          mode: file['mode'] as int,
        ),
    },
    links: {
      for (final link in (newTree['links'] as List).cast<Map>())
        link['path'] as String: link['target'] as String,
    },
  );
}

/// קורא את מניפסט החבילה מתוך קובץ ה-ZIP.
Map<String, Object?> readUpdatePackageManifest(Archive archive) {
  final file = archive.findFile(kUpdateManifestEntryName);
  if (file == null) {
    throw UpdatePackageException(
      'the package has no $kUpdateManifestEntryName',
    );
  }
  final decoded = jsonDecode(utf8.decode(file.readBytes()!));
  if (decoded is! Map<String, Object?>) {
    throw UpdatePackageException('$kUpdateManifestEntryName is not an object');
  }
  final errors = validateUpdatePackageManifest(decoded);
  if (errors.isNotEmpty) {
    throw UpdatePackageException(
      'the package manifest is invalid:\n - ${errors.join('\n - ')}',
    );
  }
  return decoded;
}

/// מאמת חבילה בכך שהיא מוחלת בפועל על [root] — עותק של ההתקנה הישנה.
///
/// זהו מאמת צד-הפרסום: CI מריץ אותו על עותק לפני ההעלאה, כדי שחבילה שבורה
/// לא תפורסם מעולם. לקוח העדכון עצמו נכתב בנפרד.
void applyUpdatePackage({
  required File package,
  required Directory root,
  required String platform,
  required String architecture,
  Zstd zstd = const Zstd(),
  Directory? workDirectory,
}) {
  final archive = ZipDecoder().decodeBytes(package.readAsBytesSync());
  final manifest = _openForApply(archive, platform, architecture, zstd);
  if (manifest['schemaVersion'] == kUpdatePackageTreeSchemaVersion) {
    throw UpdatePackageException(
      'a tree package is applied with applyTreeUpdatePackage',
    );
  }

  final work =
      workDirectory ?? Directory.systemTemp.createTempSync('otzaria-apply');
  final ownsWork = workDirectory == null;
  try {
    _applyEntries(archive, manifest, root, work, zstd);

    for (final removal in (manifest['removals'] as List).cast<Map>()) {
      final path = removal['path'] as String;
      final target = File('${root.path}/$path');
      if (!target.existsSync()) continue;
      final bytes = target.readAsBytesSync();
      if (sha256.convert(bytes).toString() != removal['oldSha256']) {
        throw UpdatePackageException(
          '$path: the local file does not match the file being removed',
        );
      }
      target.deleteSync();
    }
  } finally {
    if (ownsWork && work.existsSync()) work.deleteSync(recursive: true);
  }
}

/// מחיל חבילת עץ על [root] — עותק של ההתקנה הישנה, כולל symlinks. אותו
/// סדר פעולות כמו בלקוח: הסרות, קבצים, symlinks, הרשאות.
Future<void> applyTreeUpdatePackage({
  required File package,
  required Directory root,
  required String platform,
  required String architecture,
  Zstd zstd = const Zstd(),
  TreeFileSystem fs = const LocalTreeFileSystem(),
}) async {
  final archive = ZipDecoder().decodeBytes(package.readAsBytesSync());
  final manifest = _openForApply(archive, platform, architecture, zstd);
  if (manifest['schemaVersion'] != kUpdatePackageTreeSchemaVersion) {
    throw UpdatePackageException('the package is not a tree package');
  }
  final work = Directory.systemTemp.createTempSync('otzaria-apply');
  try {
    try {
      await removeFromTree(
        fs: fs,
        root: root.path,
        linkRemovals: [
          for (final r in (manifest['linkRemovals'] as List).cast<Map>())
            r['path'] as String,
        ],
        fileRemovals: [
          for (final r in (manifest['removals'] as List).cast<Map>())
            r['path'] as String,
        ],
      );
      _applyEntries(archive, manifest, root, work, zstd);
      await completeTree(
        fs: fs,
        root: root.path,
        links: {
          for (final l in (manifest['links'] as List).cast<Map>())
            l['path'] as String: l['target'] as String,
        },
        newTree: treeManifestOf(manifest),
      );
    } on TreeUpdateException catch (error) {
      throw UpdatePackageException(error.message);
    } on FileSystemException catch (error) {
      throw UpdatePackageException('$error');
    }
  } finally {
    if (work.existsSync()) work.deleteSync(recursive: true);
  }
}

Map<String, Object?> _openForApply(
  Archive archive,
  String platform,
  String architecture,
  Zstd zstd,
) {
  final manifest = readUpdatePackageManifest(archive);
  if (manifest['platform'] != platform ||
      manifest['architecture'] != architecture) {
    throw UpdatePackageException(
      'the package targets ${manifest['platform']}/'
      '${manifest['architecture']} but the install is $platform/$architecture',
    );
  }
  if (!zstd.isAvailable) {
    throw UpdatePackageException('zstd is not available on PATH');
  }
  return manifest;
}

void _applyEntries(
  Archive archive,
  Map<String, Object?> manifest,
  Directory root,
  Directory work,
  Zstd zstd,
) {
  final payload = File('${work.path}/payload.bin');
  final produced = File('${work.path}/produced.bin');
  for (final entry in (manifest['entries'] as List).cast<Map>()) {
    final path = entry['path'] as String;
    final target = File('${root.path}/$path');
    final bytes = archive.findFile(entry['entry'] as String)?.readBytes();
    if (bytes == null) {
      throw UpdatePackageException('$path: ${entry['entry']} is missing');
    }
    if (sha256.convert(bytes).toString() != entry['entrySha256']) {
      throw UpdatePackageException('$path: the package entry is corrupt');
    }
    payload.writeAsBytesSync(bytes);

    if (entry['method'] == 'patch') {
      if (!target.existsSync()) {
        throw UpdatePackageException('$path: the old file is missing');
      }
      final oldBytes = target.readAsBytesSync();
      if (sha256.convert(oldBytes).toString() != entry['oldSha256']) {
        throw UpdatePackageException(
          '$path: the local file does not match the patch base',
        );
      }
      zstd.applyPatch(target, payload, produced);
    } else {
      zstd.decompress(payload, produced);
    }

    final newBytes = produced.readAsBytesSync();
    if (sha256.convert(newBytes).toString() != entry['newSha256']) {
      throw UpdatePackageException('$path: the result hash does not match');
    }
    target.parent.createSync(recursive: true);
    target.writeAsBytesSync(newBytes);
  }
}

File _managedFile(
  Directory root,
  String path,
  Map<String, Object?> entry,
  String side,
) {
  final file = File('${root.path}/$path');
  if (!file.existsSync()) {
    throw UpdatePackageException('$side build is missing $path');
  }
  final bytes = file.readAsBytesSync();
  if (bytes.length != entry['size'] ||
      sha256.convert(bytes).toString() != entry['sha256']) {
    throw UpdatePackageException(
      '$side build: $path does not match its manifest entry',
    );
  }
  return file;
}

Map<String, Object?> _readManifest(String path) {
  final decoded = jsonDecode(File(path).readAsStringSync());
  if (decoded is! Map<String, Object?>) {
    throw UpdatePackageException('$path is not a JSON object');
  }
  return decoded;
}

String _option(List<String> args, String name) {
  final index = args.indexOf('--$name');
  if (index < 0 || index + 1 >= args.length) {
    throw UpdatePackageException('missing required option --$name');
  }
  return args[index + 1];
}

String? _optionalOption(List<String> args, String name) {
  final index = args.indexOf('--$name');
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}

Future<void> main(List<String> args) async {
  const usage =
      'usage: dart run tool/release/generate_update_package.dart '
      '--old-manifest <file> --old-dir <dir> '
      '--new-manifest <file> --new-dir <dir> --out-dir <dir> [--verify]';
  try {
    final oldRoot = Directory(_option(args, 'old-dir'));
    final oldManifest = _readManifest(_option(args, 'old-manifest'));
    final newManifest = _readManifest(_option(args, 'new-manifest'));
    final newRoot = Directory(_option(args, 'new-dir'));
    final outDir = _optionalOption(args, 'out-dir') ?? '.';

    // שתי חבילות לכל מעבר: ה-patch שמנסים קודם, וחבילת הקבצים המלאים
    // שמשלימה ממנה כל ערך שנכשל אצל המשתמש.
    for (final variant in UpdatePackageVariant.values) {
      final pending = File(_pendingOutputPath(args));
      final result = buildUpdatePackage(
        oldManifest: oldManifest,
        oldRoot: oldRoot,
        newManifest: newManifest,
        newRoot: newRoot,
        output: pending,
        variant: variant,
      );
      if (args.contains('--verify')) {
        if (isTreeManifestPlatform(newManifest['platform'] as String)) {
          await verifyTreePackage(pending, oldRoot, newManifest);
        } else {
          _verify(pending, oldRoot, newManifest);
        }
        print('Verified ${result.assetName} against a copy of the old install');
      }
      final finalPath = '$outDir/${result.assetName}';
      pending.renameSync(finalPath);
      print(
        'Wrote $finalPath: ${result.packageSize} bytes, '
        '${result.patchedFiles} patched, ${result.fullFiles} full, '
        '${result.removedFiles} removed, ${result.unchangedFiles} unchanged, '
        '${result.patchBytesSaved} bytes saved by patching',
      );
    }
  } on UpdatePackageException catch (error) {
    stderr.writeln('::error::${error.message}');
    stderr.writeln(usage);
    exitCode = 1;
  } on AppFileManifestException catch (error) {
    stderr.writeln('::error::${error.message}');
    stderr.writeln(usage);
    exitCode = 1;
  }
}

/// מחיל את החבילה על עותק של ההתקנה הישנה ומשווה כל קובץ למניפסט החדש.
/// חבילה שאינה עוברת כאן לא תגיע למשתמש.
void _verify(
  File package,
  Directory oldRoot,
  Map<String, Object?> newManifest,
) {
  final copy = Directory.systemTemp.createTempSync('otzaria-verify');
  try {
    for (final entity in oldRoot.listSync(recursive: true)) {
      if (entity is! File) continue;
      final relative = entity.path
          .substring(oldRoot.path.length + 1)
          .replaceAll('\\', '/');
      final target = File('${copy.path}/$relative');
      target.parent.createSync(recursive: true);
      entity.copySync(target.path);
    }
    applyUpdatePackage(
      package: package,
      root: copy,
      platform: newManifest['platform'] as String,
      architecture: newManifest['architecture'] as String,
    );
    for (final file in (newManifest['files'] as List).cast<Map>()) {
      final produced = File('${copy.path}/${file['path']}');
      if (!produced.existsSync()) {
        throw UpdatePackageException('verify: ${file['path']} was not written');
      }
      if (sha256.convert(produced.readAsBytesSync()).toString() !=
          file['sha256']) {
        throw UpdatePackageException(
          'verify: ${file['path']} does not match the new build',
        );
      }
    }
  } finally {
    if (copy.existsSync()) copy.deleteSync(recursive: true);
  }
}

/// מחיל חבילת עץ על עותק של הישן ומשווה את העץ כולו — קבצים, symlinks,
/// הרשאות, ושום דבר נוסף — לעץ החדש. [fs] מוזרק לבדיקות.
Future<void> verifyTreePackage(
  File package,
  Directory oldRoot,
  Map<String, Object?> newManifest, {
  TreeFileSystem fs = const LocalTreeFileSystem(),
  Zstd zstd = const Zstd(),
}) async {
  final temp = Directory.systemTemp.createTempSync('otzaria-verify');
  final copy = Directory('${temp.path}/root');
  try {
    await fs.copyTree(oldRoot.path, copy.path);
    await applyTreeUpdatePackage(
      package: package,
      root: copy,
      platform: newManifest['platform'] as String,
      architecture: newManifest['architecture'] as String,
      zstd: zstd,
      fs: fs,
    );
    final archive = ZipDecoder().decodeBytes(package.readAsBytesSync());
    final errors = await verifyTree(
      fs: fs,
      root: copy.path,
      newTree: treeManifestOf(readUpdatePackageManifest(archive)),
      allowUnmanaged: false,
    );
    if (errors.isNotEmpty) {
      throw UpdatePackageException('verify:\n - ${errors.join('\n - ')}');
    }
  } finally {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  }
}

/// הפלט נכתב תחילה בשם זמני ומקבל את שמו הסופי רק אחרי שנבנה במלואו,
/// כדי שהעלאה לא תלקט חבילה חלקית.
String _pendingOutputPath(List<String> args) =>
    '${_optionalOption(args, 'out-dir') ?? '.'}/update-package.pending.zip';
