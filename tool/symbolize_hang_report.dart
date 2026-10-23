// מוסיף שמות פונקציות לפריימי Dart (app.so+0x…) בדוחות התקיעה של errors.txt.
//
//   dart run tool/symbolize_hang_report.dart --symbols <file.debug> [errors.txt]
//
// קובץ הסמלים הוא הנכס otzaria-dart-symbols-windows-<arch>.debug של אותו
// release. בלי קובץ קלט נקרא stdin. קוד יציאה: 0 הצלחה, 64 שימוש שגוי.

import 'dart:convert';
import 'dart:io';

import 'src/hang_report_symbolizer.dart';

Future<void> main(List<String> args) async {
  final symbolsAt = args.indexOf('--symbols');
  final symbolsPath = symbolsAt >= 0 && symbolsAt + 1 < args.length
      ? args[symbolsAt + 1]
      : null;
  final inputs = [
    for (var i = 0; i < args.length; i++)
      if (i != symbolsAt && i != symbolsAt + 1) args[i],
  ];
  if (symbolsPath == null || inputs.length > 1 || args.contains('--help')) {
    stderr.writeln(
      'Usage: dart run tool/symbolize_hang_report.dart '
      '--symbols <file.debug> [errors.txt]',
    );
    exitCode = 64;
    return;
  }
  final symbols = DartSymbols.parse(File(symbolsPath).readAsBytesSync());
  final log = inputs.isEmpty
      ? await stdin.transform(utf8.decoder).join()
      : File(inputs.single).readAsStringSync();
  stdout.write(symbolizeHangReport(log, symbols));
}
