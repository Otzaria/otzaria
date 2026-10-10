import 'dart:convert';

import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';

/// תוצאת ייבוא של רשימת הסתרות מקובץ (issue #1448).
class HiddenBooksImportResult {
  /// מפתחות הספרים שהותאמו לספרייה.
  final Set<String> matchedBookKeys;

  /// שמות שלא נמצא להם ספר. מוצגים למשתמש כדי ששגיאת כתיב לא תיעלם בשקט.
  final List<String> unmatchedNames;

  /// כמה שמות היו בקובץ בסך הכול.
  final int totalNames;

  const HiddenBooksImportResult({
    required this.matchedBookKeys,
    required this.unmatchedNames,
    required this.totalNames,
  });

  bool get isEmpty => totalNames == 0;
}

/// מפרש קובץ הסתרות ומתאים את ערכיו לספרים בספרייה.
///
/// כל ערך מתפרש קודם כ**מזהה** בפורמט [PerBookSettings.bookKey] (למשל
/// `o__4217__אור החיים`), ואם אינו מזהה מוכר — כ**שם ספר**. כך קובץ שנוצר
/// מתוך התוכנה נטען בדיוק כפי שנשמר, וקובץ שמשתמש הכין ביד עדיין עובד.
///
/// נתמכים שני פורמטים:
/// - JSON: מערך מחרוזות, או אובייקט עם המפתח `books`.
/// - CSV/טקסט: ערך בכל שורה. בשורה עם פסיקים נלקחת העמודה הראשונה.
///
/// שם שמופיע יותר מפעם אחת בספרייה מסתיר את כל המופעים; מזהה מצביע על ספר
/// אחד בדיוק.
HiddenBooksImportResult parseHiddenBooksImport(
  String content,
  Library library,
) {
  final names = _extractNames(content);
  if (names.isEmpty) {
    return const HiddenBooksImportResult(
      matchedBookKeys: {},
      unmatchedNames: [],
      totalNames: 0,
    );
  }

  final booksByTitle = <String, List<String>>{};
  final knownKeys = <String>{};
  for (final book in library.getAllBooks()) {
    final key = PerBookSettings.bookKey(book);
    knownKeys.add(key);
    booksByTitle.putIfAbsent(book.title.trim(), () => <String>[]).add(key);
  }

  final matched = <String>{};
  final unmatched = <String>[];
  for (final value in names) {
    if (knownKeys.contains(value)) {
      matched.add(value);
      continue;
    }
    final keys = booksByTitle[value];
    if (keys == null) {
      unmatched.add(value);
      continue;
    }
    matched.addAll(keys);
  }

  return HiddenBooksImportResult(
    matchedBookKeys: matched,
    unmatchedNames: unmatched,
    totalNames: names.length,
  );
}

List<String> _extractNames(String content) {
  final trimmed = content.trim();
  if (trimmed.isEmpty) return const [];

  if (trimmed.startsWith('[') || trimmed.startsWith('{')) {
    try {
      final decoded = jsonDecode(trimmed);
      final list = decoded is Map ? decoded['books'] : decoded;
      if (list is List) {
        return _normalize(list.whereType<String>());
      }
    } catch (_) {
      // לא JSON תקין — ממשיכים לפענוח כטקסט, שהוא המקרה הנפוץ.
    }
  }

  return _normalize(
    const LineSplitter().convert(trimmed).map((line) {
      // שדה מצוטט (כמו ששומר Excel) יכול להכיל פסיק, ו-"" בתוכו הוא גרש אחד.
      final quoted = _quotedCsvCell.firstMatch(line);
      if (quoted != null) return quoted[1]!.replaceAll('""', '"');
      final cell = line.split(',').first;
      return cell.trim().replaceAll(RegExp(r'^"|"$'), '');
    }),
  );
}

final _quotedCsvCell = RegExp(r'^\s*"((?:[^"]|"")*)"\s*(?:,|$)');

/// מנקה רווחים, זורק ריקים, ושומר על סדר בלי כפילויות.
List<String> _normalize(Iterable<String> raw) {
  final seen = <String>{};
  final result = <String>[];
  for (final value in raw) {
    final name = value.trim();
    if (name.isEmpty) continue;
    if (!seen.add(name)) continue;
    result.add(name);
  }
  return result;
}
