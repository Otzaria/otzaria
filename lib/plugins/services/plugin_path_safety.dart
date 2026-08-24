import 'dart:io';

import 'package:otzaria/core/app_paths.dart';
import 'package:path/path.dart' as p;

/// מחזירה את הנתיב הקנוני של [path] (מוחלט, מנורמל ועם symlinks פתורים),
/// או `null` אם לא ניתן לפתור אותו.
///
/// אם [path] עצמו אינו קיים (למשל יעד כתיבה חדש ב-`download`/`extractZip`),
/// פותרת בצורה קנונית את האב הקיים הקרוב ביותר ומצרפת אליו את הסיומת שטרם
/// נוצרה — כך גם נתיב חדש שעובר דרך symlink מאותר לפי יעדו האמיתי. זהו גבול
/// האבטחה לכל פעולות הכתיבה/מחיקה לדיסק של תוספים: בדיקה לקסיקלית על המחרוזת
/// בלבד הייתה מאשרת כתיבה מחוץ ליעד דרך symlink-תיקייה קיים.
///
/// **המגבלה:** hard link אינו מובחן מקובץ רגיל בשום API של מערכת הקבצים, ולכן
/// אינו ניתן לזיהוי כאן — נתיב שהוא hard link ליעד חוץ ייחשב לנתיב פנימי.
String? canonicalizeNearestExisting(String path) {
  var existing = p.normalize(p.absolute(path));
  final pending = <String>[];
  // followLinks: false — קישור **תלוי** (dangling) מוחזר כ-notFound כשעוקבים
  // אחריו, והלולאה הייתה מתייחסת אליו כשם שטרם נוצר ומאשרת כתיבה ליעדו.
  while (FileSystemEntity.typeSync(existing, followLinks: false) ==
      FileSystemEntityType.notFound) {
    final parent = p.dirname(existing);
    if (parent == existing) return null; // הגענו לשורש ושום דבר לא קיים
    pending.insert(0, p.basename(existing));
    existing = parent;
  }
  try {
    final canonical = switch (FileSystemEntity.typeSync(
      existing,
      followLinks: false,
    )) {
      FileSystemEntityType.directory => Directory(
        existing,
      ).resolveSymbolicLinksSync(),
      FileSystemEntityType.link => Link(
        existing,
      ).resolveSymbolicLinksSync(),
      _ => File(existing).resolveSymbolicLinksSync(),
    };
    return pending.isEmpty
        ? canonical
        : p.normalize(p.joinAll([canonical, ...pending]));
  } catch (_) {
    return null;
  }
}

/// פותרת נתיב יחסי [relative] בתוך [root], ומחזירה את הנתיב הקנוני שלו או
/// `null` אם הוא יוצא מהשורש. זהו גבול המרחב הפרטי של תוסף (`fs.writeFile`
/// וחבריו): `..`, נתיב מוחלט, UNC, וכל רכיב symlink בדרך — כולם נדחים.
///
/// symlink נדחה **בלי לבדוק לאן הוא מצביע**: ב-Windows קישור שנוצר לפני שהיעד
/// היה קיים אינו נפתר ע"י `resolveSymbolicLinksSync`, ולכן הצורה הקנונית לבדה
/// אינה גבול מספיק. hard link אינו ניתן לזיהוי כלל (ראה
/// [canonicalizeNearestExisting]).
///
/// [relative] ריק או `.` מוחזר כשורש עצמו (ל-`listDir`/`stat` על השורש).
String? resolveWithinRoot(String root, String relative) {
  final raw = relative.trim();
  // נתיב UNC נבדק על הקלט הגולמי: p.absolute הופך `\\host\share` לנתיב מקומי
  // שגוי (`C:\host\share`) ומסתיר את העובדה שזו כתובת רשת.
  if (raw.startsWith(r'\\') || raw.startsWith('//')) return null;
  if (p.isAbsolute(raw)) return null;
  // ב-Windows ':' פותח נתיב תלוי-כונן (`C:x`) או זרם נתונים חלופי (`a.txt:s`).
  if (Platform.isWindows && raw.contains(':')) return null;

  final canonicalRoot = canonicalizeNearestExisting(root);
  if (canonicalRoot == null) return null;
  if (raw.isEmpty || raw == '.') return canonicalRoot;

  var walk = canonicalRoot;
  for (final segment in p.split(p.normalize(raw))) {
    walk = p.join(walk, segment);
    if (FileSystemEntity.isLinkSync(walk)) return null;
  }

  final canonical = canonicalizeNearestExisting(p.join(canonicalRoot, raw));
  if (canonical == null) return null;
  if (!p.isWithin(canonicalRoot, canonical)) return null;
  return canonical;
}

/// תיקיות שבחירתן ב-`ui.pickFolder` נדחית *רק כשהן עצמן נבחרו* — תיקיות
/// הבית של המשתמש. תת-תיקייה שלהן (מסמכים, הורדות) נשארת מותרת.
List<String> pluginExactOnlyProtectedFolders() {
  final env = Platform.environment;
  return [
    env['USERPROFILE'],
    env['HOME'],
  ].whereType<String>().where((e) => e.isNotEmpty).toList();
}

/// תיקיות שאסור לתוסף לקבל גישת כתיבה אליהן — לא הן ולא מה שבתוכן: תיקיות
/// המערכת, תיקיית ההתקנה של אוצריא, תיקיית הנתונים שלה והספרייה.
Future<List<String>> pluginProtectedFolderRoots() async {
  final env = Platform.environment;
  final roots = <String>[p.dirname(Platform.resolvedExecutable)];
  try {
    roots.add(await AppPaths.getDataRootPath());
  } catch (_) {
    // סביבה ללא path_provider (בדיקות) — שאר השורשים עדיין נאכפים.
  }
  try {
    // הספרייה ניתנת להזזה לכונן אחר, ולכן אינה בהכרח תחת שורש הנתונים.
    final libraryPath = await AppPaths.getLibraryPath();
    roots.add(libraryPath);
    roots.add(AppPaths.libraryRootOf(libraryPath));
  } catch (_) {
    // אין Settings/path_provider — שאר השורשים עדיין נאכפים.
  }

  void addEnvRoots(List<String> keys) {
    for (final key in keys) {
      final value = env[key];
      if (value != null && value.isNotEmpty) roots.add(value);
    }
  }

  if (Platform.isWindows) {
    addEnvRoots(const [
      'ProgramFiles',
      'ProgramFiles(x86)',
      'ProgramW6432',
      'ProgramData',
      'SystemRoot',
    ]);
    final appData = env['APPDATA'];
    if (appData != null && appData.isNotEmpty) {
      roots.add(
        p.join(
          appData,
          'Microsoft',
          'Windows',
          'Start Menu',
          'Programs',
          'Startup',
        ),
      );
    }
  } else if (Platform.isLinux || Platform.isMacOS) {
    roots.addAll(const ['/etc', '/usr', '/bin', '/System', '/Library']);
    final home = env['HOME'];
    if (home != null && home.isNotEmpty) {
      // ‎~/.config מכיל autostart, ו-‎~/.ssh את מפתחות המשתמש.
      roots.add(p.join(home, '.ssh'));
      roots.add(p.join(home, '.config'));
    }
  }
  return roots;
}

/// בודקת אם מותר לתוסף לקבל את [path] כתיקייה מאושרת ב-`ui.pickFolder`.
/// מחזירה הודעת דחייה, או `null` כשהתיקייה מותרת.
Future<String?> pluginFolderRejectionReason(
  String path, {
  List<String>? protectedRoots,
  List<String>? exactOnlyFolders,
}) async {
  // נתיב UNC (`\\server\share`, וגם `\\localhost\c$\Windows`) עוקף את בדיקת
  // isWithin מול השורשים המוגנים — ותוסף אינו אמור לקבל תיקיית רשת. הבדיקה על
  // הקלט הגולמי: p.absolute הופך `\\host\share` ל-`C:\host\share` ומטשטש אותו.
  if (Platform.isWindows && (path.startsWith(r'\\') || path.startsWith('//'))) {
    return 'תיקיית רשת אינה תיקייה מותרת לתוספים';
  }
  final canonical = canonicalizeNearestExisting(path);
  if (canonical == null) return 'לא ניתן לפתור את התיקייה שנבחרה';
  if (canonical.startsWith(r'\\')) {
    return 'תיקיית רשת אינה תיקייה מותרת לתוספים';
  }
  if (p.equals(p.dirname(canonical), canonical)) {
    return 'שורש כונן אינו תיקייה מותרת לתוספים';
  }
  for (final folder in exactOnlyFolders ?? pluginExactOnlyProtectedFolders()) {
    final canonicalFolder = canonicalizeNearestExisting(folder);
    if (canonicalFolder == null) continue;
    if (p.equals(canonical, canonicalFolder)) {
      return 'תיקיית הבית של המשתמש אינה תיקייה מותרת לתוספים';
    }
  }
  for (final root in protectedRoots ?? await pluginProtectedFolderRoots()) {
    final canonicalRoot = canonicalizeNearestExisting(root);
    if (canonicalRoot == null) continue;
    if (p.equals(canonical, canonicalRoot) ||
        p.isWithin(canonicalRoot, canonical)) {
      return 'תיקיות המערכת ותיקיות אוצריא אינן מותרות לתוספים';
    }
  }
  return null;
}
