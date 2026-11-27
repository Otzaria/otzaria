import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:otzaria/data/data_providers/cache_database_holder.dart';
import 'package:otzaria/migration/models/docx_text_cache_entry.dart';
import 'package:otzaria/utils/file/docx_to_otzaria.dart';
import 'package:otzaria/utils/text/html_escape.dart';
import 'package:otzaria/utils/file/document_format.dart';
import 'package:otzaria/utils/file/epub_to_otzaria.dart';
import 'package:otzaria/utils/file/html_to_otzaria.dart';
import 'package:otzaria/utils/file/legacy_word_to_otzaria.dart';
import 'package:otzaria/utils/file/markdown_to_otzaria.dart';
import 'package:otzaria/utils/file/odt_to_otzaria.dart';
import 'package:otzaria/utils/file/rtf_to_otzaria.dart';
import 'package:otzaria/utils/file/word_xml_to_otzaria.dart';

/// משך חיים של רשומת מטמון המרה ללא גישה. רשומות של ספרים שלא נפתחו מעבר
/// לפרק זמן זה מנוקות — כדי ש-`cache.db` לא יגדל ללא הגבלה (כל רשומה מכילה
/// את טקסט הספר המלא, כולל base64 של תמונות).
const Duration _conversionCacheTtl = Duration(days: 90);

/// תדירות מקסימלית לעדכון `accessedAt` (יום). מונע כתיבת WAL בכל פתיחה.
const int _touchThrottleMs = 24 * 60 * 60 * 1000;

final Random _pruneSampler = Random();

/// האם להריץ ניקוי אופורטוניסטי בנתיב cache-hit (הסתברות ~5%). כך מטמון
/// של ספרים שנמחקו/לא-נפתחו מתנקה גם כשאין המרות חדשות, בלי overhead
/// בכל פתיחה.
bool _shouldOpportunisticPrune() => _pruneSampler.nextInt(20) == 0;

/// המרות פעילות לפי קובץ, גרסת ממיר ווריאנט פלט; מונע עבודה כפולה מקבילה
/// לפני שהמטמון נכתב.
final Map<String, Future<String>> _inFlight = {};

/// ממיר מסמך Word מבוסס OOXML (DOCX/DOCM/DOTX/DOTM) לטקסט של אוצריא, עם
/// מטמון מתמשך ב-`cache.db`.
///
/// ההמרה (פירוק XML מלא) יקרה — לאלפי דפים מדובר בשניות בכל פתיחה. המטמון
/// נמנע מכך: מפתח-התוקף הוא גודל הקובץ + זמן-השינוי + גרסת הממיר. אם הקובץ
/// לא השתנה — מחזיר את הטקסט השמור מיידית; אם המשתמש ערך את הקובץ (ספרים
/// אישיים) — הערכים משתנים וההמרה מתבצעת מחדש. כשל מטמון אינו פוגע —
/// נופלים להמרה רגילה.
///
/// הכותרת ([title]) אינה חלק ממפתח המטמון — היא מוזרקת מחדש בכל קריאה
/// (ראו [_withFreshTitle]), כך ששינוי שם הספר אינו פוסל את המטמון אך
/// הכותרת המוצגת תמיד עדכנית.
///
/// הווריאנט חסר-התמונות נשמר במפתח נפרד — הוא נועד ל-TOC ולאינדוקס, ואסור
/// שיוגש למסך הקריאה שבו התמונות נדרשות.
Future<String> convertOoxmlWordWithCache(
  File file,
  String title,
  DocumentFormat format, {
  bool embedImages = true,
}) => _convertWithCache(
  file,
  title,
  kOoxmlWordConverterVersion,
  // הפורמט המדויק עובר לממיר גם במסלול עם התמונות: הוא זה שנרשם בחריגה,
  // ובלעדיו כל כשל של DOCM/DOTX/DOTM מדווח כ-DOCX.
  (bytes, t) =>
      ooxmlWordToText(bytes, t, format: format, embedImages: embedImages),
  cacheVariant: embedImages ? null : 'ooxml-without-images',
);

/// ממיר קובץ EPUB לטקסט של אוצריא — אותו מנגנון מטמון כמו
/// [convertOoxmlWordWithCache] (הרשומות חולקות טבלה; המפתח הוא נתיב הקובץ).
Future<String> convertEpubWithCache(File file, String title) =>
    _convertWithCache(file, title, kEpubConverterVersion, epubToText);

/// ממיר קובץ ODT דרך אותו מטמון.
Future<String> convertOdtWithCache(
  File file,
  String title, {
  bool embedImages = true,
}) => _convertWithCache(
  file,
  title,
  kOdtConverterVersion,
  embedImages
      ? odtToText
      : (bytes, t) => odtToText(bytes, t, embedImages: false),
  cacheVariant: embedImages ? 'odt' : 'odt-without-images',
);

/// ממיר קובץ RTF דרך אותו מטמון.
Future<String> convertRtfWithCache(
  File file,
  String title, {
  bool embedImages = true,
}) => _convertWithCache(
  file,
  title,
  kRtfConverterVersion,
  embedImages
      ? rtfToText
      : (bytes, t) => rtfToText(bytes, t, embedImages: false),
  cacheVariant: embedImages ? 'rtf' : 'rtf-without-images',
);

/// ממיר מסמך HTML עצמאי דרך אותו מטמון.
///
/// תיקיית הקובץ נלכדת כמחרוזת ולא דרך ה-`File`: ה-closure נשלח ל-isolate,
/// ובלעדיה הממיר אינו יודע היכן לחפש תמונות שיושבות לצד המסמך.
Future<String> convertHtmlWithCache(
  File file,
  String title,
  DocumentFormat format, {
  bool embedImages = true,
}) {
  final baseDirectory = file.parent.path;
  return _convertWithCache(
    file,
    title,
    kHtmlConverterVersion,
    // הפורמט המדויק עובר לממיר: הוא זה שנרשם בחריגה, ובלעדיו כל כשל של
    // קובץ .htm מדווח כ-.html.
    (bytes, t) => htmlToText(
      bytes,
      t,
      format: format,
      embedImages: embedImages,
      baseDirectory: baseDirectory,
    ),
    cacheVariant: embedImages ? 'html' : 'html-without-images',
  );
}

/// ממיר מסמך Word שנשמר כ-XML (Flat OPC / WordML 2003) דרך אותו מטמון.
Future<String> convertWordXmlWithCache(
  File file,
  String title, {
  bool embedImages = true,
}) => _convertWithCache(
  file,
  title,
  kWordXmlConverterVersion,
  (bytes, t) => wordXmlToText(bytes, t, embedImages: embedImages),
  cacheVariant: embedImages ? 'word-xml' : 'word-xml-without-images',
);

/// ממיר מסמך Word בינארי ישן (.doc/.dot) דרך אותו מטמון.
Future<String> convertLegacyWordWithCache(
  File file,
  String title,
  DocumentFormat format, {
  bool embedImages = true,
}) {
  // הנתיב נלכד כמחרוזת ולא דרך ה-`File`: ה-closure נשלח ל-isolate, ומחרוזת
  // בטוחה להעברה בעוד שאובייקט אינו מובטח ככזה.
  final path = file.path;
  return _convertWithCache(
    file,
    title,
    kLegacyWordConverterVersion,
    (bytes, t) => legacyWordToText(
      bytes,
      t,
      format: format,
      path: path,
      embedImages: embedImages,
    ),
    cacheVariant: embedImages ? 'legacy-word' : 'legacy-word-without-images',
  );
}

/// ממיר Markdown דרך מטמון ההמרות המשותף ומטמיע תמונות מקומיות לאחר השליפה.
Future<String> convertMarkdownWithCache(File file, String title) async {
  final html = await _convertWithCache(
    file,
    title,
    kMarkdownConverterVersion,
    markdownBytesToHtml,
    cacheVariant: 'markdown',
  );
  return const MarkdownToOtzaria().finalizeCachedHtml(html, file.parent.path);
}

/// ממיר EPUB ללא נתוני התמונות, תוך שימור placeholders ואינדקסי השורות.
/// מיועד ל-TOC, טביעות אצבע ואינדוקס ואינו מקצה מחרוזות Base64 גדולות.
Future<String> convertEpubWithoutEmbeddedImages(File file, String title) =>
    _convertWithCache(
      file,
      title,
      kEpubConverterVersion,
      _epubToTextWithoutEmbeddedImages,
      cacheVariant: 'epub-without-images',
    );

String _epubToTextWithoutEmbeddedImages(Uint8List bytes, String title) =>
    epubToText(bytes, title, embedImages: false);

Future<String> _convertWithCache(
  File file,
  String title,
  int converterVersion,
  String Function(Uint8List, String) converter, {
  String? cacheVariant,
}) async {
  final stat = await file.stat();
  final size = stat.size;
  final mtime = stat.modified.millisecondsSinceEpoch;
  final path = file.path;
  final cachePath = cacheVariant == null ? path : '$path#$cacheVariant';

  // ── נתיב cache-hit ──────────────────────────────────────────────────────
  try {
    final repo = await CacheDatabaseHolder.instance.repository;
    final entry = await repo.getDocxTextCacheEntry(cachePath);
    if (entry != null && entry.isValidFor(size, mtime, converterVersion)) {
      final now = DateTime.now().millisecondsSinceEpoch;
      // throttle: touch לכל היותר פעם ביום (מונע כתיבת WAL בכל פתיחה).
      if (now - entry.accessedAt > _touchThrottleMs) {
        unawaited(
          repo.touchDocxTextCacheEntry(cachePath, now).catchError((_) {}),
        );
      }
      if (_shouldOpportunisticPrune()) {
        unawaited(
          repo
              .pruneDocxTextCacheAccessedBefore(
                now - _conversionCacheTtl.inMilliseconds,
              )
              .catchError((_) {}),
        );
      }
      return _withFreshTitle(entry.text, title);
    }
  } catch (e) {
    debugPrint('⚠️ document cache read failed (falling back to convert): $e');
  }

  // ── נתיב המרה ──────────────────────────────────────────────────────────
  // דה-דופ המרות מקבילות: אם כבר רצה המרה לאותו קובץ, נצרף אליה.
  final key = '$cachePath|$size|$mtime|$converterVersion';
  final pending = _inFlight[key];
  if (pending != null) {
    return _withFreshTitle(await pending, title);
  }

  final future = _convert(path, title, converter);
  _inFlight[key] = future;
  final String text;
  try {
    text = await future;
  } catch (_) {
    _inFlight.remove(key);
    rethrow;
  }

  // השמירה ב-isolate נמשכת שניות; עד סופה פתיחה נוספת מקבלת את הטקסט מכאן.
  unawaited(
    _persist(
      cachePath,
      size,
      mtime,
      converterVersion,
      text,
    ).whenComplete(() => _inFlight.remove(key)),
  );
  return text;
}

/// ההמרה עצמה. ה-bytes נקראים *בתוך* ה-[Isolate.run] (לא לפניו) כדי לא
/// להעתיק buffer גדול (עשרות MB) בין ה-main isolate ל-worker — רק הנתיב
/// והכותרת (מחרוזות קטנות) עוברים.
Future<String> _convert(
  String path,
  String title,
  String Function(Uint8List, String) converter,
) {
  return Isolate.run(() {
    final bytes = File(path).readAsBytesSync();
    return converter(bytes, title);
  });
}

/// שמירת התוצאה במטמון + ניקוי TTL. best-effort — כשל אינו פוגע בטקסט שכבר
/// הוחזר למשתמש.
Future<void> _persist(
  String path,
  int size,
  int mtime,
  int converterVersion,
  String text,
) async {
  try {
    final repo = await CacheDatabaseHolder.instance.repository;
    final now = DateTime.now().millisecondsSinceEpoch;
    await repo.upsertDocxTextCacheEntry(
      DocxTextCacheEntry(
        filePath: path,
        fileSize: size,
        lastModified: mtime,
        converterVersion: converterVersion,
        text: text,
        createdAt: now,
        accessedAt: now,
      ),
    );
    await repo.pruneDocxTextCacheAccessedBefore(
      now - _conversionCacheTtl.inMilliseconds,
    );
  } catch (e) {
    debugPrint('⚠️ document cache write failed (text still returned): $e');
  }
}

/// מחליף את שורת הכותרת (h1, שורה 0 שכל הממירים מייצרים) ב-[title] הנוכחי.
/// כך המטמון נשמר לפי הקובץ ולא לפי שם הספר — שינוי-שם אינו פוסל את
/// המטמון, אך הכותרת המוצגת מתעדכנת מיד. אם הפלט אינו פותח ב-`<h1>`
/// (לא אמור לקרות) — מוחזר כפי שהוא.
@visibleForTesting
String withFreshDocxTitle(String cachedText, String title) =>
    _withFreshTitle(cachedText, title);

String _withFreshTitle(String cachedText, String title) {
  final nl = cachedText.indexOf('\n');
  final head = nl < 0 ? cachedText : cachedText.substring(0, nl);
  if (!head.startsWith('<h1>')) return cachedText;
  // escape כדי ששם קובץ עם `<`/`&` לא ישבור את ה-HTML.
  final fresh = '<h1>${escapeHtmlText(title)}</h1>';
  // ברוב הפתיחות הכותרת לא השתנתה, והעתקה של עשרות MB רק כדי לקבל בחזרה
  // את אותה מחרוזת היא בזבוז נטו.
  if (head == fresh) return cachedText;
  return nl < 0 ? fresh : '$fresh${cachedText.substring(nl)}';
}
