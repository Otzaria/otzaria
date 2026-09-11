/// המסלולים המלאים של המנוע: התורה כולה, ספר תנ"ך בודד, הפטרה וקריאת מועד.
/// פורט של `loadAndProcessAll`, `loadAndDisplayTanachBook`,
/// `loadAndDisplayHaftarah` ו-`loadAndDisplayTorahReading` (navigation.js)
/// בלי ה-IO וה-DOM — קלט טקסט גולמי, פלט שורות מעומדות.
library;

import 'package:otzaria/tools/tikkun_korim/data/tikkun_data.dart';
import 'package:otzaria/tools/tikkun_korim/engine/aliyot_annotator.dart';
import 'package:otzaria/tools/tikkun_korim/engine/decalogue_taam.dart';
import 'package:otzaria/tools/tikkun_korim/engine/line_paginator.dart';
import 'package:otzaria/tools/tikkun_korim/engine/official_pages_builder.dart';
import 'package:otzaria/tools/tikkun_korim/engine/raw_text_cleaner.dart';
import 'package:otzaria/tools/tikkun_korim/engine/special_sections_marker.dart';
import 'package:otzaria/tools/tikkun_korim/engine/stam_width_model.dart';
import 'package:otzaria/tools/tikkun_korim/engine/tokenizer.dart';
import 'package:otzaria/tools/tikkun_korim/engine/verse_range_slicer.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';
import 'package:otzaria/tools/tikkun_korim/repository/tikkun_contracts.dart';

/// אסימוני ספר בודד: ניקוי, פירוק, בחירת הפרשיות לפי [tradition] וסימון
/// הקטעים המיוחדים שלו.
List<TikkunToken> tokenizeBook(
  String rawText,
  String hebrewBookName, {
  TikkunTradition tradition = TikkunTradition.ashkenazSephard,
  TikkunDecalogueTaam decalogueTaam = TikkunDecalogueTaam.merged,
}) => markSpecialSections(
  applyDecalogueTaam(
    filterByTradition(tokenizeText(cleanRawText(rawText)), tradition),
    hebrewBookName,
    decalogueTaam,
  ),
  hebrewBookName,
);

/// עיבוד מלא של חמשת החומשים כרצף אחד, כולל סימון פרשות ועליות.
/// המפתחות ב-[rawByBookId]: bereshit/shemot/vayikra/bamidbar/devarim.
ProcessedTorah processTorah(
  Map<String, String> rawByBookId,
  StamWidthModel widths, {
  TikkunTradition tradition = TikkunTradition.ashkenazSephard,
  TikkunDecalogueTaam decalogueTaam = TikkunDecalogueTaam.merged,
}) {
  final tokens = <TikkunToken>[];
  final order = TikkunData.booksOrder;

  for (var i = 0; i < order.length; i++) {
    final bookId = order[i];
    final book = TikkunData.torahBooks[bookId];
    final raw = rawByBookId[bookId];
    if (book == null || raw == null) continue;
    if (i > 0) tokens.add(const TikkunToken(type: TikkunTokenType.bookBreak));
    tokens.addAll(
      tokenizeBook(
        raw,
        book.name,
        tradition: tradition,
        decalogueTaam: decalogueTaam,
      ),
    );
  }

  final bookStartTokenIdx = computeBookStartIndices(tokens);
  final allLines = paginateAllTokens(tokens, widths);
  annotateAliyotOnLines(tokens, allLines, bookStartTokenIdx);
  annotateCombinedAliyotOnLines(tokens, allLines, bookStartTokenIdx);

  return ProcessedTorah(
    tokens: tokens,
    allLines: allLines,
    bookStartTokenIdx: bookStartTokenIdx,
  );
}

/// חלוקה לעמודים לפי השיטה. 'single_page' = עמוד אחד ארוך.
List<TikkunPage> buildPages(ProcessedTorah processed, String methodId) {
  if (methodId == 'single_page') {
    return [
      TikkunPage(
        startLineIdx: 0,
        endLineIdx: processed.allLines.length,
        lines: processed.allLines,
      ),
    ];
  }
  final layout = TikkunData.torahLayouts[methodId];
  if (layout == null) return const [];
  return buildOfficialPages(processed.tokens, processed.allLines, layout.pages);
}

/// עיבוד ספר בודד (נביא/כתוב, או חומש לצורך הפטרה/קריאה).
ProcessedBook processBook(
  String rawText,
  String hebrewBookName,
  StamWidthModel widths, {
  TikkunTradition tradition = TikkunTradition.ashkenazSephard,
  TikkunDecalogueTaam decalogueTaam = TikkunDecalogueTaam.merged,
}) {
  final tokens = tokenizeBook(
    rawText,
    hebrewBookName,
    tradition: tradition,
    decalogueTaam: decalogueTaam,
  );
  final allLines = paginateAllTokens(tokens, widths);

  final chapterToLineIdx = <int, int>{};
  for (var i = 0; i < allLines.length; i++) {
    final ch = allLines[i].firstChapterNum;
    if (ch != null) chapterToLineIdx.putIfAbsent(ch, () => i);
  }

  return ProcessedBook(
    tokens: tokens,
    allLines: allLines,
    chapterToLineIdx: chapterToLineIdx,
  );
}

/// שמות הספרים שיש לטעון כדי להציג את [haftarah] בנוסח [nusach].
List<String> haftarahBooks(Haftarah haftarah, String nusach) => [
  for (final seg in getHaftarahSegments(haftarah, nusach)) seg.book,
];

/// שמות הספרים שיש לטעון כדי להציג את [reading].
List<String> readingBooks(TorahReading reading) => [
  for (final a in reading.aliyot) a.range.book,
];

/// שורות ההפטרה: כל מקטע נחתך מהספר שלו, עם הפסק בין המקטעים.
/// [tokensByBook] — אסימוני הספרים לפי שמם העברי (ראה [tokenizeBook]).
List<TikkunLine> buildHaftarahLines(
  Haftarah haftarah,
  String nusach,
  Map<String, List<TikkunToken>> tokensByBook,
  StamWidthModel widths,
) {
  final segs = getHaftarahSegments(haftarah, nusach);
  final combined = <TikkunToken>[];

  for (var i = 0; i < segs.length; i++) {
    final seg = segs[i];
    final tokens = tokensByBook[seg.book];
    if (tokens == null) continue;
    final slice = sliceTokensByVerseRange(
      tokens,
      seg.fromCh,
      seg.fromVs,
      seg.toCh,
      seg.toVs,
    );
    final afterSetuma = precededBySetuma(tokens, seg.fromCh, seg.fromVs);
    if (i == 0) {
      if (afterSetuma) {
        combined.add(const TikkunToken(type: TikkunTokenType.leadingSetuma));
      }
    } else {
      combined.add(
        TikkunToken(
          type: afterSetuma
              ? TikkunTokenType.leadingSetuma
              : TikkunTokenType.petucha,
        ),
      );
    }
    combined.addAll(slice);
  }

  final lines = paginateAllTokens(combined, widths);
  // שורת קטע מיוחד מחזיקה את תוכנה בתאים ולא ב-`words`; סימונה כפתוחה
  // היה מחזיר אותה למסלול השורה הרגילה, והיא הייתה מתרוקנת.
  if (lines.isNotEmpty && !lines.last.isSpecial) {
    lines.last.layout = LineLayout.petucha;
  }
  return lines;
}

/// שורות קריאת המועד, כולל סימון שם העליה בשורה שבה היא מתחילה.
List<TikkunLine> buildTorahReadingLines(
  TorahReading reading,
  Map<String, List<TikkunToken>> tokensByBook,
  StamWidthModel widths,
) {
  final combined = <TikkunToken>[];
  final markers = <({int tokenIdx, String label, String? scrollLabel})>[];
  String? lastAliyaKey;
  ({String book, int ch, int vs})? lastTo;
  var scrollIdx = 0;

  for (var i = 0; i < reading.aliyot.length; i++) {
    final aliya = reading.aliyot[i];
    final range = aliya.range;
    final tokens = tokensByBook[range.book];
    if (tokens == null) continue;
    final slice = sliceTokensByVerseRange(
      tokens,
      range.fromCh,
      range.fromVs,
      range.toCh,
      range.toVs,
    );
    final afterSetuma = precededBySetuma(tokens, range.fromCh, range.fromVs);
    if (i == 0 && afterSetuma) {
      combined.add(const TikkunToken(type: TikkunTokenType.leadingSetuma));
    }

    final isNewAliya = aliya.aliya != lastAliyaKey;
    String? scrollLabel;
    if (isNewAliya && lastTo != null) {
      final sameBook = range.book == lastTo.book;
      final isAdjacent =
          sameBook &&
          ((range.fromCh == lastTo.ch && range.fromVs == lastTo.vs + 1) ||
              (range.fromCh == lastTo.ch + 1 && range.fromVs == 1));
      final isOverlap =
          sameBook &&
          compareVerse(range.fromCh, range.fromVs, lastTo.ch, lastTo.vs) <= 0;
      if (!isAdjacent && !isOverlap) {
        combined.add(
          TikkunToken(
            type: afterSetuma
                ? TikkunTokenType.leadingSetuma
                : TikkunTokenType.petucha,
          ),
        );
        // מעבר לספר אחר = ספר תורה נוסף; באותו חומש רק אחרי שכבר הוחלף
        // ספר, שאם לא כן דילוג פנימי (תענית ציבור) ייחשב בטעות כהחלפה.
        if (!sameBook || scrollIdx > 0) {
          scrollIdx++;
          scrollLabel = torahScrollLabel(scrollIdx);
        }
      }
    }
    if (isNewAliya) {
      markers.add((
        tokenIdx: combined.length,
        label: aliya.aliyaLabel,
        scrollLabel: scrollLabel,
      ));
    }
    combined.addAll(slice);
    lastAliyaKey = aliya.aliya;
    lastTo = (book: range.book, ch: range.toCh, vs: range.toVs);
  }

  final lines = paginateAllTokens(combined, widths);
  annotateReadingAliyaMarkers(lines, combined, markers);
  if (lines.isNotEmpty && !lines.last.isSpecial) {
    lines.last.layout = LineLayout.petucha;
  }
  return lines;
}

/// מסמן את שם העליה בשורה שמכילה את מילתה הראשונה — גם כשהמילה נכנסה
/// לסוף שורה של העליה הקודמת.
void annotateReadingAliyaMarkers(
  List<TikkunLine> lines,
  List<TikkunToken> tokens,
  List<({int tokenIdx, String label, String? scrollLabel})> markers,
) {
  for (final marker in markers) {
    var firstWordIdx = -1;
    for (var j = marker.tokenIdx; j < tokens.length; j++) {
      if (tokens[j].isWord) {
        firstWordIdx = j;
        break;
      }
    }
    if (firstWordIdx < 0) continue;
    for (var i = 0; i < lines.length; i++) {
      final nextStart = i + 1 < lines.length
          ? lines[i + 1].startTokenIdx
          : 0x7fffffff;
      if (lines[i].startTokenIdx >= 0 &&
          lines[i].startTokenIdx <= firstWordIdx &&
          firstWordIdx < nextStart) {
        if (marker.label == kMaftirAliyaName) {
          lines[i].maftirName ??= marker.label;
        } else {
          lines[i].aliyaName ??= marker.label;
        }
        lines[i].torahScrollLabel ??= marker.scrollLabel;
        break;
      }
    }
  }
}
