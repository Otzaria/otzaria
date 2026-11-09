import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/models/books.dart';

/// כותרת המיקום בתוך הספר — חותך את שם הספר מ-ref.
/// fallback: "תחילת הספר" (index 0), "עמוד X" (PDF), "פסקה X" (טקסט).
String bookmarkLocationSubtitle(Bookmark item) {
  final ref = item.ref;
  final bookTitle = item.book.title;

  String location;
  if (ref == bookTitle) {
    location = '';
  } else if (ref.startsWith('$bookTitle, ')) {
    location = ref.substring('$bookTitle, '.length);
  } else if (ref.startsWith('$bookTitle ')) {
    location = ref.substring('$bookTitle '.length);
  } else {
    location = ref;
  }

  if (location.isEmpty) {
    if (item.index == 0) return 'תחילת הספר';
    if (item.book is PdfBook) return 'עמוד ${item.index}';
    return 'פסקה ${item.index}';
  }
  return location;
}
