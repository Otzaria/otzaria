import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/link_types.dart';

void main() {
  group('LinkTypes.isDependentTextLink', () {
    test('מזהה את סוגי הקישורים התלויים שמוצגים כמפרשים', () {
      for (final type in const [
        'COMMENTARY',
        'SUPER_COMMENTARY',
        'TARGUM',
        'MIDRASH',
        'PARSHANUT',
        'DIBUR_HAMATCHIL',
        'ELUCIDATION',
        'EXPLICATION',
      ]) {
        expect(LinkTypes.isDependentTextLink(type), isTrue, reason: type);
      }
    });

    test('דוחה סוגי הפניה ואת SOURCE הווירטואלי', () {
      for (final type in const [
        'REFERENCE',
        'QUOTATION',
        'MESORAT_HASHAS',
        'EIN_MISHPAT',
        'MISHNAH_IN_TALMUD',
        'RELATED',
        'OTHER',
        'SOURCE',
      ]) {
        expect(LinkTypes.isDependentTextLink(type), isFalse, reason: type);
      }
    });

    test('אינו תלוי רישיות ומחזיר false ל-null', () {
      expect(LinkTypes.isDependentTextLink('commentary'), isTrue);
      expect(LinkTypes.isDependentTextLink('Targum'), isTrue);
      expect(LinkTypes.isDependentTextLink(null), isFalse);
    });
  });

  group('LinkTypes.isReferenceLikeLink', () {
    test('מזהה קשרי עיון/הפניה אך לא מפרשים או SOURCE', () {
      expect(LinkTypes.isReferenceLikeLink('REFERENCE'), isTrue);
      expect(LinkTypes.isReferenceLikeLink('QUOTATION'), isTrue);
      expect(LinkTypes.isReferenceLikeLink('EIN_MISHPAT'), isTrue);
      expect(LinkTypes.isReferenceLikeLink('OTHER'), isTrue);
      expect(LinkTypes.isReferenceLikeLink('COMMENTARY'), isFalse);
      expect(LinkTypes.isReferenceLikeLink('EXPLICATION'), isFalse);
      expect(LinkTypes.isReferenceLikeLink('SOURCE'), isFalse);
      expect(LinkTypes.isReferenceLikeLink(null), isFalse);
    });
  });

  group('LinkTypes.isVirtualSource', () {
    test('מזהה רק את SOURCE (לא תלוי רישיות)', () {
      expect(LinkTypes.isVirtualSource('SOURCE'), isTrue);
      expect(LinkTypes.isVirtualSource('source'), isTrue);
      expect(LinkTypes.isVirtualSource('COMMENTARY'), isFalse);
      expect(LinkTypes.isVirtualSource(null), isFalse);
    });
  });
}
