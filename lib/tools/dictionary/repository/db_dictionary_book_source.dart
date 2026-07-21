import 'package:otzaria/data/data_providers/book_database_resolver.dart';

/// שולף את שורות התוכן של ספר-מילון מבסיס הנתונים לפי כותרת.
///
/// מחזיר רשימה ריקה אם הספר לא קיים או שה-DB אינו זמין — כך פיצ'רים
/// מילוניים פשוט לא מופיעים, בלי שגיאות למשתמש.
Future<List<String>> loadDictionaryBookLines(String title) async {
  try {
    final resolved = await BookDatabaseResolver.resolveBook(title: title);
    if (resolved == null) return const <String>[];
    return await resolved.repository.getLineContents(resolved.book.id);
  } catch (_) {
    return const <String>[];
  }
}
