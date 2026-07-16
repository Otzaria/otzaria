import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show HighlightPattern;

import '../support/search_engine_test_init.dart';

Future<void> main() async {
  final engineReady = await tryInitSearchEngine();

  group('highLight', () {
    test('single word - highlights the word', () {
      const text = 'כל יום טוב';
      final result = highLight(text, 'יום');
      expect(result, contains('<span style="color: red">'));
      expect(result, contains('יום'));
    });

    test('multi-word query - highlights only the complete sequence', () {
      // "כל היום" should be highlighted only where both words appear together
      const text = 'היה זה כל היום טוב';
      final result = highLight(text, 'כל היום');
      // המילה "היה" לא אמורה להיות מודגשת
      expect(result, isNot(contains('<span style="color: red">היה')));
      // רק מילות החיפוש עצמן אמורות להיות מודגשות
      expect(
        result,
        contains(
          '<span style="color: red">כל</span> <span style="color: red">היום</span>',
        ),
      );
      // "היה", "זה", "טוב" לא אמורים להיות מודגשים
      expect(result, isNot(contains('<span style="color: red">טוב')));
    });

    test('multi-word query - does not highlight lone words from query', () {
      // אם מחפשים "כל היום", מילה בודדת "כל" לא אמורה להיות מודגשת
      const text = 'כל הספרים היו שם';
      final result = highLight(text, 'כל היום');
      // אין מופע של "כל היום" יחד - לכן לא אמור להיות highlighting כלל
      expect(result, isNot(contains('<span')));
    });

    test('single word - does not highlight inside another word by default', () {
      const text = 'ויאמר משה';
      final result = highLight(text, 'אמר');

      expect(result, isNot(contains('<span')));
    });

    test('single word - can highlight inside another word when enabled', () {
      const text = 'ויאמר משה';
      final result = highLight(
        text,
        'אמר',
        searchOptions: const {
          'אמר_0': {'חלק ממילה': true},
        },
      );

      expect(result, contains('<span style="color: red">אמר</span>'));
    });

    test('multi-word query with spacing - highlights spaced phrase', () {
      const text = 'היה זה כל דבר היום טוב';
      final result = highLight(
        text,
        'כל היום',
        spacingValues: const {'0-1': '1'},
      );

      expect(
        result,
        contains(
          '<span style="color: red">כל</span> דבר <span style="color: red">היום</span>',
        ),
      );
      expect(result, isNot(contains('<span style="color: red">דבר</span>')));
    });

    test('multi-word query with spacing - respects spacing limit', () {
      const text = 'היה זה כל דבר נוסף היום טוב';
      final result = highLight(
        text,
        'כל היום',
        spacingValues: const {'0-1': '1'},
      );

      expect(result, isNot(contains('<span')));
    });

    test('multi-word query with spacing - ignores punctuation between words',
        () {
      const text = 'אמר ליה רבי יוחנן: הוא אפילו תינוקות';
      final result = highLight(
        text,
        'אמר רבי יוחנן הוא',
        spacingValues: const {'0-1': '1'},
      );

      expect(
        result,
        contains(
          '<span style="color: red">אמר</span> ליה <span style="color: red">רבי</span> <span style="color: red">יוחנן</span>: <span style="color: red">הוא</span>',
        ),
      );
      expect(result, isNot(contains('<span style="color: red">ליה</span>')));
    });

    test(
        'multi-word query with one spacing value - applies max spacing to all gaps',
        () {
      const text = 'אמר רבי שמעון בן לקיש';
      final result = highLight(
        text,
        'אמר שמעון לקיש',
        spacingValues: const {'0-1': '1'},
      );

      expect(
        result,
        contains(
          '<span style="color: red">אמר</span> רבי <span style="color: red">שמעון</span> בן <span style="color: red">לקיש</span>',
        ),
      );
      expect(result, isNot(contains('<span style="color: red">רבי</span>')));
      expect(result, isNot(contains('<span style="color: red">בן</span>')));
    });

    test('single word with nikud in text - highlights correctly', () {
      const text = 'הָיָה כָּל הַיּוֹם';
      final result = highLight(text, 'כל');
      expect(result, contains('<span style="color: red">'));
    });

    test('multi-word with nikud and spacing - highlights both words', () {
      const text = 'וְעַתָּה יֵרֶא פַּרְעֹה אִישׁ נָבוֹן וְחָכָם';
      final result = highLight(
        text,
        'פרעה נבון',
        spacingValues: const {'0-1': '1'},
      );

      expect(result, contains('<span style="color: red">פַּרְעֹה</span>'));
      expect(result, contains('<span style="color: red">נָבוֹן</span>'));
    });

    test('multi-word separated by maqaf - highlights all words', () {
      // מקף (maqaf) בין מילים בטקסט מנוקד אינו ניקוד הצמוד לאות אלא מפריד —
      // אסור שייבלע לתוך גבול המילה ויפסול את ההדגשה.
      const text = 'עֵ֣קֶב אֲשֶׁר־שָׁמַ֣ע אַבְרָהָ֖ם בְּקֹלִ֑י';
      final result = highLight(text, 'עקב אשר שמע אברהם');

      expect(result, contains('<span style="color: red">אֲשֶׁר</span>'));
      expect(result, contains('<span style="color: red">שָׁמַ֣ע</span>'));
      expect(result, contains('<span style="color: red">אַבְרָהָ֖ם</span>'));
    });

    test('yellowBackground - הדגשה רציפה אחת כולל הרווחים בין המילים', () {
      const text = 'אמר רבי יוחנן משום רבי שמעון בן יוחאי';
      final result = highLight(
        text,
        'רבי יוחנן משום',
        yellowBackground: true,
      );

      expect(
        result,
        contains(
          '<span style="background-color: yellow; color: black">רבי יוחנן משום</span>',
        ),
      );
    });

    test('yellowBackground - פיסוק בין המילים נכלל בהדגשה הרציפה', () {
      const text = 'אמר ליה רבי יוחנן: הוא אפילו תינוקות';
      final result = highLight(
        text,
        'רבי יוחנן הוא',
        yellowBackground: true,
      );

      expect(
        result,
        contains(
          '<span style="background-color: yellow; color: black">רבי יוחנן: הוא</span>',
        ),
      );
    });

    test('yellowBackground - ציטוט שנקטע באמצע מילה עדיין מודגש', () {
      // קישור ?m= נבנה מטקסט מסומן, וגרירה יכולה לעצור באמצע מילה.
      const text = 'אִם כְּמָה שֶׁנָּדַרְתָּ עָשִׂיתָ – יְהֵא נֶדֶר';
      final result = highLight(
        text,
        'שֶׁנָּדַרְתָּ עָשִׂיתָ – יְה',
        yellowBackground: true,
      );

      expect(
        result,
        contains('<span style="background-color: yellow; color: black">'),
      );
      expect(result, contains('שֶׁנָּדַרְתָּ'));
    });

    test('yellowBackground - תגי HTML בתוך הקטע נשארים מחוץ ל-span', () {
      const text = 'אמר <b>רבי</b> יוחנן';
      final result = highLight(
        text,
        'אמר רבי יוחנן',
        yellowBackground: true,
      );

      expect(
        result,
        equals(
          '<span style="background-color: yellow; color: black">אמר </span>'
          '<b><span style="background-color: yellow; color: black">רבי</span></b>'
          '<span style="background-color: yellow; color: black"> יוחנן</span>',
        ),
      );
    });

    test('multi-word with nikud and searchDistance - highlights both words',
        () {
      const text = 'וְעַתָּה יֵרֶא פַּרְעֹה אִישׁ נָבוֹן וְחָכָם';
      final result = highLight(
        text,
        'פרעה נבון',
        searchDistance: 1,
      );

      expect(result, contains('<span style="color: red">פַּרְעֹה</span>'));
      expect(result, contains('<span style="color: red">נָבוֹן</span>'));
    });
  },
      skip: engineReady
          ? false
          : 'ספריית מנוע החיפוש הנייטיבית לא נמצאה — הריצו cargo build בחבילה');

  group('stripHtmlPreservingBreaks', () {
    test('ממיר <br> למעבר שורה במקום לדחוס לרצף', () {
      expect(
        stripHtmlPreservingBreaks('שורה ראשונה<br>שורה שנייה'),
        equals('שורה ראשונה\nשורה שנייה'),
      );
    });

    test('תומך בגרסאות <br/> ו-<BR> ומסיר שאר תגים', () {
      expect(
        stripHtmlPreservingBreaks('א<br/>ב<BR>ג <b>ד</b>'),
        equals('א\nב\nג ד'),
      );
    });
  });

  group('removePunctuation', () {
    test('keeps dot and colon inside nested parentheses', () {
      const input = 'שלום: עולם! (א:ב. (ג:ד.))';

      final result = removePunctuation(input);

      expect(result, equals('שלום עולם (א:ב. (ג:ד.))'));
    });

    test('keeps allowed punctuation at end of line', () {
      const input = 'משפט עם נקודה.';

      final result = removePunctuation(input);

      expect(result, equals('משפט עם נקודה.'));
    });

    test('שומר גרשיים בראשי תיבות (אות אחת אחרי הגרשיים)', () {
      expect(removePunctuation('רש"י'), equals('רש"י'));
      expect(removePunctuation('שו"ע'), equals('שו"ע'));
      expect(removePunctuation('ב"ה'), equals('ב"ה'));
      expect(removePunctuation('רמב"ם'), equals('רמב"ם'));
    });

    test('מסיר מירכאות ציטוט (שתי אותיות אחרי הגרשיים)', () {
      expect(removePunctuation('ב"כי יותן'), equals('בכי יותן'));
      expect(
          removePunctuation('הרי הן ב"כי יותן.'), equals('הרי הן בכי יותן.'));
    });

    test('שומר ראשי תיבות גם כשהאותיות מנוקדות', () {
      // ניקוד אחרי האות לא ייחשב בטעות כאות שנייה, וניקוד לפני הגרשיים לא
      // יסתיר את האות הקודמת.
      expect(removePunctuation('רַשִׁ"י'), equals('רַשִׁ"י'));
      expect(removePunctuation('רַמבַּ"ם'), equals('רַמבַּ"ם'));
    });

    test('מסיר מירכאות ציטוט גם בטקסט מנוקד', () {
      // לפני התיקון: ב"כִּי נשמר בטעות כראשי תיבות כי הניקוד הסתיר את האות
      // השנייה אחרי הגרשיים.
      expect(removePunctuation('ב"כִּי'), equals('בכִּי'));
    });
  });

  group('normalizeForFindRefMatch', () {
    test('מחרוזת ריקה מחזירה ריקה', () {
      expect(normalizeForFindRefMatch(''), equals(''));
    });

    test('רווחים בלבד מחזירים מחרוזת ריקה', () {
      expect(normalizeForFindRefMatch('   '), equals(''));
      expect(normalizeForFindRefMatch('\t \n'), equals(''));
    });

    test('גרשיים כפולים (ASCII) מוסרים ללא הוספת רווח', () {
      // קריטי: "שו"ע" → "שוע" (לא "שו ע") כדי שראשי-תיבות יעבדו.
      expect(normalizeForFindRefMatch('שו"ע'), equals('שוע'));
      expect(normalizeForFindRefMatch('מ"ב'), equals('מב'));
    });

    test('גרשיים עבריים (״) מוסרים ללא הוספת רווח', () {
      expect(normalizeForFindRefMatch('שו״ע'), equals('שוע'));
      expect(normalizeForFindRefMatch('רמב״ם'), equals('רמבם'));
    });

    test('גרש בודד (\') מוסר ללא הוספת רווח', () {
      expect(normalizeForFindRefMatch("ה'"), equals('ה'));
    });

    test('גרש עברי (׳) מוסר ללא הוספת רווח', () {
      expect(normalizeForFindRefMatch('ה׳'), equals('ה'));
    });

    test('ניקוד עברי מוסר', () {
      expect(normalizeForFindRefMatch('בְּרֵאשִׁית'), equals('בראשית'));
      expect(normalizeForFindRefMatch('שָׁלוֹם'), equals('שלום'));
    });

    test('טעמי מקרא מוסרים', () {
      // טעם דרגא (U+05A7) על "בְּ"
      expect(normalizeForFindRefMatch('בְּ֧רֵאשִׁ֖ית'), equals('בראשית'));
    });

    test('אותיות אנגלית הופכות לאותיות קטנות', () {
      expect(normalizeForFindRefMatch('Genesis'), equals('genesis'));
      expect(normalizeForFindRefMatch('GENESIS'), equals('genesis'));
    });

    test('רווחים מרובים מתכווצים לרווח אחד', () {
      expect(normalizeForFindRefMatch('א   ב'), equals('א ב'));
      expect(normalizeForFindRefMatch('א\t\tב'), equals('א ב'));
    });

    test('תווים מיוחדים הופכים לרווח', () {
      expect(normalizeForFindRefMatch('א-ב'), equals('א ב'));
      expect(normalizeForFindRefMatch('א,ב'), equals('א ב'));
      expect(normalizeForFindRefMatch('א.ב'), equals('א ב'));
      expect(normalizeForFindRefMatch('א/ב'), equals('א ב'));
    });

    test('רווחים מובילים וסוגרים מקוצצים', () {
      expect(normalizeForFindRefMatch('  שלום  '), equals('שלום'));
    });

    test('ספרות נשמרות', () {
      expect(normalizeForFindRefMatch('פרק 1'), equals('פרק 1'));
      expect(normalizeForFindRefMatch('סימן 42'), equals('סימן 42'));
    });

    test('אותיות עבריות נשמרות', () {
      expect(normalizeForFindRefMatch('אבגדהוזחטיכלמנסעפצקרשת'),
          equals('אבגדהוזחטיכלמנסעפצקרשת'));
    });

    test('שילוב: ניקוד+גרשיים+טעמים+רווחים', () {
      // "שוּ״ע - אוֹ״ח" → "שוע אוח"
      expect(normalizeForFindRefMatch('שוּ״ע - אוֹ״ח'), equals('שוע אוח'));
    });

    group('סימון עמוד גמרא (ב. / ב:)', () {
      test('נקודה אחרי 1–3 אותיות עבריות בסוף מחרוזת → עמוד א', () {
        expect(normalizeForFindRefMatch('ב.'), equals('ב א'));
        expect(normalizeForFindRefMatch('לט.'), equals('לט א'));
        expect(normalizeForFindRefMatch('קמד.'), equals('קמד א'));
      });

      test('נקודתיים אחרי 1–3 אותיות עבריות בסוף מחרוזת → עמוד ב', () {
        expect(normalizeForFindRefMatch('ב:'), equals('ב ב'));
        expect(normalizeForFindRefMatch('לט:'), equals('לט ב'));
      });

      test('נקודה/נקודתיים בסוף טוקן (לפני רווח) → עמוד', () {
        expect(normalizeForFindRefMatch('שבת ב.'), equals('שבת ב א'));
        expect(normalizeForFindRefMatch('שבת ב:'), equals('שבת ב ב'));
        expect(normalizeForFindRefMatch('ברכות לט.'), equals('ברכות לט א'));
      });

      test('נקודה בין אותיות (לא סוף טוקן) — לא מורחבת', () {
        // "א.ב" — נקודה שאינה בגבול מילה → נותרת ריווח רגיל
        expect(normalizeForFindRefMatch('א.ב'), equals('א ב'));
      });

      test('נקודה אחרי יותר מ-3 אותיות — לא מורחבת (לא מספר דף)', () {
        // "ראשי." — 4 אותיות, לא מספר דף
        expect(normalizeForFindRefMatch('ראשי.'), equals('ראשי'));
      });

      test('קיצור עם גרש לפני הנקודה — לא מורחב (פ"א. / רמ"א.)', () {
        // "פ"א." ← גרש לפני האות; לא ציון דף אלא קיצור
        expect(normalizeForFindRefMatch('פ"א.'), equals('פא'));
        expect(normalizeForFindRefMatch('רמ"א.'), equals('רמא'));
        expect(normalizeForFindRefMatch('מ"ב.'), equals('מב'));
      });
    });
  });

  group('tocTextMatchesRef', () {
    test('הפניית תוסף עם גרשיים וע"ב מתאימה לכותרת TOC עם נקודתיים', () {
      expect(tocTextMatchesRef('דף סד:', 'ס"ד ע"ב'), isTrue);
    });

    test('הפניית ע"א מתאימה לעמוד א ולא לעמוד ב', () {
      expect(tocTextMatchesRef('דף סד.', 'ס"ד ע"א'), isTrue);
      expect(tocTextMatchesRef('דף סד:', 'ס"ד ע"א'), isFalse);
      expect(tocTextMatchesRef('דף סד.', 'ס"ד ע"ב'), isFalse);
    });

    test('אינה מתאימה דף אות-בודדת לדף עם סיומת זהה', () {
      // "ב ע"ב" לא יתאים ל"דף כב:" (התאמת טוקנים, לא substring)
      expect(tocTextMatchesRef('דף כב:', 'ב ע"ב'), isFalse);
      expect(tocTextMatchesRef('דף ב:', 'ב ע"ב'), isTrue);
    });

    test('הסדר מבדיל בין מספר הדף לציון העמוד', () {
      // "ב ע"א" (דף ב, עמוד א) — הטוקנים ב,א מול א,ב של "דף א:"
      expect(tocTextMatchesRef('דף א:', 'ב ע"א'), isFalse);
      expect(tocTextMatchesRef('דף ב.', 'ב ע"א'), isTrue);
      expect(tocTextMatchesRef('דף ב:', 'ב ע"א'), isFalse);
    });

    test('התאמה גולמית נשמרת ו-ref ריק לא מתאים', () {
      expect(tocTextMatchesRef('דף סד:', 'דף סד:'), isTrue);
      expect(tocTextMatchesRef('דף סד:', ''), isFalse);
    });
  });

  group('primeHighlightPattern', () {
    // תבנית "מבוססת אינדקס" מזויפת: מדגישה גם את וריאנט שגיאת הכתיב מסה,
    // שה-fallback (שמכיר רק את צורת השאילתה משה) לעולם לא היה מדגיש.
    const primedPattern = HighlightPattern(
      combinedPattern: '(?:משה|מסה)',
      wordPatterns: ['(?:משה|מסה)'],
      wordBoundaryEligible: [true],
    );

    test('highLight משתמש בתבנית שהוזנה מראש לאותם פרמטרים', () async {
      const query = 'משה';
      const options = {
        'משה_0': {'שגיאות כתיב': true},
      };

      await primeHighlightPattern(
        searchQuery: query,
        searchOptions: options,
        alternativeWords: const {},
        spacingValues: const {},
        searchDistance: 0,
        isFuzzy: false,
        fetch: () async => primedPattern,
      );

      final result = highLight(
        'ויקח מסה גדולה',
        query,
        searchOptions: options,
      );
      expect(result, contains('<span style="color: red">מסה</span>'));
    });

    test('פרמטרים שונים לא פוגעים בתבנית שהוזנה — מפתח לפי פרמטרים', () async {
      const query = 'משה אמר';
      await primeHighlightPattern(
        searchQuery: query,
        searchOptions: const {},
        alternativeWords: const {},
        spacingValues: const {},
        searchDistance: 0,
        isFuzzy: false,
        fetch: () async => primedPattern,
      );

      // distance שונה → מפתח שונה → אין פגיעת מטמון, וזו לא שגיאה.
      final miss = highLight('ויקח מסה', query, searchDistance: 3);
      expect(miss, isNot(contains('<span')));

      // הפרמטרים המקוריים עדיין מוצאים את התבנית שהוזנה.
      final hit = highLight('ויקח מסה', query);
      expect(hit, contains('<span style="color: red">מסה</span>'));
    });

    test('כשל בהבאה נבלע וה-fallback ממשיך לשרת', () async {
      const query = 'שלום';
      await primeHighlightPattern(
        searchQuery: query,
        searchOptions: const {},
        alternativeWords: const {},
        spacingValues: const {},
        searchDistance: 0,
        isFuzzy: false,
        fetch: () async => throw StateError('index unavailable'),
      );

      // ה-fallback הסינכרוני (תבנית מבוססת-שאילתה) עדיין עובד.
      final result = highLight('שלום עולם', query);
      expect(result, contains('<span style="color: red">שלום</span>'));
    });

    test('תבנית advanced אינה משמשת רינדור fuzzy — המצב חלק מהמפתח', () async {
      const query = 'משה רבנו';
      await primeHighlightPattern(
        searchQuery: query,
        searchOptions: const {},
        alternativeWords: const {},
        spacingValues: const {},
        searchDistance: 0,
        isFuzzy: false,
        fetch: () async => primedPattern,
      );

      // רינדור במצב fuzzy עם אותם פרמטרים לא מוצא את תבנית ה-advanced,
      // ונופל ל-fallback (שדורש את שתי המילים — אין התאמה כאן).
      final fuzzyRender = highLight('ויקח מסה', query, isFuzzy: true);
      expect(fuzzyRender, isNot(contains('<span')));

      // רינדור advanced כן פוגע בתבנית.
      final advancedRender = highLight('ויקח מסה', query);
      expect(advancedRender, contains('<span style="color: red">מסה</span>'));
    });

    test('קידומת בתוך ההתאמה אינה פוסלת הדגשה — "מיעוט" ב"במיעוט"', () async {
      const query = 'מיעוט';
      await primeHighlightPattern(
        searchQuery: query,
        searchOptions: const {},
        alternativeWords: const {},
        spacingValues: const {},
        searchDistance: 0,
        isFuzzy: false,
        fetch: () async => const HighlightPattern(
          combinedPattern: '(?:[בכלמהוש])?מיעוט',
          wordPatterns: ['מיעוט'],
          wordBoundaryEligible: [true],
        ),
      );

      final result = highLight('ראה במיעוט גדול', query);
      // רק "מיעוט" מודגש; ה"ב" של הקידומת נשאר מחוץ להדגשה.
      expect(result, contains('ב<span style="color: red">מיעוט</span>'));
    });

    test('תת-מחרוזת אקראית עדיין נדחית — "מיעוט" ב"שמיעוטי" לא מודגש',
        () async {
      const query = 'זריזות';
      await primeHighlightPattern(
        searchQuery: query,
        searchOptions: const {},
        alternativeWords: const {},
        spacingValues: const {},
        searchDistance: 0,
        isFuzzy: false,
        fetch: () async => const HighlightPattern(
          combinedPattern: 'מיעוט',
          wordPatterns: ['מיעוט'],
          wordBoundaryEligible: [true],
        ),
      );

      // התבנית מתאימה את "מיעוט" בתוך "שמיעוטי", אך הגבול בקצה ההתאמה נכשל
      // (לפניו "ש", אחריו "י") — אין הדגשה.
      final result = highLight('ראה שמיעוטי כאן', query);
      expect(result, isNot(contains('<span')));
    });

    test('הזנת תבנית חדשה מעדכנת את גרסת ההדגשה לרינדור-מחדש', () async {
      final before = highlightPatternRevision.value;
      await primeHighlightPattern(
        searchQuery: 'דוד המלך',
        searchOptions: const {},
        alternativeWords: const {},
        spacingValues: const {},
        searchDistance: 0,
        isFuzzy: false,
        fetch: () async => primedPattern,
      );
      expect(highlightPatternRevision.value, greaterThan(before));
    });
  }, skip: engineReady ? false : searchEngineSkipReason);

  group('גבולות מילה מול מפרידים עבריים', () {
    test('סוף-פסוק דבוק אינו נבלע בגבול המילה', () {
      // ׃ (U+05C3) מפריד מילים כמו במנוע — "ברא" לפני ׃ הוא טוקן שלם
      // וההדגשה חייבת לעבור את בדיקת הגבול, גם ללא רווח אחרי ה-׃.
      final result = highLight('בְּרֵאשִׁית ברא\u{05C3}והארץ היתה', 'ברא');
      expect(result, contains('<span style="color: red">ברא</span>'));
    });

    test('נו"ן הפוכה אינה נבלעת בגבול המילה', () {
      final result = highLight('פסוק\u{05C6} אחר', 'פסוק');
      expect(result, contains('<span style="color: red">פסוק</span>'));
    });

    test('ליגטורת יידיש לפני התאמה אינה נחשבת גבול מילה', () {
      final result = highLight('אב\u{05F0}שלום', 'שלום');
      expect(result, isNot(contains('<span')));
    });

    test('צורת תצוגה עברית לפני התאמה אינה נחשבת גבול מילה', () {
      final result = highLight('אב\u{FB1D}שלום', 'שלום');
      expect(result, isNot(contains('<span')));
    });
  }, skip: engineReady ? false : searchEngineSkipReason);
}
