import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';
import 'package:otzaria/plugins/view/plugin_tab_page.dart';

class MockDataRepository extends Mock implements DataRepository {}

void main() {
  group('buildResolveReference (library.resolveRef wiring)', () {
    // ספר אישי יחיד, נמצא רק כשהחיפוש כולל ספרים אישיים — בדיוק כמו
    // הבדיקות ב-find_ref_repository_test.dart עבור includePersonalBooks.
    final personalBook = (
      id: 99,
      title: 'ספר פרטי',
      filePath: null,
      fileType: 'txt',
      orderIndex: 1.0,
      folderTitles: const <String>[],
    );

    FindRefRepository buildRepo() => FindRefRepository(
      dataRepository: MockDataRepository(),
      isReferenceBooksCacheLoaded: () => true,
      warmUpReferenceBooksCache: () async {},
      searchReferenceBooks: (_, {limit = 50}) => const [],
      getTocEntriesForReference: (_, _, {queryTokens}) async => const [],
      getAllUserBooks: () async => [personalBook],
      getUserBookTocEntries: (_, _, {queryTokens}) async => const [],
    );

    test(
      'ספר אישי מוחזר דרך library.resolveRef — לא רק דרך FindRefDialog '
      '(issue: הטוגל "כלול ספרים אישיים" לא הועבר לתוסף)',
      () async {
        final resolveReference = buildResolveReference(buildRepo());
        final results = await resolveReference('ספר');
        expect(
          results.any((r) => r.isUserBook && r.title == 'ספר פרטי'),
          isTrue,
        );
      },
    );

    test(
      'בלי הזרקת הפרמטר, findRefs היה מחזיר ברירת מחדל false ומחסיר את הספר',
      () async {
        // בדיקת-נגד: מוודאת שהתשתית עצמה (findRefs) עדיין דורשת opt-in מפורש,
        // כדי שהבדיקה הקודמת אכן תלויה בכך ש-buildResolveReference מבקש
        // includePersonalBooks: true ולא בהתנהגות ברירת המחדל של הרפוזיטורי.
        final results = await buildRepo().findRefs('ספר');
        expect(results.any((r) => r.isUserBook), isFalse);
      },
    );
  });
}
