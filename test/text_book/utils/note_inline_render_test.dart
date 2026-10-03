import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/utils/note_anchor_utils.dart';
import 'package:otzaria/text_book/utils/inline_notes_utils.dart';
import 'package:otzaria/text_book/utils/inline_section_markers.dart';
import 'package:otzaria/book_common/utils/link_anchor_markers.dart';
import 'package:otzaria/text_book/utils/note_inline_render.dart';
import 'package:otzaria/text_book/utils/numbered_note_markers.dart';

PersonalNote _note({
  String? anchorText,
  String? anchorPrefix,
  String? anchorSuffix,
  int? anchorStart,
  int? anchorEnd,
}) {
  final now = DateTime(2026, 1, 1);
  return PersonalNote(
    id: 'n1',
    bookId: 'ספר',
    lineNumber: 1,
    displayTitle: anchorText,
    anchorText: anchorText,
    anchorPrefix: anchorPrefix,
    anchorSuffix: anchorSuffix,
    anchorStart: anchorStart,
    anchorEnd: anchorEnd,
    lastKnownLineNumber: null,
    status: PersonalNoteStatus.located,
    content: 'תוכן',
    contentPlain: 'תוכן',
    contentFormat: PersonalNoteContentFormat.plain,
    createdAt: now,
    updatedAt: now,
  );
}

Link _inlineLink(int start, int end) => Link(
  heRef: 'יעד',
  index1: 1,
  path2: 'ספר יעד.txt',
  index2: 3,
  connectionType: 'commentary',
  start: start,
  end: end,
);

final RegExp _tagRegExp = RegExp(r'<(/?)([a-zA-Z0-9]+)\b[^>]*?(/?)>');

// עומק הקינון המרבי של <a>, ובדיקה שהקינון תקין.
int _maxAnchorDepthOfWellFormed(String html) {
  final stack = <String>[];
  var maxDepth = 0;
  for (final m in _tagRegExp.allMatches(html)) {
    final name = m.group(2)!.toLowerCase();
    if (name == 'br' || m.group(3)!.isNotEmpty) continue;
    if (m.group(1)!.isEmpty) {
      stack.add(name);
      final depth = stack.where((t) => t == 'a').length;
      if (depth > maxDepth) maxDepth = depth;
    } else {
      expect(stack, isNotEmpty, reason: 'תגית סגירה בלי פתיחה: $html');
      expect(stack.removeLast(), name, reason: 'קינון מוצלב: $html');
    }
  }
  expect(stack, isEmpty, reason: 'תגיות לא נסגרו: $html');
  return maxDepth;
}

void main() {
  const color = Color(0xFF1A2B3C);
  const noteOpen =
      '<a href="otzaria://note?line=3" style="text-decoration: underline; '
      'text-decoration-style: dotted; text-decoration-color: #1a2b3c; '
      'color: currentcolor;">';
  const linkOpen =
      '<a href="otzaria://inline-link?path=%D7%A1%D7%A4%D7%A8%20%D7%99%D7%A2%D7%93.txt'
      '&index=3&ref=%D7%99%D7%A2%D7%93" style="text-decoration: underline;">';

  // כסדר מסכי הקריאה: קישורי inline, הזרקות נוספות, הערות.
  String render(
    String raw, {
    List<PersonalNote> notes = const [],
    List<Link> links = const [],
    String Function(String html)? transform,
    int lineIndex0 = 3,
  }) {
    var html = injectInlineLinks(raw, links);
    if (transform != null) html = transform(html);
    return buildAnnotatedLineHtml(
      rawLine: html,
      sourceLine: raw,
      notesForLine: notes,
      lineIndex0: lineIndex0,
      underlineColor: color,
    );
  }

  test('הערת מילים עוטפת רק את הביטוי בקישור otzaria://note', () {
    const raw = 'וַיֹּאמֶר יְהוָה אֶל מֹשֶׁה לֵּאמֹר';
    final html = buildAnnotatedLineHtml(
      rawLine: raw,
      notesForLine: [_note(anchorText: 'אל משה')],
      lineIndex0: 4,
      underlineColor: color,
    );
    expect(html.contains('href="otzaria://note?line=4"'), isTrue);
    expect(html.contains('#1a2b3c'), isTrue);
    // המילים שלפני הביטוי לא נמצאות בתוך תגית ה-<a>.
    final aStart = html.indexOf('<a ');
    expect(html.substring(0, aStart).contains('וַיֹּאמֶר'), isTrue);
  });

  test('הערת-שורה-שלמה עוטפת את כל השורה', () {
    const raw = 'שורה שלמה ללא בחירה';
    final html = buildAnnotatedLineHtml(
      rawLine: raw,
      notesForLine: [_note()],
      lineIndex0: 0,
      underlineColor: color,
    );
    expect(html.startsWith('<a href="otzaria://note?line=0"'), isTrue);
    expect(html.endsWith('</a>'), isTrue);
  });

  test('ללא הערות מחזיר את הטקסט ללא שינוי', () {
    const raw = 'טקסט רגיל';
    final html = buildAnnotatedLineHtml(
      rawLine: raw,
      notesForLine: const [],
      lineIndex0: 0,
      underlineColor: color,
    );
    expect(html, raw);
  });

  test('הערת-שורה-שלמה לא בולעת קישור inline באותה שורה', () {
    const raw = 'אבגד הוזח טיכל';
    // קישור inline על "הוזח" (אינדקסים 5..9).
    final html = render(raw, notes: [_note()], links: [_inlineLink(5, 9)]);
    // הקישור נשמר שלם.
    expect(html.contains('otzaria://inline-link'), isTrue);
    expect(html.contains('>הוזח</a>'), isTrue);
    // וגם סימוני ההערה קיימים סביבו (לפני ואחרי).
    expect(html.contains('otzaria://note?line=3'), isTrue);
    expect(_maxAnchorDepthOfWellFormed(html), 1);
  });

  test('ביטוי שלא נמצא נופל לסימון כל השורה', () {
    const raw = 'אבג דהו זחט';
    final html = buildAnnotatedLineHtml(
      rawLine: raw,
      notesForLine: [_note(anchorText: 'מילה שאינה קיימת')],
      lineIndex0: 2,
      underlineColor: color,
    );
    expect(html.startsWith('<a href="otzaria://note?line=2"'), isTrue);
    expect(html.endsWith('</a>'), isTrue);
  });

  test('טווח שחוצה גבול תגית מפוצל ולא יוצר HTML מוצלב (תרחיש שו"ע)', () {
    // כותרת סעיף ב-<b> מופרדת מהגוף ב-<br>; בחירה שחוצה אותו מסומנת בשני
    // קטעי <a> תקינים, לא ב-<a> אחד שחוצה את </b>.
    const raw = '<b>ובו ט סעיפים:</b><br>יתגבר כארי';
    final html = buildAnnotatedLineHtml(
      rawLine: raw,
      notesForLine: [_note(anchorText: 'סעיפים: יתגבר')],
      lineIndex0: 0,
      underlineColor: color,
    );
    // ה-<a> נסגר לפני </b> ולפני <br> — אין mis-nesting.
    expect(html.contains('סעיפים:</a></b>'), isTrue);
    expect(html.contains('<br><a '), isTrue);
    expect(html.contains('>יתגבר</a>'), isTrue);
    // אין <a> בודד שבולע את </b>.
    expect(html.contains('סעיפים:</b>'), isFalse);
  });

  test('טווח עם תגיות מאוזנות פנימיות נשאר ב-<a> רציף אחד', () {
    // סימוני מפרשים ריקים (<i ...></i>) של שו"ע מאוזנים — לא מפצלים סביבם.
    const raw = 'מעורר <i data-commentator="x"></i>השחר';
    final html = buildAnnotatedLineHtml(
      rawLine: raw,
      notesForLine: [_note(anchorText: 'מעורר השחר')],
      lineIndex0: 0,
      underlineColor: color,
    );
    // עטיפה אחת רציפה שכוללת את התגית הריקה בתוכה.
    expect('<a '.allMatches(html).length, 1);
    expect(html.contains('<i data-commentator="x"></i>השחר</a>'), isTrue);
  });

  group('שורה ללא סמנים — פלט זהה לקודם', () {
    test('הערת-שורה-שלמה סביב קישור inline', () {
      expect(
        render('abcd efgh ijkl', notes: [_note()], links: [_inlineLink(5, 9)]),
        '${noteOpen}abcd </a>${linkOpen}efgh</a>$noteOpen ijkl</a>',
      );
    });

    test('הערת מילים שחופפת לקישור inline', () {
      expect(
        render(
          'abcd efgh ijkl mnop',
          notes: [_note(anchorText: 'efgh ijkl')],
          links: [_inlineLink(5, 9)],
        ),
        'abcd ${linkOpen}efgh</a>$noteOpen ijkl</a> mnop',
      );
    });

    test('קישור inline שחוצה גבול תגית, והערה אחריו', () {
      expect(
        render(
          '<b>abcd efgh</b> ijkl mnop',
          notes: [_note(anchorText: 'ijkl')],
          links: [_inlineLink(8, 20)],
        ),
        '<b>abcd ${linkOpen}efgh</a></b>$linkOpen ijk</a>${noteOpen}l</a> mnop',
      );
    });

    test('קישורי inline בלי הערות', () {
      expect(
        render(
          'abcd efgh ijkl',
          links: [_inlineLink(0, 4), _inlineLink(10, 14)],
        ),
        '${linkOpen}abcd</a> efgh ${linkOpen}ijkl</a>',
      );
    });
  });

  group('שורה עם סמני-מספר', () {
    const raw = 'אבגד (9) הוזח טיכל';
    String markers(String html) =>
        addNumberedNoteMarkerLinks(html, lineIndex: 3);
    const marker =
        '<a class="numbered-note-marker" '
        'href="otzaria://note-marker?line=3&num=9">(9)</a>';

    test('הערת מילים מסומנת', () {
      final html = render(
        raw,
        notes: [_note(anchorText: 'טיכל')],
        transform: markers,
      );
      expect(html, contains(marker));
      expect(html, contains('$noteOpenטיכל</a>'));
      expect(_maxAnchorDepthOfWellFormed(html), 1);
    });

    test('הערת-שורה-שלמה מתפצלת סביב הסמן — בלי <a> מקונן', () {
      final html = render(raw, notes: [_note()], transform: markers);
      expect(html, contains('otzaria://note?line=3'));
      expect(html, contains(marker));
      expect(html, '$noteOpenאבגד </a>$marker$noteOpen הוזח טיכל</a>');
      expect(_maxAnchorDepthOfWellFormed(html), 1);
    });

    test('קישור inline אחרי הסמן נוחת על המילה הנכונה', () {
      final html = render(
        raw,
        notes: [_note()],
        links: [_inlineLink(9, 13)],
        transform: markers,
      );
      expect(html, contains(marker));
      expect(html, contains('$linkOpenהוזח</a>'));
      expect(_maxAnchorDepthOfWellFormed(html), 1);
    });

    test('סמן בתוך קישור inline לא נעטף שוב', () {
      final html = render(raw, links: [_inlineLink(5, 13)], transform: markers);
      expect(html, contains('$linkOpen(9) הוזח</a>'));
      expect(html, isNot(contains('numbered-note-marker')));
      expect(_maxAnchorDepthOfWellFormed(html), 1);
    });
  });

  test('הערה מוטמעת (book-note) בשורה — ההערה האישית סביבה, לא מקוננת', () {
    const raw =
        'אבגד<sup class="footnote-marker">1</sup>'
        '<i class="footnote">גוף</i> הוזח';
    final html = render(
      raw,
      notes: [_note()],
      transform: (h) => addInlineNotePreviewLinks(h, lineIndex: 3),
    );
    expect(html, contains('otzaria://book-note?line=3'));
    expect(html, contains('otzaria://note?line=3'));
    expect(_maxAnchorDepthOfWellFormed(html), 1);
  });

  test('קישור inline נשאר במקומו אחרי סמן חלוקה מוקדם', () {
    const raw = 'אבגד הוזח טיכל';
    final html = render(
      raw,
      notes: [_note(anchorText: 'טיכל')],
      links: [_inlineLink(5, 9)],
      transform: (h) => prependSectionMarker(h, 'א'),
    );
    expect(html, startsWith('<b>[א]</b> אבגד $linkOpenהוזח</a> '));
    expect(html, endsWith('$noteOpenטיכל</a>'));
  });

  test('הערה על מופע חוזר נשארת במופע שנבחר אחרי הזרקת קישור', () {
    final raw = List.filled(30, 'אבג').join(' ');
    final selected = computeAnchorForSelection(
      rawLine: raw,
      selectedText: 'אבג',
      selectionColumnHint: 52,
    )!;
    final html = render(
      raw,
      notes: [
        _note(
          anchorText: 'אבג',
          anchorPrefix: selected.prefix,
          anchorSuffix: selected.suffix,
          anchorStart: selected.start,
          anchorEnd: selected.end,
        ),
      ],
      links: [_inlineLink(0, 3)],
    );

    final noteStart = html.indexOf(noteOpen);
    expect(noteStart, greaterThan(0));
    expect('אבג'.allMatches(html.substring(0, noteStart)).length, 13);
    expect(html.substring(noteStart), startsWith('$noteOpenאבג</a>'));
  });

  test('סמן עוגן גלוי באמצע שורה אינו מסיט הערה על מופע חוזר', () {
    final raw = List.filled(30, 'אבג').join(' ');
    final selected = computeAnchorForSelection(
      rawLine: raw,
      selectedText: 'אבג',
      selectionColumnHint: 52,
    )!;
    final markerLink = Link(
      heRef: 'מפרש, א',
      index1: 1,
      path2: 'ספר יעד.txt',
      index2: 3,
      connectionType: 'COMMENTARY',
      anchorStart: 4,
      anchorLabel: 'א',
    );
    final html = render(
      raw,
      notes: [
        _note(
          anchorText: 'אבג',
          anchorPrefix: selected.prefix,
          anchorSuffix: selected.suffix,
          anchorStart: selected.start,
          anchorEnd: selected.end,
        ),
      ],
      links: [_inlineLink(0, 3)],
      transform: (h) => injectLinkAnchorMarkers(
        rawLine: h,
        anchorLinks: [markerLink],
        styleIndexByCommentator: {'ספר יעד.txt': 0},
        lineIndex: 3,
      ),
    );

    final noteStart = html.indexOf(noteOpen);
    expect(html, contains('class="link-anchor link-anchor-0"'));
    expect('אבג'.allMatches(html.substring(0, noteStart)).length, 13);
    expect(html.substring(noteStart), startsWith('$noteOpenאבג</a>'));
    expect(_maxAnchorDepthOfWellFormed(html), 1);
  });

  test('שורה שכבר סומנה אינה מסומנת שוב', () {
    final once = render('אבגד הוזח', notes: [_note()]);
    expect(
      buildAnnotatedLineHtml(
        rawLine: once,
        notesForLine: [_note()],
        lineIndex0: 3,
        underlineColor: color,
      ),
      once,
    );
  });
}
