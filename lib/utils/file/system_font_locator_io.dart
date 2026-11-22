import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:win32_registry/win32_registry.dart';

import 'system_font_locator.dart';
import 'ttc_face.dart';

/// תיקיית הגופנים שהמשתמש מייבא לארגז החול של iOS, או null בפלטפורמה אחרת או
/// כשאין HOME. ה-HOME של אפליקציית iOS הוא מכל הנתונים של האפליקציה, ושם גם
/// `getApplicationSupportDirectory` של path_provider (Library/Application Support).
/// הסריקה רצה ב-isolate בלי ערוצי פלטפורמה, ולכן הנתיב נגזר מהסביבה.
@visibleForTesting
String? userFontsDirectoryFor(String os, Map<String, String?> env) {
  if (os != 'ios') return null;
  final home = env['HOME'];
  if (home == null || home.isEmpty) return null;
  return '$home/Library/Application Support/otzaria_user_fonts';
}

/// הנתיב של [userFontsDirectoryFor] לפלטפורמה הנוכחית.
String? userFontsDirectory() =>
    userFontsDirectoryFor(Platform.operatingSystem, Platform.environment);

/// תיקיות הגופנים של [os] ("windows" / "macos" / "linux" / "android") לפי [env].
@visibleForTesting
List<String> fontDirectoriesFor(String os, Map<String, String?> env) {
  switch (os) {
    case 'ios':
      // ארגז החול לא חושף את גופני המערכת; רק מה שהמשתמש ייבא.
      return [?userFontsDirectoryFor(os, env)];
    case 'windows':
      return [
        '${env['windir']}\\Fonts',
        '${env['USERPROFILE']}\\AppData\\Local\\Microsoft\\Windows\\Fonts',
      ];
    case 'macos':
      return [
        '/Library/Fonts',
        '/System/Library/Fonts',
        '${env['HOME']}/Library/Fonts',
      ];
    case 'android':
      // גופני המערכת ותיקיות היצרנים; קריאים לכל אפליקציה, בלי הרשאה.
      return [
        '/system/fonts',
        '/system_ext/fonts',
        '/product/fonts',
        '/vendor/fonts',
      ];
    case 'linux':
      final home = env['HOME'];
      final xdgData = env['XDG_DATA_HOME'];
      return [
        '/usr/share/fonts',
        '/usr/local/share/fonts',
        // מיקום המשתמש לפי XDG, עם ברירת המחדל שלו כשהמשתנה לא מוגדר.
        if (xdgData != null && xdgData.isNotEmpty)
          '$xdgData/fonts'
        else
          '$home/.local/share/fonts',
        // המיקום הישן שעדיין נסרק בידי fontconfig ונפוץ בהתקנות ידניות.
        '$home/.fonts',
      ];
  }
  return const [];
}

List<String> _fontDirectories() =>
    fontDirectoriesFor(Platform.operatingSystem, Platform.environment);

/// אוסף גופנים (TrueType/OpenType Collection): כמה faces בקובץ אחד. ב-macOS
/// ובאנדרואיד רבים מגופני המערכת, כולל עבריים, נמצאים רק באוספים.
bool isCollectionFile(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.ttc') || lower.endsWith('.otc');
}

bool _isFontFile(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.ttf') ||
      lower.endsWith('.otf') ||
      isCollectionFile(path);
}

List<String> installedFontPaths(String? family) => _collectFontPaths(
  _fontDirectories(),
  family,
  includeRegistry: Platform.isWindows,
);

/// כמו [installedFontPaths] על [directories] בלבד, בלי רישום וינדוס.
@visibleForTesting
List<String> fontPathsInDirectories(
  List<String> directories, [
  String? family,
]) => _collectFontPaths(directories, family, includeRegistry: false);

List<String> _collectFontPaths(
  List<String> directories,
  String? family, {
  required bool includeRegistry,
}) {
  final seen = <String>{};
  final result = <String>[];
  void add(String path, [String? name]) {
    if (!_isFontFile(path)) return;
    if (family != null &&
        !SystemFontLocator.nameMentionsFamily(
          name ?? p.windows.basenameWithoutExtension(path),
          family,
        )) {
      return;
    }
    if (seen.add(path.toLowerCase())) result.add(path);
  }

  for (final dir in directories) {
    try {
      for (final entity in Directory(dir).listSync(recursive: true)) {
        if (entity is File) add(entity.path);
      }
    } catch (_) {
      // תיקייה חסרה או ללא הרשאת קריאה — ממשיכים לשאר המקורות.
    }
  }

  if (includeRegistry) {
    try {
      for (final font in _registryFonts()) {
        add(font.path, font.name);
      }
    } catch (_) {
      // כשל בקריאת ה-registry אינו מונע את גופני התיקיות.
    }
  }

  return result;
}

/// קובץ גופן עצמאי של face מספר [index] באוסף [path]. מחלץ אותו למטמון בתיקיית
/// הקבצים הזמניים (פעם אחת לכל אוסף וגרסה שלו), כדי שכל צרכן שקורא נתיב גופן
/// (טעינה, PDF, הדפסה, תוספים) יקבל את ה-face הנכון ולא את הראשון באוסף.
/// [index] ריק: הנתיב עצמו. כשהחילוץ נכשל מוחזר נתיב האוסף (ה-face הראשון).
String faceFilePath(String path, int? index) {
  if (index == null) return path;
  final key = '$index:$path';
  final cached = _extractedFaces[key];
  if (cached != null && File(cached).existsSync()) return cached;
  try {
    final source = File(path);
    final stat = source.statSync();
    final directory = Directory(
      p.join(Directory.systemTemp.path, 'otzaria_font_faces'),
    )..createSync(recursive: true);
    final name =
        '${_fnv1a(path)}_${stat.size}_${stat.modified.millisecondsSinceEpoch}_$index';
    for (final extension in const ['ttf', 'otf']) {
      final existing = File(p.join(directory.path, '$name.$extension'));
      if (existing.existsSync() && existing.lengthSync() > 0) {
        return _extractedFaces[key] = existing.path;
      }
    }
    final raf = source.openSync();
    final Uint8List? face;
    try {
      face = extractCollectionFace(
        (offset, length) {
          raf.setPositionSync(offset);
          return raf.readSync(length);
        },
        stat.size,
        index,
      );
    } finally {
      raf.closeSync();
    }
    if (face == null) return path;
    // OTTO = גופן CFF: הסיומת עוזרת לצרכנים שמזהים לפיה.
    final extension = String.fromCharCodes(face.sublist(0, 4)) == 'OTTO'
        ? 'otf'
        : 'ttf';
    final target = File(p.join(directory.path, '$name.$extension'));
    final temporary = File('${target.path}.$pid.tmp')..writeAsBytesSync(face);
    try {
      temporary.renameSync(target.path);
    } on FileSystemException {
      // תהליך אחר כתב את אותו קובץ באותו רגע; התוכן זהה.
      if (!target.existsSync()) rethrow;
      temporary.deleteSync();
    }
    return _extractedFaces[key] = target.path;
  } catch (_) {
    return path;
  }
}

final Map<String, String> _extractedFaces = {};

int _fnv1a(String text) {
  var hash = 0x811c9dc5;
  for (final unit in text.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xFFFFFFFF;
  }
  return hash;
}

const _fontsSubKey = r'SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts';

/// הגופנים כפי שווינדוס רושם אותם; ערך ללא נתיב = קובץ בתיקיית המערכת.
List<({String name, String path})> _registryFonts() {
  final windowsFontsDir =
      '${Platform.environment['windir'] ?? r'C:\Windows'}\\Fonts';
  final result = <({String name, String path})>[];
  for (final hive in [LOCAL_MACHINE, CURRENT_USER]) {
    final RegistryKey key;
    try {
      key = hive.open(_fontsSubKey);
    } catch (_) {
      continue;
    }
    try {
      for (final entry in key.values) {
        final value = entry.value;
        if (value is! StringValue) continue;
        final path = value.value.trim();
        if (path.isEmpty) continue;
        result.add((
          name: entry.name,
          path: path.contains('\\') ? path : '$windowsFontsDir\\$path',
        ));
      }
    } finally {
      key.close();
    }
  }
  return result;
}
