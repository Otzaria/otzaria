// Build hook: רץ אוטומטית על כל `flutter build` / `flutter run` /
// `flutter pub get` ומחולל שני קבצים:
//   - `lib/settings/search/settings_search_index.g.dart` — מאחד את כל הצהרות
//     `static const List<SettingsSearchEntry> searchEntries` תחת `lib/settings/`.
//   - `lib/settings/l10n/settings_en.g.dart` — הקטלוג האנגלי של ההגדרות,
//     מתוך `settings_en.arb`.
//
// הלוגיקה עצמה ב-`tool/src/`, כדי לחלוק קוד עם הסקריפטים הידניים / CI
// (`tool/generate_search_index.dart`, `tool/generate_settings_l10n.dart`).

// `package:hooks` מוגדרת כ-dev_dependency כי היא נחוצה רק לסקריפט הזה
// בזמן build ולא ל-runtime של האפליקציה.
// ignore: depend_on_referenced_packages
import 'dart:io';

// ignore: depend_on_referenced_packages
import 'package:hooks/hooks.dart';

import '../tool/src/settings_index_generator.dart';
import '../tool/src/settings_l10n_generator.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    final packageRoot = Directory.fromUri(input.packageRoot);
    generateSettingsSearchIndex(packageRoot);
    generateSettingsL10n(packageRoot);
  });
}
