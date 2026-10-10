import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_common/selection/commentary_selection.dart';

void main() {
  group('restoreCommentaryLineBreaks', () {
    String? restore(String? flat) => restoreCommentaryLineBreaks(
      flat,
      orderedKeys: ['a', 'b'],
      titlesByKey: const {'a': 'רש"י', 'b': 'תוספות'},
      textsByKey: const {'a': 'בראשית ברא', 'b': 'אלהים את'},
    );

    test('בחירה שטוחה מקבלת את מעברי השורה של המפרשים', () {
      expect(
        restore('רש"יבראשית בראתוספותאלהים'),
        'רש"י\nבראשית ברא\nתוספות\nאלהים',
      );
    });

    test('בחירה ריקה, null או עם מעברי שורה חוזרת כמות שהיא', () {
      expect(restore(null), isNull);
      expect(restore(''), '');
      expect(restore('א\nב'), 'א\nב');
    });

    test('בלי טקסט מרונדר הבחירה חוזרת כמות שהיא', () {
      expect(
        restoreCommentaryLineBreaks(
          'בראשית ברא',
          orderedKeys: ['a'],
          titlesByKey: const {},
          textsByKey: const {},
        ),
        'בראשית ברא',
      );
    });
  });
}
