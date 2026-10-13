import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/indexing/models/catalogue_order_resolver.dart';

void main() {
  group('CatalogueOrderResolver', () {
    test('ספר שבספרייה מקבל את הסדר שנקבע לו', () {
      final resolver = CatalogueOrderResolver({'id:1': 0, 'id:2': 1});

      expect(resolver.orderFor('id:1'), 0);
      expect(resolver.orderFor('id:2'), 1);
    });

    test('ספר שאינו במפת הקטלוג נדחה לפני יצירת מזהה מסמך', () {
      final resolver = CatalogueOrderResolver({'id:1': 0});

      expect(
        () => resolver.orderFor('uid:404'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('uid:404'),
          ),
        ),
      );
    });

    test('מפתחות בעלי גיבוב זהה אינם מקבלים סדר משותף או תלוי-קריאה', () {
      final resolver = CatalogueOrderResolver({'id:1': 0});

      for (final key in const [
        'uid:1h5o88x:yde',
        'uid:1x7q2cs:18w3',
      ]) {
        expect(() => resolver.orderFor(key), throwsStateError);
      }
    });

    test('הסדר המרבי החוקי מתקבל', () {
      final resolver = CatalogueOrderResolver({
        'id:last': CatalogueOrderResolver.maxCatalogueOrder,
      });

      expect(
        resolver.orderFor('id:last'),
        CatalogueOrderResolver.maxCatalogueOrder,
      );
    });

    test('סדר שחורג מטווח u64 נדחה לפני המעבר למנוע', () {
      final resolver = CatalogueOrderResolver({
        'id:overflow': CatalogueOrderResolver.maxCatalogueOrder + 1,
      });

      expect(() => resolver.orderFor('id:overflow'), throwsRangeError);
    });

    test('סדר שלילי נדחה', () {
      final resolver = CatalogueOrderResolver({'id:negative': -1});

      expect(() => resolver.orderFor('id:negative'), throwsRangeError);
    });
  });

  group('CatalogueOrderResolver.fromPositions — טווח הספרים האישיים', () {
    const base = CatalogueOrderResolver.personalOrderBase;

    test('ספר רשמי ומצורף שומרים את מקומם; ספר אישי לפי ה-id בלבד', () {
      final resolver = CatalogueOrderResolver.fromPositions({
        'id:1': 0,
        'uid:1': 1,
        'id:2': 2,
        'db:lib:1': 3,
      });

      expect(resolver.orderFor('id:1'), 0);
      expect(resolver.orderFor('id:2'), 2);
      expect(resolver.orderFor('db:lib:1'), 3);
      expect(resolver.orderFor('uid:1'), base + 1);
    });

    test('ספר אישי שנוסף אינו משנה את הסדר של ספר אישי אחר', () {
      final before = CatalogueOrderResolver.fromPositions({
        'id:1': 0,
        'uid:5': 1,
      });
      final after = CatalogueOrderResolver.fromPositions({
        'uid:9': 0,
        'id:1': 1,
        'uid:5': 2,
      });

      expect(after.orderFor('uid:5'), before.orderFor('uid:5'));
      expect(after.orderFor('uid:9'), base + 9);
    });

    test('ספר אישי וספר רשמי עם אותו id אינם חולקים סדר', () {
      final resolver = CatalogueOrderResolver.fromPositions({
        'id:0': 0,
        'uid:0': 1,
        'db:lib:0': 2,
      });
      final orders = {
        for (final key in ['id:0', 'uid:0', 'db:lib:0']) resolver.orderFor(key),
      };

      expect(orders, hasLength(3));
      expect(resolver.orderFor('uid:0'), greaterThanOrEqualTo(base));
    });

    test('הטווח נשאר בתוך 24 הסיביות שמיון לפי דור במנוע שומר', () {
      final maxId = CatalogueOrderResolver.maxSortableOrder - base;
      final resolver = CatalogueOrderResolver.fromPositions({
        'uid:$maxId': 0,
        'uid:${maxId + 1}': 1,
      });

      expect(
        resolver.orderFor('uid:$maxId'),
        CatalogueOrderResolver.maxSortableOrder,
      );
      expect(() => resolver.orderFor('uid:${maxId + 1}'), throwsRangeError);
      // (order + 1) << 32 חייב להיכנס ב-56 סיביות.
      expect(
        (CatalogueOrderResolver.maxSortableOrder + 1) << 32,
        lessThan(1 << 56),
      );
    });

    test('מפתח שאינו `uid:<מספר>` קנוני נשאר במקומו ברצף', () {
      final resolver = CatalogueOrderResolver.fromPositions({
        'uid:007': 0,
        'title|cat|TextBook|': 1,
      });

      expect(resolver.orderFor('uid:007'), 0);
      expect(resolver.orderFor('title|cat|TextBook|'), 1);
    });

    test('רצף שמגיע לטווח הספרים האישיים נדחה', () {
      expect(
        () => CatalogueOrderResolver.fromPositions({'id:1': base}),
        throwsStateError,
      );
    });
  });
}
