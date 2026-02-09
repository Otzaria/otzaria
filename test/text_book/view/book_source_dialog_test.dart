import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/view/book_source_dialog.dart';

void main() {
  group('getSourceDisplayInfo', () {
    test('should resolve Sefaria source case-insensitively', () {
      final lower = getSourceDisplayInfo('sefaria');
      final upper = getSourceDisplayInfo('Sefaria');

      expect(lower['text'], equals('ספריא'));
      expect(upper['text'], equals('ספריא'));
      expect(lower['url'], equals('https://www.sefaria.org/texts'));
      expect(upper['url'], equals('https://www.sefaria.org/texts'));
    });
  });
}
