import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/reader_selection_service.dart';
import 'package:otzaria/plugins/services/text_source_map_service.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' show HolyNameStyle;

void main() {
  const service = ReaderSelectionService();

  test('locates repeated text only inside the requested rendered section', () {
    final range = service.locateRenderedRange(
      renderedText: 'פתיחה מילה בתוך המקטע',
      selectedText: 'מילה',
    );

    expect(range, isNotNull);
    expect(range!.start, 6);
    expect(range.end, 10);
  });

  test('pointer hint selects the second occurrence in the same section', () {
    final range = service.locateRenderedRange(
      renderedText: 'מילה באמצע מילה',
      selectedText: 'מילה',
      startHint: 13,
    );

    expect(range, isNotNull);
    expect(range!.start, 11);
    expect(range.end, 15);
  });

  test('range lookup handles missing matches and hints outside the text', () {
    const text = 'אב אב אב';
    expect(
      service.locateRenderedRange(renderedText: text, selectedText: ''),
      isNull,
    );
    expect(
      service.locateRenderedRange(renderedText: text, selectedText: 'גד'),
      isNull,
    );
    for (final entry in [(null, 0), (-10, 0), (3, 3), (100, 6)]) {
      final range = service.locateRenderedRange(
        renderedText: text,
        selectedText: 'אב',
        startHint: entry.$1,
      );
      expect(range, (start: entry.$2, end: entry.$2 + 2));
    }
  });

  test('range lookup preserves overlapping matches', () {
    final range = service.locateRenderedRange(
      renderedText: 'אאאא',
      selectedText: 'אא',
      startHint: 1,
    );
    expect(range, (start: 1, end: 3));
  });

  test('equal-distance hints consistently choose the earlier occurrence', () {
    final range = service.locateRenderedRange(
      renderedText: List.filled(80, 'א ').join(),
      selectedText: 'א',
      startHint: 79,
    );
    expect(range, (start: 78, end: 79));
  });

  test('range hints use UTF-16 positions around emoji and nikud', () {
    final range = service.locateRenderedRange(
      renderedText: '🙂אָ|🙂אָ',
      selectedText: '🙂אָ',
      startHint: 4,
    );
    expect(range, (start: 5, end: 9));
  });

  test('normalized equal-distance hints prefer the earlier source range', () {
    final selection = service.buildFromRenderedSelection(
      bookId: 'book',
      bookTitle: 'ספר',
      sectionIndex: 0,
      rawText: 'אב  גד || אב\tגד',
      settings: const RenderSettings(
        replaceHolyNames: false,
        formatParentheses: false,
      ),
      selectedText: 'אב גד',
      startHint: 5,
    );
    expect(selection?.sourceRange.start.utf16, 0);
    expect(selection?.sourceRange.end.utf16, 6);
    expect(selection?.sourceSelectedText, 'אב  גד');
  });

  test('normalized selection chooses the nearest original-text occurrence', () {
    const settings = RenderSettings(
      replaceHolyNames: false,
      formatParentheses: false,
    );
    const rawText = 'אב  גד | אב\tגד';
    final selection = service.buildFromRenderedSelection(
      bookId: 'book',
      bookTitle: 'ספר',
      sectionIndex: 0,
      rawText: rawText,
      settings: settings,
      selectedText: 'אב גד',
      startHint: 100,
    );
    expect(selection, isNotNull);
    expect(selection!.sourceRange.start.utf16, 9);
    expect(selection.sourceRange.end.utf16, 14);
    expect(selection.sourceSelectedText, 'אב\tגד');
  });

  test('maps a displayed holy-name replacement back to the source', () {
    const settings = RenderSettings(
      replaceHolyNames: true,
      formatParentheses: false,
    );
    const rawText = 'לפני יהוה אחרי';
    final map = const TextSourceMapService().build(
      bookId: 'book',
      sectionIndex: 8,
      rawText: rawText,
      settings: settings,
    );
    final displayedName = map.renderedText.substring(
      'לפני '.length,
      map.renderedText.length - ' אחרי'.length,
    );
    final range = service.locateRenderedRange(
      renderedText: map.renderedText,
      selectedText: displayedName,
    );
    final resolvedRange = range!;
    final selection = service.build(
      bookId: 'book',
      bookTitle: 'ספר',
      sectionIndex: 8,
      rawText: rawText,
      settings: settings,
      renderedStartUtf16: resolvedRange.start,
      renderedEndUtf16: resolvedRange.end,
    );

    expect(displayedName, isNot('יהוה'));
    expect(selection, isNotNull);
    expect(selection!.sourceSelectedText, 'יהוה');
    expect(selection.sourceRange.start.utf16, 'לפני '.length);
  });

  test(
    'maps a shortened holy-name display and partial selection to source',
    () {
      const settings = RenderSettings(
        replaceHolyNames: true,
        holyNameStyle: HolyNameStyle.hehApostrophe,
        formatParentheses: false,
      );
      const rawText = 'לפני יהוה אחרי';
      final map = const TextSourceMapService().build(
        bookId: 'book',
        sectionIndex: 8,
        rawText: rawText,
        settings: settings,
      );

      final whole = service.buildFromRenderedSelection(
        bookId: 'book',
        bookTitle: 'ספר',
        sectionIndex: 8,
        rawText: rawText,
        settings: settings,
        selectedText: "ה'",
      );
      final partial = service.buildFromRenderedSelection(
        bookId: 'book',
        bookTitle: 'ספר',
        sectionIndex: 8,
        rawText: rawText,
        settings: settings,
        selectedText: 'ה',
      );

      expect(map.renderedText, contains("ה'"));
      expect(whole?.sourceSelectedText, 'יהוה');
      expect(whole?.sourceRange.start.utf16, 'לפני '.length);
      expect(partial?.sourceSelectedText, 'יהוה');
      expect(partial?.sourceRange.start.utf16, 'לפני '.length);
    },
  );

  test('ממפה קיצור חוזר לשם המקור המתאים לפי מיקום הבחירה', () {
    const rawText = 'יהוה יהוה יהוה יהוה יהוה';
    const settings = RenderSettings(
      replaceHolyNames: true,
      holyNameStyle: HolyNameStyle.hehApostrophe,
      formatParentheses: false,
    );
    final map = const TextSourceMapService().build(
      bookId: 'book',
      sectionIndex: 0,
      rawText: rawText,
      settings: settings,
    );
    final selection = service.buildFromRenderedSelection(
      bookId: 'book',
      bookTitle: 'ספר',
      sectionIndex: 0,
      rawText: rawText,
      settings: settings,
      selectedText: "ה'",
      startHint: map.renderedText.lastIndexOf("ה'"),
    );

    expect(selection?.sourceSelectedText, 'יהוה');
    expect(
      selection?.sourceRange.start.utf16,
      map.sourceText.lastIndexOf('יהוה'),
    );
  });

  test('בחירה חלקית בהחלפה שומרת גבולות פנימיים כשהאורך לא השתנה', () {
    const rawText = 'לפני יהוה אחרי';
    const settings = RenderSettings(
      replaceHolyNames: true,
      holyNameStyle: HolyNameStyle.kufKuf,
      formatParentheses: false,
    );
    final selection = service.buildFromRenderedSelection(
      bookId: 'book',
      bookTitle: 'ספר',
      sectionIndex: 0,
      rawText: rawText,
      settings: settings,
      selectedText: 'קוק',
    );

    expect(selection?.sourceSelectedText, 'הוה');
    expect(selection?.sourceRange.start.utf16, rawText.indexOf('יהוה') + 1);
  });

  test('מיפוי בחירה לאחר שם בתוך תגיות HTML נשאר מדויק', () {
    const rawText = 'אבג<b>יהוה</b> יהוה יהוה יהוה יהוה';
    const settings = RenderSettings(
      replaceHolyNames: true,
      holyNameStyle: HolyNameStyle.hehApostrophe,
      formatParentheses: false,
    );
    final map = const TextSourceMapService().build(
      bookId: 'book',
      sectionIndex: 0,
      rawText: rawText,
      settings: settings,
    );
    final selection = service.buildFromRenderedSelection(
      bookId: 'book',
      bookTitle: 'ספר',
      sectionIndex: 0,
      rawText: rawText,
      settings: settings,
      selectedText: "ה'",
      startHint: map.renderedText.lastIndexOf("ה'"),
    );

    expect(selection?.sourceSelectedText, 'יהוה');
    expect(
      selection?.sourceRange.start.utf16,
      map.sourceText.lastIndexOf('יהוה'),
    );
  });

  test('בחירה רגילה אחרי שם בתוך תגיות אינה ממופה ביחס שגוי', () {
    const rawText = 'אבג<b>יהוה</b> יהוה יהוה יהוה יהוה מילה עוד סוף';
    const settings = RenderSettings(
      replaceHolyNames: true,
      holyNameStyle: HolyNameStyle.hehApostrophe,
      formatParentheses: false,
    );
    final map = const TextSourceMapService().build(
      bookId: 'book',
      sectionIndex: 0,
      rawText: rawText,
      settings: settings,
    );
    final selection = service.buildFromRenderedSelection(
      bookId: 'book',
      bookTitle: 'ספר',
      sectionIndex: 0,
      rawText: rawText,
      settings: settings,
      selectedText: 'מילה',
      startHint: map.renderedText.lastIndexOf('מילה'),
    );

    expect(selection?.sourceSelectedText, 'מילה');
    expect(selection?.sourceRange.start.utf16, map.sourceText.indexOf('מילה'));
  });

  test('שם במאפיין HTML אינו מסיט את מיפוי הטקסט הגלוי שאחריו', () {
    const rawText = '<b data="יהוה">טקסט</b> יהוה יהוה יהוה יהוה מילה';
    const settings = RenderSettings(
      replaceHolyNames: true,
      holyNameStyle: HolyNameStyle.hehApostrophe,
      formatParentheses: false,
    );
    final map = const TextSourceMapService().build(
      bookId: 'book',
      sectionIndex: 0,
      rawText: rawText,
      settings: settings,
    );
    final selection = service.buildFromRenderedSelection(
      bookId: 'book',
      bookTitle: 'ספר',
      sectionIndex: 0,
      rawText: rawText,
      settings: settings,
      selectedText: 'מילה',
      startHint: map.renderedText.lastIndexOf('מילה'),
    );

    expect(selection?.sourceSelectedText, 'מילה');
    expect(selection?.sourceRange.start.utf16, map.sourceText.indexOf('מילה'));
  });

  test(
    'maps a selection across HTML entities, breaks, and repeated spaces',
    () {
      const settings = RenderSettings(
        replaceHolyNames: true,
        holyNameStyle: HolyNameStyle.kufKuf,
        formatParentheses: false,
      );
      const rawText = 'לפני&nbsp;&nbsp;<b>יהוה</b><br>אחרי';
      final selection = service.buildFromRenderedSelection(
        bookId: 'book',
        bookTitle: 'ספר',
        sectionIndex: 1,
        rawText: rawText,
        settings: settings,
        selectedText: 'יקוק אחרי',
        startHint: 'לפני יקוק אחרי'.indexOf('יקוק'),
      );

      expect(selection, isNotNull);
      expect(selection!.sourceSelectedText, 'יהוה אחרי');
      expect(selection.sourceRange.start.utf16, greaterThan(0));
    },
  );

  test('uses the visible start hint after collapsing source whitespace', () {
    const settings = RenderSettings(
      replaceHolyNames: true,
      formatParentheses: false,
    );
    const rawText = 'מילה&nbsp;&nbsp;יהוה אחרי <b>מילה</b>';
    final selection = service.buildFromRenderedSelection(
      bookId: 'book',
      bookTitle: 'ספר',
      sectionIndex: 2,
      rawText: rawText,
      settings: settings,
      selectedText: 'מילה',
      startHint: 'מילה יקוק אחרי מילה'.lastIndexOf('מילה'),
    );

    expect(selection?.sourceSelectedText, 'מילה');
    expect(
      selection?.sourceRange.start.utf16,
      'מילה\u00a0\u00a0יהוה אחרי '.length,
    );
  });

  test('בונה עוגן source חד-משמעי למופע השני של אותה מילה', () {
    final selection = service.build(
      bookId: 'book',
      bookTitle: 'ספר',
      sectionIndex: 4,
      rawText: 'אני אומר שאני יודע',
      settings: const RenderSettings(formatParentheses: false),
      renderedStartUtf16: 10,
      renderedEndUtf16: 13,
      currentRef: 'פרק א',
      createdAt: DateTime.utc(2026, 7, 14),
    );

    expect(selection, isNotNull);
    expect(selection!.sourceSelectedText, 'אני');
    expect(selection.sourceRange.start.grapheme, 10);
    expect(selection.sourceRange.occurrenceIndexInSection, 1);
    expect(selection.sourceRange.occurrenceCountInSection, 2);
    expect(selection.sourceRange.beforeText.raw, 'אני אומר ש');
  });

  test('מתרגם בחירה ללא ניקוד בחזרה לטווח המקור המנוקד', () {
    final selection = service.build(
      bookId: 'book',
      bookTitle: 'ספר',
      sectionIndex: 0,
      rawText: 'אָב אמר',
      settings: const RenderSettings(
        removeNikud: true,
        removeTeamim: false,
        formatParentheses: false,
      ),
      renderedStartUtf16: 0,
      renderedEndUtf16: 2,
    );

    expect(selection, isNotNull);
    expect(selection!.renderedSelectedText, 'אב');
    expect(selection.sourceSelectedText, 'אָב');
    expect(selection.sourceRange.start.grapheme, 0);
    expect(selection.sourceRange.end.grapheme, 2);
  });

  test('דוחה offset שנופל באמצע surrogate pair', () {
    final selection = service.build(
      bookId: 'book',
      bookTitle: 'ספר',
      sectionIndex: 0,
      rawText: 'א😀ב',
      settings: const RenderSettings(formatParentheses: false),
      renderedStartUtf16: 1,
      renderedEndUtf16: 2,
    );

    expect(selection, isNull);
  });

  test('בונה עוגנים באצווה עם מופעים ואינדקסי מילים זהים', () {
    final anchors = service.buildRangeAnchors(
      text: '  אב אבא אב ',
      ranges: const [
        (startGrapheme: 2, endGrapheme: 4),
        (startGrapheme: 5, endGrapheme: 8),
        (startGrapheme: 9, endGrapheme: 11),
        (startGrapheme: 12, endGrapheme: 12),
      ],
      layer: 'source',
    );

    expect(anchors, hasLength(4));
    expect(anchors[0]!.occurrenceIndexInSection, 0);
    expect(anchors[0]!.occurrenceCountInSection, 3);
    expect(anchors[0]!.startWordIndex, 0);
    expect(anchors[1]!.occurrenceCountInSection, 1);
    expect(anchors[1]!.startWordIndex, 1);
    expect(anchors[2]!.occurrenceIndexInSection, 2);
    expect(anchors[2]!.startWordIndex, 2);
    expect(anchors[3], isNull);
  });

  test('anchors long overlapping ranges in repeated text', () {
    final text = List.filled(8192, 'א').join();
    final query = List.filled(512, 'א').join();
    final anchors = service.buildRangeAnchors(
      text: text,
      ranges: const [
        (startGrapheme: 0, endGrapheme: 512),
        (startGrapheme: 17, endGrapheme: 529),
        (startGrapheme: 7000, endGrapheme: 7512),
      ],
      layer: 'source',
    );

    expect(anchors.map((anchor) => anchor!.exactText), [query, query, query]);
    expect(anchors.map((anchor) => anchor!.occurrenceIndexInSection), [
      0,
      17,
      7000,
    ]);
    expect(anchors.map((anchor) => anchor!.occurrenceCountInSection), [
      7681,
      7681,
      7681,
    ]);
  });

  test('overlapping batch anchors preserve grapheme and Unicode offsets', () {
    final anchors = service.buildRangeAnchors(
      text: '🙂אָאָאָ🙂אָאָ',
      ranges: const [
        (startGrapheme: 1, endGrapheme: 3),
        (startGrapheme: 2, endGrapheme: 4),
        (startGrapheme: 5, endGrapheme: 7),
      ],
      layer: 'rendered',
      renderedTextHash: 'hash',
    );

    expect(anchors.map((anchor) => anchor!.exactText), [
      'אָאָ',
      'אָאָ',
      'אָאָ',
    ]);
    expect(anchors.map((anchor) => anchor!.occurrenceIndexInSection), [
      0,
      1,
      2,
    ]);
    expect(anchors.map((anchor) => anchor!.occurrenceCountInSection), [
      3,
      3,
      3,
    ]);
    expect(anchors.map((anchor) => anchor!.start.codePoint), [1, 3, 8]);
    expect(anchors.map((anchor) => anchor!.end.codePoint), [5, 7, 12]);
    expect(anchors.map((anchor) => anchor!.start.utf16), [2, 4, 10]);
    expect(anchors.map((anchor) => anchor!.end.utf16), [6, 8, 14]);
    expect(anchors.last!.renderedTextHash, 'hash');
  });

  group('buildMultiSectionPayload', () {
    const settings = RenderSettings(formatParentheses: false);

    test('בונה עוגן לכל פסקה בבחירה חוצת-פסקאות', () {
      final payload = service.buildMultiSectionPayload(
        bookId: 'book',
        bookTitle: 'ספר',
        firstSectionIndex: 7,
        rawTexts: const ['שלום עולם', 'ברוך הבא'],
        lineRanges: const [
          (line: 0, start: 5, end: 9),
          (line: 1, start: 0, end: 4),
        ],
        settings: settings,
        selectedText: 'עולם\nברוך',
        currentRef: 'פרק א',
      );

      expect(payload['currentIndex'], 7);
      expect(payload['sourceRange'], isNull);
      final sections = payload['sections'] as List;
      expect(sections, hasLength(2));
      final first = sections[0] as Map<String, dynamic>;
      final second = sections[1] as Map<String, dynamic>;
      expect(first['sectionIndex'], 7);
      expect(first['currentIndex'], 7);
      expect((first['sourceRange'] as Map)['exactText'], 'עולם');
      expect(second['sectionIndex'], 8);
      expect((second['sourceRange'] as Map)['exactText'], 'ברוך');
    });

    test('פסקה יחידה מתמזגת לרמה העליונה כמו בחירה רגילה', () {
      final payload = service.buildMultiSectionPayload(
        bookId: 'book',
        bookTitle: 'ספר',
        firstSectionIndex: 3,
        rawTexts: const ['שלום עולם'],
        lineRanges: const [(line: 0, start: 5, end: 9)],
        settings: settings,
        selectedText: 'עולם',
      );

      expect(payload.containsKey('sections'), isFalse);
      expect(payload['sectionIndex'], 3);
      expect((payload['sourceRange'] as Map)['exactText'], 'עולם');
    });

    test('ללא טווחים — payload בסיסי בלי sections', () {
      final payload = service.buildMultiSectionPayload(
        bookId: 'book',
        bookTitle: 'ספר',
        firstSectionIndex: 0,
        rawTexts: const ['שלום עולם'],
        lineRanges: const [],
        settings: settings,
        selectedText: 'טקסט',
      );

      expect(payload.containsKey('sections'), isFalse);
      expect(payload.containsKey('sourceRange'), isFalse);
      expect(payload['text'], 'טקסט');
    });
  });
}
