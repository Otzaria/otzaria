import 'dart:io';

import 'package:path/path.dart' as p;

/// קובץ סימון בתיקייה שהאפליקציה יצרה לחיפוש הסמנטי.
const String kSemanticOwnerMarker = '.otzaria-semantic';

/// יוצר את [dir] (אם חסרה) ומסמן אותה כשייכת לחיפוש הסמנטי.
Future<void> markSemanticDirectory(String dir) async {
  await Directory(dir).create(recursive: true);
  final marker = File(p.join(dir, kSemanticOwnerMarker));
  if (!await marker.exists()) await marker.writeAsString('');
}

const List<String> _ownershipSigns = [
  kSemanticOwnerMarker,
  'CURRENT',
  'PREVIOUS',
];

/// האם [dir] שייכת לחיפוש הסמנטי: נושאת את הסימון, או שהמנוע מזהה אותה
/// כסט וקטורים (`CURRENT`/`PREVIOUS`). תיקייה זרה באותו שם אינה נמחקת.
Future<bool> isSemanticOwnedDirectory(String dir) async {
  if (!await Directory(dir).exists()) return false;
  for (final name in _ownershipSigns) {
    if (await File(p.join(dir, name)).exists()) return true;
  }
  return false;
}

/// מוחק את [dir] רק כשהיא שלנו. מחזיר האם נמחקה.
Future<bool> deleteSemanticOwnedDirectory(String dir) async {
  if (!await isSemanticOwnedDirectory(dir)) return false;
  // followLinks של list מגן רק על הילדים, לא על קישור השורש.
  if (await FileSystemEntity.isLink(dir)) {
    await Link(dir).delete();
    return true;
  }
  // סימני הבעלות נמחקים אחרונים: קובץ נעול לא ישאיר תיקייה שכבר לא מזוהה כשלנו.
  await for (final entry in Directory(dir).list(followLinks: false)) {
    if (_ownershipSigns.contains(p.basename(entry.path))) continue;
    await entry.delete(recursive: true);
  }
  await Directory(dir).delete(recursive: true);
  return true;
}
