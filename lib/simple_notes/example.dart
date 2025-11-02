/// דוגמאות שימוש במערכת הערות פשוטה
///
/// קובץ זה מכיל דוגמאות לשימוש במערכת ההערות החדשה.

import 'package:otzaria/simple_notes/simple_notes.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';

/// דוגמה 1: יצירת הערה חדשה
Future<void> exampleCreateNote() async {
  final repository = SimpleNotesRepository.instance;

  final note = await repository.createNote(
    bookTitle: 'בראשית',
    lineNumber: 1,
    lineText: 'בראשית ברא אלהים את השמים ואת הארץ',
    content: 'זוהי הערה על הפסוק הראשון בתורה',
  );

  print('נוצרה הערה: ${note.id}');
}

/// דוגמה 2: קבלת כל ההערות לספר
Future<void> exampleGetNotes() async {
  final repository = SimpleNotesRepository.instance;

  // כל ההערות
  final allNotes = await repository.getNotesForBook('בראשית');
  print('סה"כ הערות: ${allNotes.length}');

  // רק הערות עם מיקום
  final locatedNotes = await repository.getLocatedNotes('בראשית');
  print('הערות עם מיקום: ${locatedNotes.length}');

  // רק הערות ללא מיקום
  final locationlessNotes = await repository.getLocationlessNotes('בראשית');
  print('הערות ללא מיקום: ${locationlessNotes.length}');
}

/// דוגמה 3: עדכון הערה
Future<void> exampleUpdateNote() async {
  final repository = SimpleNotesRepository.instance;

  // קבלת הערה
  final notes = await repository.getNotesForBook('בראשית');
  if (notes.isEmpty) return;

  final note = notes.first;

  // עדכון התוכן
  final updatedNote = note.copyWith(
    content: 'תוכן מעודכן להערה',
    updatedAt: DateTime.now(),
  );

  await repository.updateNote(updatedNote);
  print('הערה עודכנה: ${updatedNote.id}');
}

/// דוגמה 4: מחיקת הערה
Future<void> exampleDeleteNote() async {
  final repository = SimpleNotesRepository.instance;

  // קבלת הערה
  final notes = await repository.getNotesForBook('בראשית');
  if (notes.isEmpty) return;

  final note = notes.first;

  // מחיקה
  await repository.deleteNote(note.id, note.bookTitle);
  print('הערה נמחקה: ${note.id}');
}

/// דוגמה 5: אימות מיקום הערות
Future<void> exampleVerifyLocations() async {
  final repository = SimpleNotesRepository.instance;
  final fileSystemData = FileSystemData.instance;

  // קבלת טקסט הספר
  final bookText = await fileSystemData.getBookText('בראשית');

  // אימות מיקום
  final result = await repository.verifyNoteLocations(
    bookTitle: 'בראשית',
    bookText: bookText,
  );

  print('תוצאות אימות:');
  print('  סה"כ הערות: ${result.totalNotes}');
  print('  הערות תקינות: ${result.anchoredNotes}');
  print('  הערות שהוזזו: ${result.shiftedNotes}');
  print('  הערות ללא מיקום: ${result.locationlessNotes}');
}

/// דוגמה 6: מיקום מחדש של הערה
Future<void> exampleRelocateNote() async {
  final repository = SimpleNotesRepository.instance;

  // קבלת הערה ללא מיקום
  final locationlessNotes = await repository.getLocationlessNotes('בראשית');
  if (locationlessNotes.isEmpty) return;

  final note = locationlessNotes.first;

  // מיקום מחדש לשורה 5
  final relocatedNote = await repository.relocateNote(
    noteId: note.id,
    bookTitle: note.bookTitle,
    newLineNumber: 5,
    newLineText: 'טקסט השורה החדשה',
  );

  print(
      'הערה מוקמה מחדש: ${relocatedNote.id} -> שורה ${relocatedNote.lineNumber}');
}

/// דוגמה 7: המרת הערות ישנות (הוסר)
///
/// MigrationService הוסר כי הוא תלוי במערכת הישנה שנמחקה.
/// משתמשים קיימים יצטרכו לייצא הערות לפני העדכון.
Future<void> exampleMigrateOldNotes() async {
  print('המרת הערות ישנות - לא זמין יותר');
  print('MigrationService הוסר כי המערכת הישנה נמחקה');
}

/// דוגמה 8: שימוש בספק הנתונים ישירות
Future<void> exampleDirectFileAccess() async {
  final provider = FileSystemNotesProvider.instance;

  // קריאת קובץ הערות
  final notesLines = await provider.readNotesFile('בראשית');
  print('מספר שורות בקובץ: ${notesLines.length}');

  // קריאת קובץ מיפוי
  final mappings = await provider.readMappingFile('בראשית');
  print('מספר מיפויים: ${mappings.length}');

  // Escape/Unescape
  final content = 'הערה עם | ו-\nירידת שורה';
  final escaped = provider.escapeNoteContent(content);
  final unescaped = provider.unescapeNoteContent(escaped);
  print('מקורי: $content');
  print('Escaped: $escaped');
  print('Unescaped: $unescaped');
}

/// הרצת כל הדוגמאות
Future<void> runAllExamples() async {
  print('=== דוגמאות שימוש במערכת הערות פשוטה ===\n');

  try {
    print('1. יצירת הערה חדשה');
    await exampleCreateNote();
    print('');

    print('2. קבלת הערות');
    await exampleGetNotes();
    print('');

    print('3. עדכון הערה');
    await exampleUpdateNote();
    print('');

    print('4. מחיקת הערה');
    await exampleDeleteNote();
    print('');

    print('5. אימות מיקום');
    await exampleVerifyLocations();
    print('');

    print('6. מיקום מחדש');
    await exampleRelocateNote();
    print('');

    print('7. המרת הערות ישנות');
    await exampleMigrateOldNotes();
    print('');

    print('8. גישה ישירה לקבצים');
    await exampleDirectFileAccess();
    print('');

    print('=== כל הדוגמאות הושלמו בהצלחה ===');
  } catch (e) {
    print('שגיאה: $e');
  }
}
