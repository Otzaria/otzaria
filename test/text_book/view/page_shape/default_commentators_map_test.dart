import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_default_commentators.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/services/category_commentators_service.dart';
import 'package:otzaria/book_common/utils/default_commentators.dart';

import '../../../test_helpers/memory_cache_provider.dart';

/// טסטים למיפוי מפרשי ברירת המחדל ל-4 מיקומי צורת הדף:
/// position 0→ימין, 1→שמאל, 2→תחתון, 3→תחתון נוסף. position חסר → מיקום ריק.
/// מפתחות הפאנלים הפוכים לצד הפיזי (Row ב-RTL): 'left' מוצג בימין ולהפך.
void main() {
  ({String title, int position}) c(String title, int position) =>
      (title: title, position: position);

  group('PageShapeDefaultCommentators.mapToPageShape', () {
    test('תורה: מפרש בימין, תרגום בשמאל', () {
      final result = PageShapeDefaultCommentators.mapToPageShape(
        [c('רש"י', 0)],
        ['תרגום אונקלוס'],
      );

      expect(result['left'], 'רש"י');
      expect(result['right'], 'תרגום אונקלוס');
      expect(result['bottom'], isNull);
      expect(result['bottomRight'], isNull);
    });

    test('בבלי ללא תרגום: המפרש השני נכנס לשמאל', () {
      final result = PageShapeDefaultCommentators.mapToPageShape(
        [c('רש"י', 0), c('תוספות', 1)],
        [],
      );

      expect(result['left'], 'רש"י');
      expect(result['right'], 'תוספות');
      expect(result['bottom'], isNull);
      expect(result['bottomRight'], isNull);
    });

    test('ארבעה מפרשים ללא תרגום ממלאים את כל המיקומים לפי הסדר', () {
      final result = PageShapeDefaultCommentators.mapToPageShape(
        [
          c('רש"י', 0),
          c('מצודת דוד', 1),
          c('מצודת ציון', 2),
          c('רד"ק', 3),
        ],
        [],
      );

      expect(result['left'], 'רש"י');
      expect(result['right'], 'מצודת דוד');
      expect(result['bottom'], 'מצודת ציון');
      expect(result['bottomRight'], 'רד"ק');
    });

    test('שני מפרשים + תרגום: מפרשים בימין ובשמאל, התרגום בתחתון', () {
      final result = PageShapeDefaultCommentators.mapToPageShape(
        [c('רש"י', 0), c('רד"ק', 1)],
        ['תרגום אונקלוס'],
      );

      expect(result['left'], 'רש"י');
      expect(result['right'], 'רד"ק');
      expect(result['bottom'], 'תרגום אונקלוס');
      expect(result['bottomRight'], isNull);
    });

    test('slot ריק (position מדולג): המיקום נשאר ריק והמפרש הבא במקומו', () {
      // מפרש ב-position 0 (ימין), דילוג על 1 (שמאל), מפרש ב-position 2 (תחתון)
      final result = PageShapeDefaultCommentators.mapToPageShape(
        [c('מפרש א', 0), c('מפרש ב', 2)],
        [],
      );

      expect(result['left'], 'מפרש א');
      expect(result['right'], isNull); // ה-slot הריק נשמר
      expect(result['bottom'], 'מפרש ב');
      expect(result['bottomRight'], isNull);
    });

    test('slot ריק מכוון מוסתר בנראות ברירת המחדל', () {
      final result = PageShapeDefaultCommentators.mapToPageShapeDefaults(
        [c('מפרש א', 0), c('מפרש ב', 2)],
        [],
      );

      expect(result.commentators['left'], 'מפרש א');
      expect(result.commentators['right'], isNull);
      expect(result.commentators['bottom'], 'מפרש ב');
      expect(result.visibility['left'], isTrue);
      expect(result.visibility['right'], isFalse);
      expect(result.visibility['bottom'], isTrue);
      expect(result.visibility['bottomRight'], isTrue);
    });

    test('slotים שאחרי המיקום האחרון לא מוסתרים בגלל ברירת מחדל חסרה', () {
      final result = PageShapeDefaultCommentators.mapToPageShapeDefaults(
        [c('רש"י', 0)],
        [],
      );

      expect(result.commentators['left'], 'רש"י');
      expect(result.commentators['right'], isNull);
      expect(result.commentators['bottom'], isNull);
      expect(result.visibility.values, everyElement(isTrue));
    });

    test('רשימות ריקות מחזירות null בכל המיקומים', () {
      final result = PageShapeDefaultCommentators.mapToPageShape([], []);

      expect(result['right'], isNull);
      expect(result['left'], isNull);
      expect(result['bottom'], isNull);
      expect(result['bottomRight'], isNull);
    });
  });

  // הבחירה ההתחלתית לפאנל/כרטסיית המפרשים: ברירת מחדל אם הוגדרה, אחרת כל
  // המפרשים אם יש עד 4. baseCommentators מועבר מפורשות כדי לבדוק את הלוגיקה
  // הטהורה ללא גישה ל-DB.
  group('DefaultCommentators.getInitialSelection', () {
    final book = TextBook(title: 'ספר');

    test('מפרשי ברירת מחדל מוגדרים → נבחרים גם כשיש יותר מ-4 זמינים', () async {
      final result = await DefaultCommentators.getInitialSelection(
        book,
        availableCommentators: const [
          'רש"י',
          'תוספות',
          'רמב"ן',
          'ספורנו',
          'אבן עזרא',
        ],
        baseCommentators: const ['רש"י', 'תוספות'],
      );

      expect(result, ['רש"י', 'תוספות']);
    });

    test('עד 4 מפרשים ללא ברירת מחדל → כולם נבחרים', () async {
      final result = await DefaultCommentators.getInitialSelection(
        book,
        availableCommentators: const ['א', 'ב', 'ג', 'ד'],
        baseCommentators: const [],
      );

      expect(result, ['א', 'ב', 'ג', 'ד']);
    });

    test('יותר מ-4 מפרשים ללא ברירת מחדל → רשימה ריקה (בחירה ידנית)', () async {
      final result = await DefaultCommentators.getInitialSelection(
        book,
        availableCommentators: const ['א', 'ב', 'ג', 'ד', 'ה'],
        baseCommentators: const [],
      );

      expect(result, isEmpty);
    });

    test('אין מפרשים זמינים → רשימה ריקה', () async {
      final result = await DefaultCommentators.getInitialSelection(
        book,
        availableCommentators: const [],
        baseCommentators: const ['רש"י'],
      );

      expect(result, isEmpty);
    });

    test('ברירת מחדל מותאמת לשם המלא הזמין; שם שאינו קיים נושר', () async {
      final result = await DefaultCommentators.getInitialSelection(
        book,
        availableCommentators: const ['רש"י על התורה', 'תוספות'],
        baseCommentators: const ['רש"י', 'לא קיים'],
      );

      expect(result, ['רש"י על התורה']);
    });
  });

  // מפרשים קבועים שהמשתמש קבע לקטגוריה (issue #866) גוברים על ברירת המחדל
  // מה-DB, אך בחירה שמורה פר-ספר עדיין גוברת עליהם (resolveAutoSelection).
  group('DefaultCommentators — מפרשים קבועים לקטגוריה', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    final book = TextBook(
      title: 'ברכות',
      heCategories: 'אוצריא, תלמוד, תלמוד בבלי, סדר זרעים',
    );

    setUp(() async {
      await Settings.init(cacheProvider: MemoryCacheProvider());
    });

    test('קביעת קטגוריה גוברת על מפרשי ברירת המחדל מה-DB', () async {
      await CategoryCommentatorsService.save(
        'תלמוד בבלי',
        ['מהרש"א על ברכות'],
        bookTitle: 'ברכות',
      );

      final result = await DefaultCommentators.getInitialSelection(
        book,
        availableCommentators: const ['רש"י על ברכות', 'מהרש"א על ברכות'],
        baseCommentators: const ['רש"י'],
      );

      expect(result, ['מהרש"א על ברכות']);
    });

    test('קביעה ריקה מפורשת → נפתח בלי מפרשים (גם כשיש עד 4 זמינים)', () async {
      await CategoryCommentatorsService.save(
        'תלמוד בבלי',
        const [],
        bookTitle: 'ברכות',
      );

      final result = await DefaultCommentators.getInitialSelection(
        book,
        availableCommentators: const ['רש"י על ברכות', 'תוספות על ברכות'],
        baseCommentators: const ['רש"י'],
      );

      expect(result, isEmpty);
    });

    test('קביעה שאף שם בה לא נפתר בספר → נופלים לברירת המחדל מה-DB', () async {
      await CategoryCommentatorsService.save(
        'תלמוד בבלי',
        ['מפרש שאינו קיים'],
        bookTitle: 'ברכות',
      );

      final result = await DefaultCommentators.getInitialSelection(
        book,
        availableCommentators: const ['רש"י על ברכות', 'תוספות על ברכות'],
        baseCommentators: const ['רש"י'],
      );

      expect(result, ['רש"י על ברכות']);
    });

    test('בחירה שמורה פר-ספר גוברת על קביעת הקטגוריה', () async {
      await CategoryCommentatorsService.save(
        'תלמוד בבלי',
        ['מהרש"א על ברכות'],
        bookTitle: 'ברכות',
      );

      final result = await DefaultCommentators.resolveAutoSelection(
        book,
        availableCommentators: const ['רש"י על ברכות', 'מהרש"א על ברכות'],
        savedSelection: const ['רש"י על ברכות'],
      );

      expect(result, isNull);
    });

    test('ספר בלי heCategories (כמו PDF) נופל ל-categoryPath', () async {
      await CategoryCommentatorsService.save(
        'תלמוד בבלי',
        ['מהרש"א על ברכות'],
        bookTitle: 'ברכות',
      );

      final pdfLikeBook = TextBook(
        title: 'ברכות',
        categoryPath: 'אוצריא, תלמוד, תלמוד בבלי, סדר זרעים',
      );
      final result = await DefaultCommentators.getInitialSelection(
        pdfLikeBook,
        availableCommentators: const ['רש"י על ברכות', 'מהרש"א על ברכות'],
        baseCommentators: const ['רש"י'],
      );

      expect(result, ['מהרש"א על ברכות']);
    });

    test('שם בסיסי שנשמר ממסכת אחת נפתר לשם המלא במסכת אחרת', () async {
      await CategoryCommentatorsService.save(
        'תלמוד בבלי',
        ['רש"י על ברכות'],
        bookTitle: 'ברכות',
      );

      final shabbat = TextBook(
        title: 'שבת',
        heCategories: 'אוצריא, תלמוד, תלמוד בבלי, סדר מועד',
      );
      final result = await DefaultCommentators.getInitialSelection(
        shabbat,
        availableCommentators: const ['רש"י על שבת', 'תוספות על שבת'],
        baseCommentators: const [],
      );

      expect(result, ['רש"י על שבת']);
    });
  });

  // resolveAutoSelection מחליטה אם להחיל ברירת מחדל בפתיחה: בחירה שמורה (גם
  // ריקה) גוברת ומבטלת אוטו-בחירה. ה-repository של ה-DB אינו מאותחל בבדיקה,
  // לכן getBaseCommentators מחזירה ריק ונבדק מסלול "עד 4 → כל הזמינים".
  group('DefaultCommentators.resolveAutoSelection', () {
    final book = TextBook(title: 'ספר');

    test('בחירה שמורה ריקה גוברת — לא מחילים ברירת מחדל (null)', () async {
      final result = await DefaultCommentators.resolveAutoSelection(
        book,
        availableCommentators: const ['רש"י', 'רד"ק'],
        savedSelection: const [],
      );

      expect(result, isNull);
    });

    test('בחירה שמורה לא-ריקה גוברת — לא מחילים ברירת מחדל (null)', () async {
      final result = await DefaultCommentators.resolveAutoSelection(
        book,
        availableCommentators: const ['רש"י', 'רד"ק'],
        savedSelection: const ['אבן עזרא'],
      );

      expect(result, isNull);
    });

    test('ללא בחירה שמורה ועד 4 מפרשים → מחזיר את כל הזמינים', () async {
      final result = await DefaultCommentators.resolveAutoSelection(
        book,
        availableCommentators: const ['רש"י', 'רד"ק'],
        savedSelection: null,
      );

      expect(result, ['רש"י', 'רד"ק']);
    });

    test('ללא בחירה שמורה ויותר מ-4 מפרשים ללא ברירת מחדל → null', () async {
      final result = await DefaultCommentators.resolveAutoSelection(
        book,
        availableCommentators: const ['א', 'ב', 'ג', 'ד', 'ה'],
        savedSelection: null,
      );

      expect(result, isNull);
    });
  });
}
