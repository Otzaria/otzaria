/// [spellingKey] משמיט אמות קריאה ומקפל סופיות, כי כתיב מלא וחסר מתחלפים
/// שיטתית בין מהדורות (`חידושי` ↔ `חדושי`).
class ResponsaHebrew {
  ResponsaHebrew._();

  static final RegExp _nikud = RegExp('[֑-ׇ]');

  /// גרשיים וגרש הם סימנים **בתוך** מילה (`רשב"א`). מסירים אותם בלי
  /// להותיר רווח, אחרת `רשב"א` הופך לשתי מילים ואינו משתווה ל-`רשבא`.
  static final RegExp _intraWordMarks = RegExp('["\'׳״`]');

  static final RegExp _punctuation = RegExp(r'[.,;:!?()\[\]{}<>\-–—_/\\|*]');
  static final RegExp _whitespace = RegExp(r'\s+');
  static final RegExp _matres = RegExp('[יו]');

  /// תווים בלתי-נראים ששוברים כל השוואה.
  static final RegExp _invisible = RegExp(
    '[​‎‏ ﻿]',
  );

  static const Map<String, String> _finals = {
    'ך': 'כ',
    'ם': 'מ',
    'ן': 'נ',
    'ף': 'פ',
    'ץ': 'צ',
  };

  static String normalize(String? text) {
    if (text == null || text.isEmpty) return '';
    var value = text.replaceAll(_invisible, ' ');
    value = value.replaceAll(_nikud, '');
    value = value.replaceAll(_intraWordMarks, '');
    value = value.replaceAll(_punctuation, ' ');
    return value.replaceAll(_whitespace, ' ').trim();
  }

  static String spellingKey(String? text) {
    var value = normalize(text);
    if (value.isEmpty) return '';
    for (final entry in _finals.entries) {
      value = value.replaceAll(entry.key, entry.value);
    }
    value = value.replaceAll(_matres, '');
    return value.replaceAll(_whitespace, ' ').trim();
  }

  static List<String> tokens(String? text) =>
      spellingKey(text).split(' ').where((w) => w.isNotEmpty).toList();

  static final RegExp _abbreviationMark = RegExp("['׳]\$");

  /// גרש בסוף מילה מסמן ראשי תיבות (`ר'` = `רבי`). המפתח מפוצל שוב אחרי
  /// הנרמול, כי `כו-כז` הופך ל-`כ כז` ואסימון עם רווח לעולם לא ישתווה.
  static List<({String key, bool abbreviated})> markedTokens(String? text) {
    if (text == null || text.isEmpty) return const [];
    final cleaned = text.replaceAll(_invisible, ' ').replaceAll(_nikud, '');
    return [
      for (final word in cleaned.split(_whitespace))
        if (spellingKey(word) case final key when key.isNotEmpty)
          for (final part in key.split(' '))
            if (part.isNotEmpty)
              (key: part, abbreviated: _abbreviationMark.hasMatch(word.trim())),
    ];
  }

  // ------------------------------------------------------------ גימטריה

  static const Map<String, int> _letterValues = {
    'א': 1,
    'ב': 2,
    'ג': 3,
    'ד': 4,
    'ה': 5,
    'ו': 6,
    'ז': 7,
    'ח': 8,
    'ט': 9,
    'י': 10,
    'כ': 20,
    'ל': 30,
    'מ': 40,
    'נ': 50,
    'ס': 60,
    'ע': 70,
    'פ': 80,
    'צ': 90,
    'ק': 100,
    'ר': 200,
    'ש': 300,
    'ת': 400,
  };

  /// גימטריה → מספר. `null` כשיש תו שאינו אות-מספר.
  static int? numeralToInt(String? text) {
    if (text == null || text.isEmpty) return null;
    var total = 0;
    for (final char in text.split('')) {
      final value = _letterValues[_finals[char] ?? char];
      if (value == null) return null;
      total += value;
    }
    return total == 0 ? null : total;
  }

  // ------------------------------------------------- התאמת כותרות

  /// התוכנה מרחיבה את ההפניה במיקום, ולכן התאמה מלאה אינה השכיחה.
  /// `substring` חזק מ-`contains` כי הוא שומר על סדר המילים.
  static ResponsaMatchLevel matchLevel(String? expected, String? actual) {
    final want = normalize(expected);
    final got = normalize(actual);
    if (want.isEmpty || got.isEmpty) return ResponsaMatchLevel.none;
    if (want == got) return ResponsaMatchLevel.exact;
    if (got.startsWith(want) || want.startsWith(got)) {
      return ResponsaMatchLevel.prefix;
    }
    final wantKey = spellingKey(expected);
    final gotKey = spellingKey(actual);
    if (wantKey.isNotEmpty &&
        gotKey.isNotEmpty &&
        (gotKey.contains(wantKey) || wantKey.contains(gotKey))) {
      return ResponsaMatchLevel.substring;
    }
    final wantWords = markedTokens(expected);
    final gotWords = tokens(actual).toSet();
    if (wantWords.isNotEmpty &&
        wantWords.every((token) => _hasWord(gotWords, token))) {
      return ResponsaMatchLevel.contains;
    }
    return ResponsaMatchLevel.none;
  }

  /// אותיות שימוש שהתוכנה מוסיפה לפני שם (`לרמב"ם` מול `רמב"ם`). ההרפיה היא
  /// אות אחת בלבד מהרשימה, כדי לא לפתוח את ההשוואה לכל דבר.
  static const String _prefixLetters = 'בכלמושהד';

  static bool _hasWord(
    Set<String> words,
    ({String key, bool abbreviated}) token,
  ) {
    if (token.abbreviated) {
      return words.any((word) => word.startsWith(token.key));
    }
    if (words.contains(token.key)) return true;
    return words.any(
      (word) =>
          word.length == token.key.length + 1 &&
          word.endsWith(token.key) &&
          _prefixLetters.contains(word[0]),
    );
  }

  static bool titlesMatch(String? expected, String? actual) =>
      matchLevel(expected, actual) != ResponsaMatchLevel.none;

  /// העץ מכיל צמתי מבנה שהתוכנה משמיטה מכותרת החלון, ולכן די בראש השם (זהות
  /// החיבור) ובסופו (היחידה).
  static bool coversTitle(String? expected, String? actual) {
    if (titlesMatch(expected, actual) || titlesMatch(actual, expected)) {
      return true;
    }
    final want = markedTokens(expected);
    final got = tokens(actual).toSet();
    if (want.isEmpty || got.isEmpty) return false;
    if (!_hasWord(got, want.last)) return false;
    // ויתור על אסימון מוביל אחד בלבד (מדף שנדבק לשם) - שניים כבר מקבלים
    // ספר אחר לגמרי.
    if (_hasWord(got, want.first)) return true;
    return want.length > 2 && _hasWord(got, want[1]);
  }

  /// מבדיל בין מועמדים כש-[matchLevel] מחזירה `none` לכולם, כי אף אחד אינו
  /// מכיל את הכותרת כולה.
  static int sharedTokenCount(String? expected, String? actual) {
    final got = tokens(actual).toSet();
    if (got.isEmpty) return 0;
    var shared = 0;
    for (final token in markedTokens(expected)) {
      if (_hasWord(got, token)) shared++;
    }
    return shared;
  }

  static final RegExp _parenthetical = RegExp(r'\(([^)]*)\)');

  /// שאר ההשוואות מתעלמות מסוגריים, אך `שמות רבה (שנאן)` ו-`(וילנא)` הם שני
  /// ספרים. סתירה רק כששני הצדדים נושאים הסתייגות.
  static bool editionsConflict(String? a, String? b) {
    final first = _editionsOf(a);
    final second = _editionsOf(b);
    if (first.isEmpty || second.isEmpty) return false;
    return first.intersection(second).isEmpty;
  }

  /// הסתייגות שיש בה ספרה היא מיקום (`(עמ' 108-126)`), לא מהדורה.
  static final RegExp _digit = RegExp(r'\d');

  static Set<String> _editionsOf(String? text) {
    if (text == null) return const {};
    return {
      for (final match in _parenthetical.allMatches(text))
        if (match.group(1) case final inner? when !_digit.hasMatch(inner))
          if (spellingKey(inner) case final key when key.isNotEmpty) key,
    };
  }
}

/// רמות ההתאמה, מהחזקה לחלשה. הסדר הוא המשמעות — `rank` משמש לבחירת
/// התוצאה הטובה ביותר מבין תוצאות המנתח.
enum ResponsaMatchLevel {
  none,
  contains,
  substring,
  prefix,
  exact;

  int get rank => index;
}
