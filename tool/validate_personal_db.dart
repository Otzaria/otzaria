// בודק מסד ספרים אישי לפני צירוף לאוצריא. אינו כותב למסד.
//
//   dart run tool/validate_personal_db.dart <path.db> [--no-file-check]
//
// קוד יציאה: 0 תקין (אולי עם אזהרות), 1 בעיה חוסמת, 64 שימוש שגוי.

import 'dart:io';

import 'src/personal_db_validator.dart';

void main(List<String> args) {
  final paths = args.where((a) => !a.startsWith('--')).toList();
  if (paths.isEmpty || args.contains('--help') || args.contains('-h')) {
    stderr.writeln(
      'Usage: dart run tool/validate_personal_db.dart <db> [<db> ...] '
      '[--no-file-check]',
    );
    exitCode = 64;
    return;
  }
  final checkFiles = !args.contains('--no-file-check');
  var failed = false;
  for (final path in paths) {
    final report = validatePersonalDb(path, checkFiles: checkFiles);
    stdout.writeln(formatReport(report));
    failed |= report.hasErrors;
  }
  exitCode = failed ? 1 : 0;
}
