import 'dart:typed_data';

import 'package:otzaria/utils/file/cfb_reader.dart';
import 'package:otzaria/utils/file/document_conversion_exceptions.dart';
import 'package:otzaria/utils/file/document_format.dart';
import 'package:otzaria/utils/file/html_to_otzaria.dart'
    show kHtmlConverterVersion;
import 'package:otzaria/utils/file/legacy_word_pictures.dart';
import 'package:otzaria/utils/file/legacy_word_properties.dart';
import 'package:otzaria/utils/file/text_encoding.dart';
import 'package:otzaria/utils/file/word_number_format.dart';
import 'package:otzaria/utils/file/word_web_page.dart';
import 'package:otzaria/utils/text/html_escape.dart';
import 'package:otzaria/utils/text/otzaria_markup.dart';

/// גרסת ממיר ה-Word הבינארי. **חובה להעלות בכל שינוי שמשפיע על הפלט** —
/// הגרסה היא חלק ממפתח-התוקף של המטמון.
/// v2: שדות מקוננים אינם מדליפים את ההוראה לגוף, וחתיכה שחורגת מהזרם זורקת
/// חריגה במקום להשמיט פסקה בשקט.
/// v3: שכבת המאפיינים (STSH + FKP) — כותרות, מודגש/נטוי/קו-תחתי, טבלאות
/// ומרכוז. עד כאן הפלט היה טקסט חשוף בלבד.
/// v4: הערות שוליים (PlcffndRef/PlcffndTxt) — עד כאן נמחקו לחלוטין.
/// v5: תמונות מוטמעות מזרם ה-Data, דרך עץ רשומות ה-OfficeArt.
/// v6: וריאנט ה-Bi (complex script) של מודגש/נטוי נצבר בנפרד — צבירה משותפת
/// ביטלה את עצמה וכל ההדגשה והנטייה **בעברית** נעלמו. בנוסף: טקסט מוסתר
/// מדולג, וריאנטי קו תחתי, קו חוצה כפול, צבע טקסט ומרקר.
/// v7: יישור נגזר גם מ-`sprmPFBiDi`; בפסקה RTL נשמר מרכוז בלבד.
/// v8: גוף ריק ותקרת תווים זורקים חריגה במקום להחזיר כותרת בלבד, וטבלת
/// סגנונות פגומה אינה מפילה עוד את שכבת ה-PAPX/CHPX כולה.
/// v10: דף אינטרנט שנשמר כ-.doc (HTML או MHTML) עובר במנוע ה-HTML.
const int _legacyWordLayerVersion = 10;

/// נגזרת גם מגרסת מנוע ה-HTML, שממיר את דפי האינטרנט שנשמרו כ-.doc: קבוע
/// עצמאי היה נשאר מאחור בכל שינוי שם, והמטמון היה מגיש פלט מיושן.
const int kLegacyWordConverterVersion =
    _legacyWordLayerVersion * 1000 + kHtmlConverterVersion;

/// ממיר מסמך Word בינארי ישן (.doc / .dot, פורמט Word 97-2003) לטקסט
/// של אוצריא.
///
/// **הטקסט במסמך אינו רציף.** Word מפצל אותו ל"חתיכות" (pieces) לפי הקידוד,
/// וה-piece table הוא היחיד שיודע לשחזר את הסדר. לכן זהו parser מלא ולא
/// גרידה של מחרוזות מהבינארי: גרידה מייצרת טקסט בסדר שגוי עם זבל ביניים,
/// ובעברית היא הורסת את המסמך לגמרי.
///
/// ראו `docs/legacy_word_doc_research.md` לרקע, למגבלות ולתכנית ההמשך.
String legacyWordToText(
  Uint8List bytes,
  String title, {
  DocumentFormat format = DocumentFormat.doc,
  String? path,
  bool embedImages = true,
}) {
  final webPage = hasOleContainerSignature(bytes)
      ? null
      : sniffWordWebPage(bytes);
  if (webPage != null) {
    return wordWebPageToText(
      bytes,
      title,
      kind: webPage,
      format: format,
      path: path,
      embedImages: embedImages,
    );
  }

  final cfb = CfbFile.parse(bytes, format: format, path: path);

  final wordDocument = cfb.readStream('WordDocument');
  if (wordDocument == null) {
    throw CorruptedDocumentException(
      path: path,
      format: format,
      cause: 'אין זרם WordDocument — המכולה אינה מסמך Word',
    );
  }

  final fib = _Fib.parse(wordDocument, format: format, path: path);

  if (fib.isEncrypted) {
    throw EncryptedDocumentException(
      path: path,
      format: format,
      cause: 'המסמך מוגן בסיסמה',
    );
  }

  // זרם הטבלה נבחר לפי דגל ב-FIB; בחירה שגויה מפרשת piece table של מסמך אחר.
  final tableName = fib.useTable1 ? '1Table' : '0Table';
  final table = cfb.readStream(tableName);
  if (table == null) {
    throw CorruptedDocumentException(
      path: path,
      format: format,
      cause: 'זרם $tableName חסר',
    );
  }

  final pieces = _parsePieceTable(
    table,
    fib,
    format: format,
    path: path,
  );

  final characters = _readCharacters(
    wordDocument,
    pieces,
    0,
    fib.ccpText,
    format: format,
    path: path,
  );
  // גוף ריק אינו "ספר ריק" אלא FIB פגום: `ccpText` שנקרא שלילי או אפס
  // מייצר פלט "כותרת בלבד" שנראה כספר תקין, נשמר במטמון ומאונדקס ככזה.
  if (characters.characters.isEmpty) {
    throw CorruptedDocumentException(
      path: path,
      format: format,
      cause: 'גוף המסמך ריק (ccpText=${fib.ccpText})',
    );
  }
  final footnotes = _readFootnotes(
    wordDocument,
    table,
    pieces,
    fib,
    format: format,
    path: path,
  );
  // שכבת העיצוב אופציונלית: מסמך בלי FKP מאבד כותרות ועיצוב אך לא טקסט.
  final properties = LegacyWordProperties.parse(
    wordDocument,
    table,
    fib.propertyLocations,
  );
  final paragraphs = _buildParagraphs(
    characters,
    properties,
    footnotes,
    cfb.readStream('Data'),
    embedImages: embedImages,
    footnoteNumFmt: wordNumFmtForMsonfc(
      legacyWordFootnoteNumberFormat(
        wordDocument,
        table,
        plcfSedOffset: fib.fcPlcfSed,
        plcfSedLength: fib.lcbPlcfSed,
      ),
    ),
  );

  final output = <String>[
    otzariaInlineText('<h1>${escapeHtmlText(title)}</h1>'),
    ...paragraphs,
  ];
  return output.join('\n');
}

// ── FIB ───────────────────────────────────────────────────────────────────

/// ה-File Information Block שבראש זרם `WordDocument`.
///
/// המבנה משתנה בין גרסאות, ולכן האורכים נקראים מהקובץ (`csw`, `cslw`,
/// `cbRgFcLcb`) ולא מקובעים — קובץ ישן יותר היה מפורש בהיסט שגוי.
class _Fib {
  final bool isEncrypted;
  final bool useTable1;

  /// מספר התווים בגוף המסמך הראשי. כל מה שמעבר לו הוא הערות שוליים,
  /// כותרות עליונות/תחתונות והערות — ואינו חלק מהטקסט הנקרא.
  final int ccpText;

  /// מיקום ואורך ה-CLX, המכיל את ה-piece table.
  final int fcClx;
  final int lcbClx;

  /// מספר התווים בתת-מסמך הערות השוליים, שיושב מיד אחרי גוף המסמך.
  final int ccpFtn;

  /// `PlcffndRef` — מיקומי סימני ההערות בגוף; `PlcffndTxt` — גבולות הטקסט
  /// של כל הערה בתת-המסמך.
  final int fcPlcffndRef;
  final int lcbPlcffndRef;
  final int fcPlcffndTxt;
  final int lcbPlcffndTxt;

  /// `PlcfSed` — טבלת הסקציות, שממנה נקרא פורמט מספור ההערות.
  final int fcPlcfSed;
  final int lcbPlcfSed;

  /// מיקומי שכבת העיצוב — טבלת הסגנונות ועמודי ה-PAPX/CHPX.
  final LegacyWordPropertyLocations propertyLocations;

  const _Fib({
    required this.isEncrypted,
    required this.useTable1,
    required this.ccpText,
    required this.ccpFtn,
    required this.fcClx,
    required this.lcbClx,
    required this.fcPlcffndRef,
    required this.lcbPlcffndRef,
    required this.fcPlcffndTxt,
    required this.lcbPlcffndTxt,
    required this.fcPlcfSed,
    required this.lcbPlcfSed,
    required this.propertyLocations,
  });

  /// חתימת מסמך Word 8 (97 ומעלה).
  static const int _wIdentWord8 = 0xA5EC;

  /// גרסת ה-FIB המינימלית שהמבנה שלה נתמך כאן.
  static const int _minSupportedNFib = 101;

  static _Fib parse(
    Uint8List stream, {
    required DocumentFormat format,
    String? path,
  }) {
    Never fail(String reason) => throw CorruptedDocumentException(
      path: path,
      format: format,
      cause: reason,
    );

    if (stream.length < 0x100) fail('זרם WordDocument קצר מדי');
    final data = ByteData.sublistView(stream);

    final wIdent = data.getUint16(0x00, Endian.little);
    if (wIdent != _wIdentWord8) {
      throw UnsupportedDocumentFormatException(
        path: path,
        format: format,
        cause:
            'חתימת FIB לא נתמכת (0x${wIdent.toRadixString(16)}) — '
            'ככל הנראה Word 6/95, שאינו נתמך',
      );
    }

    final nFib = data.getUint16(0x02, Endian.little);
    if (nFib < _minSupportedNFib) {
      throw UnsupportedDocumentFormatException(
        path: path,
        format: format,
        cause: 'גרסת FIB $nFib ישנה מדי',
      );
    }

    final flags = data.getUint16(0x0A, Endian.little);

    // המבנה משתנה-אורך: כל קטע מצהיר על גודלו ממש לפניו.
    var offset = 0x20;
    final csw = data.getUint16(offset, Endian.little);
    offset += 2 + csw * 2;

    if (offset + 2 > stream.length) fail('FIB קטוע לפני fibRgLw');
    final cslw = data.getUint16(offset, Endian.little);
    final fibRgLwOffset = offset + 2;
    offset = fibRgLwOffset + cslw * 4;

    if (offset + 2 > stream.length) fail('FIB קטוע לפני fibRgFcLcb');
    final cbRgFcLcb = data.getUint16(offset, Endian.little);
    final blobOffset = offset + 2;

    // ccpText הוא הערך הרביעי ב-fibRgLw.
    const ccpTextIndex = 3;
    if (cslw <= ccpTextIndex ||
        fibRgLwOffset + (ccpTextIndex + 1) * 4 > stream.length) {
      fail('fibRgLw קצר מכדי להכיל את ccpText');
    }
    final ccpText = data.getInt32(
      fibRgLwOffset + ccpTextIndex * 4,
      Endian.little,
    );

    // fcClx/lcbClx הם הזוג ה-34 (אינדקס 33) בטבלת המצביעים.
    const clxIndex = 33;
    if (cbRgFcLcb <= clxIndex ||
        blobOffset + (clxIndex + 1) * 8 > stream.length) {
      fail('fibRgFcLcb קצר מכדי להכיל את fcClx');
    }
    final clxBase = blobOffset + clxIndex * 8;

    /// זוג `fc`/`lcb` מטבלת המצביעים. זוג שאינו בטווח מוחזר כאפס — שכבת
    /// העיצוב אופציונלית, ובלעדיה עדיין מחולץ טקסט.
    (int, int) pair(int index) {
      if (cbRgFcLcb <= index || blobOffset + (index + 1) * 8 > stream.length) {
        return (0, 0);
      }
      final base = blobOffset + index * 8;
      return (
        data.getUint32(base, Endian.little),
        data.getUint32(base + 4, Endian.little),
      );
    }

    final (stshOffset, stshLength) = pair(_stshfIndex);
    final (chpxOffset, chpxLength) = pair(_plcfBteChpxIndex);
    final (papxOffset, papxLength) = pair(_plcfBtePapxIndex);
    final (fndRefOffset, fndRefLength) = pair(_plcffndRefIndex);
    final (fndTxtOffset, fndTxtLength) = pair(_plcffndTxtIndex);
    final (sedOffset, sedLength) = pair(_plcfSedIndex);

    // ccpFtn הוא הערך החמישי ב-fibRgLw, מיד אחרי ccpText.
    const ccpFtnIndex = 4;
    final ccpFtn =
        cslw > ccpFtnIndex &&
            fibRgLwOffset + (ccpFtnIndex + 1) * 4 <= stream.length
        ? data.getInt32(fibRgLwOffset + ccpFtnIndex * 4, Endian.little)
        : 0;

    return _Fib(
      isEncrypted: flags & 0x0100 != 0,
      useTable1: flags & 0x0200 != 0,
      ccpText: ccpText < 0 ? 0 : ccpText,
      ccpFtn: ccpFtn < 0 ? 0 : ccpFtn,
      fcClx: data.getUint32(clxBase, Endian.little),
      lcbClx: data.getUint32(clxBase + 4, Endian.little),
      fcPlcffndRef: fndRefOffset,
      lcbPlcffndRef: fndRefLength,
      fcPlcffndTxt: fndTxtOffset,
      lcbPlcffndTxt: fndTxtLength,
      fcPlcfSed: sedOffset,
      lcbPlcfSed: sedLength,
      propertyLocations: LegacyWordPropertyLocations(
        stshOffset: stshOffset,
        stshLength: stshLength,
        papxOffset: papxOffset,
        papxLength: papxLength,
        chpxOffset: chpxOffset,
        chpxLength: chpxLength,
      ),
    );
  }

  /// אינדקסים בטבלת המצביעים (`fibRgFcLcb`).
  static const int _stshfIndex = 1;
  static const int _plcffndRefIndex = 2;
  static const int _plcffndTxtIndex = 3;
  static const int _plcfSedIndex = 6;
  static const int _plcfBteChpxIndex = 12;
  static const int _plcfBtePapxIndex = 13;
}

// ── piece table ───────────────────────────────────────────────────────────

/// חתיכת טקסט אחת: טווח מיקומים לוגי, ההיסט הפיזי שלו, וקידודו.
class _Piece {
  /// מיקום התו הראשון (Character Position) בטקסט הלוגי.
  final int cpStart;

  /// מיקום התו שאחרי האחרון.
  final int cpEnd;

  /// היסט בזרם `WordDocument` שבו החתיכה מתחילה.
  final int offset;

  /// האם החתיכה מקודדת בבית אחד לתו (cp1252) במקום UTF-16.
  final bool isCompressed;

  const _Piece({
    required this.cpStart,
    required this.cpEnd,
    required this.offset,
    required this.isCompressed,
  });

  int get length => cpEnd - cpStart;
}

List<_Piece> _parsePieceTable(
  Uint8List table,
  _Fib fib, {
  required DocumentFormat format,
  String? path,
}) {
  Never fail(String reason) => throw CorruptedDocumentException(
    path: path,
    format: format,
    cause: reason,
  );

  if (fib.lcbClx == 0) fail('אין piece table (lcbClx=0)');
  if (fib.fcClx + fib.lcbClx > table.length) fail('ה-CLX חורג מזרם הטבלה');

  final clx = Uint8List.sublistView(table, fib.fcClx, fib.fcClx + fib.lcbClx);
  final clxView = ByteData.sublistView(clx);

  // ה-CLX פותח ברצף Prc אופציונליים (clxt=1) עד ל-Pcdt (clxt=2).
  var cursor = 0;
  while (cursor < clx.length && clx[cursor] == 0x01) {
    if (cursor + 3 > clx.length) fail('Prc קטוע ב-CLX');
    final cbGrpprl = clxView.getUint16(cursor + 1, Endian.little);
    cursor += 3 + cbGrpprl;
  }

  if (cursor >= clx.length || clx[cursor] != 0x02) {
    fail('לא נמצא Pcdt ב-CLX');
  }
  if (cursor + 5 > clx.length) fail('Pcdt קטוע');

  final plcSize = clxView.getUint32(cursor + 1, Endian.little);
  final plcStart = cursor + 5;
  if (plcStart + plcSize > clx.length) fail('ה-PlcPcd חורג מה-CLX');

  // PlcPcd = (n+1) מיקומי CP בני 4 בתים, ואחריהם n מתארי חתיכה בני 8.
  final pieceCount = (plcSize - 4) ~/ 12;
  if (pieceCount <= 0) fail('piece table ריק');

  final plc = ByteData.sublistView(clx, plcStart, plcStart + plcSize);
  final pcdBase = (pieceCount + 1) * 4;

  final pieces = <_Piece>[];
  for (var i = 0; i < pieceCount; i++) {
    final cpStart = plc.getUint32(i * 4, Endian.little);
    final cpEnd = plc.getUint32((i + 1) * 4, Endian.little);
    if (cpEnd <= cpStart) continue;

    final fcValue = plc.getUint32(pcdBase + i * 8 + 2, Endian.little);
    // סיבית 30 מסמנת חתיכה דחוסה; ההיסט האמיתי יושב בסיביות 0–29.
    final isCompressed = fcValue & 0x40000000 != 0;
    final fc = fcValue & 0x3FFFFFFF;

    pieces.add(
      _Piece(
        cpStart: cpStart,
        cpEnd: cpEnd,
        offset: isCompressed ? fc ~/ 2 : fc,
        isCompressed: isCompressed,
      ),
    );
  }

  if (pieces.isEmpty) fail('piece table בלי חתיכות תקינות');
  return pieces;
}

/// קורא את תווי גוף המסמך לפי סדרם הלוגי.
///
/// חתיכה דחוסה מקודדת בית-לתו לפי cp1252; חתיכה שאינה דחוסה היא UTF-16LE.
/// **כאן נמצאת העברית**: היא אינה נכנסת ל-cp1252, ולכן Word שומר אותה תמיד
/// בחתיכות UTF-16 — ומכאן שאין צורך לנחש דף-קוד.
///
/// חתיכה שהיסטה חורג מהזרם = קובץ קטוע. דילוג עליה היה משמיט פסקה שלמה
/// בשקט ומייצר "ספר תקין" חסר, שנשמר במטמון ומאונדקס כך.
///
/// לצד נקודות הקוד מוחזר ההיסט הפיזי (FC) של כל תו: הוא המפתח לטבלאות
/// המאפיינים, שמפתחן הוא היסט בזרם ולא מיקום לוגי.
///
/// [cpFrom]–[cpTo] הוא טווח המיקומים הלוגי. גוף המסמך הוא `0..ccpText`, ומיד
/// אחריו יושב תת-מסמך הערות השוליים — אותו piece table משרת את שניהם.
_Text _readCharacters(
  Uint8List stream,
  List<_Piece> pieces,
  int cpFrom,
  int cpTo, {
  required DocumentFormat format,
  String? path,
}) {
  Never fail(String reason) => throw CorruptedDocumentException(
    path: path,
    format: format,
    cause: reason,
  );

  final characters = <int>[];
  final offsets = <int>[];
  if (cpTo <= cpFrom) return _Text(characters, offsets);

  // תקרה גלובלית: טווחי ה-CP שבטבלה אינם חייבים להיות זרים, ולכן חתיכות
  // שכולן מצביעות לאותו קטע מייצרות גידול **ריבועי** בגודל הקובץ. בלי
  // התקרה .doc בן קילובייטים בודדים מקצה ג'יגה-בייטים ומפיל את התהליך.
  final limit = _maxCharacters;
  if (cpTo - cpFrom > limit) {
    fail('המסמך מצהיר על ${cpTo - cpFrom} תווים (מעל התקרה $limit)');
  }

  for (final piece in pieces) {
    if (piece.cpStart >= cpTo) break;
    if (piece.cpEnd <= cpFrom) continue;

    // חיתוך לגבולות הטווח המבוקש בשני הקצוות.
    final skip = cpFrom > piece.cpStart ? cpFrom - piece.cpStart : 0;
    final until = piece.cpEnd > cpTo ? cpTo - piece.cpStart : piece.length;
    final take = until - skip;
    if (take <= 0) continue;

    final stride = piece.isCompressed ? 1 : 2;
    final base = piece.offset + skip * stride;
    final end = base + take * stride;
    if (base < 0 || end > stream.length) {
      fail('חתיכה בהיסט ${piece.offset} חורגת מזרם WordDocument');
    }

    if (characters.length + take > limit) {
      fail('טבלת החתיכות מייצרת יותר מ-$limit תווים');
    }

    if (piece.isCompressed) {
      for (var i = 0; i < take; i++) {
        characters.add(decodeCodepageByte(stream[base + i], 1252));
        offsets.add(base + i);
      }
    } else {
      final view = ByteData.sublistView(stream, base, end);
      for (var i = 0; i < take; i++) {
        characters.add(view.getUint16(i * 2, Endian.little));
        offsets.add(base + i * 2);
      }
    }
  }

  return _Text(characters, offsets);
}

/// תקרת תווים לתת-מסמך יחיד. 50 מיליון תווים הם סדר גודל מעל כל ספר
/// אמיתי, ועדיין חוסמים את הניפוח שטבלת חתיכות זדונית מייצרת.
const int _maxCharacters = 50 * 1000 * 1000;

// ── הערות שוליים ──────────────────────────────────────────────────────────

/// גופי הערות השוליים, ממופים לפי מיקום הסימן שלהן בגוף המסמך (CP).
///
/// הטקסט של ההערות יושב באותו piece table, מיד אחרי גוף המסמך: `PlcffndTxt`
/// נותן את גבולותיו ו-`PlcffndRef` את מיקומי הסימנים בגוף.
///
/// **אינו זורק**: מסמך בלי הערות או עם PLC פגום מאבד הערות בלבד.
Map<int, String> _readFootnotes(
  Uint8List stream,
  Uint8List table,
  List<_Piece> pieces,
  _Fib fib, {
  required DocumentFormat format,
  String? path,
}) {
  if (fib.ccpFtn <= 0 || fib.lcbPlcffndRef <= 4 || fib.lcbPlcffndTxt <= 4) {
    return const {};
  }
  try {
    if (fib.fcPlcffndRef + fib.lcbPlcffndRef > table.length ||
        fib.fcPlcffndTxt + fib.lcbPlcffndTxt > table.length) {
      return const {};
    }

    // PlcffndRef: (n+1) מיקומי CP ואחריהם n מבני FRD בני 2 בתים.
    final refs = ByteData.sublistView(
      table,
      fib.fcPlcffndRef,
      fib.fcPlcffndRef + fib.lcbPlcffndRef,
    );
    final count = (fib.lcbPlcffndRef - 4) ~/ 6;

    // PlcffndTxt: מיקומי CP בלבד, יחסית לתחילת תת-המסמך.
    final texts = ByteData.sublistView(
      table,
      fib.fcPlcffndTxt,
      fib.fcPlcffndTxt + fib.lcbPlcffndTxt,
    );
    final boundaries = fib.lcbPlcffndTxt ~/ 4;
    if (count <= 0 || boundaries < 2) return const {};

    final body = _readCharacters(
      stream,
      pieces,
      fib.ccpText,
      fib.ccpText + fib.ccpFtn,
      format: format,
      path: path,
    );

    final result = <int, String>{};
    for (var i = 0; i < count && i + 1 < boundaries; i++) {
      final from = texts.getUint32(i * 4, Endian.little);
      final to = texts.getUint32((i + 1) * 4, Endian.little);
      if (to <= from || to > body.characters.length) continue;

      final text = _plainText(body.characters.sublist(from, to));
      if (text.isEmpty) continue;
      result[refs.getUint32(i * 4, Endian.little)] = text;
    }
    return result;
  } catch (_) {
    return const {};
  }
}

/// טקסט נקי מרצף תווים: תווי בקרה מושמטים, גבולות פסקה הופכים לרווח,
/// והוראות שדה מושמטות כמו בגוף המסמך.
String _plainText(List<int> characters) {
  final buffer = StringBuffer();
  final fields = _FieldState();
  for (final character in characters) {
    if (fields.consume(character)) continue;
    if (_paragraphBoundaries.contains(character) ||
        character == _charLineBreak) {
      fields.reset();
      buffer.write(' ');
    } else if (!fields.inInstruction &&
        (character >= 0x20 || character == 0x09)) {
      buffer.writeCharCode(character);
    }
  }
  return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// מחסנית השדות הפתוחים (`\13 הוראה \14 תוצאה \15`) — מקור יחיד לגוף
/// המסמך ולטקסט ההערות; בלעדיו `NOTEREF _Ref403498473` זולג לגוף ההערה.
class _FieldState {
  /// `true` = השדה נמצא בחלק ההוראה שלו. שדות מקוננים (`IF { PAGE } = …`)
  /// נפוצים, ודגל בוליאני יחיד נסגר על ה-`\14` הפנימי ומדליף את ההמשך.
  final List<bool> _open = <bool>[];
  int _instructions = 0;

  /// האם הקריאה נמצאת בתוך הוראת שדה — טקסט שאינו חלק מהמסמך הנקרא.
  bool get inInstruction => _instructions > 0;

  /// מעדכן את המחסנית. מחזיר true כש-[character] הוא תו בקרה של שדה.
  bool consume(int character) {
    switch (character) {
      case _charFieldBegin:
        _open.add(true);
        _instructions++;
        return true;
      case _charFieldSeparator:
        if (_open.isNotEmpty && _open.last) {
          _open[_open.length - 1] = false;
          _instructions--;
        }
        return true;
      case _charFieldEnd:
        if (_open.isNotEmpty && _open.removeLast()) _instructions--;
        return true;
    }
    return false;
  }

  /// שדה אינו חוצה גבול פסקה: בלי האיפוס הזה שדה שנפתח ולא נסגר
  /// (קובץ קטוע) בולע את כל שאר המסמך.
  void reset() {
    _open.clear();
    _instructions = 0;
  }
}

/// תווי המסמך וההיסט הפיזי של כל אחד מהם.
class _Text {
  final List<int> characters;
  final List<int> offsets;
  const _Text(this.characters, this.offsets);
}

// ── תווי בקרה של Word ─────────────────────────────────────────────────────

/// placeholder של תמונה מוטמעת. התו עצמו אינו טקסט.
const int _charPicture = 0x01;

const int _charParagraphEnd = 0x0D;
const int _charCellEnd = 0x07;
const int _charLineBreak = 0x0B;
const int _charPageBreak = 0x0C;
const int _charFieldBegin = 0x13;
const int _charFieldSeparator = 0x14;
const int _charFieldEnd = 0x15;
const int _charNonBreakingHyphen = 0x1E;
const int _charOptionalHyphen = 0x1F;
const int _charNonBreakingSpace = 0xA0;

const Set<int> _paragraphBoundaries = {
  _charParagraphEnd,
  _charCellEnd,
  _charPageBreak,
};

/// מרכיב פסקאות מזרם התווים, ומחיל עליהן את שכבת המאפיינים.
///
/// שדות (`\13 הוראה \14 תוצאה \15`) מטופלים כמו ב-Word: ההוראה מושמטת
/// והתוצאה נשמרת — אחרת מחרוזות כמו `HYPERLINK "http://…"` היו מופיעות
/// בגוף הספר.
List<String> _buildParagraphs(
  _Text text,
  LegacyWordProperties properties,
  Map<int, String> footnotes,
  Uint8List? dataStream, {
  required bool embedImages,
  required String footnoteNumFmt,
}) {
  final characters = text.characters;
  final offsets = text.offsets;
  final paragraphs = <String>[];
  var footnoteNumber = 1;

  // ה-HTML של הפסקה הנוכחית, ולצדו טקסט גולמי שטרם עבר escape. ההפרדה
  // מאפשרת לכתוב תגיות (`<br>`) בלי שה-escape יהפוך אותן ל-entity, ובלי
  // placeholder טקסטואלי שתוכן המסמך היה יכול להתנגש בו.
  final html = StringBuffer();
  final raw = StringBuffer();

  // ה-run הנצבר: העיצוב שתחתיו נכתב הטקסט. בלי הצבירה כל תו היה מקבל עותק
  // מלא של התגיות, וההדגשה בחיפוש — שמחפשת רצף — הייתה נשברת.
  var runProperties = LegacyCharacterProperties.plain;

  // תאי השורה הנוכחית ושורות הטבלה שטרם נסגרה.
  final rowCells = <String>[];
  final tableRows = <String>[];

  final fields = _FieldState();

  void flushText() {
    if (raw.isEmpty) return;
    final escaped = escapeHtmlText(raw.toString());
    raw.clear();
    // טקסט מוסתר (`sprmCFVanish`) קיים במסמך ואינו אמור להיראות — הצגתו
    // מזהמת את גוף הספר בהערות עבודה ובאינדקסים פנימיים.
    if (runProperties.hidden) return;
    html.write(
      runProperties.isPlain
          ? escaped
          : '${runProperties.openTags}$escaped${runProperties.closeTags}',
    );
  }

  /// מחליף את עיצוב ה-run הנוכחי, אחרי פריקת מה שנצבר תחת הקודם.
  void useProperties(LegacyCharacterProperties next) {
    if (next == runProperties) return;
    flushText();
    runProperties = next;
  }

  void flushTable() {
    if (tableRows.isEmpty) return;
    paragraphs.add('${otzariaTableOpen()}${tableRows.join()}</table>');
    tableRows.clear();
  }

  /// סוגר את הפסקה הנוכחית. [properties] קובעות אם היא כותרת, תא בטבלה או
  /// פסקה ממורכזת.
  void endParagraph(LegacyParagraphProperties paragraph) {
    flushText();
    final body = html.toString().trim();
    html.clear();

    if (paragraph.inTable) {
      rowCells.add(body);
      return;
    }
    flushTable();
    if (body.replaceAll('<br>', '').trim().isEmpty) return;

    final level = paragraph.headingLevel;
    if (level != null) {
      paragraphs.add('<h$level>$body</h$level>');
      return;
    }
    paragraphs.add(
      paragraph.textAlign == null
          ? body
          : '<div style="text-align: ${paragraph.textAlign};">$body</div>',
    );
  }

  void endRow() {
    if (rowCells.isEmpty) return;
    final cells = rowCells
        .map((cell) => '<td style="$otzariaTableCellStyle">$cell</td>')
        .join();
    tableRows.add('<tr>$cells</tr>');
    rowCells.clear();
  }

  for (var index = 0; index < characters.length; index++) {
    final character = characters[index];
    final fc = index < offsets.length ? offsets[index] : -1;

    // האינדקס הוא ה-CP עצמו — הקריאה מתחילה ב-CP 0 ורצה לפי הסדר הלוגי.
    // הסימן עצמו הוא תו בקרה (0x02) ולכן לא היה מגיע לפלט בלעדי המפה.
    final footnote = footnotes[index];
    if (footnote != null) {
      flushText();
      // סימון ריק (`numFmt` שמבטל מספור) היה מנתק את גוף ההערה
      // מהעוגן שלו בשכבת התצוגה, ולכן חוזר לספרות.
      final number = footnoteNumber++;
      final label = formatWordNumber(number, footnoteNumFmt);
      html.write(
        otzariaFootnote(
          label.isEmpty ? '$number' : label,
          escapeHtmlText(footnote),
        ),
      );
    }

    if (fields.consume(character)) continue;
    if (_paragraphBoundaries.contains(character)) {
      fields.reset();
    } else if (fields.inInstruction) {
      continue;
    }

    switch (character) {
      case _charParagraphEnd:
      case _charPageBreak:
        endParagraph(properties.paragraphAt(fc));
      case _charCellEnd:
        // אותו תו מסיים תא ומסיים שורה; ה-PAPX הוא שמבדיל (`sprmPFTtp`).
        final paragraph = properties.paragraphAt(fc);
        endParagraph(paragraph);
        if (paragraph.isRowEnd || !paragraph.inTable) endRow();
      case _charLineBreak:
        flushText();
        html.write('<br>');
      case _charNonBreakingHyphen:
        raw.write('-');
      case _charOptionalHyphen:
        break; // מקף אופציונלי — ללא ייצוג
      case _charPicture:
        // התמונה עצמה יושבת בזרם `Data`; ה-CHPX של התו הזה מצביע אליה.
        final offset = properties.characterAt(fc).pictureOffset;
        final tag = offset == null || dataStream == null
            ? null
            : legacyWordPictureTag(
                dataStream,
                offset,
                embedImages: embedImages,
              );
        if (tag != null) {
          flushText();
          html.write(tag);
        }
      case _charNonBreakingSpace:
        raw.write(' ');
      default:
        // תווי בקרה נותרים (תמונות, אובייקטים, סימוני הערה) אינם טקסט.
        if (character >= 0x20 || character == 0x09) {
          useProperties(properties.characterAt(fc));
          raw.writeCharCode(character);
        }
    }
  }
  endParagraph(LegacyParagraphProperties.none);
  endRow();
  flushTable();

  return paragraphs;
}
