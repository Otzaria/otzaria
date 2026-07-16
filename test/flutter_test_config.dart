import 'dart:async';

import 'support/search_engine_test_init.dart';

/// אתחול גלובלי לכל חבילת הטסטים: פונקציות נרמול/טוקניזציה של החיפוש
/// (`sanitizeQuery`, `splitQueryWords`, `normalizeTextForIndexing` ...) מאצילות
/// למנוע ה-Rust דרך FRB, ולכן כל טסט (כולל widget tests שמפעילים אותן בעקיפין)
/// דורש ש-[RustLib] יאותחל. כאן מאתחלים אותו פעם אחת מול הספרייה הנייטיבית
/// שנבנתה מקומית. כשאין build זמין (CI ללא Rust) האתחול נכשל בשקט וטסטים
/// שתלויים במנוע ידווחו על כך.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await tryInitSearchEngine();
  await testMain();
}
