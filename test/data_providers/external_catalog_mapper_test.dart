import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/external_catalog_mapper.dart';
import 'package:otzaria/external_catalog/providers/external_provider_registry.dart';

void main() {
  group('ExternalCatalogMapper', () {
    test('resolveLink מחזיר קישור HebrewBooks תקין', () {
      expect(
        ExternalCatalogMapper.resolveLink(externalLibraryId: 'hb:77'),
        'https://hebrewbooks.org/77',
      );
    });

    test('resolveLink מחזיר קישור אוצר החכמה תקין', () {
      expect(
        ExternalCatalogMapper.resolveLink(externalLibraryId: 'oh:42'),
        'https://tablet.otzar.org/book/book.php?book=42',
      );
    });

    test('resolveLink מחזיר null לפרויקט השו"ת — אין לו אתר', () {
      expect(
        ExternalCatalogMapper.resolveLink(externalLibraryId: 'rp:1524'),
        isNull,
      );
    });
  });

  group('פענוח prefix:value', () {
    test('oh:42 → אוצר החכמה, 42', () {
      final parsed = ExternalCatalogMapper.parse('oh:42')!;
      expect(parsed.provider.kind, ExternalProviderKind.otzar);
      expect(parsed.value, '42');
      expect(parsed.numericValue, 42);
    });

    test('hb:77 → היברובוקס, 77', () {
      final parsed = ExternalCatalogMapper.parse('hb:77')!;
      expect(parsed.provider.kind, ExternalProviderKind.hebrewBooks);
      expect(parsed.numericValue, 77);
    });

    test('rp:1524 → פרויקט השו"ת, 1524', () {
      final parsed = ExternalCatalogMapper.parse('rp:1524')!;
      expect(parsed.provider.kind, ExternalProviderKind.responsa);
      expect(parsed.provider.id, 'responsa');
      expect(parsed.numericValue, 1524);
      expect(parsed.canonicalId, 'rp:1524');
    });

    test('תחילית לא מוכרת אינה מזוהה', () {
      expect(ExternalCatalogMapper.parse('zz:5'), isNull);
      expect(
        ExternalCatalogMapper.extractExternalId(externalLibraryId: 'zz:5'),
        isNull,
      );
    });

    test('ערך ריק אינו מזוהה', () {
      expect(ExternalCatalogMapper.parse('rp:'), isNull);
      expect(ExternalCatalogMapper.parse(''), isNull);
      expect(ExternalCatalogMapper.parse(null), isNull);
    });

    test('מחרוזת עם מספר שאינה מזהה חיצוני אינה מחזירה את המספר', () {
      // שליפת ספרות מכל מחרוזת שהיא הייתה מחזירה כאן 3.
      expect(
        ExternalCatalogMapper.extractExternalId(
          externalLibraryId: 'ספר בן 3 חלקים',
        ),
        isNull,
      );
    });

    test('תחיליות תאימות לאחור ממשיכות לעבוד', () {
      expect(
        ExternalCatalogMapper.parse('otzar:9')!.provider.kind,
        ExternalProviderKind.otzar,
      );
      expect(
        ExternalCatalogMapper.parse('hebrewbooks:9')!.provider.kind,
        ExternalProviderKind.hebrewBooks,
      );
      expect(
        ExternalCatalogMapper.parse('responsa:9')!.provider.kind,
        ExternalProviderKind.responsa,
      );
    });

    test('מזהה חיצוני גובר על הקישור בקביעת הספק', () {
      final provider = ExternalCatalogMapper.providerOf(
        externalLibraryId: 'hb:123',
        link: 'file:///C:/otzaria/books/x.pdf',
      );
      expect(provider?.kind, ExternalProviderKind.hebrewBooks);
    });

    test('בלי מזהה חיצוני — הספק נקבע לפי הקישור', () {
      expect(
        ExternalCatalogMapper.providerOf(
          link: 'https://tablet.otzar.org/book/book.php?book=42',
        )?.kind,
        ExternalProviderKind.otzar,
      );
      expect(
        ExternalCatalogMapper.providerOf(
          link: 'https://hebrewbooks.org/77',
        )?.kind,
        ExternalProviderKind.hebrewBooks,
      );
    });
  });
}
