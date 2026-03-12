// lib/tools/gematria/models/search_result.dart
//
// מודל תוצאת חיפוש — מייצג שורה אחת שנמצאה בחיפוש גימטריה.
// הוצא מ-gematria_search.dart לקובץ עצמאי לפי עקרון SRP.

class SearchResult {
  final String file;
  final int line;
  final String text;
  final String path; // הנתיב ההיררכי (כותרות)
  final String verseNumber; // מספר הפסוק
  final String contextBefore; // מילים לפני התוצאה
  final String contextAfter; // מילים אחרי התוצאה

  const SearchResult({
    required this.file,
    required this.line,
    required this.text,
    this.path = '',
    this.verseNumber = '',
    this.contextBefore = '',
    this.contextAfter = '',
  });
}
