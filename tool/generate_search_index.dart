// ignore_for_file: avoid_print
//
// סקריפט בנייה: סורק את כל קבצי ה-Dart תחת lib/settings/ ואוסף את כל
// הצהרות `static const List<SettingsSearchEntry> searchEntries`,
// ומחולל את lib/settings/search/settings_search_index.g.dart המכיל
// אינדקס מאוחד של כל הפריטים.
//
// הפעלה ידנית:  `dart run tool/generate_search_index.dart`
// ב-CI:         הוסף לפני `flutter analyze`/`flutter build` כצעד עצמאי.
//
// הלוגיקה עצמה ב-`tool/src/settings_index_generator.dart`, ומשותפת עם
// `hook/build.dart` (שרץ אוטומטית בכל בנייה).

import 'dart:io';

import 'src/settings_index_generator.dart';

void main(List<String> args) {
  final root = Directory(settingsRootRelativePath);
  if (!root.existsSync()) {
    stderr.writeln('Settings directory not found: $settingsRootRelativePath');
    exit(1);
  }

  final result = generateSettingsSearchIndex(Directory.current);
  if (result.changed) {
    stdout.writeln(
      'Generated ${result.outputPath} with ${result.declarationsCount} declaration(s).',
    );
  } else {
    stdout.writeln(
      'Index up-to-date: ${result.outputPath} (${result.declarationsCount} declarations).',
    );
  }
}
