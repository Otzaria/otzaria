import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_catalog_builder.dart';
import 'package:otzaria/external_catalog/responsa/text/responsa_structure.dart';

/// שימור `external_key` בין בנייה לבנייה.
///
/// ה-key הוא זהות הספר מחוץ לקטלוג: הסימניות, ההיסטוריה והמועדפים של
/// המשתמש מצביעים עליו. רענון שמזיז אותו אינו שגיאה שהמשתמש רואה —
/// הוא פותח ספר אחר.
void main() {
  /// שרשרת עץ שבה הצומת האחרון הוא החיבור (סוג 4).
  ResponsaBookRow row(List<String> path, {int param = 7}) => ResponsaBookRow(
    chain: [
      for (final (i, name) in path.indexed)
        (
          level: i,
          param: i == path.length - 1
              ? (ResponsaStructure.workKind << 16) | param
              : (1 << 16),
          name: name,
        ),
    ],
  );

  ({String key, String refPath, int? treeParam}) old(
    String key,
    String refPath, {
    int? treeParam = 7,
  }) => (key: key, refPath: refPath, treeParam: treeParam);

  test('קטלוג ראשון — מזהים רצים מאחד', () {
    final result = ResponsaCatalogBuilder.assignExternalKeys([
      row(['שו"ת', 'אבני נזר']),
      row(['שו"ת', 'חתם סופר']),
    ], const []);

    expect(result.keys, ['1', '2']);
    expect(result.stats['new'], 2);
  });

  test('נתיב זהה — אותו מזהה נשמר', () {
    final result = ResponsaCatalogBuilder.assignExternalKeys(
      [
        row(['שו"ת', 'חתם סופר']),
        row(['שו"ת', 'אבני נזר']),
      ],
      [old('41', 'שו"ת > אבני נזר'), old('17', 'שו"ת > חתם סופר')],
    );

    expect(result.keys, ['17', '41']);
    expect(result.stats['exact'], 2);
    expect(result.stats['new'], 0);
  });

  /// שינוי כתיב בין מהדורות הוא רפורמה שיטתית, לא באג. ספר שנשאר אותו
  /// ספר חייב לשמור על המזהה.
  test('הבדל כתיב בלבד — המזהה נשמר בשלב הנרמול', () {
    final result = ResponsaCatalogBuilder.assignExternalKeys(
      [
        row(['שו"ת', 'חדושי הרים']),
      ],
      [old('9', 'שו"ת > חידושי הרים')],
    );

    expect(result.keys, ['9']);
    expect(result.stats['normalized'], 1);
  });

  /// חיבור ששמו שונה מזוהה לפי ההורה וה-`lParam` שלו בעץ — המספר
  /// שהתוכנה עצמה נותנת לצומת, ולא השם.
  test('שם החיבור השתנה — המזהה נשמר לפי ההורה וה-param', () {
    final book = row(['שו"ת', 'אחרונים', 'אבני נזר'], param: 55);
    final result = ResponsaCatalogBuilder.assignExternalKeys(
      [book],
      [
        old(
          '4',
          'שו"ת > אחרונים > אבני נזר החדש',
          treeParam: book.treeParam,
        ),
      ],
    );

    expect(result.keys, ['4']);
    expect(result.stats['parentParam'], 1);
  });

  /// שני ספרים שנתיבם זהה אינם ניתנים להבחנה, ולכן איש מהם אינו יורש
  /// את המזהה: ירושה שרירותית פותחת ספר אחר מזה שהסימנייה מצביעה עליו.
  test('נתיב שמופיע פעמיים — אף אחד אינו יורש', () {
    final result = ResponsaCatalogBuilder.assignExternalKeys(
      [
        row(['שו"ת', 'שם כפול']),
        row(['שו"ת', 'שם כפול']),
      ],
      [old('8', 'שו"ת > שם כפול')],
    );

    expect(result.stats['exact'], 0);
    expect(result.keys.toSet(), hasLength(2));
    expect(result.keys, isNot(contains('8')));
  });

  test('מזהה חדש אינו דורס מזהה קיים, גם כשהקיים גבוה', () {
    final result = ResponsaCatalogBuilder.assignExternalKeys(
      [
        row(['שו"ת', 'אבני נזר']),
        row(['שו"ת', 'ספר חדש']),
      ],
      [old('100', 'שו"ת > אבני נזר')],
    );

    expect(result.keys, ['100', '101']);
  });

  /// זה מה שקורה כשקריאת הקטלוג הקיים נכשלת: הרשימה חוזרת ריקה, וכל
  /// הספרים מקבלים מזהה חדש. הבדיקה מתעדת את המחיר.
  test('בלי קטלוג קיים — כל הספרים מקבלים מזהה חדש', () {
    final books = [
      row(['שו"ת', 'א']),
      row(['שו"ת', 'ב']),
      row(['שו"ת', 'ג']),
    ];
    expect(
      ResponsaCatalogBuilder.assignExternalKeys(books, const []).stats['new'],
      3,
    );
  });
}
