import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/utils/note_location_ref.dart';

PersonalNote _note({required int? lineNumber}) => PersonalNote(
      id: 'n',
      bookId: 'בבא קמא',
      lineNumber: lineNumber,
      lastKnownLineNumber: null,
      status: lineNumber == null
          ? PersonalNoteStatus.missing
          : PersonalNoteStatus.located,
      content: '',
      contentPlain: '',
      contentFormat: PersonalNoteContentFormat.plain,
      createdAt: DateTime(2025, 1, 1),
      updatedAt: DateTime(2025, 1, 1),
    );

void main() {
  // עץ TOC: דף נ -> ע"א (שורה 5), ע"ב (שורה 9).
  final toc = [
    TocEntry(text: 'דף נ', index: 4, level: 1)
      ..children.addAll([
        TocEntry(text: 'ע"א', index: 5, level: 2),
        TocEntry(text: 'ע"ב', index: 9, level: 2),
      ]),
  ];

  group('personalNoteLocationRef - טקסט', () {
    test('בונה כתובת מלאה עם שם הספר מתוך ה-TOC', () {
      final ref = personalNoteLocationRef(
        _note(lineNumber: 6), // index 5 -> ע"א
        isPdf: false,
        bookTitle: 'בבא קמא',
        tableOfContents: toc,
      );
      expect(ref, 'בבא קמא, דף נ, ע"א');
    });

    test('מתקדם לכותרת הנכונה לפי השורה', () {
      final ref = personalNoteLocationRef(
        _note(lineNumber: 10), // index 9 -> ע"ב
        isPdf: false,
        bookTitle: 'בבא קמא',
        tableOfContents: toc,
      );
      expect(ref, 'בבא קמא, דף נ, ע"ב');
    });

    test('מחזיר null כשאין TOC טעון', () {
      final ref = personalNoteLocationRef(
        _note(lineNumber: 6),
        isPdf: false,
        bookTitle: 'בבא קמא',
        tableOfContents: null,
      );
      expect(ref, isNull);
    });

    test('מחזיר null להערה ללא מיקום', () {
      final ref = personalNoteLocationRef(
        _note(lineNumber: null),
        isPdf: false,
        bookTitle: 'בבא קמא',
        tableOfContents: toc,
      );
      expect(ref, isNull);
    });

    test('includeBookTitle=false משמיט את שם הספר', () {
      final ref = personalNoteLocationRef(
        _note(lineNumber: 6), // index 5 -> ע"א
        isPdf: false,
        bookTitle: 'בבא קמא',
        tableOfContents: toc,
        includeBookTitle: false,
      );
      expect(ref, 'דף נ, ע"א');
    });
  });

  group('personalNoteLocationRef - PDF', () {
    test('מחזיר null כשה-outline עדיין לא נטען', () {
      final ref = personalNoteLocationRef(
        _note(lineNumber: 3),
        isPdf: true,
        bookTitle: 'בבא קמא',
        pdfOutline: null,
      );
      expect(ref, isNull);
    });
  });
}
