/// ה-VFS של מסד הספרייה (`otzaria_zvfs`): `seforim.zdb` נקרא דרכו, וכל קובץ
/// אחר עובר דרכו ללא שינוי. נייטיבי בלבד — ב-web נבחר מימוש ריק.
library;

export 'library_vfs_stub.dart' if (dart.library.io) 'library_vfs_io.dart';

/// סיומת קובץ הספרייה הדחוס. הרזולבר בוחר קובץ כזה רק כשהוא zdb תקין.
const String zdbFileExtension = '.zdb';

/// האם [path] הוא קובץ ספרייה דחוס — לפי השם בלבד, בלי גישה לקובץ.
bool isZdbPath(String path) => path.toLowerCase().endsWith(zdbFileExtension);
