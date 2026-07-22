import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:otzaria/data/data_providers/cache_database_holder.dart';
import 'package:otzaria/migration/models/docx_text_cache_entry.dart';
import 'package:otzaria/utils/file/docx_to_otzaria.dart';
import 'package:otzaria/utils/file/epub_to_otzaria.dart';

/// משך חיים של רשומת מטמון המרה (docx/epub) ללא גישה. רשומות של ספרים שלא
/// נפתחו מעבר לפרק זמן זה מנוקות — כדי ש-`cache.db` לא יגדל ללא הגבלה (כל
/// רשומה מכילה את טקסט הספר המלא, כולל base64 של תמונות).
const Duration _docxCacheTtl = Duration(days: 90);

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

/// ממיר קובץ docx חיצוני לטקסט של אוצריא, עם מטמון מתמשך ב-`cache.db`.
///
/// ההמרה (פירוק XML מלא ב-[docxToText]) יקרה — לאלפי דפים מדובר בשניות בכל
/// פתיחה. המטמון נמנע מכך: מפתח-התוקף הוא גודל הקובץ + זמן-השינוי + גרסת
/// הממיר. אם הקובץ לא השתנה — מחזיר את הטקסט השמור מיידית; אם המשתמש ערך
/// את הקובץ (ספרים אישיים) — הערכים משתנים וההמרה מתבצעת מחדש. כך הטריות
/// נשמרת. כשל מטמון אינו פוגע — נופלים להמרה רגילה.
///
/// הכותרת ([title]) אינה חלק ממפתח המטמון — היא מוזרקת מחדש בכל קריאה
/// (ראו [_withFreshTitle]), כך ששינוי שם הספר אינו פוסל את המטמון אך
/// הכותרת המוצגת תמיד עדכנית.
Future<String> convertDocxWithCache(File file, String title) =>
    _convertWithCache(file, title, kDocxConverterVersion, docxToText);

/// ממיר קובץ EPUB לטקסט של אוצריא — אותו מנגנון מטמון כמו
/// [convertDocxWithCache] (הרשומות חולקות טבלה; המפתח הוא נתיב הקובץ).
Future<String> convertEpubWithCache(File file, String title) =>
    _convertWithCache(file, title, kEpubConverterVersion, epubToText);

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
                now - _docxCacheTtl.inMilliseconds,
              )
              .catchError((_) {}),
        );
      }
      return _withFreshTitle(entry.text, title);
    }
  } catch (e) {
    debugPrint('⚠️ docx cache read failed (falling back to convert): $e');
  }

  // ── נתיב המרה ──────────────────────────────────────────────────────────
  // דה-דופ המרות מקבילות: אם כבר רצה המרה לאותו קובץ, נצרף אליה.
  final key = '$cachePath|$size|$mtime|$converterVersion';
  final pending = _inFlight[key];
  if (pending != null) return _withFreshTitle(await pending, title);

  final future = _convert(path, title, converter);
  _inFlight[key] = future;
  final String text;
  try {
    text = await future;
  } finally {
    _inFlight.remove(key);
  }

  // שמירה ברקע (fire-and-forget): הטקסט כבר מוכן, אין צורך להמתין ל-DB.
  unawaited(_persist(cachePath, size, mtime, converterVersion, text));
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
      now - _docxCacheTtl.inMilliseconds,
    );
  } catch (e) {
    debugPrint('⚠️ docx cache write failed (text still returned): $e');
  }
}

/// מחליף את שורת הכותרת (h1, שורה 0 ש-[docxToText] תמיד מייצר) ב-[title]
/// הנוכחי. כך המטמון נשמר לפי הקובץ ולא לפי שם הספר — שינוי-שם אינו פוסל
/// את המטמון, אך הכותרת המוצגת מתעדכנת מיד. אם הפלט אינו פותח ב-`<h1>`
/// (לא אמור לקרות) — מוחזר כפי שהוא.
@visibleForTesting
String withFreshDocxTitle(String cachedText, String title) =>
    _withFreshTitle(cachedText, title);

String _withFreshTitle(String cachedText, String title) {
  final nl = cachedText.indexOf('\n');
  final head = nl < 0 ? cachedText : cachedText.substring(0, nl);
  if (!head.startsWith('<h1>')) return cachedText;
  final rest = nl < 0 ? '' : cachedText.substring(nl);
  // escape כדי ששם קובץ עם `<`/`&` לא ישבור את ה-HTML.
  return '<h1>${escapeHtmlText(title)}</h1>$rest';
}
