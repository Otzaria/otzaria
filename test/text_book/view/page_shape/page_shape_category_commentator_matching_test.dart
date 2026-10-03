// התאמת מפרשים בין ספרים בהגדרות צורת הדף בהיקף קטגוריה.
//
// יש משפחות מפרשים ששמן "<מפרש> <שם הספר>" בלי "על" — "יכין מקואות",
// "ריף בבא מציעא", "רלבג שיר השירים", "באר היטב אורח חיים", "תרגום קהלת".

import 'package:otzaria/book_common/utils/commentator_name_matching.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_commentary_selection.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_settings_manager.dart';

import '../../../test_helpers/memory_cache_provider.dart';

/// המפרשים הזמינים במסכת נדה שבמשנה, בשמות כפי שהם בספרייה.
const _mishnaNidaCommentators = [
  'ברטנורא על משנה נדה',
  'תוספות יום טוב על משנה נדה',
  'עיקר תוספות יום טוב על משנה נדה',
  'תוספות רבי עקיבא איגר על משנה נדה',
  'מלאכת שלמה על משנה נדה',
  'רמבם על משנה נדה',
  'יכין נדה',
  'בועז על משנה נדה',
];

const _mishnaMikvaotCommentators = [
  'ברטנורא על משנה מקואות',
  'תוספות יום טוב על משנה מקואות',
  'יכין מקואות',
  'בועז על משנה מקואות',
];

/// שומר בחירת מפרש בהיקף קטגוריה ומחזיר את השם שהותאם לספר אחר בקטגוריה.
Future<String?> _reresolveInOtherBook({
  required String category,
  required String savedFromBookTitle,
  required String savedCommentator,
  required String otherBookTitle,
  required String otherBookCategories,
  required List<String> otherBookCommentators,
}) async {
  await PageShapeSettingsManager.saveConfiguration(
    savedFromBookTitle,
    {
      'left': savedCommentator,
      'right': null,
      'bottom': null,
      'bottomRight': null,
    },
    saveToCategory: category,
  );

  final config = PageShapeSettingsManager.loadConfiguration(
    otherBookTitle,
    heCategories: otherBookCategories,
  );

  return resolvePageShapeCommentatorSelection(
    selection: config?['left'],
    availableCommentators: otherBookCommentators,
    commentedBookTitle: otherBookTitle,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  group('extractBaseCommentatorName — שמות שכוללים "על"', () {
    test('מחזיר את הקידומת שלפני "על"', () {
      expect(
        PageShapeSettingsManager.extractBaseCommentatorName(
          'ברטנורא על משנה נדה',
          commentedBookTitle: 'משנה נדה',
        ),
        'ברטנורא',
      );
      expect(
        PageShapeSettingsManager.extractBaseCommentatorName(
          'תוספות רבי עקיבא איגר על משנה טהרות',
          commentedBookTitle: 'משנה טהרות',
        ),
        'תוספות רבי עקיבא איגר',
      );
      expect(
        PageShapeSettingsManager.extractBaseCommentatorName(
          'רשי על סנהדרין',
          commentedBookTitle: 'סנהדרין',
        ),
        'רשי',
      );
    });

    test('שם ספר מורכב אחרי "על" אינו משפיע על הקידומת', () {
      expect(
        PageShapeSettingsManager.extractBaseCommentatorName(
          'אור שמח על משנה תורה, הלכות ציצית',
          commentedBookTitle: 'משנה תורה, הלכות ציצית',
        ),
        'אור שמח',
      );
    });

    test('"על" גובר גם בלי שם ספר נתון', () {
      expect(
        PageShapeSettingsManager.extractBaseCommentatorName('רמבן על ברכות'),
        'רמבן',
      );
    });
  });

  group('extractBaseCommentatorName — שמות בלי "על"', () {
    test('מסיר את שם המסכת של המשנה', () {
      expect(
        PageShapeSettingsManager.extractBaseCommentatorName(
          'יכין מקואות',
          commentedBookTitle: 'משנה מקואות',
        ),
        'יכין',
      );
    });

    test('מסיר שם מסכת בן שתי מילים', () {
      expect(
        PageShapeSettingsManager.extractBaseCommentatorName(
          'יכין טבול יום',
          commentedBookTitle: 'משנה טבול יום',
        ),
        'יכין',
      );
      expect(
        PageShapeSettingsManager.extractBaseCommentatorName(
          'ריף בבא מציעא',
          commentedBookTitle: 'בבא מציעא',
        ),
        'ריף',
      );
      expect(
        PageShapeSettingsManager.extractBaseCommentatorName(
          'ריף עבודה זרה',
          commentedBookTitle: 'עבודה זרה',
        ),
        'ריף',
      );
    });

    test('מסיר שם ספר בתנ"ך', () {
      expect(
        PageShapeSettingsManager.extractBaseCommentatorName(
          'רלבג שיר השירים',
          commentedBookTitle: 'שיר השירים',
        ),
        'רלבג',
      );
      expect(
        PageShapeSettingsManager.extractBaseCommentatorName(
          'תרגום קהלת',
          commentedBookTitle: 'קהלת',
        ),
        'תרגום',
      );
      expect(
        PageShapeSettingsManager.extractBaseCommentatorName(
          'תרגום דברי הימים ב',
          commentedBookTitle: 'דברי הימים ב',
        ),
        'תרגום',
      );
    });

    test('מסיר חלק משם הספר כשהמפרש נושא רק את הסיומת', () {
      expect(
        PageShapeSettingsManager.extractBaseCommentatorName(
          'באר היטב אורח חיים',
          commentedBookTitle: 'שולחן ערוך אורח חיים',
        ),
        'באר היטב',
      );
    });
  });

  group('extractBaseCommentatorName — מקרי קצה', () {
    test('null מוחזר כ-null', () {
      expect(
        PageShapeSettingsManager.extractBaseCommentatorName(
          null,
          commentedBookTitle: 'משנה נדה',
        ),
        isNull,
      );
    });

    test('מפרש שאינו נושא את שם הספר נשאר שלם', () {
      expect(
        PageShapeSettingsManager.extractBaseCommentatorName(
          'משנה ברורה',
          commentedBookTitle: 'שולחן ערוך אורח חיים',
        ),
        'משנה ברורה',
      );
      expect(
        PageShapeSettingsManager.extractBaseCommentatorName(
          'ביאור הלכה',
          commentedBookTitle: 'שולחן ערוך אורח חיים',
        ),
        'ביאור הלכה',
      );
    });

    test('בלי שם ספר נתון השם נשאר שלם', () {
      expect(
        PageShapeSettingsManager.extractBaseCommentatorName('יכין מקואות'),
        'יכין מקואות',
      );
      expect(
        PageShapeSettingsManager.extractBaseCommentatorName(
          'יכין מקואות',
          commentedBookTitle: '',
        ),
        'יכין מקואות',
      );
    });

    test('שם זהה לחלוטין לשם הספר אינו מתרוקן', () {
      expect(
        PageShapeSettingsManager.extractBaseCommentatorName(
          'משנה נדה',
          commentedBookTitle: 'משנה נדה',
        ),
        'משנה נדה',
      );
      expect(
        PageShapeSettingsManager.extractBaseCommentatorName(
          'נדה',
          commentedBookTitle: 'משנה נדה',
        ),
        'נדה',
      );
    });

    test('רווחים כפולים אינם מונעים את ההסרה', () {
      expect(
        PageShapeSettingsManager.extractBaseCommentatorName(
          'יכין  מקואות',
          commentedBookTitle: 'משנה   מקואות',
        ),
        'יכין',
      );
    });

    test('התאמה חלקית של מילה אינה נחשבת', () {
      // "מקוואות" אינה "מקואות" — אין מילה משותפת ולכן אין הסרה.
      expect(
        PageShapeSettingsManager.extractBaseCommentatorName(
          'יכין מקואות',
          commentedBookTitle: 'משנה מקוואות',
        ),
        'יכין מקואות',
      );
    });
  });

  group('findMatchingCommentator — התאמה לספר הנוכחי', () {
    test('שם בסיס חדש מותאם למסכת הנוכחית', () {
      expect(
        findMatchingCommentator('יכין', _mishnaNidaCommentators),
        'יכין נדה',
      );
      expect(
        findMatchingCommentator('ברטנורא', _mishnaNidaCommentators),
        'ברטנורא על משנה נדה',
      );
    });

    test('הגדרה ישנה עם שם מסכת אחרת מותאמת לפי חלק-המפרש', () {
      expect(
        findMatchingCommentator(
          'יכין מקואות',
          _mishnaNidaCommentators,
          commentedBookTitle: 'משנה נדה',
        ),
        'יכין נדה',
      );
      expect(
        findMatchingCommentator(
          'ריף בבא מציעא',
          const ['רשי על שבת', 'ריף שבת', 'תוספות על שבת'],
          commentedBookTitle: 'שבת',
        ),
        'ריף שבת',
      );
      expect(
        findMatchingCommentator(
          'רלבג שיר השירים',
          const ['רלבג אסתר', 'אבן עזרא על אסתר'],
          commentedBookTitle: 'אסתר',
        ),
        'רלבג אסתר',
      );
      expect(
        findMatchingCommentator(
          'ברטנורא על משנה מקואות',
          _mishnaNidaCommentators,
          commentedBookTitle: 'משנה נדה',
        ),
        'ברטנורא על משנה נדה',
      );
    });

    test('בלי שם הספר הנוכחי אין ריפוי של הגדרה ישנה', () {
      expect(
        findMatchingCommentator(
          'יכין מקואות',
          _mishnaNidaCommentators,
        ),
        isNull,
      );
    });

    test('הקידומת הארוכה ביותר גוברת על קידומת קצרה יותר', () {
      expect(
        findMatchingCommentator(
          'תוספות יום טוב על משנה פרה',
          _mishnaNidaCommentators,
          commentedBookTitle: 'משנה נדה',
        ),
        'תוספות יום טוב על משנה נדה',
      );
    });

    test('משפחות שחולקות קידומת אינן מתבלבלות', () {
      expect(
        findMatchingCommentator(
          'עיקר תוספות יום טוב',
          _mishnaNidaCommentators,
          commentedBookTitle: 'משנה נדה',
        ),
        'עיקר תוספות יום טוב על משנה נדה',
      );
      expect(
        findMatchingCommentator(
          'תוספות רבי עקיבא איגר',
          _mishnaNidaCommentators,
          commentedBookTitle: 'משנה נדה',
        ),
        'תוספות רבי עקיבא איגר על משנה נדה',
      );
      expect(
        findMatchingCommentator(
          'רמבם',
          _mishnaNidaCommentators,
          commentedBookTitle: 'משנה נדה',
        ),
        'רמבם על משנה נדה',
      );
    });

    test('מפרש חסר אינו מוחלף במפרש של מחבר אחר', () {
      // רגרסיה: התאמה לפי מילות פתיחה משותפות החזירה כאן "תוספות יום טוב".
      expect(
        findMatchingCommentator(
          'תוספות רבי עקיבא איגר',
          const ['ברטנורא על משנה עדיות', 'תוספות יום טוב על משנה עדיות'],
          commentedBookTitle: 'משנה עדיות',
        ),
        isNull,
      );
      expect(
        findMatchingCommentator(
          'עיקר תוספות יום טוב',
          const ['ברטנורא על משנה עדיות', 'תוספות יום טוב על משנה עדיות'],
          commentedBookTitle: 'משנה עדיות',
        ),
        isNull,
      );
    });

    test('שכבה חסרה של אותו מחבר נופלת חזרה לפירושו בספר הנוכחי', () {
      expect(
        findMatchingCommentator(
          'מלבים באור המילות',
          const ['מלבים על רות', 'אבן עזרא על רות'],
          commentedBookTitle: 'רות',
        ),
        'מלבים על רות',
      );
    });

    test('מפרש שאין לו מקבילה בספר הנוכחי אינו מותאם', () {
      expect(
        findMatchingCommentator(
          'מלאכת שלמה על משנה נדה',
          const ['רשי על בראשית', 'רמבן על בראשית'],
          commentedBookTitle: 'בראשית',
        ),
        isNull,
      );
      expect(
        findMatchingCommentator(
          'יכין מקואות',
          const [],
          commentedBookTitle: 'משנה נדה',
        ),
        isNull,
      );
    });

    test('null אינו מותאם', () {
      expect(
        findMatchingCommentator(null, _mishnaNidaCommentators),
        isNull,
      );
    });
  });

  group('resolvePageShapeCommentatorSelection', () {
    test('ערכי sentinel עוברים כמות שהם', () {
      expect(
        resolvePageShapeCommentatorSelection(
          selection: pageShapeRemainingCommentatorsValue,
          availableCommentators: _mishnaNidaCommentators,
        ),
        pageShapeRemainingCommentatorsValue,
      );
      expect(
        resolvePageShapeCommentatorSelection(
          selection: pageShapeMultipleCommentatorsModeValue,
          availableCommentators: _mishnaNidaCommentators,
        ),
        isNull,
      );
    });

    test('בחירה מרובה שנשמרה במסכת אחרת מותאמת כולה', () {
      final encoded = encodePageShapeCommentatorsSelection(
        const ['יכין מקואות', 'ברטנורא על משנה מקואות'],
        forceMultipleMode: true,
      );

      final resolved = resolvePageShapeCommentatorSelection(
        selection: encoded,
        availableCommentators: _mishnaNidaCommentators,
        commentedBookTitle: 'משנה נדה',
      );

      expect(
        decodePageShapeCommentatorsSelection(resolved),
        ['יכין נדה', 'ברטנורא על משנה נדה'],
      );
    });

    test('בחירה מרובה מסוננת לפי מה שקיים בספר הנוכחי', () {
      final encoded = encodePageShapeCommentatorsSelection(
        const ['יכין מקואות', 'מפרש שלא קיים כאן'],
        forceMultipleMode: true,
      );

      expect(
        resolvePageShapeSelectedCommentators(
          selection: encoded,
          availableCommentators: _mishnaNidaCommentators,
          commentedBookTitle: 'משנה נדה',
        ),
        ['יכין נדה'],
      );
    });

    test('שדה בחירה בודדת מציג את השם המותאם למסכת הנוכחית', () {
      expect(
        resolvePageShapeSingleCommentatorSelection(
          selection: 'יכין מקואות',
          availableCommentators: _mishnaNidaCommentators,
          commentedBookTitle: 'משנה נדה',
        ),
        'יכין נדה',
      );
    });
  });

  group('מסלול מלא: שמירה לקטגוריה וטעינה בספר אחר', () {
    test('יכין — משנה', () async {
      final resolved = await _reresolveInOtherBook(
        category: 'משנה',
        savedFromBookTitle: 'משנה מקואות',
        savedCommentator: 'יכין מקואות',
        otherBookTitle: 'משנה נדה',
        otherBookCategories: 'אוצריא, משנה, סדר טהרות, נדה',
        otherBookCommentators: _mishnaNidaCommentators,
      );
      expect(resolved, 'יכין נדה');
    });

    test('ברטנורא — משנה (שם עם "על")', () async {
      final resolved = await _reresolveInOtherBook(
        category: 'משנה',
        savedFromBookTitle: 'משנה מקואות',
        savedCommentator: 'ברטנורא על משנה מקואות',
        otherBookTitle: 'משנה נדה',
        otherBookCategories: 'אוצריא, משנה, סדר טהרות, נדה',
        otherBookCommentators: _mishnaNidaCommentators,
      );
      expect(resolved, 'ברטנורא על משנה נדה');
    });

    test('רי"ף — תלמוד', () async {
      final resolved = await _reresolveInOtherBook(
        category: 'בבלי',
        savedFromBookTitle: 'בבא מציעא',
        savedCommentator: 'ריף בבא מציעא',
        otherBookTitle: 'שבת',
        otherBookCategories: 'אוצריא, תלמוד, בבלי, סדר מועד',
        otherBookCommentators: const ['רשי על שבת', 'ריף שבת'],
      );
      expect(resolved, 'ריף שבת');
    });

    test('רלב"ג — תנ"ך', () async {
      final resolved = await _reresolveInOtherBook(
        category: 'כתובים',
        savedFromBookTitle: 'שיר השירים',
        savedCommentator: 'רלבג שיר השירים',
        otherBookTitle: 'אסתר',
        otherBookCategories: 'אוצריא, תנ"ך, כתובים, אסתר',
        otherBookCommentators: const ['רלבג אסתר', 'אבן עזרא על אסתר'],
      );
      expect(resolved, 'רלבג אסתר');
    });

    test('באר היטב — שולחן ערוך', () async {
      final resolved = await _reresolveInOtherBook(
        category: 'שולחן ערוך',
        savedFromBookTitle: 'שולחן ערוך אורח חיים',
        savedCommentator: 'באר היטב אורח חיים',
        otherBookTitle: 'שולחן ערוך יורה דעה',
        otherBookCategories: 'הלכה, שולחן ערוך, יורה דעה',
        otherBookCommentators: const [
          'באר היטב יורה דעה',
          'שך על שולחן ערוך יורה דעה',
        ],
      );
      expect(resolved, 'באר היטב יורה דעה');
    });

    test('בחירה מרובה נשמרת ומותאמת בספר אחר', () async {
      await PageShapeSettingsManager.saveConfiguration(
        'משנה מקואות',
        {
          'left': null,
          'right': encodePageShapeCommentatorsSelection(
            const ['יכין מקואות', 'ברטנורא על משנה מקואות'],
            forceMultipleMode: true,
          ),
          'bottom': null,
          'bottomRight': null,
        },
        saveToCategory: 'משנה',
      );

      final config = PageShapeSettingsManager.loadConfiguration(
        'משנה נדה',
        heCategories: 'אוצריא, משנה, סדר טהרות, נדה',
      );

      expect(
        decodePageShapeCommentatorsSelection(config?['right']),
        ['יכין', 'ברטנורא'],
        reason: 'בהיקף קטגוריה נשמרים שמות הבסיס בלבד',
      );
      expect(
        resolvePageShapeSelectedCommentators(
          selection: config?['right'],
          availableCommentators: _mishnaNidaCommentators,
          commentedBookTitle: 'משנה נדה',
        ),
        ['יכין נדה', 'ברטנורא על משנה נדה'],
      );
    });

    test('מפרש שאינו קיים בספר האחר נשמר ואינו מוחלף במפרש זר', () async {
      const otherBookCommentators = ['ברטנורא על משנה נדה'];
      final resolved = await _reresolveInOtherBook(
        category: 'משנה',
        savedFromBookTitle: 'משנה מקואות',
        savedCommentator: 'מלאכת שלמה על משנה מקואות',
        otherBookTitle: 'משנה נדה',
        otherBookCategories: 'אוצריא, משנה, סדר טהרות, נדה',
        otherBookCommentators: otherBookCommentators,
      );

      // ההגדרה נשמרת כדי שלא תימחק משאר ספרי הקטגוריה, אבל היא אינה מפרש
      // של הספר הזה ולכן החלונית לא תטען אותה.
      expect(resolved, 'מלאכת שלמה');
      expect(otherBookCommentators.contains(resolved), isFalse);
    });
  });

  group('היקף ספר בודד — השם המלא נשמר כמות שהוא', () {
    test('שמירה לספר אינה מקצרת את שם המפרש', () async {
      await PageShapeSettingsManager.saveConfiguration(
        'משנה מקואות',
        const {
          'left': 'יכין מקואות',
          'right': null,
          'bottom': null,
          'bottomRight': null,
        },
      );

      final config = PageShapeSettingsManager.loadConfiguration(
        'משנה מקואות',
      );
      expect(config?['left'], 'יכין מקואות');
      expect(
        resolvePageShapeCommentatorSelection(
          selection: config?['left'],
          availableCommentators: _mishnaMikvaotCommentators,
        ),
        'יכין מקואות',
      );
    });

    test('הגדרת ספר גוברת על הגדרת הקטגוריה', () async {
      await PageShapeSettingsManager.saveConfiguration(
        'משנה מקואות',
        const {
          'left': 'יכין מקואות',
          'right': null,
          'bottom': null,
          'bottomRight': null,
        },
        saveToCategory: 'משנה',
      );
      await PageShapeSettingsManager.saveConfiguration(
        'משנה נדה',
        const {
          'left': 'בועז על משנה נדה',
          'right': null,
          'bottom': null,
          'bottomRight': null,
        },
      );

      final config = PageShapeSettingsManager.loadConfiguration(
        'משנה נדה',
        heCategories: 'אוצריא, משנה, סדר טהרות, נדה',
      );
      expect(config?['left'], 'בועז על משנה נדה');
    });
  });
}
