/// סימון קטעי השירה/הרשימה בתוך רצף האסימונים. פורט של
/// `markSpecialSections`, `applyBoundaryTrimming`, `injectExtraBreaks`
/// ו-`suppressSegmentBreaks` (special_layouts.js).
library;

import 'package:otzaria/tools/tikkun_korim/data/tikkun_data.dart';
import 'package:otzaria/tools/tikkun_korim/engine/tokenizer.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';

final RegExp _puaZeiraRabati = RegExp('[-]');
final RegExp _puaKetivQere = RegExp('[-]');
final RegExp _maqaf = RegExp('־');
final RegExp _spaces = RegExp(r'\s+');

/// הקטע המיוחד הראשון שמכיל את (ספר, פרק, פסוק), או `null`.
SpecialSection? findSpecialSection(
  String book,
  int ch,
  int vs, {
  List<SpecialSection>? sections,
}) {
  for (final sec in sections ?? TikkunData.specialSections) {
    if (sec.book != book) continue;
    if (ch < sec.fromCh || ch > sec.toCh) continue;
    if (ch == sec.fromCh && vs < sec.fromVs) continue;
    if (ch == sec.toCh && vs > sec.toVs) continue;
    return sec;
  }
  return null;
}

/// מחדיר `special_start`/`special_end` סביב כל קטע מיוחד של [bookName],
/// ואז מיישם טרים גבולות, הזרקת מעברי סגמנט וביטולם.
List<TikkunToken> markSpecialSections(
  List<TikkunToken> tokens,
  String? bookName, {
  List<SpecialSection>? sections,
}) {
  if (bookName == null || bookName.isEmpty) return tokens;

  final out = <TikkunToken>[];
  int? curCh;
  int? curVs;
  SpecialSection? activeSection;

  void checkAndOpen() {
    if (activeSection != null) return;
    if (curCh == null || curVs == null) return;
    final sec = findSpecialSection(
      bookName,
      curCh,
      curVs,
      sections: sections,
    );
    if (sec != null) {
      activeSection = sec;
      out.add(
        TikkunToken(
          type: TikkunTokenType.specialStart,
          section: sec,
          openingChapter: curCh,
          openingVerse: curVs,
        ),
      );
    }
  }

  void checkAndClose() {
    if (activeSection == null) return;
    if (curCh == null || curVs == null) return;
    final stillIn = findSpecialSection(
      bookName,
      curCh,
      curVs,
      sections: sections,
    );
    if (stillIn == null || stillIn.id != activeSection!.id) {
      out.add(const TikkunToken(type: TikkunTokenType.specialEnd));
      activeSection = null;
    }
  }

  for (final tok in tokens) {
    if (tok.type == TikkunTokenType.chapterBreak) {
      curCh = tok.chapterNum;
      curVs = null;
      checkAndClose();
      out.add(tok);
      continue;
    }
    if (tok.type == TikkunTokenType.verseBreak) {
      curVs = tok.verseNum;
      checkAndClose();
      out.add(tok);
      checkAndOpen();
      continue;
    }
    out.add(tok);
  }

  if (activeSection != null) {
    out.add(const TikkunToken(type: TikkunTokenType.specialEnd));
  }

  return suppressSegmentBreaks(injectExtraBreaks(applyBoundaryTrimming(out)));
}

String _cleanStam(String w) => stripNikud(w)
    .replaceAll(_puaZeiraRabati, '')
    .replaceAll(_puaKetivQere, '')
    .replaceAll(_maqaf, ' ');

/// האם [recent] מסתיים בדיוק ב-[pattern]?
bool _endsWith(List<String> recent, List<String> pattern) {
  if (recent.length < pattern.length) return false;
  final offset = recent.length - pattern.length;
  for (var i = 0; i < pattern.length; i++) {
    if (recent[offset + i] != pattern[i]) return false;
  }
  return true;
}

/// מזריק `segment_break` אחרי כל רצף מילים מתוך `section.extraBreaks`.
List<TikkunToken> injectExtraBreaks(List<TikkunToken> tokens) {
  final result = <TikkunToken>[];
  List<List<String>>? activeExtras;
  final recent = <String>[];

  for (final tok in tokens) {
    if (tok.type == TikkunTokenType.specialStart) {
      final extras = tok.section?.extraBreaks ?? const <List<String>>[];
      activeExtras = extras.isEmpty ? null : extras;
      recent.clear();
      result.add(tok);
      continue;
    }
    if (tok.type == TikkunTokenType.specialEnd) {
      activeExtras = null;
      recent.clear();
      result.add(tok);
      continue;
    }
    result.add(tok);

    if (activeExtras == null || tok.type != TikkunTokenType.word) continue;
    for (final piece in _cleanStam(tok.value!).split(_spaces)) {
      if (piece.isNotEmpty) recent.add(piece);
    }
    final maxLen = activeExtras
        .map((p) => p.length)
        .reduce((a, b) => a > b ? a : b);
    while (recent.length > maxLen) {
      recent.removeAt(0);
    }
    for (final pattern in activeExtras) {
      if (_endsWith(recent, pattern)) {
        result.add(const TikkunToken(type: TikkunTokenType.segmentBreak));
        break;
      }
    }
  }
  return result;
}

/// מבטל את המעבר שאחרי כל רצף מילים מתוך `section.suppressBreaks`.
List<TikkunToken> suppressSegmentBreaks(List<TikkunToken> tokens) {
  final result = <TikkunToken>[];
  List<List<String>>? activeSuppress;
  final recent = <String>[];
  var pendingSuppress = false;

  for (final tok in tokens) {
    if (tok.type == TikkunTokenType.specialStart) {
      final list = tok.section?.suppressBreaks ?? const <List<String>>[];
      activeSuppress = list.isEmpty ? null : list;
      recent.clear();
      pendingSuppress = false;
      result.add(tok);
      continue;
    }
    if (tok.type == TikkunTokenType.specialEnd) {
      activeSuppress = null;
      recent.clear();
      pendingSuppress = false;
      result.add(tok);
      continue;
    }

    if (pendingSuppress && tok.type == TikkunTokenType.segmentBreak) {
      pendingSuppress = false;
      continue;
    }
    if (pendingSuppress && tok.type == TikkunTokenType.verseBreak) {
      pendingSuppress = false;
      result.add(
        TikkunToken(
          type: TikkunTokenType.verseBreak,
          verseNum: tok.verseNum,
          suppressFlush: true,
        ),
      );
      continue;
    }

    result.add(tok);

    if (activeSuppress == null || tok.type != TikkunTokenType.word) continue;
    for (final piece in _cleanStam(tok.value!).split(_spaces)) {
      if (piece.isNotEmpty) recent.add(piece);
    }
    final maxLen = activeSuppress
        .map((p) => p.length)
        .reduce((a, b) => a > b ? a : b);
    while (recent.length > maxLen) {
      recent.removeAt(0);
    }
    for (final pattern in activeSuppress) {
      if (_endsWith(recent, pattern)) {
        pendingSuppress = true;
        break;
      }
    }
  }
  return result;
}

/// מזיז את `special_start`/`special_end` פנימה לפי `section.trim`, כך
/// שהמילים שמחוץ לטרים יעברו עיבוד טקסט רגיל.
List<TikkunToken> applyBoundaryTrimming(List<TikkunToken> tokens) {
  final result = List<TikkunToken>.of(tokens);

  for (var i = 0; i < result.length; i++) {
    final tok = result[i];
    if (tok.type != TikkunTokenType.specialStart) continue;
    final n = tok.section?.trimStartKeepLast;
    if (n == null) continue;

    var endIdx = result.length;
    for (var j = i + 1; j < result.length; j++) {
      final t = result[j].type;
      if (t == TikkunTokenType.verseBreak ||
          t == TikkunTokenType.specialEnd ||
          t == TikkunTokenType.chapterBreak) {
        endIdx = j;
        break;
      }
    }
    final wordIndices = <int>[];
    for (var j = i + 1; j < endIdx; j++) {
      if (result[j].type == TikkunTokenType.word) wordIndices.add(j);
    }
    if (wordIndices.length <= n) continue;
    final keepFromIdx = wordIndices[wordIndices.length - n];
    final ss = result.removeAt(i);
    result.insert(keepFromIdx - 1, ss);
    i = keepFromIdx - 1;
  }

  for (var i = 0; i < result.length; i++) {
    if (result[i].type != TikkunTokenType.specialEnd) continue;
    var startIdx = -1;
    for (var j = i - 1; j >= 0; j--) {
      if (result[j].type == TikkunTokenType.specialStart) {
        startIdx = j;
        break;
      }
    }
    if (startIdx < 0) continue;
    final m = result[startIdx].section?.trimEndKeepFirst;
    if (m == null) continue;

    var lastBreak = startIdx;
    for (var j = i - 1; j > startIdx; j--) {
      final t = result[j].type;
      if (t == TikkunTokenType.verseBreak ||
          t == TikkunTokenType.chapterBreak) {
        lastBreak = j;
        break;
      }
    }
    final wordIndices = <int>[];
    for (var j = lastBreak + 1; j < i; j++) {
      if (result[j].type == TikkunTokenType.word) wordIndices.add(j);
    }
    if (wordIndices.length <= m) continue;
    final keepToIdx = wordIndices[m - 1];
    final se = result.removeAt(i);
    result.insert(keepToIdx + 1, se);
    i = keepToIdx + 1;
  }

  return result;
}
