import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/models/library_book_selection.dart';
import 'package:otzaria/models/books.dart';

Book _book(String title) => TextBook(title: title);

void main() {
  late LibraryBookSelection selection;
  late List<Book> visible;
  var notifications = 0;

  setUp(() {
    selection = LibraryBookSelection()..addListener(() => notifications++);
    notifications = 0;
    visible = [
      for (final t in ['א', 'ב', 'ג', 'ד', 'ה']) _book(t),
    ];
  });

  tearDown(() => selection.dispose());

  test('toggle מוסיף ומסיר, והסדר הוא סדר הצירוף', () {
    selection
      ..toggle(visible[3])
      ..toggle(visible[1])
      ..toggle(visible[2]);
    expect(selection.books, [visible[3], visible[1], visible[2]]);

    selection.toggle(visible[1]);
    expect(selection.books, [visible[3], visible[2]]);
    expect(selection.contains(visible[1]), isFalse);
  });

  test('ספר חיצוני אינו נבחר', () {
    final external = ExternalLibraryBook(
      title: 'חיצוני',
      link: 'https://example.com',
      id: 1,
    );
    selection.toggle(external);
    selection.selectRange(external, [external]);
    expect(selection.isEmpty, isTrue);
    expect(notifications, 0);
  });

  test('selectRange מוסיף את הטווח לפי סדר התצוגה, בשני הכיוונים', () {
    selection.toggle(visible[1]);
    selection.selectRange(visible[3], visible);
    expect(selection.books, [visible[1], visible[2], visible[3]]);

    selection
      ..clear()
      ..toggle(visible[3])
      ..selectRange(visible[1], visible);
    expect(selection.books, [visible[3], visible[1], visible[2]]);
  });

  test('selectRange בלי עוגן, או כשהעוגן מחוץ לרשימה, בוחר רק את הספר', () {
    selection.selectRange(visible[2], visible);
    expect(selection.books, [visible[2]]);

    final elsewhere = _book('אחר');
    selection
      ..clear()
      ..toggle(elsewhere)
      ..selectRange(visible[4], visible);
    expect(selection.books, [elsewhere, visible[4]]);
  });

  test('selectRange חוזר על עצמו בלי כפילויות', () {
    selection.toggle(visible[0]);
    selection.selectRange(visible[2], visible);
    selection.selectRange(visible[2], visible);
    expect(selection.length, 3);
  });

  test('reconcile מחליף מופעים ישנים בחדשים ומסיר ספר שנעלם, בסדר המקורי', () {
    selection
      ..toggle(visible[2])
      ..toggle(visible[0])
      ..toggle(visible[1]);
    notifications = 0;

    final rebuilt = {
      visible[2]: _book('ג חדש'),
      visible[1]: _book('ב חדש'),
    };
    // visible[0] נמחק מהספרייה.
    selection.reconcile((book) => rebuilt[book]);

    expect(selection.books, [rebuilt[visible[2]], rebuilt[visible[1]]]);
    expect(notifications, 1);
  });

  test('reconcile בלי שינוי לא מודיע, והעוגן עובר למופע החדש', () {
    selection.toggle(visible[1]);
    notifications = 0;
    selection.reconcile((book) => book);
    expect(notifications, 0);

    final rebuilt = _book('ב חדש');
    selection.reconcile((_) => rebuilt);
    selection.selectRange(visible[3], [rebuilt, visible[2], visible[3]]);
    expect(selection.books, [rebuilt, visible[2], visible[3]]);
  });

  test('clear מאפס, ושוב על בחירה ריקה לא מודיע', () {
    selection.toggle(visible[0]);
    selection.clear();
    expect(selection.isEmpty, isTrue);
    final count = notifications;
    selection.clear();
    expect(notifications, count);
  });
}
