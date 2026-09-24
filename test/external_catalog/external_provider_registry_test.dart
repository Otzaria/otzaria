import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/external_catalog/providers/external_provider_registry.dart';

/// נועל את החוזה של הרישום: תחיליות, יכולות ולוגו לכל ספק.
/// שינוי כאן משנה זהות של ספרים שכבר נשמרו אצל משתמשים.
void main() {
  group('ExternalProviderRegistry', () {
    test('אוצר החכמה — פתיחה באתר ומקומית', () {
      const provider = ExternalProviderRegistry.otzar;
      expect(provider.id, 'otzar');
      expect(provider.idPrefix, 'oh');
      expect(provider.capabilities.webOpen, isTrue);
      expect(provider.capabilities.localOpen, isTrue);
      expect(provider.capabilities.pdfDownload, isFalse);
      expect(provider.iconAsset, 'assets/logos/otzar.ico');
      expect(
        provider.webLinkFor('42'),
        'https://tablet.otzar.org/book/book.php?book=42',
      );
    });

    test('היברובוקס — פתיחה באתר והורדת PDF', () {
      const provider = ExternalProviderRegistry.hebrewBooks;
      expect(provider.id, 'hebrewbooks');
      expect(provider.idPrefix, 'hb');
      expect(provider.capabilities.webOpen, isTrue);
      expect(provider.capabilities.pdfDownload, isTrue);
      expect(provider.capabilities.localOpen, isFalse);
      expect(provider.iconAsset, 'assets/logos/hebrew_books.png');
      expect(provider.webLinkFor('77'), 'https://hebrewbooks.org/77');
    });

    test('פרויקט השו"ת — פתיחה מקומית בלבד, בלי אתר ובלי PDF', () {
      const provider = ExternalProviderRegistry.responsa;
      expect(provider.id, 'responsa');
      expect(provider.idPrefix, 'rp');
      expect(provider.capabilities.webOpen, isFalse);
      expect(provider.capabilities.localOpen, isTrue);
      expect(provider.capabilities.pdfDownload, isFalse);
      expect(provider.webLinkFor('1524'), isNull);
      expect(provider.externalLibraryIdFor('1524'), 'rp:1524');
    });

    test('תחיליות אינן מתנגשות בין ספקים', () {
      final seen = <String>{};
      for (final provider in ExternalProviderRegistry.all) {
        for (final prefix in provider.allPrefixes) {
          expect(seen.add(prefix), isTrue, reason: 'תחילית כפולה: $prefix');
        }
      }
    });

    /// הכפתור המשותף מחווט לפותחן של פרויקט השו"ת. ספר של אוצר החכמה
    /// שהגיע אליו נכשל בהודעה "הספר אינו ספר של פרויקט השו"ת", ומסלול
    /// הפתיחה המקומי האמיתי שלו אינו נקרא כלל.
    test('הכפתור המשותף לפתיחה מקומית אינו של אוצר החכמה', () {
      expect(
        ExternalProviderRegistry.usesSharedLocalOpen(
          ExternalProviderRegistry.responsa,
        ),
        isTrue,
      );
      expect(
        ExternalProviderRegistry.usesSharedLocalOpen(
          ExternalProviderRegistry.otzar,
        ),
        isFalse,
        reason: 'לאוצר החכמה מסלול פתיחה מקומי משלו',
      );
      expect(
        ExternalProviderRegistry.usesSharedLocalOpen(
          ExternalProviderRegistry.hebrewBooks,
        ),
        isFalse,
        reason: 'אין לו פתיחה מקומית כלל',
      );
      expect(ExternalProviderRegistry.usesSharedLocalOpen(null), isFalse);
    });

    test('byId ו-byPrefix אינם רגישים לרישיות ולרווחים', () {
      expect(ExternalProviderRegistry.byId(' Responsa ')?.idPrefix, 'rp');
      expect(ExternalProviderRegistry.byPrefix('OH')?.id, 'otzar');
      expect(ExternalProviderRegistry.byId('אין כזה'), isNull);
      expect(ExternalProviderRegistry.byPrefix(''), isNull);
    });
  });
}
