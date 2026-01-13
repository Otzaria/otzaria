import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/toc_parser.dart';

void main() {
  group('TocParser.parseEntriesFromContent', () {
    test('parses HTML headings with leading whitespace', () {
      final content = '''
        <h1>כותרת ראשית</h1>
        טקסט רגיל
          <h2>כותרת משנה</h2>
        עוד טקסט
      ''';

      final toc = TocParser.parseEntriesFromContent(content);

      expect(toc.length, 1);
      expect(toc.first.text, 'כותרת ראשית');
      expect(toc.first.level, 1);
      expect(toc.first.children.length, 1);
      expect(toc.first.children.first.text, 'כותרת משנה');
      expect(toc.first.children.first.level, 2);
    });

    test('parses Markdown headings (#..######)', () {
      final content = '''
# פרק א
טקסט
## סעיף א
עוד טקסט
### תת סעיף
      ''';

      final toc = TocParser.parseEntriesFromContent(content);

      expect(toc.length, 1);
      expect(toc.first.text, 'פרק א');
      expect(toc.first.level, 1);
      expect(toc.first.children.length, 1);
      expect(toc.first.children.first.text, 'סעיף א');
      expect(toc.first.children.first.level, 2);
      expect(toc.first.children.first.children.length, 1);
      expect(toc.first.children.first.children.first.text, 'תת סעיף');
      expect(toc.first.children.first.children.first.level, 3);
    });

    test('does not treat hash-without-space as heading', () {
      final content = '###בלי רווח\nטקסט';
      final toc = TocParser.parseEntriesFromContent(content);
      expect(toc, isEmpty);
    });
  });
}
