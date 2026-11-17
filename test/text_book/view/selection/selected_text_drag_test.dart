import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/view/selection/selected_text_drag.dart';

void main() {
  test('CF_HTML offsets are UTF-8 byte offsets, including Hebrew niqqud', () {
    const html = '<span dir="rtl">בְּרֵאשִׁית</span>';
    final bytes = buildWindowsHtmlDragData(html);
    final header = utf8.decode(bytes);
    int offset(String key) =>
        int.parse(RegExp('$key:(\\d{10})').firstMatch(header)!.group(1)!);
    final startHtml = offset('StartHTML');
    final endHtml = offset('EndHTML');
    final startFragment = offset('StartFragment');
    final endFragment = offset('EndFragment');
    expect(startHtml, lessThan(startFragment));
    expect(endFragment, lessThan(endHtml));
    expect(endHtml, bytes.length);
    expect(utf8.decode(bytes.sublist(startFragment, endFragment)), html);
    expect(
      utf8.decode(bytes.sublist(startHtml, endHtml)),
      contains('<!--StartFragment-->$html<!--EndFragment-->'),
    );
  });

  test(
    'native drag starts only on a second drag inside existing selection',
    () {
      expect(
        shouldStartSelectedTextDrag(
          isSelectedTextHit: true,
          primaryMouseHeld: true,
          distance: 20,
        ),
        isTrue,
      );
      for (final (hit, held, distance) in [
        (false, true, 20.0),
        (true, false, 20.0),
        (true, true, 2.0),
      ]) {
        expect(
          shouldStartSelectedTextDrag(
            isSelectedTextHit: hit,
            primaryMouseHeld: held,
            distance: distance,
          ),
          isFalse,
        );
      }
    },
  );
}
