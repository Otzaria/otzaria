import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';

/// ספר לצורך העדפות האיתור: המפתח היציב שלו והכותרת שאיתה נרשם.
typedef FindRefPreferenceBook = ({String key, String title});

/// ניקוד של ספר והכותרת שאיתה נצבר; כותרת אחרת לאותו מזהה = ספר אחר.
typedef FindRefPreferenceEntry = ({double score, String title});

/// תמונת מצב קבועה של ההעדפות, כפי שהדירוג של שאילתה אחת רואה אותן.
@immutable
class FindRefPreferences {
  const FindRefPreferences({this.books = const {}, this.bases = const {}});

  static const FindRefPreferences empty = FindRefPreferences();

  /// מקדם הדעיכה של כל הניקודים בכל פתיחה מהאיתור.
  static const double decay = 0.95;

  /// מתחת לסף זה הזיקה אינה משפיעה על הסדר (כ-3 פתיחות אחרונות).
  static const double affinityThreshold = 2.0;

  /// הניקוד שאליו מתכנסות פתיחות רצופות; ערך שמור גבוה ממנו נחתך אליו.
  static const double maxScore = 1 / (1 - decay);

  /// רשומה שדעכה מתחת לסף זה נמחקת.
  static const double negligibleScore = 0.05;

  /// מספר הרשומות המרבי בכל מפה; הנמוכות מושלכות.
  static const int maxEntries = 200;

  /// ניקוד לפי ספר שנפתח.
  final Map<String, FindRefPreferenceEntry> books;

  /// ניקוד לפי ספר בסיס — נצבר גם מפתיחת מפרשיו.
  final Map<String, FindRefPreferenceEntry> bases;

  bool get isEmpty => books.isEmpty && bases.isEmpty;

  /// המפתח היציב של ספר: מקור + מזהה במסד, ול-PDF מהדיסק הנתיב. `null` = אין זהות.
  static String? bookKey({
    required BookSource source,
    required int? bookId,
    bool isPdf = false,
    String filePath = '',
  }) {
    if (bookId != null && bookId > 0) {
      return '${source.wireKey}|$bookId${isPdf ? '|pdf' : ''}';
    }
    return filePath.isEmpty ? null : 'f|$filePath';
  }

  /// המפתח של ספר בסיס רשמי (טבלת `book_base_text`).
  static String officialBaseKey(int bookId) =>
      '${BookSource.official.wireKey}|$bookId';

  /// הניקוד הישיר של הספר, או 0 כשהכותרת השמורה אינה שלו.
  double directScore(String? key, String title) => _score(books, key, title);

  /// ניקוד הבסיס של המפתח, או 0 כשהכותרת השמורה אינה שלו.
  double baseScore(String? key, String title) => _score(bases, key, title);

  static double _score(
    Map<String, FindRefPreferenceEntry> map,
    String? key,
    String title,
  ) {
    if (key == null) return 0;
    final entry = map[key];
    return entry == null || entry.title != title ? 0 : entry.score;
  }

  /// הזיקה שמשפיעה על הסדר: הגבוה בין הניקודים, ו-0 מתחת ל-[affinityThreshold].
  double affinity({
    required String? key,
    required String title,
    Iterable<FindRefPreferenceBook> baseBooks = const [],
  }) {
    var best = math.max(directScore(key, title), baseScore(key, title));
    for (final base in baseBooks) {
      best = math.max(best, baseScore(base.key, base.title));
    }
    return best < affinityThreshold ? 0 : best;
  }

  /// ההעדפות אחרי פתיחת [book] מהאיתור: דעיכה לכולם, ואז +1 לספר ולבסיסיו.
  /// [companions] — ספרים שנפתחו באותה פעולה (שורת התוצאה של מפרש).
  FindRefPreferences recordOpen(
    FindRefPreferenceBook book, {
    Iterable<FindRefPreferenceBook> baseBooks = const [],
    Iterable<FindRefPreferenceBook> companions = const [],
  }) {
    final opened = <String, String>{book.key: book.title};
    for (final companion in companions) {
      opened.putIfAbsent(companion.key, () => companion.title);
    }
    // גם הספרים עצמם: ספר בסיס שנלמד מקבל זיקה גם מפתיחת מפרשיו.
    final baseTargets = {...opened};
    for (final base in baseBooks) {
      baseTargets.putIfAbsent(base.key, () => base.title);
    }
    return FindRefPreferences(
      books: _bumped(books, opened),
      bases: _bumped(bases, baseTargets),
    );
  }

  static Map<String, FindRefPreferenceEntry> _bumped(
    Map<String, FindRefPreferenceEntry> current,
    Map<String, String> targets,
  ) {
    final next = <String, FindRefPreferenceEntry>{};
    for (final MapEntry(:key, :value) in current.entries) {
      final score = value.score * decay;
      if (score < negligibleScore) continue;
      next[key] = (score: score, title: value.title);
    }
    for (final MapEntry(key: key, value: title) in targets.entries) {
      final previous = next[key];
      // כותרת שהתחלפה לאותו מזהה היא ספר אחר, והניקוד מתחיל מחדש.
      final carried = previous != null && previous.title == title
          ? previous.score
          : 0.0;
      next[key] = (score: carried + 1, title: title);
    }
    if (next.length <= maxEntries) return next;
    final ordered = next.entries.toList()..sort(_byScoreThenKey);
    return {for (final e in ordered.take(maxEntries)) e.key: e.value};
  }

  static int _byScoreThenKey(
    MapEntry<String, FindRefPreferenceEntry> a,
    MapEntry<String, FindRefPreferenceEntry> b,
  ) {
    final byScore = b.value.score.compareTo(a.value.score);
    return byScore != 0 ? byScore : a.key.compareTo(b.key);
  }

  Map<String, Object?> toJson() => {
    'v': 1,
    'books': _encode(books),
    'bases': _encode(bases),
  };

  static Map<String, Object?> _encode(
    Map<String, FindRefPreferenceEntry> map,
  ) => {
    for (final MapEntry(:key, :value) in map.entries)
      key: [value.score, value.title],
  };

  /// מפענח ערך שמור; כל חלק פגום מדולג, כך שערך שבור אינו מפיל את האיתור.
  static FindRefPreferences fromJson(Object? decoded) {
    if (decoded is! Map) return empty;
    return FindRefPreferences(
      books: _decode(decoded['books']),
      bases: _decode(decoded['bases']),
    );
  }

  static Map<String, FindRefPreferenceEntry> _decode(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, FindRefPreferenceEntry>{};
    for (final MapEntry(:key, :value) in raw.entries) {
      if (key is! String || key.isEmpty) continue;
      if (value is! List || value.length != 2) continue;
      final score = value[0];
      final title = value[1];
      if (score is! num || title is! String) continue;
      final asDouble = score.toDouble();
      if (!asDouble.isFinite || asDouble < negligibleScore) continue;
      out[key] = (score: math.min(asDouble, maxScore), title: title);
    }
    if (out.length <= maxEntries) return out;
    final ordered = out.entries.toList()..sort(_byScoreThenKey);
    return {for (final e in ordered.take(maxEntries)) e.key: e.value};
  }
}

/// העדפות האיתור האישיות: אילו ספרים נפתחו מהאיתור לאחרונה. נשמרות בהגדרות
/// כ-JSON; הדעיכה לפי פתיחות ולא לפי שעון, ולכן דטרמיניסטית.
class FindRefPreferenceStore {
  FindRefPreferenceStore._();

  static const String scoresKey = 'key-find-ref-preference-scores';
  static const String enabledKey = 'key-find-ref-preference-enabled';

  static int _revision = 0;

  /// משתנה בעקבות רישום פתיחה, מחיקה או שינוי המתג.
  static int get revision => _revision;

  /// שינוי יזום שמבטל רישום פתיחה שעדיין ממתין לספרי הבסיס.
  static int _configurationRevision = 0;
  static int get configurationRevision => _configurationRevision;

  /// האם האיתור מותאם אישית. כבוי = לא מדרגים וגם לא רושמים.
  static bool get isEnabled =>
      Settings.getValue<bool>(enabledKey, defaultValue: true) ?? true;

  static Future<void> setEnabled(bool value) async {
    _configurationRevision++;
    _revision++;
    await Settings.setValue<bool>(enabledKey, value);
  }

  /// מוחק את כל ההעדפות שנצברו.
  static void clear() {
    _configurationRevision++;
    _revision++;
    Settings.setValue<String>(scoresKey, '');
  }

  /// האם נשמר משהו שאפשר לאפס, בלי לפענח את ה-JSON.
  static bool get hasData =>
      (Settings.getValue<String>(scoresKey, defaultValue: '') ?? '').isNotEmpty;

  /// כל מה שנשמר, גם כשהמתג כבוי.
  static FindRefPreferences load() {
    final raw = Settings.getValue<String>(scoresKey, defaultValue: '') ?? '';
    if (raw.isEmpty) return FindRefPreferences.empty;
    try {
      return FindRefPreferences.fromJson(jsonDecode(raw));
    } catch (_) {
      // ערך פגום בהגדרות לא ימנע את האיתור.
      return FindRefPreferences.empty;
    }
  }

  /// ההעדפות לדירוג שאילתה, או `null` כשהמתג כבוי או שלא נצבר דבר.
  static FindRefPreferences? snapshot() {
    if (!isEnabled) return null;
    final preferences = load();
    return preferences.isEmpty ? null : preferences;
  }

  /// רושם פתיחה של [book] מדיאלוג האיתור. כשהמתג כבוי אינו רושם.
  static Future<void> recordOpen(
    FindRefPreferenceBook book, {
    Iterable<FindRefPreferenceBook> baseBooks = const [],
    Iterable<FindRefPreferenceBook> companions = const [],
  }) async {
    if (!isEnabled) return;
    final next = load().recordOpen(
      book,
      baseBooks: baseBooks,
      companions: companions,
    );
    _revision++;
    await Settings.setValue<String>(scoresKey, jsonEncode(next.toJson()));
  }
}
