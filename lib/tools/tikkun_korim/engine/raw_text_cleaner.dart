/// ניקוי הטקסט הגולמי שמגיע מהספרייה והפיכתו לרצף מילים עם סמני מבנה.
/// פורט נאמן של `cleanRawText` בתוסף "תיקון קוראים" (navigation.js).
library;

import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';

const Map<String, int> _gematriaValues = {
  'א': 1,
  'ב': 2,
  'ג': 3,
  'ד': 4,
  'ה': 5,
  'ו': 6,
  'ז': 7,
  'ח': 8,
  'ט': 9,
  'י': 10,
  'כ': 20,
  'ל': 30,
  'מ': 40,
  'נ': 50,
  'ס': 60,
  'ע': 70,
  'פ': 80,
  'צ': 90,
  'ק': 100,
  'ר': 200,
  'ש': 300,
  'ת': 400,
  'ך': 20,
  'ם': 40,
  'ן': 50,
  'ף': 80,
  'ץ': 90,
};

/// המרת אותיות עבריות למספר. אותיות שאינן במפה נספרות כאפס.
int gematriaToNumber(String letters) {
  var total = 0;
  for (final ch in letters.split('')) {
    total += _gematriaValues[ch] ?? 0;
  }
  return total;
}

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
  'shy': '­',
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

/// המסורת שההערה שוללת בה את הפרשה, לפי שמות העדות שבגוף ההערה.
/// המודל הוא שתי מסורות בלבד, ולכן "ספרד" ו"אשכנז" הן אותה מסורת,
/// והערה שמזכירה גם תימן מוכרעת לתימן.
TikkunTradition? _excludedTraditionOf(String note) {
  if (note.contains('תימן')) return TikkunTradition.yemen;
  if (note.contains('ספרד') || note.contains('אשכנז')) {
    return TikkunTradition.ashkenazSephard;
  }
  return null;
}

/// מנקה את טקסט ה-HTML של הספר לרצף מילים עם סמני פרק/פסוק/פרשה.
String cleanRawText(String raw) {
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
    final excluded = _excludedTraditionOf(m[2]!);
    if (excluded == null) return m[0]!;
    return ' {${m[1]}:${excluded.id}} ';
  });

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

  // קמץ קטן (U+05C7) שובר את הגופנים; מנרמלים לקמץ רגיל.
  text = text.replaceAll(_kamatzKatan, 'ָ');

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

  text = text.replaceAll(_maqaf, ' ');
  return text.replaceAll(_whitespaceRun, ' ').trim();
}
