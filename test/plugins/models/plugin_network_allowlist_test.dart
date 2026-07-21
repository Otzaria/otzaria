import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/plugin_network_allowlist.dart';

void main() {
  group('matchingNetworkAllowlistPrefix', () {
    const allowlist = [
      'https://github.com/Open-Otzarya-Projects/Otzarya-Unofficial-Books',
      'https://nakdan.dicta.org.il/api',
    ];

    test('מתיר URL מהרשימה ותתי-נתיביו', () {
      expect(
        matchingNetworkAllowlistPrefix(
            Uri.parse(
                'https://github.com/Open-Otzarya-Projects/Otzarya-Unofficial-Books/releases/latest/download/a.zip'),
            allowlist),
        isNotNull,
      );
      expect(
        matchingNetworkAllowlistPrefix(
            Uri.parse('https://nakdan.dicta.org.il/api?text=שלום'), allowlist),
        isNotNull,
      );
    });

    test('חוסם נתיב אחר, קידומת חלקית ודומיין אחר', () {
      expect(
        matchingNetworkAllowlistPrefix(
            Uri.parse('https://github.com/Someone/Other/releases'), allowlist),
        isNull,
      );
      expect(
        matchingNetworkAllowlistPrefix(
            Uri.parse('https://nakdan.dicta.org.il/apix'), allowlist),
        isNull,
      );
      expect(
        matchingNetworkAllowlistPrefix(
            Uri.parse('https://objects.githubusercontent.com/abc/a.zip'),
            allowlist),
        isNull,
      );
    });
  });

  group('isUriAllowedForPluginNetwork', () {
    test('מתיר URL של מאגר הספרים המאושר ותתי-נתיביו', () {
      expect(
        isUriAllowedForPluginNetwork(Uri.parse(
            'https://github.com/Open-Otzarya-Projects/Otzarya-Unofficial-Books/releases/latest/download/a.zip')),
        isTrue,
      );
    });

    test('חוסם דומייני CDN של גיטהאב כגישה ישירה (אינם ברשימה הגלובלית)', () {
      expect(
        isUriAllowedForPluginNetwork(
            Uri.parse('https://objects.githubusercontent.com/abc/a.zip')),
        isFalse,
      );
      expect(
        isUriAllowedForPluginNetwork(Uri.parse(
            'https://release-assets.githubusercontent.com/abc/a.zip')),
        isFalse,
      );
    });

    test('חוסם מאגר גיטהאב אחר', () {
      expect(
        isUriAllowedForPluginNetwork(
            Uri.parse('https://github.com/Someone/Other/releases')),
        isFalse,
      );
    });
  });

  group('matchingLoopbackPrefix', () {
    test('host חשוף מתיר כל פורט/נתיב על אותו host', () {
      const allowlist = ['127.0.0.1', 'localhost'];
      expect(
        matchingLoopbackPrefix(
            Uri.parse('http://127.0.0.1:11434/api/tags'), allowlist),
        isNotNull,
      );
      expect(
        matchingLoopbackPrefix(
            Uri.parse('http://localhost:1234/v1/models'), allowlist),
        isNotNull,
      );
    });

    test('URL מלא עם פורט מתיר רק את אותו פורט', () {
      const allowlist = ['http://127.0.0.1:11434'];
      expect(
        matchingLoopbackPrefix(
            Uri.parse('http://127.0.0.1:11434/api/tags'), allowlist),
        isNotNull,
      );
      expect(
        matchingLoopbackPrefix(
            Uri.parse('http://127.0.0.1:1234/api/tags'), allowlist),
        isNull,
      );
    });

    test('חוסם כשאין הצהרת loopback תואמת, או כשהיעד אינו loopback', () {
      expect(
        matchingLoopbackPrefix(
            Uri.parse('http://127.0.0.1:11434/api'), const []),
        isNull,
      );
      expect(
        matchingLoopbackPrefix(
            Uri.parse('https://example.com'), const ['127.0.0.1']),
        isNull,
      );
    });
  });

  group('requiredNetworkPermissionFor', () {
    test('יעד loopback דורש network.localhost', () {
      expect(requiredNetworkPermissionFor(Uri.parse('http://127.0.0.1:11434')),
          'network.localhost');
      expect(requiredNetworkPermissionFor(Uri.parse('http://localhost:1234')),
          'network.localhost');
    });

    test('יעד אינטרנט דורש network.access', () {
      expect(
          requiredNetworkPermissionFor(
              Uri.parse('https://nakdan.dicta.org.il')),
          'network.access');
    });
  });

  group('parsePluginNetworkAllowlistText', () {
    test('מפרק שורות ומדלג על הערות ושורות ריקות', () {
      const source = '''
# הערה בראש הקובץ
https://a.example.com

  https://b.example.com/path
# הערה נוספת
''';

      expect(
        parsePluginNetworkAllowlistText(source),
        ['https://a.example.com', 'https://b.example.com/path'],
      );
    });
  });

  group('isGithubReleaseRedirectAllowed', () {
    final githubRelease = Uri.parse(
        'https://github.com/Open-Otzarya-Projects/Otzarya-Unofficial-Books/releases/latest/download/a.zip');
    final cdn =
        Uri.parse('https://release-assets.githubusercontent.com/abc/a.zip');

    test('מתיר redirect מ-github.com אל ה-CDN', () {
      expect(isGithubReleaseRedirectAllowed(githubRelease, cdn), isTrue);
    });

    test('מתיר המשך שרשרת redirect בין דומייני CDN', () {
      final cdn2 = Uri.parse('https://objects.githubusercontent.com/x/a.zip');
      expect(isGithubReleaseRedirectAllowed(cdn, cdn2), isTrue);
    });

    test('חוסם redirect ליעד שאינו דומיין CDN של גיטהאב', () {
      final evil = Uri.parse('https://evil.example.com/a.zip');
      expect(isGithubReleaseRedirectAllowed(githubRelease, evil), isFalse);
    });

    test('חוסם redirect ל-CDN ממקור שאינו github/CDN', () {
      final arbitrary = Uri.parse('https://otzaria.org/x');
      expect(isGithubReleaseRedirectAllowed(arbitrary, cdn), isFalse);
    });
  });
}
