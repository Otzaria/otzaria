import 'package:otzaria/utils/file/document_format.dart';

/// כשלי המרת מסמך. טיפוסים נבדלים — כדי שהקורא יוכל להבחין בין "פורמט לא
/// נתמך" (אין מה לנסות) לבין "קובץ פגום" (ראוי לדווח למשתמש) בלי לנתח
/// מחרוזות שגיאה.
sealed class DocumentConversionException implements Exception {
  /// נתיב הקובץ שנכשל, לצורך תיעוד ולוג.
  final String? path;

  /// הפורמט שזוהה בפועל (לא בהכרח זה שהסיומת הצהירה עליו).
  final DocumentFormat? format;

  /// החריגה המקורית שגרמה לכשל, אם הייתה.
  final Object? cause;

  const DocumentConversionException({this.path, this.format, this.cause});

  String get _label;

  @override
  String toString() {
    final buffer = StringBuffer(_label);
    if (format != null) buffer.write(' [${format!.extension}]');
    if (path != null) buffer.write(': $path');
    if (cause != null) buffer.write(' — $cause');
    return buffer.toString();
  }
}

/// אין ממיר לפורמט הזה. **לעולם אין ליפול מכאן לקריאת הקובץ כטקסט** — קריאת
/// ZIP או OLE כטקסט מייצרת ג'יבריש שנראה כמו ספר תקין.
class UnsupportedDocumentFormatException extends DocumentConversionException {
  const UnsupportedDocumentFormatException({
    super.path,
    super.format,
    super.cause,
  });

  @override
  String get _label => 'פורמט מסמך שאינו נתמך';
}

/// המכולה נקראה אך מבנה המסמך שבור (ZIP פגום, XML חסר, זרם בינארי קטוע).
class CorruptedDocumentException extends DocumentConversionException {
  const CorruptedDocumentException({super.path, super.format, super.cause});

  @override
  String get _label => 'קובץ המסמך פגום';
}

/// המסמך מוצפן/מוגן בסיסמה ואין אפשרות לקרוא את תוכנו.
class EncryptedDocumentException extends DocumentConversionException {
  const EncryptedDocumentException({super.path, super.format, super.cause});

  @override
  String get _label => 'המסמך מוצפן';
}
