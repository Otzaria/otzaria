import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/update/my_update_widget.dart';

void main() {
  group('changelogBetweenVersionsForUpdateDialog', () {
    test('reads the current hotfix section from the release changelog', () {
      final changelog = File('assets/יומן שינויים.md').readAsStringSync();
      final result = changelogBetweenVersionsForUpdateDialog(
        changelog: changelog,
        currentVersion: '0.9.97.1',
        latestVersion: '0.9.97.2',
      );

      expect(result, contains('גרסה זו יצאה עקב באגים שונים במתקינים'));
      expect(result, isNot(contains('כלי חדש: ביוגרפיות')));
    });

    test(
      'returns only versions between current and latest, including headings',
      () {
        const changelog = '''
* **0.9.92**
  - שינוי חדש

* **0.9.91**
  - תיקון ביניים

* **0.9.90**
  - שינוי ישן
''';

        final result = changelogBetweenVersionsForUpdateDialog(
          changelog: changelog,
          currentVersion: '0.9.90+9900',
          latestVersion: '0.9.92',
        );

        expect(result, contains('* **0.9.92**'));
        expect(result, contains('  - שינוי חדש'));
        expect(result, contains('* **0.9.91**'));
        expect(result, contains('  - תיקון ביניים'));
        expect(result, isNot(contains('* **0.9.90**')));
        expect(result, isNot(contains('  - שינוי ישן')));
      },
    );

    test('skips unheaded top changes because they are not released yet', () {
      const changelog = '''
  - שינוי ללא כותרת

* **0.9.91**
  - שינוי זמין

* **0.9.90**
  - שינוי ישן
''';

      final result = changelogBetweenVersionsForUpdateDialog(
        changelog: changelog,
        currentVersion: '0.9.90',
        latestVersion: '0.9.91-dev.1',
      );

      expect(result, contains('* **0.9.91**'));
      expect(result, contains('  - שינוי זמין'));
      expect(result, isNot(contains('  - שינוי ללא כותרת')));
      expect(result, isNot(contains('  - שינוי ישן')));
    });
  });

  group('rawAssetUrlForTag', () {
    test(
      'preserves the + separator inside release tags with build numbers',
      () {
        final url = rawAssetUrlForTag('0.9.92+628', 'assets/changelog.md');

        // `+` הוא תו חוקי ב-path segments לפי RFC 3986 ו-GitHub מקבל אותו
        // בצורתו המילולית בנתיב raw (אומת ידנית מול raw.githubusercontent.com).
        expect(
          url.pathSegments,
          containsAllInOrder(['Otzaria', 'otzaria', 'refs', 'tags']),
        );
        expect(url.pathSegments[4], '0.9.92+628');
        // והמחרוזת השלמה משמרת את ה-tag המלא, כך שהיומן יישלף מהקומיט הנכון
        // ולא מקומיט אחר עם אותה core version.
        expect(url.toString(), contains('/refs/tags/0.9.92+628/'));
      },
    );

    test('preserves release tags with v prefix verbatim', () {
      final url = rawAssetUrlForTag('v0.9.92', 'assets/changelog.md');
      expect(url.pathSegments[4], 'v0.9.92');
    });

    test('encodes Hebrew filename and spaces in the asset path', () {
      final url = rawAssetUrlForTag('0.9.92+628', 'assets/יומן שינויים.md');

      // pathSegments מקודד אוטומטית את התווים העבריים ואת הרווח.
      expect(url.scheme, 'https');
      expect(url.host, 'raw.githubusercontent.com');
      // הסגמנט האחרון, לאחר פענוח, חייב לחזור לערך המקורי.
      expect(url.pathSegments.last, 'יומן שינויים.md');
      // ובמחרוזת ה-URL הגולמית — חייב להופיע קידוד אחוז.
      expect(url.toString(), contains('%'));
      expect(url.toString(), isNot(contains(' ')));
    });
  });

  group('גרסאות hotfix (issue #1547)', () {
    // 0.9.97+99702 הוא hotfix 2; appReleaseVersion מציג אותו כ-0.9.97.2.
    test('hotfix מותקן מול התג שלו — אין עדכון', () {
      expect(
        isNewerReleaseVersion(
          latestVersion: '0.9.97.2',
          currentVersion: '0.9.97.2',
        ),
        isFalse,
      );
    });

    test('גרסת בסיס מול hotfix שלה — מוצע עדכון', () {
      expect(
        isNewerReleaseVersion(
          latestVersion: '0.9.97.2',
          currentVersion: '0.9.97',
        ),
        isTrue,
      );
    });

    test('hotfix מול הגרסה הבאה — מוצע עדכון, ולא להפך', () {
      expect(
        isNewerReleaseVersion(
          latestVersion: '0.9.98',
          currentVersion: '0.9.97.2',
        ),
        isTrue,
      );
      expect(
        isNewerReleaseVersion(
          latestVersion: '0.9.97.2',
          currentVersion: '0.9.98',
        ),
        isFalse,
      );
    });

    test('hotfix נמוך מול גבוה', () {
      expect(
        isNewerReleaseVersion(
          latestVersion: '0.9.97.3',
          currentVersion: '0.9.97.2',
        ),
        isTrue,
      );
    });

    test('תגים בפורמט הישן ממשיכים לעבוד', () {
      expect(
        isNewerReleaseVersion(
          latestVersion: '0.9.98',
          currentVersion: '0.9.97',
        ),
        isTrue,
      );
      expect(
        isNewerReleaseVersion(
          latestVersion: '0.9.97',
          currentVersion: '0.9.97',
        ),
        isFalse,
      );
      expect(
        isNewerReleaseVersion(
          latestVersion: '0.10.0+900',
          currentVersion: '0.9.99',
        ),
        isTrue,
      );
    });

    test('יומן השינויים כולל כותרת hotfix שבין הגרסאות', () {
      const changelog = '''
* **0.9.98**
  - גרסה הבאה

* **0.9.97.2**
  - תיקון חירום

* **0.9.97**
  - גרסת בסיס
''';

      final fromBase = changelogBetweenVersionsForUpdateDialog(
        changelog: changelog,
        currentVersion: '0.9.97',
        latestVersion: '0.9.97.2',
      );
      expect(fromBase, contains('* **0.9.97.2**'));
      expect(fromBase, contains('  - תיקון חירום'));
      expect(fromBase, isNot(contains('  - גרסה הבאה')));
      expect(fromBase, isNot(contains('  - גרסת בסיס')));

      final fromHotfix = changelogBetweenVersionsForUpdateDialog(
        changelog: changelog,
        currentVersion: '0.9.97.2',
        latestVersion: '0.9.98+800',
      );
      expect(fromHotfix, contains('  - גרסה הבאה'));
      expect(fromHotfix, isNot(contains('  - תיקון חירום')));
    });
  });
}
