import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;

import 'package:otzaria/utils/file/cfb_reader.dart';
import 'package:otzaria/utils/file/docx_cache.dart';
import 'package:otzaria/utils/file/docx_to_otzaria.dart';
import 'package:otzaria/utils/file/document_conversion_exceptions.dart';
import 'package:otzaria/utils/file/document_format.dart';
import 'package:otzaria/utils/file/epub_to_otzaria.dart';
import 'package:otzaria/utils/file/html_to_otzaria.dart';
import 'package:otzaria/utils/file/legacy_word_to_otzaria.dart';
import 'package:otzaria/utils/file/markdown_to_otzaria.dart';
import 'package:otzaria/utils/file/odt_to_otzaria.dart';
import 'package:otzaria/utils/file/rtf_to_otzaria.dart';
import 'package:otzaria/utils/file/text_encoding.dart';
import 'package:otzaria/utils/file/word_xml_to_otzaria.dart';

/// נקודת ה-dispatch **היחידה** בין פורמט מסמך למנוע ההמרה שלו.
///
/// כל שכבה אחרת (סורק, generator, provider, אינדוקס, UI) שואלת את
/// [DocumentFormat] על תכונות סמנטיות ומגיעה לכאן — אין שרשראות
/// `if (ext == 'docx')` מחוץ לקובץ הזה.

/// ממיר בייטים של מסמך לטקסט אוצריא (HTML קל).
///
/// סינכרוני בכוונה — מיועד לריצה בתוך `Isolate.run`. זורק
/// [UnsupportedDocumentFormatException] לפורמט שאין לו מנוע, ולעולם אינו
/// נופל לקריאה כטקסט: פירוש ZIP/OLE כטקסט מייצר ג'יבריש שנראה כספר תקין.
String convertDocumentBytesSync(
  Uint8List bytes,
  String title, {
  required DocumentFormat format,
  bool embedImages = true,
  String? path,
}) {
  // WBK הוא גיבוי של Word ויכול להיות OOXML או בינארי ישן, ו-.doc נשמר לעתים
  // כ-RTF או OOXML. היישוב נעשה כאן ולא מוטל על הקורא: הבייטים כבר בידינו,
  // וקורא שישכח ליישב יקבל כשל על קובץ תקין.
  final resolved = format.needsContentSniffing || format.isLegacyWord
      ? (resolveDocumentFormat(format, bytes) ?? format)
      : format;

  if (resolved.isOoxmlWord) {
    return ooxmlWordToText(
      bytes,
      title,
      format: resolved,
      embedImages: embedImages,
    );
  }
  if (resolved.isLegacyWord) {
    return legacyWordToText(
      bytes,
      title,
      format: resolved,
      path: path,
      embedImages: embedImages,
    );
  }
  if (resolved.isHtmlDocument) {
    return htmlToText(
      bytes,
      title,
      format: resolved,
      embedImages: embedImages,
      baseDirectory: path == null ? null : p.dirname(path),
    );
  }
  return switch (resolved) {
    DocumentFormat.txt || DocumentFormat.text => _decodeTextBytes(bytes, path),
    DocumentFormat.epub => epubToText(bytes, title, embedImages: embedImages),
    DocumentFormat.md ||
    DocumentFormat.markdown => markdownBytesToHtml(bytes, title),
    DocumentFormat.odt => odtToText(bytes, title, embedImages: embedImages),
    DocumentFormat.rtf => rtfToText(bytes, title, embedImages: embedImages),
    DocumentFormat.xml => wordXmlToText(
      bytes,
      title,
      embedImages: embedImages,
    ),
    // PDF, ו-WBK שתוכנו אינו Word: אין להם מנוע ואין לנחש.
    _ => throw UnsupportedDocumentFormatException(
      path: path,
      format: resolved,
    ),
  };
}

/// ממיר קובץ מסמך מנתיב. קורא את הבייטים בעצמו כדי שאפשר יהיה להריץ את
/// כולה בתוך `Isolate.run` בלי להעביר buffer של עשרות MB בין isolates.
///
/// [format] ריק — נגזר מהסיומת. פורמט שדורש זיהוי-תוכן ([DocumentFormat
/// .needsContentSniffing]) מיושב מול הבייטים בפועל.
String convertDocumentFileSync(
  String filePath, {
  DocumentFormat? format,
  bool embedImages = true,
}) {
  final bytes = File(filePath).readAsBytesSync();
  final declared = format ?? documentFormatFromExtension(filePath);
  final resolved = declared != null && declared.needsContentSniffing
      ? resolveDocumentFormat(declared, bytes)
      : declared;
  if (resolved == null) {
    throw UnsupportedDocumentFormatException(
      path: filePath,
      format: declared,
    );
  }
  final title = _titleFromPath(filePath);
  return convertDocumentBytesSync(
    bytes,
    title,
    format: resolved,
    embedImages: embedImages,
    path: filePath,
  );
}

/// ממיר קובץ מסמך דרך מטמון ההמרות המתמשך.
///
/// זהו הנתיב שכל קריאה ב-runtime עוברת בו (פתיחת ספר, TOC, אינדוקס), ולכן
/// כאן מרוכזת גם ההחלטה איזה וריאנט מטמון משמש כל פורמט.
Future<String> convertDocumentWithCache(
  File file,
  String title,
  DocumentFormat format, {
  bool embedImages = true,
}) async {
  // WBK ו-.doc אינם מסגירים את המנוע — רק התוכן מכריע. אותו יישוב בדיוק
  // כמו ב-[convertDocumentBytesSync]: בלעדיו שני מסלולי הכניסה מתנהגים הפוך
  // זה מזה על אותו קובץ.
  final resolved = format.needsContentSniffing || format.isLegacyWord
      ? resolveDocumentFormat(format, await _readSniffWindow(file))
      : format;
  if (resolved == null) {
    throw UnsupportedDocumentFormatException(path: file.path, format: format);
  }

  if (resolved.isOoxmlWord) {
    return convertOoxmlWordWithCache(
      file,
      title,
      resolved,
      embedImages: embedImages,
    );
  }
  if (resolved.isLegacyWord) {
    return convertLegacyWordWithCache(
      file,
      title,
      resolved,
      embedImages: embedImages,
    );
  }
  if (resolved.isHtmlDocument) {
    return convertHtmlWithCache(
      file,
      title,
      resolved,
      embedImages: embedImages,
    );
  }
  return switch (resolved) {
    DocumentFormat.txt || DocumentFormat.text => _readPlainTextFile(file),
    DocumentFormat.epub =>
      embedImages
          ? convertEpubWithCache(file, title)
          : convertEpubWithoutEmbeddedImages(file, title),
    DocumentFormat.md ||
    DocumentFormat.markdown => convertMarkdownWithCache(file, title),
    DocumentFormat.odt => convertOdtWithCache(
      file,
      title,
      embedImages: embedImages,
    ),
    DocumentFormat.rtf => convertRtfWithCache(
      file,
      title,
      embedImages: embedImages,
    ),
    DocumentFormat.xml => convertWordXmlWithCache(
      file,
      title,
      embedImages: embedImages,
    ),
    _ => throw UnsupportedDocumentFormatException(
      path: file.path,
      format: format,
    ),
  };
}

/// גודל חלון זיהוי-התוכן. נקראים ראש הקובץ *וזנבו*: החתימות יושבות בראש,
/// אבל שמות הרשומות של חבילת ZIP מרוכזים ב-central directory שבסוף.
const int _sniffWindowBytes = 256 * 1024;

/// האם הקובץ נאסף כספר בסריקת תיקייה.
///
/// מרחיב את [isSupportedBookFile] בשער תוכן לפורמטים שסיומתם אינה מספיקה
/// (.xml, .wbk): .xml היא סיומת גנרית, ובלי השער כל קובץ הגדרות בתיקייה
/// שנסרקת היה נאסף כ"ספר" ונכשל בפתיחה.
///
/// שגיאת קריאה מחזירה `false` — קובץ שאי אפשר לקרוא אינו ספר, וסריקה אינה
/// נופלת בגללו (§76).
Future<bool> isSupportedBookFileByContent(String filePath) async {
  final format = documentFormatFromExtension(filePath);
  if (format == null || !format.isProductionSupported) return false;
  if (!format.needsContentSniffing) return true;
  try {
    final file = File(filePath);
    final window = await _readSniffWindow(file);
    final resolved = resolveDocumentFormat(format, window);
    if (resolved == null) return false;
    if (format != DocumentFormat.wbk || !resolved.isLegacyWord) return true;

    // חתימת OLE משותפת גם ל-Excel ול-Outlook; רק זרם WordDocument מאשר WBK.
    return isLegacyWordContainer(await file.readAsBytes(), path: filePath);
  } catch (_) {
    return false;
  }
}

/// קורא את הטקסט של ספר שתוכנו יושב בקובץ חיצוני.
///
/// מחזיר `null` עבור PDF — הוא file-backed אך אינו טקסט, והקוראים שלו
/// עוברים בצנרת נפרדת.
///
/// כששם הקובץ אינו מזהה פורמט, ההכרעה נעשית לפי תוכנו ולא בקריאה עיוורת
/// כטקסט: מכולה בינארית (ZIP/OLE) שנקראת כטקסט מייצרת ג'יבריש שנראה
/// כספר תקין.
Future<String?> readFileBackedBookText(
  File file,
  String? fileType,
  String title, {
  bool embedImages = true,
}) async {
  final format =
      documentFormatOf(fileType: fileType, path: file.path) ??
      await _sniffFormat(file);
  if (format == null) {
    throw UnsupportedDocumentFormatException(path: file.path);
  }
  if (!format.isTextual) return null;
  return convertDocumentWithCache(
    file,
    title,
    format,
    embedImages: embedImages,
  );
}

/// מזהה פורמט לפי תוכן הקובץ.
///
/// קובץ שאינו מכולה בינארית מוכרת נחשב לטקסט רגיל — כך קובץ ללא סיומת ממשיך
/// להיקרא כמקודם. מכולה בינארית שלא זוהתה מחזירה `null` ולא `txt`: פירושה
/// כטקסט מייצר ג'יבריש שנראה כספר תקין.
Future<DocumentFormat?> _sniffFormat(File file) async {
  final window = await _readSniffWindow(file);
  return detectDocumentFormatFromContentSync(window) ??
      (isBinaryContainerHeader(window) ? null : DocumentFormat.txt);
}

/// קורא קובץ טקסט, אחרי שאימת שאינו מכולה בינארית. נקראים 8 בתים בלבד,
/// כדי לא לטעון קובץ שלם רק לצורך הבדיקה.
Future<String> _readPlainTextFile(File file) async {
  _assertNotBinaryContainer(await _readFileHead(file, 8), file.path);
  return _textOf(await readTextFileSmartDetailed(file), file.path);
}

String _decodeTextBytes(Uint8List bytes, String? path) {
  _assertNotBinaryContainer(bytes, path);
  return _textOf(decodeTextBytesSmartDetailed(bytes), path);
}

/// זיהוי קידוד לא-ודאי נרשם ללוג: הסימפטום שלו — ספר שנראה ג'יבריש — אינו
/// מבחין את עצמו בשום שכבה אחרת, ובלי הרישום אין דרך לאבחן דיווח כזה.
String _textOf(TextDecodingResult result, String? path) {
  if (result.lowConfidence) {
    debugPrint(
      '⚠️ זיהוי קידוד בוודאות נמוכה ל-$path: ${result.encoding.label} '
      '(${result.confidence.toStringAsFixed(2)}) — ${result.detectionReason}',
    );
  }
  return result.text;
}

/// שכבת ההגנה האחרונה לפני פענוח כטקסט: הפענוח אינו זורק לעולם — כל בית
/// מתפרש כ-Windows-1255 — ולכן ZIP/OLE שהגיע לכאן בטעות היה נשמר כספר
/// ג'יבריש במטמון ובאינדקס, בלי שום סימן לתקלה.
void _assertNotBinaryContainer(Uint8List head, String? path) {
  if (!isBinaryContainerHeader(head)) return;
  throw UnsupportedDocumentFormatException(
    path: path,
    format: DocumentFormat.txt,
    cause: 'הקובץ הוא מכולה בינארית ואינו טקסט',
  );
}

Future<Uint8List> _readFileHead(File file, int length) async {
  final handle = await file.open();
  try {
    return await handle.read(length);
  } finally {
    await handle.close();
  }
}

/// קורא את ראש הקובץ ואת זנבו כבלוק אחד רצוף, לצורכי זיהוי-תוכן.
Future<Uint8List> _readSniffWindow(File file) async {
  final handle = await file.open();
  try {
    final head = await handle.read(_sniffWindowBytes);
    final length = await file.length();
    if (length <= _sniffWindowBytes) return head;

    await handle.setPosition(length - _sniffWindowBytes);
    final tail = await handle.read(_sniffWindowBytes);
    return Uint8List(head.length + tail.length)
      ..setRange(0, head.length, head)
      ..setRange(head.length, head.length + tail.length, tail);
  } finally {
    await handle.close();
  }
}

/// ממיר לצורכי אינדוקס ו-TOC — בלי להטמיע תמונות. חוסך הקצאת מחרוזות
/// base64 של עשרות MB בזיכרון עבור תוכן שאיש אינו רואה.
///
/// הווריאנט חסר-התמונות משמר את **מספר השורות** בדיוק (התג נשאר, רק ה-URI
/// מתרוקן) — בלי זה אינדקסי ה-TOC היו זזים מול התוכן שהקורא רואה.
Future<String> convertDocumentForIndex(
  File file,
  String title,
  DocumentFormat format,
) {
  // לפורמט שאין לו וריאנט חסר-תמונות אין ברירה אלא הפלט המלא; ניקוי ה-data
  // URI נעשה אז אצל הקורא (`stripDataUrisForIndex`).
  return convertDocumentWithCache(
    file,
    title,
    format,
    embedImages: !format.supportsImageFreeConversion,
  );
}

/// גרסת הממיר שמטפל בפורמט. חלק ממפתח-התוקף של המטמון, ולכן נדרשת בכל
/// דיווח כשל — בלעדיה אי אפשר לדעת איזו גרסת קוד ייצרה את הפלט.
///
/// לפורמט שמנועו נקבע לפי תוכן (.wbk) אין גרסה משל עצמו — יש להעביר את
/// הפורמט **שזוהה**, זה שנשמר בחריגה.
int? converterVersionFor(DocumentFormat? format) {
  if (format == null) return null;
  if (format.isOoxmlWord) return kOoxmlWordConverterVersion;
  if (format.isLegacyWord) return kLegacyWordConverterVersion;
  if (format.isHtmlDocument) return kHtmlConverterVersion;
  return switch (format) {
    DocumentFormat.epub => kEpubConverterVersion,
    DocumentFormat.md || DocumentFormat.markdown => kMarkdownConverterVersion,
    DocumentFormat.odt => kOdtConverterVersion,
    DocumentFormat.rtf => kRtfConverterVersion,
    DocumentFormat.xml => kWordXmlConverterVersion,
    _ => null,
  };
}

String _titleFromPath(String filePath) {
  final sep = filePath.lastIndexOf(RegExp(r'[/\\]'));
  final name = sep < 0 ? filePath : filePath.substring(sep + 1);
  final dot = name.lastIndexOf('.');
  return dot <= 0 ? name : name.substring(0, dot);
}
