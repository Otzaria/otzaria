// בודק מסד ספרים אישי לפני צירוף לאוצריא. אינו כותב למסד.
//
//   dart run tool/validate_personal_db.dart <path.db> [--no-file-check]
//       [--library=<seforim.db>]
//
// קוד יציאה: 0 תקין (אולי עם אזהרות), 1 בעיה חוסמת, 64 שימוש שגוי.

import 'dart:io';

import 'src/personal_db_validator.dart';

void main(List<String> args) {
  final paths = args.where((a) => !a.startsWith('--')).toList();
  if (paths.isEmpty || args.contains('--help') || args.contains('-h')) {
    stderr.writeln(
      'Usage: dart run tool/validate_personal_db.dart <db> [<db> ...] '
      '[--no-file-check] [--library=<seforim.db>]',
    );
    exitCode = 64;
    return;
  }
  final checkFiles = !args.contains('--no-file-check');
  const libraryFlag = '--library=';
  final library = args
      .where((a) => a.startsWith(libraryFlag))
      .map((a) => a.substring(libraryFlag.length))
      .lastOrNull;
  var failed = false;
  for (final path in paths) {
    final report = validatePersonalDb(
      path,
      checkFiles: checkFiles,
      officialLibrary: library,
    );
    stdout.writeln(formatReport(report));
    failed |= report.hasErrors;
  }
  exitCode = failed ? 1 : 0;
}
