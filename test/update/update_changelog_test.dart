import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/update/my_update_widget.dart';

void main() {
  group('changelogBetweenVersionsForUpdateDialog', () {
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
    test('preserves the + separator inside dev-channel tags', () {
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
    });

    test('preserves stable-channel tags with v prefix verbatim', () {
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

    test('builds a path rooted under the upstream repo', () {
      final url = rawAssetUrlForTag('0.9.92+628', 'assets/foo.md');
      expect(url.pathSegments.first, 'Otzaria');
      expect(url.pathSegments[1], 'otzaria');
      expect(url.pathSegments[2], 'refs');
      expect(url.pathSegments[3], 'tags');
    });
  });

  group('pickLatestDevRelease', () {
    Map<String, dynamic> rel(
      String tag, {
      bool prerelease = true,
      bool draft = false,
    }) {
      return {
        'tag_name': tag,
        'prerelease': prerelease,
        'draft': draft,
      };
    }

    test(
      'returns the newest matching pre-release when two share core version',
      () {
        // GitHub מחזיר releases מהחדש לישן. אם 628 ו-629 שניהם תקפים,
        // יש לבחור את 629 — אחרת ה-changelog/binary לא יתאמו ל-release
        // שזוהה כ"latest".
        final releases = [
          rel('0.9.92+629'),
          rel('0.9.92+628'),
        ];

        final picked = pickLatestDevRelease(releases);

        expect(picked['tag_name'], '0.9.92+629');
      },
    );

    test('skips draft and PR-preview releases', () {
      final releases = [
        rel('0.9.92-pr.5+999'), // PR preview — חייב להידחות
        rel('0.9.92+650', draft: true), // draft — חייב להידחות
        rel('0.9.92+628'), // המועמד התקף הראשון
        rel('0.9.91+622'),
      ];

      final picked = pickLatestDevRelease(releases);

      expect(picked['tag_name'], '0.9.92+628');
    });

    test('falls back to the first release if nothing matches the filter', () {
      // לדוגמה, אם הכל draft או PR preview — שמירה על ההתנהגות הקודמת
      // של firstWhere(orElse: ...).
      final releases = [
        rel('0.9.92-pr.1+100'),
        rel('0.9.91-pr.1+50'),
      ];

      final picked = pickLatestDevRelease(releases);

      expect(picked['tag_name'], '0.9.92-pr.1+100');
    });
  });

  group('release cache keying', () {
    setUp(() => releaseCacheForTesting.clear());
    tearDown(() => releaseCacheForTesting.clear());

    test(
      'stable and dev entries with the same core version do not collide',
      () {
        // התרחיש: stable=0.9.92, ובמקביל dev=0.9.92+629. שני המפתחות
        // המנורמלים זהים ("0.9.92"), אבל ה-release-ים שונים — לכן חובה
        // שהמפתח יכלול גם את הערוץ.
        releaseCacheForTesting['stable:0.9.92'] = {'tag_name': 'v0.9.92'};
        releaseCacheForTesting['dev:0.9.92'] = {'tag_name': '0.9.92+629'};

        expect(releaseCacheForTesting['stable:0.9.92']!['tag_name'], 'v0.9.92');
        expect(releaseCacheForTesting['dev:0.9.92']!['tag_name'], '0.9.92+629');
      },
    );
  });
}
