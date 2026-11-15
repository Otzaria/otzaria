import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/text_book/companion/tur_shulchan_aruch.dart';

void main() {
  group('turShulchanAruchPairTitles', () {
    test('the Tur pairs with the four Shulchan Arukh parts', () {
      expect(turShulchanAruchPairTitles(TextBook(title: 'טור')), [
        'שולחן ערוך, אורח חיים',
        'שולחן ערוך, יורה דעה',
        'שולחן ערוך, אבן העזר',
        'שולחן ערוך, חושן משפט',
      ]);
    });

    test('each Shulchan Arukh part pairs with the Tur', () {
      expect(
        turShulchanAruchPairTitles(TextBook(title: 'שולחן ערוך, אבן העזר')),
        ['טור'],
      );
    });

    test('other and unofficial books have no pair', () {
      expect(
        turShulchanAruchPairTitles(TextBook(title: 'משנה ברורה')),
        isEmpty,
      );
      expect(
        turShulchanAruchPairTitles(TextBook(title: 'שולחן ערוך, הקדמה')),
        isEmpty,
      );
      expect(
        turShulchanAruchPairTitles(
          TextBook(title: 'טור', source: BookSource.user),
        ),
        isEmpty,
      );
    });
  });

  group('turShulchanAruchTarget', () {
    test('Tur → the Shulchan Arukh part at the same siman', () {
      expect(turShulchanAruchTarget('טור', 'טור, אורח חיים,  כה, א'), (
        title: 'שולחן ערוך, אורח חיים',
        refKey: 'כה א',
      ));
      expect(turShulchanAruchTarget('טור', 'טור, חושן משפט, תכז, ג'), (
        title: 'שולחן ערוך, חושן משפט',
        refKey: 'תכז א',
      ));
    });

    test('Shulchan Arukh → the Tur at the same siman', () {
      expect(
        turShulchanAruchTarget(
          'שולחן ערוך, אורח חיים',
          'שולחן ערוך, אורח חיים, תקפח, ב',
        ),
        (title: 'טור', refKey: 'אורח חיים תקפח א'),
      );
    });

    test('extra spaces after the comma are ignored', () {
      expect(
        turShulchanAruchTarget(
          'שולחן ערוך, אבן העזר',
          'שולחן ערוך, אבן העזר,  א, ב',
        ),
        (title: 'טור', refKey: 'אבן העזר א א'),
      );
    });

    test('an introduction opens the other book with no siman', () {
      expect(turShulchanAruchTarget('טור', 'טור, יורה דעה, הקדמה,  ב'), (
        title: 'שולחן ערוך, יורה דעה',
        refKey: null,
      ));
    });

    test('a heRef of another book has no target', () {
      expect(turShulchanAruchTarget('טור', 'משנה ברורה, א, א'), isNull);
      expect(
        turShulchanAruchTarget('שולחן ערוך, יורה דעה', 'טור, יורה דעה, א, א'),
        isNull,
      );
    });
  });
}
