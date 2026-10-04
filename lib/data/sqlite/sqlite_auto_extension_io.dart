import 'dart:ffi';

import 'package:sqlite3/sqlite3.dart';

/// רושם את הפונקציה שבכתובת [address] כ-auto extension, ופותח חיבור זמני
/// כדי שתרוץ מיד. הרישום גלובלי לתהליך.
void registerSqliteAutoExtension(int address) {
  sqlite3.ensureExtensionLoaded(SqliteExtension(Pointer.fromAddress(address)));
  sqlite3.openInMemory().close();
}
