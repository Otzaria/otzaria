import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/view/plugin_correction_projection.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;

const _patah = 'ַ';
const _holam = 'ֹ';

void main() {
  const samples = [
    'בְּרֵאשִׁ֖ית בָּרָ֣א אֱלֹהִ֑ים אֵ֣ת־הַשָּׁמַ֔יִם',
    'אב ׀ גד',
    'אב־׀גד ׀',
    'abc | def',
    '',
  ];

  group('הטקסט הגלוי כמו בקורא', () {
    for (final sample in samples) {
      for (final nikud in [false, true]) {
        for (final teamim in [false, true]) {
          test('"$sample" ניקוד=$nikud טעמים=$teamim', () {
            final projection = CorrectionProjection(
              sample,
              nikud: nikud,
              teamim: teamim,
            );
            expect(
              projection.visible,
              utils.removeMarks(sample, nikud: nikud, teamim: teamim),
            );
            // כל תו גלוי ממופה ליחידה שהוא נובע ממנה, בסדר עולה.
            var previous = -1;
            for (var i = 0; i < projection.visible.length; i++) {
              final offset = projection.fullOffset(i);
              expect(offset, greaterThan(previous));
              expect(projection.visibleOffset(offset), i);
              previous = offset;
            }
            expect(
              projection.fullOffset(projection.visible.length),
              sample.length,
            );
          });
        }
      }
    }
  });

  test('סימנים מוסתרים שייכים לתו שלפניהם', () {
    final projection = CorrectionProjection(
      'ב$_patahב$_holam',
      nikud: true,
      teamim: false,
    );
    expect(projection.visible, 'בב');
    expect(projection.fullOffset(0), 0);
    expect(projection.fullOffset(1), 2);
    expect(projection.fullOffset(2), 4);
    expect(projection.visibleOffset(1), 1);
    expect(projection.visibleOffset(2), 1);
    expect(projection.visibleOffset(3), 2);
  });

  test('רווח שנמחק לפני פסק הוא הרווח הראשון, והנשאר גלוי הוא השני', () {
    final projection = CorrectionProjection(
      'אב ׀ גד',
      nikud: false,
      teamim: true,
    );
    expect(projection.visible, 'אב גד');
    expect(projection.fullOffset(2), 4);
  });

  test('בלי הסתרה הטקסט הגלוי הוא המלא וההיסטים זהים', () {
    final projection = CorrectionProjection(
      'ב$_patahב',
      nikud: false,
      teamim: false,
    );
    expect(projection.visible, 'ב$_patahב');
    expect(projection.fullOffset(2), 2);
    expect(projection.visibleOffset(2), 2);
  });
}
