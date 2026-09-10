/// החלפת מילות עשרת הדברות בצורת הטעמים הנבחרת. במסד שתי מערכות הטעמים
/// ממוזגות על אותן אותיות, והנכס שב-`data/decalogue_taamim.g.dart` מפריד ביניהן.
library;

import 'package:flutter/foundation.dart';
import 'package:otzaria/tools/tikkun_korim/data/tikkun_data.dart';
import 'package:otzaria/tools/tikkun_korim/engine/tokenizer.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';

/// מקף ורווח נחלקים אחרת בין שתי המערכות; `cleanRawText` ממילא הפך כל מקף
/// לרווח, ולכן מילה בנכס עשויה לכסות כמה אסימונים.
final RegExp _wordSeparator = RegExp('[־\\s]+');

/// CGJ בא רק בצורה המשולבת, שבה הוא שומר על סדר הטעמים משתי המערכות; הוא
/// חסר רוחב ואינו חלק מזהות המילה.
final RegExp _joiner = RegExp('\u034F');

List<String> _parts(String word) =>
    word.split(_wordSeparator).where((p) => p.isNotEmpty).toList();

String _consonants(String word) => stripNikud(word).replaceAll(_joiner, '');

/// מחליף את מילות עשרת הדברות שב-[tokens] בצורת [taam]. מחזיר את [tokens]
/// עצמו כשאין מה להחליף.
///
/// ההתאמה נעשית מילה-במילה לפי העיצורים, ולכן עמודת הסת"ם והעימוד אינם
/// משתנים, וסימני הפרשיות והאותיות הגדולות נשארים במקומם.
List<TikkunToken> applyDecalogueTaam(
  List<TikkunToken> tokens,
  String hebrewBookName,
  TikkunDecalogueTaam taam,
) {
  if (taam == TikkunDecalogueTaam.merged) return tokens;
  final place = TikkunData.decaloguePlaceOf(hebrewBookName);
  if (place == null) return tokens;

  final wordIdx = <int>[];
  var chapter = 0;
  var verse = 0;
  for (var i = 0; i < tokens.length; i++) {
    final tok = tokens[i];
    switch (tok.type) {
      case TikkunTokenType.chapterBreak:
        chapter = tok.chapterNum!;
      case TikkunTokenType.verseBreak:
        verse = tok.verseNum!;
      case TikkunTokenType.word:
        if (chapter == place.chapter &&
            verse >= place.fromVerse &&
            verse <= place.toVerse) {
          wordIdx.add(i);
        }
      default:
        break;
    }
  }
  if (wordIdx.isEmpty) return tokens;

  final consonants = [
    for (final i in wordIdx) _consonants(tokens[i].value!),
  ];
  final out = List<TikkunToken>.of(tokens);
  var pos = 0;
  var skipped = 0;

  for (final word in place.words) {
    final target = _parts(word.merged).map(_consonants).toList();
    final replacement = _parts(word.formFor(taam));
    var found = -1;
    for (var j = pos; j + target.length <= consonants.length; j++) {
      var ok = true;
      for (var k = 0; k < target.length; k++) {
        if (consonants[j + k] != target[k]) {
          ok = false;
          break;
        }
      }
      if (ok) {
        found = j;
        break;
      }
    }
    if (found < 0) {
      skipped++;
      continue;
    }
    pos = found + target.length;
    if (replacement.length != target.length) {
      skipped++;
      continue;
    }
    for (var k = 0; k < target.length; k++) {
      out[wordIdx[found + k]] = TikkunToken.word(replacement[k]);
    }
  }

  if (skipped > 0) {
    debugPrint(
      'tikkun: decalogue taam ${taam.id} — $skipped of ${place.words.length} '
      'words left unchanged in ${place.bookName}',
    );
  }
  return out;
}
