import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';

import '../../helpers/memory_settings_cache.dart';

/// המודל של הפיצול: זוג חלוניות אופקי, ומה שקורה למצב שמור מגרסה שתמכה
/// בקינון ובציר אנכי.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  PdfBookTab leaf(String title) => PdfBookTab(
    book: PdfBook(title: title, path: '/tmp/$title.pdf'),
    pageNumber: 1,
  );

  Map<String, dynamic> splitJson(
    dynamic right,
    dynamic left, {
    double splitRatio = 0.5,
    bool isPinned = false,
  }) => {
    'type': 'CombinedTab',
    'rightTab': right,
    'leftTab': left,
    'splitRatio': splitRatio,
    'isPinned': isPinned,
  };

  OpenedTab nestedOf(
    List<OpenedTab> leaves, {
    double splitRatio = 0.5,
    bool isPinned = false,
  }) {
    var json = leaves.last.toJson();
    for (var i = leaves.length - 2; i >= 0; i--) {
      json = splitJson(
        leaves[i].toJson(),
        json,
        splitRatio: i == 0 ? splitRatio : 0.5,
        isPinned: i == 0 && isPinned,
      );
    }
    return OpenedTab.fromJson(json);
  }

  group('זוג החלוניות', () {
    test('הבנאי דוחה פיצול מקונן גם ב-release', () {
      final split = CombinedTab(rightTab: leaf('א'), leftTab: leaf('ב'));

      expect(
        () => CombinedTab(rightTab: split, leftTab: leaf('ג')),
        throwsArgumentError,
      );
    });

    test('panes מחזיר את שתיהן בסדר התצוגה', () {
      final a = leaf('א');
      final b = leaf('ב');

      expect(CombinedTab(rightTab: a, leftTab: b).panes, [same(a), same(b)]);
    });

    test('sibling מחזיר את החלונית שממול', () {
      final a = leaf('א');
      final b = leaf('ב');
      final tab = CombinedTab(rightTab: a, leftTab: b);

      expect(tab.sibling(a), same(b));
      expect(tab.sibling(b), same(a));
    });

    test('sibling מחזיר null לחלונית שאינה בטאב', () {
      final tab = CombinedTab(rightTab: leaf('א'), leftTab: leaf('ב'));

      expect(tab.sibling(leaf('זר')), isNull);
    });

    test('הכותרת נגזרת מהחלוניות ומתעדכנת אחריהן', () {
      final right = leaf('בראשית');
      final tab = CombinedTab(rightTab: right, leftTab: leaf('שמות'));

      expect(tab.title, 'משולב: בראשית | שמות');

      right.title = 'בראשית, פרק ג';
      expect(tab.title, 'משולב: בראשית, פרק ג | שמות');
    });

    test('כתיבה לכותרת נחסמת במפורש ואינה נבלעת', () {
      final tab = CombinedTab(rightTab: leaf('א'), leftTab: leaf('ב'));

      expect(() => tab.title = 'משהו', throwsUnsupportedError);
    });

    test('copyWith משמר יחס והצמדה כשלא נמסרו', () {
      final tab = CombinedTab(
        rightTab: leaf('א'),
        leftTab: leaf('ב'),
        splitRatio: 0.3,
        isPinned: true,
      );
      final c = leaf('ג');

      final copy = tab.copyWith(leftTab: c);

      expect(copy.rightTab, same(tab.rightTab));
      expect(copy.leftTab, same(c));
      expect(copy.splitRatio, 0.3);
      expect(copy.isPinned, isTrue);
    });

    test('copyWith דוחה פיצול מקונן', () {
      final tab = CombinedTab(rightTab: leaf('א'), leftTab: leaf('ב'));
      final nested = CombinedTab(rightTab: leaf('ג'), leftTab: leaf('ד'));

      expect(() => tab.copyWith(leftTab: nested), throwsArgumentError);
    });
  });

  group('leafPanes', () {
    test('טאב מפוצל מחזיר שתי חלוניות', () {
      final a = leaf('א');
      final b = leaf('ב');

      expect(leafPanes(CombinedTab(rightTab: a, leftTab: b)), [
        same(a),
        same(b),
      ]);
    });

    test('טאב רגיל הוא חלונית אחת — עצמו', () {
      final plain = leaf('רגיל');

      expect(leafPanes(plain), [same(plain)]);
    });
  });

  group('persistence', () {
    test('הלוך-ושוב משמר את הספרים, היחס וההצמדה', () {
      final original = CombinedTab(
        rightTab: leaf('א'),
        leftTab: leaf('ב'),
        splitRatio: 0.35,
        isPinned: true,
      );

      final restored = decodeCombinedTab(original.toJson()) as CombinedTab;

      expect(leafPanes(restored).map((p) => p.title).toList(), ['א', 'ב']);
      expect(restored.splitRatio, 0.35);
      expect(restored.isPinned, isTrue);
    });

    test('מפתח ציר ישן בקובץ אינו מפיל את השחזור', () {
      final json = CombinedTab(rightTab: leaf('א'), leftTab: leaf('ב')).toJson()
        ..['axis'] = 'vertical';

      final restored = decodeCombinedTab(json);

      expect(leafPanes(restored).map((p) => p.title).toList(), ['א', 'ב']);
    });

    test('הציר אינו נשמר יותר', () {
      final json = CombinedTab(
        rightTab: leaf('א'),
        leftTab: leaf('ב'),
      ).toJson();

      expect(json.containsKey('axis'), isFalse);
    });

    test('שכפול הטאב יוצר עותקים חדשים של שתי החלוניות', () {
      final original = CombinedTab(
        rightTab: leaf('א'),
        leftTab: leaf('ב'),
        splitRatio: 0.4,
      );

      final clone = OpenedTab.from(original) as CombinedTab;

      expect(clone.rightTab, isNot(same(original.rightTab)));
      expect(clone.leftTab, isNot(same(original.leftTab)));
      expect(clone.splitRatio, 0.4);
      expect(clone.rightTab, isNot(isA<CombinedTab>()));
      expect(clone.leftTab, isNot(isA<CombinedTab>()));
    });
  });

  group('decodeCombinedTab — חלונית שאינה ניתנת לשחזור', () {
    test('טיפוס לא מוכר בחלונית אחת אינו גורר את אחותה', () {
      final restored = decodeCombinedTab(
        splitJson(leaf('שורד').toJson(), {'type': 'TabMehadash'}),
      );

      expect(restored, isNot(isA<CombinedTab>()));
      expect(restored.title, 'שורד');
    });

    test('גם כשהחלונית הפגומה היא הימנית', () {
      final restored = decodeCombinedTab(
        splitJson({'type': 'TabMehadash'}, leaf('שורד').toJson()),
      );

      expect(restored.title, 'שורד');
    });

    test('חלונית חסרה לגמרי אינה מפילה את אחותה', () {
      final restored = decodeCombinedTab(
        splitJson(null, leaf('שורד').toJson()),
      );

      expect(restored.title, 'שורד');
    });

    test('הצמדת הפיצול עוברת לחלונית ששרדה', () {
      final json = splitJson(leaf('שורד').toJson(), {'type': 'TabMehadash'})
        ..['isPinned'] = true;

      expect(decodeCombinedTab(json).isPinned, isTrue);
    });

    test('כששתי החלוניות פגומות הטאב נזרק ולא נוצר טאב רפאים', () {
      expect(
        () => decodeCombinedTab(
          splitJson({'type': 'TabMehadash'}, {'type': 'TabAher'}),
        ),
        throwsFormatException,
      );
    });

    test('ערך הצמדה מטיפוס לא צפוי אינו מפיל את הפענוח', () {
      final json = splitJson(leaf('א').toJson(), leaf('ב').toJson())
        ..['isPinned'] = 'yes';

      final restored = decodeCombinedTab(json);

      expect(leafPanes(restored).map((p) => p.title).toList(), ['א', 'ב']);
      expect(restored.isPinned, isFalse);
    });

    test('יחס מחוץ לתחום נחסם ל-0..1', () {
      final json = splitJson(leaf('א').toJson(), leaf('ב').toJson())
        ..['splitRatio'] = 7.5;

      expect((decodeCombinedTab(json) as CombinedTab).splitRatio, 1.0);
    });
  });

  group('prunePanes', () {
    test('כששתי החלוניות נשמרות מוחזר אותו טאב', () {
      final tab = CombinedTab(rightTab: leaf('א'), leftTab: leaf('ב'));

      expect(prunePanes(tab, (_) => true), same(tab));
    });

    test('חלונית שנדחתה מוסרת ואחותה תופסת את מקום הטאב', () {
      final keeper = leaf('נשאר');
      final dropped = leaf('מוסר');
      final tab = CombinedTab(rightTab: dropped, leftTab: keeper);

      expect(prunePanes(tab, (pane) => pane != dropped), same(keeper));
    });

    test('כששתיהן נדחות מוחזר null', () {
      final tab = CombinedTab(rightTab: leaf('א'), leftTab: leaf('ב'));

      expect(prunePanes(tab, (_) => false), isNull);
    });

    test('טאב רגיל נבדק בעצמו', () {
      final plain = leaf('רגיל');

      expect(prunePanes(plain, (_) => true), same(plain));
      expect(prunePanes(plain, (_) => false), isNull);
    });
  });

  group('flattenRestoredSplits', () {
    test('רשימה בלי פיצול מקונן חוזרת כמות שהיא', () {
      final plain = leaf('רגיל');
      final split = CombinedTab(rightTab: leaf('א'), leftTab: leaf('ב'));

      expect(flattenRestoredSplits([plain, split]).tabs, [
        same(plain),
        same(split),
      ]);
    });

    test('פיצול מקונן נשמר כשתי החלוניות הראשונות', () {
      final a = leaf('א');
      final b = leaf('ב');
      final c = leaf('ג');

      final result = flattenRestoredSplits([
        nestedOf([a, b, c]),
      ]).tabs;

      expect(result, hasLength(2));
      final split = result[0] as CombinedTab;
      expect(split.rightTab.title, a.title);
      expect(split.leftTab.title, b.title);
      expect(result[1].title, c.title);
    });

    test('החלוניות העודפות אינן נעלמות גם בעומק גדול', () {
      final leaves = [
        for (final t in ['א', 'ב', 'ג', 'ד']) leaf(t),
      ];
      final nested = OpenedTab.fromJson(
        splitJson(
          splitJson(leaves[0].toJson(), leaves[1].toJson()),
          splitJson(leaves[2].toJson(), leaves[3].toJson()),
        ),
      );

      final result = flattenRestoredSplits([nested]).tabs;

      expect(result, hasLength(3));
      expect(leafPanes(result[0]).map((tab) => tab.title), ['א', 'ב']);
      expect(result[1].title, 'ג');
      expect(result[2].title, 'ד');
    });

    test('היחס וההצמדה של השורש עוברים לפיצול שנשאר', () {
      final nested = nestedOf(
        [leaf('א'), leaf('ב'), leaf('ג')],
        splitRatio: 0.25,
        isPinned: true,
      );

      final split = flattenRestoredSplits([nested]).tabs[0] as CombinedTab;

      expect(split.splitRatio, 0.25);
      expect(split.isPinned, isTrue);
    });

    test('ההצמדה עוברת גם לחלוניות העודפות שיצאו ככרטיסיות', () {
      final nested = nestedOf(
        [leaf('א'), leaf('ב'), leaf('ג')],
        isPinned: true,
      );

      final result = flattenRestoredSplits([nested]).tabs;

      expect(result[1].isPinned, isTrue);
    });

    test('פיצול שאינו מוצמד אינו מצמיד את החלוניות העודפות', () {
      final result = flattenRestoredSplits([
        nestedOf([leaf('א'), leaf('ב'), leaf('ג')]),
      ]).tabs;

      expect(result[1].isPinned, isFalse);
    });

    test('סדר הכרטיסיות סביב הפיצול נשמר', () {
      final before = leaf('לפני');
      final after = leaf('אחרי');
      final nested = nestedOf([leaf('א'), leaf('ב'), leaf('ג')]);

      final result = flattenRestoredSplits([before, nested, after]).tabs;

      expect(result.map((t) => t.title).toList(), [
        'לפני',
        'משולב: א | ב',
        'ג',
        'אחרי',
      ]);
    });

    test('רשימה ריקה חוזרת ריקה', () {
      expect(flattenRestoredSplits(const []).tabs, isEmpty);
    });
  });

  group('flattenRestoredSplits — האינדקס הפעיל', () {
    OpenedTab nested3() => nestedOf([leaf('א'), leaf('ב'), leaf('ג')]);

    test('כרטיסייה שאחרי פיצול מקונן נדחפת קדימה יחד עם האינדקס', () {
      final after = leaf('אחרי');

      final result = flattenRestoredSplits([nested3(), after], currentIndex: 1);

      expect(result.tabs[result.currentIndex], same(after));
    });

    test('כמה פיצולים מקוננים מצטברים', () {
      final after = leaf('אחרי');

      final result = flattenRestoredSplits([
        nested3(),
        nested3(),
        after,
      ], currentIndex: 2);

      expect(result.tabs[result.currentIndex], same(after));
    });

    test('אינדקס שמצביע על הפיצול עצמו אינו זז', () {
      final before = leaf('לפני');

      final result = flattenRestoredSplits([
        before,
        nested3(),
      ], currentIndex: 1);

      expect(result.currentIndex, 1);
      expect(result.tabs[1], isA<CombinedTab>());
    });

    test('אינדקס שלפני הפיצול אינו זז', () {
      final before = leaf('לפני');

      final result = flattenRestoredSplits([
        before,
        nested3(),
      ], currentIndex: 0);

      expect(result.tabs[result.currentIndex], same(before));
    });

    test('פיצול דו-חלוניתי רגיל אינו מזיז דבר', () {
      final after = leaf('אחרי');
      final split = CombinedTab(rightTab: leaf('א'), leftTab: leaf('ב'));

      final result = flattenRestoredSplits([split, after], currentIndex: 1);

      expect(result.currentIndex, 1);
      expect(result.tabs[1], same(after));
    });

    test('ברירת המחדל של האינדקס היא אפס', () {
      expect(flattenRestoredSplits([leaf('א')]).currentIndex, 0);
    });
  });
}
