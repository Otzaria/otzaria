import 'dart:convert';

import 'package:characters/characters.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/plugin_highlight.dart';
import 'package:otzaria/plugins/models/plugin_reader_selection.dart';
import 'package:otzaria/plugins/models/text_source_map.dart';
import 'package:otzaria/plugins/services/plugin_highlight_renderer.dart';
import 'package:otzaria/plugins/services/text_source_map_service.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';

/// המימוש הלינארי שקדם ל-binary search — קו הבסיס לבדיקת השקילות.
int _linearRenderedToSource(PluginTextSourceMap map, int boundary) {
  for (final segment in map.mappings) {
    final renderedStart = segment.renderedStart.grapheme;
    final renderedEnd = segment.renderedEnd.grapheme;
    if (boundary < renderedStart || boundary > renderedEnd) continue;
    final sourceStart = segment.sourceStart.grapheme;
    final sourceEnd = segment.sourceEnd.grapheme;
    final renderedLength = renderedEnd - renderedStart;
    final sourceLength = sourceEnd - sourceStart;
    if (renderedLength == 0) return sourceEnd;
    if (segment.kind == PluginTextSourceMapKind.identity) {
      return sourceStart + (boundary - renderedStart);
    }
    final progress = (boundary - renderedStart) / renderedLength;
    return sourceStart + (sourceLength * progress).round();
  }
  return map.sourceText.characters.length;
}

int _linearSourceToRendered(PluginTextSourceMap map, int boundary) {
  for (final segment in map.mappings) {
    final sourceStart = segment.sourceStart.grapheme;
    final sourceEnd = segment.sourceEnd.grapheme;
    if (boundary < sourceStart || boundary > sourceEnd) continue;
    final renderedStart = segment.renderedStart.grapheme;
    final renderedEnd = segment.renderedEnd.grapheme;
    final sourceLength = sourceEnd - sourceStart;
    final renderedLength = renderedEnd - renderedStart;
    if (sourceLength == 0) return renderedEnd;
    if (segment.kind == PluginTextSourceMapKind.identity) {
      return renderedStart + (boundary - sourceStart);
    }
    final progress = (boundary - sourceStart) / sourceLength;
    return renderedStart + (renderedLength * progress).round();
  }
  return map.renderedText.characters.length;
}

void main() {
  const service = TextSourceMapService();

  group('אורכי גרפמות מוטמנים', () {
    test('האורכים על המפה זהים לסריקה מלאה', () {
      final map = service.build(
        bookId: 'book',
        sectionIndex: 0,
        rawText: 'אָב 😀 גד',
        settings: const RenderSettings(
          removeNikud: true,
          formatParentheses: false,
        ),
      );

      expect(map.sourceGraphemeLength, map.sourceText.characters.length);
      expect(map.renderedGraphemeLength, map.renderedText.characters.length);
    });

    test('תרגום גבול אינו תלוי באורך הטקסט', () {
      final long = List.filled(20000, 'שלום עולם ').join();
      final map = service.buildFromProcessedHtml(
        bookId: 'book',
        sectionIndex: 0,
        rawText: long,
        processedHtml: long,
      );

      // קו הבסיס: העלות שהקוד הישן שילם בכל תרגום בודד.
      final scanWatch = Stopwatch()..start();
      var scanned = 0;
      for (var index = 0; index < 200; index++) {
        scanned += map.renderedText.characters.length;
      }
      scanWatch.stop();
      expect(scanned, greaterThan(0));

      final translateWatch = Stopwatch()..start();
      var total = 0;
      for (var index = 0; index < 200; index++) {
        total += service.sourceBoundaryToRendered(map, index);
        total += service.renderedBoundaryToSource(map, index);
      }
      translateWatch.stop();
      expect(total, greaterThan(0));

      // ignore: avoid_print
      print(
        'סריקה בלבד: ${scanWatch.elapsedMicroseconds}µs, '
        'תרגום מלא: ${translateWatch.elapsedMicroseconds}µs',
      );
      expect(
        translateWatch.elapsedMicroseconds * 10,
        lessThan(scanWatch.elapsedMicroseconds),
      );
    });
  });

  group('binary search על ה-segments', () {
    test('ה-segments ממוינים ורציפים בשני המרחבים', () {
      final map = service.build(
        bookId: 'book',
        sectionIndex: 0,
        rawText: 'בְּרֵאשִׁית בָּרָא אֱלֹהִים אֵת הַשָּׁמַיִם וְאֵת הָאָרֶץ',
        settings: const RenderSettings(removeNikud: true),
      );

      expect(map.mappings.length, greaterThan(2));
      for (var index = 1; index < map.mappings.length; index++) {
        final previous = map.mappings[index - 1];
        final current = map.mappings[index];
        expect(current.sourceStart.grapheme, previous.sourceEnd.grapheme);
        expect(current.renderedStart.grapheme, previous.renderedEnd.grapheme);
      }
    });

    test('שקילות מוחלטת לסריקה הלינארית בכל גבול', () {
      final maps = [
        service.build(
          bookId: 'book',
          sectionIndex: 0,
          rawText: 'בְּרֵאשִׁ֖ית בָּרָ֣א אֱלֹהִ֑ים וַיֹּ֥אמֶר יהוה',
          settings: const RenderSettings(
            removeNikud: true,
            removeTeamim: true,
            replaceHolyNames: true,
          ),
        ),
        service.buildFromProcessedHtml(
          bookId: 'book',
          sectionIndex: 1,
          rawText: 'שלום עולם גדול',
          processedHtml: 'עולם',
        ),
        service.buildFromProcessedHtml(
          bookId: 'book',
          sectionIndex: 2,
          rawText: 'אבג',
          processedHtml: 'אבג נוסף',
        ),
      ];

      for (final map in maps) {
        for (
          var boundary = -2;
          boundary <= map.renderedGraphemeLength + 2;
          boundary++
        ) {
          final clamped = boundary.clamp(0, map.renderedGraphemeLength);
          expect(
            service.renderedBoundaryToSource(map, boundary),
            _linearRenderedToSource(map, clamped),
            reason: 'rendered→source בגבול $boundary',
          );
        }
        for (
          var boundary = -2;
          boundary <= map.sourceGraphemeLength + 2;
          boundary++
        ) {
          final clamped = boundary.clamp(0, map.sourceGraphemeLength);
          expect(
            service.sourceBoundaryToRendered(map, boundary),
            _linearSourceToRendered(map, clamped),
            reason: 'source→rendered בגבול $boundary',
          );
        }
      }
    });
  });

  group('עלות ההיסנכרון מעדיפה רצף רצוף', () {
    test('מילה שהוסרה אינה מסונכרנת לפי גרפמה בודדת מזדמנת', () {
      // המקור פותח במילה שאינה מוצגת. ההתאמות הקרובות ("ל" ו-"ו") הן בנות
      // גרפמה אחת, והיישור האמיתי הוא הרצף "עולם" שרחוק מהן.
      final map = service.buildFromProcessedHtml(
        bookId: 'book',
        sectionIndex: 0,
        rawText: 'שלום עולם',
        processedHtml: 'עולם',
      );

      final identity = map.mappings.where(
        (segment) => segment.kind == PluginTextSourceMapKind.identity,
      );
      expect(identity, hasLength(1));
      expect(identity.single.sourceStart.grapheme, 5);
      expect(identity.single.sourceEnd.grapheme, 9);
      expect(identity.single.renderedStart.grapheme, 0);
      expect(identity.single.renderedEnd.grapheme, 4);
      for (var boundary = 0; boundary <= 4; boundary++) {
        expect(service.renderedBoundaryToSource(map, boundary), 5 + boundary);
      }
    });

    test('הסרת ניקוד עדיין מסונכרנת מקומית ולא לרצף רחוק', () {
      final map = service.build(
        bookId: 'book',
        sectionIndex: 0,
        rawText: 'בְּרֵאשִׁית ברא עולם',
        settings: const RenderSettings(removeNikud: true),
      );

      // "ברא" של המקור אינו נגרר להתחלת המילה המוצגת "בראשית".
      expect(service.sourceBoundaryToRendered(map, 7), 7);
      expect(service.renderedBoundaryToSource(map, 7), 7);
    });
  });

  group('מטמון המפה', () {
    setUp(TextSourceMapService.clearCacheForTesting);

    test('קלט זהה מוגש מהמטמון, וקלט שונה בונה מפה חדשה', () {
      final first = service.cachedFromProcessedHtml(
        bookId: 'book',
        sectionIndex: 0,
        rawText: 'שלום עולם',
        processedHtml: 'שלום עולם',
      );
      final again = service.cachedFromProcessedHtml(
        bookId: 'book',
        sectionIndex: 0,
        rawText: 'שלום עולם',
        processedHtml: 'שלום עולם',
      );
      expect(again, same(first));
      expect(TextSourceMapService.cachedMapCount, 1);

      final other = service.cachedFromProcessedHtml(
        bookId: 'book',
        sectionIndex: 0,
        rawText: 'שלום עולם',
        processedHtml: 'שלום',
      );
      expect(other, isNot(same(first)));
      expect(other.renderedText, 'שלום');
      expect(TextSourceMapService.cachedMapCount, 2);
    });

    test('שינוי הגדרות תצוגה אינו מוגש מהמטמון בטווח מיושן', () {
      const renderer = PluginHighlightRenderer();
      const context = PluginAnchorContext(
        raw: '',
        normalized: '',
        maxGraphemes: 30,
        actualGraphemes: 0,
        truncatedAtBoundary: true,
      );
      final highlight = PluginHighlight(
        highlightId: 'h1',
        ownerPluginId: 'plugin',
        bookId: 'book',
        sectionIndex: 0,
        range: const PluginTextRangeAnchor(
          layer: 'source',
          exactText: 'עולם',
          start: PluginTextOffset(grapheme: 5, codePoint: 5, utf16: 5),
          end: PluginTextOffset(grapheme: 9, codePoint: 9, utf16: 9),
          beforeText: context,
          afterText: context,
          occurrenceIndexInSection: 0,
          occurrenceCountInSection: 1,
        ),
        style: const PluginHighlightStyle(backgroundColor: '#FFE066'),
        createdAt: DateTime.utc(2026, 7, 14),
        updatedAt: DateTime.utc(2026, 7, 14),
      );

      List<PluginHighlightRenderedRange> ranges(String processedHtml) =>
          renderer.resolveRenderedRanges(
            bookId: 'book',
            sectionIndex: 0,
            rawText: 'שלום עולם',
            processedHtml: processedHtml,
            highlights: [highlight],
          );

      expect(ranges('שלום עולם').single.start, 5);
      expect(ranges('עולם').single.start, 0);
      expect(ranges('שלום עולם').single.start, 5);
    });

    test('המטמון חסום ואינו גדל בלי הגבלה', () {
      final chunk = List.filled(30000, 'א').join();
      for (var index = 0; index < 60; index++) {
        service.cachedFromProcessedHtml(
          bookId: 'book',
          sectionIndex: index,
          rawText: '$chunk$index',
          processedHtml: '$chunk$index',
        );
      }
      expect(TextSourceMapService.cachedMapCount, lessThan(60));
    });
  });

  test('מנוע המפה אינו משנה את hash הטקסטים', () {
    // עוגני ההדגשות נשמרים בשכבת source ומאומתים מול ה-hash; אם הוא נגזר
    // ממשהו מלבד הטקסט עצמו, שינוי במנוע יפסול הדגשות שמורות.
    final map = service.buildFromProcessedHtml(
      bookId: 'book',
      sectionIndex: 0,
      rawText: 'שלום עולם',
      processedHtml: 'עולם',
    );
    final identical = service.buildFromProcessedHtml(
      bookId: 'other-book',
      sectionIndex: 7,
      rawText: 'שלום עולם',
      processedHtml: 'עולם גדול',
    );

    expect(
      map.sourceTextHash,
      sha256.convert(utf8.encode('שלום עולם')).toString(),
    );
    expect(
      map.renderedTextHash,
      sha256.convert(utf8.encode('עולם')).toString(),
    );
    // אותו טקסט מקור — אותו hash, גם כשהתצוגה, המזהה והמיפוי שונים.
    expect(identical.sourceTextHash, map.sourceTextHash);
    expect(identical.renderedTextHash, isNot(map.renderedTextHash));
  });
}
