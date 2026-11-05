import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/find_ref/repository/db_reference_result.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';
import 'package:otzaria/models/book_source.dart';

/// מימוש ייחוס: תחילית לכל רווח בכל כתובת.
List<DbReferenceResult> _previousSuppress(
  List<DbReferenceResult> entries, {
  void Function()? onPrefixProbe,
}) {
  if (entries.length < 2) return entries;
  final groups = <(int, BookSource, bool, bool), Map<String, bool>>{};
  for (final e in entries) {
    final refs = groups[(e.bookId, e.source, e.isAltToc, e.isPdf)] ??= {};
    refs[e.reference] = (refs[e.reference] ?? true) && e.isPartialTocMatch;
  }
  return entries.where((entry) {
    if (entry.isSourceLine) return true;
    final siblings =
        groups[(entry.bookId, entry.source, entry.isAltToc, entry.isPdf)]!;
    final reference = entry.reference;
    for (
      var i = reference.indexOf(' ');
      i >= 0;
      i = reference.indexOf(' ', i + 1)
    ) {
      onPrefixProbe?.call();
      final ancestorIsPartial = siblings[reference.substring(0, i)];
      if (ancestorIsPartial == null) continue;
      if (!ancestorIsPartial || entry.isPartialTocMatch) return false;
    }
    return true;
  }).toList();
}

/// כמו תוצאות "שולחן ערוך א": עשרות ספרים בעלי שם ארוך, ובכל אחד ספר,
/// סימנים וסעיפים.
List<DbReferenceResult> _commentaryResults({int books = 35, int simanim = 75}) {
  final out = <DbReferenceResult>[];
  for (var b = 0; b < books; b++) {
    final title = 'מפרש מספר $b על שולחן ערוך אורח חיים';
    out.add(
      DbReferenceResult(
        title: title,
        reference: title,
        segment: 0,
        bookId: b + 1,
      ),
    );
    for (var s = 0; s < simanim; s++) {
      out.add(
        DbReferenceResult(
          title: title,
          reference: '$title סימן $s',
          segment: s * 10,
          bookId: b + 1,
          tocLevel: 2,
          isPartialTocMatch: s.isOdd,
        ),
      );
      out.add(
        DbReferenceResult(
          title: title,
          reference: '$title סימן $s סעיף א',
          segment: s * 10 + 1,
          bookId: b + 1,
          tocLevel: 3,
        ),
      );
    }
  }
  return out;
}

void main() {
  test('סינון הצאצאים זהה למימוש הקודם', () {
    const user = BookSource.user;
    final cases = <List<DbReferenceResult>>[
      _commentaryResults(books: 4, simanim: 6),
      [
        // "פרק א" אינו חוסם את "פרק אבות", ואב חלקי אינו חוסם צאצא מלא.
        const DbReferenceResult(
          title: 'ספר',
          reference: 'פרק א',
          segment: 1,
          bookId: 1,
        ),
        const DbReferenceResult(
          title: 'ספר',
          reference: 'פרק אבות',
          segment: 2,
          bookId: 1,
        ),
        const DbReferenceResult(
          title: 'ספר',
          reference: 'פרק א משנה ב',
          segment: 3,
          bookId: 1,
        ),
        const DbReferenceResult(
          title: 'ספר',
          reference: 'פרק ב',
          segment: 4,
          bookId: 1,
          isPartialTocMatch: true,
        ),
        const DbReferenceResult(
          title: 'ספר',
          reference: 'פרק ב משנה א',
          segment: 5,
          bookId: 1,
        ),
        const DbReferenceResult(
          title: 'ספר',
          reference: 'פרק ב משנה ב',
          segment: 6,
          bookId: 1,
          isPartialTocMatch: true,
        ),
        // שורת מקור, AltToc, PDF ומקור אחר אינם נחסמים בידי אותה כתובת.
        const DbReferenceResult(
          title: 'ספר',
          reference: 'פרק א משנה ג',
          segment: 7,
          bookId: 1,
          isSourceLine: true,
        ),
        const DbReferenceResult(
          title: 'ספר',
          reference: 'פרק א עליה',
          segment: 8,
          bookId: 1,
          isAltToc: true,
        ),
        const DbReferenceResult(
          title: 'ספר',
          reference: 'פרק א דף',
          segment: 9,
          bookId: 1,
          isPdf: true,
        ),
        const DbReferenceResult(
          title: 'ספר',
          reference: 'פרק א סוף',
          segment: 10,
          bookId: 1,
          source: user,
        ),
        const DbReferenceResult(
          title: 'ספר',
          reference: 'פרק א',
          segment: 11,
          bookId: 1,
          source: user,
        ),
        // אותה כתובת פעמיים, פעם חלקית ופעם מלאה.
        const DbReferenceResult(
          title: 'אחר',
          reference: 'סימן ג',
          segment: 1,
          bookId: 2,
          isPartialTocMatch: true,
        ),
        const DbReferenceResult(
          title: 'אחר',
          reference: 'סימן ג',
          segment: 2,
          bookId: 2,
        ),
        const DbReferenceResult(
          title: 'אחר',
          reference: 'סימן ג סעיף א',
          segment: 3,
          bookId: 2,
        ),
        const DbReferenceResult(
          title: 'אחר',
          reference: 'א',
          segment: 4,
          bookId: 2,
        ),
        const DbReferenceResult(
          title: 'אחר',
          reference: 'א ב',
          segment: 5,
          bookId: 2,
        ),
        const DbReferenceResult(
          title: 'אחר',
          reference: ' ',
          segment: 6,
          bookId: 2,
        ),
        const DbReferenceResult(
          title: 'אחר',
          reference: '',
          segment: 7,
          bookId: 2,
        ),
      ],
      [
        for (var n = 1; n <= 30; n++)
          DbReferenceResult(
            title: 'שרשרת',
            reference: [for (var i = 0; i < n; i++) 'מילה$i'].join(' '),
            segment: n,
            bookId: 3,
            isPartialTocMatch: n % 3 == 0,
          ),
      ],
      [
        for (var i = 0; i < 50; i++)
          DbReferenceResult(
            title: 'ספר $i',
            reference: 'ספר $i',
            segment: 0,
            bookId: i,
          ),
      ],
    ];
    for (final entries in cases) {
      expect(
        FindRefRepository.suppressDeeperVariants(entries),
        orderedEquals(_previousSuppress(entries)),
      );
    }
  });

  test('סינון הצאצאים אינו בונה תחילית לכל רווח בשם הספר', () {
    final entries = _commentaryResults();
    var previous = 0;
    var current = 0;
    final expected = _previousSuppress(
      entries,
      onPrefixProbe: () => previous++,
    );
    final actual = FindRefRepository.suppressDeeperVariants(
      entries,
      debugOnPrefixProbe: () => current++,
    );
    expect(actual, orderedEquals(expected));
    expect(current, greaterThan(0));
    expect(
      current * 2,
      lessThan(previous),
      reason: 'בדיקות תחילית: previous=$previous current=$current',
    );
  });
}
