/// רישום נקודת כניסה ב-`sqlite3_auto_extension` של ה-SQLite שהאפליקציה טוענת.
library;

export 'sqlite_auto_extension_stub.dart'
    if (dart.library.io) 'sqlite_auto_extension_io.dart';
