import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/text_book/utils/note_inline_render.dart';

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

void main() {
  const color = Color(0xFF1A2B3C);

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
    final link = Link(
      heRef: 'יעד',
      index1: 1,
      path2: 'ספר יעד.txt',
      index2: 3,
      connectionType: 'commentary',
      start: 5,
      end: 9,
    );
    final html = buildAnnotatedLineHtml(
      rawLine: raw,
      notesForLine: [_note()],
      lineIndex0: 0,
      underlineColor: color,
      inlineLinks: [link],
    );
    // הקישור נשמר שלם.
    expect(html.contains('otzaria://inline-link'), isTrue);
    expect(html.contains('>הוזח</a>'), isTrue);
    // וגם סימוני ההערה קיימים סביבו (לפני ואחרי).
    expect(html.contains('otzaria://note?line=0'), isTrue);
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
}
