import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';

Link _link({
  required String heRef,
  String path2 = 'רמב"ן על דברים',
  String? heRefEnd,
  int? index2End,
}) => Link(
  heRef: heRef,
  index1: 1,
  path2: path2,
  index2: 0,
  connectionType: LinkTypes.commentary,
  heRefEnd: heRefEnd,
  index2End: index2End,
);

void main() {
  group('כתובת התצוגה מוותרת על הרמה האחרונה', () {
    test('רמב"ן: אינדקס הפירוש בתוך הפסוק יורד מהתצוגה', () {
      expect(
        _link(heRef: 'רמב"ן על דברים,  ז, ט, א').fallbackDisplayReference,
        'רמב"ן על דברים, ז, ט',
      );
      expect(
        _link(heRef: 'רמב"ן על דברים,  ז, יב, א').fallbackDisplayReference,
        'רמב"ן על דברים, ז, יב',
      );
    });

    test('קישור-טווח שמובחן ברמה האחרונה שומר עליה', () {
      final link = _link(
        heRef: 'רמב"ן על דברים,  יג, ה, ב',
        heRefEnd: 'רמב"ן על דברים,  יג, ה, ג',
        index2End: 5,
      );
      expect(
        link.fallbackDisplayReference.startsWith('רמב"ן על דברים, יג, ה, ב'),
        isTrue,
        reason: 'got ${link.fallbackDisplayReference}',
      );
    });

    test('כתובת דו-רכיבית לא מתקצרת לשם הספר בלבד', () {
      expect(
        _link(
          heRef: 'משנה ברורה,  לב',
          path2: 'משנה ברורה',
        ).fallbackDisplayReference,
        'משנה ברורה, לב',
      );
    });

    test('משנה ברורה: הס"ק נשמר — כתובת תלת-רכיבית לא מתקצרת', () {
      expect(
        _link(
          heRef: 'משנה ברורה,  לב, ה',
          path2: 'משנה ברורה',
        ).fallbackDisplayReference,
        'משנה ברורה, לב, ה',
      );
    });
  });
}
