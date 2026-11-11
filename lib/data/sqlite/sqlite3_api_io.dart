import 'dart:ffi';
import 'dart:isolate';

import 'package:sqlite3/sqlite3.dart';

export 'package:sqlite3/sqlite3.dart';

/// פותח חיבור ב-isolate ומעביר בעלות לקורא. החיבור לא יכול לכלול callbacks של Dart.
Future<Database> openSqliteInBackground(Database Function() open) async {
  final address = await Isolate.run(() {
    final db = open();
    final address = db.leak().address;
    db.close();
    return address;
  }, debugName: 'SqliteOpen');
  return sqlite3.fromPointer(Pointer.fromAddress(address));
}

extension DatabaseCloseInIsolate on Database {
  /// סגירת הקובץ (CloseHandle) נתקעת לשניות בכונן איטי או תחת סורק, ולכן
  /// החיבור עובר ל-isolate ונסגר שם.
  Future<void> closeInIsolate() {
    final address = leak().address;
    close();
    return Isolate.run(
      () => sqlite3.fromPointer(Pointer.fromAddress(address)).close(),
      debugName: 'SqliteClose',
    );
  }
}
