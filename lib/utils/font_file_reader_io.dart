import 'dart:io';

List<int> readBytesSync(String path) {
  // הקריאה סינכרונית כדי לשמור על API סינכרוני של רשימות גופנים.
  return File(path).readAsBytesSync();
}
