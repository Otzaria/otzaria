import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/find_ref/find_ref_preference_store.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';

import '../helpers/memory_settings_cache.dart';

const FindRefPreferenceBook _choshen = (key: 'o|4', title: 'חושן משפט');
const FindRefPreferenceBook _orach = (key: 'o|1', title: 'אורח חיים');
const FindRefPreferenceBook _eruvin = (key: 'o|20', title: 'עירובין');
const FindRefPreferenceBook _rashba = (key: 'o|21', title: 'רשב"א על עירובין');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  setUp(() async {
    await FindRefPreferenceStore.setEnabled(true);
    FindRefPreferenceStore.clear();
  });

  group('FindRefPreferences', () {
    test('כל פתיחה מדעיכה את כל הניקודים ומוסיפה 1 לספר שנפתח', () {
      var p = FindRefPreferences.empty.recordOpen(_choshen);
      expect(p.directScore('o|4', 'חושן משפט'), 1);

      p = p.recordOpen(_orach);
      expect(p.directScore('o|4', 'חושן משפט'), closeTo(0.95, 1e-9));
      expect(p.directScore('o|1', 'אורח חיים'), 1);

      p = p.recordOpen(_choshen);
      expect(p.directScore('o|4', 'חושן משפט'), closeTo(1.9025, 1e-9));
      expect(p.directScore('o|1', 'אורח חיים'), closeTo(0.95, 1e-9));
    });

    test('הזיקה היא 0 עד הסף, ומעליו הניקוד עצמו', () {
      var p = FindRefPreferences.empty
          .recordOpen(_choshen)
          .recordOpen(_choshen);
      // 1.95 — שתי פתיחות עדיין מתחת לסף.
      expect(p.affinity(key: 'o|4', title: 'חושן משפט'), 0);

      p = p.recordOpen(_choshen);
      expect(
        p.affinity(key: 'o|4', title: 'חושן משפט'),
        closeTo(2.8525, 1e-9),
      );
    });

    test('ספר בסיס צובר ניקוד מפתיחתו ומפתיחת מפרשיו', () {
      var p = FindRefPreferences.empty;
      for (var i = 0; i < 2; i++) {
        p = p.recordOpen(_eruvin).recordOpen(_rashba, baseBooks: [_eruvin]);
      }
      // 1 → 1.95 → 2.8525 → 3.709875
      expect(p.baseScore('o|20', 'עירובין'), closeTo(3.709875, 1e-9));
      // מפרש אחר על אותו ספר בסיס, שלא נפתח מעולם, יורש את הזיקה.
      expect(
        p.affinity(
          key: 'o|11',
          title: 'ריטב"א על עירובין',
          baseBooks: [_eruvin],
        ),
        closeTo(3.709875, 1e-9),
      );
      expect(
        p.affinity(
          key: 'o|10',
          title: 'ריטב"א על ברכות',
          baseBooks: const [(key: 'o|30', title: 'ברכות')],
        ),
        0,
      );
    });

    test('ספר נלווה מקבל אותו ניקוד ישיר באותה פתיחה', () {
      var p = FindRefPreferences.empty;
      for (var i = 0; i < 3; i++) {
        p = p.recordOpen(_rashba, baseBooks: [_eruvin], companions: [_eruvin]);
      }

      expect(p.directScore('o|21', 'רשב"א על עירובין'), closeTo(2.8525, 1e-9));
      expect(p.directScore('o|20', 'עירובין'), closeTo(2.8525, 1e-9));
      // ספר שהוא גם נלווה וגם בסיס נספר פעם אחת בלבד במפת הבסיס.
      expect(p.baseScore('o|20', 'עירובין'), closeTo(2.8525, 1e-9));
    });

    test('כותרת אחרת לאותו מזהה אינה יורשת את הניקוד', () {
      var p = FindRefPreferences.empty;
      for (var i = 0; i < 5; i++) {
        p = p.recordOpen(_choshen);
      }
      expect(p.directScore('o|4', 'ספר אחר'), 0);
      expect(p.affinity(key: 'o|4', title: 'ספר אחר'), 0);

      p = p.recordOpen((key: 'o|4', title: 'ספר אחר'));
      expect(p.directScore('o|4', 'ספר אחר'), 1);
    });

    test('רשומה שדעכה מתחת לסף הזניח נמחקת', () {
      var p = FindRefPreferences.empty.recordOpen(_choshen);
      for (var i = 0; i < 80; i++) {
        p = p.recordOpen(_orach);
      }
      expect(p.books.containsKey('o|4'), isFalse);
      expect(p.bases.containsKey('o|4'), isFalse);
      expect(p.books.containsKey('o|1'), isTrue);
    });

    test('כל מפה חסומה בגודלה, והנמוכים מושלכים', () {
      var p = FindRefPreferences(
        books: {
          for (var i = 0; i < FindRefPreferences.maxEntries; i++)
            'o|${1000 + i}': (score: 10.0 + i, title: 't$i'),
        },
      );
      p = p.recordOpen(_choshen);

      expect(p.books, hasLength(FindRefPreferences.maxEntries));
      // הרשומה החדשה (1) היא הנמוכה ביותר, והיא זו שנשרה.
      expect(p.books.containsKey('o|4'), isFalse);
      expect(p.books.containsKey('o|1000'), isTrue);
    });

    test('המפתח נפרד לכל מקור, ול-PDF מהדיסק הוא הנתיב', () {
      String? key(
        BookSource source,
        int? id, {
        bool pdf = false,
        String path = '',
      }) => FindRefPreferences.bookKey(
        source: source,
        bookId: id,
        isPdf: pdf,
        filePath: path,
      );

      expect(key(BookSource.official, 7), 'o|7');
      expect(key(BookSource.user, 7), 'u|7');
      expect(key(BookSource.attached('lib'), 7), 'd:lib|7');
      expect(key(BookSource.official, 7, pdf: true), 'o|7|pdf');
      expect(
        key(BookSource.official, -1, pdf: true, path: 'a/b.pdf'),
        'f|a/b.pdf',
      );
      expect(key(BookSource.official, -1), isNull);
      expect(key(BookSource.official, null), isNull);
      expect(FindRefPreferences.officialBaseKey(7), 'o|7');
    });

    test('הקידוד ל-JSON והפענוח משחזרים את אותן העדפות', () {
      final p = FindRefPreferences.empty
          .recordOpen(_eruvin)
          .recordOpen(_rashba, baseBooks: [_eruvin]);
      final restored = FindRefPreferences.fromJson(
        jsonDecode(jsonEncode(p.toJson())),
      );

      expect(restored.books, p.books);
      expect(restored.bases, p.bases);
    });

    test('ניקוד שמור מעל המקסימום הטבעי נחתך אליו', () {
      final p = FindRefPreferences.fromJson({
        'books': {
          'o|1': [1e9, 'ערוך ידנית'],
          'o|2': [7.5, 'רגיל'],
        },
        'bases': {
          'o|1': [500, 'ערוך ידנית'],
        },
      });

      expect(FindRefPreferences.maxScore, closeTo(20, 1e-9));
      expect(p.directScore('o|1', 'ערוך ידנית'), FindRefPreferences.maxScore);
      expect(p.baseScore('o|1', 'ערוך ידנית'), FindRefPreferences.maxScore);
      expect(p.directScore('o|2', 'רגיל'), 7.5);

      // פתיחות רצופות אינן עוברות את המקסימום, ולכן שום ערך תקין אינו נחתך.
      var natural = FindRefPreferences.empty;
      for (var i = 0; i < 500; i++) {
        natural = natural.recordOpen(_choshen);
      }
      expect(
        natural.directScore('o|4', 'חושן משפט'),
        lessThanOrEqualTo(FindRefPreferences.maxScore),
      );
    });

    test('רשומות פגומות בתוך JSON תקין מדולגות', () {
      final p = FindRefPreferences.fromJson({
        'books': {
          'o|1': [3.0, 'תקין'],
          'o|2': 'לא רשימה',
          'o|3': [1.0],
          'o|4': ['x', 'כותרת'],
          'o|5': [2.0, 7],
          'o|6': [-1.0, 'שלילי'],
          'o|7': [double.infinity, 'אינסוף'],
          '': [2.0, 'מפתח ריק'],
        },
        'bases': 'לא מפה',
      });

      expect(p.books.keys, ['o|1']);
      expect(p.bases, isEmpty);
      expect(FindRefPreferences.fromJson(const [1, 2]).isEmpty, isTrue);
      expect(FindRefPreferences.fromJson(null).isEmpty, isTrue);
    });
  });

  group('FindRefPreferenceStore', () {
    test('ברירת המחדל פעילה, ובלי פתיחות אין מה לדרג', () {
      expect(FindRefPreferenceStore.isEnabled, isTrue);
      expect(FindRefPreferenceStore.snapshot(), isNull);
      expect(FindRefPreferenceStore.load().isEmpty, isTrue);
    });

    test('פתיחות נשמרות ונקראות חזרה', () {
      FindRefPreferenceStore.recordOpen(_eruvin);
      FindRefPreferenceStore.recordOpen(_rashba, baseBooks: [_eruvin]);

      final p = FindRefPreferenceStore.snapshot()!;
      expect(p.directScore('o|21', 'רשב"א על עירובין'), 1);
      expect(p.directScore('o|20', 'עירובין'), closeTo(0.95, 1e-9));
      expect(p.baseScore('o|20', 'עירובין'), closeTo(1.95, 1e-9));
    });

    test('ערך פגום בהגדרות מחזיר העדפות ריקות ואינו זורק', () async {
      for (final raw in ['{not json', '[]', '42', '{"books": 5}', 'null']) {
        await Settings.setValue<String>(FindRefPreferenceStore.scoresKey, raw);
        expect(FindRefPreferenceStore.load().isEmpty, isTrue, reason: raw);
        expect(FindRefPreferenceStore.snapshot(), isNull, reason: raw);
      }
      // גם אחרי ערך פגום הרישום הבא נשמר כרגיל.
      FindRefPreferenceStore.recordOpen(_choshen);
      expect(FindRefPreferenceStore.load().books.keys, ['o|4']);
    });

    test('כשהמתג כבוי לא מדרגים וגם לא רושמים', () async {
      FindRefPreferenceStore.recordOpen(_choshen);
      await FindRefPreferenceStore.setEnabled(false);

      expect(FindRefPreferenceStore.isEnabled, isFalse);
      expect(FindRefPreferenceStore.snapshot(), isNull);

      FindRefPreferenceStore.recordOpen(_choshen);
      FindRefPreferenceStore.recordOpen(_orach);
      expect(FindRefPreferenceStore.load().books.keys, ['o|4']);
      expect(FindRefPreferenceStore.load().directScore('o|4', 'חושן משפט'), 1);

      // ההעדפות שנצברו נשמרות, וחוזרות בהדלקה.
      await FindRefPreferenceStore.setEnabled(true);
      expect(FindRefPreferenceStore.snapshot(), isNotNull);
    });

    test('clear מוחק הכול', () {
      FindRefPreferenceStore.recordOpen(_rashba, baseBooks: [_eruvin]);
      FindRefPreferenceStore.clear();

      expect(FindRefPreferenceStore.load().isEmpty, isTrue);
      expect(FindRefPreferenceStore.snapshot(), isNull);
    });

    test('revision מתקדם ברישום פתיחה, במחיקה ובשינוי המתג', () async {
      final start = FindRefPreferenceStore.revision;
      FindRefPreferenceStore.recordOpen(_choshen);
      expect(FindRefPreferenceStore.revision, start + 1);

      FindRefPreferenceStore.clear();
      expect(FindRefPreferenceStore.revision, start + 2);

      await FindRefPreferenceStore.setEnabled(false);
      expect(FindRefPreferenceStore.revision, start + 3);
    });
  });
}
