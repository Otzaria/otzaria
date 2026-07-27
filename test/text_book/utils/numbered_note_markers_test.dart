import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
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

/// ספק שמחזיר תוכן לפי (path2, index2), ומאפשר לעכב תשובות כדי לבדוק מקביליות.
class _FakeContentProvider implements LibraryProvider {
  _FakeContentProvider(this.contents, {this.gate});

  final Map<String, String> contents;

  /// כשקיים — כל קריאה ממתינה לו, וכך אפשר לבדוק כמה קריאות התחילו במקביל.
  final Completer<void>? gate;

  final List<String> startedKeys = [];

  @override
  Future<String> getLinkContent(Link link) async {
    final key = '${link.path2}:${link.index2}';
    startedKeys.add(key);
    if (gate != null) await gate!.future;
    final content = contents[key];
    if (content == null) throw StateError('אין תוכן ל-$key');
    return content;
  }

  @override
  String get displayName => 'Fake';
  @override
  bool get isInitialized => true;
  @override
  int get priority => 0;
  @override
  String get providerId => 'fake';
  @override
  String get sourceIndicator => 'T';
  @override
  Future<void> initialize() async {}
  @override
  Future<Set<String>> getAvailableBookTitles() async => const {};
  @override
  Future<bool> hasBook(String title, int categoryId, String fileType) async =>
      false;
  @override
  Future<String?> getBookText(
    String title,
    int categoryId,
    String fileType, {
    bool preferUserBooks = false,
  }) async => null;
  @override
  Future<List<TocEntry>?> getBookToc(
    String title,
    int categoryId,
    String fileType, {
    bool preferUserBooks = false,
  }) async => const [];
  @override
  Future<Library> buildLibraryCatalog(
    Map<String, Map<String, dynamic>> metadata,
    String rootPath,
  ) => throw UnimplementedError();
  @override
  Future<List<Link>> getAllLinksForBook(
    String title,
    int categoryId,
    String fileType,
  ) async => const [];
  @override
  Future<Map<String, List<Book>>> loadBooks(
    Map<String, Map<String, dynamic>> metadata,
  ) async => const {};
}

_FakeContentProvider _seedProvider(
  Map<String, String> contents, {
  Completer<void>? gate,
}) {
  final provider = _FakeContentProvider(contents, gate: gate);
  LibraryProviderManager.instance.seedMappingsForTesting(
    mapping: const {},
    providers: [provider],
  );
  return provider;
}

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

    test('לא עוטף סמן שכבר נמצא בתוך קישור', () {
      const line = 'טקסט <a href="otzaria://link?ref=3_0">(9)</a> המשך';

      expect(addNumberedNoteMarkerLinks(line, lineIndex: 7), line);
    });

    test('עוטף סמן שאחרי סגירת הקישור, ולא את זה שבתוכו', () {
      const line = '<a href="x">(9)</a> ואחר-כך (10)';

      final result = addNumberedNoteMarkerLinks(line, lineIndex: 7);

      expect(result, startsWith('<a href="x">(9)</a>'));
      expect(
        result,
        contains('href="otzaria://note-marker?line=7&num=10">(10)</a>'),
      );
    });

    test('קישור עם תגים פנימיים מגן על כל הסמנים שבתוכו', () {
      const line = '<a href="x">(9) <b>וגם (10)</b></a>';

      expect(addNumberedNoteMarkerLinks(line, lineIndex: 7), line);
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

  group('numberedNoteLinkFromUrl', () {
    tearDown(() => LibraryProviderManager.instance.resetForTesting());

    test('מחזיר את ההערה שנפתחת באותו מספר', () async {
      _seedProvider({
        'הערות א:1': '(8) ההערה השמינית',
        'הערות א:2': '(9) ההערה התשיעית',
        'הערות א:3': '(10) ההערה העשירית',
      });
      final links = [
        _link('הערות א', index2: 1),
        _link('הערות א', index2: 2),
        _link('הערות א', index2: 3),
      ];

      final link = await numberedNoteLinkFromUrl(
        'otzaria://note-marker?line=5&num=9',
        links,
      );

      expect(link?.index2, 2);
    });

    test('מזהה סמן פתיחה עטוף ב-HTML וברווחים', () async {
      _seedProvider({'הערות ב:1': '<b> ( 9 ) </b> ההערה'});
      final links = [_link('הערות ב', index2: 1)];

      final link = await numberedNoteLinkFromUrl(
        'otzaria://note-marker?line=5&num=9',
        links,
      );

      expect(link?.path2, 'הערות ב');
    });

    test('מחזיר null כשאין הערה שנפתחת במספר המבוקש', () async {
      _seedProvider({'הערות ג:1': '(8) ההערה השמינית'});
      final links = [_link('הערות ג', index2: 1)];

      final link = await numberedNoteLinkFromUrl(
        'otzaria://note-marker?line=5&num=9',
        links,
      );

      expect(link, isNull);
    });

    test('מועמד שטעינתו נכשלת אינו מונע התאמה למועמד שאחריו', () async {
      _seedProvider({'הערות ד:2': '(9) ההערה התשיעית'});
      final links = [
        _link('הערות ד', index2: 1), // אין לו תוכן — הטעינה נכשלת
        _link('הערות ד', index2: 2),
      ];

      final link = await numberedNoteLinkFromUrl(
        'otzaria://note-marker?line=5&num=9',
        links,
      );

      expect(link?.index2, 2);
    });

    test('טוען את כל המועמדים במקביל ולא בזה-אחר-זה', () async {
      final gate = Completer<void>();
      final provider = _seedProvider({
        'הערות ה:1': '(7) ראשונה',
        'הערות ה:2': '(8) שנייה',
        'הערות ה:3': '(9) שלישית',
      }, gate: gate);
      final links = [
        _link('הערות ה', index2: 1),
        _link('הערות ה', index2: 2),
        _link('הערות ה', index2: 3),
      ];

      final pending = numberedNoteLinkFromUrl(
        'otzaria://note-marker?line=5&num=9',
        links,
      );
      // אף טעינה לא הושלמה עדיין — בסריקה סדרתית רק הראשונה הייתה מתחילה.
      await Future<void>.delayed(Duration.zero);
      expect(provider.startedKeys, hasLength(3));

      gate.complete();
      expect((await pending)?.index2, 3);
    });

    test('מתעלם מכתובת שאינה סמן-מספר ואינו קורא כלל לספק', () async {
      final provider = _seedProvider({'הערות ו:1': '(9) ההערה'});
      final links = [_link('הערות ו', index2: 1)];

      expect(
        await numberedNoteLinkFromUrl('otzaria://anchor?ref=0_0', links),
        isNull,
      );
      expect(
        await numberedNoteLinkFromUrl('otzaria://note-marker', links),
        isNull,
      );
      expect(provider.startedKeys, isEmpty);
    });

    test('מתעלם ממפרש שאינו ספר "הערות"', () async {
      final provider = _seedProvider({'רש"י:1': '(9) לא הערה'});
      final links = [_link('רש"י', index2: 1)];

      final link = await numberedNoteLinkFromUrl(
        'otzaria://note-marker?line=5&num=9',
        links,
      );

      expect(link, isNull);
      expect(provider.startedKeys, isEmpty);
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
