/// מבנה ספר מקרא כפי ששמור במסד: שורת ספר (`<h1>`), שורת פרק (`<h2>`) ושורת
/// פסוק שמספרו באותיות בתחילתה (`(א) ...`), עם פתוחה/סתומה בסוף הפסוק.
///
/// במצב קריאה רציף של ספרי מקרא אין חלוקת פרקים בגוף הטקסט: כותרות הפרקים
/// ומספרי הפסוקים עוברים לגליון הצדדי, והפסקה נשברת רק בפתוחה ובשם ספר.
/// כמו כל מצב רציף, זה לתצוגה בלבד — הנוסח, השורות והאינדקסים אינם משתנים.
library;

import 'package:otzaria/tools/tikkun_korim/data/aliyot_index.g.dart';
import 'package:otzaria/tools/tikkun_korim/data/tanach_structure.g.dart';
import 'package:otzaria/utils/text/numeral_formats.dart';

enum MikraLineKind { bookTitle, chapterTitle, verse, other }

/// ציון הגליון של שורת פסוק: הפרק מופיע רק בפסוק הראשון בפרק.
class MikraGutterLabel {
  const MikraGutterLabel({this.chapter, required this.verse});

  /// הפרק באותיות, או null כשהפסוק אינו ראשון בפרק.
  final String? chapter;
  final String verse;

  @override
  bool operator ==(Object other) =>
      other is MikraGutterLabel &&
      other.chapter == chapter &&
      other.verse == verse;

  @override
  int get hashCode => Object.hash(chapter, verse);

  @override
  String toString() => chapter == null ? verse : '$chapter:$verse';
}

/// ציון החלוקה המסורתית בגליון: שם הפרשה (בפסוק הראשון בה) והעלייה.
class MikraDivisionLabel {
  const MikraDivisionLabel({this.parasha, required this.aliyah});

  /// שם הפרשה, רק בעלייה הראשונה שלה.
  final String? parasha;

  /// שם העלייה: ראשון, שני, שלישי ...
  final String aliyah;

  @override
  bool operator ==(Object other) =>
      other is MikraDivisionLabel &&
      other.parasha == parasha &&
      other.aliyah == aliyah;

  @override
  int get hashCode => Object.hash(parasha, aliyah);

  @override
  String toString() => parasha == null ? aliyah : '$parasha $aliyah';
}

class MikraLine {
  const MikraLine({
    required this.kind,
    this.chapter = 0,
    this.verse = 0,
    this.petucha = false,
    this.setuma = false,
  });

  final MikraLineKind kind;
  final int chapter;
  final int verse;

  /// הפסוק מסתיים בפרשה פתוחה: השורה הבאה נפתחת בפסקה חדשה.
  final bool petucha;

  /// הפסוק מסתיים בפרשה סתומה: ריווח ברצף, בלי שבירת שורה.
  final bool setuma;
}

final RegExp _tags = RegExp(r'<[^>]*>');
final RegExp _versePrefixText = RegExp(
  "^\\s*\\(([\\u05D0-\\u05EA'\"\\u05F3\\u05F4]{1,5})\\)\\s*",
);
final RegExp _versePrefixHtml = RegExp(
  "^((?:\\s*<[^>]+>)*)\\s*\\([\\u05D0-\\u05EA'\"\\u05F3\\u05F4]{1,5}\\)\\s*",
);
final RegExp _chapterTitle = RegExp(
  "^\\s*\\u05E4\\u05E8\\u05E7\\s+([\\u05D0-\\u05EA'\"\\u05F3\\u05F4]{1,5})\\s*\$",
);

/// ערך גימטרי של מספר באותיות ("יא" → 11); 0 אם אינו מספר תקין.
int parseHebrewNumeral(String letters) {
  const values = {
    'א': 1, 'ב': 2, 'ג': 3, 'ד': 4, 'ה': 5, 'ו': 6, 'ז': 7, 'ח': 8, 'ט': 9, //
    'י': 10, 'כ': 20, 'ל': 30, 'מ': 40, 'נ': 50, 'ס': 60, 'ע': 70, 'פ': 80,
    'צ': 90, 'ק': 100, 'ר': 200, 'ש': 300, 'ת': 400,
  };
  var total = 0;
  for (final rune in letters.runes) {
    final value = values[String.fromCharCode(rune)];
    if (value == null) continue;
    total += value;
  }
  return total;
}

/// הסרת מספר הפסוק `(א)` מתחילת שורה, בלי לגעת בתגיות שלפניו.
String stripMikraVersePrefix(String html) =>
    html.replaceFirstMapped(_versePrefixHtml, (match) => match.group(1) ?? '');

final RegExp _petuchaMark = RegExp(
  r'<span class="mam-spi-pe">(.*?)</span>(?:\s*<br\s*/?>)?',
  dotAll: true,
);

/// הערת המהדורה: הסימן וההערה שאחריו.
const String _footnote =
    r'<sup class="footnote-marker">[^<]*</sup><i class="footnote">(?:(?!</i>)[\s\S])*</i>';
final RegExp _footnotes = RegExp(_footnote);

/// פתוחה בסוף הפסוק — רק היא חותכת את הפסקה אחרי השורה. אחריה מותרות רק הערות
/// המהדורה, שהן על הפתוחה עצמה (שמות לג, כג; ויקרא ז, כא ו-כז). פתוחה באמצע
/// פסוק («פסקא באמצע פסוק», 24 מקומות) שוברת את השורה בתוך הפסוק.
final RegExp _petuchaAtEnd = RegExp(
  r'<span class="mam-spi-pe">[^<]*</span>\s*(?:<br\s*/?>)?\s*(?:' +
      _footnote +
      r'\s*)*$',
);

/// אחרי [m] אין עוד כתוב בשורה: רק רווחים והערות המהדורה.
bool mikraBlankAfter(Match m) =>
    m.input.substring(m.end).replaceAll(_footnotes, '').trim().isEmpty;

final RegExp _setumaMark = RegExp(
  r'<span class="mam-spi-samekh">(.*?)</span>(?:\s*<br\s*/?>)?',
  dotAll: true,
);

/// צבע סימוני {פ} ו-{ס} בגוף הכתוב.
const String kMikraMarkColor = '#8a8579';

/// ריווח הסתומה: ארבעה רווחי em (כתשע אותיות) לפני סימון {ס}.
const String _setumaGap = '    ';

/// שורת מקרא לתצוגה רציפה: בלי `(א)`, וסימוני הפרשיות באפור מוקטן. פתוחה בסוף
/// הפסוק אינה שוברת שורה בעצמה — הפריסה חותכת את הפסקה אחריה; פתוחה באמצע
/// פסוק שומרת את שבירת השורה שבמסד. הסתומה היא ריווח ברצף.
String mikraDisplayHtml(String html) {
  var out = stripMikraVersePrefix(html);
  out = out.replaceAllMapped(
    _petuchaMark,
    // פתוחה באמצע פסוק: שבירת השורה נשארת, וההמשך נפתח בשורה חדשה.
    (m) =>
        '<small><span style="color:$kMikraMarkColor"> ${m.group(1)}</span></small>'
        '${mikraBlankAfter(m) ? '' : '<br>'}',
  );
  out = out.replaceAllMapped(
    _setumaMark,
    (m) =>
        '<small><span style="color:$kMikraMarkColor"> ${m.group(1)}</span></small>$_setumaGap',
  );
  return out;
}

class MikraStructure {
  MikraStructure._(this.lines, this._labels, this._divisions);

  final List<MikraLine> lines;
  final Map<int, MikraGutterLabel> _labels;
  final Map<int, MikraDivisionLabel> _divisions;

  /// ספר מקרא מזוהה כשכל שורה היא כותרת או פסוק, ויש בו כותרות פרק.
  /// מחזיר null לכל ספר אחר — והתצוגה נשארת כמות שהיא.
  ///
  /// [bookTitle] — שם ספר בתורה ("בראשית"): רק בו יש פרשות ועליות בגליון.
  static MikraStructure? parse(List<String> content, {String? bookTitle}) {
    if (content.length < 3) return null;
    final lines = <MikraLine>[];
    final labels = <int, MikraGutterLabel>{};
    var chapter = 0;
    var chapters = 0;
    var verses = 0;
    var chapterAnnounced = true;
    for (var i = 0; i < content.length; i++) {
      final raw = content[i];
      final head = raw.trimLeft();
      if (head.startsWith('<h1')) {
        lines.add(const MikraLine(kind: MikraLineKind.bookTitle));
        continue;
      }
      final text = raw.replaceAll(_tags, '').replaceAll('&nbsp;', ' ').trim();
      if (head.startsWith('<h2')) {
        final match = _chapterTitle.firstMatch(text);
        chapter = match == null
            ? chapter + 1
            : parseHebrewNumeral(match.group(1)!);
        chapters++;
        chapterAnnounced = false;
        lines.add(
          MikraLine(kind: MikraLineKind.chapterTitle, chapter: chapter),
        );
        continue;
      }
      final match = _versePrefixText.firstMatch(text);
      if (match == null) {
        lines.add(const MikraLine(kind: MikraLineKind.other));
        continue;
      }
      final verse = parseHebrewNumeral(match.group(1)!);
      verses++;
      lines.add(
        MikraLine(
          kind: MikraLineKind.verse,
          chapter: chapter,
          verse: verse,
          petucha: _petuchaAtEnd.hasMatch(raw),
          setuma: raw.contains('mam-spi-samekh'),
        ),
      );
      labels[i] = MikraGutterLabel(
        chapter: chapterAnnounced ? null : toHebrewNumeral(chapter),
        verse: toHebrewNumeral(verse),
      );
      chapterAnnounced = true;
    }
    // כל שורה היא ספר, פרק או פסוק; אחרת זה אינו נוסח מקרא במבנה הזה.
    if (chapters == 0 || verses == 0) return null;
    if (lines.any((line) => line.kind == MikraLineKind.other)) return null;
    return MikraStructure._(
      List<MikraLine>.unmodifiable(lines),
      Map<int, MikraGutterLabel>.unmodifiable(labels),
      Map<int, MikraDivisionLabel>.unmodifiable(
        _divisionsFor(lines, bookTitle),
      ),
    );
  }

  MikraLineKind kindAt(int line) =>
      line >= 0 && line < lines.length ? lines[line].kind : MikraLineKind.other;

  /// שורות הספר — הן היחידות ששוברות את הרצף.
  late final List<int> bookTitleLines = [
    for (var i = 0; i < lines.length; i++)
      if (lines[i].kind == MikraLineKind.bookTitle) i,
  ];

  /// שורות פסוק שאחריהן נחתכת הפסקה (פרשה פתוחה).
  late final List<int> paragraphEndLines = [
    for (var i = 0; i < lines.length; i++)
      if (lines[i].petucha) i,
  ];

  /// כותרת פרק אינה מוצגת בגוף הטקסט; מספרה עובר לגליון.
  bool isHiddenLine(int line) => kindAt(line) == MikraLineKind.chapterTitle;

  /// ציון הגליון של שורה, או null לשורה שאינה פסוק.
  MikraGutterLabel? gutterLabelAt(int line) => _labels[line];

  /// פרשה ועלייה שמתחילות בשורה, או null.
  MikraDivisionLabel? divisionAt(int line) => _divisions[line];

  late final List<int> _divisionStarts = _divisions.keys.toList()..sort();

  /// הפרשה והעלייה שהשורה [line] בתוכן; null לפני העלייה הראשונה, ובספר
  /// שאין בו פרשות (שאינו בתורה).
  ({String parasha, String aliyah})? citationAt(int line) {
    String? parasha;
    String? aliyah;
    for (final start in _divisionStarts) {
      if (start > line) break;
      final label = _divisions[start]!;
      aliyah = label.aliyah;
      parasha = label.parasha ?? parasha;
    }
    if (parasha == null || aliyah == null) return null;
    return (parasha: parasha, aliyah: aliyah);
  }

  /// פתוחה/סתומה בשורה — לרינדור (שבירה/ריווח).
  bool petuchaAt(int line) =>
      line >= 0 && line < lines.length && lines[line].petucha;
  bool setumaAt(int line) =>
      line >= 0 && line < lines.length && lines[line].setuma;
}

/// הפרשות והעליות של ספר בתורה, לפי טבלת תיקון קוראים: שורת הפסוק שבה כל עלייה
/// מתחילה. פרשות מחוברות ומפטיר אינן מסומנות (הן חוזרות על פסוקים קיימים).
Map<int, MikraDivisionLabel> _divisionsFor(
  List<MikraLine> lines,
  String? bookTitle,
) {
  final book = bookTitle == null ? null : kAliyotIndex[bookTitle];
  if (book is! Map) return const {};
  final firstLineOfVerse = <int, int>{};
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.kind != MikraLineKind.verse) continue;
    firstLineOfVerse.putIfAbsent(line.chapter * 1000 + line.verse, () => i);
  }
  final result = <int, MikraDivisionLabel>{};
  book.forEach((parasha, aliyot) {
    if (parasha is! String || parasha.contains('-') || aliyot is! List) return;
    var first = true;
    for (final aliya in aliyot) {
      if (aliya is! Map) continue;
      final name = kAliyaDisplayNames[aliya['aliya']];
      if (name == null || name == 'מפטיר') continue;
      final parts = '${aliya['from']}'.split(':');
      if (parts.length != 2) continue;
      final key =
          (int.tryParse(parts[0]) ?? 0) * 1000 + (int.tryParse(parts[1]) ?? 0);
      final line = firstLineOfVerse[key];
      if (line == null) continue;
      result[line] = MikraDivisionLabel(
        parasha: first ? parasha : null,
        aliyah: name,
      );
      first = false;
    }
  });
  return result;
}
