import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/find_ref/find_ref_preference_store.dart';
import 'package:otzaria/find_ref/repository/alt_toc_flat_entry.dart';
import 'package:otzaria/find_ref/repository/db_reference_result.dart';
import 'package:otzaria/find_ref/repository/find_ref_ranking.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';
import 'package:otzaria/find_ref/repository/reference_books_cache.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/plugins/bridge/plugin_reference_resolver.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';
import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../helpers/memory_settings_cache.dart';

class _MockDataRepository extends Mock implements DataRepository {}

typedef _Book = ({int id, String title, String? path});

ReferenceBookHit _hit(_Book book, double orderIndex) => ReferenceBookHit(
  bookId: book.id,
  title: book.title,
  normalizedTitle: normalizeForFindRefMatch(book.title),
  filePath: '',
  fileType: 'txt',
  matchRank: 0,
  orderIndex: orderIndex,
);

/// ספרייה מוזרקת: [books] בסדר המדף, ו-[toc] מחזיר את ערכי התוכן של כל ספר.
FindRefRepository _repo(
  List<_Book> books, {
  List<Map<String, dynamic>> Function(_Book book, List<String> tokens)? toc,
  Map<int, List<_Book>> bases = const {},
  Future<List<Map<String, dynamic>>> Function(GlobalAltTocRequest)? globalAlt,
}) {
  final byId = {for (final b in books) b.id: b};
  final repo = FindRefRepository(
    dataRepository: _MockDataRepository(),
    isReferenceBooksCacheLoaded: () => true,
    warmUpReferenceBooksCache: () async {},
    searchReferenceBooks: (query, {int limit = 50}) => [
      for (var i = 0; i < books.length; i++) _hit(books[i], i + 1.0),
    ],
    getTocEntriesForReference: (bookId, title, {queryTokens}) async =>
        toc?.call(byId[bookId]!, queryTokens ?? const []) ?? const [],
    getAltTocEntriesForReference: (bookId, title, {queryTokens}) async =>
        const [],
    getAllAltTocFlatEntries: globalAlt == null ? () async => const [] : null,
    searchAltTocFlatEntries: globalAlt,
    getCategoryPathSync: (id) => byId[id]?.path,
    getCategoryPath: (id) async => byId[id]?.path ?? '',
    loadBookBaseTexts: () async => [
      for (final MapEntry(key: bookId, value: baseBooks) in bases.entries)
        for (final base in baseBooks)
          {'bookId': bookId, 'baseBookId': base.id, 'baseTitle': base.title},
    ],
  );
  addTearDown(repo.dispose);
  return repo;
}

FindRefPreferenceBook _pref(_Book book) =>
    (key: FindRefPreferences.officialBaseKey(book.id), title: book.title);

FindRefPreferences _opened(
  _Book book,
  int times, {
  FindRefPreferences from = FindRefPreferences.empty,
  List<_Book> bases = const [],
}) {
  var p = from;
  for (var i = 0; i < times; i++) {
    p = p.recordOpen(_pref(book), baseBooks: bases.map(_pref));
  }
  return p;
}

List<String> _titles(List<DbReferenceResult> results) => [
  for (final r in results) r.title,
];

/// כל מה שמבחין בין שתי תוצאות.
String _row(DbReferenceResult r) => [
  r.bookId,
  r.source.wireKey,
  r.title,
  r.reference,
  r.segment,
  r.isPdf,
  r.filePath,
  r.isAltToc,
  r.tocLevel,
  r.isSourceLine,
  r.isPartialTocMatch,
  r.bookPath,
].join('|');

List<String> _rows(List<DbReferenceResult> results) => [
  for (final r in results) _row(r),
];

/// האינווריאנט המרכזי: [personal] מכיל כל שורה של [plain], מוסיף מעטות, ומי
/// שאינו מספר מועדף שומר על סדרו.
void _expectOnlyReordered(
  List<DbReferenceResult> plain,
  List<DbReferenceResult> personal, {
  required Set<int> preferredBooks,
  String? reason,
}) {
  final plainRows = _rows(plain);
  final personalRows = _rows(personal);
  expect(personalRows.toSet(), containsAll(plainRows), reason: reason);
  expect(personalRows.toSet(), hasLength(personalRows.length), reason: reason);
  expect(
    personal.length - plain.length,
    inInclusiveRange(0, findRefPersonalMaxAdditions),
    reason: reason,
  );
  List<String> others(List<DbReferenceResult> list) => [
    for (final r in list)
      if (!preferredBooks.contains(r.bookId)) _row(r),
  ];
  expect(others(personal), others(plain), reason: reason);
}

const _sa = 'הלכה, שולחן ערוך';
const _Book _orach = (id: 1, title: 'שולחן ערוך אורח חיים', path: _sa);
const _Book _yoreh = (id: 2, title: 'שולחן ערוך יורה דעה', path: _sa);
const _Book _even = (id: 3, title: 'שולחן ערוך אבן העזר', path: _sa);
const _Book _choshen = (id: 4, title: 'שולחן ערוך חושן משפט', path: _sa);
const _shulchanAruch = [_orach, _yoreh, _even, _choshen];

List<Map<String, dynamic>> _simanToc(_Book book, List<String> tokens) => [
  {
    'reference': '${book.title} סימן ל',
    'segment': 30,
    'level': 2,
    'dbLineId': 0,
  },
];

const _Book _ritvaBerakhot = (id: 10, title: 'ריטב"א על ברכות', path: null);
const _Book _ritvaEruvin = (id: 11, title: 'ריטב"א על עירובין', path: null);
const _Book _eruvin = (id: 20, title: 'עירובין', path: 'תלמוד בבלי, סדר מועד');
const _Book _rashbaEruvin = (id: 21, title: 'רשב"א על עירובין', path: null);
const _Book _berakhot = (id: 30, title: 'ברכות', path: 'תלמוד בבלי, סדר זרעים');
const _talmudBases = {
  10: [_berakhot],
  11: [_eruvin],
  21: [_eruvin],
};

List<Map<String, dynamic>> _dafToc(_Book book, List<String> tokens) => [
  {
    'reference': '${book.title} דף ל.',
    'segment': 60,
    'level': 2,
    'dbLineId': 0,
  },
];

const _sections = ['דף', 'פרק', 'סימן', 'שער', 'כלל', 'אות', 'ענף', 'חלק'];

/// כמה שורות לכל ספר, כמו בספרייה אמיתית: [count] ערכי תוכן שונים.
List<Map<String, dynamic>> Function(_Book, List<String>) _manyRows(int count) =>
    (book, tokens) => [
      for (var i = 0; i < count; i++)
        {
          'reference': '${book.title} ${_sections[i]} ב',
          'segment': 10 * (i + 1),
          'level': 2,
          'dbLineId': 0,
        },
    ];

/// מפתח דירוג סינתטי לבדיקות הפונקציה הטהורה.
FindRefRankKey<int> _key(
  int item, {
  int? tier,
  int era = 1,
  double order = 0,
  bool startsWith = true,
  bool citationMatch = true,
  bool partial = false,
  int level = 2,
}) => FindRefRankKey<int>(
  item: item,
  normTitle: 'ספר',
  fuzzyBookMatch: false,
  exactMatch: false,
  startsWithMatch: startsWith,
  titleWordMatches: const [true],
  citationMatch: citationMatch,
  bookRank: (foundationalTier: tier, eraOrder: era),
  isOfficial: true,
  orderIndex: order,
  specificity: findRefSpecificityRank(
    isSourceLine: false,
    isAltToc: false,
    tocLevel: level,
    isPartialTocMatch: partial,
  ),
  reference: 'ציון',
  segment: item,
  bookId: order.toInt(),
);

/// [cutoff] ברירת מחדל: אורך הרצף הפותח של [kept].
List<int> _personalize(
  List<FindRefRankKey<Object?>> sorted,
  List<int> kept,
  FindRefRankQuery query, {
  required List<String?> books,
  required List<double> affinities,
  int? cutoff,
}) {
  var prefix = 0;
  while (prefix < kept.length && kept[prefix] == prefix) {
    prefix++;
  }
  return personalizeFindRefOrder(
    sorted,
    kept,
    query,
    cutoff: cutoff ?? prefix,
    books: books,
    affinities: affinities,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  setUp(() async {
    await FindRefPreferenceStore.setEnabled(true);
    FindRefPreferenceStore.clear();
  });

  group('התרחישים מ-issue #5168', () {
    test('שו"ע סימן ל: בלי העדפות לפי סדר המדף', () async {
      final results = await _repo(
        _shulchanAruch,
        toc: _simanToc,
      ).findRefs('שולחן ערוך סימן ל');

      expect(_titles(results), [for (final b in _shulchanAruch) b.title]);
    });

    test('שו"ע סימן ל: מי שפותח חושן משפט מקבל אותו ראשון', () async {
      final results = await _repo(
        _shulchanAruch,
        toc: _simanToc,
      ).findRefs('שולחן ערוך סימן ל', preferences: _opened(_choshen, 3));

      // שאר החלקים נשארים בסדר המדף.
      expect(_titles(results), [
        _choshen.title,
        _orach.title,
        _yoreh.title,
        _even.title,
      ]);
    });

    test('שתי פתיחות בלבד עדיין מתחת לסף, והסדר אינו משתנה', () async {
      final results = await _repo(
        _shulchanAruch,
        toc: _simanToc,
      ).findRefs('שולחן ערוך סימן ל', preferences: _opened(_choshen, 2));

      expect(results.first.title, _orach.title);
    });

    test('ריטב"א דף ל: לומד עירובין מקבל את הריטב"א על עירובין', () async {
      FindRefRepository repo() => _repo(
        [_ritvaBerakhot, _ritvaEruvin],
        toc: _dafToc,
        bases: _talmudBases,
      );

      final plain = await repo().findRefs('ריטב"א דף ל');
      expect(plain.first.title, _ritvaBerakhot.title);

      // הריטב"א עצמו לא נפתח מעולם: הזיקה מגיעה מספר הבסיס.
      var preferences = FindRefPreferences.empty;
      for (var i = 0; i < 2; i++) {
        preferences = _opened(_eruvin, 1, from: preferences);
        preferences = _opened(
          _rashbaEruvin,
          1,
          from: preferences,
          bases: [_eruvin],
        );
      }
      final personal = await repo().findRefs(
        'ריטב"א דף ל',
        preferences: preferences,
      );

      expect(_titles(personal), [_ritvaEruvin.title, _ritvaBerakhot.title]);
    });
  });

  group('רישום פתיחות ברפוזיטורי', () {
    test('פתיחת מפרש מזינה גם את ספר הבסיס', () async {
      final repo = _repo([_rashbaEruvin, _eruvin], bases: _talmudBases);
      for (var i = 0; i < 3; i++) {
        await repo.recordFindRefOpen(
          source: BookSource.official,
          bookId: _rashbaEruvin.id,
          title: _rashbaEruvin.title,
        );
      }

      final stored = FindRefPreferenceStore.snapshot()!;
      expect(stored.books.keys, ['o|21']);
      expect(stored.bases.keys.toSet(), {'o|21', 'o|20'});
      expect(stored.baseScore('o|20', _eruvin.title), closeTo(2.8525, 1e-9));
    });

    test('מפרש מתפריט שורת תוצאה מזכה גם את ספר התוצאה, באותו ניקוד', () async {
      final repo = _repo([_rashbaEruvin, _eruvin], bases: _talmudBases);
      const row = DbReferenceResult(
        title: 'עירובין',
        reference: 'עירובין דף ל.',
        segment: 60,
        bookId: 20,
      );
      for (var i = 0; i < 6; i++) {
        await repo.recordFindRefOpen(
          source: BookSource.official,
          bookId: _rashbaEruvin.id,
          title: _rashbaEruvin.title,
          openedFrom: row,
        );
      }

      final stored = FindRefPreferenceStore.snapshot()!;
      final commentator = stored.directScore('o|21', _rashbaEruvin.title);
      expect(commentator, greaterThan(FindRefPreferences.affinityThreshold));
      // בלי פער בין השניים אין למפרש דומיננטיות מלאכותית על הגמרא.
      expect(stored.directScore('o|20', _eruvin.title), commentator);
    });

    test('מפרש בלי זהות: שורת התוצאה שלו עדיין נרשמת', () async {
      final repo = _repo([_rashbaEruvin, _eruvin], bases: _talmudBases);
      await repo.recordFindRefOpen(
        source: BookSource.official,
        bookId: null,
        title: 'מפרש בלי מזהה',
        openedFrom: const DbReferenceResult(
          title: 'רשב"א על עירובין',
          reference: 'רשב"א על עירובין דף ל.',
          segment: 60,
          bookId: 21,
        ),
      );

      final stored = FindRefPreferenceStore.load();
      expect(stored.books.keys, ['o|21']);
      expect(stored.bases.keys.toSet(), {'o|21', 'o|20'});
    });

    test('ספר בלי זהות וספר לא-רשמי אינם שולפים ספרי בסיס', () async {
      var loads = 0;
      final repo = FindRefRepository(
        dataRepository: _MockDataRepository(),
        loadBookBaseTexts: () async {
          loads++;
          return const [];
        },
      );
      addTearDown(repo.dispose);

      await repo.recordFindRefOpen(
        source: BookSource.official,
        bookId: -1,
        title: 'בלי זהות',
      );
      await repo.recordFindRefOpen(
        source: BookSource.user,
        bookId: 21,
        title: 'ספר אישי',
      );

      expect(loads, 0);
      // מזהה אישי אינו מתנגש במזהה הרשמי הזהה.
      expect(FindRefPreferenceStore.load().books.keys, ['u|21']);
    });

    for (final reset in [true, false]) {
      test(
        reset
            ? 'איפוס מבטל פתיחה שטרם נרשמה'
            : 'כיבוי והפעלה מחדש מבטלים פתיחה שטרם נרשמה',
        () async {
          final bases = Completer<List<Map<String, dynamic>>>();
          final repo = FindRefRepository(
            dataRepository: _MockDataRepository(),
            loadBookBaseTexts: () => bases.future,
          );
          addTearDown(repo.dispose);

          final opening = repo.recordFindRefOpen(
            source: BookSource.official,
            bookId: _rashbaEruvin.id,
            title: _rashbaEruvin.title,
          );
          if (reset) {
            FindRefPreferenceStore.clear();
          } else {
            await FindRefPreferenceStore.setEnabled(false);
            await FindRefPreferenceStore.setEnabled(true);
          }
          bases.complete(const []);
          await opening;

          expect(FindRefPreferenceStore.load().isEmpty, isTrue);
        },
      );
    }

    test('כשל בשליפת ספרי הבסיס אינו מונע את הרישום ואינו נזרק', () async {
      final repo = FindRefRepository(
        dataRepository: _MockDataRepository(),
        loadBookBaseTexts: () async => throw StateError('db down'),
      );
      addTearDown(repo.dispose);

      await repo.recordFindRefOpen(
        source: BookSource.official,
        bookId: 21,
        title: _rashbaEruvin.title,
      );

      expect(FindRefPreferenceStore.load().books.keys, ['o|21']);
    });

    test(
      'שליפה שהתחילה לפני clearCaches אינה מקבעת מפה של ספרייה ישנה',
      () async {
        var loads = 0;
        late FindRefRepository repo;
        repo = FindRefRepository(
          dataRepository: _MockDataRepository(),
          loadBookBaseTexts: () async {
            final first = loads++ == 0;
            // הספרייה מתחלפת בזמן שהשליפה הראשונה עוד בדרך.
            if (first) repo.clearCaches();
            return [
              {
                'bookId': 21,
                'baseBookId': first ? 20 : 99,
                'baseTitle': first ? 'ישן' : 'חדש',
              },
            ];
          },
        );
        addTearDown(repo.dispose);

        Future<void> open() => repo.recordFindRefOpen(
          source: BookSource.official,
          bookId: 21,
          title: _rashbaEruvin.title,
        );
        await open();
        await open();
        await open();

        // השליפה השנייה נקבעה בקאש, והשלישית כבר לא פנתה למסד.
        expect(loads, 2);
        expect(FindRefPreferenceStore.load().bases.keys, {'o|21', 'o|99'});
      },
    );
  });

  group('רגרסיות ה-QA: ספרים מרובי-שורות ומעל התקרה', () {
    const _Book mishnah = (id: 1, title: 'משנה ברכות', path: 'משנה, סדר זרעים');
    const _Book bavli = (id: 2, title: 'ברכות', path: 'תלמוד בבלי, סדר זרעים');
    const _Book rashi = (id: 3, title: 'רש"י על ברכות', path: null);
    const _Book meiri = (id: 9, title: 'מאירי על ברכות', path: null);
    final library = <_Book>[
      mishnah,
      bavli,
      rashi,
      for (var i = 4; i <= 8; i++)
        (id: i, title: 'מפרש $i על ברכות', path: null),
      meiri,
      for (var i = 10; i <= 14; i++)
        (id: i, title: 'מפרש $i על ברכות', path: null),
    ];
    const libraryBases = {
      3: [bavli],
      9: [bavli],
    };
    FindRefRepository repo() =>
        _repo(library, toc: _manyRows(6), bases: libraryBases);

    test('מאירי ×6: הגמרא, המשנה ורש"י אינם נעלמים', () async {
      final plain = await repo().findRefs('ברכות ב');
      final personal = await repo().findRefs(
        'ברכות ב',
        preferences: _opened(meiri, 6, bases: [bavli]),
      );

      // ה-fixture אכן מעל התקרה: לא כל שורות הספרייה מוצגות.
      expect(plain.length, lessThan(library.length * 6));
      _expectOnlyReordered(
        plain,
        personal,
        preferredBooks: {meiri.id, bavli.id, rashi.id},
      );
      for (final book in [mishnah, bavli, rashi]) {
        expect(
          personal.where((r) => r.bookId == book.id).length,
          plain.where((r) => r.bookId == book.id).length,
          reason: book.title,
        );
      }
      // מפרש אינו עוקף את ספר הבסיס שלו, גם כשהוא מועדף באופן מובהק.
      expect(_rows(personal).take(2), _rows(plain).take(2));
      expect(
        personal.where((r) => r.bookId == meiri.id).length,
        lessThanOrEqualTo(
          plain.where((r) => r.bookId == meiri.id).length +
              findRefPersonalRowsPerBook,
        ),
      );
    });

    test('רש"י ×6 מתפריט המפרשים של שורת הגמרא: הגמרא נשארת ראשונה', () async {
      final plain = await repo().findRefs('ברכות ב');
      final gemaraRow = plain.firstWhere((r) => r.bookId == bavli.id);
      final recorder = repo();
      for (var i = 0; i < 6; i++) {
        await recorder.recordFindRefOpen(
          source: BookSource.official,
          bookId: rashi.id,
          title: rashi.title,
          openedFrom: gemaraRow,
        );
      }

      final personal = await repo().findRefs(
        'ברכות ב',
        preferences: FindRefPreferenceStore.snapshot(),
      );

      expect(_row(personal.first), _row(plain.first));
      _expectOnlyReordered(
        plain,
        personal,
        preferredBooks: {rashi.id, bavli.id, meiri.id},
      );
    });

    test('ה-AltToc הגלובלי מתבקש זהה עם ובלי העדפות', () async {
      final requests = <String>[];
      FindRefRepository altRepo() => _repo(
        const [],
        globalAlt: (request) async {
          requests.add(request.encode().toString());
          return const [];
        },
      );

      await altRepo().findRefs('אורח חיים סימן ל');
      await altRepo().findRefs(
        'אורח חיים סימן ל',
        preferences: _opened(_orach, 9),
      );

      expect(requests, hasLength(2));
      expect(requests.last, requests.first);
    });

    test('קבוצת שוויון בגבול התקרה אינה מתפצלת (בראשית א)', () async {
      const _Book bereshit = (id: 1, title: 'בראשית', path: 'תנ"ך, תורה');
      const _Book rashiTorah = (id: 2, title: 'רש"י על בראשית', path: null);
      List<Map<String, dynamic>> toc(_Book book, List<String> tokens) => [
        for (var i = 0; i < 30; i++)
          {
            'reference': '${book.title} פרק א פסוק ${i + 1}',
            'segment': i,
            'level': 3,
            'dbLineId': 0,
          },
      ];
      FindRefRepository repo() => _repo([bereshit, rashiTorah], toc: toc);

      final plain = await repo().findRefs('בראשית א');
      final personal = await repo().findRefs(
        'בראשית א',
        preferences: _opened(rashiTorah, 6),
      );

      expect(plain.length, greaterThan(20));
      _expectOnlyReordered(plain, personal, preferredBooks: {rashiTorah.id});
      expect(_row(personal.first), _row(plain.first));
    });

    test('שורות הספר המועדף שמעבר לשתיים הראשונות נשארות במקומן', () async {
      const _Book a = (id: 1, title: 'אוצר ראשון', path: null);
      const _Book b = (id: 2, title: 'אוצר שני', path: null);
      // בלי ערך "דף": הוא מדורג במחלקת התאמה משלו, לפני שאר ערכי הספר.
      List<Map<String, dynamic>> toc(_Book book, List<String> tokens) =>
          _manyRows(6)(book, tokens).sublist(1);
      FindRefRepository repo() => _repo([a, b], toc: toc);

      final plain = await repo().findRefs('אוצר ב');
      final personal = await repo().findRefs(
        'אוצר ב',
        preferences: _opened(b, 4),
      );

      expect(_rows(personal).toSet(), _rows(plain).toSet());
      final aRows = [
        for (final r in plain)
          if (r.bookId == a.id) _row(r),
      ];
      final bRows = [
        for (final r in plain)
          if (r.bookId == b.id) _row(r),
      ];
      expect(bRows.length, greaterThan(findRefPersonalRowsPerBook));
      // שתי שורות בלבד עלו לראש; השאר אחרי כל שורות הספר הראשון, כמו היום.
      expect(_rows(personal), [...bRows.take(2), ...aRows, ...bRows.skip(2)]);
    });
  });

  group('התאמת טקסט גוברת תמיד', () {
    const _Book shabbat = (id: 1, title: 'שבת', path: 'תלמוד בבלי, סדר מועד');
    const _Book shabbatHaaretz = (id: 2, title: 'שבת הארץ', path: null);

    test('שם מלא קודם לספר מועדף שרק מתחיל בשאילתה', () async {
      final results = await _repo([
        shabbatHaaretz,
        shabbat,
      ]).findRefs('שבת', preferences: _opened(shabbatHaaretz, 12));

      expect(_titles(results), [shabbat.title, shabbatHaaretz.title]);
    });

    test('ציון דף מעדיף גמרא גם כשהמשנה מועדפת באופן מובהק', () async {
      const _Book mishnah = (
        id: 1,
        title: 'משנה ברכות',
        path: 'משנה, סדר זרעים',
      );
      const _Book bavli = (
        id: 2,
        title: 'ברכות',
        path: 'תלמוד בבלי, סדר זרעים',
      );
      List<Map<String, dynamic>> toc(_Book book, List<String> tokens) => [
        {
          'reference': book.id == 1
              ? '${book.title} פרק ב משנה א'
              : '${book.title} דף ב.',
          'segment': book.id,
          'level': 2,
          'dbLineId': 0,
        },
      ];

      for (final query in ['ברכות דף ב א', 'ברכות לב א']) {
        final plain = await _repo([mishnah, bavli], toc: toc).findRefs(query);
        final personal = await _repo([
          mishnah,
          bavli,
        ], toc: toc).findRefs(query, preferences: _opened(mishnah, 12));

        expect(plain.first.title, bavli.title, reason: query);
        expect(_rows(personal), _rows(plain), reason: query);
      }
    });
  });

  group('מפרש מול ספר הבסיס שלו', () {
    const _Book chumash = (id: 1, title: 'בראשית', path: 'תנ"ך, תורה');
    const _Book ramban = (id: 2, title: 'רמב"ן על בראשית', path: null);
    const _Book rashi = (id: 3, title: 'רש"י על בראשית', path: null);
    const books = [chumash, ramban, rashi];
    List<Map<String, dynamic>> toc(_Book book, List<String> tokens) => [
      {
        'reference': '${book.title} פרק א',
        'segment': 1,
        'level': 2,
        'dbLineId': 0,
      },
    ];

    test('מפרש שנפתח שוב ושוב אינו עוקף את ספר הבסיס', () async {
      final results = await _repo(
        books,
        toc: toc,
        bases: const {
          2: [chumash],
          3: [chumash],
        },
      ).findRefs('בראשית א', preferences: _opened(rashi, 8));

      // רש"י עדיין קודם לרמב"ן בתוך מחלקתו, אבל החומש נשאר ראשון.
      expect(_titles(results), [chumash.title, rashi.title, ramban.title]);
    });

    test('גם בלי שורת בסיס במסד המפרש אינו עוקף את החומש', () async {
      final results = await _repo(
        books,
        toc: toc,
      ).findRefs('בראשית א', preferences: _opened(rashi, 12));

      expect(_titles(results), [chumash.title, rashi.title, ramban.title]);
    });
  });

  group('התוצאה הראשונה אחרי 12 פתיחות ישירות', () {
    const _Book mishnehTorah = (
      id: 1,
      title: 'משנה תורה הלכות שבת',
      path: 'הלכה, משנה תורה, ספר זמנים',
    );
    const _Book mishnehLamelech = (id: 2, title: 'משנה למלך', path: null);
    const _Book mishnahBerurah = (id: 3, title: 'משנה ברורה', path: null);
    const books = [mishnehTorah, mishnehLamelech, mishnahBerurah];

    test('ספר יסוד נשאר ראשון; המועדף עוקף רק את שכנו למדף', () async {
      final plain = await _repo(books).findRefs('משנה');
      final personal = await _repo(
        books,
      ).findRefs('משנה', preferences: _opened(mishnahBerurah, 12));

      expect(_titles(plain), [for (final b in books) b.title]);
      expect(_titles(personal), [
        mishnehTorah.title,
        mishnahBerurah.title,
        mishnehLamelech.title,
      ]);
    });

    test('ראשונה שווה במחלקה ובספציפיות מתחלפת בספר המועדף', () async {
      final shelf = [mishnehLamelech, mishnahBerurah];
      final personal = await _repo(
        shelf,
      ).findRefs('משנה', preferences: _opened(mishnahBerurah, 12));

      expect(_titles(personal), [mishnahBerurah.title, mishnehLamelech.title]);
    });

    test('שורה פחות ספציפית של הספר המועדף אינה עולה לראש', () async {
      // אותה מחלקת התאמה, אבל הכותרת של המועדף עמוקה יותר בתוכן העניינים.
      List<Map<String, dynamic>> toc(_Book book, List<String> tokens) => [
        {
          'reference': '${book.title} סימן ל',
          'segment': 30,
          'level': book.id == mishnahBerurah.id ? 3 : 2,
          'dbLineId': 0,
        },
      ];
      final shelf = [mishnehLamelech, mishnahBerurah];
      final plain = await _repo(shelf, toc: toc).findRefs('משנה סימן ל');
      final personal = await _repo(
        shelf,
        toc: toc,
      ).findRefs('משנה סימן ל', preferences: _opened(mishnahBerurah, 12));

      expect(plain.first.title, mishnehLamelech.title);
      expect(_rows(personal), _rows(plain));
    });

    test('ספר מועדף שאינו בתוצאות אינו משנה דבר', () async {
      const _Book other = (id: 99, title: 'ספר אחר לגמרי', path: null);
      final results = await _repo(
        books,
      ).findRefs('משנה', preferences: _opened(other, 12));

      expect(_titles(results), [for (final b in books) b.title]);
    });
  });

  group('אינווריאנטים מקצה לקצה', () {
    final manyBooks = <_Book>[
      for (var i = 1; i <= 40; i++) (id: i, title: 'אוצר חלק $i', path: null),
    ];

    Future<void> expectSameAsPlain(
      FindRefRepository Function() repo,
      String query,
      FindRefPreferences preferences,
    ) async {
      final plain = await repo().findRefs(query);
      final personal = await repo().findRefs(query, preferences: preferences);
      expect(_rows(personal), _rows(plain), reason: query);
    }

    test('מאגר ריק או העדפות לספרים אחרים: סדר זהה להיום', () async {
      const _Book stranger = (id: 777, title: 'ספר זר', path: null);
      for (final preferences in [
        FindRefPreferences.empty,
        _opened(stranger, 15),
      ]) {
        await expectSameAsPlain(
          () => _repo(_shulchanAruch, toc: _simanToc),
          'שולחן ערוך סימן ל',
          preferences,
        );
        await expectSameAsPlain(
          () => _repo(
            [_ritvaBerakhot, _ritvaEruvin],
            toc: _dafToc,
            bases: _talmudBases,
          ),
          'ריטב"א דף ל',
          preferences,
        );
        await expectSameAsPlain(() => _repo(manyBooks), 'אוצר', preferences);
        await expectSameAsPlain(
          () => _repo(manyBooks, toc: _manyRows(4)),
          'אוצר ב',
          preferences,
        );
      }
    });

    test('ניקוד של מזהה שכותרתו התחלפה אינו משפיע', () async {
      await expectSameAsPlain(
        () => _repo(_shulchanAruch, toc: _simanToc),
        'שולחן ערוך סימן ל',
        _opened((id: _choshen.id, title: 'ספר שהיה כאן פעם', path: null), 12),
      );
    });

    test('מעל התקרה: ספר מועדף נוסף, ושום שורה אינה נדחקת החוצה', () async {
      final plain = await _repo(manyBooks).findRefs('אוצר');
      final preferred = manyBooks[36];
      expect(_titles(plain), isNot(contains(preferred.title)));

      final personal = await _repo(
        manyBooks,
      ).findRefs('אוצר', preferences: _opened(preferred, 4));

      expect(_titles(personal), [preferred.title, ..._titles(plain)]);
    });

    test('מעל התקרה מתווספות לכל היותר שש שורות', () async {
      final preferences = FindRefPreferences(
        books: {
          for (final book in manyBooks.skip(25))
            _pref(book).key: (score: 3.0, title: book.title),
        },
      );
      final plain = await _repo(manyBooks).findRefs('אוצר');
      final personal = await _repo(
        manyBooks,
      ).findRefs('אוצר', preferences: preferences);

      expect(personal.length, plain.length + findRefPersonalMaxAdditions);
      _expectOnlyReordered(
        plain,
        personal,
        preferredBooks: {for (final b in manyBooks.skip(25)) b.id},
      );
    });

    test('מכסת הזנב של התאמות תת-מחרוזת (#839) נשמרת', () async {
      final books = <_Book>[
        for (var i = 1; i <= 30; i++) (id: i, title: 'מאור $i', path: null),
        for (var i = 31; i <= 36; i++) (id: i, title: 'יומא $i', path: null),
      ];
      List<String> substringMatches(List<DbReferenceResult> results) => [
        for (final r in results)
          if (r.title.startsWith('יומא')) r.title,
      ];

      final plain = await _repo(books).findRefs('מא');
      final personal = await _repo(
        books,
      ).findRefs('מא', preferences: _opened(books[25], 9));

      expect(substringMatches(plain), isNotEmpty);
      expect(substringMatches(personal), substringMatches(plain));
      expect(_titles(personal), [books[25].title, ..._titles(plain)]);
    });
  });

  group('personalizeFindRefOrder', () {
    final query = FindRefRankQuery(['ספר']);

    test('בלי זיקה מוחזר החיתוך עצמו', () {
      final sorted = [for (var i = 0; i < 5; i++) _key(i, order: i + 0.0)];
      final result = _personalize(
        sorted,
        [0, 1, 2],
        query,
        books: ['a', 'b', 'c', 'd', 'e'],
        affinities: [0, 0, 0, 0, 0],
      );

      expect(result, [0, 1, 2]);
    });

    test('שורה מוקדמת רק בתוך מחלקת ההתאמה שלה', () {
      final sorted = [
        _key(0, tier: 3, order: 5),
        _key(1, order: 1),
        _key(2, order: 2),
        _key(3, order: 3),
      ];
      final result = _personalize(
        sorted,
        [0, 1, 2, 3],
        query,
        books: ['gemara', 'x', 'y', 'liked'],
        affinities: [0, 0, 0, 4],
      );

      expect(result, [0, 3, 1, 2]);
    });

    test('רק שתי השורות הראשונות של ספר מוקדמות, וחלקית אינה מוקדמת', () {
      final sorted = [
        _key(0, order: 1),
        _key(1, order: 2),
        _key(2, order: 2),
        _key(3, order: 2),
        _key(4, order: 2, partial: true),
      ];
      final result = _personalize(
        sorted,
        [0, 1, 2, 3, 4],
        query,
        books: ['x', 'liked', 'liked', 'liked', 'liked'],
        affinities: [0, 3, 3, 3, 3],
      );

      expect(result, [1, 2, 0, 3, 4]);
    });

    test('שורה מועדפת אינה עוקפת שורה ספציפית יותר', () {
      final sorted = [
        _key(0, order: 1, level: 2),
        // כותרת פנימית עמוקה: התאמה חלשה יותר מהשורה שמעליה.
        _key(1, order: 2, level: 3),
      ];
      final result = _personalize(
        sorted,
        [0, 1],
        query,
        books: ['x', 'liked'],
        affinities: [0, 9],
      );

      expect(result, [0, 1]);
    });

    test('שורה מועדפת עוקפת שורה שווה או פחות ספציפית', () {
      for (final level in [2, 3]) {
        final sorted = [
          _key(0, order: 1, level: level),
          _key(1, order: 2, level: 2),
        ];
        final result = _personalize(
          sorted,
          [0, 1],
          query,
          books: ['x', 'liked'],
          affinities: [0, 9],
        );

        expect(result, [1, 0], reason: 'level $level');
      }
    });

    test('מועמד נעצר בחוסם הראשון, גם כשמעליו שורות עבירות', () {
      final sorted = [
        _key(0, order: 1, level: 3),
        _key(1, order: 2, level: 2),
        _key(2, order: 3, level: 3),
      ];
      final result = _personalize(
        sorted,
        [0, 1, 2],
        query,
        books: ['x', 'y', 'liked'],
        affinities: [0, 0, 9],
      );

      expect(result, [0, 1, 2]);
    });

    test('מועמד בעל זיקה גבוהה עוקף מועמד בעל זיקה נמוכה, ולא להפך', () {
      final sorted = [for (var i = 0; i < 3; i++) _key(i, order: i + 1.0)];
      final result = _personalize(
        sorted,
        [0, 1, 2],
        query,
        books: ['x', 'low', 'high'],
        affinities: [0, 3, 7],
      );

      expect(result, [2, 1, 0]);
    });

    test('תוספת מעבר לחיתוך רק באותה מחלקת התאמה, ועד שש', () {
      final sorted = [for (var i = 0; i < 14; i++) _key(i, order: i + 0.0)];
      final result = _personalize(
        sorted,
        [0, 1, 2, 3],
        query,
        books: [for (var i = 0; i < 14; i++) 'b$i'],
        affinities: [for (var i = 0; i < 14; i++) i >= 4 ? 3.0 + i : 0],
      );

      // הגבוהות בזיקה קודמות; מעבר לשש הראשונות בסדר הדירוג לא נוסף דבר.
      expect(result, [9, 8, 7, 6, 5, 4, 0, 1, 2, 3]);
    });

    test('שורה ממחלקה גרועה מהגבול אינה מתווספת', () {
      final sorted = [
        _key(0, order: 0),
        _key(1, order: 1),
        // לא מתחיל בשאילתה, בניגוד לשורה האחרונה שנשארה.
        _key(2, order: 2, startsWith: false),
      ];
      final result = _personalize(
        sorted,
        [0, 1],
        query,
        books: ['a', 'b', 'liked'],
        affinities: [0, 0, 9],
      );

      expect(result, [0, 1]);
    });

    test('גם זיקה גבוהה מאוד אינה עוקפת ספר יסוד או התאמת טקסט טובה', () {
      final sorted = [
        _key(0, tier: 3, order: 9),
        _key(1, order: 1),
        _key(2, order: 2),
        // אינה תואמת את סגנון הציון, בניגוד לשורות שמעליה.
        _key(3, order: 3, citationMatch: false),
      ];
      final result = _personalize(
        sorted,
        [0, 1, 2, 3],
        query,
        books: ['gemara', 'x', 'liked', 'loved'],
        affinities: [0, 0, 20, 20],
      );

      expect(result, [0, 2, 1, 3]);
    });

    test('זנב #839 שצמוד לחיתוך אינו הופך לגבול התוספות', () {
      final sorted = [
        _key(0, order: 0),
        _key(1, order: 1),
        // מכסת הזנב: לא מתחילה בשאילתה, ונשארה אף שהיא מעבר לחיתוך.
        _key(2, order: 2, startsWith: false),
        _key(3, order: 3, startsWith: false),
      ];
      final result = _personalize(
        sorted,
        [0, 1, 2],
        query,
        cutoff: 2,
        books: ['a', 'b', 'tail', 'liked'],
        affinities: [0, 0, 0, 9],
      );

      // שורה 3 שווה במחלקתה לזנב, אבל גרועה מהשורה האחרונה שבחיתוך.
      expect(result, [0, 1, 2]);
    });

    test('התאמה אישית אינה מחזירה שורה שנדחקה ממכסת הזנב', () {
      final sorted = [
        _key(0, order: 0),
        _key(1, order: 1),
        _key(2, order: 2),
        _key(3, order: 3, startsWith: false),
      ];
      final result = _personalize(
        sorted,
        [0, 3],
        query,
        cutoff: 2,
        books: ['a', 'displaced', 'liked', 'tail'],
        affinities: [0, 9, 8, 0],
      );

      expect(result, [2, 0, 3]);
    });

    test('בלי חיתוך אין תוספות', () {
      final sorted = [for (var i = 0; i < 4; i++) _key(i, order: i + 0.0)];
      final result = _personalize(
        sorted,
        [0, 1, 2, 3],
        query,
        books: ['a', 'b', 'c', 'liked'],
        affinities: [0, 0, 0, 9],
      );

      expect(result, [3, 0, 1, 2]);
    });

    test('תכונה: על קלט אקראי הפלט מכיל את החיתוך ורק מזיז מועמדים', () {
      final random = Random(5168);
      for (var round = 0; round < 400; round++) {
        final bookCount = 2 + random.nextInt(7);
        final rowCount = 4 + random.nextInt(40);
        final keys = <FindRefRankKey<int>>[];
        for (var i = 0; i < rowCount; i++) {
          final book = random.nextInt(bookCount);
          keys.add(
            _key(
              i,
              // לכל ספר tier, דור ומקום קבועים, ושורות אחדות.
              tier: book % 3 == 0 ? 3 : null,
              era: book % 2,
              order: book.toDouble(),
              startsWith: random.nextInt(5) != 0,
              citationMatch: random.nextInt(6) != 0,
              partial: random.nextInt(5) == 0,
              level: 1 + random.nextInt(4),
            ),
          );
        }
        keys.sort((a, b) => compareFindRefRank(a, b, query));
        final books = [for (final k in keys) 'b${k.orderIndex.toInt()}'];

        // חיתוך קטן כמו ב-_rankResults: רצף פותח, שוויון בגבול, וזנב.
        var end = min(keys.length, 3 + random.nextInt(6));
        while (end < keys.length &&
            compareFindRefRelevance(keys[end], keys[end - 1], query) == 0) {
          end++;
        }
        final kept = [
          for (var i = 0; i < end; i++) i,
          for (var i = end; i < keys.length; i++)
            if (random.nextInt(9) == 0) i,
        ];

        final liked = {
          for (var b = 0; b < bookCount; b++)
            if (random.nextInt(3) == 0) 'b$b': 2.0 + random.nextInt(9),
        };
        final affinities = [for (final b in books) liked[b] ?? 0.0];

        // אורקל עצמאי: המועמדים מחושבים מהקלט, לא ממה שהפונקציה מחזירה.
        bool isPartial(int i) => keys[i].specificity >= 1 << 16;
        final candidates = <int>{};
        final rowsPerBook = <String, int>{};
        for (var i = 0; i < keys.length; i++) {
          if (affinities[i] <= 0 || isPartial(i)) continue;
          final taken = rowsPerBook[books[i]] ?? 0;
          if (taken >= 2) continue;
          rowsPerBook[books[i]] = taken + 1;
          candidates.add(i);
        }
        double boost(int i) => candidates.contains(i) ? affinities[i] : 0;
        final expectedAdditions = end == keys.length
            ? <int>[]
            : candidates
                  .where(
                    (i) =>
                        !kept.contains(i) &&
                        compareFindRefMatchClass(
                              keys[i],
                              keys[end - 1],
                              query,
                            ) <=
                            0,
                  )
                  .take(6)
                  .toList();

        final order = personalizeFindRefOrder(
          keys,
          kept,
          query,
          cutoff: end,
          books: books,
          affinities: affinities,
        );
        final reason = 'round $round';

        // הפלט הוא תמורה של החיתוך ושל התוספות הצפויות בלבד.
        expect(order.toSet(), hasLength(order.length), reason: reason);
        expect(order.toSet(), {...kept, ...expectedAdditions}, reason: reason);
        // מי שאינו מועמד נשאר בסדר המקורי בדיוק.
        expect(
          order.where((i) => !candidates.contains(i)),
          kept.where((i) => !candidates.contains(i)),
          reason: reason,
        );
        // אף שורה אינה עוקפת שורה ממחלקה טובה יותר או ספציפית יותר: מי
        // שעקף — מועמד, מאותה מחלקה, מועדף מהנעקפת, ולא פחות ספציפי ממנה.
        for (var at = 0; at < order.length; at++) {
          final mover = order[at];
          for (final passed in order.skip(at + 1).where((x) => x < mover)) {
            expect(candidates, contains(mover), reason: reason);
            expect(
              compareFindRefMatchClass(keys[passed], keys[mover], query),
              0,
              reason: reason,
            );
            expect(boost(passed), lessThan(boost(mover)), reason: reason);
            expect(
              keys[passed].specificity,
              greaterThanOrEqualTo(keys[mover].specificity),
              reason: reason,
            );
          }
        }
        // כל מועמד נעצר רק בחוסם אמיתי: השורה שמעליו אינה עבירה.
        for (var at = 1; at < order.length; at++) {
          final row = order[at];
          final above = order[at - 1];
          if (!candidates.contains(row) || above > row) continue;
          final passable =
              compareFindRefMatchClass(keys[above], keys[row], query) == 0 &&
              boost(above) < boost(row) &&
              keys[above].specificity >= keys[row].specificity;
          expect(passable, isFalse, reason: reason);
        }

        final plain = personalizeFindRefOrder(
          keys,
          kept,
          query,
          cutoff: end,
          books: books,
          affinities: [for (final _ in books) 0],
        );
        expect(plain, kept, reason: reason);
      }
    });
  });

  group('מי שאינו דיאלוג האיתור אינו מותאם אישית', () {
    test('תוספים מקבלים את סדר המדף גם כשיש העדפות שמורות', () async {
      final repo = _repo(_shulchanAruch, toc: _simanToc);
      for (var i = 0; i < 9; i++) {
        await repo.recordFindRefOpen(
          source: BookSource.official,
          bookId: _choshen.id,
          title: _choshen.title,
        );
      }
      expect(FindRefPreferenceStore.snapshot(), isNotNull);

      final hits = await buildPluginReferenceResolver(repo)(
        'שולחן ערוך סימן ל',
      );
      final concurrent = await repo.findRefsConcurrently('שולחן ערוך סימן ל');
      final plain = await repo.findRefs('שולחן ערוך סימן ל');

      final shelf = [for (final b in _shulchanAruch) b.title];
      expect([for (final h in hits) h.title], shelf);
      expect(_titles(concurrent), shelf);
      expect(_titles(plain), shelf);
    });
  });

  group('SeforimRepository.loadBookBaseTexts', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('otzaria_base_texts');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    Future<List<Map<String, dynamic>>> load(String schema) async {
      final dbPath = path.join(tempDir.path, 'seforim.db');
      sqlite3.sqlite3.open(dbPath)
        ..execute(schema)
        ..close();
      final database = MyDatabase.withPath(dbPath, readOnly: true);
      addTearDown(database.close);
      final repo = SeforimRepository(database);
      await repo.ensureInitialized();
      return repo.loadBookBaseTexts();
    }

    test('מחזיר לכל ספר את ספרי הבסיס שלו עם כותרותיהם', () async {
      final rows = await load('''
        CREATE TABLE book (id INTEGER PRIMARY KEY, title TEXT NOT NULL);
        CREATE TABLE book_base_text (
          bookId INTEGER NOT NULL, baseBookId INTEGER NOT NULL,
          PRIMARY KEY (bookId, baseBookId));
        INSERT INTO book VALUES (20, 'עירובין'), (11, 'ריטב"א על עירובין'),
          (21, 'רשב"א על עירובין');
        INSERT INTO book_base_text VALUES (11, 20), (21, 20);
      ''');

      expect(
        {
          for (final r in rows)
            '${r['bookId']}>${r['baseBookId']} ${r['baseTitle']}',
        },
        {'11>20 עירובין', '21>20 עירובין'},
      );
    });

    test('מסד בלי הטבלה מחזיר רשימה ריקה', () async {
      final rows = await load(
        'CREATE TABLE book (id INTEGER PRIMARY KEY, title TEXT NOT NULL);',
      );
      expect(rows, isEmpty);
    });
  });
}
