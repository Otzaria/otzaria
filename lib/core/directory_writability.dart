import 'dart:io';

import 'package:path/path.dart' as p;

/// שם הקובץ שנכתב ונמחק כדי לוודא הרשאת כתיבה בפועל.
const String _writeProbeFileName = '.otzaria_write_probe';
final _activeProbes = <String, Future<bool>>{};

/// בודק שניתן לכתוב לתיקייה, ויוצר אותה אם אינה קיימת.
///
/// קיום התיקייה אינו מספיק: ACL שנוצר בהרשאות מנהל, או תיקייה תחת
/// Program Files במצב נייד, קריאים אך חסומים לכתיבה (issue #1031).
Future<bool> isDirectoryWritable(String path) => _activeProbes.putIfAbsent(
  path,
  () => _probe(path).whenComplete(() {
    _activeProbes.remove(path);
  }),
);

Future<bool> _probe(String path) async {
  try {
    await Directory(path).create(recursive: true);
    final probe = File(p.join(path, _writeProbeFileName));
    await probe.writeAsString('', flush: true);
    await probe.delete();
    return true;
  } catch (_) {
    return false;
  }
}
