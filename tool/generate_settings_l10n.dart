// ignore_for_file: avoid_print
//
// סקריפט בנייה: מחולל את lib/settings/l10n/settings_en.g.dart מתוך
// lib/settings/l10n/settings_en.arb, ומוודא את תקינות הקטלוג.
//
// הפעלה ידנית:  `dart run tool/generate_settings_l10n.dart`
// ב-CI:         הוסף לפני `flutter analyze`/`flutter build` כצעד עצמאי.
//
// הלוגיקה עצמה ב-`tool/src/settings_l10n_generator.dart`, ומשותפת עם
// `hook/build.dart` (שרץ אוטומטית בכל בנייה).

import 'dart:io';

import 'src/settings_l10n_generator.dart';

void main(List<String> args) {
  try {
    final result = generateSettingsL10n(Directory.current);
    if (result.changed) {
      stdout.writeln(
        'Generated ${result.outputPath} with ${result.entriesCount} entry/ies.',
      );
    } else {
      stdout.writeln(
        'Catalog up-to-date: ${result.outputPath} '
        '(${result.entriesCount} entries).',
      );
    }
  } on SettingsL10nError catch (e) {
    stderr.writeln(e.message);
    exit(1);
  }
}
