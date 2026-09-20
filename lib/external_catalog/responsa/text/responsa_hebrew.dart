/// נרמול טקסט עברי והשוואת כותרות עבור אוטומציית פרויקט השו"ת.
///
/// שלוש רמות, מהמקילה למחמירה:
///
/// * [normalize] — ניקוד, פיסוק, גרשיים, רווחים. להשוואת כותרות.
/// * [spellingKey] — בנוסף: השמטת אמות קריאה (י/ו) וקיפול אותיות
///   סופיות. מנטרל את ההבדל בין כתיב מלא לחסר, שהוא רפורמה שיטתית בין
///   מהדורות (`חידושי` ↔ `חדושי`, `ביאור` ↔ `באור`).
/// * [numeralToInt] / [intToNumeral] — גימטריה. כותרת חלון היא
///   `<ספר> סימן <גימטריה>`, והיא האורקל היחיד למיקום הנוכחי.
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

  /// אסימונים, כשכל אחד מסומן אם הוא **ראשי-תיבות**.
  ///
  /// גרש בסוף מילה מקצר אותה: `ר'` הוא `רבי`. בלי הסימון הזה
  /// `ר' אברהם מן ההר יבמות` אינו מתאים לכותרת
  /// `רבי אברהם מן ההר (מהד' בלוי) מסכת יבמות` — כי `ר` ו-`רב` הם שני
  /// אסימונים שונים — ופתיחה תקינה לחלוטין נפסלת.
  static List<({String key, bool abbreviated})> markedTokens(String? text) {
    if (text == null || text.isEmpty) return const [];
    final cleaned = text.replaceAll(_invisible, ' ').replaceAll(_nikud, '');
    return [
      for (final word in cleaned.split(_whitespace))
        if (spellingKey(word) case final key when key.isNotEmpty)
          (key: key, abbreviated: _abbreviationMark.hasMatch(word.trim())),
    ];
  }

  // ------------------------------------------------------------ גימטריה

  static const List<String> _ones = [
    '',
    'א',
    'ב',
    'ג',
    'ד',
    'ה',
    'ו',
    'ז',
    'ח',
    'ט',
  ];
  static const List<String> _tens = [
    '',
    'י',
    'כ',
    'ל',
    'מ',
    'נ',
    'ס',
    'ע',
    'פ',
    'צ',
  ];
  static const List<String> _hundreds = [
    '',
    'ק',
    'ר',
    'ש',
    'ת',
    'תק',
    'תר',
    'תש',
    'תת',
    'תתק',
  ];
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

  /// 1..999 → גימטריה כפי שהיא מופיעה בכותרות (טו/טז חריגים).
  static String intToNumeral(int value) {
    if (value <= 0 || value >= 1000) {
      throw ArgumentError.value(value, 'value', 'נתמך 1..999 בלבד');
    }
    final text = _hundreds[value ~/ 100];
    final rest = value % 100;
    // טו/טז נכתבים כך ולא כ-יה/יו.
    final suffix = switch (rest) {
      15 => 'טו',
      16 => 'טז',
      _ => '${_tens[rest ~/ 10]}${_ones[rest % 10]}',
    };
    return '$text$suffix';
  }

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

  /// רמת ההתאמה בין הכותרת המצופה לכותרת החלון שנפתח בפועל.
  ///
  /// התאמה מלאה אינה נדרשת ואף אינה השכיחה: התוכנה **מרחיבה** את ההפניה
  /// ומוסיפה לה מיקום — `משנה יבמות` נפתח ככותרת `משנה מסכת יבמות פרק א`.
  ///
  /// `substring` חזק מ-`contains` כי הוא שומר על **סדר** המילים:
  /// `כלל יא` הוא תת-מחרוזת של `רא"ש כלל יא סימן א` אבל **לא** של
  /// `רא"ש כלל ב סימן יא`, בעוד שהכלה לפי מילים אינה מבדילה ביניהם.
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

  /// אותיות שימוש שהתוכנה מוסיפה לפני שם: `לרמב"ם` מול `רמב"ם`.
  ///
  /// נצפה חי: `רמב"ם הוריות` נפתח ככותרת
  /// `פירוש המשנה לרמב"ם מסכת הוריות`, ונדחה — כי `לרמבמ` ו-`רמבמ` הם
  /// שני אסימונים שונים. ההרפיה היא **אות אחת בלבד** ומתוך הרשימה
  /// הסגורה הזו, ולכן אינה פותחת את ההשוואה לכל דבר.
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

  /// האם [actual] הוא הספר ש-[expected] מתאר — בדיקה רכה יותר.
  ///
  /// [expected] הוא שם שאוצריא הרכיבה מהעץ, ו-[actual] הוא השם שהתוכנה
  /// נותנת לחלון. שניהם שמות של אותו ספר, אבל הם נבנו אחרת: העץ מכיל
  /// צמתי מבנה שהתוכנה משמיטה (`חידושי הגר"ח > חידושים על הגמרא > מכות`
  /// נפתח ככותרת `חידושי הגר"ח מסכת מכות דף ב עמוד א`), והתוכנה מוסיפה
  /// מיקום שהעץ אינו מכיל.
  ///
  /// לכן, כשההשוואה המלאה נכשלת, די ב**ראש השם ובסופו**: הראש הוא זהות
  /// החיבור או המחבר, והסוף הוא היחידה. `מנהגי החגים ... יבמות` מול
  /// `משנה מסכת יבמות` עדיין נדחה — הראש אינו שם.
  static bool coversTitle(String? expected, String? actual) {
    if (titlesMatch(expected, actual) || titlesMatch(actual, expected)) {
      return true;
    }
    final want = markedTokens(expected);
    final got = tokens(actual).toSet();
    if (want.isEmpty || got.isEmpty) return false;
    if (!_hasWord(got, want.last)) return false;
    // ראש השם, או האסימון שאחריו.
    //
    // הוויתור על אסימון מוביל אחד אינו שרירותי: הוא מכסה **מדף שנדבק
    // לשם**. `מדרש רבה (תורה) > שמות רבה (וילנא)` הוא מדף וחיבור,
    // והתוכנה מכנה את החלון `שמות רבה (וילנא)` בלבד — 13 ספרים נפסלו
    // אף שנפתחו נכון.
    //
    // ולא יותר מאסימון אחד: `בית הבחירה למאירי על הש"ס ברכות` נפתח
    // בטעות כ-`שרידי אש על הש"ס ברכות`, ורק הדרישה ל-`בית` או
    // `הבחירה` פוסלת אותו. ויתור על שניים היה מקבל אותו.
    if (_hasWord(got, want.first)) return true;
    return want.length > 2 && _hasWord(got, want[1]);
  }

  /// כמה אסימונים מ-[expected] מופיעים ב-[actual].
  ///
  /// דירוג מדורג, שנחוץ בדיוק כשאף שורה אינה מכילה את הכותרת כולה:
  /// `רי"ד (פסקים) בבא קמא משניות` אינו מוכל לא ב-`פסקי רי"ד מסכת
  /// ברכות` ולא ב-`פסקי רי"ד מסכת בבא קמא`, כי `משניות` אינו באף אחת.
  /// [matchLevel] מחזירה `none` לשתיהן; הספירה מבדילה — 1 מול 3.
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

  /// האם שתי כותרות נושאות **מהדורות סותרות**.
  ///
  /// `שמות רבה (שנאן)` ו-`שמות רבה (וילנא)` הם שני ספרים, וההבדל היחיד
  /// ביניהם הוא הסוגריים. שאר ההשוואות כאן מתעלמות מהסוגריים בכוונה —
  /// הן מטא-דאטה של הקטלוג — ולכן דרושה בדיקה נפרדת.
  ///
  /// **רק כששתי הכותרות נושאות הסתייגות.** צד אחד בלבד אינו סתירה:
  /// `היכלות (עמ' 108-126)` נפתח ככותרת `אוצר מדרשים (אייזנשטיין)
  /// היכלות`, ושתי ההסתייגויות מתארות דברים שונים לגמרי.
  static bool editionsConflict(String? a, String? b) {
    final first = _editionsOf(a);
    final second = _editionsOf(b);
    if (first.isEmpty || second.isEmpty) return false;
    return first.intersection(second).isEmpty;
  }

  /// הסתייגות שיש בה ספרה היא **מיקום**, לא מהדורה.
  ///
  /// `(עמ' 108-126)` מתאר טווח עמודים ב-110 שמות במאגר; `(וילנא)`,
  /// `(שנאן)`, `(ליברמן)` מתארים מהדורה. בלי ההבחנה הזו
  /// `היכלות (עמ' 108-126)` נחשב סותר את `אוצר מדרשים (אייזנשטיין)
  /// היכלות` — שהוא בדיוק הספר הנכון.
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
