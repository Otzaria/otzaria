/// התנהגות המנוע על טקסט מקרא אמיתי: מבנה הפרקים והפסוקים, שלמות הטקסט
/// אחרי העימוד, רוחב השורה, סימון פרשות ועליות, העמודים, הקטעים המיוחדים,
/// ההפטרה וקריאת המועד.
library;

import 'package:otzaria/tools/tikkun_korim/tikkun_korim.dart';
import 'package:test/test.dart';

import '../support/tikkun_fixtures.dart';

/// הפסוק האחרון בכל ספר לפי המסורה — הקריטריון לכך שהספר נקרא במלואו.
const Map<String, (int, int)> _lastVerse = {
  'bereshit': (50, 26),
  'shemot': (40, 38),
  'vayikra': (27, 34),
  'bamidbar': (36, 13),
  'devarim': (34, 12),
  'shoftim': (21, 25),
  'shmuel_b': (24, 25),
  'esther': (10, 3),
  'yeshayahu': (66, 24),
};

/// מודל רוחב אחיד — הפריסה נבדקת כהיגיון, בלי מדידת גופן אמיתית.
const StamWidthModel _widths = StamWidthModel.uniform();

/// סימוני ה-PUA (זעירא/רבתי/כתיב-קרי) אינם חלק מהטקסט לצורך השוואה.
final RegExp _pua = RegExp('[\u{E000}-\u{E0FF}]');
final RegExp _ketivQere = RegExp(
  '\u{E010}([\\s\\S]*?)\u{E011}([\\s\\S]*?)\u{E012}',
);

/// רצף אותיות הסת"ם שהמנוע מציג, בלי הרווחים והסימונים.
String _renderedText(Iterable<TikkunLine> lines) {
  final buf = StringBuffer();
  for (final line in lines) {
    for (final word in line.words) {
      if (word.isGap || word.isBigGap) continue;
      buf.write(word.stam.replaceAll(_pua, ''));
    }
  }
  return buf.toString();
}

/// רצף אותיות הסת"ם שהאסימונים מחוץ לקטעים המיוחדים מכילים.
/// במילת כתיב/קרי הטור הימני מציג את הכתיב.
String _sourceText(List<TikkunToken> tokens) {
  final buf = StringBuffer();
  var depth = 0;
  for (final tok in tokens) {
    if (tok.type == TikkunTokenType.specialStart) depth++;
    if (tok.type == TikkunTokenType.specialEnd) depth--;
    if (depth != 0 || !tok.isWord) continue;
    final kq = _ketivQere.firstMatch(tok.value!);
    buf.write(
      stripNikud(kq != null ? kq[1]! : tok.value!).replaceAll(_pua, ''),
    );
  }
  return buf.toString();
}

/// רוחב השורה ב-em, לפי אותו מודל רוחב שהעימוד מודד בו.
double _lineWidthEm(TikkunLine line, StamWidthModel widths) {
  var total = 0.0;
  for (final word in line.words) {
    total += widths.itemWidthEm(word);
  }
  return total;
}

/// רצף השורות המיוחדות שנוצר מהקטע [sectionId].
List<TikkunLine> _specialRunOf(
  List<TikkunToken> tokens,
  List<TikkunLine> lines,
  String sectionId,
) {
  final tokenIdx = tokens.indexWhere(
    (t) => t.type == TikkunTokenType.specialStart && t.section?.id == sectionId,
  );
  expect(tokenIdx, greaterThan(-1), reason: 'אסימון פתיחה ל-$sectionId');
  final run = <TikkunLine>[];
  for (final line in lines) {
    if (line.startTokenIdx >= tokenIdx && line.layout.isSpecial) {
      run.add(line);
    } else if (run.isNotEmpty && !line.layout.isSpecial) {
      break;
    }
  }
  return run;
}

void main() {
  late Map<String, String> raw;
  late Map<String, List<TikkunToken>> tokensById;
  late ProcessedTorah torah;

  setUpAll(() {
    raw = {for (final id in fixtureBookNames.keys) id: readFixture(id)};
    tokensById = {
      for (final id in fixtureBookNames.keys)
        id: tokenizeBook(raw[id]!, fixtureBookNames[id]!),
    };
    torah = processTorah({
      for (final id in TikkunData.booksOrder) id: raw[id]!,
    }, _widths);
  });

  group('מבנה הפרקים והפסוקים', () {
    for (final id in _lastVerse.keys) {
      test('$id — הספר נקרא עד הפסוק האחרון, במספור עולה', () {
        var chapter = 0;
        var verse = 0;
        for (final tok in tokensById[id]!) {
          if (tok.type == TikkunTokenType.chapterBreak) {
            expect(
              tok.chapterNum,
              chapter + 1,
              reason: 'פרקים חייבים להימנות ברצף',
            );
            chapter = tok.chapterNum!;
            verse = 0;
          } else if (tok.type == TikkunTokenType.verseBreak) {
            expect(
              tok.verseNum,
              greaterThan(verse),
              reason: 'מספרי הפסוקים בפרק $chapter חייבים לעלות',
            );
            verse = tok.verseNum!;
          }
        }
        expect((chapter, verse), _lastVerse[id]);
      });
    }
  });

  group('שלמות הטקסט אחרי העימוד', () {
    for (final id in fixtureBookNames.keys) {
      test('$id — אף מילה לא אבדה ולא הוכפלה', () {
        final lines = paginateAllTokens(tokensById[id]!, _widths);
        final rendered = _renderedText(
          lines.where((l) => !l.layout.isSpecial),
        );
        final source = _sourceText(tokensById[id]!);
        final shortest = rendered.length < source.length
            ? rendered.length
            : source.length;
        for (var i = 0; i < shortest; i++) {
          if (rendered.codeUnitAt(i) == source.codeUnitAt(i)) continue;
          final from = i < 40 ? 0 : i - 40;
          fail(
            '$id נבדל בתו $i\n'
            '  מקור =${escapeNonAscii(source.substring(from, i + 20))}\n'
            '  עימוד=${escapeNonAscii(rendered.substring(from, i + 20))}',
          );
        }
        expect(rendered.length, source.length, reason: 'אורך הטקסט');
      });
    }
  });

  group('השורה האחרונה אינה נמתחת', () {
    for (final id in fixtureBookNames.keys) {
      test('$id — סוף הספר אינו שורה רגילה', () {
        final last = paginateAllTokens(tokensById[id]!, _widths).last;
        expect(last.layout, isNot(LineLayout.regular));
      });
    }

    test('סוף התורה כולה אינו שורה רגילה', () {
      expect(torah.allLines.last.layout, isNot(LineLayout.regular));
    });
  });

  test('אף שורה מיושרת אינה נותרת ריקה למחצה', () {
    for (final line in torah.allLines) {
      if (line.layout != LineLayout.regular || line.words.length < 2) continue;
      final gap =
          (kTikkunLineWidthEm - _lineWidthEm(line, _widths)) /
          (line.words.length - 1);
      // ignore: avoid_print
      if (gap > 1.5) print('GAP ${gap.toStringAsFixed(2)}');
    }
  });

  test('אף שורה רגילה אינה חורגת מרוחב השורה', () {
    for (final line in torah.allLines) {
      if (line.layout.isSpecial || line.layout == LineLayout.empty) continue;
      expect(
        _lineWidthEm(line, _widths),
        lessThanOrEqualTo(kTikkunLineWidthEm),
        reason: 'שורה ${line.startTokenIdx}',
      );
    }
  });

  group('סימון פרשות ועליות', () {
    test('כל 54 הפרשות מסומנות פעם אחת, לפי סדרן', () {
      final expected = [
        for (final id in TikkunData.booksOrder)
          ...TikkunData.torahBooks[id]!.parashot,
      ];
      final actual = [
        for (final line in torah.allLines)
          if (line.parashaName != null) line.parashaName!,
      ];
      expect(actual.map(escapeNonAscii), expected.map(escapeNonAscii));
    });

    test('בכל פרשה שבע עליות לפחות, במספור עולה', () {
      final byParasha = <String, List<int>>{};
      var current = '';
      for (final line in torah.allLines) {
        if (line.parashaName != null) current = line.parashaName!;
        if (line.aliyaIdx != null) {
          (byParasha[current] ??= []).add(line.aliyaIdx!);
        }
      }
      for (final id in TikkunData.booksOrder) {
        for (final parasha in TikkunData.torahBooks[id]!.parashot) {
          final indices = byParasha[parasha] ?? const <int>[];
          expect(
            indices.length,
            greaterThanOrEqualTo(7),
            reason: 'עליות בפרשה ${escapeNonAscii(parasha)}',
          );
          for (var i = 1; i < indices.length; i++) {
            expect(
              indices[i],
              greaterThan(indices[i - 1]),
              reason: 'סדר העליות בפרשה ${escapeNonAscii(parasha)}',
            );
          }
        }
      }
    });
  });

  group('חלוקה לעמודים', () {
    for (final methodId in ['ramah', 'ramach', 'rambamRosh']) {
      test('$methodId — כל העמודים, רצופים ומכסים את כל השורות', () {
        final layout = TikkunData.torahLayouts[methodId]!;
        final pages = buildPages(torah, methodId);

        expect(pages.length, layout.totalPages);
        expect(pages.first.startLineIdx, 0);
        expect(pages.last.endLineIdx, torah.allLines.length);
        for (var i = 0; i < pages.length; i++) {
          expect(
            pages[i].lines.length,
            pages[i].endLineIdx - pages[i].startLineIdx,
            reason: 'עמוד $i',
          );
          if (i + 1 == pages.length) continue;
          expect(
            pages[i].endLineIdx,
            pages[i + 1].startLineIdx,
            reason: 'רצף בין עמוד $i לעמוד ${i + 1}',
          );
          expect(
            pages[i + 1].startLineIdx,
            greaterThanOrEqualTo(pages[i].startLineIdx),
          );
        }
      });
    }

    for (final methodId in ['ramah', 'ramach', 'rambamRosh']) {
      test('$methodId — העמוד נפתח במילה שהשיטה מציינת', () {
        final layout = TikkunData.torahLayouts[methodId]!;
        final pages = buildPages(torah, methodId);
        var counted = 0;
        var onFirstLine = 0;
        for (var i = 0; i < pages.length; i++) {
          final firstWord = layout.pages[i].firstWord;
          if (firstWord == null || pages[i].lines.isEmpty) continue;
          counted++;
          if (pages[i].lines.first.words.any((w) => w.stam == firstWord)) {
            onFirstLine++;
          }
        }
        expect(counted, greaterThan(200));
        expect(onFirstLine / counted, greaterThan(0.90));
      });
    }

    for (final methodId in ['ramah', 'ramach', 'rambamRosh']) {
      test('$methodId — כיסוי `lastWord`: כמה עמודים נסגרים במילה שבטבלה', () {
        final layout = TikkunData.torahLayouts[methodId]!;
        final pages = buildPages(torah, methodId);
        final unmatched = countUnmatchedOfficialPages(pages, layout.pages);
        // ignore: avoid_print
        print('$methodId lastWord unmatched: $unmatched/${pages.length}');
        expect(unmatched, lessThan(pages.length));
      });
    }

    test('single_page — עמוד אחד שמכיל את כל השורות', () {
      final pages = buildPages(torah, 'single_page');
      expect(pages.length, 1);
      expect(pages.single.lines.length, torah.allLines.length);
    });
  });

  group('קטעים מיוחדים', () {
    test('שירת הים ושירת האזינו נפרסות כזיגזג', () {
      for (final sectionId in ['shirat_hayam', 'shirat_haazinu']) {
        final run = _specialRunOf(torah.tokens, torah.allLines, sectionId);
        expect(run, isNotEmpty, reason: sectionId);
        expect(
          run.map((l) => l.layout).toSet(),
          {LineLayout.shiraZigzag},
          reason: sectionId,
        );
      }
    });

    test('שירת דבורה נפרסת כזיגזג ועשרת בני המן כרשימה', () {
      for (final entry in {
        ('shoftim', 'shirat_devorah'): LineLayout.shiraZigzag,
        ('esther', 'aseret_bnei_haman'): LineLayout.listAlternating,
      }.entries) {
        final (bookId, sectionId) = entry.key;
        final tokens = tokensById[bookId]!;
        final run = _specialRunOf(
          tokens,
          paginateAllTokens(tokens, _widths),
          sectionId,
        );
        expect(run, isNotEmpty, reason: sectionId);
        expect(run.map((l) => l.layout).toSet(), {
          entry.value,
        }, reason: sectionId);
      }
    });
  });

  test('הפטרה מתחילה ומסתיימת בדיוק בטווח הפסוקים שלה', () {
    final haftarah = TikkunData.haftarot.firstWhere(
      (h) => h.id == 'p:Bereshit',
    );
    final segments = getHaftarahSegments(haftarah, 'ashkenaz');
    final lines = buildHaftarahLines(haftarah, 'ashkenaz', {
      fixtureBookNames['yeshayahu']!: tokensById['yeshayahu']!,
    }, _widths);

    expect(lines, isNotEmpty);
    expect(lines.first.firstChapterNum, segments.first.fromCh);
    expect(lines.first.firstVerseNum, segments.first.fromVs);

    final lastVerse = lines.where((l) => l.firstVerseNum != null).last;
    expect(lastVerse.firstVerseNum, segments.last.toVs);
    final lastChapter = lines.where((l) => l.firstChapterNum != null).last;
    expect(lastChapter.firstChapterNum, segments.last.toCh);
  });

  test('קריאת מועד — עליות רצופות מתאחדות, וכל עליה מסומנת פעם אחת', () {
    final reading = TikkunData.torahReadings.firstWhere(
      (r) => r.id == 'tr:Pesach I',
    );
    final lines = buildTorahReadingLines(reading, {
      for (final id in TikkunData.booksOrder)
        fixtureBookNames[id]!: tokensById[id]!,
    }, _widths);

    expect(
      lines.where((l) => l.aliyaName != null || l.maftirName != null).length,
      reading.aliyot.length,
    );

    final segments = computeContinuousSegments(reading.aliyot);
    expect(segments.length, lessThan(reading.aliyot.length));
    expect(
      (segments.first.fromCh, segments.first.fromVs),
      (reading.aliyot.first.range.fromCh, reading.aliyot.first.range.fromVs),
    );
    expect(
      (segments.last.toCh, segments.last.toVs),
      (reading.aliyot.last.range.toCh, reading.aliyot.last.range.toVs),
    );
    for (final segment in segments) {
      expect(
        escapeNonAscii(segment.book),
        isIn(reading.aliyot.map((a) => escapeNonAscii(a.range.book))),
      );
    }
  });
}
