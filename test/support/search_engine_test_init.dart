import 'dart:convert';
import 'dart:io';

import 'package:otzaria_search_engine/otzaria_search_engine.dart';

/// מאתר את שורש חבילת המנוע דרך package_config.json (תחת `flutter test`
/// ‏Isolate.resolvePackageUri מחזיר null, ולכן קוראים את הקובץ ישירות;
/// ה-CWD של flutter test הוא שורש הפרויקט).
String? _searchEnginePackageRoot() {
  final configFile = File('.dart_tool/package_config.json');
  if (!configFile.existsSync()) return null;
  final config = jsonDecode(configFile.readAsStringSync());
  final packages = config['packages'] as List<dynamic>;
  for (final package in packages) {
    if (package['name'] == 'otzaria_search_engine') {
      final rootUri = Uri.parse(package['rootUri'] as String);
      final resolved = rootUri.hasScheme
          ? rootUri
          : configFile.absolute.parent.uri.resolveUri(rootUri);
      return resolved.toFilePath();
    }
  }
  return null;
}

/// כל בניות המנוע הזמינות (release/debug), ממוינות מהחדשה לישנה — קוד
/// ה-FRB המחולל חייב להתאים ל-DLL (בדיקת content hash באתחול), ו-build
/// ישן בפרופיל אחד אסור שיסתיר build עדכני בפרופיל השני.
List<String> searchEngineLibraryCandidates() {
  final packageRoot = _searchEnginePackageRoot();
  if (packageRoot == null) return const [];
  const names = [
    'search_engine.dll',
    'libsearch_engine.so',
    'libsearch_engine.dylib',
  ];
  final candidates = <File>[];
  for (final profile in ['release', 'debug']) {
    for (final name in names) {
      final path = '$packageRoot/rust/target/$profile/$name'
          .replaceAll('\\', '/')
          .replaceAll('//', '/');
      final file = File(path);
      if (file.existsSync()) {
        candidates.add(file);
      }
    }
  }
  candidates.sort(
    (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
  );
  return [for (final file in candidates) file.path];
}

bool? _initResult;

/// טוען את ספריית מנוע החיפוש הנייטיבית ומאתחל את [RustLib]. פונקציות כמו
/// `sanitizeQuery`/`splitQueryWords`/`normalizeTextForIndexing` מאצילות למנוע,
/// כך שהטסטים שלהן דורשים את הספרייה; כשאין build זמין מוחזר `false` והקבוצה
/// תדולג. מנסה את הבניות מהחדשה לישנה — build מיושן שנכשל בבדיקת
/// ה-content hash אינו חוסם build תואם בפרופיל אחר. אידמפוטנטי — האתחול
/// קורה פעם אחת ל-isolate ותוצאתו נשמרת, כך שאפשר לקרוא גם
/// מ-`flutter_test_config.dart` וגם מ-`main` של כל טסט.
Future<bool> tryInitSearchEngine() async {
  if (_initResult != null) return _initResult!;
  for (final path in searchEngineLibraryCandidates()) {
    try {
      await RustLib.init(externalLibrary: ExternalLibrary.open(path));
      return _initResult = true;
    } catch (_) {
      // אתחול כושל עלול להשאיר instance חלקי שחוסם ניסיון נוסף.
      try {
        RustLib.dispose();
      } catch (_) {}
    }
  }
  return _initResult = false;
}

/// הודעת דילוג אחידה לקבוצות טסט שתלויות במנוע הנייטיבי.
const String searchEngineSkipReason =
    'ספריית מנוע החיפוש הנייטיבית לא נמצאה — הריצו cargo build בחבילה';
