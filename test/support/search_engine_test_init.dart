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
///
/// נסרקים גם פלטי הבנייה של האפליקציה עצמה — לא פעם זו הבנייה היחידה על
/// מכונת פיתוח, ובלעדיה כל קבוצות הטסט שתלויות במנוע מדולגות בשקט.
List<String> searchEngineLibraryCandidates() {
  const names = [
    'search_engine.dll',
    'libsearch_engine.so',
    'libsearch_engine.dylib',
  ];
  final packageRoot = _searchEnginePackageRoot();
  final roots = <String>[
    for (final profile in ['release', 'debug'])
      if (packageRoot != null) '$packageRoot/rust/target/$profile',
    for (final profile in ['Release', 'Debug'])
      'build/windows/x64/plugins/otzaria_search_engine/$profile',
    'build/linux/x64/release/plugins/otzaria_search_engine',
    'build/linux/x64/debug/plugins/otzaria_search_engine',
  ];

  // במק המנוע נארז ב-framework, והבינארי שבו חסר סיומת.
  final macFrameworks = [
    for (final profile in ['Release', 'Debug'])
      'build/macos/Build/Products/$profile/otzaria_search_engine/'
          'search_engine.framework/search_engine',
  ];

  final candidates = <File>[];
  for (final root in roots) {
    for (final name in names) {
      final path = '$root/$name'.replaceAll('\\', '/').replaceAll('//', '/');
      final file = File(path);
      if (file.existsSync()) {
        candidates.add(file);
      }
    }
  }
  candidates.addAll(macFrameworks.map(File.new).where((f) => f.existsSync()));
  candidates.sort(
    (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
  );
  return [for (final file in candidates) file.path];
}

/// תיקיית העותקים שהטסטים טוענים ממנה. הבנייה לעולם אינה כותבת לכאן.
const String _testLoadDir = 'build/test_engine';

String _fileName(String path) {
  final separator = path.lastIndexOf(RegExp(r'[/\\]'));
  return separator < 0 ? path : path.substring(separator + 1);
}

/// מעתיק את הספרייה לנתיב פרטי לטסטים ומחזיר אותו. tester שנשאר תלוי אחרי
/// ריצה מחזיק נעול את הקובץ שטען, ועל פלט הבנייה זה מפיל כל בנייה הבאה.
String? _testLoadCopy(String source) {
  try {
    final file = File(source);
    final stat = file.statSync();
    final fileName = _fileName(source);
    final dot = fileName.lastIndexOf('.');
    final base = dot < 0 ? fileName : fileName.substring(0, dot);
    final extension = dot < 0 ? '' : fileName.substring(dot);
    // גרסת הבנייה בשם הקובץ: עותק חדש נוצר לצד הישן במקום לדרוס אותו נעול.
    final stamp = '${stat.modified.millisecondsSinceEpoch}_${stat.size}';
    final targetName = '${base}_$stamp$extension';
    final target = File('$_testLoadDir/$targetName');
    if (target.existsSync()) return target.path;

    Directory(_testLoadDir).createSync(recursive: true);
    final temp = File('$_testLoadDir/$base.$pid$extension.tmp');
    file.copySync(temp.path);
    try {
      temp.renameSync(target.path);
    } catch (_) {
      // tester מקביל הקדים אותנו — העותק שלו זהה בתוכנו.
      try {
        temp.deleteSync();
      } catch (_) {}
    }
    return target.existsSync() ? target.path : null;
  } catch (_) {
    return null;
  }
}

/// מוחק עותקים של בניות קודמות, מכל מקור (cargo או framework של מק). קובץ
/// שטוען אותו כרגע tester אחר אינו נמחק.
void _pruneStaleCopies(String keepName) {
  final copyName = RegExp(r'^(?:lib)?search_engine_\d+_\d+(?:\.\w+)?$');
  for (final entity in Directory(_testLoadDir).listSync()) {
    if (entity is! File) continue;
    final name = _fileName(entity.path);
    if (name == keepName || !copyName.hasMatch(name)) continue;
    try {
      entity.deleteSync();
    } catch (_) {}
  }
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
      final loadPath = _testLoadCopy(path) ?? path;
      await RustLib.init(externalLibrary: ExternalLibrary.open(loadPath));
      // מנקים רק אחרי טעינה מוצלחת — מועמד שנדחה לא ימחק עותק תקין.
      if (loadPath != path) _pruneStaleCopies(_fileName(loadPath));
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
