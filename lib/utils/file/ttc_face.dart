import 'dart:typed_data';

import 'sfnt_bytes.dart';

/// קורא את הטווח [offset, offset + length) של המקור. מחזיר פחות מ-[length]
/// בתים (או ריק) כשהטווח חורג מסוף המקור.
typedef SfntRangeReader = Uint8List Function(int offset, int length);

/// כמה גופנים יש באוסף TrueType/OpenType (`ttcf`), או 0 כשהבתים אינם אוסף.
/// מספיקים 12 הבתים הראשונים של הקובץ.
int collectionFaceCount(Uint8List header) {
  if (header.length < 12 || header.sfntTag(0) != 'ttcf') return 0;
  final count = header.sfntU32(8);
  return count > 0 && count <= 0xFFFF ? count : 0;
}

/// מחלץ את ה-face שמספרו [index] מאוסף ל-sfnt עצמאי, שאפשר לטעון כגופן רגיל:
/// ב-TTC ההיסטים בטבלאות מוחלטים לתוך האוסף, וטוענים כמו FontLoader ו-PDFium
/// קוראים רק את ה-face הראשון. הטבלאות מועתקות כמו שהן (כולל checksum), ההיסטים
/// נכתבים מחדש והטבלאות מיושרות ל-4 בתים.
///
/// מחזיר `null` כשהמקור אינו אוסף, האינדקס מחוץ לטווח או המבנה פגום. טבלה
/// שחורגת מסוף המקור נחתכת. טבלה שההיסט שלה מחוץ למקור נחשבת מבנה פגום, אלא אם
/// [skipMissingTables]: אז היא מושמטת מהגופן המחולץ. זה המצב על מטא-דאטה
/// קומפקטי (`SfntMetadataReader`), שבו טבלאות הגליפים לא נכללו בכלל.
Uint8List? extractCollectionFace(
  SfntRangeReader read,
  int length,
  int index, {
  bool skipMissingTables = false,
}) {
  if (length < 16 || index < 0) return null;
  final header = read(0, 12);
  final count = collectionFaceCount(header);
  if (count == 0 || index >= count) return null;
  final offsetBytes = read(12 + index * 4, 4);
  if (offsetBytes.length < 4) return null;
  final faceOffset = offsetBytes.sfntU32(0);
  if (faceOffset <= 0 || faceOffset + 12 > length) return null;

  final offsetTable = read(faceOffset, 12);
  if (offsetTable.length < 12) return null;
  final numTables = offsetTable.sfntU16(4);
  if (numTables <= 0) return null;
  final directory = read(faceOffset, 12 + numTables * 16);
  if (directory.length < 12 + numTables * 16) return null;

  final records = <int>[];
  final sources = <({int offset, int length})>[];
  var dataLength = 0;
  for (var t = 0; t < numTables; t++) {
    final record = 12 + t * 16;
    final offset = directory.sfntU32(record + 8);
    final declared = directory.sfntU32(record + 12);
    if (offset < 0 || declared < 0 || offset >= length) {
      if (skipMissingTables) continue;
      return null;
    }
    final available = offset + declared > length ? length - offset : declared;
    records.add(record);
    sources.add((offset: offset, length: available));
    dataLength += (available + 3) & ~3;
  }
  if (records.isEmpty) return null;

  final kept = records.length;
  final headerLength = 12 + kept * 16;
  final out = Uint8List(headerLength + dataLength);
  out.setRange(0, 12, directory);
  final view = ByteData.sublistView(out);
  // כותרת הגופן המחולץ מתארת את הטבלאות שנשארו.
  var entrySelector = 0;
  while (2 << entrySelector <= kept) {
    entrySelector++;
  }
  final searchRange = (1 << entrySelector) * 16;
  view
    ..setUint16(4, kept)
    ..setUint16(6, searchRange)
    ..setUint16(8, entrySelector)
    ..setUint16(10, kept * 16 - searchRange);
  var cursor = headerLength;
  for (var i = 0; i < kept; i++) {
    final source = sources[i];
    final table = read(source.offset, source.length);
    if (table.length < source.length) return null;
    final record = 12 + i * 16;
    out.setRange(record, record + 16, directory, records[i]);
    out.setRange(cursor, cursor + source.length, table);
    view.setUint32(record + 8, cursor);
    cursor += (source.length + 3) & ~3;
  }
  return out;
}

/// [extractCollectionFace] על אוסף שנמצא כולו בזיכרון.
Uint8List? extractCollectionFaceFromBytes(
  Uint8List collection,
  int index, {
  bool skipMissingTables = false,
}) => extractCollectionFace(
  (offset, length) => offset >= collection.length
      ? Uint8List(0)
      : Uint8List.sublistView(
          collection,
          offset,
          offset + length > collection.length
              ? collection.length
              : offset + length,
        ),
  collection.length,
  index,
  skipMissingTables: skipMissingTables,
);
