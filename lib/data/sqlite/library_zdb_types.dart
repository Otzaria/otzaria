/// כותרת קובץ zdb כפי ש-zvfs קרא ואימת אותה (כותרת, מילון ואינדקס).
class LibraryZdbHeader {
  const LibraryZdbHeader({
    required this.formatMajor,
    required this.formatMinor,
    required this.pageSize,
    required this.logicalSize,
    required this.physicalSize,
    required this.dictName,
    required this.dictId,
    required this.level,
    required this.fileUuidHex,
    required this.contentXxh64Hex,
  });

  final int formatMajor;
  final int formatMinor;
  final int pageSize;

  /// הגודל ש-SQLite רואה (בסיס + overlay).
  final int logicalSize;

  /// גודל קובץ הבסיס בדיסק, בלי ה-overlay.
  final int physicalSize;
  final String dictName;
  final int dictId;
  final int level;

  /// 32 ספרות hex באותיות קטנות, בסדר הבתים שבקובץ (כמו `zvfs_cli info`).
  final String fileUuidHex;

  /// 16 ספרות hex באותיות קטנות.
  final String contentXxh64Hex;
}

/// סוג הכשל של פעולת zdb, ממופה מקודי השגיאה של zvfs.
enum LibraryZdbFailure { busy, corrupt, unsupported, notZdb, io, other }

/// כשל של פעולת zdb (קריאה, אימות, התקנה או דחיסה).
class LibraryZdbException implements Exception {
  const LibraryZdbException(this.failure, this.message);

  final LibraryZdbFailure failure;
  final String message;

  /// הקובץ פתוח בתהליך הזה או באחר. ניסיון מאוחר יותר עשוי להצליח.
  bool get isBusy => failure == LibraryZdbFailure.busy;

  @override
  String toString() => 'LibraryZdbException(${failure.name}): $message';
}
