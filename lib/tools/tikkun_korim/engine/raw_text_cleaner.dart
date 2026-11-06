/// ניקוי הטקסט הגולמי שמגיע מהספרייה והפיכתו לרצף מילים עם סמני מבנה.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';
import 'package:otzaria/utils/text/numeral_formats.dart';

const Map<String, String> _namedEntities = {
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': ' ',
  'thinsp': ' ',
  'ensp': ' ',
  'emsp': ' ',
  'ndash': '–',
  'mdash': '—',
  'hellip': '…',
  'lsquo': '‘',
  'rsquo': '’',
  'ldquo': '“',
  'rdquo': '”',
  'bull': '•',
  'middot': '·',
  'shy': '\u00ad',
  'deg': '°',
};

final RegExp _entityRe = RegExp(
  r'&(#[0-9]+|#[xX][0-9a-fA-F]+|[a-zA-Z][a-zA-Z0-9]*);',
);

/// מקביל ל-`textarea.value` בדפדפן: מפענח ישויות מספריות ואת הישויות
/// הנקובות שמופיעות בטקסטים של הספרייה. ישות לא מוכרת נשארת כמות שהיא.
String decodeHtmlEntities(String input) {
  if (!input.contains('&')) return input;
  return input.replaceAllMapped(_entityRe, (m) {
    final body = m[1]!;
    if (body.startsWith('#')) {
      final isHex = body[1] == 'x' || body[1] == 'X';
      final code = int.tryParse(
        isHex ? body.substring(2) : body.substring(1),
        radix: isHex ? 16 : 10,
      );
      if (code == null || code < 0 || code > 0x10ffff) return m[0]!;
      return String.fromCharCode(code);
    }
    return _namedEntities[body] ?? m[0]!;
  });
}

final RegExp _chapterHeading = RegExp(
  '<h2[^>]*>פרק\\s+([א-ת"׳]+)\\s*</h2>',
  caseSensitive: false,
);
final RegExp _quoteMarks = RegExp('["׳]');
final RegExp _anyHeading = RegExp(
  r'<h[1-6][^>]*>[\s\S]*?</h[1-6]>',
  caseSensitive: false,
);
final RegExp _footnoteMarker = RegExp(
  r'<sup[^>]*class="footnote-marker"[^>]*>[\s\S]*?</sup>',
  caseSensitive: false,
);
final RegExp _footnote = RegExp(
  r'<i[^>]*class="footnote"[^>]*>[\s\S]*?</i>',
  caseSensitive: false,
);

/// סמן פרשה שנשענת עליו הערת שוליים "אין פרשה בספרי ..." — המסד מציין כך
/// את הפרשיות שנוסח הכתר גורס ואינן בכל המסורות.
final RegExp _traditionParashaNote = RegExp(
  r'<span[^>]*class="mam-spi-(?:pe|samekh)"[^>]*>\{([פס])\}</span>\s*'
  r'(?:<sup[^>]*class="footnote-marker"[^>]*>[\s\S]*?</sup>\s*)?'
  r'<i[^>]*class="footnote"[^>]*>\(אין פרשה בספרי ([^)<]*)\)</i>',
);
const _variantWord =
    r'(?:<(?:big|small)>)?[א-ת](?:[א-ת\u0591-\u05bd\u05bf\u05c1\u05c2\u05c4\u05c5\u05c7]|</?(?:big|small)>)*';
const _variantNoteStart =
    r'<sup[^>]*class="footnote-marker"[^>]*>[^<]*</sup>\s*'
    r'<i[^>]*class="footnote"[^>]*>\(בספרי ';
final _leadingVariantNote = RegExp(
  r'(\s)('
  '$_variantNoteStart'
  r'(?:[^<()]|</?(?:big|small)>)+\)</i>)'
  '($_variantWord)',
);
final _traditionWordNote = RegExp(
  '((?:$_variantWord'
  r'[־\s]+)?)'
  '($_variantWord)$_variantNoteStart'
  r'([^<()]*?(?:תימן|אשכנז)) (?:נהוג לכתוב )?'
  '($_variantWord)'
  r'( [^<()]*)?\)</i>',
);
final _ashkenazMegillahNote = RegExp(
  '($_variantWord)'
  r'<sup[^>]*class="footnote-marker"[^>]*>[^<]*</sup>\s*'
  r'<i[^>]*class="footnote"[^>]*>\(במגילות אשכנז '
  '($_variantWord)'
  r'\)</i>',
);

/// בוחר את חילופי הנוסח המסומנים במקור כמנהג מגילות אשכנז.
String applyMegillahNusach(String raw, String nusach) {
  // ההערה קיימת רק במגילות.
  if (nusach != 'ashkenaz' || !raw.contains('(במגילות אשכנז ')) return raw;
  variantNoteScans++;
  return replaceBeforeSup(raw, _ashkenazMegillahNote, (m) => m[2]!);
}

/// `replaceAllMapped` לביטוי שנפתח במילים שמיד אחריהן `<sup`: התאמה יכולה
/// להתחיל רק ברצף המילים שלפני `<sup`, ולכן רק שם הביטוי מנוסה.
@visibleForTesting
String replaceBeforeSup(
  String text,
  RegExp pattern,
  String Function(Match) replace,
) {
  final out = StringBuffer();
  var copied = 0;
  for (
    var sup = text.indexOf('<sup');
    sup >= 0;
    sup = text.indexOf('<sup', sup + 1)
  ) {
    for (var i = math.max(_wordsStart(text, sup), copied); i < sup; i++) {
      final match = pattern.matchAsPrefix(text, i);
      if (match == null) continue;
      out
        ..write(text.substring(copied, i))
        ..write(replace(match));
      copied = match.end;
      break;
    }
  }
  if (copied == 0) return text;
  return (out..write(text.substring(copied))).toString();
}

const _wordTags = ['<big>', '</big>', '<small>', '</small>'];

/// תחילת רצף המילים שנגמר ב-[end]: אותיות, ניקוד, רווחים ותגי big/small —
/// בלי שום תו ASCII אחר.
int _wordsStart(String text, int end) {
  var i = end;
  while (i > 0) {
    final c = text.codeUnitAt(i - 1);
    if (c <= 0x20 || c >= 0x7F) {
      i--;
      continue;
    }
    final tag = _wordTags.indexWhere(
      (t) => i >= t.length && text.startsWith(t, i - t.length),
    );
    if (tag < 0) break;
    i -= _wordTags[tag].length;
  }
  return i;
}

/// מספר הסריקות בביטויי חילופי הנוסח.
@visibleForTesting
int variantNoteScans = 0;

final RegExp _bigTag = RegExp(r'<big[^>]*>([\s\S]*?)</big>');
final RegExp _smallTag = RegExp(r'<small[^>]*>([\s\S]*?)</small>');
final RegExp _hebrewLetter = RegExp('[א-ת]');
final RegExp _kqKThenQ = RegExp(
  r'<span[^>]*class="mam-kq-k"[^>]*>\(([^<()]+)\)[־]?</span>\s*'
  r'<span[^>]*class="mam-kq-q"[^>]*>\[([^<\[\]]+)\]</span>',
);
final RegExp _kqQThenK = RegExp(
  r'<span[^>]*class="mam-kq-q"[^>]*>\[([^<\[\]]+)\]</span>\s*'
  r'<span[^>]*class="mam-kq-k"[^>]*>\(([^<()]+)\)[־]?</span>',
);
final RegExp _kqKOnly = RegExp(
  r'<span[^>]*class="mam-kq-k"[^>]*>\(([^<()]+)\)[־]?</span>',
);
final RegExp _kqQOnly = RegExp(
  r'<span[^>]*class="mam-kq-q"[^>]*>\[([^<\[\]]+)\]</span>',
);
final RegExp _brTag = RegExp(r'<br\s*/?>', caseSensitive: false);
final RegExp _anyTag = RegExp(r'<[^>]*>?', multiLine: true);
final RegExp _kamatzKatan = RegExp('ׇ');
final RegExp _holamHaserForVav = RegExp('ֺ');
final RegExp _nbspRun = RegExp(' {4,}');
final RegExp _parenThenBracket = RegExp(
  r'\(([^()\[\]]+?)\)(?:\s|&nbsp;|&thinsp;)*\[([^()\[\]]+?)\]',
);
final RegExp _bracketThenParen = RegExp(
  r'\[([^()\[\]]{2,}?)\](?:\s|&nbsp;|&thinsp;)*\(([^()\[\]]{2,}?)\)',
);
final RegExp _verseMark = RegExp('\\(([א-ת"׳]+)\\)');
final RegExp _maqaf = RegExp('־');
final RegExp _whitespaceRun = RegExp(r'\s+');

final String _kqStart = String.fromCharCode(kKetivQereStart);
final String _kqSep = String.fromCharCode(kKetivQereSep);
final String _kqEnd = String.fromCharCode(kKetivQereEnd);
final String _zeiraStart = String.fromCharCode(kZeiraStart);
final String _zeiraEnd = String.fromCharCode(kZeiraEnd);
final String _rabatiStart = String.fromCharCode(kRabatiStart);
final String _rabatiEnd = String.fromCharCode(kRabatiEnd);

String _tightenWord(String s) =>
    s.trim().replaceAll(_whitespaceRun, '').replaceAll(_maqaf, '');

/// ספרד ואשכנז משויכות לאותה מסורת; אזכור תימן גובר על שתיהן.
TikkunTradition? _traditionOf(String note) {
  if (note.contains('תימן')) return TikkunTradition.yemen;
  if (note.contains('ספרד') || note.contains('אשכנז')) {
    return TikkunTradition.ashkenazSephard;
  }
  return null;
}

/// מנקה את טקסט ה-HTML של הספר לרצף מילים עם סמני פרק/פסוק/פרשה.
String cleanRawText(String raw, {TikkunTradition? tradition}) {
  var text = raw.replaceAllMapped(_chapterHeading, (m) {
    final n = gematriaToNumber(m[1]!.replaceAll(_quoteMarks, ''));
    return n > 0 ? ' CHAPTERMARK${n}MARK ' : ' ';
  });

  text = text.replaceAll(_anyHeading, ' ');

  // ה-bridge עלול לחתוך באמצע כותרת פותחת; חותכים עד סוף התגית הסוגרת.
  final head = text.substring(0, text.length < 300 ? text.length : 300);
  final lastCloseH = head.lastIndexOf('</h');
  if (lastCloseH >= 0) {
    final tagEnd = text.indexOf('>', lastCloseH);
    if (tagEnd >= 0 && tagEnd < 300) {
      text = text.substring(tagEnd + 1);
    }
  }

  // חייב לרוץ לפני מחיקת ההערות — הן הנתון היחיד שמבדיל בין המסורות.
  text = text.replaceAllMapped(_traditionParashaNote, (m) {
    final excluded = _traditionOf(m[2]!);
    if (excluded == null) return m[0]!;
    return ' {${m[1]}:${excluded.id}} ';
  });

  // _leadingVariantNote סורק כל אות בספר, ורוב ספרי הנביאים בלי הערת חילוף.
  if (tradition != null && text.contains('(בספרי ')) {
    variantNoteScans++;
    // יש הערות חילוף לפני המילה; מאחדים את מקומן לפני בחירת החלופה.
    text = text.replaceAllMapped(
      _leadingVariantNote,
      (m) => '${m[1]}${m[3]}${m[2]}',
    );
    text = replaceBeforeSup(text, _traditionWordNote, (m) {
      if (_traditionOf(m[3]!) != tradition) return '${m[1]}${m[2]}';
      final prefix = m[5]?.trim() == 'בתיבה אחת' ? '' : m[1]!;
      return '$prefix${m[4]}';
    });
  }

  text = text.replaceAll(_footnoteMarker, ' ');
  text = text.replaceAll(_footnote, ' ');
  text = text.replaceAllMapped(_bigTag, (m) {
    final content = m[1]!;
    if (_hebrewLetter.hasMatch(content)) {
      return '$_rabatiStart$content$_rabatiEnd';
    }
    return content;
  });
  text = text.replaceAllMapped(_smallTag, (m) {
    final content = m[1]!;
    if (_hebrewLetter.hasMatch(content)) {
      return '$_zeiraStart$content$_zeiraEnd';
    }
    return content;
  });

  text = text.replaceAllMapped(_kqKThenQ, (m) {
    final k = _tightenWord(m[1]!);
    final q = _tightenWord(m[2]!);
    return ' $_kqStart$k$_kqSep$q$_kqEnd ';
  });
  text = text.replaceAllMapped(_kqQThenK, (m) {
    final q = _tightenWord(m[1]!);
    final k = _tightenWord(m[2]!);
    return ' $_kqStart$k$_kqSep$q$_kqEnd ';
  });
  // כתיב בלי קרי / קרי בלי כתיב — הסמנים נשמרים עם צד ריק, כמו במקור.
  text = text.replaceAllMapped(
    _kqKOnly,
    (m) => ' $_kqStart${_tightenWord(m[1]!)}$_kqSep$_kqEnd ',
  );
  text = text.replaceAllMapped(
    _kqQOnly,
    (m) => ' $_kqStart$_kqSep${_tightenWord(m[1]!)}$_kqEnd ',
  );

  text = text.replaceAll(_brTag, ' ');
  text = text.replaceAll(_anyTag, ' ');

  text = decodeHtmlEntities(text);

  // קמץ קטן (U+05C7) וחולם חסר לוי"ו (U+05BA) חסרים בגופנים ונופלים לגופן
  // חלופי; מנרמלים לקמץ ולחולם רגילים.
  text = text.replaceAll(_kamatzKatan, 'ָ');
  text = text.replaceAll(_holamHaserForVav, 'ֹ');

  text = text.replaceAll(_nbspRun, ' SEGBREAKMARK ');

  text = text.replaceAllMapped(_parenThenBracket, (m) {
    final k = _tightenWord(m[1]!);
    final q = _tightenWord(m[2]!);
    return ' $_kqStart$k$_kqSep$q$_kqEnd ';
  });
  text = text.replaceAllMapped(_bracketThenParen, (m) {
    final q = _tightenWord(m[1]!);
    final k = _tightenWord(m[2]!);
    return ' $_kqStart$k$_kqSep$q$_kqEnd ';
  });

  text = text.replaceAllMapped(_verseMark, (m) {
    final inner = m[1]!;
    final n = gematriaToNumber(inner.replaceAll(_quoteMarks, ''));
    return n > 0 ? ' VERSEMARK${n}MARK ' : ' ';
  });

  // המקף שובר תיבה לשתיים, כי בספר תורה אין מקף; בטור המנוקד הוא נשאר
  // בסוף התיבה הראשונה, ו-stripNikud מסיר אותו מן הסת"ם.
  text = text.replaceAll(_maqaf, '־ ');
  return text.replaceAll(_whitespaceRun, ' ').trim();
}
