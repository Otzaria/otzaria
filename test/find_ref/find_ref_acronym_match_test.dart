import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/cache/acronyms_cache.dart';
import 'package:otzaria/data/cache/books_cache.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';
import 'package:otzaria/find_ref/repository/reference_books_cache.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

/// טסטים למסלול ההתאמה **האמיתי** של "איתור מקורות": [ReferenceBooksCache.search]
/// (התאמת כותרות + ראשי תיבות מ-`book_acronym`) יחד עם [FindRefRepository.findRefs],
/// ללא הזרקת `searchReferenceBooks`. הכותרות וראשי-התיבות בטסטים הם נתוני אמת
/// מ-`seforim.db`, כולל מזהי הספרים.
typedef _SeedBook = ({int id, String title, List<String> acronyms});

/// זורע ספרייה קטנה לשלושת המטמונים שמסלול ההתאמה קורא מהם.
void _seedLibrary(List<_SeedBook> books) {
  BooksCache.instance.setBooksForTesting([
    for (var i = 0; i < books.length; i++)
      BookCacheEntry(
        id: books[i].id,
        title: books[i].title,
        filePath: '',
        fileType: 'txt',
        categoryId: 1,
        orderIndex: i.toDouble(),
      ),
  ]);
  AcronymsCache.instance.setAcronymsForTesting({
    for (final b in books) b.id: b.acronyms,
  });
  ReferenceBooksCache.instance
    ..setFsPdfBooksForTesting(const [])
    ..seedForTesting(
      normalizedTitles: {
        for (final b in books) b.id: normalizeForFindRefMatch(b.title),
      },
      categoryPaths: {for (final b in books) b.id: 'ספרייה'},
    );
}

final _repos = <FindRefRepository>[];

FindRefRepository _buildRepo({
  Map<int, List<Map<String, dynamic>>> tocEntries = const {},
  List<List<String>?>? tocQueryTokensSeen,
}) {
  final repo = FindRefRepository(
    isReferenceBooksCacheLoaded: () => true,
    warmUpReferenceBooksCache: () async {},
    getTocEntriesForReference: (bookId, bookTitle, {queryTokens}) async {
      tocQueryTokensSeen?.add(queryTokens);
      return tocEntries[bookId] ?? const <Map<String, dynamic>>[];
    },
    getAltTocEntriesForReference: (bookId, bookTitle, {queryTokens}) async =>
        const <Map<String, dynamic>>[],
    getAllAltTocFlatEntries: () async => const <Map<String, dynamic>>[],
    getCategoryPath: (bookId) async => 'ספרייה',
  );
  _repos.add(repo);
  return repo;
}

// --- נתוני אמת מ-seforim.db (ראשי-התיבות בסדר הטעינה: ORDER BY term) ---

const _rambamTefila = (
  id: 302,
  title: 'משנה תורה, הלכות תפילה וברכת כהנים',
  acronyms: [
    'משנ"ת',
    'משנ"ת הלכות תפילה וברכת כהנים',
    'משנ"ת תפילה וברכת כהנים',
    'רמב"ם',
    'רמב"ם הל\' תפילה וברכת כהנים',
    'רמב"ם הלכות תפילה וברכת כהנים',
    'רמב"ם תפילה וברכת כהנים',
    'תפילה וברכת כהנים',
  ],
);

const _rambamSederTefila = (
  id: 307,
  title: 'משנה תורה, סדר התפילה',
  acronyms: [
    'משנ"ת הלכות תפילה',
    'משנ"ת תפילה',
    'משנה תורה הלכות תפילה',
    'רמב"ם',
    'רמב"ם הל\' תפילה',
    'רמב"ם הלכות תפילה',
    'רמב"ם תפילה',
  ],
);

const _tur = (
  id: 380,
  title: 'טור',
  acronyms: [
    'ארבעה טורים',
    'הטור',
    'טור אורח חיים',
    'טור חושן משפט',
    'טור יורה דעה',
  ],
);

const _rashiBereshit = (
  id: 3695,
  title: 'רש"י על בראשית',
  acronyms: ['רש"י', 'רש"י על ספר בראשית', 'רשי על בראשית'],
);

const _rashiBereshitRabba = (
  id: 3113,
  title: 'רש"י על בראשית רבה',
  acronyms: ['רש"י בראשית רבה', 'רשי על בראשית רבה'],
);

void main() {
  tearDown(() {
    for (final r in _repos) {
      r.disposeForTesting();
    }
    _repos.clear();
    BooksCache.instance.clear();
    AcronymsCache.instance.clear();
    ReferenceBooksCache.instance.clear();
  });

  group('findRefs — ראש-תיבות שהוא תחילית של ראש-תיבות ארוך יותר', () {
    test('"רמב״ם תפילה" מחזיר גם את הלכות תפילה וברכת כהנים וגם את סדר '
        'התפילה', () async {
      // הבאג המדווח: ל"משנה תורה, סדר התפילה" יש ראש-תיבות *מדויק* "רמב"ם תפילה"
      // (rank 3), ולכן החיפוש נעצר עליו; "משנה תורה, הלכות תפילה וברכת כהנים"
      // הותאם רק כתחילית של "רמב"ם תפילה וברכת כהנים" (rank 4) ונזרק כליל.
      _seedLibrary(const [_rambamTefila, _rambamSederTefila]);
      final results = await _buildRepo().findRefs('רמב״ם תפילה');
      final titles = results.map((r) => r.title).toList();

      expect(titles, contains('משנה תורה, הלכות תפילה וברכת כהנים'));
      expect(titles, contains('משנה תורה, סדר התפילה'));
    });

    test('גרשיים יוניקוד (״) וגרשיים ASCII (") מחזירים אותן תוצאות', () async {
      _seedLibrary(const [_rambamTefila, _rambamSederTefila]);
      final unicode = await _buildRepo().findRefs('רמב״ם תפילה');
      final ascii = await _buildRepo().findRefs('רמב"ם תפילה');

      expect(
        ascii.map((r) => r.reference).toList(),
        unicode.map((r) => r.reference).toList(),
      );
    });

    test('כל ספרי "חידושי רע"א" מוחזרים, לא רק זה שיש לו ראש-התיבות '
        'המדויק', () async {
      // ל"על מסכת תענית" יש ראש-תיבות מדויק "חידושי רע"א"; לשאר הספרים יש רק
      // ראשי-תיבות ארוכים יותר שהשאילתה היא תחילית שלהם.
      _seedLibrary(const [
        (
          id: 2661,
          title: 'חידושי רבי עקיבא איגר על מסכת תענית',
          acronyms: [
            'חידושי רבי עקיבא איגר תענית',
            'חידושי רע"א',
            'חידושי רע"א על תענית',
            'חידושי רעא על מסכת תענית',
          ],
        ),
        (
          id: 2667,
          title: 'חידושי רבי עקיבא איגר על מסכת ראש השנה',
          acronyms: [
            'חידושי רע"א ראש השנה',
            'חידושי רעא על מסכת ראש השנה',
            'חידושי רעא על ראש השנה',
          ],
        ),
        (
          id: 4429,
          title: 'חידושי רבי עקיבא איגר על משנה תורה, הלכות יסודי התורה',
          acronyms: [
            'חידושי רבי עקיבא איגר יסודי התורה',
            'חידושי רעא על משנה תורה, הלכות יסודי התורה',
          ],
        ),
      ]);

      final titles = (await _buildRepo().findRefs(
        'חידושי רע"א',
      )).map((r) => r.title).toSet();

      expect(titles, contains('חידושי רבי עקיבא איגר על מסכת תענית'));
      expect(titles, contains('חידושי רבי עקיבא איגר על מסכת ראש השנה'));
      expect(
        titles,
        contains('חידושי רבי עקיבא איגר על משנה תורה, הלכות יסודי התורה'),
      );
    });

    test('"רש"י בראשית" לא מוסתר ע"י "רש"י על בראשית רבה"', () async {
      // ל"בראשית רבה" יש ראש-תיבות "רש"י בראשית רבה" שהשאילתה היא תחילית שלו
      // וזנבו ("רבה") הוא מילת-כותרת. הקבלה שלו אסור לה לעצור את החיפוש בשלב
      // הזה — "רש"י על בראשית" נמצא רק בשלב של טוקן אחד ("רש"י" + "בראשית"
      // מהכותרת), והיה נעלם.
      _seedLibrary(const [_rashiBereshit, _rashiBereshitRabba]);
      final titles = (await _buildRepo().findRefs(
        'רש"י בראשית',
      )).map((r) => r.title).toList();

      expect(titles, contains('רש"י על בראשית'));
      expect(titles, contains('רש"י על בראשית רבה'));
    });

    test(
      '"טור חושן" עדיין יורד לכותרות הפנימיות ולא הופך לתוצאת-ספר',
      () async {
        // "טור חושן" הוא תחילית של ראש-התיבות "טור חושן משפט", אבל "משפט" אינה
        // מילה בכותרת "טור" — כלומר ההמשך הוא כותרת פנימית. אם הספר היה מוחזר
        // כתוצאת-ספר, ה-reference הקצר ("טור") היה גם *חוסם* את התוצאה הפנימית
        // ב-_suppressDeeperVariants.
        _seedLibrary(const [_tur]);
        final seen = <List<String>?>[];
        final results = await _buildRepo(
          tocQueryTokensSeen: seen,
          tocEntries: const {
            380: [
              {'reference': 'טור חושן משפט', 'segment': 5, 'level': 1},
            ],
          },
        ).findRefs('טור חושן');

        expect(
          seen.any((t) => t != null && t.length == 1 && t.first == 'חושן'),
          isTrue,
          reason: 'ה-TOC חייב להיחפש לפי טוקן הסעיף "חושן"',
        );
        expect(results.map((r) => r.reference), contains('טור חושן משפט'));
        expect(
          results.map((r) => r.reference),
          isNot(contains('טור')),
          reason: 'תוצאת-ספר קצרה הייתה חוסמת את התוצאה הפנימית',
        );
      },
    );

    test(
      'שאילתת מילה אחת ("רמב"ם") מחזירה את כל הספרים בלי חיפוש TOC',
      () async {
        _seedLibrary(const [_rambamTefila, _rambamSederTefila]);
        final seen = <List<String>?>[];
        final titles = (await _buildRepo(
          tocQueryTokensSeen: seen,
        ).findRefs('רמב"ם')).map((r) => r.title).toSet();

        expect(titles, contains('משנה תורה, הלכות תפילה וברכת כהנים'));
        expect(titles, contains('משנה תורה, סדר התפילה'));
        expect(seen, isEmpty);
      },
    );
  });

  group('ReferenceBooksCache.search — דירוג התאמת ראשי תיבות', () {
    test('ראש-תיבות מדויק מקבל rank 3', () {
      _seedLibrary(const [_rambamSederTefila]);
      final hit = ReferenceBooksCache.instance.search('רמב"ם תפילה').single;

      expect(hit.bookId, 307);
      expect(hit.matchRank, 3);
    });

    test('תחילית שכל זנבה מילות-כותרת → rank 4 עם '
        'acronymTailIsTitleWords', () async {
      _seedLibrary(const [_rambamTefila]);
      final hit = ReferenceBooksCache.instance.search('רמב"ם תפילה').single;

      expect(hit.matchRank, 4);
      expect(
        hit.matchedTerm,
        normalizeForFindRefMatch('רמב"ם תפילה וברכת כהנים'),
      );
      expect(hit.acronymTailIsTitleWords, isTrue);
    });

    test('תחילית שזנבה כותרת פנימית → rank 4 בלי '
        'acronymTailIsTitleWords', () {
      _seedLibrary(const [_tur]);
      final hit = ReferenceBooksCache.instance.search('טור חושן').single;

      expect(hit.matchRank, 4);
      expect(hit.acronymTailIsTitleWords, isFalse);
    });

    test('התאמת התחילית נמדדת במילים שלמות — "רמב"ם תפיל" אינו זיהוי '
        'מלא', () {
      _seedLibrary(const [_rambamTefila, _rambamSederTefila]);
      final hits = ReferenceBooksCache.instance.search('רמב"ם תפיל');

      expect(hits, isNotEmpty);
      for (final hit in hits) {
        expect(hit.acronymTailIsTitleWords, isFalse, reason: hit.title);
      }
    });

    test('מונח "contains" שנסרק ראשון אינו מקבע rank 5 ומונע את התאמת '
        'התחילית', () {
      // ל"הלכות יסודי התורה" יש גם ראש-תיבות עם ו' החיבור ("ורמב"ם יסודי
      // התורה") שנסרק ראשון ורק *מכיל* את השאילתה, וגם "רמב"ם יסודי התורה"
      // שהוא תחילית אמיתית שלה.
      _seedLibrary(const [
        (
          id: 296,
          title: 'משנה תורה, הלכות יסודי התורה',
          acronyms: [
            'ורמב"ם הלכות יסודי התורה',
            'ורמב"ם יסודי התורה',
            'רמב"ם הל\' יסודי התורה',
            'רמב"ם הלכות יסודי התורה',
            'רמב"ם יסודי התורה',
          ],
        ),
      ]);
      final hit = ReferenceBooksCache.instance.search('רמב"ם יסודי').single;

      expect(hit.matchRank, 4);
      expect(hit.acronymTailIsTitleWords, isTrue);
    });
  });
}
