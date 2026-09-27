import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_discovery.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_profile.dart';

/// הכותרות כאן הן כפי שהן במשאבי Hebrew.dll, English.dll ו-French.dll של
/// בר אילן.
void main() {
  const citation = ResponsaVersionProfile.citationHints;
  const info = ResponsaVersionProfile.infoModalHintsDefault;

  test('דיאלוג העיון — עברית, אנגלית וצרפתית', () {
    expect(ResponsaDiscovery.titleMatches(' עיון', citation), isTrue);
    expect(ResponsaDiscovery.titleMatches('Text', citation), isTrue);
    expect(ResponsaDiscovery.titleMatches('Texte', citation), isTrue);
    expect(ResponsaDiscovery.titleMatches('חיפוש', citation), isFalse);
  });

  test('חלון המידע — בדיוק, בכל שפה', () {
    expect(ResponsaDiscovery.titleMatches('מידע', info), isTrue);
    expect(ResponsaDiscovery.titleMatches('Information', info), isTrue);
    expect(ResponsaDiscovery.titleMatches('מידע נוסף', info), isFalse);
  });
}
