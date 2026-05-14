// Build hook: רץ אוטומטית על כל `flutter build` / `flutter run` /
// `flutter pub get` ומחולל את `lib/settings/search/settings_search_index.g.dart`
// המאחד את כל הצהרות `static const List<SettingsSearchEntry> searchEntries`
// בקבצים תחת `lib/settings/`.
//
// הלוגיקה עצמה ב-`tool/src/settings_index_generator.dart`, כדי לחלוק קוד
// עם `tool/generate_search_index.dart` (הסקריפט הידני / CI).

// `package:hooks` מוגדרת כ-dev_dependency כי היא נחוצה רק לסקריפט הזה
// בזמן build ולא ל-runtime של האפליקציה.
// ignore: depend_on_referenced_packages
import 'dart:io';

// ignore: depend_on_referenced_packages
import 'package:hooks/hooks.dart';

import '../tool/src/settings_index_generator.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    final packageRoot = Directory.fromUri(input.packageRoot);
    generateSettingsSearchIndex(packageRoot);
  });
}
