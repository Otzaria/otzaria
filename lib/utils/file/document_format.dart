import 'dart:typed_data';

import 'package:otzaria/data/data_providers/book_composite_key.dart';

/// פורמט המסמך של ספר — מקור האמת היחיד לשאלות "האם צריך המרה", "האם יש
/// טקסט לאינדוקס", "איזה מנוע ממיר" וכו'.
///
/// כל ערך מייצג *סיומת* אחת בדיוק, ולא משפחה: `docm` אינו `docx` גם אם שני
/// הפורמטים עוברים את אותו מנוע OOXML. הסיבה: `fileType` הוא חלק מזהות הספר
/// ([BookCompositeKey]) ומשמש ב-provider lookup, במטמון, ב-dedup, באינדקס
/// ובסיריאליזציה של טאבים — מיפוי `docm → docx` היה שובר זהות של ספרים
/// קיימים.
enum DocumentFormat {
  txt,
  text,
  pdf,
  epub,

  /// שתי סיומות Markdown נפרדות; שתיהן נשמרות כ-`fileType` נבדל מאותה סיבה.
  md,
  markdown,

  docx,
  docm,
  dotx,
  dotm,

  doc,
  dot,
  wbk,

  /// מסמך Word שנשמר כ-XML — Flat OPC או WordprocessingML 2003. הסיומת
  /// גנרית, ולכן הפורמט מזוהה תמיד לפי תוכנו (ראו [needsContentSniffing]).
  xml,

  rtf,
  odt,

  /// שתי סיומות HTML נפרדות; שתיהן עוברות את אותו מנוע ונשמרות כ-`fileType`
  /// נבדל, מאותה סיבה כמו `md`/`markdown`.
  html,
  htm,
  xhtml,
}

/// תכונות סמנטיות של פורמט. כל predicate מתאר מציאות *אחת* — אין כאן
/// כפילויות של אותו ערך אמת בשמות שונים (ראו `isTextual` להלן).
extension DocumentFormatProperties on DocumentFormat {
  /// הסיומת הקנונית ללא נקודה. זהה ל-`fileType` שנשמר ב-DB.
  String get extension => name;

  /// הסיומת עם נקודה, לשימוש בהשוואות מול `path.extension`.
  String get dottedExtension => '.$name';

  /// האם מהפורמט נגזר טקסט לקריאה, לתוכן עניינים ולאינדוקס.
  ///
  /// זהו ה-predicate היחיד לשלוש השאלות האלה — הן תמיד זהות: PDF הוא
  /// היחיד שאין ממנו טקסט, והוא בונה תוכן עניינים מה-outline שלו במסלול
  /// נפרד ואינו נכנס לאינדקס הטקסטואלי.
  bool get isTextual => this != DocumentFormat.pdf;

  /// האם קריאת הקובץ כטקסט אינה מספיקה ונדרש ממיר ייעודי.
  ///
  /// PDF הוא `false` — לא מפני שהוא טקסט, אלא מפני שאין לו ממיר-לטקסט
  /// בצנרת הזו כלל. תמיד יש לבדוק `isTextual` לפני שמסיקים מכאן.
  bool get requiresConversion => switch (this) {
    DocumentFormat.txt || DocumentFormat.text || DocumentFormat.pdf => false,
    _ => true,
  };

  /// האם הפורמט ממודל כספר-מסמך ([ConvertibleDocumentBook]) ולא כ-TextBook.
  ///
  /// Markdown דורש המרה אך נשאר TextBook — הקורא מקבל ממנו HTML דרך
  /// `getBookText`, ואין לו התנהגות נבדלת שמצדיקה מחלקה. זהו גם ה-predicate
  /// שקובע את זהות הספר מול תוספים, ולכן שני המקומות חייבים לחלוק אותו.
  bool get isDocumentBook =>
      requiresConversion &&
      this != DocumentFormat.md &&
      this != DocumentFormat.markdown;

  /// Word מודרני מבוסס OOXML — כולם עוברים את אותו מנוע המרה.
  bool get isOoxmlWord => switch (this) {
    DocumentFormat.docx ||
    DocumentFormat.docm ||
    DocumentFormat.dotx ||
    DocumentFormat.dotm => true,
    _ => false,
  };

  /// Word בינארי ישן (OLE Compound File).
  bool get isLegacyWord =>
      this == DocumentFormat.doc || this == DocumentFormat.dot;

  /// מסמך HTML עצמאי — .html ו-.htm עוברים את אותו מנוע המרה.
  bool get isHtmlDocument =>
      this == DocumentFormat.html ||
      this == DocumentFormat.htm ||
      this == DocumentFormat.xhtml;

  /// האם המסמך הוא חבילת ZIP — קובע את מגבלות ה-decompression (ראו
  /// `zip_limits.dart`) ואת אופן זיהוי התוכן.
  bool get isZipPackage =>
      isOoxmlWord || this == DocumentFormat.epub || this == DocumentFormat.odt;

  /// האם שורות התוכן יכולות להישמר ב-DB במקום להיקרא מהקובץ בכל פתיחה.
  /// רק TXT — כל השאר file-backed תמיד, כי תוכנם דורש המרה בזמן קריאה.
  bool get canStoreLinesInDb => isPlainText;

  /// Plain text files. Both the modern `.txt` and legacy `.text` extensions
  /// use the same decoding, rendering, indexing and storage pipeline.
  bool get isPlainText =>
      this == DocumentFormat.txt || this == DocumentFormat.text;

  /// האם הפורמט יכול להכיל תמונות מוטמעות שיש להמיר ל-data URI.
  bool get supportsEmbeddedImages => switch (this) {
    DocumentFormat.txt || DocumentFormat.text || DocumentFormat.pdf => false,
    _ => true,
  };

  /// האם הממיר תומך ב-`embedImages: false` — המרה חסכונית לאינדוקס ול-TOC,
  /// שאינה מקצה מחרוזות base64 של עשרות MB.
  bool get supportsImageFreeConversion =>
      supportsEmbeddedImages &&
      this != DocumentFormat.md &&
      this != DocumentFormat.markdown;

  /// האם *חובה* לזהות את התוכן כדי לנתב — הסיומת לבדה אינה מספיקה.
  ///
  /// WBK הוא גיבוי של Word ויכול להיות OOXML או בינארי ישן. .xml היא סיומת
  /// גנרית: רוב קובצי ה-XML בעולם אינם מסמכי Word, ובלי בדיקת תוכן כל קובץ
  /// הגדרות בתיקייה היה נאסף כ"ספר".
  bool get needsContentSniffing =>
      this == DocumentFormat.wbk || this == DocumentFormat.xml;

  /// האם הפורמט פעיל למשתמשי production. פורמט שיש לו ערך ב-enum אך אין לו
  /// עדיין ממיר בשל — נשאר `false` ואינו מופיע ב-FilePicker ובסורק.
  bool get isProductionSupported => kProductionBookFormats.contains(this);

  /// מסמך Word — OOXML, בינארי ישן, גיבוי, או מסמך שנשמר כ-XML. **מקור
  /// יחיד** למשפחה: ממנו נגזרים גם תווית התצוגה וגם אייקון הספר.
  bool get isWordDocument =>
      isOoxmlWord ||
      isLegacyWord ||
      this == DocumentFormat.wbk ||
      this == DocumentFormat.xml;

  /// שם משפחה לתצוגה ב-UI. אין להסיק ממנו `fileType`.
  String get familyLabel => isWordDocument
      ? 'Word'
      : switch (this) {
          DocumentFormat.pdf => 'PDF',
          DocumentFormat.epub => 'EPUB',
          DocumentFormat.md || DocumentFormat.markdown => 'Markdown',
          DocumentFormat.rtf => 'RTF',
          DocumentFormat.odt => 'ODT',
          DocumentFormat.html ||
          DocumentFormat.htm ||
          DocumentFormat.xhtml => 'HTML',
          _ => 'טקסט',
        };
}

/// הפורמטים הפעילים ל-production. זהו **מקור האמת היחיד** לרשימות סיומות
/// בסורק, ב-FilePicker, בסנכרון הקבצים ובייבוא ספרים אישיים.
///
/// פורמט נכנס לכאן רק אחרי שהממיר שלו עבר את כל השרשרת (סריקה → פתיחה →
/// TOC → אינדוקס → restart), ולא ברגע שנוסף ערך ב-[DocumentFormat].
const Set<DocumentFormat> kProductionBookFormats = {
  DocumentFormat.txt,
  DocumentFormat.text,
  DocumentFormat.pdf,
  DocumentFormat.epub,
  DocumentFormat.md,
  DocumentFormat.markdown,

  // כל פורמטי OOXML של Word חולקים את אותו מנוע המרה בדוק (ראו
  // `docx_golden_test.dart` — שקילות בין הפורמטים).
  DocumentFormat.docx,
  DocumentFormat.docm,
  DocumentFormat.dotx,
  DocumentFormat.dotm,

  DocumentFormat.odt,
  DocumentFormat.rtf,

  // Word בינארי ישן. WBK הוא גיבוי שיכול להיות כל אחד מהשניים, ולכן הוא
  // מיושב לפי תוכן ולא לפי הסיומת.
  DocumentFormat.doc,
  DocumentFormat.dot,
  DocumentFormat.wbk,

  // מסמך Word שנשמר כ-XML. נאסף בסריקה רק אם תוכנו אכן מסמך Word.
  DocumentFormat.xml,

  // שתי סיומות ה-HTML, אותו מנוע.
  DocumentFormat.html,
  DocumentFormat.htm,
  DocumentFormat.xhtml,
};

/// סיומות הספרים הנתמכות (ללא נקודה), נגזרות מ-[kProductionBookFormats].
final List<String> kSupportedBookExtensions = List.unmodifiable(
  kProductionBookFormats.map((f) => f.extension).toList()..sort(),
);

/// סיומות הספרים הנתמכות עם נקודה — לשימוש מול `path.extension`.
final List<String> kSupportedDottedBookExtensions = List.unmodifiable(
  kProductionBookFormats.map((f) => f.dottedExtension).toList()..sort(),
);

/// גוזר פורמט מ-`fileType` שנשמר ב-DB. משתמש בנרמול היחיד של המערכת
/// ([BookCompositeKey.normalizeFileType]) — אין נרמול מקביל.
DocumentFormat? documentFormatFromFileType(String? fileType) {
  return _byExtension[BookCompositeKey.normalizeFileType(fileType)];
}

/// גוזר פורמט מסיומת של נתיב קובץ. מטפל בנתיבים עם כמה נקודות
/// (`a.b.docx`) ובאותיות גדולות (`.DOCX`).
DocumentFormat? documentFormatFromExtension(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0 || dot == path.length - 1) return null;
  final sep = path.lastIndexOf(RegExp(r'[/\\]'));
  if (dot < sep) return null; // הנקודה בתיקייה, לא בשם הקובץ
  return _byExtension[path.substring(dot + 1).toLowerCase()];
}

/// גוזר פורמט מספר קיים: `fileType` קודם, ובהיעדרו הסיומת של הנתיב.
///
/// חריג אחד: `txt` הוא ברירת המחדל של העמודה ב-DB (`fileType TEXT DEFAULT
/// 'txt'`) ולא הצהרה של מישהו, ולכן סיומת שאומרת אחרת גוברת עליו. בלי החריג
/// ספר .docx שרשומתו נשארה על ברירת המחדל נקרא כטקסט — כלומר ג'יבריש
/// שנראה כספר תקין.
DocumentFormat? documentFormatOf({String? fileType, String? path}) {
  final byExtension = path == null ? null : documentFormatFromExtension(path);
  final declared = (fileType ?? '').trim();
  if (declared.isNotEmpty) {
    final byType = documentFormatFromFileType(declared);
    if (byType != null) {
      if (byType != DocumentFormat.txt || byExtension == null) return byType;
      return byExtension;
    }
  }
  return byExtension;
}

/// האם הקובץ נסרק כספר. מחליף כל רשימת-סיומות מקומית בסורקים.
bool isSupportedBookFile(String path) {
  final format = documentFormatFromExtension(path);
  return format != null && format.isProductionSupported;
}

final Map<String, DocumentFormat> _byExtension = {
  for (final format in DocumentFormat.values) format.extension: format,
};

// ── זיהוי לפי תוכן ────────────────────────────────────────────────────────

/// חתימות בינאריות בתחילת הקובץ.
const List<int> _zipSignature = [0x50, 0x4B, 0x03, 0x04];
const List<int> _oleSignature = [
  0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, //
];
const List<int> _pdfSignature = [0x25, 0x50, 0x44, 0x46]; // %PDF
const List<int> _rtfSignature = [0x7B, 0x5C, 0x72, 0x74, 0x66]; // {\rtf

/// מזהה פורמט לפי *תוכן* הקובץ בלבד, בלי להסתמך על שם הקובץ.
///
/// גרסה סינכרונית — בטוחה לקריאה בתוך isolate. מחזירה `null` כשהתוכן אינו
/// אחד מהפורמטים הבינאריים המוכרים (למשל טקסט רגיל).
///
/// הזיהוי הוא ברמת *משפחה* ודי לו בכותרת הקובץ: חתימת OLE מוחזרת כ-`doc`
/// אף ש-.xls ו-.msg נושאים אותה חתימה בדיוק. להבחנה מדויקת נדרש פענוח
/// המכולה — ראו `isLegacyWordContainer` ב-`cfb_reader.dart`, שדורש את
/// הקובץ המלא ולכן אינו חלק מהמסלול המהיר הזה.
DocumentFormat? detectDocumentFormatFromContentSync(Uint8List bytes) {
  if (_startsWith(bytes, _pdfSignature)) return DocumentFormat.pdf;
  if (_startsWith(bytes, _rtfSignature)) return DocumentFormat.rtf;
  if (_startsWith(bytes, _oleSignature)) return DocumentFormat.doc;
  if (_startsWith(bytes, _zipSignature)) return _sniffZipPackage(bytes);
  if (sniffWordXmlDialect(bytes) != null) return DocumentFormat.xml;
  return null;
}

/// שני הדיאלקטים שבהם Word שומר מסמך כקובץ .xml יחיד.
enum WordXmlDialect {
  /// Flat OPC — חבילת OOXML שלמה שנשטחה לקובץ אחד (`pkg:package`).
  flatOpc,

  /// WordprocessingML 2003 — מסמך יחיד עם שורש `w:wordDocument`.
  wordMl2003,
}

/// שם השורש → דיאלקט. ההשוואה היא לשם ה**מקומי**: הקידומת אינה מובטחת.
const Map<String, WordXmlDialect> _wordXmlRoots = {
  'package': WordXmlDialect.flatOpc,
  'wordDocument': WordXmlDialect.wordMl2003,
};

WordXmlDialect? wordXmlDialectForRootName(String localName) =>
    _wordXmlRoots[localName];

/// מזהה מסמך Word שנשמר כ-XML, בלי לפרסר את הקובץ כולו.
///
/// .xml היא סיומת גנרית, ולכן זהו התנאי היחיד שמכניס קובץ כזה לספרייה:
/// בלעדיו כל קובץ הגדרות בתיקייה שנסרקת היה נאסף כ"ספר" ונכשל בהמרה.
WordXmlDialect? sniffWordXmlDialect(Uint8List bytes) {
  // השורש יושב בראש הקובץ, אחרי הצהרת ה-XML וההוראות; חלון קטן מספיק.
  final limit = bytes.length < _xmlSniffWindow ? bytes.length : _xmlSniffWindow;
  final head = String.fromCharCodes(bytes, 0, limit);
  for (final match in _xmlTagPattern.allMatches(head)) {
    final dialect = _wordXmlRoots[match.group(2)];
    if (dialect != null) return dialect;
  }
  return null;
}

const int _xmlSniffWindow = 8 * 1024;

/// תג פתיחה, עם קידומת namespace אופציונלית. שם התג הוא ASCII, ולכן
/// הקריאה כ-code units בטוחה גם על בייטים של UTF-8.
final RegExp _xmlTagPattern = RegExp(r'<(?:([\w.-]+):)?([\w.-]+)[\s>]');

/// מיישב בין הפורמט שהסיומת הצהירה עליו לבין מה שהתוכן מראה.
///
/// כלל ההכרעה: הסיומת קובעת כל עוד היא ומה שנמצא בקובץ שייכים לאותו מנוע
/// המרה — כך `docm` נשאר `docm` ולא הופך ל-`docx` רק מפני ששניהם OOXML.
///
/// אינה קוראת מהדיסק — ה-[bytes] מועברים בידי הקורא, כדי שהקריאה תתבצע
/// בתוך אותו isolate של ההמרה.
DocumentFormat? resolveDocumentFormat(
  DocumentFormat? declared,
  Uint8List bytes,
) {
  final detected = detectDocumentFormatFromContentSync(bytes);
  if (declared == null) return detected;
  if (detected == null) {
    // תוכן שאינו מוכר: חבילת ZIP שיקרה לגבי עצמה, ופורמט שסיומתו גנרית
    // (.xml, .wbk) לא הוכיח שהוא מסמך בכלל. .doc נשאר doc — מנוע Word
    // הישן הוא שמדווח עליו "פגום".
    return declared.isZipPackage || declared.needsContentSniffing
        ? null
        : declared;
  }
  if (_sameEngine(declared, detected)) return declared;
  return detected;
}

bool _sameEngine(DocumentFormat a, DocumentFormat b) {
  if (a == b) return true;
  if (a.isOoxmlWord && b.isOoxmlWord) return true;
  if (a.isLegacyWord && b.isLegacyWord) return true;
  if (a.isHtmlDocument && b.isHtmlDocument) return true;
  return false;
}

/// מבחין בין חבילות ZIP. שמות הרשומות ב-ZIP אינם דחוסים, ולכן חיפוש בייטים
/// ישיר מספיק ואינו דורש פריסה של הארכיון (שיקול אבטחה — ראו zip bomb).
DocumentFormat? _sniffZipPackage(Uint8List bytes) {
  if (_containsAscii(bytes, 'word/document.xml')) return DocumentFormat.docx;
  if (_containsAscii(bytes, 'application/vnd.oasis.opendocument.text') ||
      (_containsAscii(bytes, 'content.xml') &&
          _containsAscii(bytes, 'META-INF/manifest.xml'))) {
    return DocumentFormat.odt;
  }
  if (_containsAscii(bytes, 'META-INF/container.xml') ||
      _containsAscii(bytes, 'application/epub+zip')) {
    return DocumentFormat.epub;
  }
  return null;
}

/// האם הבייטים פותחים בחתימת מכולת OLE/CFB.
///
/// גם מסמך Office **מודרני** ומוצפן נשמר כמכולת OLE (עם זרם `EncryptedPackage`)
/// ולא כ-ZIP — ולכן זו גם הדרך לזהות DOCX מוצפן.
bool hasOleContainerSignature(Uint8List bytes) =>
    _startsWith(bytes, _oleSignature);

/// האם הבייטים פותחים בחתימת מכולה בינארית מוכרת.
///
/// מכולה שלא זוהתה לפורמט ספציפי **אסור** שתיקרא כטקסט: פירוש בייטי ZIP/OLE
/// כ-Windows-1255 מייצר ג'יבריש עברי שנראה כספר תקין לגמרי.
bool isBinaryContainerHeader(Uint8List bytes) =>
    _startsWith(bytes, _zipSignature) ||
    _startsWith(bytes, _oleSignature) ||
    _startsWith(bytes, _pdfSignature);

bool _startsWith(Uint8List bytes, List<int> signature) {
  if (bytes.length < signature.length) return false;
  for (var i = 0; i < signature.length; i++) {
    if (bytes[i] != signature[i]) return false;
  }
  return true;
}

/// חיפוש מחרוזת ASCII ב-[window] הבייטים הראשונים וב-[window] האחרונים.
///
/// שני חלונות ולא סריקה מלאה, כדי שהזיהוי יישאר זול על קבצים של עשרות MB.
/// הזנב חיוני: שמות הרשומות של חבילת ZIP מרוכזים ב-central directory שבסופה,
/// ולכן DOCX שנפתח בתמונה גדולה אינו מזוהה מהראש בלבד.
bool _containsAscii(Uint8List bytes, String needle, {int window = 1 << 20}) {
  if (_containsAsciiIn(bytes, needle, 0, bytes.length.clamp(0, window))) {
    return true;
  }
  if (bytes.length <= window) return false;
  return _containsAsciiIn(bytes, needle, bytes.length - window, bytes.length);
}

bool _containsAsciiIn(Uint8List bytes, String needle, int from, int to) {
  final target = needle.codeUnits;
  if (target.isEmpty || to - from < target.length) return false;
  final first = target[0];
  final last = to - target.length;
  outer:
  for (var i = from; i <= last; i++) {
    if (bytes[i] != first) continue;
    for (var j = 1; j < target.length; j++) {
      if (bytes[i + j] != target[j]) continue outer;
    }
    return true;
  }
  return false;
}
