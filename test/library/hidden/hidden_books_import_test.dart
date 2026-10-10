import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/hidden/hidden_books_import.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';

Library _library() {
  final tora = Category(
    title: 'תורה',
    description: '',
    shortDescription: '',
    order: 1,
    subCategories: [],
    books: [
      TextBook(title: 'בראשית', categoryId: 10),
      TextBook(title: 'שמות', categoryId: 10),
      TextBook(title: 'שו"ת רעק"א', categoryId: 10),
      TextBook(title: 'משנה תורה, הלכות שבת', categoryId: 10),
    ],
    parent: null,
  );
  final library = Library(categories: [tora]);
  tora.parent = library;
  return library;
}

String _key(String title) =>
    PerBookSettings.bookKey(TextBook(title: title, categoryId: 10));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('CSV — שם בכל שורה (issue #1448)', () {
    final result = parseHiddenBooksImport('בראשית\nשמות\n', _library());

    expect(result.matchedBookKeys, {_key('בראשית'), _key('שמות')});
    expect(result.unmatchedNames, isEmpty);
    expect(result.totalNames, 2);
  });

  test('CSV — נלקחת העמודה הראשונה, גרשיים יורדים (issue #1448)', () {
    final result = parseHiddenBooksImport(
      'שם,מחבר\n"בראשית",משה\n',
      _library(),
    );

    expect(result.matchedBookKeys, {_key('בראשית')});
    expect(
      result.unmatchedNames,
      ['שם'],
      reason: 'שורת כותרת שאינה ספר מדווחת ולא נבלעת',
    );
  });

  test('JSON — מערך מחרוזות (issue #1448)', () {
    final result = parseHiddenBooksImport('["שמות"]', _library());

    expect(result.matchedBookKeys, {_key('שמות')});
  });

  test('JSON — אובייקט עם המפתח books (issue #1448)', () {
    final result = parseHiddenBooksImport(
      '{"books": ["בראשית", "שמות"]}',
      _library(),
    );

    expect(result.matchedBookKeys, hasLength(2));
  });

  test('מזהה פנימי מתקבל כמות שהוא (issue #1448)', () {
    final result = parseHiddenBooksImport(_key('שמות'), _library());

    expect(result.matchedBookKeys, {_key('שמות')});
    expect(result.unmatchedNames, isEmpty);
  });

  test('קובץ מעורב — מזהה ושם יחד (issue #1448)', () {
    final result = parseHiddenBooksImport(
      '${_key('שמות')}\nבראשית\n',
      _library(),
    );

    expect(result.matchedBookKeys, {_key('שמות'), _key('בראשית')});
  });

  test('שם שאינו בספרייה מדווח ואינו מסתיר דבר (issue #1448)', () {
    final result = parseHiddenBooksImport('בראשית\nאין כזה ספר\n', _library());

    expect(result.matchedBookKeys, {_key('בראשית')});
    expect(result.unmatchedNames, ['אין כזה ספר']);
    expect(result.totalNames, 2);
  });

  test('כפילויות ושורות ריקות מנוקות (issue #1448)', () {
    final result = parseHiddenBooksImport(
      '\n בראשית \n\nבראשית\n',
      _library(),
    );

    expect(result.totalNames, 1);
    expect(result.matchedBookKeys, {_key('בראשית')});
  });

  test('קובץ ריק אינו מסתיר דבר (issue #1448)', () {
    expect(parseHiddenBooksImport('   ', _library()).isEmpty, isTrue);
  });

  test('JSON פגום נקרא כטקסט ולא מפיל (issue #1448)', () {
    final result = parseHiddenBooksImport('[בראשית', _library());

    expect(result.unmatchedNames, ['[בראשית']);
  });

  test('CSV — גרשיים כפולים בשדה מצוטט מתפענחים לגרשיים (#2242)', () {
    final result = parseHiddenBooksImport('"שו""ת רעק""א"\n', _library());

    expect(result.matchedBookKeys, {_key('שו"ת רעק"א')});
    expect(result.unmatchedNames, isEmpty);
  });

  test('CSV — פסיק בתוך שדה מצוטט אינו מפצל את השם (#2242)', () {
    final result = parseHiddenBooksImport(
      '"משנה תורה, הלכות שבת",רמב"ם\n',
      _library(),
    );

    expect(result.matchedBookKeys, {_key('משנה תורה, הלכות שבת')});
    expect(result.unmatchedNames, isEmpty);
  });

  test('שם לא מצוטט עם גרשיים נשאר כמות שהוא (#2242)', () {
    final result = parseHiddenBooksImport('שו"ת רעק"א\n', _library());

    expect(result.matchedBookKeys, {_key('שו"ת רעק"א')});
  });
}
