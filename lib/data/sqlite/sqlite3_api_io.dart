import 'dart:ffi';
import 'dart:isolate';

import 'package:sqlite3/sqlite3.dart';

export 'package:sqlite3/sqlite3.dart';

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
