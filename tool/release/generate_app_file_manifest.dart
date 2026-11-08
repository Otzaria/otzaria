// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
// הכללים של הלקוח עצמו: נתיב שהוא דוחה היה משבית אצלו את המסלול הדיפרנציאלי
// לגמרי ובשקט.
import 'package:otzaria/update/differential/managed_paths.dart'
    show managedApplicationPathError;
import 'package:otzaria/update/differential/tree_fs.dart'
    show linkTargetError, pathsThroughLinksErrors;

/// גרסת הסכמה של מניפסט קובצי האפליקציה ב-Windows. צרכן חייב לדחות גרסה
/// שאינה מוכרת לו.
const int kAppFileManifestSchemaVersion = 1;

/// גרסת הסכמה של מניפסט עץ (macOS, Linux): כל קובץ נושא `mode`, ו-`links`
/// מתאר כל symlink. bundle שחסר בו symlink או ביט הרצה אינו עולה.
const int kAppFileTreeManifestSchemaVersion = 2;

/// האם הפלטפורמה מנוהלת כעץ — עם symlinks והרשאות — ולא כרשימת קבצים.
bool isTreeManifestPlatform(String platform) => platform != 'windows';

/// קבצים שקיימים בארכיון הנייד אך אינם חלק מההתקנה, ולכן אינם מנוהלים.
/// `portable.marker` נוסף ל-ZIP אחרי הבנייה (ראה "Zip Windows build").
const Set<String> kAppFileManifestExclusions = {'portable.marker'};

/// חותם השחרור שיושב **בתוך** תיקיית ההתקנה. זו הדרך היחידה של התוכנה
/// המותקנת לדעת את תגה: `<version>+<run_number>` אינו נגזר מ-PackageInfo.
const String kInstalledReleaseFileName = 'otzaria-release.json';

/// גרסת הסכמה של חותם השחרור. צרכן חייב לדחות גרסה גבוהה יותר.
const int kInstalledReleaseSchemaVersion = 1;

final RegExp _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');
final RegExp _architecturePattern = RegExp(r'^[a-z0-9_]+$');

/// שגיאת קלט בבניית מניפסט קובצי האפליקציה. תמיד עוצרת — מניפסט חלקי היה
/// גורם לעדכון דיפרנציאלי למחוק או לדלג על קובץ שהוא כן חלק מההתקנה.
class AppFileManifestException implements Exception {
  AppFileManifestException(this.message);
  final String message;
  @override
  String toString() => 'AppFileManifestException: $message';
}

/// שם הנכס של מניפסט קובצי האפליקציה. הארכיטקטורה היא חלק מהזהות: מניפסט
/// x64 מול התקנת ARM64 חייב להידחות.
String appFileManifestAssetName({
  required String platform,
  required String architecture,
}) => 'otzaria-app-files-$platform-$architecture.json';

/// בונה את תוכן חותם השחרור. אינו נושא hash של עצמו, ולכן הוא נכתב לתיקיית
/// הבנייה **לפני** סריקת המניפסט ונרשם בו ככל קובץ מנוהל אחר.
Map<String, Object?> buildInstalledReleaseStamp({
  required String releaseTag,
  required String releaseVersion,
  required String platform,
  required String architecture,
}) {
  if (releaseTag.trim().isEmpty) {
    throw AppFileManifestException('release tag is empty');
  }
  if (releaseVersion.trim().isEmpty) {
    throw AppFileManifestException('release version is empty');
  }
  if (platform.trim().isEmpty) {
    throw AppFileManifestException('platform is empty');
  }
  if (!_architecturePattern.hasMatch(architecture)) {
    throw AppFileManifestException(
      'architecture must be lowercase [a-z0-9_]: $architecture',
    );
  }
  return <String, Object?>{
    'schemaVersion': kInstalledReleaseSchemaVersion,
    'releaseTag': releaseTag,
    'releaseVersion': releaseVersion,
    'platform': platform,
    'architecture': architecture,
  };
}

/// כותב את חותם השחרור לתוך [root] ומחזיר את הקובץ.
File writeInstalledReleaseStamp({
  required Directory root,
  required String releaseTag,
  required String releaseVersion,
  required String platform,
  required String architecture,
}) {
  if (!root.existsSync()) {
    throw AppFileManifestException('build directory not found: ${root.path}');
  }
  final stamp = buildInstalledReleaseStamp(
    releaseTag: releaseTag,
    releaseVersion: releaseVersion,
    platform: platform,
    architecture: architecture,
  );
  final file = File(
    '${_normalizeDirectory(root.absolute.path)}'
    '$kInstalledReleaseFileName',
  );
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(stamp)}\n',
  );
  return file;
}

/// בונה מניפסט של קובצי ההתקנה מתוך [root] — תיקיית הבנייה
/// (`build/windows/<arch>/runner/Release`), לא ה-ZIP.
Map<String, Object?> buildAppFileManifest({
  required String releaseTag,
  required String releaseVersion,
  required String platform,
  required String architecture,
  required Directory root,
  Set<String> exclude = kAppFileManifestExclusions,
  int Function(File file)? modeOf,
}) {
  if (releaseTag.trim().isEmpty) {
    throw AppFileManifestException('release tag is empty');
  }
  if (releaseVersion.trim().isEmpty) {
    throw AppFileManifestException('release version is empty');
  }
  if (platform.trim().isEmpty) {
    throw AppFileManifestException('platform is empty');
  }
  if (!_architecturePattern.hasMatch(architecture)) {
    throw AppFileManifestException(
      'architecture must be lowercase [a-z0-9_]: $architecture',
    );
  }
  if (!root.existsSync()) {
    throw AppFileManifestException('build directory not found: ${root.path}');
  }

  final tree = isTreeManifestPlatform(platform);
  final readMode = modeOf ?? (File file) => file.statSync().mode & 0x1FF;
  final rootPath = _normalizeDirectory(root.absolute.path);
  final files = <Map<String, Object?>>[];
  final links = <Map<String, Object?>>[];
  for (final entity in root.listSync(recursive: true, followLinks: false)) {
    if (entity is Directory) continue;
    final absolute = _normalizeSeparators(entity.absolute.path);
    if (!absolute.startsWith(rootPath)) {
      throw AppFileManifestException(
        'file outside the build directory: ${entity.path}',
      );
    }
    final relative = absolute.substring(rootPath.length);
    if (exclude.contains(relative)) continue;
    final error = managedApplicationPathError(relative);
    if (error != null) {
      throw AppFileManifestException('$error: $relative');
    }
    if (entity is Link) {
      // symlink שנפסח בשקט היה משאיר framework חדש בלי Versions/Current.
      if (!tree) {
        throw AppFileManifestException('symlinks are not supported: $relative');
      }
      links.add({'path': relative, 'target': entity.targetSync()});
      continue;
    }
    final file = entity as File;
    final bytes = file.readAsBytesSync();
    files.add({
      'path': relative,
      'size': bytes.length,
      'sha256': sha256.convert(bytes).toString(),
      if (tree) 'mode': readMode(file),
    });
  }
  if (files.isEmpty) {
    throw AppFileManifestException('build directory is empty: ${root.path}');
  }
  int byPath(Map<String, Object?> a, Map<String, Object?> b) =>
      (a['path'] as String).compareTo(b['path'] as String);
  files.sort(byPath);
  links.sort(byPath);

  var installedSize = 0;
  for (final file in files) {
    installedSize += file['size'] as int;
  }

  final manifest = <String, Object?>{
    'schemaVersion': tree
        ? kAppFileTreeManifestSchemaVersion
        : kAppFileManifestSchemaVersion,
    'releaseTag': releaseTag,
    'releaseVersion': releaseVersion,
    'platform': platform,
    'architecture': architecture,
    'fileCount': files.length,
    'installedSize': installedSize,
    'files': files,
    if (tree) 'links': links,
  };

  final errors = validateAppFileManifest(manifest);
  if (errors.isNotEmpty) {
    throw AppFileManifestException(
      'generated manifest is invalid:\n - ${errors.join('\n - ')}',
    );
  }
  return manifest;
}

/// מאמת מניפסט ומחזיר רשימת שגיאות (ריקה = תקין). שדות לא מוכרים נסבלים.
List<String> validateAppFileManifest(Object? manifest) {
  final errors = <String>[];
  if (manifest is! Map) return ['manifest is not a JSON object'];
  final schema = manifest['schemaVersion'];
  final tree = schema == kAppFileTreeManifestSchemaVersion;
  if (schema != kAppFileManifestSchemaVersion && !tree) {
    errors.add(
      'schemaVersion must be $kAppFileManifestSchemaVersion or '
      '$kAppFileTreeManifestSchemaVersion',
    );
  }
  final platform = manifest['platform'];
  if (platform is String && tree != isTreeManifestPlatform(platform)) {
    errors.add('schemaVersion does not match the platform $platform');
  }
  for (final key in const [
    'releaseTag',
    'releaseVersion',
    'platform',
    'architecture',
  ]) {
    final value = manifest[key];
    if (value is! String || value.trim().isEmpty) {
      errors.add('$key must be a non-empty string');
    }
  }
  final architecture = manifest['architecture'];
  if (architecture is String && !_architecturePattern.hasMatch(architecture)) {
    errors.add('architecture must be lowercase [a-z0-9_]');
  }

  final files = manifest['files'];
  if (files is! List || files.isEmpty) {
    errors.add('files must be a non-empty list');
    return errors;
  }

  final seen = <String>{};
  var total = 0;
  String? previous;
  for (final file in files) {
    if (file is! Map) {
      errors.add('a file entry is not a JSON object');
      continue;
    }
    final path = file['path'];
    if (path is! String) {
      errors.add('a file entry has no path');
      continue;
    }
    final pathError = managedApplicationPathError(path);
    if (pathError != null) {
      errors.add('file $path: $pathError');
    } else if (!seen.add(path)) {
      errors.add('file $path: duplicate path');
    }
    if (previous != null && previous.compareTo(path) >= 0) {
      errors.add('file $path: entries must be sorted by path');
    }
    previous = path;

    final size = file['size'];
    if (size is! int || size < 0) {
      errors.add('file $path: size must be a non-negative integer');
    } else {
      total += size;
    }
    final sha = file['sha256'];
    if (sha is! String || !_sha256Pattern.hasMatch(sha)) {
      errors.add('file $path: sha256 must be 64 lowercase hex characters');
    }
    final mode = file['mode'];
    if (tree && (mode is! int || mode < 0 || mode > 0x1FF)) {
      errors.add('file $path: mode must be permission bits (0-0777)');
    } else if (!tree && mode != null) {
      errors.add('file $path: mode belongs to a tree manifest only');
    }
  }

  final links = manifest['links'];
  if (tree) {
    if (links is! List) {
      errors.add('links must be a list');
    } else {
      final linkPaths = <String>{};
      String? previousLink;
      for (final link in links) {
        if (link is! Map || link['path'] is! String) {
          errors.add('a link entry has no path');
          continue;
        }
        final path = link['path'] as String;
        final pathError = managedApplicationPathError(path);
        if (pathError != null) {
          errors.add('link $path: $pathError');
        } else if (!seen.add(path) || !linkPaths.add(path)) {
          errors.add('link $path: duplicate path');
        }
        if (previousLink != null && previousLink.compareTo(path) >= 0) {
          errors.add('link $path: entries must be sorted by path');
        }
        previousLink = path;
        final target = link['target'];
        final targetError = target is String
            ? linkTargetError(path, target)
            : 'link target is missing';
        if (targetError != null) errors.add('link $path: $targetError');
      }
      errors.addAll(
        pathsThroughLinksErrors([
          for (final file in files)
            if (file is Map && file['path'] is String) file['path'] as String,
          ...linkPaths,
        ], linkPaths),
      );
    }
  } else if (links != null) {
    errors.add('links belong to a tree manifest only');
  }

  final fileCount = manifest['fileCount'];
  if (fileCount is! int || fileCount != files.length) {
    errors.add('fileCount must equal the number of file entries');
  }
  final installedSize = manifest['installedSize'];
  if (installedSize is! int || installedSize != total) {
    errors.add('installedSize must equal the sum of the file sizes');
  }
  return errors;
}

/// מפה מנתיב ה-symlink ליעדו. מניפסט Windows אינו נושא symlinks.
Map<String, String> appFileManifestLinks(Map<String, Object?> manifest) => {
  for (final link in (manifest['links'] as List? ?? const []).cast<Map>())
    link['path'] as String: link['target'] as String,
};

/// מפה מנתיב ל-entry, לשימוש הצרכנים (השוואה, אימות, בניית חבילת עדכון).
Map<String, Map<String, Object?>> appFileManifestIndex(
  Map<String, Object?> manifest,
) {
  final index = <String, Map<String, Object?>>{};
  for (final file in (manifest['files'] as List).cast<Map<String, Object?>>()) {
    index[file['path'] as String] = file;
  }
  return index;
}

/// זורק אם המניפסט אינו מתאר את היעד המבוקש. זה השער שמונע החלת עדכון x64
/// על התקנת ARM64 — אותם שמות קבצים, בינאריים שאינם ניתנים להרצה.
void requireAppFileManifestTarget(
  Map<String, Object?> manifest, {
  required String platform,
  required String architecture,
}) {
  if (manifest['platform'] != platform ||
      manifest['architecture'] != architecture) {
    throw AppFileManifestException(
      'manifest targets ${manifest['platform']}/${manifest['architecture']} '
      'but $platform/$architecture was requested',
    );
  }
}

String _normalizeSeparators(String path) => path.replaceAll('\\', '/');

String _normalizeDirectory(String path) {
  final normalized = _normalizeSeparators(path);
  return normalized.endsWith('/') ? normalized : '$normalized/';
}

String _option(List<String> args, String name) {
  final index = args.indexOf('--$name');
  if (index < 0 || index + 1 >= args.length) {
    throw AppFileManifestException('missing required option --$name');
  }
  return args[index + 1];
}

String? _optionalOption(List<String> args, String name) {
  final index = args.indexOf('--$name');
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}

void main(List<String> args) {
  const usage =
      'usage: dart run tool/release/generate_app_file_manifest.dart '
      '--tag <release-tag> --version <version> --dir <install-root> '
      '--architecture <x64|arm64|universal> [--platform windows|macos|linux] '
      '[--out <file>] '
      '[--stamp]';
  try {
    final tag = _option(args, 'tag');
    final version = _option(args, 'version');
    final dir = _option(args, 'dir');
    final architecture = _option(args, 'architecture');
    final platform = _optionalOption(args, 'platform') ?? 'windows';

    if (args.contains('--stamp')) {
      final file = writeInstalledReleaseStamp(
        root: Directory(dir),
        releaseTag: tag,
        releaseVersion: version,
        platform: platform,
        architecture: architecture,
      );
      print('Wrote ${file.path} for $tag ($platform/$architecture)');
      return;
    }

    final out =
        _optionalOption(args, 'out') ??
        appFileManifestAssetName(
          platform: platform,
          architecture: architecture,
        );

    final manifest = buildAppFileManifest(
      releaseTag: tag,
      releaseVersion: version,
      platform: platform,
      architecture: architecture,
      root: Directory(dir),
    );
    File(out).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
    );
    print(
      'Wrote $out with ${manifest['fileCount']} files '
      '(${manifest['installedSize']} bytes)',
    );
  } on AppFileManifestException catch (error) {
    stderr.writeln('::error::${error.message}');
    stderr.writeln(usage);
    exitCode = 1;
  }
}
