import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';

import 'support/search_engine_test_init.dart';

/// אתחול גלובלי לכל חבילת הטסטים: פונקציות נרמול/טוקניזציה של החיפוש
/// (`sanitizeQuery`, `splitQueryWords`, `normalizeTextForIndexing` ...) מאצילות
/// למנוע ה-Rust דרך FRB, ולכן כל טסט (כולל widget tests שמפעילים אותן בעקיפין)
/// דורש ש-[RustLib] יאותחל. כאן מאתחלים אותו פעם אחת מול הספרייה הנייטיבית
/// שנבנתה מקומית. כשאין build זמין (CI ללא Rust) האתחול נכשל בשקט וטסטים
/// שתלויים במנוע ידווחו על כך.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // ב-CI הספרייה הנייטיבית חייבת להיטען: בלעדיה טסטי המנוע מדלגים על עצמם
  // והריצה ירוקה בלי לבדוק דבר.
  if (!await tryInitSearchEngine() &&
      Platform.environment['OTZARIA_REQUIRE_SEARCH_ENGINE'] == '1') {
    throw StateError(searchEngineSkipReason);
  }
  // שורש נתונים זמני לכל קובץ בדיקה — אחרת לוג השגיאות והאינדקס נכתבים
  // לפרופיל האמיתי של המפתח.
  final profileRoot = Directory.systemTemp.createTempSync('otzaria_test_data_');
  AppPaths.debugProfileDataRootPath = profileRoot.path;
  tearDownAll(() async {
    try {
      await profileRoot.delete(recursive: true);
    } on FileSystemException {
      // קובץ שנשאר פתוח בסוף הריצה — תיקייה זמנית, לא חוסמים עליה.
    }
  });
  await testMain();
}
