import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/tikkun_korim/data/tikkun_data.dart';
import 'package:otzaria/tools/tikkun_korim/engine/line_paginator.dart';
import 'package:otzaria/tools/tikkun_korim/engine/official_pages_builder.dart';
import 'package:otzaria/tools/tikkun_korim/engine/stam_width_model.dart';
import 'package:otzaria/tools/tikkun_korim/engine/tikkun_processor.dart';
import 'package:otzaria/tools/tikkun_korim/engine/tokenizer.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';

import '../support/tikkun_fixtures.dart';

const _methods = ['ramah', 'ramach', 'rambamRosh'];

List<TikkunToken> _torahTokens(
  TikkunTradition tradition,
  TikkunDecalogueTaam taam,
) {
  final tokens = <TikkunToken>[];
  for (final id in TikkunData.booksOrder) {
    if (tokens.isNotEmpty) {
      tokens.add(const TikkunToken(type: TikkunTokenType.bookBreak));
    }
    tokens.addAll(
      tokenizeBook(
        readFixture(id),
        TikkunData.torahBooks[id]!.name,
        tradition: tradition,
        decalogueTaam: taam,
      ),
    );
  }
  return tokens;
}

/// המילה הראשונה והאחרונה של כל עמוד לפי טבלאות "אור לסופר" — מקור העוגנים.
List<({String? first, String? last})> _sourcePages(String methodId) {
  final json =
      jsonDecode(
            File(
              'tool/tikkun_korim/vendor/or_lasofer_layouts.json',
            ).readAsStringSync(),
          )
          as Map;
  final method = (json['methods'] as Map)[methodId] as Map;
  return [
    for (final page in method['pages'] as List)
      (
        first: (page as Map)['first'] as String?,
        last: page['last'] as String?,
      ),
  ];
}

/// אותו מפתח השוואה שהגנרטור משתמש בו (כתיב, בלי זעירא/רבתי, פיסוק, השם).
String _key(String stam) {
  final bare = stam
      .replaceAllMapped(
        RegExp('\u{E010}([\\s\\S]*?)\u{E011}[\\s\\S]*'),
        (m) => m[1]!,
      )
      .replaceAll(RegExp('[\u{E000}-\u{E0FF}]'), '')
      .replaceAll('יקוק', 'יהוה');
  if (RegExp('^[ולבכמש]*ה[\'׳]\$').hasMatch(bare)) {
    return '${bare.substring(0, bare.length - 2)}יהוה';
  }
  return bare.replaceAll(RegExp('[.\'׳]'), '');
}

/// האם [value] (שעלול לשאת שארית של תווית) מכיל רכיב ששווה ל-[key].
bool _hasPart(String? value, String key) =>
    value != null && value.split(' ').any((w) => _key(w) == key);

void main() {
  group('טבלת העוגנים', () {
    for (final methodId in _methods) {
      test('$methodId — עוגן לכל עמוד, והראשון בראש התורה', () {
        final anchors = TikkunData.torahPageAnchors(methodId);
        expect(anchors.length, TikkunData.torahLayouts[methodId]!.pages.length);
        expect(anchors.first, (book: 1, chapter: 1, verse: 1, word: 1));
        final anchored = anchors.where((a) => a != null).length;
        expect(anchored / anchors.length, greaterThan(0.95));
      });

      for (final taam in TikkunDecalogueTaam.values) {
        test('$methodId/${taam.id} — כל עוגן נמצא בטקסט, בסדר עולה, '
            'ובמילה שהטבלה מציינת', () {
          final source = _sourcePages(methodId);
          final anchors = TikkunData.torahPageAnchors(methodId);
          final tokens = _torahTokens(
            TikkunTradition.forMethod(methodId),
            taam,
          );
          final resolved = resolveWordRefs(tokens, anchors);
          final unresolved = <int>[];
          final wrongWord = <int>[];
          var prev = -1;
          for (var p = 0; p < anchors.length; p++) {
            if (anchors[p] == null) continue;
            final tok = resolved[p];
            if (tok == null) {
              unresolved.add(p + 1);
              continue;
            }
            expect(tok, greaterThan(prev), reason: 'עמוד ${p + 1}');
            prev = tok;
            // עוגן מאומת כשהמילה שלו היא הראשונה בעמוד לפי הטבלה, או כשהמילה
            // שלפניו היא האחרונה של העמוד הקודם (כתיב הטבלה שונה לעיתים).
            if (p == 0) continue;
            final firstOk = _hasPart(
              source[p].first,
              _key(stripNikud(tokens[tok].value!)),
            );
            var before = tok - 1;
            while (before >= 0 &&
                (!tokens[before].isWord ||
                    stripNikud(tokens[before].value!).isEmpty)) {
              before--;
            }
            final lastOk =
                before >= 0 &&
                _hasPart(
                  source[p - 1].last,
                  _key(stripNikud(tokens[before].value!)),
                );
            if (!firstOk && !lastOk) wrongWord.add(p + 1);
          }
          expect(unresolved, isEmpty);
          expect(wrongWord, isEmpty);
        });
      }
    }
  });

  group('הפניה למילה', () {
    test('ספירת המילים מתאפסת בפסוק ובפרק, והחומש מתקדם בגבול', () {
      final tokens = tokenizeText(
        'CHAPTERMARK1MARK VERSEMARK1MARK א ב VERSEMARK2MARK ג '
        'BOOKBREAKMARKER CHAPTERMARK1MARK VERSEMARK1MARK ד',
      );
      final refs = <TikkunWordRef>[];
      forEachTorahWord(tokens, (_, ref) => refs.add(ref));
      expect(refs, [
        (book: 1, chapter: 1, verse: 1, word: 1),
        (book: 1, chapter: 1, verse: 1, word: 2),
        (book: 1, chapter: 1, verse: 2, word: 1),
        (book: 2, chapter: 1, verse: 1, word: 1),
      ]);
    });

    test('הפניה שאינה בטקסט נשארת בלי אסימון', () {
      final tokens = tokenizeText('CHAPTERMARK1MARK VERSEMARK1MARK א ב');
      final resolved = resolveWordRefs(tokens, [
        (book: 1, chapter: 1, verse: 1, word: 2),
        (book: 1, chapter: 9, verse: 9, word: 9),
        null,
      ]);
      expect(tokens[resolved[0]!].value, 'ב');
      expect(resolved[1], isNull);
      expect(resolved[2], isNull);
    });
  });

  group('שבירת עמוד כפויה', () {
    test('העוגן פותח שורה, גם כשהשורה הקודמת לא התמלאה', () {
      final tokens = tokenizeText('א ב ג ד');
      final anchored = insertPageBreaks(tokens, [0, 3]);
      final lines = paginateAllTokens(
        anchored.tokens,
        const StamWidthModel.uniform(),
      );
      expect(lines, hasLength(2));
      expect(lines[1].startTokenIdx, anchored.pageStarts[1]);
      expect(lines[1].words.first.stam, 'ד');
    });

    test('בתוך קטע מיוחד לא מוזרקת שבירה', () {
      const tokens = [
        TikkunToken(type: TikkunTokenType.specialStart),
        TikkunToken.word('א'),
        TikkunToken(type: TikkunTokenType.specialEnd),
        TikkunToken.word('ב'),
      ];
      final anchored = insertPageBreaks(tokens, [0, 1, 3]);
      final breaks = anchored.tokens
          .where((t) => t.type == TikkunTokenType.pageBreak)
          .length;
      expect(breaks, 1);
      expect(anchored.tokens[anchored.pageStarts[2]!].value, 'ב');
    });

    test('עמודים בלי עוגן מתחלקים שווה בשורות', () {
      final lines = [
        for (var i = 0; i < 12; i++)
          TikkunLine(layout: LineLayout.regular, startTokenIdx: i),
      ];
      final pages = buildOfficialPages(lines, [0, null, null, 9], 4);
      expect([for (final p in pages) p.startLineIdx], [0, 3, 6, 9]);
      expect(pages.last.endLineIdx, 12);
    });
  });

  group('מיקום פסוק בין חלוקות', () {
    TikkunLine line({int? chapter, int? verse}) =>
        TikkunLine(firstChapterNum: chapter, firstVerseNum: verse);
    List<TikkunPage> split(List<TikkunLine> lines, List<int> starts) => [
      for (var p = 0; p < starts.length; p++)
        TikkunPage(
          startLineIdx: starts[p],
          endLineIdx: p + 1 < starts.length ? starts[p + 1] : lines.length,
          lines: lines.sublist(
            starts[p],
            p + 1 < starts.length ? starts[p + 1] : lines.length,
          ),
        ),
    ];
    // שני חומשים: פרק 50 ואחריו פרק 1 של החומש הבא.
    final lines = [
      line(chapter: 50, verse: 1),
      line(verse: 2),
      line(),
      line(chapter: 1, verse: 1),
      line(verse: 2),
      line(),
    ];

    test('אותו פסוק נמצא בחלוקה אחרת', () {
      final key = tikkunVerseKeyAt(split(lines, [0, 3]), 1, 2)!;
      expect(tikkunLocateVerse(split(lines, [0, 2, 4]), key), (
        pageIdx: 2,
        lineInPage: 0,
      ));
    });

    test('פרק 1 אחרי פרק 50 הוא חומש חדש ולא חזרה לאחור', () {
      final pages = split(lines, [0]);
      expect(
        tikkunVerseKeyAt(pages, 0, 3)!,
        greaterThan(tikkunVerseKeyAt(pages, 0, 2)!),
      );
    });
  });

  group('דפי השירה רחבים', () {
    test('שורה בדף רחב מכילה יותר מילים', () {
      final tokens = tokenizeText(List.filled(200, 'אבג').join(' '));
      final regular = paginateAllTokens(
        tokens,
        const StamWidthModel.uniform(),
      );
      final wide = paginateAllTokens(
        tokens,
        const StamWidthModel.uniform(),
        widthFactors: List.filled(tokens.length, kTikkunShiraPageWidthFactor),
      );
      expect(
        wide.first.words.length,
        greaterThan(regular.first.words.length * 1.4),
      );
    });

    for (final methodId in _methods) {
      test('$methodId — רק דפי השירה רחבים, וכל שורותיהם', () {
        final torah = processTorah(
          {for (final id in TikkunData.booksOrder) id: readFixture(id)},
          const StamWidthModel.uniform(),
          tradition: TikkunTradition.forMethod(methodId),
          methodId: methodId,
        );
        final pages = buildPages(torah, methodId);
        bool isShira(TikkunLine line) {
          for (var i = line.startTokenIdx; i >= 0; i--) {
            final tok = torah.tokens[i];
            if (tok.type == TikkunTokenType.specialEnd) return false;
            if (tok.type == TikkunTokenType.specialStart) {
              return kTikkunWidePageSections.contains(tok.section?.id);
            }
          }
          return false;
        }

        final regular = pages.first.lines.first.widthFactor;
        final wide = <int>[];
        for (var p = 0; p < pages.length; p++) {
          final factors = {for (final l in pages[p].lines) l.widthFactor};
          expect(factors, hasLength(1), reason: 'דף ${p + 1} ברוחב אחיד');
          final shira = pages[p].lines.any((l) => l.isSpecial && isShira(l));
          if (shira) {
            wide.add(p);
            expect(factors.single, greaterThanOrEqualTo(regular));
          } else {
            expect(factors.single, regular, reason: 'דף ${p + 1}');
          }
        }
        expect(wide, hasLength(3), reason: 'שירת הים בדף, האזינו בשניים');
      });
    }

    for (final methodId in ['ramah', 'ramach']) {
      test('$methodId — כל דף שירה יוצא במניין השורות של השיטה', () {
        final torah = processTorah(
          {for (final id in TikkunData.booksOrder) id: readFixture(id)},
          const StamWidthModel.uniform(),
          tradition: TikkunTradition.forMethod(methodId),
          methodId: methodId,
        );
        final target = TikkunData.torahLayouts[methodId]!.linesPerPage;
        final pages = buildPages(torah, methodId);
        final wide = [
          for (final page in pages)
            if (page.lines.any((l) => l.isSpecial)) page,
        ];
        expect(
          [for (final page in wide) page.lines.length],
          [target, target, target],
        );
        expect(
          wide[1].lines.first.widthFactor,
          wide[2].lines.first.widthFactor,
          reason: 'שני דפי האזינו ברוחב אחד',
        );
        for (final page in wide) {
          final last = page.lines.last;
          if (last.isSpecial) continue;
          expect(
            last.words.length,
            greaterThan(1),
            reason: 'השורה האחרונה בדף שירה אינה מילה יתומה',
          );
        }
      });
    }
  });

  group('מניין השורות הקבוע', () {
    for (final methodId in _methods) {
      test('$methodId — כל דף במניין, ורק מיעוט הדפים צפוף מרוחב הטור', () {
        final torah = processTorah(
          {for (final id in TikkunData.booksOrder) id: readFixture(id)},
          const StamWidthModel.uniform(),
          tradition: TikkunTradition.forMethod(methodId),
          methodId: methodId,
        );
        final target = TikkunData.torahLayouts[methodId]!.linesPerPage;
        final pages = buildPages(torah, methodId);
        final off = [
          for (var p = 0; p < pages.length; p++)
            if (pages[p].lines.length != target) p + 1,
        ];
        expect(off, isEmpty);
        final dense = [
          for (var p = 0; p < pages.length; p++)
            if (pages[p].lines.any((l) => l.slackFraction < 0)) p + 1,
        ];
        expect(dense.length, lessThanOrEqualTo(pages.length ~/ 20));
        final regularWidth = pages.first.lines.first.widthFactor;
        for (final line in torah.allLines) {
          // בדף שירה הפרוזה נדחסת עד גבול הדחיסה של השירה.
          final floor = line.widthFactor > regularWidth
              ? 1 - 1 / kTikkunShiraMinCondense
              : -0.1;
          expect(line.slackFraction, greaterThan(floor - 1e-9));
        }
      });
    }
  });

  test('התורה המעובדת לפי שיטה נושאת את מיקומי העוגנים', () {
    final torah = processTorah(
      {for (final id in TikkunData.booksOrder) id: readFixture(id)},
      const StamWidthModel.uniform(),
      methodId: 'ramah',
    );
    expect(
      torah.pageStartTokenIdx.length,
      TikkunData.torahLayouts['ramah']!.pages.length,
    );
    expect(
      torah.tokens.where((t) => t.type == TikkunTokenType.pageBreak).length,
      greaterThan(200),
    );
  });

  group('סוף התורה', () {
    for (final methodId in _methods) {
      test('$methodId — העמוד האחרון מלא, והספר נגמר באמצע שיטתו האחרונה', () {
        const widths = StamWidthModel.uniform();
        final torah = processTorah(
          {for (final id in TikkunData.booksOrder) id: readFixture(id)},
          widths,
          tradition: TikkunTradition.forMethod(methodId),
          methodId: methodId,
        );
        final last = buildPages(torah, methodId).last.lines;
        expect(
          last,
          hasLength(TikkunData.torahLayouts[methodId]!.linesPerPage),
        );
        final words = [
          for (final w in last.last.words)
            if (!w.isGap && !w.isBigGap) w,
        ];
        var used = widths.wordGapEm * (words.length - 1);
        for (final w in words) {
          used += widths.wordWidthEm(w.stam);
        }
        expect(
          used / (widths.lineWidthEm * last.last.budgetFactor),
          inInclusiveRange(0.25, 0.75),
        );
      });
    }
  });

  group('רוחב דפי השירה', () {
    for (final methodId in _methods) {
      test('$methodId — כל חצי שיטה בהאזינו נכנס, בדחיסה קלה לכל היותר', () {
        const widths = StamWidthModel.uniform();
        final torah = processTorah(
          {for (final id in TikkunData.booksOrder) id: readFixture(id)},
          widths,
          tradition: TikkunTradition.forMethod(methodId),
          methodId: methodId,
        );
        final rows = [
          for (final line in torah.allLines)
            if (line.cssClasses.contains('justify-cells') &&
                tikkunManualCellsEm(line, widths) != null)
              line,
        ];
        expect(rows, hasLength(70));
        for (final line in rows) {
          final row = tikkunManualCellsEm(line, widths)!;
          expect(
            line.cellGapFactor,
            inInclusiveRange(
              kTikkunShiraMinGapFactor,
              kTikkunShiraMaxGapFactor,
            ),
          );
          expect(
            row.cells * kTikkunShiraMinCondense +
                widths.setumaGapEm * row.gaps * line.cellGapFactor,
            lessThanOrEqualTo(line.widthFactor * widths.lineWidthEm + 1e-9),
          );
        }
      });
    }

    for (final methodId in _methods) {
      test('$methodId — אריחי שירת הים נכנסים, והדף צר מרוחב הפתיחה', () {
        const widths = StamWidthModel.uniform();
        final torah = processTorah(
          {for (final id in TikkunData.booksOrder) id: readFixture(id)},
          widths,
          tradition: TikkunTradition.forMethod(methodId),
          methodId: methodId,
        );
        final rows = [
          for (final line in torah.allLines)
            if (line.manualCells != null &&
                !line.cssClasses.contains('justify-cells'))
              line,
        ];
        expect(rows, hasLength(30));
        for (final line in rows) {
          expect(
            tikkunManualCellsEm(line, widths)!.cells * kTikkunShiraMinCondense +
                widths.setumaGapEm * kTikkunShiraMinGapFactor,
            lessThanOrEqualTo(line.widthFactor * widths.lineWidthEm + 1e-9),
          );
        }
        expect(rows.first.widthFactor, lessThan(kTikkunShiraPageWidthFactor));
      });
    }

    test('rambamRosh — אין שיטה פנויה לפני האזינו', () {
      const widths = StamWidthModel.uniform();
      final torah = processTorah(
        {for (final id in TikkunData.booksOrder) id: readFixture(id)},
        widths,
        tradition: TikkunTradition.forMethod('rambamRosh'),
        methodId: 'rambamRosh',
      );
      final lines = torah.allLines;
      final first = lines.indexWhere(
        (l) => l.cssClasses.contains('justify-cells'),
      );
      expect(lines[first - 1].layout, isNot(LineLayout.empty));
    });
  });
}
