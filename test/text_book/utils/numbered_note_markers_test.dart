import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/text_book/utils/numbered_note_markers.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;

Link _link(String title, {int index2 = 1, String type = 'COMMENTARY'}) => Link(
  heRef: title,
  index1: 1,
  path2: title,
  index2: index2,
  connectionType: type,
);

void main() {
  group('addNumberedNoteMarkerLinks', () {
    test('עוטף כל סמן-מספר בעוגן ריחוף', () {
      const line = '<b>מאי לאו</b>, קרבן פסח!? (9) ומשנינן: <b>לא</b>. (10)';

      final result = addNumberedNoteMarkerLinks(line, lineIndex: 5963);

      expect(
        result,
        contains('href="otzaria://note-marker?line=5963&num=9">(9)</a>'),
      );
      expect(
        result,
        contains('href="otzaria://note-marker?line=5963&num=10">(10)</a>'),
      );
    });

    test('לא נוגע בטקסט הגלוי — רק מוסיף תגים', () {
      const line = 'טקסט (9) המשך <b>מודגש (10)</b>';

      final result = addNumberedNoteMarkerLinks(line, lineIndex: 0);

      expect(utils.stripHtmlIfNeeded(result), utils.stripHtmlIfNeeded(line));
    });

    test('מדלג על מספרים בתוך תגי HTML', () {
      const line = '<span class="link-anchor-(3)">טקסט</span>';

      expect(addNumberedNoteMarkerLinks(line, lineIndex: 0), line);
    });

    test('מתעלם ממספרים ללא סוגריים ומרצפים ארוכים', () {
      const line = 'שנת (1990) וגם 9 בלבד';

      expect(addNumberedNoteMarkerLinks(line, lineIndex: 0), line);
    });
  });

  group('numberedNoteLinks', () {
    test('מסנן רק מפרשים שכותרתם "הערות"', () {
      final links = [
        _link('רש"י'),
        _link('הערות על חברותא על זבחים'),
        _link('הערות על חברותא על זבחים', index2: 2, type: 'LINKER'),
      ];

      final result = numberedNoteLinks(links);

      expect(result, hasLength(1));
      expect(result.single.path2, 'הערות על חברותא על זבחים');
    });
  });

  group('noteMarkerLineFromUrl', () {
    test('מחזיר את מספר השורה', () {
      expect(
        noteMarkerLineFromUrl('otzaria://note-marker?line=5963&num=9'),
        5963,
      );
    });

    test('מחזיר null לכתובת אחרת', () {
      expect(noteMarkerLineFromUrl('otzaria://note?line=5'), isNull);
    });
  });
}
