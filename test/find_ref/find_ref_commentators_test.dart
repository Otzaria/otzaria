import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/find_ref/repository/db_commentator_entry.dart';
import 'package:otzaria/find_ref/repository/db_reference_result.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';
import 'package:otzaria/services/commentary_service.dart';

// המבחנים בודקים את ההתנהגות האמיתית של
// [FindRefRepository.getCommentatorsForResult] — לא שכפול מקומי.
// אנחנו מזריקים את שורות המפרשים הגולמיות דרך ה-constructor
// (`fetchCommentatorRows` / `getBookEra`) ובודקים שהקוד האמיתי מנקה כפילויות,
// ממיין לפי דורות, מוסיף ל-cache, ומכבד את התנאים של PDF / bookId<=0 /
// isUserBook, ובונה את ה-`targetSegment` מ-`targetLineIndex`.
//
// חישוב **טווח** הקטע (כותרת עד הכותרת הבאה / כל הספר כשאין כותרות פנימיות)
// אינו באחריות ה-repository הזה אלא של [SeforimRepository.getCommentatorsForReference]
// — ולכן הוא נבדק בנפרד מול DB אמיתי, לא כאן.
//
// במבחנים ללא [getBookEra] אנו מסתמכים על fallback ל-CommentaryService.getBookEra:
// בסביבת טסט SqliteDataProvider אינו מאותחל ולכן הוא מחזיר CommentaryEra.other
// לכל המפרשים — מה שגורר מיון אלפביתי על פי `String.compareTo`.

DbReferenceResult _ref({
  int bookId = 10,
  int sourceLineId = 1,
  int segment = 1,
  int tocLevel = 1,
  bool isAltToc = false,
  bool isPdf = false,
  bool isUserBook = false,
}) => DbReferenceResult(
  title: 'בראשית',
  reference: 'בראשית פרק א',
  segment: segment,
  bookId: bookId,
  sourceLineId: sourceLineId,
  tocLevel: tocLevel,
  isAltToc: isAltToc,
  isPdf: isPdf,
  isUserBook: isUserBook,
);

FindRefRepository _repoWith({
  Future<List<Map<String, dynamic>>> Function(DbReferenceResult)? fetch,
  Future<CommentaryEra> Function(String)? era,
}) => FindRefRepository(
  fetchCommentatorRows: fetch,
  getBookEra: era,
);

List<String> _titles(List<DbCommentatorEntry> entries) => [
  for (final e in entries) e.title,
];

void main() {
  group('FindRefRepository.getCommentatorsForResult — קוד היצור', () {
    test('PDF — מחזיר רשימה ריקה בלי קריאה ל-loader', () async {
      var calls = 0;
      final repo = _repoWith(
        fetch: (ref) async {
          calls++;
          return const [];
        },
      );

      final result = await repo.getCommentatorsForResult(
        _ref(isPdf: true, bookId: -1),
      );

      expect(result, isEmpty);
      expect(calls, 0);
    });

    test('bookId ≤ 0 — מחזיר רשימה ריקה בלי קריאה ל-loader', () async {
      var calls = 0;
      final repo = _repoWith(
        fetch: (ref) async {
          calls++;
          return const [];
        },
      );

      final result = await repo.getCommentatorsForResult(_ref(bookId: -1));

      expect(result, isEmpty);
      expect(calls, 0);
    });

    test('isUserBook — לא קורא ל-loader (namespace collision)', () async {
      var calls = 0;
      final repo = _repoWith(
        fetch: (ref) async {
          calls++;
          return [
            {'targetBookTitle': 'מפרש מספר אחר'},
          ];
        },
      );

      final result = await repo.getCommentatorsForResult(
        _ref(isUserBook: true, bookId: 5, sourceLineId: 42),
      );

      expect(result, isEmpty);
      expect(calls, 0);
    });

    test('`targetSegment` נלקח מ-`targetLineIndex`', () async {
      final repo = _repoWith(
        fetch: (ref) async => [
          {'targetBookTitle': 'רש"י', 'targetLineIndex': 100},
          {'targetBookTitle': 'אבן עזרא', 'targetLineIndex': 250},
        ],
      );

      final result = await repo.getCommentatorsForResult(
        _ref(sourceLineId: 42, segment: 7),
      );

      final segmentByTitle = {for (final e in result) e.title: e.targetSegment};
      expect(segmentByTitle['רש"י'], 100);
      expect(segmentByTitle['אבן עזרא'], 250);
    });

    test('row בלי `targetLineIndex` — targetSegment=null', () async {
      // הגנה: אם ה-row אינו מכיל targetLineIndex (row חריג), `targetSegment`
      // יישאר null. הצרכן (הדיאלוג) יפתח את ספר המפרש בתחילתו.
      final repo = _repoWith(
        fetch: (ref) async => [
          {'targetBookTitle': 'רש"י'}, // אין targetLineIndex
        ],
      );

      final result = await repo.getCommentatorsForResult(
        _ref(sourceLineId: 42, segment: 17),
      );

      expect(result.single.title, 'רש"י');
      expect(result.single.targetSegment, isNull);
    });

    test('מיון לפי דורות: עם injection של [getBookEra]', () async {
      // ה-loader מחזיר 4 מפרשים בסדר שרירותי. ה-eraResolver ממפה כל אחד לדור
      // אחר. אנו מאמתים שהמיון הוא: chazal → rishonim → acharonim → modern.
      // השמות לא ממוינים אלפביתית — לכן אם המיון נשבר, הסדר ישתנה.
      final repo = _repoWith(
        fetch: (ref) async => [
          {'targetBookTitle': 'מחבר מודרני'},
          {'targetBookTitle': 'משנה'},
          {'targetBookTitle': 'רמב"ם'},
          {'targetBookTitle': 'חתם סופר'},
        ],
        era: (title) async {
          switch (title) {
            case 'משנה':
              return CommentaryEra.chazal;
            case 'רמב"ם':
              return CommentaryEra.rishonim;
            case 'חתם סופר':
              return CommentaryEra.acharonim;
            case 'מחבר מודרני':
              return CommentaryEra.modern;
            default:
              return CommentaryEra.other;
          }
        },
      );

      final result = await repo.getCommentatorsForResult(_ref());

      expect(_titles(result), ['משנה', 'רמב"ם', 'חתם סופר', 'מחבר מודרני']);
    });

    test('מיון אלפביתי בתוך אותו דור', () async {
      // כל המפרשים באותו דור (rishonim) → סדר אלפביתי גובר.
      final repo = _repoWith(
        fetch: (ref) async => [
          {'targetBookTitle': 'רש"י'},
          {'targetBookTitle': 'אבן עזרא'},
          {'targetBookTitle': 'רמב"ן'},
        ],
        era: (title) async => CommentaryEra.rishonim,
      );

      final result = await repo.getCommentatorsForResult(_ref());

      // אלפביתי עברי: 'אבן עזרא' (א) < 'רמב"ן' (ר+מ) < 'רש"י' (ר+ש).
      expect(_titles(result), ['אבן עזרא', 'רמב"ן', 'רש"י']);
    });

    test(
      'מסיר כפילויות לפי (targetBookTitle, targetBookId) — שומר על הראשון',
      () async {
        // אם אותו (title, bookId) מופיע פעמיים, אנחנו שומרים על ה-row הראשון
        // (כולל ה-targetLineIndex שלו). שני קישורים שונים לאותו מפרש שונים זה
        // מזה רק ב-targetLineIndex, אנחנו רוצים את הראשון (המוקדם בקטע).
        final repo = _repoWith(
          fetch: (ref) async => [
            {
              'targetBookTitle': 'רש"י',
              'targetBookId': 50,
              'targetLineIndex': 100,
            },
            {
              'targetBookTitle': 'רש"י',
              'targetBookId': 50,
              'targetLineIndex': 999,
            },
            {
              'targetBookTitle': 'אבן עזרא',
              'targetBookId': 60,
              'targetLineIndex': 50,
            },
          ],
        );

        final result = await repo.getCommentatorsForResult(
          _ref(sourceLineId: 1),
        );

        expect(_titles(result), ['אבן עזרא', 'רש"י']);
        final segmentByTitle = {
          for (final e in result) e.title: e.targetSegment,
        };
        expect(segmentByTitle['רש"י'], 100); // ראשון, לא 999
        expect(segmentByTitle['אבן עזרא'], 50);
      },
    );

    test('שני מפרשים בעלי אותה כותרת ו-targetBookId שונה — שניהם נשמרים '
        '(P1 רגרסיה)', () async {
      // המקרה שהדיפף נועד לתקן: book table יכול להכיל שני book records נפרדים
      // עם אותה כותרת (למשל "רש"י" על תורה ועל בבלי). dedupe לפי title בלבד
      // היה זורק אחד. כעת dedupe לפי (title, bookId) שומר את שניהם.
      final repo = _repoWith(
        fetch: (ref) async => [
          {
            'targetBookTitle': 'רש"י',
            'targetBookId': 100,
            'targetLineIndex': 10,
          },
          {
            'targetBookTitle': 'רש"י',
            'targetBookId': 200,
            'targetLineIndex': 20,
          },
        ],
      );

      final result = await repo.getCommentatorsForResult(_ref(sourceLineId: 1));

      expect(
        result,
        hasLength(2),
        reason: 'שני מפרשים בעלי targetBookId שונה לא יכולים להתאחד',
      );
      final byBookId = {for (final e in result) e.bookId: e};
      expect(byBookId[100], isNotNull);
      expect(byBookId[100]!.targetSegment, 10);
      expect(byBookId[200], isNotNull);
      expect(byBookId[200]!.targetSegment, 20);
      expect(result.every((e) => e.title == 'רש"י'), isTrue);
    });

    test('rows ללא targetBookId — נחשבים אותו "ספר" ומתאחדים '
        '(תאימות לאחור)', () async {
      // אם DB ישן לא מחזיר targetBookId, כל ה-rows באותו title חולקים מפתח
      // dedupe (title, null) — והשני מסונן.
      final repo = _repoWith(
        fetch: (ref) async => [
          {'targetBookTitle': 'רש"י', 'targetLineIndex': 11},
          {'targetBookTitle': 'רש"י', 'targetLineIndex': 22},
        ],
      );

      final result = await repo.getCommentatorsForResult(_ref(sourceLineId: 1));

      expect(result, hasLength(1));
      expect(result.single.bookId, isNull);
      expect(result.single.targetSegment, 11);
    });

    test('targetBookTitle ריק/null — מדלג', () async {
      final repo = _repoWith(
        fetch: (ref) async => [
          {'targetBookTitle': null},
          {'targetBookTitle': ''},
          {'targetBookTitle': 'רש"י'},
        ],
      );

      final result = await repo.getCommentatorsForResult(_ref());

      expect(_titles(result), ['רש"י']);
    });

    test('cache — קריאה שנייה לא קוראת ל-loader שוב', () async {
      var calls = 0;
      final repo = _repoWith(
        fetch: (ref) async {
          calls++;
          return [
            {'targetBookTitle': 'רש"י'},
          ];
        },
      );

      final first = await repo.getCommentatorsForResult(_ref());
      final second = await repo.getCommentatorsForResult(_ref());

      expect(_titles(first), ['רש"י']);
      expect(_titles(second), ['רש"י']);
      expect(calls, 1);
      // אותה רשימה מהקאש (זהות אובייקטים).
      expect(identical(first, second), isTrue);
    });

    test('cache — מפרידים לפי (bookId, sourceLineId)', () async {
      var calls = 0;
      final repo = _repoWith(
        fetch: (ref) async {
          calls++;
          return [
            {'targetBookTitle': 'מפרש ל-${ref.sourceLineId}'},
          ];
        },
      );

      final r1 = await repo.getCommentatorsForResult(_ref(sourceLineId: 42));
      final r2 = await repo.getCommentatorsForResult(_ref(sourceLineId: 7));

      expect(_titles(r1), ['מפרש ל-42']);
      expect(_titles(r2), ['מפרש ל-7']);
      expect(calls, 2);
    });

    test(
      'cache — TOC רגיל ו-AltToc על אותה שורה לא מתערבבים (P1 רגרסיה)',
      () async {
        // שני refs יכולים לחלוק את אותו (bookId, sourceLineId) — לדוגמה
        // "בראשית פרק א" (TOC) ו"פרשת בראשית" (AltToc), שתחילתם באותה line.id —
        // אבל הטווח המחושב להם שונה (boundary מ-TOC vs alt_toc_entry). אם המפתח
        // לא כולל את isAltToc/level/segment, ה-loader נקרא פעם אחת והרשומה
        // השנייה תקבל מפרשים שגויים מהקאש של הראשונה.
        var calls = 0;
        final repo = _repoWith(
          fetch: (ref) async {
            calls++;
            return [
              {'targetBookTitle': ref.isAltToc ? 'מפרש-AltToc' : 'מפרש-TOC'},
            ];
          },
        );

        final tocRef = _ref(sourceLineId: 100, tocLevel: 2, isAltToc: false);
        final altRef = _ref(sourceLineId: 100, tocLevel: 1, isAltToc: true);

        final tocResult = await repo.getCommentatorsForResult(tocRef);
        final altResult = await repo.getCommentatorsForResult(altRef);

        expect(_titles(tocResult), ['מפרש-TOC']);
        expect(_titles(altResult), ['מפרש-AltToc']);
        expect(
          calls,
          2,
          reason:
              'שני refs עם אותו sourceLineId אך isAltToc שונה דורשים '
              'fetch נפרד — אסור להם לחלוק cache',
        );
      },
    );

    test('ספרים שונים — לא מערבבים cache', () async {
      var calls = 0;
      final repo = _repoWith(
        fetch: (ref) async {
          calls++;
          return [
            {'targetBookTitle': 'מפרש לספר ${ref.bookId}'},
          ];
        },
      );

      final r1 = await repo.getCommentatorsForResult(_ref(bookId: 10));
      final r2 = await repo.getCommentatorsForResult(_ref(bookId: 20));

      expect(_titles(r1), ['מפרש לספר 10']);
      expect(_titles(r2), ['מפרש לספר 20']);
      expect(calls, 2);
    });

    test('בלי injection ובלי DB — מחזיר ריק בלי לזרוק', () async {
      // ה-repository ייפול ל-`SqliteDataProvider.instance.repository` שמחזיר
      // null כאשר ה-DB לא מאותחל (כמו בסביבת טסט). המתודה אמורה להחזיר ריק
      // ולא לזרוק.
      final repo = FindRefRepository();
      final result = await repo.getCommentatorsForResult(_ref());
      expect(result, isEmpty);
    });
  });
}
